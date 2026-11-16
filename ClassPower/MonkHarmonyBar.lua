--[[
	Monk Chi (Harmony) bar on Whoa player frame (MoP).
	Reference: reference/Blizzard_UnitFrame/Mists/MonkHarmonyBar.lua|.xml
]]

do
	if not WhoaUF:HasMonkChi() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "MONK" then
		return
	end
end

local TEX_CLIENT = "Interface\\PlayerFrame\\MonkUI"

local function GetMonkTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(TEX_CLIENT)
	end
	return TEX_CLIENT
end
local MAX_CHI_UI = 5

local function HasMonkChi()
	return WhoaUF:HasMonkChi()
end

local function GetChiType()
	return (Enum and Enum.PowerType and Enum.PowerType.Chi) or 12
end

local function IsMonk()
	local _, class = UnitClass("player")
	return class == "MONK"
end

function WhoaUF:GetMonkHarmonyBarAnchor()
	-- Mists MonkHarmonyBar.xml: TOP of PlayerFrame (31, -50) ≡ Player BOTTOM (31, 50)
	-- (PlayerFrame height 100). Managed leftPadding 46 / topPadding -14 → same slot.
	return 31, 50
end

local function CreateAlphaAnim(group, fromAlpha, toAlpha, duration, order)
	local anim = group:CreateAnimation("Alpha")
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(toAlpha)
	anim:SetDuration(duration)
	anim:SetOrder(order or 1)
	return anim
end

local function SetEnergy(orb, active)
	if orb.active == active then
		return
	end
	orb.active = active
	if active then
		if orb.deactivate:IsPlaying() then
			orb.deactivate:Stop()
		end
		if not orb.activate:IsPlaying() then
			orb.activate:Play()
		end
	else
		if orb.activate:IsPlaying() then
			orb.activate:Stop()
		end
		if not orb.deactivate:IsPlaying() then
			orb.deactivate:Play()
		end
	end
end

local function LayoutChiOrbs(self, maxLight)
	-- Match MonkHarmonyBarMixin:Update — LEFT of the 1px managed frame (≈ center).
	if maxLight == 4 then
		self.orbs[1]:SetPoint("LEFT", self, "LEFT", -43, 1)
		for i = 2, 4 do
			self.orbs[i]:SetPoint("LEFT", self.orbs[i - 1], "RIGHT", 5, 0)
		end
		self.orbs[5]:Hide()
	else
		self.orbs[1]:SetPoint("LEFT", self, "LEFT", -46, 1)
		for i = 2, 5 do
			self.orbs[i]:SetPoint("LEFT", self.orbs[i - 1], "RIGHT", 1, 0)
			self.orbs[i]:Show()
		end
	end
	self.maxLight = maxLight
end

local function UpdateMonkHarmonyBar(self)
	local powerType = GetChiType()
	local light, maxLight
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("MONK") then
		maxLight = MAX_CHI_UI
		light = MAX_CHI_UI
	else
		light = UnitPower("player", powerType)
		maxLight = UnitPowerMax and UnitPowerMax("player", powerType)
		if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(light, maxLight) then
			return
		end
		light = light or 0
		maxLight = maxLight or 4
		if not maxLight or maxLight < 1 then
			maxLight = 4
		end
		maxLight = math.min(maxLight, MAX_CHI_UI)
	end
	if self.maxLight ~= maxLight then
		LayoutChiOrbs(self, maxLight)
	end
	for i = 1, maxLight do
		SetEnergy(self.orbs[i], i <= light)
	end
end

local function RefreshMonkHarmonyVisibility(self)
	local show = HasMonkChi() and IsMonk()
	self:SetShown(show)
	if show then
		UpdateMonkHarmonyBar(self)
	end
	if WhoaUF.LayoutPlayerBottomFrames then
		WhoaUF:LayoutPlayerBottomFrames()
	end
end

function WhoaUF:RefreshMonkHarmonyBar()
	local frame = self.unitFrames and self.unitFrames.player and self.unitFrames.player.MonkHarmonyBar
	if frame then
		RefreshMonkHarmonyVisibility(frame)
	end
end

function WhoaUF:InitMonkHarmonyBar(playerFrame)
	if not playerFrame or playerFrame.MonkHarmonyBar then
		return
	end
	if not HasMonkChi() then
		return
	end

	local frame = CreateFrame("Frame", "WhoaUFMonkHarmonyBar", playerFrame)
	-- Mists MonkHarmonyBar.xml: Size 1x60; art/orbs are centered on this point.
	frame:SetSize(1, 60)
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(playerFrame:GetFrameLevel() + 5)
	frame:Hide()
	frame.orbs = {}
	frame.maxLight = 4

	local shadow = frame:CreateTexture(nil, "BACKGROUND")
	shadow:SetSize(136, 43)
	shadow:SetPoint("CENTER")
	shadow:SetTexture(GetMonkTex())
	shadow:SetTexCoord(0.00390625, 0.53515625, 0.00781250, 0.34375000)

	local bg = frame:CreateTexture(nil, "BORDER")
	bg:SetSize(136, 43)
	bg:SetPoint("CENTER")
	bg:SetTexture(GetMonkTex())
	bg:SetTexCoord(0.00390625, 0.53515625, 0.35937500, 0.69531250)

	for i = 1, MAX_CHI_UI do
		-- Named frames required: ClassPower.xml Alpha targets `$parentGlow`.
		-- Unnamed orbs collapse to a shared "Glow" and all chi anims drive one orb.
		local orb = CreateFrame("Frame", "WhoaUFMonkHarmonyBarOrb" .. i, frame, "WhoaUFMonkChiOrbTemplate")
		orb.active = false
		if WhoaUF.ApplyClassPowerSheetToRegions then
			WhoaUF:ApplyClassPowerSheetToRegions(orb, TEX_CLIENT)
		end
		frame.orbs[i] = orb
	end
	LayoutChiOrbs(frame, 4)

	local function RegisterMonkHarmonyBarEvents(f)
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("UNIT_DISPLAYPOWER")
		f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		f:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	end
	self.RegisterMonkHarmonyBarEvents = RegisterMonkHarmonyBarEvents
	RegisterMonkHarmonyBarEvents(frame)

	frame:SetScript("OnEvent", function(self, event, unit, powerToken)
		if event == "UNIT_POWER_FREQUENT" then
			-- Match MonkHarmonyBarMixin: CHI / DARK_FORCE only (ignore ENERGY ticks).
			if self:IsShown() and (powerToken == "CHI" or powerToken == "DARK_FORCE") then
				UpdateMonkHarmonyBar(self)
			end
			return
		end
		if event == "UNIT_MAXPOWER" then
			if self:IsShown() then
				UpdateMonkHarmonyBar(self)
			end
			return
		end
		RefreshMonkHarmonyVisibility(self)
	end)

	playerFrame.MonkHarmonyBar = frame
	-- Mists MonkHarmonyBar.xml bottomPadding -10 (managed stack spacing).
	frame.whoaBottomPadding = -10
	frame.whoaClassPowerSheet = TEX_CLIENT
	RefreshMonkHarmonyVisibility(frame)
end

function WhoaUF:ApplyMonkHarmonyBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.MonkHarmonyBar
	if not frame then
		return
	end
	if self.ApplyClassPowerSheetRecursive then
		self:ApplyClassPowerSheetRecursive(frame, TEX_CLIENT)
	end
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "MONK",
		load = function()
			return WhoaUF:HasMonkChi()
		end,
		init = function(uf, player)
			uf:InitMonkHarmonyBar(player)
		end,
		refresh = function(uf)
			uf:RefreshMonkHarmonyBar()
		end,
		applyArt = function(uf)
			uf:ApplyMonkHarmonyBarArt()
		end,
		frameKey = "MonkHarmonyBar",
		registerEvents = "RegisterMonkHarmonyBarEvents",
		layout = {
			slot = "bottom",
			order = 50,
			frameKey = "MonkHarmonyBar",
			style = "top",
			getAnchor = "GetMonkHarmonyBarAnchor",
			defaultX = 31,
			defaultY = 50,
		},
	})
end
