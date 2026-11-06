--[[
	Mana regen sparks: mana-colored = 2s regen tick / Cata-MoP combat pulse, white = FSR.
	Standalone module — no calls into SwingTickGlow / PowerTickGlow.
	Uses db.manaTickGlow only; shared plumbing comes from WhoaUF.Timing.

	Client gating (docs/timing/mana-regen.md §1):
	  Era / TBC  regen tick + FSR
	  Wrath      FSR only — 3.0.2 made mana regen continuous
	  Cata / MoP in-combat 5s mana pulse (5% base + Meditation) — not a 2s tick
	The Era/TBC tick must never be driven from UNIT_POWER_UPDATE, whose 2s
	throttle fabricates a tick on clients that no longer have one.

	Frame safety: never call RefreshAlternateManaBar, LayoutPlayerBottomFrames,
	or LayoutPlayerCombatGlow from this file. Boot deferred to PLAYER_ENTERING_WORLD;
	form/power changes use a deferred refresh only.
]]

local WhoaUF = WhoaUF
local Timing = WhoaUF.Timing

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local RAGE = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1
local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

local SUPPORTED = Timing.hasRegenTick or Timing.hasFiveSecondRule or Timing.hasCombatManaPulse
local DRIVER_KEY = "manaTick"

-- A tick cannot arrive this soon after the previous one on a 2s grid, so an
-- in-band gain that does is a buff/proc collision, not a tick.
local MIN_TICK_INTERVAL = 1.2
-- How close to a predicted boundary a small gain must land to be trusted.
local ON_PHASE = 0.3
-- Cast completion and the matching mana decrease arrive in either order.
local SPEND_MATCH_WINDOW = 0.6
-- Power changes this soon after a form/power-type swap are bookkeeping, not ticks.
local RESEED_GRACE = 0.4
-- TBC UNIT_AURA can spam; coalesce clock resets.
local AURA_RESET_THROTTLE = 0.5

-- Staleness is deliberately longer than one five-second rule: during the rule the
-- grid keeps ticking but grants no spirit mana, so no gains arrive to confirm it.
-- Dropping the anchor there would make the spark vanish for the whole window.
local GRID_STALE_AFTER = 8
-- Combat pulse free-runs without discrete arrivals; keep the anchor alive.
local PULSE_STALE_AFTER = 30

-- Rank-1 ids → localized names. "Drink" is a generic consumable buff name.
local RAPID_REGEN_NAMES = Timing.SpellNameSet({ 29166, 12051 }) -- Innervate, Evocation
RAPID_REGEN_NAMES["Drink"] = true

local state = {
	grid = Timing:NewGrid(Timing.REGEN_PERIOD, nil, GRID_STALE_AFTER),
	pulseGrid = Timing:NewGrid(Timing.COMBAT_MANA_PULSE, nil, PULSE_STALE_AFTER),
	pulseActive = false,
}

local watcher
local watcherRegistered
local moduleReady
local refreshPending
local refreshDepth = 0

local function GetMode()
	return Timing.NormalizeMode(WhoaUF.db and WhoaUF.db.manaTickGlow)
end

local function IsDruidMeleeForm()
	if Timing.PlayerClass() ~= "DRUID" then
		return false
	end
	local powerType = UnitPowerType("player")
	return powerType == RAGE or powerType == ENERGY
end

local function IsManaPowerBar(bar)
	if not bar then
		return false
	end
	if bar.powerToken == "MANA" or bar.powerType == MANA then
		return true
	end
	if bar.powerToken == nil and bar.powerType == nil then
		return UnitPowerType(bar.unit or "player") == MANA
	end
	return false
end

--- Cat/bear/travel and Mistweaver keep the mana pool on the alternate bar.
--- AlternateManaBar is Wrath+; on Era/TBC forms host the spark on the visible
--- power bar while still reading UnitPower(..., MANA) for the hidden pool.
local function ResolveManaBar(frame)
	if not frame or frame.kind ~= "player" then
		return nil
	end
	local altShown = WhoaUF.IsAlternateManaBarShown and WhoaUF:IsAlternateManaBarShown()
	if IsDruidMeleeForm() then
		if altShown then
			return frame.AlternateManaBar
		end
		if (Timing.hasRegenTick or Timing.hasFiveSecondRule) and frame.Power then
			return frame.Power
		end
		return nil
	end
	if altShown then
		return frame.AlternateManaBar
	end
	local power = frame.Power
	if power and IsManaPowerBar(power) then
		return power
	end
	return nil
end

local function HasManaHeadroom()
	local max = UnitPowerMax("player", MANA) or 0
	if max <= 0 then
		return false
	end
	return (UnitPower("player", MANA) or 0) < max
end

local function InFiveSecondRule()
	return state.fsrEnd ~= nil
end

local function UseLatencyOffset()
	return WhoaUF.db and WhoaUF.db.manaTickLatency and Timing.hasRegenTick
end

--- Display clock: optional world-latency lead for weave timing (default off).
--- Observe still uses raw arrival time so "when will my bar move" stays correct
--- when the option is off. Docs: docs/timing/mana-regen.md §5.6
local function DisplayNow(now)
	now = now or GetTime()
	if UseLatencyOffset() then
		return now + Timing:WorldLatency()
	end
	return now
end

local function BuffNameAt(index)
	if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
		local data = C_UnitAuras.GetBuffDataByIndex("player", index)
		return data and data.name
	end
	if UnitBuff then
		return UnitBuff("player", index)
	end
	return nil
end

local function HasRapidRegenAura()
	for i = 1, 40 do
		local name = BuffNameAt(i)
		if not name then
			break
		end
		if RAPID_REGEN_NAMES[name] then
			return true
		end
	end
	return false
end

--- Prefer GetManaRegen when it returns a usable rate; else the EMA baseline.
--- GetManaRegen is unreliable on Classic (ignores gear mp5 / some buffs) but
--- still beats accepting the first random buff pulse as the band seed.
local function ExpectedTickSize()
	if GetManaRegen then
		local base, casting = GetManaRegen()
		local rate = InFiveSecondRule() and casting or base
		if (not rate or rate <= 0) then
			rate = (base and base > 0 and base) or (casting and casting > 0 and casting) or nil
		end
		if rate and rate > 0 then
			local expected = rate * Timing.REGEN_PERIOD
			if expected >= 1 then
				return expected
			end
		end
	end
	return state.tickBaseline
end

---------------------------------------------------------------------------
-- Sparks — only create textures for mechanics this client actually has
---------------------------------------------------------------------------

local function EnsureSparks(host, bar)
	-- Era/TBC 2s tick and Cata/MoP combat pulse share the blue regen spark;
	-- those clients never overlap.
	if (Timing.hasRegenTick or Timing.hasCombatManaPulse) and not host.RegenSpark then
		host.RegenSpark = Timing:CreateSpark(host, bar, Timing.LANE.regen)
	end
	if Timing.hasFiveSecondRule and not host.FsrSpark then
		host.FsrSpark = Timing:CreateSpark(host, bar, Timing.LANE.fsr)
	end
end

local function HideSparks(host)
	if not host then
		return
	end
	if host.RegenSpark then
		host.RegenSpark:Hide()
	end
	if host.FsrSpark then
		host.FsrSpark:Hide()
	end
end

local function EnsureHost(frame)
	local bar = ResolveManaBar(frame)
	if not bar then
		return nil, nil
	end
	local host = bar.ManaTickHost
	if not host then
		host = CreateFrame("Frame", nil, frame)
		host:EnableMouse(false)
		host.bar = bar
		EnsureSparks(host, bar)
		bar.ManaTickHost = host
	end
	host.bar = bar
	return bar, host
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------

local Render
local OnManaValueChanged

local function StartRender()
	if not moduleReady then
		return
	end
	Timing:AddSpark(DRIVER_KEY, Render)
end

local function StopRender()
	Timing:RemoveSpark(DRIVER_KEY)
end

--- TBC 2.2: any regen-rate change restarts the per-player tick clock.
local function ResetTickClock()
	if not Timing.hasRegenTick then
		return
	end
	state.grid:Reset()
	-- Tick size changes with mp5/gear/buffs; drop the EMA so the next real tick
	-- re-seeds rather than rejecting against a stale baseline.
	state.tickBaseline = nil
end

--- Cata: blue 5s spark while in combat with missing mana. MoP: 1s spark (faster regen).
--- Full mana clears it until the next spend (or combat re-entry below full).
local function StopCombatPulse()
	if not Timing.hasCombatManaPulse then
		return
	end
	state.pulseActive = false
	state.pulseGrid:Reset()
end

local function StartCombatPulse(now)
	if not Timing.hasCombatManaPulse then
		return
	end
	if not UnitAffectingCombat("player") or not HasManaHeadroom() then
		return
	end
	now = now or GetTime()
	-- Anchor combat pulse once per below-full stint — re-Observing every spend
	-- reset the spark on each cast; free-run until full mana or leave combat.
	if not state.pulseActive then
		state.pulseGrid:Reset()
		state.pulseGrid:Observe(now)
		state.pulseActive = true
	end
	StartRender()
end

--- Advance the grid on real time, then optionally lead the drawn position by
--- world latency without a second mutating Progress call.
local function SparkProgress(grid, now, ignoreStale, drawNow)
	local p = grid:Progress(now, ignoreStale)
	if not p then
		return nil
	end
	if not drawNow or drawNow == now then
		return p
	end
	local period = grid.period
	if not period or period <= 0 then
		return p
	end
	local shifted = p + (drawNow - now) / period
	return shifted - math.floor(shifted)
end

Render = function(now)
	local frame = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	local bar = frame and ResolveManaBar(frame)
	local host = bar and bar.ManaTickHost
	if not host then
		return false
	end
	if not Timing:BarReady(frame, bar) or not Timing.ModeAllows(GetMode(), frame) then
		HideSparks(host)
		return false
	end

	local showFsr = false
	if state.fsrEnd then
		if now >= state.fsrEnd and not state.channeling then
			-- Predicted end can land ~1s before the first spirit tick. Hold the
			-- white spark until mana actually moves (or +2s), so the glow does
			-- not "arrive" before the bar refills.
			local base = (state.fsrStart or now) + Timing.FIVE_SECOND_RULE
			local tickAfter = state.grid.lastObserved and state.grid.lastObserved >= base - 0.05
			if Timing.hasRegenTick and not tickAfter and now < base + Timing.REGEN_PERIOD then
				showFsr = true
			else
				state.fsrEnd = nil
				state.fsrStart = nil
				-- TBC 2.2: leaving the rule is a regen-rate change. Re-anchor so the
				-- blue spark counts the fresh ~2s until the first full-rate refill
				-- instead of sitting dark until that tick is classified.
				if Timing.tickClockResets then
					ResetTickClock()
					state.grid:Observe(now)
				elseif Timing.hasRegenTick and not tickAfter then
					-- Timed out with no post-rule tick yet — wait for one before blue.
					state.hideBlueUntilTick = true
				end
			end
		else
			showFsr = true
		end
	end

	-- Poll after FSR expiry so a same-frame tick sees the leave-boundary reset.
	-- Include combat-pulse clients so full-mana clears the spark without waiting
	-- on UNIT_POWER_* alone.
	if Timing.hasRegenTick or Timing.hasFiveSecondRule or Timing.hasCombatManaPulse then
		OnManaValueChanged(now)
	end

	if host.FsrSpark then
		if showFsr then
			local span = state.fsrEnd and state.fsrStart and (state.fsrEnd - state.fsrStart) or Timing.FIVE_SECOND_RULE
			local start = state.fsrStart or (now - Timing.FIVE_SECOND_RULE)
			-- While holding past predicted end, pin the spark at the right edge.
			local prog = span > 0 and (now - start) / span or 1
			if prog > 1 then
				prog = 1
			end
			Timing:PositionSpark(host.FsrSpark, bar, prog)
			host.FsrSpark:Show()
		else
			host.FsrSpark:Hide()
		end
	end

	-- Blue spark: Era/TBC 2s tick, or Cata 5s / MoP 1s combat pulse (missing mana only).
	local showRegen = false
	local capped = not HasManaHeadroom()
	if host.RegenSpark then
		local progress
		local drawNow = DisplayNow(now)
		if Timing.hasCombatManaPulse then
			if state.pulseActive then
				if not UnitAffectingCombat("player") or capped then
					StopCombatPulse()
				else
					progress = SparkProgress(state.pulseGrid, now, true, drawNow)
				end
			end
		elseif Timing.hasRegenTick then
			-- Keep the watchdog alive at full mana / during FSR (ignoreStale), but
			-- never draw the blue spark while full, in FSR, or waiting on the
			-- first post-rule tick — that was the "keeps going at full" / early
			-- arrival after a cast.
			local inFsr = InFiveSecondRule() or showFsr
			local ignoreStale = capped or inFsr or state.hideBlueUntilTick
			local p = SparkProgress(state.grid, now, ignoreStale, drawNow)
			if showFsr or capped or state.hideBlueUntilTick then
				progress = nil
			else
				progress = p
			end
		end
		if progress then
			Timing:PositionSpark(host.RegenSpark, bar, progress)
			host.RegenSpark:Show()
			showRegen = true
		else
			host.RegenSpark:Hide()
		end
	end

	-- At full mana with nothing else to show, drop the driver (pulse already stopped).
	if capped and not showFsr and not showRegen then
		if Timing.hasCombatManaPulse then
			StopCombatPulse()
		end
		HideSparks(host)
		return false
	end

	if not showFsr and not showRegen then
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Five-second rule
---------------------------------------------------------------------------

local function FiveSecondEnd(spentAt)
	local base = spentAt + Timing.FIVE_SECOND_RULE
	-- Era: the grid is indifferent to the rule, so spirit regen resumes on the
	-- first boundary at or after t+5 — the real wait is 5-7s, not 5s.
	if Timing.isEra then
		local boundary = state.grid:NextBoundary(base)
		if boundary then
			return boundary
		end
		-- Grid not locked yet: plain t+5 ends the white spark before the first
		-- possible tick (up to +2s). Use the worst-case 7s bound so the glow
		-- does not clear a second before mana starts moving.
		return base + Timing.REGEN_PERIOD
	end
	-- TBC / Wrath: plain 5s countdown. TBC's first full-rate tick arrives ~2s
	-- after expiry because leaving the rule resets the clock — Render re-anchors
	-- the blue spark at leave so it lands with that refill.
	return base
end

local function StartFiveSecondRule(spentAt)
	if not Timing.hasFiveSecondRule then
		return
	end
	-- TBC 2.2: entering the rule is itself a regen-rate change.
	if Timing.tickClockResets then
		ResetTickClock()
	end
	state.fsrStart = spentAt
	state.fsrEnd = FiveSecondEnd(spentAt)
	StartRender()
end

local function ArmFiveSecondRule(spentAt)
	if state.fsrArmedAt == spentAt then
		return
	end
	state.fsrArmedAt = spentAt
	StartFiveSecondRule(spentAt)
end

--- Cast completion and the mana decrease can arrive in either order, so pair
--- them rather than trusting one alone. A cast that spent nothing (Clearcasting,
--- Inner Focus, 0-cost spells) never gets a partner and never arms the rule.
local function TryStartFiveSecondRule()
	if not Timing.hasFiveSecondRule then
		return
	end
	local castAt, spentAt = state.lastCastAt, state.lastSpendAt
	if not castAt or not spentAt then
		return
	end
	if math.abs(castAt - spentAt) > SPEND_MATCH_WINDOW then
		return
	end
	ArmFiveSecondRule(spentAt)
end

--- Mana drains (burn, diseases) spend without a cast. After the cast-match
--- window, arm from the spend alone if nothing paired.
local function ScheduleDrainFiveSecondRule(spentAt)
	if not Timing.hasFiveSecondRule or not C_Timer or not C_Timer.After then
		return
	end
	C_Timer.After(SPEND_MATCH_WINDOW, function()
		if state.fsrArmedAt == spentAt or state.lastSpendAt ~= spentAt then
			return
		end
		local castAt = state.lastCastAt
		if castAt and math.abs(castAt - spentAt) <= SPEND_MATCH_WINDOW then
			return
		end
		ArmFiveSecondRule(spentAt)
	end)
end

---------------------------------------------------------------------------
-- Tick classification (Era / TBC only)
---------------------------------------------------------------------------

--- Only mana the server actually granted proves a tick happened, and only some
--- gains are ticks. MP5 from gear, Blessing of Wisdom, Mana Spring and potions
--- all arrive on their own clocks. Band against GetManaRegen when sane, else
--- the EMA baseline. Docs: docs/timing/mana-regen.md §5.2
local function ClassifyGain(now, delta, cur, max)
	if not Timing.hasRegenTick then
		return
	end
	-- TBC: the tick clock is dead for the whole FSR window. Meditation partials
	-- must not re-lock mid-rule; the leave-boundary reset + next full tick do.
	if Timing.tickClockResets and InFiveSecondRule() then
		return
	end

	local grid = state.grid
	local since = grid:SinceObserved(now)
	if since and since < MIN_TICK_INTERVAL then
		return
	end

	local clipped = max > 0 and cur >= max
	local band = ExpectedTickSize()
	local baseline = state.tickBaseline
	-- TBC pro-rates mid-cycle; Meditation inside the FSR (Era) yields partials.
	local minRatio = Timing.tickClockResets and 0.5 or 0.6
	if InFiveSecondRule() then
		minRatio = minRatio * 0.7
	end

	local outsized = band ~= nil and delta > band * 3
	-- Drink / Innervate / Evocation may re-anchor; other outsized gains (BoW,
	-- Mana Spring pulses) must not lock the grid onto a foreign clock.
	if outsized and not HasRapidRegenAura() then
		return
	end

	local accept
	if not band then
		accept = true
	elseif delta >= band * minRatio then
		accept = true
	elseif clipped then
		-- Truncated final tick: real, and it carries real phase.
		accept = true
	else
		local progress = grid:Progress(now)
		accept = progress ~= nil and (progress < ON_PHASE or progress > 1 - ON_PHASE)
	end
	if not accept then
		return
	end

	grid:Observe(now)
	state.hideBlueUntilTick = nil
	if not clipped and not outsized then
		state.tickBaseline = baseline and (baseline * 0.7 + delta * 0.3) or delta
	end
	StartRender()
end

local function ReseedMana(now, grace)
	state.lastMana = UnitPower("player", MANA) or 0
	if grace then
		state.ignoreUntil = (now or GetTime()) + RESEED_GRACE
	end
end

OnManaValueChanged = function(now)
	local cur = UnitPower("player", MANA) or 0
	local prev = state.lastMana
	local max = UnitPowerMax("player", MANA) or 0
	state.lastMana = cur
	if prev == nil or cur == prev then
		return
	end

	if cur < prev then
		state.lastSpendAt = now
		TryStartFiveSecondRule()
		ScheduleDrainFiveSecondRule(now)
		-- Cata/MoP: spending mana (re)arms the combat pulse while below full.
		StartCombatPulse(now)
		return
	end

	-- Full mana: drop the combat pulse until the next spend.
	if Timing.hasCombatManaPulse and max > 0 and cur >= max then
		StopCombatPulse()
		return
	end

	-- Wrath+: continuous regen produces frequent small gains. Never treat them
	-- as Era/TBC ticks — the discrete 2s grid does not exist past 3.0.2.
	-- Cata/MoP combat pulse stays free-running from spend/combat enter; observing
	-- every continuous gain would pin the spark at zero.
	if not Timing.hasRegenTick then
		return
	end
	if state.ignoreUntil and now < state.ignoreUntil then
		return
	end
	ClassifyGain(now, cur - prev, cur, max)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function RequestRefresh()
	if not moduleReady or refreshPending then
		return
	end
	refreshPending = true
	Timing.DeferRefresh(function()
		refreshPending = false
		WhoaUF:RefreshManaTickGlow()
	end)
end

local function IsManaPowerToken(powerType)
	if powerType == "MANA" then
		return true
	end
	if type(powerType) == "number" then
		return powerType == MANA
	end
	return false
end

local function OnWatcherEvent(_, event, unit, arg2)
	local now = GetTime()

	if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
		if unit == "player" and IsManaPowerToken(arg2) then
			OnManaValueChanged(now)
		end
		return
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if unit == "player" then
			state.lastCastAt = now
			TryStartFiveSecondRule()
		end
		return
	end

	if event == "UNIT_SPELLCAST_CHANNEL_START" then
		if unit == "player" then
			state.channeling = true
			StartFiveSecondRule(now)
		end
		return
	end

	if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if unit == "player" then
			state.channeling = false
			-- The rule holds for at least the channel duration: Mind Flay (3s)
			-- ends at start+5, Tranquility (10s) ends when the channel does.
			if state.fsrEnd and now > state.fsrEnd then
				state.fsrEnd = now
			end
		end
		return
	end

	if event == "UNIT_MAXPOWER" then
		if unit == "player" then
			ReseedMana(now, false)
		end
		return
	end

	if event == "PLAYER_EQUIPMENT_CHANGED" then
		ReseedMana(now, false)
		-- TBC 2.2: gear mp5 swaps restart the tick clock.
		if Timing.tickClockResets then
			ResetTickClock()
		end
		return
	end

	if event == "PLAYER_DAMAGE_DONE_MODS" then
		-- Fires when power regeneration changes (BoW, Mana Spring, etc.).
		if Timing.tickClockResets then
			ResetTickClock()
		end
		return
	end

	if event == "UNIT_AURA" then
		-- TBC 2.2: aura mp5/spirit swaps (BoW, Mana Spring, Innervate) reset the
		-- per-player clock. Throttled — UNIT_AURA is noisy.
		if unit == "player" and Timing.tickClockResets then
			if not state.auraResetAt or (now - state.auraResetAt) >= AURA_RESET_THROTTLE then
				state.auraResetAt = now
				ResetTickClock()
			end
		end
		return
	end

	if event == "UNIT_DISPLAYPOWER" then
		if unit == "player" then
			ReseedMana(now, true)
			RequestRefresh()
		end
		return
	end

	if event == "UPDATE_SHAPESHIFT_FORM" then
		-- Druid form changes that cost mana start the five-second rule. Pairing
		-- with SPELLCAST_SUCCEEDED is unreliable for shapeshift, so arm directly
		-- from a confirmed mana drop before reseed wipes the delta.
		if Timing.hasFiveSecondRule then
			local cur = UnitPower("player", MANA) or 0
			local prev = state.lastMana
			if prev ~= nil and cur < prev then
				StartFiveSecondRule(now)
			end
		end
		ReseedMana(now, true)
		RequestRefresh()
		return
	end

	if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" or event == "PLAYER_ENTERING_WORLD" then
		state.grid:Reset()
		StopCombatPulse()
		state.fsrStart = nil
		state.fsrEnd = nil
		state.channeling = false
		state.tickBaseline = nil
		state.lastCastAt = nil
		state.lastSpendAt = nil
		state.fsrArmedAt = nil
		state.auraResetAt = nil
		state.hideBlueUntilTick = nil
		ReseedMana(now, true)
		RequestRefresh()
		return
	end

	if event == "PLAYER_REGEN_DISABLED" then
		-- Enter combat below full mana → start the 5s pulse.
		StartCombatPulse(now)
		RequestRefresh()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" then
		StopCombatPulse()
		RequestRefresh()
	end
end

local function UnregisterWatcher()
	if not watcher or not watcherRegistered then
		return
	end
	watcher:UnregisterAllEvents()
	watcherRegistered = false
	state.lastMana = nil
	StopRender()
end

local function RegisterWatcher()
	if watcherRegistered or not SUPPORTED or not moduleReady or GetMode() == "off" then
		return
	end
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnEvent", OnWatcherEvent)
	end
	watcherRegistered = true
	ReseedMana(GetTime(), true)

	-- UNIT_POWER_FREQUENT keeps lastMana fresh on continuous (Wrath) regen so
	-- spend pairing for the FSR is accurate. Tick classification is gated inside
	-- OnManaValueChanged / ClassifyGain and never runs without hasRegenTick.
	-- UNIT_POWER_UPDATE stays registered because it is guaranteed on
	-- spell-caused changes and at full power.
	watcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	watcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	watcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	watcher:RegisterEvent("PLAYER_ALIVE")
	watcher:RegisterEvent("PLAYER_UNGHOST")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	if Timing.tickClockResets then
		watcher:RegisterEvent("PLAYER_DAMAGE_DONE_MODS")
		watcher:RegisterUnitEvent("UNIT_AURA", "player")
	end
	if Timing.hasFiveSecondRule then
		watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
	end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function WhoaUF:SyncManaTickGlowLayout(frame)
	if not SUPPORTED or not frame or frame.kind ~= "player" then
		return
	end
	local bar = ResolveManaBar(frame)
	local host = bar and bar.ManaTickHost
	if not host then
		return
	end
	Timing:AnchorHost(host, frame, bar)
	EnsureSparks(host, bar)
	if host.RegenSpark then
		Timing:ApplySparkVisual(host.RegenSpark, bar, Timing.LANE.regen)
	end
	if host.FsrSpark then
		Timing:ApplySparkVisual(host.FsrSpark, bar, Timing.LANE.fsr)
	end
end

function WhoaUF:InitManaTickGlowModule()
	if not SUPPORTED or GetMode() == "off" then
		UnregisterWatcher()
		moduleReady = false
		return
	end
	if not (self.unitFrames and self.unitFrames.player) then
		return
	end
	moduleReady = true
	RegisterWatcher()
end

local function StopHost(bar)
	local host = bar and bar.ManaTickHost
	if not host then
		return
	end
	HideSparks(host)
end

local function RefreshBody(frame)
	frame = frame or (WhoaUF.unitFrames and WhoaUF.unitFrames.player)
	if not frame then
		return
	end
	if not SUPPORTED or GetMode() == "off" then
		UnregisterWatcher()
		moduleReady = false
		StopHost(frame.Power)
		StopHost(frame.AlternateManaBar)
		return
	end
	if not moduleReady then
		return
	end
	RegisterWatcher()

	local bar = ResolveManaBar(frame)
	if not bar then
		StopHost(frame.Power)
		StopHost(frame.AlternateManaBar)
		StopRender()
		return
	end
	-- Druid form swaps move the mana host between Power and AlternateManaBar —
	-- hide the idle bar's spark host so only one draws.
	StopHost((bar == frame.Power) and frame.AlternateManaBar or frame.Power)

	local _, host = EnsureHost(frame)
	if not host then
		return
	end
	WhoaUF:SyncManaTickGlowLayout(frame)

	if state.fsrEnd
		or (Timing.hasRegenTick and state.grid:IsLocked())
		or (Timing.hasCombatManaPulse and state.pulseActive)
	then
		StartRender()
	elseif Timing.hasCombatManaPulse and UnitAffectingCombat("player") and HasManaHeadroom() then
		StartCombatPulse(GetTime())
	end
end

function WhoaUF:RefreshManaTickGlow(frame)
	if refreshDepth > 0 then
		return
	end
	refreshDepth = refreshDepth + 1
	RefreshBody(frame)
	refreshDepth = refreshDepth - 1
end

function WhoaUF:StopManaTickGlow(bar)
	StopHost(bar)
end

WhoaUF.NormalizeManaTickGlowMode = Timing.NormalizeMode

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------

if SUPPORTED then
	local boot = CreateFrame("Frame")
	boot:RegisterEvent("PLAYER_ENTERING_WORLD")
	boot:SetScript("OnEvent", function(self)
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		Timing.DeferRefresh(function()
			if GetMode() == "off" then
				return
			end
			if not (WhoaUF.unitFrames and WhoaUF.unitFrames.player) then
				return
			end
			WhoaUF:InitManaTickGlowModule()
			WhoaUF:RefreshManaTickGlow()
		end)
	end)
end
