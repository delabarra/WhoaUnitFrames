--[[
	Swing timer sparks on the player power bar: main hand, off hand and ranged,
	each an independent clock with its own spark and lane.
	Standalone module — no calls into ManaTickGlow / PowerTickGlow.
	Uses db.swingTickGlow only; shared plumbing comes from WhoaUF.Timing.

	The swing clock lives entirely on the server and no API exposes it, so
	everything here is reconstruction from combat-log arrivals and is therefore
	systematically late by downstream latency. Main hand and off hand are two
	genuinely independent server clocks and are modelled as such.
	Docs: docs/timing/swing-timer.md

	Known gaps, deliberate (see docs §3.2, §10.4):
	  - Instant spells that reset the swing on Era/TBC/Wrath are not modelled.
	    The real mechanism is the spell's interruptFlags, which is unreadable on
	    these clients, and a spell-ID whitelist has a long exception list
	    (bombs, Volley, Hurricane, Evocation, Steady Shot, drums). Only completed
	    hard casts reset here.
	  - Feign Death resets at cast success rather than polling the cooldown for
	    the server-apply moment.

	Frame safety: never call RefreshAlternateManaBar, LayoutPlayerBottomFrames,
	or LayoutPlayerCombatGlow from this file.
]]

local WhoaUF = WhoaUF
local Timing = WhoaUF.Timing

local DRIVER_KEY = "swingTick"
local COMBAT_LOG_KEY = "swingTick"

-- SPELL_EXTRA_ATTACKS and the swing it triggers are timestamped separately;
-- WeakAuras relaxed an exact match to this tolerance for that reason.
local EXTRA_ATTACK_WINDOW = 0.04
-- A form change fires UNIT_ATTACK_SPEED with the new speed, but the swing was
-- reset outright rather than rescaled.
local FORM_CHANGE_WINDOW = 0.5
-- Base ids only; matching on the localized name covers every rank without
-- enumerating ~40 rank ids.
local ON_NEXT_SWING_IDS = { 78, 845, 6807, 2973 } -- Heroic Strike, Cleave, Maul, Raptor Strike
local SLAM_ID = 1464
local FEIGN_DEATH_ID = 5384
-- Auto Shot, Shoot, Throw, Shoot Wand. Aimed/Multi/Steady also log RANGE_*;
-- the ranged clock must only advance on auto-repeat attacks.
local AUTO_REPEAT_SPELLS = { [75] = true, [3018] = true, [2764] = true, [5019] = true }

local hands = {
	main = { sparkKey = "MainSpark", lane = Timing.LANE.swingMain },
	off = { sparkKey = "OffSpark", lane = Timing.LANE.swingOff },
	ranged = { sparkKey = "RangedSpark", lane = Timing.LANE.swingRanged },
}

local state = {
	skipCount = 0,
}

local watcher
local watcherRegistered
local moduleReady
local refreshPending
local refreshDepth = 0
local onNextSwingNames
local slamName
local autoRepeatNames

--- Auto-repeat attacks (Auto Shot, Shoot, Throw, Shoot Wand). Quartz anchors the
--- hunter clock on UNIT_SPELLCAST_SUCCEEDED because CLEU RANGE_* arrives later.
local function IsAutoRepeatCast(spellId)
	if not spellId then
		return false
	end
	if AUTO_REPEAT_SPELLS[spellId] then
		return true
	end
	if not autoRepeatNames or not next(autoRepeatNames) then
		autoRepeatNames = Timing.SpellNameSet({ 75, 3018, 2764, 5019 })
	end
	local name = Timing.SpellName(spellId)
	return name ~= nil and autoRepeatNames[name] == true
end

-- Mainline / Forever: no addon COMBAT_LOG_EVENT_UNFILTERED, and attack-speed
-- APIs return secret numbers in combat, so no clock can be built.
local function GetMode()
	if not Timing.cleuAllowed then
		return "off"
	end
	return Timing.NormalizeMode(WhoaUF.db and WhoaUF.db.swingTickGlow)
end

---------------------------------------------------------------------------
-- Speeds
---------------------------------------------------------------------------

--- Main-hand and off-hand speed in seconds, haste already included.
--- A nil/0 off-hand speed is the standard dual-wield test.
local function MeleeSpeeds()
	local mh, oh = UnitAttackSpeed("player")
	if not (mh and mh > 0) then
		mh = nil
	end
	if not (oh and oh > 0) then
		oh = nil
	end
	return mh, oh
end

--- UnitRangedDamage returns speed first, in seconds. No correction multiplier.
local function RangedSpeed()
	if not UnitRangedDamage then
		return nil
	end
	local speed = UnitRangedDamage("player")
	if type(speed) == "number" and speed > 0 then
		return speed
	end
	return nil
end

---------------------------------------------------------------------------
-- Clocks
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

local function StopHand(hand)
	hand.active = false
	hand.startTime = nil
	hand.endTime = nil
end

local function StartHand(hand, at, speed, duration)
	if not speed or speed <= 0 then
		return
	end
	hand.speed = speed
	hand.startTime = at
	hand.endTime = at + (duration or speed)
	hand.active = true
	StartRender()
end

local function StartRangedClock(now)
	StartHand(hands.ranged, now, RangedSpeed())
end

--- Proportional rescale: the completed fraction is preserved and the end time
--- moves. Each hand uses its OWN old speed (dividing the new off-hand speed by
--- the old main-hand speed is a live WeakAuras bug).
local function RescaleHand(hand, now, newSpeed)
	if not newSpeed or newSpeed <= 0 then
		return
	end
	local oldSpeed = hand.speed
	if not hand.active or not hand.startTime or not hand.endTime or not oldSpeed or oldSpeed <= 0 then
		hand.speed = newSpeed
		return
	end
	local duration = hand.endTime - hand.startTime
	if duration <= 0 then
		hand.speed = newSpeed
		return
	end
	local elapsed = now - hand.startTime
	local fraction = elapsed / duration
	if fraction < 0 then
		fraction = 0
	end
	local remaining = (duration - elapsed) * (newSpeed / oldSpeed)
	hand.speed = newSpeed
	if remaining <= 0 or fraction >= 1 then
		hand.endTime = now + (remaining > 0 and remaining or 0)
		hand.startTime = hand.endTime - newSpeed
		return
	end
	-- Keep the rendered fraction where it is and let the remainder run at the
	-- new rate, rather than letting the spark jump when speed changes.
	local newDuration = remaining / (1 - fraction)
	hand.startTime = now - fraction * newDuration
	hand.endTime = hand.startTime + newDuration
end

--- When a unit parries an incoming attack, that unit's own next swing is
--- hastened — so this only ever fires for swings aimed at the player.
--- Flat 0.40 x weapon speed with a 0.20 x floor, worked entirely in
--- remaining-time space. Comparing an absolute expiration against a relative
--- floor is LibClassicSwingTimerAPI #53; `duration * 0.6` is Quartz's error.
--- Docs: docs/timing/swing-timer.md §4.2
local function ApplyParryHaste()
	local hand = hands.main
	if not hand.active or not hand.endTime or not hand.speed then
		return
	end
	local remaining = hand.endTime - GetTime()
	local floorTime = 0.20 * hand.speed
	if remaining <= floorTime then
		return
	end
	local offset = 0.40 * hand.speed
	if remaining - offset < floorTime then
		offset = remaining - floorTime
	end
	hand.endTime = hand.endTime - offset
	StartRender()
end

--- Slam suspends the swing from Wrath onward (on Era/TBC it resets instead,
--- which the completed-hard-cast path already covers).
local function PauseMelee(now)
	if state.pausedAt then
		return
	end
	state.pausedAt = now
end

local function ResumeMelee(now)
	local pausedAt = state.pausedAt
	state.pausedAt = nil
	if not pausedAt then
		return
	end
	local shift = now - pausedAt
	if shift <= 0 then
		return
	end
	if hands.main.active then
		hands.main.startTime = hands.main.startTime + shift
		hands.main.endTime = hands.main.endTime + shift
	end
	if hands.off.active then
		hands.off.startTime = hands.off.startTime + shift
		hands.off.endTime = hands.off.endTime + shift
	end
end

local function ResetMeleeClocks(now)
	-- Only reset hands that already have an observed swing. isAttacking alone means
	-- auto-attack is toggled on, not that a swing has landed — starting here on pull
	-- (common with /startattack macros) draws a timer before the first hit.
	if not (hands.main.active or hands.off.active) then
		return
	end
	local mh, oh = MeleeSpeeds()
	if hands.main.active then
		StartHand(hands.main, now, mh)
	end
	if hands.off.active then
		if oh then
			StartHand(hands.off, now, oh)
		else
			StopHand(hands.off)
		end
	end
end

---------------------------------------------------------------------------
-- Sparks
---------------------------------------------------------------------------

local function EnsureSparks(host, bar)
	for _, hand in pairs(hands) do
		if not host[hand.sparkKey] then
			host[hand.sparkKey] = Timing:CreateSpark(host, bar, hand.lane)
		end
	end
end

local function HideSparks(host)
	if not host then
		return
	end
	for _, hand in pairs(hands) do
		local spark = host[hand.sparkKey]
		if spark then
			spark:Hide()
		end
	end
end

local function EnsureHost(frame)
	if not frame or frame.kind ~= "player" or not frame.Power then
		return nil, nil
	end
	local bar = frame.Power
	local host = bar.SwingTickHost
	if not host then
		host = CreateFrame("Frame", nil, frame)
		host:EnableMouse(false)
		host.bar = bar
		EnsureSparks(host, bar)
		bar.SwingTickHost = host
		frame.SwingTickHost = host
	end
	host.bar = bar
	return bar, host
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------

local function DrawHand(host, bar, hand, now)
	local spark = host[hand.sparkKey]
	if not spark then
		return false
	end
	if not hand.active or not hand.startTime or not hand.endTime then
		spark:Hide()
		return false
	end
	local span = hand.endTime - hand.startTime
	local progress = (span > 0) and ((now - hand.startTime) / span) or 1
	-- Hide as soon as the swing clock expires. Holding at the edge while
	-- auto-attack / autorepeat stayed on left the glow stuck when the next
	-- SWING_* was delayed or withheld (out of range, dead target).
	if progress >= 1 then
		StopHand(hand)
		spark:Hide()
		return false
	end
	-- Stock spark texture, no vertex tint (lane.noColor).
	Timing:TintSpark(spark, bar, hand.lane)
	Timing:PositionSpark(spark, bar, progress, hand.lane)
	spark:Show()
	return true
end

Render = function(now)
	local frame = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	local bar = frame and frame.Power
	local host = bar and bar.SwingTickHost
	if not host then
		return false
	end
	if not Timing:BarReady(frame, bar) or not Timing.ModeAllows(GetMode(), frame) then
		HideSparks(host)
		return false
	end

	-- Melee freezes while a suspending cast is in flight.
	local meleeNow = state.pausedAt or now
	local drewMain = DrawHand(host, bar, hands.main, meleeNow)
	local drewOff = DrawHand(host, bar, hands.off, meleeNow)
	local drewRanged = DrawHand(host, bar, hands.ranged, now)

	if not drewMain and not drewOff and not drewRanged then
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Combat log
---------------------------------------------------------------------------

local function IsOnNextSwing(spellId)
	if not Timing.hasOnNextSwing or not spellId then
		return false
	end
	if not onNextSwingNames or not next(onNextSwingNames) then
		onNextSwingNames = Timing.SpellNameSet(ON_NEXT_SWING_IDS)
	end
	local name = Timing.SpellName(spellId)
	return name ~= nil and onNextSwingNames[name] == true
end

--- Slam has a spell id per rank, so match on the localized name.
local function IsSlam(spellId)
	if not spellId then
		return false
	end
	if not slamName then
		slamName = Timing.SpellName(SLAM_ID)
		if not slamName then
			return false
		end
	end
	return Timing.SpellName(spellId) == slamName
end

local function HandleSwing(timestamp, isOffHand)
	local now = GetTime()
	local mh, oh = MeleeSpeeds()

	-- Extra attacks (Windfury, Sword Specialization, Hand of Justice) have not
	-- reset the swing clock since patch 1.4, but they emit swing events that look
	-- identical to real ones. Suppression is main-hand only, and the comparison
	-- uses the combat-log timestamp, which is a different clock from GetTime().
	if not isOffHand and state.skipAt and state.skipCount > 0
		and (timestamp - state.skipAt) < EXTRA_ATTACK_WINDOW then
		state.skipCount = state.skipCount - 1
		return
	end

	-- The flag is reliable on all five clients, so it is trusted rather than
	-- guessed at — but it cannot mean off-hand with nothing in the off hand.
	if isOffHand and not oh then
		isOffHand = false
	end

	if isOffHand then
		state.firstOffSwing = true
		StartHand(hands.off, now, oh)
	else
		StartHand(hands.main, now, mh)
	end
end

-- Payload slots, per docs/timing/swing-timer.md §8:
--   SWING_DAMAGE       12 amount ... 21 isOffHand
--   SWING_MISSED       12 missType, 13 isOffHand
--   RANGE_*            12 spellId
--   SPELL_EXTRA_ATTACKS 15 amount
local function OnCombatLog(timestamp, subevent, sourceGUID, destGUID,
	p12, p13, p14, p15, p16, p17, p18, p19, p20, p21)
	local playerGUID = state.playerGUID
	if not playerGUID then
		return
	end

	if sourceGUID == playerGUID then
		if subevent == "SPELL_EXTRA_ATTACKS" then
			state.skipAt = timestamp
			state.skipCount = tonumber(p15) or 0
			return
		end
		if subevent == "SWING_DAMAGE" then
			-- isOffHand is arg 21 here and arg 13 on SWING_MISSED; test truthiness,
			-- because main-hand swings report false or omit it depending on client.
			HandleSwing(timestamp, p21 and true or false)
			return
		end
		if subevent == "SWING_MISSED" then
			HandleSwing(timestamp, p13 and true or false)
			return
		end
		if subevent == "RANGE_DAMAGE" or subevent == "RANGE_MISSED" then
			local spellId = tonumber(p12)
			-- Ranged CLEU without spellId: fall back here; UNIT_SPELLCAST_SUCCEEDED anchors first.
			if IsAutoRepeatCast(spellId) then
				StartRangedClock(GetTime())
			end
			return
		end
		return
	end

	if destGUID == playerGUID and subevent == "SWING_MISSED" and p12 == "PARRY" then
		ApplyParryHaste()
	end
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
		WhoaUF:RefreshSwingTickGlow()
	end)
end

local function OnAttackSpeedChanged(now)
	local mh, oh = MeleeSpeeds()
	local skipRescale = false
	if state.formChangeAt and (now - state.formChangeAt) < FORM_CHANGE_WINDOW then
		skipRescale = true
	elseif Timing.isEra and state.class == "PALADIN" then
		-- Seal of the Crusader snapshots in both directions and is the only
		-- dynamic speed change an Era paladin has.
		skipRescale = true
	end
	if skipRescale then
		hands.main.speed = mh or hands.main.speed
		hands.off.speed = oh or hands.off.speed
		return
	end
	RescaleHand(hands.main, now, mh)
	RescaleHand(hands.off, now, oh)
end

local function OnSpellcastSucceeded(now, spellId)
	local wasCasting = state.casting
	state.casting = false

	if spellId == FEIGN_DEATH_ID then
		ResetMeleeClocks(now)
		StopHand(hands.ranged)
		return
	end

	if state.pausedAt then
		ResumeMelee(now)
		return
	end

	-- On-next-swing abilities consume the main-hand swing and emit SPELL_DAMAGE
	-- instead of SWING_DAMAGE, so without this the bar sits dead at zero.
	if IsOnNextSwing(spellId) then
		local mh = MeleeSpeeds()
		StartHand(hands.main, now, mh)
		return
	end

	-- Auto Shot / Shoot / Throw / Shoot Wand: anchor when the cast succeeds on the
	-- client, not on combat enter or START_AUTOREPEAT (Quartz Swing.lua).
	if IsAutoRepeatCast(spellId) then
		StartRangedClock(now)
		return
	end

	if Timing.castResetsSwing and wasCasting then
		ResetMeleeClocks(now)
	end
end

local function OnWatcherEvent(_, event, arg1, arg2, arg3)
	local now = GetTime()

	if event == "UNIT_ATTACK_SPEED" then
		if arg1 == "player" then
			OnAttackSpeedChanged(now)
		end
		return
	end

	if event == "UNIT_RANGEDDAMAGE" then
		if arg1 == "player" and hands.ranged.active then
			RescaleHand(hands.ranged, now, RangedSpeed())
		end
		return
	end

	if event == "PLAYER_ENTER_COMBAT" then
		-- Melee auto-attack toggled ON (not combat state). Do not speculate a
		-- clock here — wait for SWING_* and run full UnitAttackSpeed from there.
		state.isAttacking = true
		return
	end

	if event == "PLAYER_LEAVE_COMBAT" then
		state.isAttacking = false
		state.firstOffSwing = false
		return
	end

	if event == "START_AUTOREPEAT_SPELL" then
		-- Record autorepeat on — do not start a clock here. Speculative first-shot
		-- timers desync vs CLEU RANGE_* at full UnitRangedDamage.
		state.isAutoRepeating = true
		return
	end

	if event == "STOP_AUTOREPEAT_SPELL" then
		state.isAutoRepeating = false
		StopHand(hands.ranged)
		return
	end

	if event == "UNIT_SPELLCAST_START" then
		if arg1 ~= "player" then
			return
		end
		state.casting = true
		-- Slam suspends the swing from Wrath onward; on Era/TBC it resets instead,
		-- which the completed-hard-cast path already covers.
		if Timing.apiLevel >= 3 and IsSlam(arg3) then
			PauseMelee(now)
		end
		return
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if arg1 == "player" then
			OnSpellcastSucceeded(now, arg3)
		end
		return
	end

	if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
		or event == "UNIT_SPELLCAST_FAILED" then
		if arg1 == "player" then
			state.casting = false
			ResumeMelee(now)
		end
		return
	end

	if event == "UNIT_SPELLCAST_CHANNEL_START" then
		-- A channel is a cast: on Era/TBC/Wrath starting one resets the swing.
		if arg1 == "player" and Timing.castResetsSwing then
			ResetMeleeClocks(now)
		end
		return
	end

	if event == "UPDATE_SHAPESHIFT_FORM" then
		state.formChangeAt = now
		if state.class == "DRUID" then
			-- A form change resets the swing and changes attack speed.
			StopHand(hands.main)
			StopHand(hands.off)
			state.firstOffSwing = false
		end
		RequestRefresh()
		return
	end

	if event == "PLAYER_EQUIPMENT_CHANGED" then
		-- arg1 is the inventory slot: 16 main hand, 17 off hand, 18 ranged.
		if arg1 == 16 or arg1 == 17 then
			local mh, oh = MeleeSpeeds()
			if hands.main.active then
				StartHand(hands.main, now, mh)
			end
			if arg1 == 17 then
				if oh then
					StartHand(hands.off, now, oh)
				else
					StopHand(hands.off)
				end
			end
		elseif arg1 == 18 and Timing.hasRangedSlot then
			if hands.ranged.active then
				StartHand(hands.ranged, now, RangedSpeed())
			end
		end
		return
	end

	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		state.playerGUID = UnitGUID("player")
		state.class = Timing.PlayerClass()
		StopHand(hands.main)
		StopHand(hands.off)
		StopHand(hands.ranged)
		state.isAttacking = false
		state.isAutoRepeating = false
		state.firstOffSwing = false
		state.pausedAt = nil
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
	Timing:UnsubscribeCombatLog(COMBAT_LOG_KEY)
	StopHand(hands.main)
	StopHand(hands.off)
	StopHand(hands.ranged)
	StopRender()
end

local function RegisterWatcher()
	if watcherRegistered or not moduleReady or GetMode() == "off" then
		return
	end
	if not watcher then
		watcher = CreateFrame("Frame")
		watcher:SetScript("OnEvent", OnWatcherEvent)
	end
	watcherRegistered = true
	state.playerGUID = UnitGUID("player")
	state.class = Timing.PlayerClass()

	Timing:SubscribeCombatLog(COMBAT_LOG_KEY, OnCombatLog)

	watcher:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	watcher:RegisterEvent("PLAYER_ENTER_COMBAT")
	watcher:RegisterEvent("PLAYER_LEAVE_COMBAT")
	watcher:RegisterEvent("START_AUTOREPEAT_SPELL")
	watcher:RegisterEvent("STOP_AUTOREPEAT_SPELL")
	watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	watcher:RegisterEvent("PLAYER_ALIVE")
	watcher:RegisterEvent("PLAYER_UNGHOST")
	watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	if Timing.hasRangedSlot then
		watcher:RegisterUnitEvent("UNIT_RANGEDDAMAGE", "player")
	end
	-- Needed on every client: Era/TBC/Wrath for the cast reset, Wrath onward for
	-- the Slam suspend.
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
	watcher:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function WhoaUF:SyncSwingTickGlowLayout(frame)
	if not frame or frame.kind ~= "player" or not frame.Power then
		return
	end
	local bar = frame.Power
	local host = bar.SwingTickHost
	if not host then
		return
	end
	Timing:AnchorHost(host, frame, bar)
	EnsureSparks(host, bar)
	for _, hand in pairs(hands) do
		Timing:ApplySparkVisual(host[hand.sparkKey], bar, hand.lane)
	end
end

function WhoaUF:InitSwingTickGlowModule()
	if GetMode() == "off" then
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
	if not frame or not frame.Power then
		return
	end
	if GetMode() == "off" then
		UnregisterWatcher()
		moduleReady = false
		HideSparks(frame.Power.SwingTickHost)
		return
	end
	if not moduleReady then
		return
	end
	RegisterWatcher()

	local _, host = EnsureHost(frame)
	if not host then
		return
	end
	WhoaUF:SyncSwingTickGlowLayout(frame)

	if hands.main.active or hands.off.active or hands.ranged.active then
		StartRender()
	end
end

function WhoaUF:RefreshSwingTickGlow(frame)
	if refreshDepth > 0 then
		return
	end
	refreshDepth = refreshDepth + 1
	RefreshBody(frame)
	refreshDepth = refreshDepth - 1
end

function WhoaUF:StopSwingTickGlow(bar)
	HideSparks(bar and bar.SwingTickHost)
end

WhoaUF.NormalizeSwingTickGlowMode = Timing.NormalizeMode

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------

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
		WhoaUF:InitSwingTickGlowModule()
		WhoaUF:RefreshSwingTickGlow()
	end)
end)
