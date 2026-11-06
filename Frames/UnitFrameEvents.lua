--[[
	Unit frame event watcher. Mirrors Blizzard PlayerFrame/TargetFrame event contracts.
	Hot UNIT_* events dispatch aspect updaters (health/power/identity/…); full
	UpdateUnitFrame stays on unit swap / PEW / Apply / faction rebuilds.
	Reference: reference/Blizzard_UnitFrame/Classic/PlayerFrame.lua, TargetFrame.lua
]]

local UF = WhoaUF._UF
local frames = UF.frames

local function IsPlayerFrameEventUnit(unit)
	return unit == "player" or unit == "vehicle"
end

local function FrameForUnit(unit)
	if unit == "player" or unit == "vehicle" then
		return frames.player
	elseif unit == "target" then
		return frames.target
	elseif unit == "focus" then
		return frames.focus
	elseif unit == "targettarget" then
		return frames.tot
	elseif unit == "focustarget" then
		return frames.focustot
	elseif frames.pet and unit == frames.pet.unit then
		return frames.pet
	end
end

local function UpdatePetIfUnit(unit)
	if frames.pet and unit == frames.pet.unit and WhoaUF.UpdatePetFrame then
		WhoaUF:UpdatePetFrame()
		return true
	end
	return false
end

-- UNIT_FACTION / UNIT_FLAGS often fire for only one token when target+focus (or
-- ToT aliases) share a GUID. Refresh the other Whoa frames so hostility tint
-- (orange → red, tap grey, etc.) stays in sync.
local SELECTION_ALIAS_TOKENS = { "target", "focus", "targettarget", "focustarget" }

local function RefreshSelectionColorAliases(eventUnit, fullRebuild)
	if not eventUnit or not WhoaUF.UnitMatchesToken then
		return
	end
	for i = 1, #SELECTION_ALIAS_TOKENS do
		local token = SELECTION_ALIAS_TOKENS[i]
		if token ~= eventUnit
			and UnitExists(token)
			and WhoaUF:UnitMatchesToken(eventUnit, token)
		then
			local frame = FrameForUnit(token)
			if frame then
				if fullRebuild then
					WhoaUF:UpdateUnitFrame(frame)
				else
					WhoaUF:RefreshUnitTint(frame)
					if token == "target" or token == "focus" then
						UF.UpdatePvPIcon(frame, token)
					elseif UF.UpdateToTAttackMode then
						UF.UpdateToTAttackMode(frame)
					end
				end
			end
		end
	end
end

-- Parent HP drives ToT visibility (Blizzard: hide ToT when parent health <= 0).
local function RefreshParentDrivenToT(parentUnit)
	local parent, tot
	if parentUnit == "target" then
		parent, tot = frames.target, frames.tot
	elseif parentUnit == "focus" then
		parent, tot = frames.focus, frames.focustot
	else
		return
	end
	if not tot then
		return
	end
	local hadToT = parent and parent.haveToT
	WhoaUF:UpdateUnitFrame(tot)
	-- Aura / spellbar layout depends on haveToT; refresh when visibility flips.
	if parent and parent.haveToT ~= hadToT and WhoaUF.UpdateUnitAuras then
		WhoaUF:UpdateUnitAuras(parent)
	end
end

function WhoaUF:InitUnitFrameEvents()
	if self.unitFrameWatcher then
		return
	end
	local watcher = CreateFrame("Frame")
	-- RegisterUnitEvent accepts at most 4 units and re-register overwrites — a
	-- second frame carries focus / ToT / ToF so they actually receive UNIT_*.
	local watcherB = CreateFrame("Frame")
	local function RegisterUnitFrameWatcherEvents(w, wB)
		wB = wB or WhoaUF.unitFrameWatcherB
		w:RegisterEvent("PLAYER_ENTERING_WORLD")
		w:RegisterEvent("PLAYER_TARGET_CHANGED")
		pcall(function()
			w:RegisterEvent("PLAYER_FOCUS_CHANGED")
		end)
		local function RegisterUFUnitEvent(event)
			w:RegisterUnitEvent(event, "player", "vehicle", "pet", "target")
			if wB then
				wB:RegisterUnitEvent(event, "focus", "targettarget", "focustarget")
			end
		end
		RegisterUFUnitEvent("UNIT_HEALTH")
		pcall(function()
			RegisterUFUnitEvent("UNIT_HEALTH_FREQUENT")
		end)
		RegisterUFUnitEvent("UNIT_MAXHEALTH")
		-- Heal prediction is Classic-only (Frames/HealPrediction_Classic.lua).
		if WhoaUF.UpdateHealPrediction then
			pcall(function()
				RegisterUFUnitEvent("UNIT_HEAL_PREDICTION")
			end)
			-- Absorb shields (Power Word: Shield, etc.) — MoP/Cata+. Not covered by
			-- UNIT_HEAL_PREDICTION; Blizzard UnitFrame registers these separately.
			pcall(function()
				RegisterUFUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED")
			end)
			pcall(function()
				RegisterUFUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
			end)
		end
		pcall(function()
			w:RegisterEvent("PORTRAITS_UPDATED")
		end)
		RegisterUFUnitEvent("UNIT_POWER_UPDATE")
		pcall(function()
			RegisterUFUnitEvent("UNIT_POWER_FREQUENT")
		end)
		RegisterUFUnitEvent("UNIT_MAXPOWER")
		RegisterUFUnitEvent("UNIT_DISPLAYPOWER")
		RegisterUFUnitEvent("UNIT_LEVEL")
		RegisterUFUnitEvent("UNIT_NAME_UPDATE")
		RegisterUFUnitEvent("UNIT_PORTRAIT_UPDATE")
		RegisterUFUnitEvent("UNIT_CLASSIFICATION_CHANGED")
		-- Global (not unit-filtered): player PvP/faction flips must still refresh
		-- target/focus selection colors (Blizzard TargetFrame UNIT_FACTION).
		w:RegisterEvent("UNIT_FACTION")
		-- Tap / attackability / civilian flags — same selection-color impact as faction.
		w:RegisterEvent("UNIT_FLAGS")
		pcall(function()
			w:RegisterEvent("UNIT_TARGETABLE_CHANGED")
		end)
		RegisterUFUnitEvent("UNIT_CONNECTION")
		w:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
		w:RegisterUnitEvent("UNIT_AURA", "target", "focus", "targettarget", "focustarget")
		w:RegisterUnitEvent("PLAYER_FLAGS_CHANGED", "player", "target", "focus")
		w:RegisterEvent("CVAR_UPDATE")
		w:RegisterEvent("PLAYER_UPDATE_RESTING")
		w:RegisterEvent("PLAYER_ENTER_COMBAT")
		w:RegisterEvent("PLAYER_LEAVE_COMBAT")
		w:RegisterEvent("PLAYER_REGEN_DISABLED")
		w:RegisterEvent("PLAYER_REGEN_ENABLED")
		-- Player/vehicle only: UNIT_COMBAT has no attacker, so target/focus
		-- registration showed every hit on that unit. Outgoing player/pet
		-- feedback on those frames is driven by CLEU (SetCombatFeedbackRuntime).
		pcall(function()
			w:RegisterUnitEvent("UNIT_COMBAT", "player", "vehicle")
		end)
		w:RegisterEvent("PARTY_LEADER_CHANGED")
		w:RegisterEvent("GROUP_ROSTER_UPDATE")
		w:RegisterEvent("RAID_TARGET_UPDATE")
		w:RegisterEvent("PLAYER_DEAD")
		w:RegisterEvent("PLAYER_ALIVE")
		w:RegisterEvent("PLAYER_UNGHOST")
		pcall(function()
			w:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
			w:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
			w:RegisterUnitEvent("UNIT_ENTERING_VEHICLE", "player")
			w:RegisterUnitEvent("UNIT_EXITING_VEHICLE", "player")
		end)
		pcall(function()
			w:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
		end)
	end
	self.RegisterUnitFrameWatcherEvents = RegisterUnitFrameWatcherEvents
	RegisterUnitFrameWatcherEvents(watcher, watcherB)
	self.unitFrameWatcher = watcher
	self.unitFrameWatcherB = watcherB
	local function OnUnitFrameWatcherEvent(_, event, unit, ...)
		if event == "PLAYER_ENTERING_WORLD" then
			C_Timer.After(0, function()
				local player = frames.player
				if player then
					player.inCombat = nil
					player.onHateList = UnitAffectingCombat("player") and true or nil
					local seatActive = WhoaUF.PlayerVehicleSeatActive and WhoaUF:PlayerVehicleSeatActive()
					if seatActive then
						player.inSeat = true
						player.state = "vehicle"
						player.vehicleHidesPet = UnitInVehicleHidesPetFrame
							and UnitInVehicleHidesPetFrame("player")
							or false
					else
						player.inSeat = nil
						player.state = "player"
						player.vehicleHidesPet = false
					end
				end
				WhoaUF:CaptureBlizzardUnitFrameAnchors()
				WhoaUF:SyncUnitFramePositions()
				WhoaUF:ApplyUnitFrames()
				WhoaUF:ApplyPlayerVehicleTransition()
				-- Instance load can reset cast bars to stock light chrome;
				-- re-run SpellbarArt_*.lua ApplyAllSpellbarArt after the deferred apply.
				if WhoaUF.ApplyAllSpellbarArt then
					pcall(WhoaUF.ApplyAllSpellbarArt, WhoaUF)
				end
			end)
			return
		end
		if event == "UPDATE_VEHICLE_ACTIONBAR" then
			WhoaUF:ApplyPlayerVehicleTransition()
			if WhoaUF.SchedulePlayerVehicleTransition then
				WhoaUF:SchedulePlayerVehicleTransition()
			end
			return
		end
		if event == "UNIT_ENTERING_VEHICLE" then
			if unit == "player" then
				local player = frames.player
				if player then
					player.inSeat = false
					local showVehicleUI = ...
					if showVehicleUI
						or (WhoaUF.PlayerVehicleSeatActive and WhoaUF:PlayerVehicleSeatActive())
						or (UnitHasVehiclePlayerFrameUI and UnitHasVehiclePlayerFrameUI("player")) then
						WhoaUF:SuppressPlayerVehicleChrome()
						if WhoaUF.ApplyPlayerVehicleVisuals then
							WhoaUF:ApplyPlayerVehicleVisuals()
						end
					end
				end
			end
			return
		end
		if event == "UNIT_ENTERED_VEHICLE" then
			if unit == "player" then
				local player = frames.player
				if player then
					player.inSeat = true
					-- Only some vehicles hide the pet slot; most keep it and show the player.
					player.vehicleHidesPet = UnitInVehicleHidesPetFrame
						and UnitInVehicleHidesPetFrame("player")
						or false
					WhoaUF:ApplyPlayerVehicleTransition()
					-- HasUI / vehicle unit can lag one frame on scripted seats.
					if WhoaUF.SchedulePlayerVehicleTransition then
						WhoaUF:SchedulePlayerVehicleTransition()
					end
				end
			end
			return
		end
		if event == "UNIT_EXITING_VEHICLE" then
			if unit == "player" then
				local player = frames.player
				if player then
					local wasVehicle = player.state == "vehicle"
						or player.unit == "vehicle"
						or (WhoaUF.IsPlayerVehicleFrameActive and WhoaUF:IsPlayerVehicleFrameActive(player))
						or (UnitHasVehiclePlayerFrameUI and UnitHasVehiclePlayerFrameUI("player"))
					if not wasVehicle then
						player.updatePetFrame = true
					end
					player.vehicleHidesPet = false
					-- Quest vehicles often despawn here; don't wait solely on EXITED.
					if wasVehicle and WhoaUF.SchedulePlayerVehicleTransition then
						WhoaUF:SchedulePlayerVehicleTransition()
					end
					if WhoaUF.SchedulePlayerFrameOptionsRefresh then
						WhoaUF:SchedulePlayerFrameOptionsRefresh()
					end
				end
			end
			return
		end
		if event == "UNIT_EXITED_VEHICLE" then
			if unit == "player" then
				local player = frames.player
				if player then
					player.inSeat = true
					-- Flag already cleared on EXITING; keep false in case EXITING was skipped.
					player.vehicleHidesPet = false
					if player.updatePetFrame then
						player.updatePetFrame = false
						if WhoaUF.ApplyPetFrameVisibility then
							WhoaUF:ApplyPetFrameVisibility()
						end
						if WhoaUF.UpdatePetFrame then
							WhoaUF:UpdatePetFrame()
						end
					end
					WhoaUF:ApplyPlayerVehicleTransition()
					-- Retry next frame: HasUI can still be true while "vehicle" is gone.
					if WhoaUF.SchedulePlayerVehicleTransition then
						WhoaUF:SchedulePlayerVehicleTransition()
					end
					-- Always re-apply style mana/HP from options after seat loss.
					if WhoaUF.SchedulePlayerFrameOptionsRefresh then
						WhoaUF:SchedulePlayerFrameOptionsRefresh()
					end
				end
			end
			return
		end
		if event == "CVAR_UPDATE" then
			if unit == "statusText" or unit == "statusTextDisplay" then
				WhoaUF:RefreshAllUnitFrames()
			elseif unit == "showTargetOfTarget" then
				WhoaUF:ApplyUnitFrames()
			end
			return
		end
		if event == "PORTRAITS_UPDATED" then
			for _, f in pairs(frames) do
				if type(f) == "table" and f.Portrait and f.unit and UnitExists(f.unit) then
					f.PortraitLastGuid = nil
					UF.UpdatePortrait(f, f.unit)
				end
			end
			return
		end
		if event == "UNIT_HEAL_PREDICTION"
			or event == "UNIT_ABSORB_AMOUNT_CHANGED"
			or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
		then
			local f
			if unit == "player" or unit == "vehicle" then
				f = frames.player
			elseif unit == "target" then
				f = frames.target
			elseif unit == "focus" then
				f = frames.focus
			elseif unit == "pet" then
				f = frames.pet
			elseif unit == "targettarget" then
				f = frames.tot
			elseif unit == "focustarget" then
				f = frames.focustot
			end
			if f and WhoaUF.UpdateHealPrediction then
				WhoaUF:UpdateHealPrediction(f)
			end
			return
		end
		if event == "PLAYER_TARGET_CHANGED" then
			if frames.target then
				UF.ResetFrameHealthPaint(frames.target)
				if UF.ResetFramePowerPaint then
					UF.ResetFramePowerPaint(frames.target)
				end
				if UF.ResetFrameChrome then
					UF.ResetFrameChrome(frames.target)
				end
				local acquiring = UnitExists("target")
				-- Blizzard keeps the frame up on retarget; cloak alpha only on first Show.
				if acquiring and not frames.target:IsShown() then
					if UF.HoldTargetFrameReveal then
						UF.HoldTargetFrameReveal(frames.target)
					end
				elseif acquiring and frames.target.whoaTargetRevealHold then
					-- OnShow already cloaked the frame; keep alpha 0 until deferred reveal.
				elseif acquiring then
					frames.target.whoaTargetRevealHold = nil
					frames.target:SetAlpha(1)
				end
				if acquiring and WhoaUF.ApplyTargetClassificationChrome then
					WhoaUF:ApplyTargetClassificationChrome(frames.target)
				end
			end
			if frames.target and WhoaUF.ResetSpellDiminishTray then
				WhoaUF:ResetSpellDiminishTray(frames.target)
			end
			-- First pass: paint bars; power and frame stay cloaked until deferred reveal.
			WhoaUF:UpdateUnitFrame(frames.target)
			WhoaUF:UpdateUnitFrame(frames.tot)
			if frames.target and WhoaUF.AdjustSpellBar then
				WhoaUF:AdjustSpellBar(frames.target)
			end
			local function revealTargetFrame()
				if frames.target then
					if UF.ReleasePowerBarReveal then
						UF.ReleasePowerBarReveal(frames.target)
					end
					if frames.target.whoaTargetRevealHold and UF.ReleaseTargetFrameReveal then
						UF.ReleaseTargetFrameReveal(frames.target)
					end
					WhoaUF:UpdateUnitFrame(frames.target)
				end
				if frames.tot then
					if UF.ReleasePowerBarReveal then
						UF.ReleasePowerBarReveal(frames.tot)
					end
					WhoaUF:UpdateUnitFrame(frames.tot)
				end
			end
			C_Timer.After(0, revealTargetFrame)
			if frames.player and WhoaUF.UpdateFrameThreat then
				WhoaUF:UpdateFrameThreat(frames.player)
			end
			-- Player power unchanged on target swap; still re-sync cap pulse for combat/at-max.
			if frames.player and UnitAffectingCombat("player") then
				UF.UpdatePower(frames.player, frames.player.unit or "player")
			end
			return
		end
		if event == "PLAYER_FOCUS_CHANGED" then
			if frames.focus and WhoaUF.ResetSpellDiminishTray then
				WhoaUF:ResetSpellDiminishTray(frames.focus)
			end
			UF.RefreshFocusFrames()
			return
		end
		-- Faction / flags / targetable: UnitSelectionColor, tap grey, name bg, HP tint.
		-- Mirror TargetFrameMixin: the unit itself or "player" refreshes affected frames.
		if event == "UNIT_FACTION"
			or event == "UNIT_FLAGS"
			or event == "UNIT_TARGETABLE_CHANGED"
		then
			if unit == "player" or unit == "vehicle" then
				if event == "UNIT_FACTION" then
					-- Full rebuild: PvP icon, auras/level on target (Blizzard CheckFaction path).
					WhoaUF:UpdateUnitFrame(frames.player)
					if frames.target and UnitExists("target") then
						WhoaUF:UpdateUnitFrame(frames.target)
					end
					if frames.focus and UnitExists("focus") then
						WhoaUF:UpdateUnitFrame(frames.focus)
					end
					if frames.tot and UnitExists("targettarget") then
						WhoaUF:UpdateUnitFrame(frames.tot)
					end
					if frames.focustot and UnitExists("focustarget") then
						WhoaUF:UpdateUnitFrame(frames.focustot)
					end
					if WhoaUF.UpdatePetFrame then
						WhoaUF:UpdatePetFrame()
					end
					if WhoaUF.UpdateAllPartyFrames then
						WhoaUF:UpdateAllPartyFrames()
					end
				else
					-- FLAGS / TARGETABLE on player: selection tint without full rebuild spam.
					if frames.player then
						UF.UpdatePvPIcon(frames.player, frames.player.unit or "player")
					end
					WhoaUF:RefreshPlayerSelectionDependentTints()
				end
			elseif unit == "pet" then
				if WhoaUF.UpdatePetFrame then
					WhoaUF:UpdatePetFrame()
				end
			elseif unit == "target" then
				if event == "UNIT_FACTION" then
					WhoaUF:UpdateUnitFrame(frames.target)
					RefreshSelectionColorAliases(unit, true)
				else
					WhoaUF:RefreshUnitTint(frames.target)
					if frames.target then
						UF.UpdatePvPIcon(frames.target, "target")
					end
					RefreshSelectionColorAliases(unit, false)
				end
			elseif unit == "focus" then
				if event == "UNIT_FACTION" then
					WhoaUF:UpdateUnitFrame(frames.focus)
					RefreshSelectionColorAliases(unit, true)
				else
					WhoaUF:RefreshUnitTint(frames.focus)
					if frames.focus then
						UF.UpdatePvPIcon(frames.focus, "focus")
					end
					RefreshSelectionColorAliases(unit, false)
				end
			elseif unit == "targettarget" then
				if event == "UNIT_FACTION" then
					WhoaUF:UpdateUnitFrame(frames.tot)
					RefreshSelectionColorAliases(unit, true)
				else
					WhoaUF:RefreshUnitTint(frames.tot)
					if frames.tot and UF.UpdateToTAttackMode then
						UF.UpdateToTAttackMode(frames.tot)
					end
					RefreshSelectionColorAliases(unit, false)
				end
			elseif unit == "focustarget" then
				if event == "UNIT_FACTION" then
					WhoaUF:UpdateUnitFrame(frames.focustot)
					RefreshSelectionColorAliases(unit, true)
				else
					WhoaUF:RefreshUnitTint(frames.focustot)
					if frames.focustot and UF.UpdateToTAttackMode then
						UF.UpdateToTAttackMode(frames.focustot)
					end
					RefreshSelectionColorAliases(unit, false)
				end
			end
			return
		end
		if event == "UNIT_CONNECTION" then
			-- Disconnect / reconnect: full refresh so Offline label, lightning, power
			-- visibility, and bar text all snap back to a normal frame.
			local function RefreshConnection(frame)
				if not frame then
					return
				end
				WhoaUF:UpdateUnitFrame(frame)
			end
			if IsPlayerFrameEventUnit(unit) then
				RefreshConnection(frames.player)
			elseif unit == "pet" then
				if WhoaUF.UpdatePetFrame then
					WhoaUF:UpdatePetFrame()
				end
			elseif unit == "target" then
				RefreshConnection(frames.target)
			elseif unit == "focus" then
				RefreshConnection(frames.focus)
			elseif unit == "targettarget" then
				RefreshConnection(frames.tot)
			elseif unit == "focustarget" then
				RefreshConnection(frames.focustot)
			end
			return
		end
		if event == "UNIT_TARGET" then
			-- Nested tokens (targettarget / focustarget) often lag one frame on Classic.
			if unit == "target" then
				if frames.tot then
					UF.ResetFrameHealthPaint(frames.tot)
					if UF.ResetFramePowerPaint then
						UF.ResetFramePowerPaint(frames.tot)
					end
					WhoaUF:UpdateUnitFrame(frames.tot)
					C_Timer.After(0, function()
						if frames.tot then
							if UF.ReleasePowerBarReveal then
								UF.ReleasePowerBarReveal(frames.tot)
							end
							WhoaUF:UpdateUnitFrame(frames.tot)
						end
					end)
				end
				if frames.target and WhoaUF.AdjustSpellBar then
					WhoaUF:AdjustSpellBar(frames.target)
				end
			elseif unit == "focus" then
				if frames.focustot then
					UF.ResetFrameHealthPaint(frames.focustot)
					if UF.ResetFramePowerPaint then
						UF.ResetFramePowerPaint(frames.focustot)
					end
					WhoaUF:UpdateUnitFrame(frames.focustot)
					C_Timer.After(0, function()
						if frames.focustot then
							if UF.ReleasePowerBarReveal then
								UF.ReleasePowerBarReveal(frames.focustot)
							end
							WhoaUF:UpdateUnitFrame(frames.focustot)
						end
					end)
				end
				if frames.focus and WhoaUF.AdjustSpellBar then
					WhoaUF:AdjustSpellBar(frames.focus)
				end
			end
			return
		end
		if event == "UNIT_AURA" then
			if unit == "target" then
				WhoaUF:UpdateUnitAuras(frames.target)
			elseif unit == "focus" then
				WhoaUF:UpdateUnitAuras(frames.focus)
			elseif unit == "targettarget" then
				if WhoaUF.UpdateToTDebuffs then
					WhoaUF:UpdateToTDebuffs(frames.tot)
				end
			elseif unit == "focustarget" then
				if WhoaUF.UpdateToTDebuffs then
					WhoaUF:UpdateToTDebuffs(frames.focustot)
				end
			end
			return
		end
		if event == "PLAYER_UPDATE_RESTING" then
			if frames.player then
				UF.UpdatePlayerStatus(frames.player)
			end
			return
		end
		if event == "UNIT_COMBAT" then
			UF.DispatchCombatFeedback(unit, ...)
			return
		end
		-- Match PlayerFrame.lua: inCombat = auto-attack only; onHateList = regen/lockdown.
		-- Merging them left combat swords stuck if PLAYER_LEAVE_COMBAT never fired.
		if event == "PLAYER_ENTER_COMBAT" then
			if frames.player then
				frames.player.inCombat = true
				UF.UpdatePlayerStatus(frames.player)
				-- Cap pulse checks UnitAffectingCombat; power may already be max with no UNIT_POWER tick.
				UF.UpdatePower(frames.player, frames.player.unit or "player")
			end
			return
		end
		if event == "PLAYER_LEAVE_COMBAT" then
			if frames.player then
				frames.player.inCombat = nil
				UF.UpdatePlayerStatus(frames.player)
				UF.UpdatePower(frames.player, frames.player.unit or "player")
			end
			return
		end
		if event == "PLAYER_REGEN_DISABLED" then
			if frames.player then
				frames.player.onHateList = true
				UF.UpdatePlayerStatus(frames.player)
				UF.UpdatePower(frames.player, frames.player.unit or "player")
			end
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			if frames.player then
				frames.player.onHateList = nil
				UF.UpdatePlayerStatus(frames.player)
				UF.UpdatePower(frames.player, frames.player.unit or "player")
			end
			-- Leave combat: reclaim combat-churn garbage once (force past throttle).
			if WhoaUF.RequestIdleCollect then
				WhoaUF:RequestIdleCollect(true)
			end
			return
		end
		if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
			-- Release spirit flips Dead → Ghost without a unit health event.
			WhoaUF:UpdateUnitFrame(frames.player)
			if frames.target and UnitExists("target") then
				WhoaUF:UpdateUnitFrame(frames.target)
			end
			if frames.focus and UnitExists("focus") then
				WhoaUF:UpdateUnitFrame(frames.focus)
			end
			if frames.tot and UnitExists("targettarget") then
				WhoaUF:UpdateUnitFrame(frames.tot)
			end
			if frames.focustot and UnitExists("focustarget") then
				WhoaUF:UpdateUnitFrame(frames.focustot)
			end
			return
		end
		if event == "RAID_TARGET_UPDATE" then
			if frames.target then
				UF.UpdateRaidTargetIcon(frames.target, "target")
			end
			if frames.focus then
				UF.UpdateRaidTargetIcon(frames.focus, "focus")
			end
			return
		end
		if event == "PARTY_LEADER_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
			-- Do not ClearFocus() here like TargetFrame does: it is protected and
			-- blocked from addon code. RegisterUnitWatch hides the focus frame.
			if WhoaUF.LayoutPartyFrames then
				WhoaUF:LayoutPartyFrames()
			end
			WhoaUF:RefreshAllUnitFrames()
			return
		end
		if event == "PLAYER_FLAGS_CHANGED" then
			-- PvP flag / FFA toggles change UnitSelectionColor on hostile players.
			if unit == "player" then
				if frames.player then
					UF.UpdateLeaderIcon(frames.player, "player")
					UF.UpdatePvPIcon(frames.player, "player")
				end
				WhoaUF:RefreshPlayerSelectionDependentTints()
				if frames.target and UnitExists("target") then
					UF.UpdatePvPIcon(frames.target, "target")
					UF.UpdateLeaderIcon(frames.target, "target")
				end
				if frames.focus and UnitExists("focus") then
					UF.UpdatePvPIcon(frames.focus, "focus")
					UF.UpdateLeaderIcon(frames.focus, "focus")
				end
			elseif unit == "target" or unit == "focus" then
				local frame = frames[unit]
				if frame then
					UF.UpdateLeaderIcon(frame, unit)
					UF.UpdatePvPIcon(frame, unit)
					WhoaUF:RefreshUnitTint(frame)
				end
				RefreshSelectionColorAliases(unit, false)
			end
			return
		end

		-- Aspect dispatch (Blizzard: health/mana bars own UNIT_HEALTH / UNIT_POWER;
		-- TargetFrame only CheckDead / CheckLevel / CheckClassification on those events).
		-- Full UpdateUnitFrame stays on unit swap / PEW / Apply / faction rebuilds.
		if event == "UNIT_HEALTH"
			or event == "UNIT_HEALTH_FREQUENT"
			or event == "UNIT_MAXHEALTH"
		then
			if UpdatePetIfUnit(unit) then
				return
			end
			local frame = FrameForUnit(unit)
			if frame then
				if frame.kind == "tot" or frame.kind == "focustot" then
					WhoaUF:UpdateUnitFrame(frame)
				elseif UnitExists(frame.unit) then
					local u = frame.unit
					UF.UpdateHealth(frame, u)
					UF.UpdateDeadText(frame, u)
					-- Dead/ghost hides power; rez restores it (cheaper than full rebuild).
					UF.UpdatePower(frame, u)
				end
			end
			RefreshParentDrivenToT(unit)
			return
		end

		if event == "UNIT_POWER_UPDATE"
			or event == "UNIT_POWER_FREQUENT"
			or event == "UNIT_MAXPOWER"
			or event == "UNIT_DISPLAYPOWER"
		then
			if UpdatePetIfUnit(unit) then
				return
			end
			local frame = FrameForUnit(unit)
			if frame then
				if frame.kind == "tot" or frame.kind == "focustot" then
					WhoaUF:UpdateUnitFrame(frame)
				elseif UnitExists(frame.unit) then
					UF.UpdatePower(frame, frame.unit)
				end
			end
			return
		end

		if event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
			if UpdatePetIfUnit(unit) then
				return
			end
			local frame = FrameForUnit(unit)
			if frame then
				if frame.kind == "tot" or frame.kind == "focustot" then
					WhoaUF:UpdateUnitFrame(frame)
				elseif UnitExists(frame.unit) then
					UF.UpdateIdentity(frame, frame.unit)
				end
			end
			return
		end

		if event == "UNIT_PORTRAIT_UPDATE" then
			if UpdatePetIfUnit(unit) then
				return
			end
			local frame = FrameForUnit(unit)
			if frame and frame.Portrait and UnitExists(frame.unit) then
				if frame.kind == "tot" or frame.kind == "focustot" then
					WhoaUF:UpdateUnitFrame(frame)
				else
					frame.PortraitLastGuid = nil
					UF.UpdatePortrait(frame, frame.unit)
				end
			end
			return
		end

		if event == "UNIT_CLASSIFICATION_CHANGED" then
			if UpdatePetIfUnit(unit) then
				return
			end
			local frame = FrameForUnit(unit)
			if frame and UnitExists(frame.unit) then
				if frame.kind == "tot" or frame.kind == "focustot" then
					WhoaUF:UpdateUnitFrame(frame)
				else
					UF.UpdateClassification(frame)
					-- Minus / life chrome can toggle power visibility.
					UF.UpdatePower(frame, frame.unit)
				end
			end
			return
		end
	end
	watcher:SetScript("OnEvent", OnUnitFrameWatcherEvent)
	watcherB:SetScript("OnEvent", OnUnitFrameWatcherEvent)
	if UF.SetCombatFeedbackRuntime then
		UF.SetCombatFeedbackRuntime(WhoaUF.db and WhoaUF.db.enabled)
	end
end
