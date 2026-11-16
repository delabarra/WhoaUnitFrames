--[[
	Balance Eclipse bar on Whoa player frame (Cata+).
	Reference: reference/Blizzard_UnitFrame/Cata/EclipseBarFrame.lua|.xml
]]

do
	if not WhoaUF:HasEclipseBar() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "DRUID" then
		return
	end
end

local ECLIPSE_BAR_TRAVEL = 38
local ECLIPSE_BAR_SOLAR_BUFF_ID = 48517
local ECLIPSE_BAR_LUNAR_BUFF_ID = 48518
local TEX_CLIENT = "Interface\\PlayerFrame\\UI-DruidEclipse"

local function GetEclipseTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(TEX_CLIENT)
	end
	return TEX_CLIENT
end

-- Atlas slices from EclipseBarFrame.lua / UI-DruidEclipse (256x128).
local ECLIPSE_ICONS = {
	moon = {
		norm = { 23, 23, 0.55859375, 0.64843750, 0.57031250, 0.75000000 },
		dark = { 23, 23, 0.55859375, 0.64843750, 0.37500000, 0.55468750 },
		big = { 43, 45, 0.73437500, 0.90234375, 0.00781250, 0.35937500 },
	},
	sun = {
		norm = { 23, 23, 0.65625000, 0.74609375, 0.37500000, 0.55468750 },
		dark = { 23, 23, 0.55859375, 0.64843750, 0.76562500, 0.94531250 },
		big = { 43, 45, 0.55859375, 0.72656250, 0.00781250, 0.35937500 },
	},
}

local ECLIPSE_MARKER_COORDS = {
	none = { 0.914, 1.0, 0.82, 1.0 },
	sun = { 0.914, 1.0, 0.641, 0.82 },
	moon = { 1.0, 0.914, 0.641, 0.82 },
}

local function IsCataOrLater()
	return WhoaUF:HasEclipseBar()
end

local function IsMists()
	-- MoP Classic eclipse chrome only (never Mainline).
	return WhoaUF:IsClassicClient() and WhoaUF:HasMoPArt()
end

local function GetBalanceType()
	return (Enum and Enum.PowerType and Enum.PowerType.Balance) or 26
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

-- Cat-form check for Eclipse DevTools force-show (skip when player combo bar owns the slot).
local function IsDruidCatForm()
	local form = GetShapeshiftFormID and GetShapeshiftFormID()
	if form == nil then
		return false
	end
	if CAT_FORM and form == CAT_FORM then
		return true
	end
	return form == 1
end

local function ShouldDisplayEclipse()
	if not IsCataOrLater() then
		return false
	end
	local _, class = UnitClass("player")
	if class ~= "DRUID" then
		return false
	end
	local force = WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("DRUID")
	-- DevTools force-show: fill eclipse for Balance layout (skip in cat — combo bar owns that slot).
	if force then
		return not IsDruidCatForm()
	end
	local form = GetShapeshiftFormID and GetShapeshiftFormID()
	-- Not in cat/bear/travel/etc. — moonkin or caster form only.
	if not (form == MOONKIN_FORM or not form) then
		return false
	end
	local spec = GetSpec()
	local balance = (SPEC_DRUID_BALANCE) or 1
	if IsMists() then
		return spec == balance
	end
	return spec == 1 or spec == balance
end

function WhoaUF:GetEclipseBarAnchor()
	-- Cata EclipseBarFrame.xml: TOP→BOTTOM (30, 36); leftPadding 40 / topPadding 0.
	return 30, 36
end

local function CreateAlphaAnim(group, target, fromAlpha, toAlpha, duration, order)
	local anim = group:CreateAnimation("Alpha")
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(toAlpha)
	anim:SetDuration(duration)
	anim:SetOrder(order or 1)
	if target and anim.SetTarget then
		anim:SetTarget(target)
	end
	return anim
end

local function CreateScaleAnim(group, target, fromX, fromY, toX, toY, duration, order, smoothing)
	local anim = group:CreateAnimation("Scale")
	if anim.SetScaleFrom then
		anim:SetScaleFrom(fromX, fromY)
		anim:SetScaleTo(toX, toY)
	elseif anim.SetFromScale then
		anim:SetFromScale(fromX, fromY)
		anim:SetToScale(toX, toY)
	else
		return nil
	end
	anim:SetDuration(duration)
	anim:SetOrder(order or 1)
	if smoothing and anim.SetSmoothing then
		anim:SetSmoothing(smoothing)
	end
	if target and anim.SetTarget then
		anim:SetTarget(target)
	end
	return anim
end

local function ApplyIcon(tex, info)
	tex:SetSize(info[1], info[2])
	tex:SetTexCoord(info[3], info[4], info[5], info[6])
end

-- EclipseBarFrame.xml: sun/moon Activate|Deactivate + glow.pulse.
local function BuildEclipseAnims(frame)
	local sunActivate = frame:CreateAnimationGroup()
	CreateAlphaAnim(sunActivate, frame.sunBar, 0, 1, 0.6, 1)
	CreateAlphaAnim(sunActivate, frame.glow, 0, 1, 0.6, 1)
	CreateAlphaAnim(sunActivate, frame.darkMoon, 0, 1, 0.6, 1)
	sunActivate:SetScript("OnPlay", function(self)
		local parent = self:GetParent()
		parent.moonBar:SetAlpha(0)
		parent.darkSun:SetAlpha(0)
	end)
	sunActivate:SetScript("OnFinished", function(self)
		local parent = self:GetParent()
		parent.sunBar:SetAlpha(1)
		parent.glow:SetAlpha(1)
		parent.darkMoon:SetAlpha(1)
		parent.glow.pulse:Play()
	end)
	frame.sunActivate = sunActivate

	local sunDeactivate = frame:CreateAnimationGroup()
	CreateAlphaAnim(sunDeactivate, frame.sunBar, 1, 0, 0.6, 1)
	CreateAlphaAnim(sunDeactivate, frame.glow, 1, 0, 0.6, 1)
	CreateAlphaAnim(sunDeactivate, frame.darkMoon, 1, 0, 0.6, 1)
	sunDeactivate:SetScript("OnPlay", function(self)
		self:GetParent().glow.pulse:Stop()
	end)
	sunDeactivate:SetScript("OnFinished", function(self)
		local parent = self:GetParent()
		parent.sunBar:SetAlpha(0)
		parent.glow:SetAlpha(0)
		parent.darkMoon:SetAlpha(0)
	end)
	frame.sunDeactivate = sunDeactivate

	local moonActivate = frame:CreateAnimationGroup()
	CreateAlphaAnim(moonActivate, frame.moonBar, 0, 1, 0.6, 1)
	CreateAlphaAnim(moonActivate, frame.glow, 0, 1, 0.6, 1)
	CreateAlphaAnim(moonActivate, frame.darkSun, 0, 1, 0.6, 1)
	moonActivate:SetScript("OnPlay", function(self)
		local parent = self:GetParent()
		parent.sunBar:SetAlpha(0)
		parent.darkMoon:SetAlpha(0)
	end)
	moonActivate:SetScript("OnFinished", function(self)
		local parent = self:GetParent()
		parent.moonBar:SetAlpha(1)
		parent.glow:SetAlpha(1)
		parent.darkSun:SetAlpha(1)
		parent.glow.pulse:Play()
	end)
	frame.moonActivate = moonActivate

	local moonDeactivate = frame:CreateAnimationGroup()
	CreateAlphaAnim(moonDeactivate, frame.moonBar, 1, 0, 0.6, 1)
	CreateAlphaAnim(moonDeactivate, frame.glow, 1, 0, 0.6, 1)
	CreateAlphaAnim(moonDeactivate, frame.darkSun, 1, 0, 0.6, 1)
	moonDeactivate:SetScript("OnPlay", function(self)
		self:GetParent().glow.pulse:Stop()
	end)
	moonDeactivate:SetScript("OnFinished", function(self)
		local parent = self:GetParent()
		parent.moonBar:SetAlpha(0)
		parent.glow:SetAlpha(0)
		parent.darkSun:SetAlpha(0)
	end)
	frame.moonDeactivate = moonDeactivate

	-- Glow host: textures cannot host Scale pulse on some clients.
	-- Anchor host to the bar first, then reparent glow — never host↔glow mutual SetPoint.
	local glowHost = CreateFrame("Frame", nil, frame)
	glowHost:SetSize(43, 45)
	glowHost:SetPoint("CENTER")
	glowHost:SetFrameLevel(frame:GetFrameLevel() + 8)
	glowHost:EnableMouse(false)
	frame.glow:SetParent(glowHost)
	frame.glow:ClearAllPoints()
	frame.glow:SetAllPoints(glowHost)
	frame.glowHost = glowHost

	local pulse = glowHost:CreateAnimationGroup()
	if pulse.SetLooping then
		pulse:SetLooping("REPEAT")
	end
	CreateScaleAnim(pulse, glowHost, 1, 1, 1.08, 1.08, 0.5, 1, "IN_OUT")
	CreateScaleAnim(pulse, glowHost, 1.08, 1.08, 1, 1, 0.5, 2, "IN_OUT")
	frame.glow.pulse = pulse
end

local function StopEclipseAnims(self)
	if self.sunActivate then
		self.sunActivate:Stop()
	end
	if self.sunDeactivate then
		self.sunDeactivate:Stop()
	end
	if self.moonActivate then
		self.moonActivate:Stop()
	end
	if self.moonDeactivate then
		self.moonDeactivate:Stop()
	end
	if self.glow and self.glow.pulse then
		self.glow.pulse:Stop()
	end
end

local function AnchorGlow(self, side)
	local icon = side == "moon" and self.moon or self.sun
	ApplyIcon(self.glow, ECLIPSE_ICONS[side].big)
	if self.glowHost then
		self.glowHost:ClearAllPoints()
		self.glowHost:SetPoint("CENTER", icon, "CENTER")
		self.glowHost:SetSize(ECLIPSE_ICONS[side].big[1], ECLIPSE_ICONS[side].big[2])
	else
		self.glow:ClearAllPoints()
		self.glow:SetPoint("CENTER", icon, "CENTER")
	end
end

local function UpdateEclipsePower(self)
	local unit = GetPowerUnit()
	local powerType = GetBalanceType()
	local power = UnitPower(unit, powerType) or 0
	local maxPower = UnitPowerMax and UnitPowerMax(unit, powerType) or 0
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("DRUID") then
		power = maxPower > 0 and maxPower or 100
		maxPower = maxPower > 0 and maxPower or 100
	end
	if maxPower == 0 then
		return
	end
	local xpos = ECLIPSE_BAR_TRAVEL * (power / maxPower)
	-- EclipseBarFrameMixin:Update — CENTER offset only (travel ±38).
	self.marker:SetPoint("CENTER", xpos, 0)
	if self.powerText then
		local absPower = math.abs(power)
		local display = self.textDisplay
		if display == "BOTH" then
			self.powerText:SetText(string.format("(%d%%) %d / %d", math.abs(power / maxPower * 100), absPower, math.abs(maxPower)))
		elseif display == "PERCENT" then
			self.powerText:SetText(string.format("%d%%", math.abs(power / maxPower * 100)))
		else
			self.powerText:SetText(tostring(absPower))
		end
	end
end

local function HasAura(spellID)
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		return C_UnitAuras.GetPlayerAuraBySpellID(spellID) and true or false
	end
	return false
end

local function GetEclipseBuffState()
	local force = WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("DRUID")
	if force then
		return true, false
	end
	return HasAura(ECLIPSE_BAR_LUNAR_BUFF_ID), HasAura(ECLIPSE_BAR_SOLAR_BUFF_ID)
end

-- EclipseBarFrameMixin:OnShow — snap state + start pulse (no activate fade).
local function ApplyEclipseBuffsInstant(self)
	local hasLunar, hasSolar = GetEclipseBuffState()

	if hasLunar then
		AnchorGlow(self, "moon")
		self.sunBar:SetAlpha(0)
		self.darkMoon:SetAlpha(0)
		self.moonBar:SetAlpha(1)
		self.darkSun:SetAlpha(1)
		self.glow:SetAlpha(1)
		if self.glow.pulse and not self.glow.pulse:IsPlaying() then
			self.glow.pulse:Play()
		end
	elseif hasSolar then
		AnchorGlow(self, "sun")
		self.moonBar:SetAlpha(0)
		self.darkSun:SetAlpha(0)
		self.sunBar:SetAlpha(1)
		self.darkMoon:SetAlpha(1)
		self.glow:SetAlpha(1)
		if self.glow.pulse and not self.glow.pulse:IsPlaying() then
			self.glow.pulse:Play()
		end
	else
		self.sunBar:SetAlpha(0)
		self.moonBar:SetAlpha(0)
		self.darkSun:SetAlpha(0)
		self.darkMoon:SetAlpha(0)
		self.glow:SetAlpha(0)
		if self.glow.pulse then
			self.glow.pulse:Stop()
		end
	end

	self.hasLunarEclipse = hasLunar
	self.hasSolarEclipse = hasSolar
end

-- EclipseBarFrameMixin:CheckBuffs — activate/deactivate fades on aura change.
local function CheckEclipseBuffs(self)
	if not self:IsShown() then
		return
	end
	-- DevTools force-show: snap lunar side (skip activate/deactivate fades).
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("DRUID") then
		ApplyEclipseBuffsInstant(self)
		return
	end

	local hasLunar, hasSolar = GetEclipseBuffState()

	if hasLunar then
		AnchorGlow(self, "moon")
		if self.moonDeactivate:IsPlaying() then
			self.moonDeactivate:Stop()
		end
		if not self.moonActivate:IsPlaying() and hasLunar ~= self.hasLunarEclipse then
			self.moonActivate:Play()
		end
	else
		if self.moonActivate:IsPlaying() then
			self.moonActivate:Stop()
		end
		if not self.moonDeactivate:IsPlaying() and hasLunar ~= self.hasLunarEclipse then
			self.moonDeactivate:Play()
		end
	end

	if hasSolar then
		AnchorGlow(self, "sun")
		if self.sunDeactivate:IsPlaying() then
			self.sunDeactivate:Stop()
		end
		if not self.sunActivate:IsPlaying() and hasSolar ~= self.hasSolarEclipse then
			self.sunActivate:Play()
		end
	else
		if self.sunActivate:IsPlaying() then
			self.sunActivate:Stop()
		end
		if not self.sunDeactivate:IsPlaying() and hasSolar ~= self.hasSolarEclipse then
			self.sunDeactivate:Play()
		end
	end

	self.hasLunarEclipse = hasLunar
	self.hasSolarEclipse = hasSolar
end

local function SetMarkerDirection(self, direction)
	direction = direction or "none"
	local coords = ECLIPSE_MARKER_COORDS[direction] or ECLIPSE_MARKER_COORDS.none
	self.marker:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
end

local function RefreshEclipseVisibility(self)
	local show = ShouldDisplayEclipse()
	if show and OverrideActionBar and OverrideActionBar.IsShown and OverrideActionBar:IsShown() then
		show = WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("DRUID")
	end
	self:SetShown(show)
	if show then
		-- EclipseBarFrameMixin:UpdateShown — status text CVar gates power number.
		self.textDisplay = GetCVar and GetCVar("statusTextDisplay") or nil
		if GetCVarBool and GetCVarBool("playerStatusText") then
			self.powerText:Show()
			self.lockShow = true
		else
			self.powerText:Hide()
			self.lockShow = false
		end
		SetMarkerDirection(self, GetEclipseDirection and GetEclipseDirection())
		-- OnShow path: snap eclipse chrome (activate fades are UNIT_AURA only).
		StopEclipseAnims(self)
		ApplyEclipseBuffsInstant(self)
		UpdateEclipsePower(self)
	else
		StopEclipseAnims(self)
	end
	if WhoaUF.LayoutPlayerBottomFrames then
		WhoaUF:LayoutPlayerBottomFrames()
	end
end

function WhoaUF:RefreshEclipseBar()
	local frame = self.unitFrames and self.unitFrames.player and self.unitFrames.player.EclipseBar
	if frame then
		RefreshEclipseVisibility(frame)
	end
end

function WhoaUF:InitEclipseBar(playerFrame)
	if not playerFrame or playerFrame.EclipseBar then
		return
	end
	if not IsCataOrLater() then
		return
	end

	local frame = CreateFrame("Frame", "WhoaUFEclipseBar", playerFrame)
	frame:SetSize(140, 38)
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(playerFrame:GetFrameLevel() + 5)
	frame:EnableMouse(true)
	frame:SetHitRectInsets(4, 4, 6, 6)
	frame:Hide()

	-- Match Cata EclipseBarFrame.xml layering and anchors (not freehand ±38 icons).
	local sheet = GetEclipseTex()
	local function MakeTex(layer, subLevel, w, h)
		local t = frame:CreateTexture(nil, layer, nil, subLevel or 0)
		t:SetSize(w, h)
		t:SetTexture(sheet)
		return t
	end

	frame.bar = MakeTex("ARTWORK", 0, 140, 38)
	frame.bar:SetPoint("CENTER")
	frame.bar:SetTexCoord(0.00390625, 0.55078125, 0.63281250, 0.92968750)

	frame.sun = MakeTex("BACKGROUND", 0, 23, 23)
	ApplyIcon(frame.sun, ECLIPSE_ICONS.sun.norm)
	frame.sun:SetPoint("CENTER", frame.bar, "RIGHT", -17, 1)

	frame.moon = MakeTex("BACKGROUND", 0, 23, 23)
	ApplyIcon(frame.moon, ECLIPSE_ICONS.moon.norm)
	frame.moon:SetPoint("CENTER", frame.bar, "LEFT", 17, 1)

	frame.darkSun = MakeTex("BACKGROUND", 1, 23, 23)
	ApplyIcon(frame.darkSun, ECLIPSE_ICONS.sun.dark)
	frame.darkSun:SetPoint("CENTER", frame.sun)
	frame.darkSun:SetAlpha(0)

	frame.darkMoon = MakeTex("BACKGROUND", 1, 23, 23)
	ApplyIcon(frame.darkMoon, ECLIPSE_ICONS.moon.dark)
	frame.darkMoon:SetPoint("CENTER", frame.moon)
	frame.darkMoon:SetAlpha(0)

	frame.sunBar = MakeTex("ARTWORK", 1, 140, 38)
	frame.sunBar:SetPoint("CENTER")
	frame.sunBar:SetTexCoord(0.00390625, 0.55078125, 0.32031250, 0.61718750)
	frame.sunBar:SetAlpha(0)

	frame.moonBar = MakeTex("ARTWORK", 1, 140, 38)
	frame.moonBar:SetPoint("CENTER")
	frame.moonBar:SetTexCoord(0.00390625, 0.55078125, 0.00781250, 0.30468750)
	frame.moonBar:SetAlpha(0)

	frame.marker = MakeTex("OVERLAY", 0, 20, 20)
	frame.marker:SetPoint("CENTER", 0, 2)
	frame.marker:SetTexCoord(
		ECLIPSE_MARKER_COORDS.none[1],
		ECLIPSE_MARKER_COORDS.none[2],
		ECLIPSE_MARKER_COORDS.none[3],
		ECLIPSE_MARKER_COORDS.none[4]
	)
	frame.marker:SetBlendMode("ADD")

	frame.glow = MakeTex("OVERLAY", 0, 43, 45)
	ApplyIcon(frame.glow, ECLIPSE_ICONS.sun.big)
	frame.glow:SetPoint("CENTER")
	frame.glow:SetAlpha(0)

	BuildEclipseAnims(frame)

	frame.powerText = frame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.powerText:SetPoint("CENTER", 0, 0)
	frame.powerText:Hide()
	if WhoaUF.ApplyStatusBarTextFont then
		WhoaUF:ApplyStatusBarTextFont(frame.powerText)
	end
	frame:SetScript("OnEnter", function(self)
		self.powerText:Show()
		if GameTooltip_SetDefaultAnchor and GameTooltip and BALANCE then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
			GameTooltip:SetText(BALANCE, 1, 1, 1)
			if BALANCE_TOOLTIP then
				GameTooltip:AddLine(BALANCE_TOOLTIP, nil, nil, nil, true)
			end
			GameTooltip:Show()
		end
	end)
	frame:SetScript("OnLeave", function(self)
		if not self.lockShow then
			self.powerText:Hide()
		end
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)

	local function RegisterEclipseBarEvents(f)
		f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		f:RegisterEvent("PLAYER_TALENT_UPDATE")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("ECLIPSE_DIRECTION_CHANGE")
		f:RegisterEvent("CVAR_UPDATE")
		pcall(function()
			f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
		f:RegisterUnitEvent("UNIT_AURA", "player", "vehicle")
		f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "vehicle")
		f:RegisterUnitEvent("UNIT_MAXPOWER", "player", "vehicle")
	end
	self.RegisterEclipseBarEvents = RegisterEclipseBarEvents
	RegisterEclipseBarEvents(frame)

	frame:SetScript("OnEvent", function(self, event, unit, powerToken)
		if event == "UNIT_AURA" then
			if unit == GetPowerUnit() then
				CheckEclipseBuffs(self)
			end
		elseif event == "ECLIPSE_DIRECTION_CHANGE" then
			SetMarkerDirection(self, unit)
		elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
			if unit == GetPowerUnit() then
				UpdateEclipsePower(self)
			end
		else
			RefreshEclipseVisibility(self)
		end
	end)

	playerFrame.EclipseBar = frame
	frame.whoaClassPowerSheet = TEX_CLIENT
	RefreshEclipseVisibility(frame)
end

function WhoaUF:ApplyEclipseBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.EclipseBar
	if not frame then
		return
	end
	if self.ApplyClassPowerSheetRecursive then
		self:ApplyClassPowerSheetRecursive(frame, TEX_CLIENT)
	end
	-- SetTexture can drop ADD; restore marker blend after sheet swap.
	if frame.marker and frame.marker.SetBlendMode then
		frame.marker:SetBlendMode("ADD")
	end
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "DRUID",
		load = function()
			return WhoaUF:HasEclipseBar()
		end,
		init = function(uf, player)
			uf:InitEclipseBar(player)
		end,
		refresh = function(uf)
			uf:RefreshEclipseBar()
		end,
		applyArt = function(uf)
			uf:ApplyEclipseBarArt()
		end,
		frameKey = "EclipseBar",
		registerEvents = "RegisterEclipseBarEvents",
		layout = {
			slot = "bottom",
			order = 30,
			frameKey = "EclipseBar",
			style = "top",
			getAnchor = "GetEclipseBarAnchor",
			defaultX = 30,
			defaultY = 36,
		},
	})
end
