--[[
	PvP spell diminishing-returns tray on Whoa target/focus frames.

	Uses Blizzard's SpellDiminishStatusTrayTemplate + C_SpellDiminish (Mainline).
	Reference: reference/Blizzard_SpellDiminishUI/Blizzard_SpellDiminishUITemplates.lua
	           reference/Blizzard_SettingsDefinitions_Frame/AdvancedOptions.lua (CVars)
]]

local UF = WhoaUF._UF

local CVAR_PVP_ENEMIES = "spellDiminishPVPEnemiesEnabled"

local function SystemSupported()
	return C_SpellDiminish
		and C_SpellDiminish.IsSystemSupported
		and C_SpellDiminish.IsSystemSupported()
end

local function EnsureBlizzardSpellDiminishUI()
	if SpellDiminishStatusTrayMixin then
		return true
	end
	if C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_SpellDiminishUI")
	elseif LoadAddOn then
		pcall(LoadAddOn, "Blizzard_SpellDiminishUI")
	end
	return SpellDiminishStatusTrayMixin ~= nil
end

local function AnchorTray(tray, frame)
	tray:ClearAllPoints()
	-- Left of classic target chrome (bars on left, portrait on right).
	tray:SetPoint("TOPRIGHT", frame, "TOPLEFT", -2, -12)
end

local function AttachTray(frame)
	if not frame or frame.SpellDiminishStatusTray then
		return frame and frame.SpellDiminishStatusTray
	end
	if not SystemSupported() or not EnsureBlizzardSpellDiminishUI() then
		return nil
	end

	local tray = CreateFrame("Frame", nil, frame, "SpellDiminishStatusTrayTemplate")
	if not tray then
		return nil
	end

	AnchorTray(tray, frame)
	tray:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
	if frame.unit and tray.SetUnit then
		tray:SetUnit(frame.unit)
	end
	if tray.UpdateShownState then
		tray:UpdateShownState()
	end

	frame.SpellDiminishStatusTray = tray
	return tray
end

--- Drop active icons when the unit token keeps the same name but points at a new GUID
--- (target/focus swap). Arena-style fixed tokens do not need this; target/focus do.
function WhoaUF:ResetSpellDiminishTray(frame)
	local tray = frame and frame.SpellDiminishStatusTray
	if not tray then
		return
	end
	if tray.RemoveAllTrayItems then
		tray:RemoveAllTrayItems()
	end
	if frame.unit and tray.SetUnit then
		tray:SetUnit(frame.unit)
	end
end

function WhoaUF:UpdateSpellDiminishShownState()
	local frames = UF.frames
	if not frames then
		return
	end
	local targetTray = frames.target and frames.target.SpellDiminishStatusTray
	if targetTray and targetTray.UpdateShownState then
		targetTray:UpdateShownState()
	end
	local focusTray = frames.focus and frames.focus.SpellDiminishStatusTray
	if focusTray and focusTray.UpdateShownState then
		focusTray:UpdateShownState()
	end
end

function WhoaUF:InitSpellDiminish()
	if not SystemSupported() then
		return
	end
	if not EnsureBlizzardSpellDiminishUI() then
		return
	end

	local frames = UF.frames
	if frames and frames.target then
		AttachTray(frames.target)
	end
	if frames and frames.focus then
		AttachTray(frames.focus)
	end

	if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback and not UF.spellDiminishCVarHooked then
		UF.spellDiminishCVarHooked = true
		-- Explicit owner: a nil owner draws from the shared CallbackRegistry ID counter.
		CVarCallbackRegistry:RegisterCallback(CVAR_PVP_ENEMIES, function()
			if WhoaUF.UpdateSpellDiminishShownState then
				WhoaUF:UpdateSpellDiminishShownState()
			end
		end, WhoaUF)
	end
end
