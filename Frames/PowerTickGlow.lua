--[[
	Energy regen tick spark on the player power bar (rogues, druid cat form).
	Standalone module — no calls into ManaTickGlow / SwingTickGlow.
	Uses db.powerTickGlow only; shared plumbing comes from WhoaUF.Timing.

	Client gating (docs/timing/energy-focus-regen.md §1): the discrete energy tick
	exists on Era and TBC only. Patch 3.0.2 replaced it with continuous regen at
	1 per decisecond, so Wrath/Cata/MoP have no tick to display — the 2s rhythm
	visible there is only UNIT_POWER_UPDATE's throttle.

	Player focus (Cata/MoP) is continuous and every notable focus gain is an
	instantaneous energize, so focus gets no indicator. Pet focus cadence is unverified — omitted on purpose.

	Frame safety: never call RefreshAlternateManaBar, LayoutPlayerBottomFrames,
	or LayoutPlayerCombatGlow from this file.
]]

local WhoaUF = WhoaUF
local Timing = WhoaUF.Timing

local ENERGY = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3

local SUPPORTED = Timing.hasRegenTick
local DRIVER_KEY = "powerTick"

local MIN_TICK_INTERVAL = 1.2
local RESEED_GRACE = 0.5

-- Energy values are absolute, so fixed tolerance windows work where mana needs a
-- self-calibrating band. 18-22 absorbs the documented 19/21 anomalies; 38-42 is
-- Adrenaline Rush, which doubles the rate and so produces real 40-energy ticks.
local TICK_LOW, TICK_HIGH = 18, 22
local DOUBLE_LOW, DOUBLE_HIGH = 38, 42

local state = {
	grid = Timing:NewGrid(Timing.REGEN_PERIOD),
}

local watcher
local watcherRegistered
local moduleReady
local refreshPending
local refreshDepth = 0

local function GetMode()
	return Timing.NormalizeMode(WhoaUF.db and WhoaUF.db.powerTickGlow)
end

local function IsEnergyBar(bar)
	if not bar then
		return false
	end
	if bar.powerToken == "ENERGY" or bar.powerType == ENERGY then
		return true
	end
	if bar.powerToken == nil and bar.powerType == nil then
		return UnitPowerType(bar.unit or "player") == ENERGY
	end
	return false
end

local function ResolveEnergyBar(frame)
	if not frame or frame.kind ~= "player" then
		return nil
	end
	if UnitPowerType("player") ~= ENERGY then
		return nil
	end
	local power = frame.Power
	if power and IsEnergyBar(power) then
		return power
	end
	return nil
end

---------------------------------------------------------------------------
-- Sparks
---------------------------------------------------------------------------

local function EnsureSparks(host, bar)
	if not host.TickSpark then
		host.TickSpark = Timing:CreateSpark(host, bar, Timing.LANE.energy)
	end
end

local function HideSparks(host)
	if host and host.TickSpark then
		host.TickSpark:Hide()
	end
end

local function EnsureHost(frame)
	local bar = ResolveEnergyBar(frame)
	if not bar then
		return nil, nil
	end
	local host = bar.PowerTickHost
	if not host then
		host = CreateFrame("Frame", nil, frame)
		host:EnableMouse(false)
		host.bar = bar
		EnsureSparks(host, bar)
		bar.PowerTickHost = host
	end
	host.bar = bar
	return bar, host
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------

local Render

local function StartRender()
	if not moduleReady then
		return
	end
	Timing:AddSpark(DRIVER_KEY, Render)
end

local function StopRender()
	Timing:RemoveSpark(DRIVER_KEY)
end

Render = function(now)
	local frame = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	local bar = frame and ResolveEnergyBar(frame)
	local host = bar and bar.PowerTickHost
	if not host then
		return false
	end
	if not Timing:BarReady(frame, bar) or not Timing.ModeAllows(GetMode(), frame) then
		HideSparks(host)
		return false
	end

	-- At the cap no deltas arrive at all, because the server has nothing to send.
	-- The grid keeps running server-side, which is what the watchdog is for, so
	-- absence of evidence must not be read as a bad anchor here.
	local capped = (UnitPower("player", ENERGY) or 0) >= (UnitPowerMax("player", ENERGY) or 0)
	local progress = state.grid:Progress(now, capped)
	if not progress then
		HideSparks(host)
		return false
	end

	Timing:PositionSpark(host.TickSpark, bar, progress)
	host.TickSpark:Show()
	return true
end

---------------------------------------------------------------------------
-- Tick classification
---------------------------------------------------------------------------

local function ClassifyGain(now, delta, cur, max)
	local since = state.grid:SinceObserved(now)
	if since and since < MIN_TICK_INTERVAL then
		-- On a fixed grid a tick cannot arrive this early, so this is Relentless
		-- Strikes / Combat Potency / Focused Attacks colliding with the window.
		return
	end

	local accept = (delta >= TICK_LOW and delta <= TICK_HIGH)
		or (delta >= DOUBLE_LOW and delta <= DOUBLE_HIGH)
	if not accept and max > 0 and cur >= max and delta <= DOUBLE_HIGH then
		-- Clipped final tick: real, and it carries real phase. The upper bound is
		-- what keeps Thistle Tea out at its full 100-energy value (a level-70
		-- Thistle Tea grants ~40 and is indistinguishable from a doubled tick).
		accept = true
	end
	if not accept then
		return
	end

	state.grid:Observe(now)
	StartRender()
end

local function ReseedEnergy(now, grace)
	state.lastEnergy = UnitPower("player", ENERGY) or 0
	if grace then
		state.ignoreUntil = (now or GetTime()) + RESEED_GRACE
	end
end

local function OnEnergyValueChanged(now)
	local cur = UnitPower("player", ENERGY) or 0
	local prev = state.lastEnergy
	state.lastEnergy = cur
	if prev == nil or cur <= prev then
		return
	end
	if state.ignoreUntil and now < state.ignoreUntil then
		-- Shifting into cat form zeroes energy and Furor/Wolfshead hand back
		-- 40-60, which would otherwise read as a doubled tick.
		return
	end
	ClassifyGain(now, cur - prev, cur, UnitPowerMax("player", ENERGY) or 0)
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
		WhoaUF:RefreshPowerTickGlow()
	end)
end

local function IsEnergyToken(powerType)
	if powerType == "ENERGY" then
		return true
	end
	if type(powerType) == "number" then
		return powerType == ENERGY
	end
	return false
end

local function OnWatcherEvent(_, event, unit, arg2)
	local now = GetTime()

	if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" then
		if unit == "player" and IsEnergyToken(arg2) then
			OnEnergyValueChanged(now)
		end
		return
	end

	if event == "UNIT_MAXPOWER" then
		ReseedEnergy(now, false)
		return
	end

	if event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
		-- Cat/bear grid survives shapeshift — keep anchor; ignore Furor/Wolfshead energy in grace window.
		ReseedEnergy(now, true)
		RequestRefresh()
		return
	end

	if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" or event == "PLAYER_ENTERING_WORLD" then
		-- Seed grid on login/reload so spark draws before first classified tick;
		-- next real +20 energy Observe hard-locks phase.
		state.grid:Seed(now)
		ReseedEnergy(now, true)
		RequestRefresh()
		return
	end

	if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		RequestRefresh()
	end
end

local function UnregisterWatcher()
	if not watcher or not watcherRegistered then
		return
	end
	watcher:UnregisterAllEvents()
	watcherRegistered = false
	state.lastEnergy = nil
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
	ReseedEnergy(GetTime(), true)

	watcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	watcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	watcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	watcher:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	watcher:RegisterEvent("PLAYER_ALIVE")
	watcher:RegisterEvent("PLAYER_UNGHOST")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function WhoaUF:SyncPowerTickGlowLayout(frame)
	if not SUPPORTED or not frame or frame.kind ~= "player" then
		return
	end
	local bar = ResolveEnergyBar(frame)
	local host = bar and bar.PowerTickHost
	if not host then
		return
	end
	Timing:AnchorHost(host, frame, bar)
	EnsureSparks(host, bar)
	Timing:ApplySparkVisual(host.TickSpark, bar, Timing.LANE.energy)
end

function WhoaUF:InitPowerTickGlowModule()
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

local function RefreshBody(frame)
	frame = frame or (WhoaUF.unitFrames and WhoaUF.unitFrames.player)
	if not frame then
		return
	end
	if not SUPPORTED or GetMode() == "off" then
		UnregisterWatcher()
		moduleReady = false
		HideSparks(frame.Power and frame.Power.PowerTickHost)
		return
	end
	if not moduleReady then
		return
	end
	RegisterWatcher()

	local bar = ResolveEnergyBar(frame)
	if not bar then
		HideSparks(frame.Power and frame.Power.PowerTickHost)
		StopRender()
		return
	end

	local _, host = EnsureHost(frame)
	if not host then
		return
	end
	WhoaUF:SyncPowerTickGlowLayout(frame)
	-- Show immediately when enabled / after reload. Phase corrects on the first
	-- classified tick; until then Seed keeps a free-running provisional clock.
	if not state.grid:IsLocked() then
		state.grid:Seed(GetTime())
	end
	StartRender()
end

function WhoaUF:RefreshPowerTickGlow(frame)
	if refreshDepth > 0 then
		return
	end
	refreshDepth = refreshDepth + 1
	RefreshBody(frame)
	refreshDepth = refreshDepth - 1
end

function WhoaUF:StopPowerTickGlow(bar)
	HideSparks(bar and bar.PowerTickHost)
end

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
			WhoaUF:InitPowerTickGlowModule()
			WhoaUF:RefreshPowerTickGlow()
		end)
	end)
end
