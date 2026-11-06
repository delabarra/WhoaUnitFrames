--[[
	Monk Stagger bar overlay on Whoa player frame (MoP Brewmaster).
	Reference: reference/Blizzard_UnitFrame/Mists/MonkStaggerBar.lua|.xml
	           reference/Blizzard_UnitFrame/Mists/AlternatePowerBar.xml
	           MonkManaBar chrome matches Whoa AlternateManaBar SetLook() monk branch.
	Anchored on the player chrome (not the bottom managed stack).
]]

do
	if not WhoaUF:HasMonkStagger() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "MONK" then
		return
	end
end

local STAGGER_YELLOW_TRANSITION = 0.30
local STAGGER_RED_TRANSITION = 0.60
local MONK_MANA_BAR_CLIENT = "Interface\\PlayerFrame\\MonkManaBar"
-- MonkManaBar chrome from AlternateManaBar SetLook() monk branch (94×12 at 100, 0).
local MONK_BAR_W, MONK_BAR_H = 94, 12
local MONK_BAR_X, MONK_BAR_Y = 100, 0

local function GetMonkManaBarTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(MONK_MANA_BAR_CLIENT)
	end
	return MONK_MANA_BAR_CLIENT
end

local function GetStaggerColors()
	return WhoaUF:GetPowerBarColor("STAGGER")
end

local function HasMonkStagger()
	return WhoaUF:HasMonkStagger()
end

local function GetSpec()
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		return C_SpecializationInfo.GetSpecialization()
	end
	if GetSpecialization then
		return GetSpecialization()
	end
	return nil
end

local function IsBrewmaster()
	local _, class = UnitClass("player")
	if class ~= "MONK" then
		return false
	end
	local brew = SPEC_MONK_BREWMASTER or 1
	return GetSpec() == brew
end

local function GetPowerUnit()
	local player = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	return (player and player.unit) or "player"
end

local function ApplyBarTexture(bar)
	local path
	if WhoaUF.GetStatusBarTexturePaths then
		local _, mana = WhoaUF:GetStatusBarTexturePaths()
		path = mana
	end
	bar:SetStatusBarTexture(path or "Interface\\TargetingFrame\\UI-StatusBar")
end

local function UpdateStaggerValue(self)
	local unit = GetPowerUnit()
	local cur = 0
	local force = WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("MONK")
	local maxH = UnitHealthMax(unit)
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(maxH) then
		-- Secret max HP: still SetValue from UnitStagger when available.
		if not force and UnitStagger then
			cur = UnitStagger(unit)
		end
		self:SetMinMaxValues(0, maxH)
		if cur ~= nil then
			self:SetValue(cur)
		end
		-- Band colors need cur/max ratio; stay green while max HP is secret.
		local colors = GetStaggerColors()
		local info = colors and colors[1]
		if info then
			self:SetStatusBarColor(info.r, info.g, info.b)
		end
		return
	end
	maxH = maxH or 1
	if force then
		cur = maxH * 0.45
	elseif UnitStagger then
		cur = UnitStagger(unit) or 0
	end
	if maxH < 1 then
		maxH = 1
	end
	self:SetMinMaxValues(0, maxH)
	self:SetValue(cur)
	local percent = cur / maxH
	local colors = GetStaggerColors()
	local info = colors and colors[1]
	if colors then
		if percent > STAGGER_YELLOW_TRANSITION and percent < STAGGER_RED_TRANSITION then
			info = colors[2]
		elseif percent >= STAGGER_RED_TRANSITION then
			info = colors[3]
		end
	end
	if info then
		self:SetStatusBarColor(info.r, info.g, info.b)
	end
end

local function RefreshStaggerVisibility(self)
	local _, class = UnitClass("player")
	local force = WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("MONK")
	local show = HasMonkStagger()
		and class == "MONK"
		and (force or (IsBrewmaster() and not (UnitHasVehiclePlayerFrameUI and UnitHasVehiclePlayerFrameUI("player"))))
	self:SetShown(show)
	if show then
		UpdateStaggerValue(self)
		self:SetScript("OnUpdate", function(bar)
			UpdateStaggerValue(bar)
		end)
	else
		self:SetScript("OnUpdate", nil)
	end
end

function WhoaUF:RefreshMonkStaggerBar()
	local frame = self.unitFrames and self.unitFrames.player and self.unitFrames.player.MonkStaggerBar
	if frame then
		RefreshStaggerVisibility(frame)
	end
end

function WhoaUF:AnchorMonkStaggerBar()
	local player = self.unitFrames and self.unitFrames.player
	local anchorFrame = self:GetClassPowerAnchorFrame() or player
	local bar = player and player.MonkStaggerBar
	if not bar or not anchorFrame then
		return
	end
	bar:ClearAllPoints()
	bar:SetSize(MONK_BAR_W, MONK_BAR_H)
	bar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", MONK_BAR_X, MONK_BAR_Y)
	self:ApplyClassPowerFrameLevel(bar, 4)
end

function WhoaUF:ApplyMonkStaggerBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local bar = player and player.MonkStaggerBar
	if not bar then
		return
	end
	local path = GetMonkManaBarTex()
	if bar.MonkBackground then
		bar.MonkBackground:SetTexture(path)
	end
	if bar.MonkBorder then
		bar.MonkBorder:SetTexture(path)
	end
	ApplyBarTexture(bar)
end

function WhoaUF:InitMonkStaggerBar(playerFrame)
	if not playerFrame or playerFrame.MonkStaggerBar then
		return
	end
	if not HasMonkStagger() then
		return
	end

	local bar = CreateFrame("StatusBar", "WhoaUFMonkStaggerBar", playerFrame)
	bar:SetSize(MONK_BAR_W, MONK_BAR_H)
	self:AnchorMonkStaggerBar()
	bar:SetFrameStrata("LOW")
	bar:SetFrameLevel(playerFrame:GetFrameLevel() + 4)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:Hide()
	bar.whoaClassPowerSheet = MONK_MANA_BAR_CLIENT
	ApplyBarTexture(bar)

	-- MonkManaBar chrome (Mists AlternatePowerBar.xml + AlternateManaBar SetLook monk branch).
	local monkBg = bar:CreateTexture(nil, "BACKGROUND")
	monkBg:SetTexture(GetMonkManaBarTex())
	monkBg:SetSize(128, 16)
	monkBg:SetPoint("TOPLEFT", -17, 0)
	monkBg:SetTexCoord(0, 1, 0.5, 1)
	monkBg:SetVertexColor(0, 0, 0, 0.5)
	bar.MonkBackground = monkBg

	local chrome = CreateFrame("Frame", nil, bar)
	chrome:SetAllPoints()
	chrome:SetFrameLevel(bar:GetFrameLevel() + 5)
	bar.Chrome = chrome

	local monkBorder = chrome:CreateTexture(nil, "OVERLAY")
	monkBorder:SetTexture(GetMonkManaBarTex())
	monkBorder:SetSize(128, 16)
	monkBorder:SetPoint("TOPLEFT", bar, "TOPLEFT", -17, 0)
	monkBorder:SetTexCoord(0, 1, 0, 0.5)
	bar.MonkBorder = monkBorder

	local function RegisterMonkStaggerBarEvents(f)
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("UNIT_DISPLAYPOWER")
		f:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
		pcall(function()
			f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
		f:RegisterEvent("PLAYER_TALENT_UPDATE")
	end
	self.RegisterMonkStaggerBarEvents = RegisterMonkStaggerBarEvents
	RegisterMonkStaggerBarEvents(bar)

	bar:SetScript("OnEvent", function(self)
		RefreshStaggerVisibility(self)
	end)

	playerFrame.MonkStaggerBar = bar
	RefreshStaggerVisibility(bar)
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "MONK",
		load = function()
			return WhoaUF:HasMonkStagger()
		end,
		init = function(uf, player)
			uf:InitMonkStaggerBar(player)
		end,
		refresh = function(uf)
			uf:RefreshMonkStaggerBar()
		end,
		applyArt = function(uf)
			uf:ApplyMonkStaggerBarArt()
		end,
		frameKey = "MonkStaggerBar",
		registerEvents = "RegisterMonkStaggerBarEvents",
		layout = {
			slot = "overlay",
			frameKey = "MonkStaggerBar",
			anchor = "AnchorMonkStaggerBar",
		},
	})
end
