--[[
	Priest Shadow Orbs bar on Whoa player frame (MoP).
	Reference: reference/Blizzard_UnitFrame/Mists/PriestBar.lua|.xml
]]

do
	if not WhoaUF:HasShadowOrbs() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "PRIEST" then
		return
	end
end

local SHADOW_ORBS_SHOW_LEVEL = 10
local PRIEST_BAR_NUM_ORBS = 3
local TEX_CLIENT = "Interface\\PlayerFrame\\Priest-ShadowUI"

local function GetPriestTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(TEX_CLIENT)
	end
	return TEX_CLIENT
end

local function HasShadowOrbs()
	return WhoaUF:HasShadowOrbs()
end

local function GetShadowOrbsType()
	return (Enum and Enum.PowerType and Enum.PowerType.ShadowOrbs) or 28
end

local function GetPowerUnit()
	local player = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	return (player and player.unit) or "player"
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

local function IsPriest()
	local _, class = UnitClass("player")
	return class == "PRIEST"
end

function WhoaUF:GetPriestBarAnchor()
	-- Mists PriestBar.xml: TOP→BOTTOM (35, 33); leftPadding 50 / topPadding 3.
	return 35, 33
end

local function CreateAlphaAnim(group, fromAlpha, toAlpha, duration, order)
	local anim = group:CreateAnimation("Alpha")
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(toAlpha)
	anim:SetDuration(duration)
	anim:SetOrder(order or 1)
	return anim
end

local function SetOrbActive(orb, active, instant)
	if instant then
		if orb.animIn then
			orb.animIn:Stop()
		end
		if orb.animOut then
			orb.animOut:Stop()
		end
		orb.glow:SetAlpha(active and 1 or 0)
		orb.active = active
		return
	end
	if active then
		if orb.animOut and orb.animOut:IsPlaying() then
			orb.animOut:Stop()
		end
		if not orb.active and orb.animIn and not orb.animIn:IsPlaying() then
			orb.animIn:Play()
		end
		orb.active = true
	else
		if orb.animIn and orb.animIn:IsPlaying() then
			orb.animIn:Stop()
		end
		if orb.active and orb.animOut and not orb.animOut:IsPlaying() then
			orb.animOut:Play()
		end
		orb.active = false
	end
end

local function UpdatePriestBar(self, instant)
	local numOrbs
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("PRIEST") then
		numOrbs = PRIEST_BAR_NUM_ORBS
	else
		numOrbs = UnitPower(GetPowerUnit(), GetShadowOrbsType()) or 0
	end
	for i = 1, PRIEST_BAR_NUM_ORBS do
		SetOrbActive(self.orbs[i], i <= numOrbs, instant)
	end
end

local function ShouldShowPriestBar()
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("PRIEST") then
		return HasShadowOrbs()
	end
	if not IsPriest() or not HasShadowOrbs() then
		return false
	end
	local level = UnitLevel("player") or 1
	if level < SHADOW_ORBS_SHOW_LEVEL then
		return false
	end
	local shadow = SPEC_PRIEST_SHADOW or 3
	return GetSpec() == shadow
end

local function RefreshPriestBarVisibility(self)
	local show = ShouldShowPriestBar()
	self:SetShown(show)
	if show then
		UpdatePriestBar(self, true)
	end
	if WhoaUF.LayoutPlayerBottomFrames then
		WhoaUF:LayoutPlayerBottomFrames()
	end
end

function WhoaUF:RefreshPriestBar()
	local frame = self.unitFrames and self.unitFrames.player and self.unitFrames.player.PriestBar
	if frame then
		RefreshPriestBarVisibility(frame)
	end
end

function WhoaUF:InitPriestBar(playerFrame)
	if not playerFrame or playerFrame.PriestBar then
		return
	end
	if not HasShadowOrbs() then
		return
	end

	local frame = CreateFrame("Frame", "WhoaUFPriestBar", playerFrame)
	frame:SetSize(159, 54)
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(playerFrame:GetFrameLevel() + 5)
	frame:EnableMouse(true)
	frame:SetHitRectInsets(28, 33, 2, 22)
	frame:Hide()
	frame.orbs = {}
	-- Mists PriestBar.xml bottomPadding -20.
	frame.whoaBottomPadding = -20

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(159, 54)
	bg:SetPoint("TOPLEFT")
	bg:SetTexture(GetPriestTex())
	bg:SetTexCoord(0.00390625, 0.62500000, 0.00781250, 0.42968750)

	for i = 1, PRIEST_BAR_NUM_ORBS do
		local orb = CreateFrame("Frame", nil, frame)
		orb:SetSize(38, 37)
		if i == 1 then
			orb:SetPoint("TOPLEFT", 26, -1)
		else
			orb:SetPoint("LEFT", frame.orbs[i - 1], "RIGHT", -5, 0)
		end

		local orbBg = orb:CreateTexture(nil, "BACKGROUND")
		orbBg:SetAllPoints()
		orbBg:SetTexture(GetPriestTex())
		orbBg:SetTexCoord(0.30078125, 0.44921875, 0.44531250, 0.73437500)

		local glow = orb:CreateTexture(nil, "ARTWORK")
		glow:SetAllPoints()
		glow:SetTexture(GetPriestTex())
		glow:SetTexCoord(0.45703125, 0.60546875, 0.44531250, 0.73437500)
		glow:SetAlpha(0)
		orb.glow = glow

		local animIn = orb:CreateAnimationGroup()
		CreateAlphaAnim(animIn, 0, 1, 0.2, 1)
		animIn:SetScript("OnPlay", function()
			glow:SetAlpha(0)
		end)
		animIn:SetScript("OnFinished", function()
			glow:SetAlpha(1)
		end)
		-- animIn Alpha targets glow when SetTarget exists.
		local aIn = animIn:CreateAnimation("Alpha")
		aIn:SetFromAlpha(0)
		aIn:SetToAlpha(1)
		aIn:SetDuration(0.2)
		if aIn.SetTarget then
			aIn:SetTarget(glow)
		end
		orb.animIn = animIn

		local animOut = orb:CreateAnimationGroup()
		local aOut = animOut:CreateAnimation("Alpha")
		aOut:SetFromAlpha(1)
		aOut:SetToAlpha(0)
		aOut:SetDuration(0.2)
		if aOut.SetTarget then
			aOut:SetTarget(glow)
		end
		animOut:SetScript("OnFinished", function()
			glow:SetAlpha(0)
		end)
		orb.animOut = animOut
		orb.active = false
		frame.orbs[i] = orb
	end

	local function RegisterPriestBarEvents(f)
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("PLAYER_TALENT_UPDATE")
		f:RegisterEvent("PLAYER_LEVEL_UP")
		pcall(function()
			f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
		f:RegisterEvent("UNIT_DISPLAYPOWER")
		f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "vehicle")
	end
	self.RegisterPriestBarEvents = RegisterPriestBarEvents
	RegisterPriestBarEvents(frame)

	frame:SetScript("OnEvent", function(self, event, unit, powerToken)
		if event == "UNIT_POWER_FREQUENT" then
			if self:IsShown() and unit == GetPowerUnit() and (not powerToken or powerToken == "SHADOW_ORBS") then
				UpdatePriestBar(self)
			end
			return
		end
		-- Non-power events: re-run visibility gate (Blizzard CheckAndShow).
		RefreshPriestBarVisibility(self)
	end)

	playerFrame.PriestBar = frame
	frame.whoaClassPowerSheet = TEX_CLIENT
	RefreshPriestBarVisibility(frame)
end

function WhoaUF:ApplyPriestBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.PriestBar
	if not frame then
		return
	end
	if self.ApplyClassPowerSheetRecursive then
		self:ApplyClassPowerSheetRecursive(frame, TEX_CLIENT)
	end
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "PRIEST",
		load = function()
			return WhoaUF:HasShadowOrbs()
		end,
		init = function(uf, player)
			uf:InitPriestBar(player)
		end,
		refresh = function(uf)
			uf:RefreshPriestBar()
		end,
		applyArt = function(uf)
			uf:ApplyPriestBarArt()
		end,
		frameKey = "PriestBar",
		registerEvents = "RegisterPriestBarEvents",
		layout = {
			slot = "bottom",
			order = 40,
			frameKey = "PriestBar",
			style = "top",
			getAnchor = "GetPriestBarAnchor",
			defaultX = 35,
			defaultY = 33,
		},
	})
end
