--[[
	Paladin Holy Power bar on Whoa player frame.
	Reference: reference/Blizzard_UnitFrame/Cata/PaladinPowerBar.lua|.xml
	           reference/Blizzard_UnitFrame/Mists/PaladinPowerBar.lua|.xml
]]

do
	if not WhoaUF:HasHolyPower() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "PALADIN" then
		return
	end
end

local HOLY_POWER_FULL = 3
local PALADINPOWERBAR_SHOW_LEVEL = 9
local TEX_CLIENT = "Interface\\PlayerFrame\\PaladinPowerTextures"

local function GetPaladinTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(TEX_CLIENT)
	end
	return TEX_CLIENT
end

local function IsMistsArt()
	return WhoaUF:HasMoPArt()
end

local function IsCataOrLater()
	return WhoaUF:HasHolyPower()
end

local function GetHolyPowerType()
	return (Enum and Enum.PowerType and Enum.PowerType.HolyPower) or 9
end

local function GetPowerUnit()
	local player = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	return (player and player.unit) or "player"
end

local function IsPaladin()
	local _, class = UnitClass("player")
	return class == "PALADIN"
end

function WhoaUF:GetPaladinPowerBarAnchor()
	-- Cata/Mists PaladinPowerBar.xml: TOP→BOTTOM (25, 35).
	return 25, 35
end

local function CreateAlphaAnim(group, fromAlpha, toAlpha, duration, order, startDelay)
	local anim = group:CreateAnimation("Alpha")
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(toAlpha)
	anim:SetDuration(duration)
	anim:SetOrder(order or 1)
	if startDelay and anim.SetStartDelay then
		anim:SetStartDelay(startDelay)
	end
	return anim
end

local function CreateHolyRune(parent, sizeW, sizeH, texCoords, drawLayer, subLevel)
	local rune = CreateFrame("Frame", nil, parent, "WhoaUFHolyPowerRuneTemplate")
	rune:SetSize(sizeW, sizeH)
	if rune.Texture then
		-- Fill the rune frame; a single-point anchor would size to the full atlas.
		rune.Texture:ClearAllPoints()
		rune.Texture:SetAllPoints(rune)
		rune.Texture:SetTexture(GetPaladinTex())
		rune.Texture:SetTexCoord(texCoords[1], texCoords[2], texCoords[3], texCoords[4])
		if drawLayer and rune.Texture.SetDrawLayer then
			rune.Texture:SetDrawLayer(drawLayer, subLevel or 0)
		end
	end
	return rune
end

local function ToggleHolyRune(rune, currentlyVisible)
	if currentlyVisible then
		if rune.activate:IsPlaying() then
			rune.activate:Stop()
		end
		rune.deactivate:Play()
	else
		if rune.deactivate:IsPlaying() then
			rune.deactivate:Stop()
		end
		rune.activate:Play()
	end
end

local function SetRuneVisible(rune, visible, instant)
	if rune.activate:IsPlaying() then
		rune.activate:Stop()
	end
	if rune.deactivate:IsPlaying() then
		rune.deactivate:Stop()
	end
	if instant then
		rune:SetAlpha(visible and 1 or 0)
		return
	end
	local isShown = rune:GetAlpha() > 0
	if isShown ~= visible then
		ToggleHolyRune(rune, isShown)
	end
end

local function UpdatePaladinPowerBar(self, instant)
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("PALADIN") then
		local runeCount = self.runeCount or HOLY_POWER_FULL
		for i = 1, runeCount do
			local rune = self["rune" .. i]
			if rune then
				SetRuneVisible(rune, true, true)
			end
		end
		if self.bankBG and runeCount > HOLY_POWER_FULL then
			self.bankBG:SetAlpha(1)
		end
		self.glow.pulse.stopPulse = false
		if not self.glow.pulse:IsPlaying() then
			self.glow.pulse:Play()
		end
		return
	end

	if self.delayedUpdate then
		return
	end

	local unit = GetPowerUnit()
	local powerType = GetHolyPowerType()
	local numHolyPower = UnitPower(unit, powerType)
	local maxHolyPower = UnitPowerMax and UnitPowerMax(unit, powerType)
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(numHolyPower, maxHolyPower) then
		return
	end
	numHolyPower = numHolyPower or 0
	maxHolyPower = maxHolyPower or HOLY_POWER_FULL
	if not maxHolyPower or maxHolyPower < 1 then
		maxHolyPower = HOLY_POWER_FULL
	end

	-- MoP: bank drain spends 3 HP while leaving bank runes lit briefly.
	if not instant and self.lastPower and self.lastPower > HOLY_POWER_FULL and numHolyPower == self.lastPower - HOLY_POWER_FULL then
		for i = 1, HOLY_POWER_FULL do
			local rune = self["rune" .. i]
			if rune then
				SetRuneVisible(rune, false, false)
			end
		end
		self.lastPower = nil
		self.delayedUpdate = 0.5
		self:SetScript("OnUpdate", function(frame, elapsed)
			frame.delayedUpdate = frame.delayedUpdate - elapsed
			if frame.delayedUpdate <= 0 then
				frame.delayedUpdate = nil
				frame:SetScript("OnUpdate", nil)
				UpdatePaladinPowerBar(frame)
			end
		end)
		return
	end

	local runeCount = self.runeCount or HOLY_POWER_FULL
	for i = 1, runeCount do
		local holyRune = self["rune" .. i]
		if holyRune then
			if i > maxHolyPower then
				SetRuneVisible(holyRune, false, true)
			else
				if holyRune.deactivate:IsPlaying() and numHolyPower >= 1 then
					holyRune.deactivate:Stop()
					holyRune:SetAlpha(1)
				end
				SetRuneVisible(holyRune, i <= numHolyPower, instant)
			end
		end
	end

	if numHolyPower >= HOLY_POWER_FULL then
		self.glow.pulse.stopPulse = false
		if not self.glow.pulse:IsPlaying() then
			self.glow.pulse:Play()
		end
	else
		self.glow.pulse.stopPulse = true
	end

	if self.bankBG then
		local wantBank = maxHolyPower > HOLY_POWER_FULL
		if wantBank and self.bankBG:GetAlpha() < 1 and self.showBankAnim and not self.showBankAnim:IsPlaying() then
			self.showBankAnim:Play()
		elseif not wantBank then
			if self.showBankAnim then
				self.showBankAnim:Stop()
			end
			self.bankBG:SetAlpha(0)
		end
	end
	self.maxHolyPower = maxHolyPower
	self.lastPower = numHolyPower
end

local function RefreshPaladinPowerBarVisibility(self)
	local force = WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("PALADIN")
	if force then
		self:UnregisterEvent("PLAYER_LEVEL_UP")
		self:Show()
		self:SetAlpha(1)
		UpdatePaladinPowerBar(self, true)
		if WhoaUF.LayoutPlayerBottomFrames then
			WhoaUF:LayoutPlayerBottomFrames()
		end
		return
	end

	if not IsPaladin() or not IsCataOrLater() then
		self:Hide()
		if WhoaUF.LayoutPlayerBottomFrames then
			WhoaUF:LayoutPlayerBottomFrames()
		end
		return
	end

	-- Blizzard: Shown+Alpha(0) below show level (reserves layout gap). Whoa: Hide until
	-- unlock, then showAnim + Layout so pet only moves when the bar appears.
	local level = UnitLevel("player") or 1
	if level < PALADINPOWERBAR_SHOW_LEVEL then
		self:Hide()
		self:SetAlpha(0)
		self:RegisterEvent("PLAYER_LEVEL_UP")
		if WhoaUF.LayoutPlayerBottomFrames then
			WhoaUF:LayoutPlayerBottomFrames()
		end
		return
	end

	self:UnregisterEvent("PLAYER_LEVEL_UP")
	self:Show()
	if self:GetAlpha() < 1 and not (self.showAnim and self.showAnim:IsPlaying()) then
		self:SetAlpha(1)
	end
	UpdatePaladinPowerBar(self, true)
	if WhoaUF.LayoutPlayerBottomFrames then
		WhoaUF:LayoutPlayerBottomFrames()
	end
end

function WhoaUF:RefreshPaladinPowerBar()
	local frame = self.unitFrames and self.unitFrames.player and self.unitFrames.player.PaladinPowerBar
	if frame then
		RefreshPaladinPowerBarVisibility(frame)
	end
end

local function BuildBar(playerFrame, mists)
	local frame = CreateFrame("Frame", "WhoaUFPaladinPowerBar", playerFrame)
	frame:SetSize(136, 39)
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(playerFrame:GetFrameLevel() + 5)
	frame:EnableMouse(true)
	frame:SetHitRectInsets(17, 17, 7, 4)
	frame.runeCount = mists and 5 or 3

	local showAnim = frame:CreateAnimationGroup()
	CreateAlphaAnim(showAnim, 0, 1, 0.5, 1)
	showAnim:SetScript("OnFinished", function(self)
		self:GetParent():SetAlpha(1)
	end)
	frame.showAnim = showAnim

	if mists then
		local bankHolder = CreateFrame("Frame", nil, frame)
		bankHolder:SetSize(69, 16)
		bankHolder:SetPoint("TOP", 0, -29)
		bankHolder:SetAlpha(0)
		local bankBG = bankHolder:CreateTexture(nil, "BACKGROUND")
		bankBG:SetAllPoints()
		bankBG:SetTexture(GetPaladinTex())
		bankBG:SetTexCoord(0.00390625, 0.27343750, 0.64843750, 0.77343750)
		frame.bankBG = bankHolder

		local showBankAnim = bankHolder:CreateAnimationGroup()
		CreateAlphaAnim(showBankAnim, 0, 1, 0.5, 1)
		showBankAnim:SetScript("OnFinished", function(self)
			self:GetParent():SetAlpha(1)
		end)
		frame.showBankAnim = showBankAnim
	end

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(136, 39)
	bg:SetPoint("TOP")
	bg:SetTexture(GetPaladinTex())
	if mists then
		bg:SetTexCoord(0.00390625, 0.53515625, 0.00781250, 0.31250000)
	else
		bg:SetTexCoord(0.00390625, 0.53515625, 0.32812500, 0.63281250)
	end
	frame.bg = bg

	-- MoP/Cata PaladinPowerBar.xml: glow texture is 136x39 TOP (not full-atlas).
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetAllPoints(frame)
	local glowTex = glow:CreateTexture(nil, "BACKGROUND", nil, -1)
	glowTex:SetSize(136, 39)
	glowTex:SetPoint("TOP", glow, "TOP")
	glowTex:SetTexture(GetPaladinTex())
	if mists then
		glowTex:SetTexCoord(0.00390625, 0.53515625, 0.32812500, 0.63281250)
	else
		glowTex:SetTexCoord(0.00390625, 0.53515625, 0.00781250, 0.31250000)
	end
	glow:SetAlpha(0)
	glow.texture = glowTex
	frame.glow = glow

	local pulse = glow:CreateAnimationGroup()
	CreateAlphaAnim(pulse, 0, 1, 0.5, 1)
	CreateAlphaAnim(pulse, 1, 0, 0.6, 2, 0.3)
	pulse:SetScript("OnFinished", function(self)
		if not self.stopPulse then
			self:Play()
		end
	end)
	glow.pulse = pulse

	local runeSpecs
	if mists then
		runeSpecs = {
			{ 36, 22, { 0.00390625, 0.14453125, 0.78906250, 0.96093750 }, "TOPLEFT", frame, 21, -11 },
			{ 31, 17, { 0.15234375, 0.27343750, 0.78906250, 0.92187500 }, "LEFT", "prev", 0, 0 },
			{ 27, 21, { 0.28125000, 0.38671875, 0.64843750, 0.81250000 }, "LEFT", "prev", 2, -1 },
			{ 27, 12, { 0.28125000, 0.38671875, 0.82812500, 0.92187500 }, "TOPLEFT", frame, 43, -28, "BACKGROUND", -6 },
			{ 26, 12, { 0.39453125, 0.49609375, 0.64843750, 0.74218750 }, "TOPLEFT", frame, 67, -28, "BACKGROUND", -6 },
		}
	else
		runeSpecs = {
			{ 36, 22, { 0.00390625, 0.14453125, 0.64843750, 0.82031250 }, "TOPLEFT", frame, 21, -11 },
			{ 31, 17, { 0.00390625, 0.12500000, 0.83593750, 0.96875000 }, "LEFT", "prev", 0, 0 },
			{ 27, 21, { 0.15234375, 0.25781250, 0.64843750, 0.81250000 }, "LEFT", "prev", 2, -1 },
		}
	end

	local prev
	for i, spec in ipairs(runeSpecs) do
		local rune = CreateHolyRune(frame, spec[1], spec[2], spec[3], spec[8], spec[9])
		if spec[5] == "prev" then
			rune:SetPoint(spec[4], prev, "RIGHT", spec[6], spec[7])
		else
			rune:SetPoint(spec[4], frame, spec[4], spec[6], spec[7])
		end
		frame["rune" .. i] = rune
		prev = rune
	end

	frame:SetScript("OnEnter", function(self)
		if GameTooltip_SetDefaultAnchor then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		GameTooltip:SetText(HOLY_POWER or "Holy Power", 1, 1, 1)
		if HOLY_POWER_TOOLTIP then
			GameTooltip:AddLine(HOLY_POWER_TOOLTIP, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return frame
end

function WhoaUF:InitPaladinPowerBar(playerFrame)
	if not playerFrame or playerFrame.PaladinPowerBar then
		return
	end
	if not IsPaladin() or not IsCataOrLater() then
		return
	end

	local frame = BuildBar(playerFrame, IsMistsArt())
	local anchorX, anchorY = self:GetPaladinPowerBarAnchor()
	frame:SetPoint("TOP", playerFrame, "BOTTOM", anchorX, anchorY)

	frame:SetScript("OnEvent", function(self, event, arg1, arg2)
		if event == "PLAYER_LEVEL_UP" then
			local level = arg1
			if level and level >= PALADINPOWERBAR_SHOW_LEVEL then
				self:UnregisterEvent("PLAYER_LEVEL_UP")
				self:Show()
				self:SetAlpha(0)
				self.showAnim:Play()
				UpdatePaladinPowerBar(self)
				if WhoaUF.LayoutPlayerBottomFrames then
					WhoaUF:LayoutPlayerBottomFrames()
				end
			end
			return
		end

		if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_LOGIN" or event == "UNIT_DISPLAYPOWER" then
			RefreshPaladinPowerBarVisibility(self)
			return
		end

		if (event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT") then
			local unit = GetPowerUnit()
			if arg1 == unit or arg1 == "player" then
				if arg2 == "HOLY_POWER" or arg2 == GetHolyPowerType() then
					UpdatePaladinPowerBar(self)
				end
			end
		end
	end)

	local function RegisterPaladinPowerBarEvents(f)
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("PLAYER_LOGIN")
		f:RegisterEvent("UNIT_DISPLAYPOWER")
		f:RegisterEvent("UNIT_POWER_UPDATE")
		pcall(function()
			f:RegisterEvent("UNIT_POWER_FREQUENT")
		end)
	end
	self.RegisterPaladinPowerBarEvents = RegisterPaladinPowerBarEvents
	RegisterPaladinPowerBarEvents(frame)

	playerFrame.PaladinPowerBar = frame
	frame.whoaClassPowerSheet = TEX_CLIENT
	RefreshPaladinPowerBarVisibility(frame)
end

function WhoaUF:ApplyPaladinPowerBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.PaladinPowerBar
	if not frame then
		return
	end
	if self.ApplyClassPowerSheetRecursive then
		self:ApplyClassPowerSheetRecursive(frame, TEX_CLIENT)
	end
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "PALADIN",
		init = function(uf, player)
			uf:InitPaladinPowerBar(player)
		end,
		refresh = function(uf)
			uf:RefreshPaladinPowerBar()
		end,
		applyArt = function(uf)
			uf:ApplyPaladinPowerBarArt()
		end,
		frameKey = "PaladinPowerBar",
		registerEvents = "RegisterPaladinPowerBarEvents",
		layout = {
			slot = "bottom",
			order = 20,
			frameKey = "PaladinPowerBar",
			style = "top",
			getAnchor = "GetPaladinPowerBarAnchor",
			defaultX = 25,
			defaultY = 35,
		},
	})
end
