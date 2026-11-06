--[[
	Death Knight rune bar. Player frame chrome: Frames/DkPlayerArt.lua
]]

do
	if not WhoaUF:HasDeathKnight() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "DEATHKNIGHT" then
		return
	end
end

local MAX_RUNES = 6
local RUNETYPE_BLOOD = 1
local RUNETYPE_FROST = 2
local RUNETYPE_UNHOLY = 3
local RUNETYPE_DEATH = 4

local RUNE_VISUAL_IDS = { 1, 2, 5, 6, 3, 4 }
local ENERGIZE_EARLY_SECONDS = 0.5

local iconTextures = {
	[RUNETYPE_BLOOD] = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Blood",
	[RUNETYPE_FROST] = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Frost",
	[RUNETYPE_UNHOLY] = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Unholy",
	[RUNETYPE_DEATH] = "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Death",
}

local runeEnergizeTextures = {
	[RUNETYPE_BLOOD] = "Interface\\PlayerFrame\\Deathknight-Energize-Blood",
	[RUNETYPE_FROST] = "Interface\\PlayerFrame\\Deathknight-Energize-Frost",
	[RUNETYPE_UNHOLY] = "Interface\\PlayerFrame\\Deathknight-Energize-Unholy",
	[RUNETYPE_DEATH] = "Interface\\PlayerFrame\\Deathknight-Energize-White",
}

local function ClassPowerTex(clientPath)
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(clientPath)
	end
	return clientPath
end

local function RuneIconTex(runeType)
	return ClassPowerTex(iconTextures[runeType])
end

local function RuneEnergizeTex(runeType)
	return ClassPowerTex(runeEnergizeTextures[runeType])
end

local runeColors = {
	[RUNETYPE_BLOOD] = { 1, 0, 0 },
	[RUNETYPE_FROST] = { 0, 1, 1 },
	[RUNETYPE_UNHOLY] = { 0, 0.5, 0 },
	[RUNETYPE_DEATH] = { 0.8, 0.1, 1 },
}

local runeMapping = {
	[RUNETYPE_BLOOD] = "BLOOD",
	[RUNETYPE_FROST] = "FROST",
	[RUNETYPE_UNHOLY] = "UNHOLY",
	[RUNETYPE_DEATH] = "DEATH",
}

local function GetRuneLayout()
	if WhoaUF:IsWrathTypedRuneLayout() then
		return 10, 36, 25, -6, 22
	end
	return 36, 30, 0, 0, 18
end

function WhoaUF:GetRuneFrameAnchor()
	local x, y = GetRuneLayout()
	return x, y
end

local function IsDeathKnight()
	local _, class = UnitClass("player")
	return class == "DEATHKNIGHT"
end

local function ShouldShowRuneFrame()
	if not IsDeathKnight() then
		return false
	end
	if WhoaUF.IsVehiclePlayerArtActive and WhoaUF:IsVehiclePlayerArtActive() then
		return false
	end
	return true
end

local function ShineFadeIn(shine)
	if shine.shining then
		return
	end
	shine.shining = true
	local fadeInfo = {
		mode = "IN",
		timeToFade = 0.5,
		finishedFunc = function(s)
			s.shining = false
			UIFrameFadeOut(s, 0.5)
		end,
		finishedArg1 = shine,
	}
	UIFrameFade(shine, fadeInfo)
end

local function CreateAlphaAnim(group, target, fromAlpha, toAlpha, duration, order, startDelay, endDelay, smoothing)
	local anim = group:CreateAnimation("Alpha")
	anim:SetTarget(target)
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(toAlpha)
	anim:SetDuration(duration)
	anim:SetOrder(order or 1)
	if startDelay and anim.SetStartDelay then
		anim:SetStartDelay(startDelay)
	end
	if endDelay and anim.SetEndDelay then
		anim:SetEndDelay(endDelay)
	end
	if smoothing and anim.SetSmoothing then
		anim:SetSmoothing(smoothing)
	end
	return anim
end

local function CreateEnergizeAnim(btn, whiteGlow, colorGlow)
	local group = btn:CreateAnimationGroup()
	local scale = group:CreateAnimation("Scale")
	scale:SetTarget(whiteGlow)
	scale:SetDuration(0.15)
	scale:SetOrder(1)
	if scale.SetFromScale then
		scale:SetFromScale(1, 1)
		scale:SetToScale(4, 4)
	elseif scale.SetScale then
		scale:SetScale(4, 4)
	end
	if scale.SetEndDelay then
		scale:SetEndDelay(1)
	end
	CreateAlphaAnim(group, whiteGlow, 0, 1, 0.2, 1, nil, 1)
	CreateAlphaAnim(group, colorGlow, 0, 1, 0.1, 1, 0.3, 4, "IN_OUT")
	CreateAlphaAnim(group, whiteGlow, 1, 0, 0.1, 2, nil, nil, "IN_OUT")
	CreateAlphaAnim(group, colorGlow, 1, 0, 0.1, 2, nil, nil, "IN_OUT")
	return group
end

local function UpdateRuneButton(btn, dontFlash)
	local rune = btn:GetID()
	-- Mainline / untyped: show Death visual for every rune (no GetRuneType).
	if WhoaUF:HasUntypedRunes() then
		local runeType = RUNETYPE_DEATH
		if btn.colorOrb and runeEnergizeTextures[runeType] then
			btn.colorOrb:SetTexture(RuneEnergizeTex(runeType))
		end
		if iconTextures[runeType] then
			btn.rune:SetTexture(RuneIconTex(runeType))
			btn.rune:Show()
			btn.rune.runeType = runeType
			btn.tooltipText = _G.COMBAT_TEXT_RUNE_DEATH
		end
		return
	end

	if not GetRuneType then
		btn.rune:Hide()
		return
	end

	local runeType = GetRuneType(rune)
	if not dontFlash and runeType and runeType ~= btn.rune.runeType then
		local color = runeColors[runeType]
		if color then
			btn.shine:SetVertexColor(color[1], color[2], color[3])
			ShineFadeIn(btn.shine)
		end
	end

	if btn.colorOrb and runeType and runeEnergizeTextures[runeType] then
		btn.colorOrb:SetTexture(RuneEnergizeTex(runeType))
	end

	if runeType and iconTextures[runeType] then
		btn.rune:SetTexture(RuneIconTex(runeType))
		btn.rune:Show()
		btn.rune.runeType = runeType
		local key = runeMapping[runeType]
		btn.tooltipText = key and _G["COMBAT_TEXT_RUNE_" .. key] or nil
	else
		btn.rune:Hide()
		btn.tooltipText = nil
	end
end

local function UpdateRuneCooldown(btn, allowReadyFlash, isEnergize)
	local rune = btn:GetID()
	local start, duration, runeReady = GetRuneCooldown(rune)
	local cooldown = btn.cooldown

	-- Mainline: cooldown fields may be secrets — drive C API only (no Lua compare / flash).
	if WhoaUF.NeedsSecretSafeNumberOps
		and WhoaUF:NeedsSecretSafeNumberOps(start, duration, runeReady, isEnergize)
	then
		if CooldownFrame_Set then
			CooldownFrame_Set(cooldown, start, duration, true, true)
		elseif cooldown.Clear then
			cooldown:Clear()
		else
			cooldown:Hide()
		end
		return
	end

	if not runeReady and start and start > 0 and duration and duration > 0 then
		CooldownFrame_Set(cooldown, start, duration, 1, true)
		if btn.energize then
			btn.energize:Stop()
		end
		btn.wasReady = false
		btn.cooldownEnd = start + duration
	else
		cooldown:Hide()
		if allowReadyFlash and runeReady and btn.wasReady == false then
			btn.shine:SetVertexColor(1, 1, 1)
			ShineFadeIn(btn.shine)
			-- Mainline: RUNE_POWER_UPDATE "added" is secret; a rune ready well before
			-- its cooldown end was energized (e.g. Empower Rune Weapon).
			if isEnergize == nil and btn.cooldownEnd
				and GetTime() < btn.cooldownEnd - ENERGIZE_EARLY_SECONDS
			then
				isEnergize = true
			end
		end
		if isEnergize and runeReady and btn.energize then
			btn.energize:Play()
		end
		btn.wasReady = not not runeReady
		btn.cooldownEnd = nil
	end
end

local function StackRuneButtonLevels(btn)
	local level = btn:GetFrameLevel()
	btn.cooldown:SetFrameLevel(level + 1)
	btn.border:SetFrameLevel(level + 2)
	btn.shineFrame:SetFrameLevel(level + 3)
	btn.glowFrame:SetFrameLevel(level + 4)
end

local function CreateRuneButton(parent, runeId)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(18, 18)
	btn:SetID(runeId)

	local rune = btn:CreateTexture(nil, "ARTWORK")
	rune:SetSize(24, 24)
	rune:SetPoint("CENTER", 0, -1)
	btn.rune = rune

	local cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
	cooldown:SetSize(15, 15)
	cooldown:SetPoint("CENTER", 0, -1)
	if cooldown.SetDrawEdge then
		cooldown:SetDrawEdge(true)
	end
	if cooldown.SetUseCircularEdge then
		cooldown:SetUseCircularEdge(true)
	end
	if cooldown.SetHideCountdownNumbers then
		cooldown:SetHideCountdownNumbers(true)
	end
	if cooldown.SetDrawBling then
		cooldown:SetDrawBling(false)
	end
	btn.cooldown = cooldown

	local border = CreateFrame("Frame", nil, btn)
	border:SetSize(24, 24)
	border:SetPoint("CENTER", 0, -1)
	btn.border = border
	local borderTex = border:CreateTexture(nil, "OVERLAY")
	borderTex:SetAllPoints()
	borderTex:SetTexture(ClassPowerTex("Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Ring"))
	borderTex:SetVertexColor(0.6, 0.6, 0.6, 1)
	btn.borderTex = borderTex

	-- Shine + energize glows sit on child frames so they draw above ring + cooldown.
	local shineFrame = CreateFrame("Frame", nil, btn)
	shineFrame:SetAllPoints()
	btn.shineFrame = shineFrame

	local shine = shineFrame:CreateTexture(nil, "OVERLAY")
	shine:SetSize(60, 35)
	shine:SetPoint("CENTER")
	shine:SetTexture(ClassPowerTex("Interface\\ComboFrame\\ComboPoint"))
	shine:SetTexCoord(0.5625, 1, 0, 1)
	shine:SetBlendMode("ADD")
	shine:Hide()
	btn.shine = shine

	local glowFrame = CreateFrame("Frame", nil, btn)
	glowFrame:SetAllPoints()
	btn.glowFrame = glowFrame

	local whiteGlow = glowFrame:CreateTexture(nil, "OVERLAY")
	whiteGlow:SetDrawLayer("OVERLAY", -1)
	whiteGlow:SetSize(8, 8)
	whiteGlow:SetPoint("CENTER", 0, -1)
	whiteGlow:SetTexture(ClassPowerTex("Interface\\PlayerFrame\\Deathknight-Energize-White"))
	whiteGlow:SetAlpha(0)
	btn.whiteGlow = whiteGlow

	local colorOrb = glowFrame:CreateTexture(nil, "OVERLAY")
	colorOrb:SetSize(32, 32)
	colorOrb:SetPoint("CENTER", 0, -1)
	colorOrb:SetTexture(RuneEnergizeTex(RUNETYPE_BLOOD))
	colorOrb:SetAlpha(0)
	btn.colorOrb = colorOrb

	btn.energize = CreateEnergizeAnim(btn, whiteGlow, colorOrb)
	StackRuneButtonLevels(btn)

	btn:SetScript("OnEnter", function(self)
		if self.tooltipText then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltipText)
			GameTooltip:Show()
		end
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return btn
end

local function ApplyRuneButtonArt(btn)
	if not btn then
		return
	end
	if btn.borderTex then
		btn.borderTex:SetTexture(ClassPowerTex("Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-Ring"))
	end
	if btn.shine then
		btn.shine:SetTexture(ClassPowerTex("Interface\\ComboFrame\\ComboPoint"))
	end
	if btn.whiteGlow then
		btn.whiteGlow:SetTexture(ClassPowerTex("Interface\\PlayerFrame\\Deathknight-Energize-White"))
	end
	local runeType = (btn.rune and btn.rune.runeType) or RUNETYPE_BLOOD
	if btn.colorOrb then
		btn.colorOrb:SetTexture(RuneEnergizeTex(runeType))
	end
	if btn.rune and iconTextures[runeType] then
		btn.rune:SetTexture(RuneIconTex(runeType))
	end
end

local function LayoutStockRunes(runeFrame)
	if not runeFrame or not runeFrame.runes then
		return
	end
	local _, _, buttonX, buttonY = GetRuneLayout()
	runeFrame:SetScale(1)
	local prev
	for i = 1, MAX_RUNES do
		local btn = runeFrame.runes[RUNE_VISUAL_IDS[i]]
		if btn then
			btn:SetScale(1)
			btn:ClearAllPoints()
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", 3, 0)
			else
				btn:SetPoint("LEFT", runeFrame, "LEFT", buttonX, buttonY)
			end
			prev = btn
		end
	end
end

local function LayoutDkAlphaRunes(runeFrame, scale, spacing, buttonX, buttonY)
	if not runeFrame or not runeFrame.runes then
		return
	end
	scale = scale or 1
	spacing = spacing or 7
	buttonX = buttonX or 0
	buttonY = buttonY or 0
	runeFrame:SetScale(1)
	local prev
	for i = 1, MAX_RUNES do
		local btn = runeFrame.runes[RUNE_VISUAL_IDS[i]]
		if btn then
			btn:SetScale(scale)
			btn:ClearAllPoints()
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
			else
				btn:SetPoint("LEFT", runeFrame, "LEFT", buttonX, buttonY)
			end
			prev = btn
		end
	end
end

function WhoaUF:AnchorRuneFrame()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.RuneFrame
	if not frame or not frame:IsShown() then
		return
	end

	self:ReparentClassPowerBarIfNeeded(frame)
	frame:ClearAllPoints()

	-- Alpha / BlizzCon: LEFT of player (DkPlayerArt X/Y). Stock: TOP of bottom slot.
	if self.IsDkAlphaPlayerArtActive and self:IsDkAlphaPlayerArtActive(player) and self.GetDkAlphaRuneLayout then
		local x, y, scale, spacing, buttonX, buttonY = self:GetDkAlphaRuneLayout()
		frame:SetPoint("LEFT", player, "LEFT", x, y)
		LayoutDkAlphaRunes(frame, scale, spacing, buttonX, buttonY)
	elseif self.IsDkBlizzconPlayerArtActive and self:IsDkBlizzconPlayerArtActive(player) and self.GetDkBlizzconRuneLayout then
		local x, y, scale, spacing, buttonX, buttonY = self:GetDkBlizzconRuneLayout()
		frame:SetPoint("LEFT", player, "LEFT", x, y)
		LayoutDkAlphaRunes(frame, scale, spacing, buttonX, buttonY)
	else
		local anchorX, anchorY, _, _, height = GetRuneLayout()
		frame:SetScale(1)
		frame:SetSize(130, height)
		local anchorFrame = self:GetClassPowerAnchorFrame() or player
		frame:SetPoint("TOP", anchorFrame, "BOTTOM", anchorX, anchorY)
		LayoutStockRunes(frame)
	end

	self:ApplyClassPowerFrameLevel(frame)
	for i = 1, MAX_RUNES do
		local btn = frame.runes[i]
		if btn then
			StackRuneButtonLevels(btn)
		end
	end
end

local function RefreshAllRunes(frame, dontFlash, allowReadyFlash)
	if not frame then
		return
	end
	for i = 1, MAX_RUNES do
		local btn = frame.runes[i]
		if btn then
			UpdateRuneButton(btn, dontFlash)
			UpdateRuneCooldown(btn, allowReadyFlash)
		end
	end
end

function WhoaUF:InitRuneFrame(playerFrame)
	if not playerFrame or playerFrame.RuneFrame then
		return
	end
	if not GetRuneCooldown then
		return
	end

	local anchorX, anchorY, buttonX, buttonY, height = GetRuneLayout()

	local frame = CreateFrame("Frame", "WhoaUFRuneFrame", playerFrame)
	frame:SetSize(130, height)
	frame:SetPoint("TOP", playerFrame, "BOTTOM", anchorX, anchorY)
	frame:SetFrameStrata("LOW")
	frame.runes = {}

	local prev
	for i = 1, MAX_RUNES do
		local btn = CreateRuneButton(frame, RUNE_VISUAL_IDS[i])
		if prev then
			btn:SetPoint("LEFT", prev, "RIGHT", 3, 0)
		else
			btn:SetPoint("LEFT", frame, "LEFT", buttonX, buttonY)
		end
		frame.runes[RUNE_VISUAL_IDS[i]] = btn
		prev = btn
	end

	playerFrame.RuneFrame = frame

	frame:SetScript("OnEvent", function(self, event, ...)
		if not IsDeathKnight() then
			self:Hide()
			WhoaUF:ApplyDeathKnightPlayerArt(playerFrame)
			if WhoaUF.LayoutPlayerBottomFrames then
				WhoaUF:LayoutPlayerBottomFrames()
			end
			return
		end

		if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
			if ShouldShowRuneFrame() then
				self:Show()
				WhoaUF:ApplyDeathKnightPlayerArt(playerFrame)
				RefreshAllRunes(self, true)
				if WhoaUF.LayoutPlayerBottomFrames then
					WhoaUF:LayoutPlayerBottomFrames()
				end
			else
				self:Hide()
				if WhoaUF.LayoutPlayerBottomFrames then
					WhoaUF:LayoutPlayerBottomFrames()
				end
			end
		elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
			if ShouldShowRuneFrame() then
				self:Show()
				WhoaUF:ApplyDeathKnightPlayerArt(playerFrame)
				RefreshAllRunes(self, true)
				if WhoaUF.LayoutPlayerBottomFrames then
					WhoaUF:LayoutPlayerBottomFrames()
				end
			else
				self:Hide()
				if WhoaUF.LayoutPlayerBottomFrames then
					WhoaUF:LayoutPlayerBottomFrames()
				end
			end
		elseif event == "RUNE_POWER_UPDATE" then
			local runeIndex, flag = ...
			-- Mainline: event index is secret — cannot index runes[]; refresh all
			-- (Blizzard RuneFrameMixin:UpdateRunes ignores the payload too).
			if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(runeIndex) then
				RefreshAllRunes(self, false, true)
			else
				local btn = runeIndex and self.runes[runeIndex]
				if btn then
					UpdateRuneCooldown(btn, true, flag)
				end
			end
			if WhoaUF.UpdateDkAlphaRunicPower then
				WhoaUF:UpdateDkAlphaRunicPower(playerFrame)
			end
		elseif event == "RUNE_TYPE_UPDATE" then
			local runeIndex = ...
			if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(runeIndex) then
				RefreshAllRunes(self, true)
			else
				local btn = runeIndex and self.runes[runeIndex]
				if btn then
					UpdateRuneButton(btn)
				end
			end
		end
	end)

	local function RegisterRuneFrameEvents(f)
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("RUNE_POWER_UPDATE")
		pcall(function()
			f:RegisterEvent("RUNE_TYPE_UPDATE")
		end)
		pcall(function()
			f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
		pcall(function()
			f:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
			f:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
		end)
	end
	self.RegisterRuneFrameEvents = RegisterRuneFrameEvents
	RegisterRuneFrameEvents(frame)

	if ShouldShowRuneFrame() then
		frame:Show()
		RefreshAllRunes(frame, true)
	else
		frame:Hide()
	end

	if WhoaUF.LayoutPlayerBottomFrames then
		WhoaUF:LayoutPlayerBottomFrames()
	end
end

local function ApplyAllRuneArt(frame)
	if not frame or not frame.runes then
		return
	end
	for i = 1, MAX_RUNES do
		ApplyRuneButtonArt(frame.runes[RUNE_VISUAL_IDS[i]] or frame.runes[i])
	end
end

function WhoaUF:ApplyRuneFrameArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.RuneFrame
	if not frame then
		return
	end
	ApplyAllRuneArt(frame)
	RefreshAllRunes(frame, true)
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "DEATHKNIGHT",
		load = function()
			return GetRuneCooldown ~= nil
		end,
		init = function(uf, player)
			uf:InitRuneFrame(player)
		end,
		refresh = function(uf)
			local player = uf.unitFrames and uf.unitFrames.player
			local frame = player and player.RuneFrame
			if not frame then
				return
			end
			if ShouldShowRuneFrame() then
				frame:Show()
				uf:ApplyDeathKnightPlayerArt(player)
				RefreshAllRunes(frame, true)
				if uf.LayoutPlayerBottomFrames then
					uf:LayoutPlayerBottomFrames()
				end
			else
				frame:Hide()
				uf:ApplyDeathKnightPlayerArt(player)
			end
		end,
		applyArt = function(uf)
			uf:ApplyRuneFrameArt()
		end,
		frameKey = "RuneFrame",
		registerEvents = "RegisterRuneFrameEvents",
		layout = {
			slot = "bottom",
			order = 10,
			frameKey = "RuneFrame",
			anchor = "AnchorRuneFrame",
		},
	})
end
