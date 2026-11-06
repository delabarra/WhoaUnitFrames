--[[
	Classic ComboFrame on the target (rogue / cat form / etc.).
	Player-bottom: ClassPower/RogueComboPointBar.lua (Legion tray for rogue; Classic feral too).
	Mainline feral: ClassPower/DruidComboPointBar.lua (UF-DruidCP art).
	Reference: reference/Blizzard_UnitFrame/Classic/ComboFrame.xml, ComboFrame.lua
	           reference/ComboFramePlayer_7.3.5/ComboFramePlayer.xml
	Dark: Media\shared\dark\classpower\ComboPoint.blp (frameDark on).
]]

local MAX_COMBO_POINTS_UI = 5
local COMBOFRAME_FADE_IN = 0.3
local COMBOFRAME_HIGHLIGHT_FADE_IN = 0.4
local COMBOFRAME_SHINE_FADE_IN = 0.3
local COMBOFRAME_SHINE_FADE_OUT = 0.4
local COMBO_ANCHOR_X = -26
local COMBO_ANCHOR_Y = -13
local COMBO_POINT_CLIENT = "Interface\\ComboFrame\\ComboPoint"

local function GetComboPointTexture()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(COMBO_POINT_CLIENT)
	end
	return COMBO_POINT_CLIENT
end

function WhoaUF:GetComboFrameAnchorFrame()
	return self.unitFrames and self.unitFrames.target
end

function WhoaUF:AnchorComboFrame()
	local targetFrame = self.unitFrames and self.unitFrames.target
	local combo = targetFrame and targetFrame.ComboFrame
	if not combo then
		return
	end
	local anchor = self:GetComboFrameAnchorFrame()
	if not anchor then
		return
	end
	combo:ClearAllPoints()
	combo:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", COMBO_ANCHOR_X, COMBO_ANCHOR_Y)
end

local whoaComboFrameLastNumPoints = 0

local function ResetComboFrameLastPoints()
	whoaComboFrameLastNumPoints = 0
end

local function SetComboPointRegionTexture(tex, path)
	if not tex or not tex.SetTexture or not path then
		return
	end
	if tex.SetAtlas and tex.GetAtlas then
		local atlas = tex:GetAtlas()
		if atlas and atlas ~= "" then
			pcall(function()
				tex:SetAtlas(nil)
			end)
		end
	end
	tex:SetTexture(path)
end

local function ApplyComboPointArt(point)
	if not point then
		return
	end
	local path = GetComboPointTexture()
	SetComboPointRegionTexture(point.Background, path)
	SetComboPointRegionTexture(point.Highlight, path)
	SetComboPointRegionTexture(point.Shine, path)
end

local function CreateComboPoint(parent)
	local point = CreateFrame("Frame", nil, parent)
	point:SetSize(12, 12)

	local path = GetComboPointTexture()

	local bg = point:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(12, 16)
	bg:SetPoint("TOPLEFT")
	bg:SetTexture(path)
	bg:SetTexCoord(0, 0.375, 0, 1)
	point.Background = bg

	local highlight = point:CreateTexture(nil, "ARTWORK")
	highlight:SetSize(8, 16)
	highlight:SetPoint("TOPLEFT", 2, 0)
	highlight:SetTexture(path)
	highlight:SetTexCoord(0.375, 0.5625, 0, 1)
	highlight:SetAlpha(0)
	point.Highlight = highlight

	local shine = point:CreateTexture(nil, "OVERLAY")
	shine:SetSize(14, 16)
	shine:SetPoint("TOPLEFT", 0, 4)
	shine:SetTexture(path)
	shine:SetTexCoord(0.5625, 1, 0, 1)
	shine:SetBlendMode("ADD")
	shine:SetAlpha(0)
	point.Shine = shine

	point:Hide()
	return point
end

function WhoaUF:ApplyComboFrameArt()
	local target = self.unitFrames and self.unitFrames.target
	local frame = target and target.ComboFrame
	if not frame or not frame.ComboPoints then
		return
	end
	for i = 1, #frame.ComboPoints do
		ApplyComboPointArt(frame.ComboPoints[i])
	end
end

local function GetComboUnit(frame)
	return frame.unit or frame.comboUnit or "player"
end

local function GetNumComboPoints(unit)
	-- No GetComboPoints API: read combo points from UnitPower(ComboPoints).
	if (WhoaUF.IsMainline and WhoaUF:IsMainline()) or not GetComboPoints then
		local powerType = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
		local n = UnitPower(unit, powerType)
		if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(n) then
			return nil
		end
		return n or 0
	end
	return GetComboPoints(unit, "target") or 0
end

local function GetMaxComboPoints(unit)
	local powerType = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
	if UnitPowerMax then
		local max = UnitPowerMax(unit, powerType)
		if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(max) then
			return MAX_COMBO_POINTS_UI
		end
		if max and max > 0 then
			return math.min(max, MAX_COMBO_POINTS_UI)
		end
	end
	return MAX_COMBO_POINTS_UI
end

local function ComboPointShineFadeOut(shine)
	UIFrameFadeOut(shine, COMBOFRAME_SHINE_FADE_OUT)
end

local function ComboPointShineFadeIn(shine)
	local fadeInfo = {}
	fadeInfo.mode = "IN"
	fadeInfo.timeToFade = COMBOFRAME_SHINE_FADE_IN
	fadeInfo.finishedFunc = ComboPointShineFadeOut
	fadeInfo.finishedArg1 = shine
	UIFrameFade(shine, fadeInfo)
end

local function ComboFrame_SetUnit(frame, unit)
	if unit == "vehicle" then
		if not UnitIgnoresVehicleComboPoints or not UnitIgnoresVehicleComboPoints(frame.unit or "player") then
			frame.comboUnit = "vehicle"
			frame.unit = "vehicle"
		end
	else
		frame.comboUnit = unit
		frame.unit = unit
	end
end

local function ComboFrame_UpdateMax(frame)
	frame.maxComboPoints = GetMaxComboPoints(GetComboUnit(frame))
	for i = 1, MAX_COMBO_POINTS_UI do
		frame.ComboPoints[i]:Hide()
	end
	WhoaUF:UpdateComboFrame()
end

function WhoaUF:UpdateComboFrame()
	local targetFrame = self.unitFrames and self.unitFrames.target
	local frame = targetFrame and targetFrame.ComboFrame
	if not frame then
		return
	end

	if self.AnchorComboFrame then
		self:AnchorComboFrame()
	end

	local force = self.db and self.db.forceShowComboPoints
	if self.editModePreviewActive and not force then
		frame:Hide()
		return
	end
	if force then
		-- Preview: ensure target chrome is visible so gems can be seen.
		if targetFrame and not InCombatLockdown() and not targetFrame:IsShown() then
			UnregisterUnitWatch(targetFrame)
			targetFrame:Show()
			if not UnitExists("target") then
				if targetFrame.Name then
					targetFrame.Name:SetText("Target")
				end
				if targetFrame.Portrait then
					targetFrame.Portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
				end
			end
		end
		frame:ClearAllPoints()
		frame:SetPoint("TOPRIGHT", targetFrame, "TOPRIGHT", COMBO_ANCHOR_X, COMBO_ANCHOR_Y)
		local maxPoints = MAX_COMBO_POINTS_UI
		frame.maxComboPoints = maxPoints
		frame:Show()
		frame:SetAlpha(1)
		for i = 1, MAX_COMBO_POINTS_UI do
			local cp = frame.ComboPoints[i]
			cp:Show()
			cp.Highlight:SetAlpha(1)
			cp.Shine:SetAlpha(0)
		end
		frame.lastPoints = maxPoints
		whoaComboFrameLastNumPoints = maxPoints
		return
	end

	local anchor = self.GetComboFrameAnchorFrame and self:GetComboFrameAnchorFrame()
	if anchor and not anchor:IsShown() then
		frame:Hide()
		frame.lastPoints = 0
		ResetComboFrameLastPoints()
		return
	end

	if not frame.maxComboPoints then
		frame.maxComboPoints = GetMaxComboPoints(GetComboUnit(frame))
	end
	local maxPoints = frame.maxComboPoints

	for i = 1, MAX_COMBO_POINTS_UI do
		frame.ComboPoints[i]:SetShown(i <= maxPoints)
		if i > maxPoints then
			frame.ComboPoints[i].Highlight:SetAlpha(0)
			frame.ComboPoints[i].Shine:SetAlpha(0)
		end
	end

	if not UnitExists("target") then
		frame:Hide()
		frame.lastPoints = 0
		ResetComboFrameLastPoints()
		return
	end

	local comboPoints = GetNumComboPoints(GetComboUnit(frame))
	if comboPoints == nil then
		return
	end
	if comboPoints > 0 then
		if not frame:IsShown() then
			frame:Show()
			frame:SetAlpha(0)
			UIFrameFadeIn(frame, COMBOFRAME_FADE_IN)
		end
		local comboIndex = 1
		for i = 1, maxPoints do
			local cp = frame.ComboPoints[comboIndex]
			local highlight = cp.Highlight
			local shine = cp.Shine
			if i <= comboPoints then
				if i > whoaComboFrameLastNumPoints then
					local fadeInfo = {}
					fadeInfo.mode = "IN"
					fadeInfo.timeToFade = COMBOFRAME_HIGHLIGHT_FADE_IN
					fadeInfo.finishedFunc = ComboPointShineFadeIn
					fadeInfo.finishedArg1 = shine
					UIFrameFade(highlight, fadeInfo)
				end
			else
				if ENABLE_COLORBLIND_MODE == "1" then
					cp:Hide()
				end
				highlight:SetAlpha(0)
				shine:SetAlpha(0)
			end
			cp:Show()
			comboIndex = comboIndex + 1
		end
	else
		frame.ComboPoints[1].Highlight:SetAlpha(0)
		frame.ComboPoints[1].Shine:SetAlpha(0)
		frame:Hide()
	end
	frame.lastPoints = comboPoints
	whoaComboFrameLastNumPoints = comboPoints
end

function WhoaUF:InitComboFrame(targetFrame)
	if not targetFrame or targetFrame.ComboFrame then
		return
	end

	-- Classic ComboFrame is parented to UIParent (not the target) so gems sit above chrome.
	local frame = CreateFrame("Frame", "WhoaUFComboFrame", UIParent)
	frame:SetSize(256, 32)
	-- Match ComboFrame.xml: TOPRIGHT of active target frame, -26, -13.
	frame:SetPoint("TOPRIGHT", targetFrame, "TOPRIGHT", COMBO_ANCHOR_X, COMBO_ANCHOR_Y)
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true)
	frame:SetAlpha(0)
	frame:Hide()
	frame.comboUnit = "player"
	frame.unit = "player"
	frame.lastPoints = 0
	frame.ComboPoints = {}

	local offsets = {
		{ 0, 0 },
		{ 7, -8 },
		{ 12, -18 },
		{ 14, -29 },
		{ 13, -40 },
	}
	for i = 1, MAX_COMBO_POINTS_UI do
		local cp = CreateComboPoint(frame)
		cp:SetPoint("TOPRIGHT", frame, "TOPRIGHT", offsets[i][1], offsets[i][2])
		frame.ComboPoints[i] = cp
	end
	frame.ComboPoints[1].Highlight:SetAlpha(0)
	frame.ComboPoints[1].Shine:SetAlpha(0)

	local function RegisterComboFrameEvents(f)
		-- Match Classic ComboFrame_OnLoad (UNIT_POWER_FREQUENT, not UPDATE).
		f:RegisterEvent("PLAYER_TARGET_CHANGED")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		pcall(function()
			f:RegisterEvent("COMBO_TARGET_CHANGED")
		end)
		pcall(function()
			f:RegisterEvent("PLAYER_COMBO_POINTS")
		end)
		f:RegisterEvent("UNIT_POWER_FREQUENT")
		f:RegisterEvent("UNIT_MAXPOWER")
		pcall(function()
			f:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
			f:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
		end)
	end
	self.RegisterComboFrameEvents = RegisterComboFrameEvents
	RegisterComboFrameEvents(frame)

	frame:SetScript("OnEvent", function(self, event, unit)
		if event == "PLAYER_TARGET_CHANGED" or event == "COMBO_TARGET_CHANGED" then
			ResetComboFrameLastPoints()
			WhoaUF:UpdateComboFrame()
		elseif event == "UNIT_ENTERED_VEHICLE" then
			ComboFrame_SetUnit(self, "vehicle")
			ComboFrame_UpdateMax(self)
		elseif event == "UNIT_EXITED_VEHICLE" then
			ComboFrame_SetUnit(self, "player")
			ComboFrame_UpdateMax(self)
		elseif event == "UNIT_MAXPOWER" or event == "PLAYER_ENTERING_WORLD" then
			ComboFrame_UpdateMax(self)
		elseif event == "UNIT_POWER_FREQUENT" then
			if unit and unit ~= GetComboUnit(self) then
				return
			end
			WhoaUF:UpdateComboFrame()
		elseif event == "PLAYER_COMBO_POINTS" then
			WhoaUF:UpdateComboFrame()
		end
	end)

	targetFrame.ComboFrame = frame
	WhoaUF:AnchorComboFrame()
	ComboFrame_UpdateMax(frame)
end
