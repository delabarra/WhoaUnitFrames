--[[ Combat lockdown flush: deferred apply, power visibility, hit rects. ]]

local UF = WhoaUF._UF

function WhoaUF:InitUnitFrameCombatFlush()
	if self.unitFrameCombatWatcher then
		return
	end
	local combatWatcher = CreateFrame("Frame")
	combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatWatcher:SetScript("OnEvent", function()
		-- Attribute writes first so clicks match painted units before art re-entry.
		if UF.FlushPendingSecureUnits then
			UF.FlushPendingSecureUnits()
		end
		if UF.pendingBossFramesInit and WhoaUF.LayoutBossFrames then
			UF.pendingBossFramesInit = nil
			WhoaUF:LayoutBossFrames()
		end
		if UF.pendingUnitFramesApply then
			WhoaUF:ApplyUnitFrames()
		end
		if UF.pendingVehicleArtApply then
			UF.pendingVehicleArtApply = nil
			WhoaUF:ApplyPlayerVehicleTransition()
		end
		if UF.pendingPetVisibility then
			UF.pendingPetVisibility = nil
			if WhoaUF.ApplyPetFrameVisibility then
				WhoaUF:ApplyPetFrameVisibility()
			end
			if WhoaUF.UpdatePetFrame then
				WhoaUF:UpdatePetFrame()
			end
			if WhoaUF.LayoutPlayerBottomFrames then
				WhoaUF:LayoutPlayerBottomFrames()
			end
		end
		if UF.pendingFrameScale and WhoaUF.ApplyFrameScale then
			UF.pendingFrameScale = nil
			WhoaUF:ApplyFrameScale()
		end
		if UF.pendingPowerVisibility then
			for frame, showPower in pairs(UF.pendingPowerVisibility) do
				local power = frame and frame.Power
				if power then
					local lifeStatus = frame.unit and UF.GetUnitLifeStatus(frame.unit)
					if lifeStatus == "dead" or lifeStatus == "ghost" or lifeStatus == "offline" then
						showPower = false
					end
					power:SetAlpha(1)
					if frame.kind == "player" and WhoaUF.IsDkAlphaPlayerArtActive and WhoaUF:IsDkAlphaPlayerArtActive(frame) then
						power.pauseUpdates = true
						power:Hide()
					elseif showPower then
						if power.whoaPowerHoldReveal or (not power.whoaPowerPainted and power.currValue == nil) then
							power:Hide()
						else
							power.pauseUpdates = false
							power:SetAlpha(0)
							power:Show()
							if power.currValue ~= nil and UF.SnapStatusBarValue then
								UF.SnapStatusBarValue(power, power.currValue)
							elseif power.currValue ~= nil then
								power:SetValue(power.currValue)
							end
							power:SetAlpha(1)
							UF.UpdateBarTextString(power)
						end
					else
						-- Dead/offline hide leaves pauseUpdates false; user option hide sets pauseUpdates true.
						if lifeStatus ~= "dead" and lifeStatus ~= "ghost" and lifeStatus ~= "offline" then
							power.pauseUpdates = true
						end
						power:Hide()
					end
				end
			end
			wipe(UF.pendingPowerVisibility)
			UF.pendingPowerVisibility = nil
		end
		if UF.FlushPendingSecureMouse then
			UF.FlushPendingSecureMouse()
		end
		if WhoaUF.pendingOptionsOpen then
			WhoaUF.pendingOptionsOpen = nil
			WhoaUF:OpenOptions()
		end
		WhoaUF:SyncUnitFramePositions()
		if WhoaUF.LayoutPlayerBottomFrames then
			WhoaUF:LayoutPlayerBottomFrames()
		end
	end)
	self.unitFrameCombatWatcher = combatWatcher
end
