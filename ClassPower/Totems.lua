--[[
	Player totem bar (shaman / others with totems).
	Reference: Blizzard_UnitFrame Classic + Mainline TotemFrame.xml / TotemFrame.lua
	Note: stock TotemFrame parents to PlayerFrame, not TargetFrame.

	Mainline stock uses a reverse Icon.Cooldown swipe + duration text; Classic stock
	is text-only. Whoa always draws the swipe (CooldownFrame_Set from GetTotemInfo
	startTime/duration) so short totems like Capacitor (~2s) remain readable.

	Mainline / Forever: GetTotemInfo / GetTotemTimeLeft may return secrets
	(SecretWhenTotemSlotSecret). Tainted code must not boolean-test haveTotem,
	compare duration, or ceil timeLeft — use CanAccessValue / IsAccessibleTrue,
	and prefer GetTotemDuration. IsZero only means an empty (zero-span) slot;
	after the lifetime ends use HasExpired / IsActive — otherwise icons stick
	when the cooldown swipe finishes but the slot has not cleared yet.
	CooldownFrame_Set accepts secret start/duration (same pattern as Runes.lua).
]]

do
	-- Class gate is RegisterClassBar (not file load) so UnitClass timing at
	-- ADDON_LOADED cannot skip defining Init/Refresh. Forever shamans included.
	if not WhoaUF:HasTotemFrame() then
		return
	end
end

local MAX_TOTEM_SLOTS = MAX_TOTEMS or 4

local function GetTotemPriorities()
	local _, class = UnitClass("player")
	if class == "SHAMAN" and SHAMAN_TOTEM_PRIORITIES then
		return SHAMAN_TOTEM_PRIORITIES
	end
	return STANDARD_TOTEM_PRIORITIES or { 1, 2, 3, 4 }
end

local function FormatTotemDuration(seconds)
	-- Caller must pass an accessible number (never secrets).
	seconds = math.ceil(seconds or 0)
	if seconds >= 60 then
		return string.format("%dm", math.floor(seconds / 60))
	elseif seconds > 0 then
		return string.format("%d s", seconds)
	end
	return ""
end

local function ClearTotemDurationText(btn)
	if btn.lastDurationText ~= "" then
		btn.lastDurationText = ""
		btn.Duration:SetText("")
	end
	btn.Duration:Hide()
end

-- Mainline TotemFrame: reverse Cooldown swipe (Classic stock is text-only).
local function ClearTotemButtonCooldown(btn)
	local cd = btn.Cooldown
	if not cd then
		return
	end
	btn.whoaCdStart = nil
	btn.whoaCdDuration = nil
	if CooldownFrame_Set then
		CooldownFrame_Set(cd, 0, 0, false)
	elseif cd.Clear then
		cd:Clear()
	end
	cd:Hide()
end

local function SetTotemButtonCooldown(btn, startTime, duration)
	local cd = btn.Cooldown
	if not cd or not CooldownFrame_Set then
		return
	end

	-- Secrets: drive C API only — no Lua compare / coalesce.
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(startTime, duration) then
		btn.whoaCdStart = nil
		btn.whoaCdDuration = nil
		CooldownFrame_Set(cd, startTime, duration, true)
		cd:Show()
		return
	end

	duration = duration or 0
	startTime = startTime or 0
	if duration > 0 then
		if btn.whoaCdStart == startTime and btn.whoaCdDuration == duration then
			return
		end
		btn.whoaCdStart = startTime
		btn.whoaCdDuration = duration
		CooldownFrame_Set(cd, startTime, duration, true)
		cd:Show()
	else
		ClearTotemButtonCooldown(btn)
	end
end

--- True when GetTotemDuration says this slot is finished / empty (secret-safe).
local function TotemDurationObjectIsFinished(totemDuration)
	if not totemDuration then
		return false, false
	end
	-- Empty slot (zero total span).
	if totemDuration.IsZero then
		local isZero = totemDuration:IsZero()
		if WhoaUF:CanAccessValue(isZero) and isZero then
			return true, true
		end
	end
	-- Lifetime ended; slot data may linger until PLAYER_TOTEM_UPDATE.
	if totemDuration.HasExpired then
		local expired = totemDuration:HasExpired()
		if WhoaUF:CanAccessValue(expired) and WhoaUF:IsAccessibleTrue(expired) then
			return true, true
		end
	end
	if totemDuration.IsActive then
		local isActive = totemDuration:IsActive()
		if WhoaUF:CanAccessValue(isActive) then
			return not WhoaUF:IsAccessibleTrue(isActive), true
		end
	end
	return false, false
end

local function TotemButton_OnUpdate(self, elapsed)
	if not self.slot then
		return
	end
	self.durationElapsed = (self.durationElapsed or 0) + elapsed
	if self.durationElapsed < 0.2 then
		return
	end
	self.durationElapsed = 0

	local needsRefresh = false
	local left = GetTotemTimeLeft and GetTotemTimeLeft(self.slot)
	-- Never `left or 0` / ceil / compare on secrets.
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(left) then
		ClearTotemDurationText(self)
		if GetTotemDuration then
			local finished = TotemDurationObjectIsFinished(GetTotemDuration(self.slot))
			if finished then
				needsRefresh = true
			end
		end
	else
		left = left or 0
		local text = FormatTotemDuration(left)
		if self.lastDurationText ~= text then
			self.lastDurationText = text
			self.Duration:SetText(text)
		end
		self.Duration:SetShown(left > 0)
		if left <= 0 then
			needsRefresh = true
		end
	end

	-- Wall-clock fallback when start/duration were readable at cast time.
	if not needsRefresh and self.whoaCdStart and self.whoaCdDuration and self.whoaCdDuration > 0 then
		if GetTime() >= (self.whoaCdStart + self.whoaCdDuration) then
			needsRefresh = true
		end
	end

	if needsRefresh then
		WhoaUF:UpdateTotemFrame()
		return
	end

	if GameTooltip:IsOwned(self) and GameTooltip.SetTotem then
		GameTooltip:SetTotem(self.slot)
	end
end

WhoaUF.TotemButton_OnUpdate = TotemButton_OnUpdate

--- True when this slot should show a totem button. Never `if haveTotem`.
local function TotemSlotIsActive(haveTotem, duration, slot, btn)
	local keepShown = btn and btn:IsShown() or false

	-- Forever / Mainline: DurationObject IsActive / HasExpired (not IsZero alone).
	if GetTotemDuration and WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues() then
		local totemDuration = GetTotemDuration(slot)
		local finished, known = TotemDurationObjectIsFinished(totemDuration)
		if known then
			if finished then
				return false
			end
			-- Inside the active window: require haveTotem only when accessible.
			if WhoaUF:CanAccessValue(haveTotem) then
				return WhoaUF:IsAccessibleTrue(haveTotem)
			end
			return true
		end
		-- Unreadable duration: keep prior visibility rather than guessing.
		return keepShown
	end

	if not WhoaUF:CanAccessValue(haveTotem) then
		return keepShown
	end
	if not WhoaUF:IsAccessibleTrue(haveTotem) then
		return false
	end
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(duration) then
		return keepShown
	end
	return duration ~= nil and duration > 0
end

local function CreateTotemButton(parent)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(37, 37)
	btn:RegisterForClicks("RightButtonUp")
	btn:Hide()

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(34, 34)
	bg:SetPoint("CENTER")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetVertexColor(1, 1, 1, 0.6)

	local duration = btn:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall")
	duration:SetPoint("TOP", btn, "BOTTOM", 0, 0)
	duration:SetTextColor(1, 1, 1)
	btn.Duration = duration

	local iconFrame = CreateFrame("Frame", nil, btn)
	iconFrame:SetSize(22, 22)
	iconFrame:SetPoint("CENTER")
	local icon = iconFrame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	btn.Icon = icon

	-- Match Mainline TotemButtonTemplate Icon.Cooldown (reverse swipe, no numbers).
	local cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
	cooldown:SetAllPoints(iconFrame)
	if cooldown.SetReverse then
		cooldown:SetReverse(true)
	end
	if cooldown.SetHideCountdownNumbers then
		cooldown:SetHideCountdownNumbers(true)
	end
	if cooldown.SetDrawBling then
		cooldown:SetDrawBling(false)
	end
	if cooldown.SetDrawEdge then
		cooldown:SetDrawEdge(false)
	end
	if cooldown.SetUseCircularEdge then
		cooldown:SetUseCircularEdge(true)
	end
	if cooldown.SetSwipeColor then
		cooldown:SetSwipeColor(0, 0, 0, 0.65)
	end
	cooldown:Hide()
	btn.Cooldown = cooldown

	local border = CreateFrame("Frame", nil, btn)
	border:SetSize(38, 38)
	border:SetPoint("CENTER")
	border:SetFrameLevel(btn:GetFrameLevel() + 2)
	local borderTex = border:CreateTexture(nil, "OVERLAY")
	borderTex:SetAllPoints()
	borderTex:SetTexture(
		(WhoaUF.GetClassPowerTexture and WhoaUF:GetClassPowerTexture("Interface\\CharacterFrame\\TotemBorder"))
			or "Interface\\CharacterFrame\\TotemBorder"
	)
	btn.Border = borderTex

	btn:SetScript("OnClick", function(self, mouseButton)
		if mouseButton ~= "RightButton" or not self.slot or self.slot <= 0 then
			return
		end
		if GetTotemCannotDismiss then
			-- cannotDismiss may be secret — only bail when accessible and true.
			if WhoaUF:IsAccessibleTrue(GetTotemCannotDismiss(self.slot)) then
				return
			end
		end
		if DestroyTotem then
			DestroyTotem(self.slot)
		end
	end)
	btn:SetScript("OnEnter", function(self)
		if not self.slot or not GameTooltip.SetTotem then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:SetTotem(self.slot)
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	btn:SetScript("OnUpdate", TotemButton_OnUpdate)

	return btn
end

function WhoaUF:UpdateTotemFrame()
	local frame = self.unitFrames and self.unitFrames.player and self.unitFrames.player.TotemFrame
	if not frame or not GetTotemInfo then
		return
	end

	local force = self.IsForceShowClassPowerFor and self:IsForceShowClassPowerFor("SHAMAN")
	if force then
		local prev
		local previewIcon = "Interface\\Icons\\Spell_Nature_StoneSkinTotem"
		for i = 1, MAX_TOTEM_SLOTS do
			local btn = frame.buttons[i]
			btn.slot = nil
			btn.Icon:SetTexture(previewIcon)
			btn.Icon:Show()
			btn.Duration:SetText("")
			ClearTotemButtonCooldown(btn)
			btn:ClearAllPoints()
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", -6, 0)
			else
				btn:SetPoint("LEFT", frame, "LEFT", 0, 0)
			end
			btn:Show()
			prev = btn
		end
		frame:SetWidth(MAX_TOTEM_SLOTS * 37 + (MAX_TOTEM_SLOTS - 1) * -6)
		frame:Show()
		if self.LayoutPlayerBottomFrames then
			self:LayoutPlayerBottomFrames()
		else
			self:AnchorTotemFrame()
		end
		return
	end

	local priorities = GetTotemPriorities()
	local active = 0
	local prev

	for i = 1, MAX_TOTEM_SLOTS do
		local btn = frame.buttons[i]
		local slot = priorities[i] or i
		local haveTotem, _, startTime, duration, icon = GetTotemInfo(slot)
		if TotemSlotIsActive(haveTotem, duration, slot, btn) then
			active = active + 1
			btn.slot = slot
			btn.lastDurationText = nil
			btn.durationElapsed = 0.2
			-- SetTexture accepts secret fileIDs; skip only when icon is nil.
			if icon ~= nil then
				btn.Icon:SetTexture(icon)
				btn.Icon:Show()
			end
			SetTotemButtonCooldown(btn, startTime, duration)
			btn:SetScript("OnUpdate", TotemButton_OnUpdate)
			btn:ClearAllPoints()
			if prev then
				btn:SetPoint("LEFT", prev, "RIGHT", -6, 0)
			else
				btn:SetPoint("LEFT", frame, "LEFT", 0, 0)
			end
			btn:Show()
			prev = btn
		else
			btn.slot = nil
			btn:SetScript("OnUpdate", nil)
			ClearTotemDurationText(btn)
			ClearTotemButtonCooldown(btn)
			btn:Hide()
		end
	end

	-- 37px buttons with -6 spacing (TotemFrame.xml).
	local width = active > 0 and (active * 37 + (active - 1) * -6) or 37
	frame:SetWidth(width)
	frame:SetShown(active > 0)
	-- LayoutPlayerBottomFrames: anchor totems below runes/pet slot.
	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	else
		self:AnchorTotemFrame()
	end
end

-- Match PlayerFrameBottomManagedFramesContainer + TotemFrame leftPadding (TotemFrame.xml).
-- When stackAbove is set (runes/pet), hang below it with managed-container spacing.
function WhoaUF:AnchorTotemFrame(stackAbove, spacing)
	local player = self.unitFrames and self.unitFrames.player
	local anchorFrame = self:GetClassPowerAnchorFrame() or player
	local frame = player and player.TotemFrame
	if not frame or not anchorFrame then
		return
	end

	local containerX = 10
	local containerY = (self.GetPlayerBottomManagedContainerY and self:GetPlayerBottomManagedContainerY()) or 36
	local containerWidth = 160
	local leftPadding = 38
	local playerWidth = anchorFrame:GetWidth() or 232
	local containerLeft = (playerWidth * 0.5) + containerX - (containerWidth * 0.5)
	local x = containerLeft + leftPadding

	frame:ClearAllPoints()
	if stackAbove then
		local bottomPad = stackAbove.whoaBottomPadding or 0
		frame:SetPoint("LEFT", anchorFrame, "BOTTOMLEFT", x, 0)
		frame:SetPoint("TOP", stackAbove, "BOTTOM", 0, -(spacing or 2) - bottomPad)
	else
		frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", x, containerY)
	end
	self:ApplyClassPowerFrameLevel(frame)
end

function WhoaUF:InitTotemFrame(playerFrame)
	if not playerFrame or playerFrame.TotemFrame or not GetTotemInfo then
		return
	end
	local _, class = UnitClass("player")
	if class ~= "SHAMAN" then
		return
	end

	local frame = CreateFrame("Frame", "WhoaUFTotemFrame", playerFrame)
	frame:SetSize(128, 37)
	frame:SetFrameStrata("LOW")
	frame.buttons = {}

	for i = 1, MAX_TOTEM_SLOTS do
		frame.buttons[i] = CreateTotemButton(frame)
	end

	local function RegisterTotemFrameEvents(f)
		f:RegisterEvent("PLAYER_TOTEM_UPDATE")
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		pcall(function()
			f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		end)
		pcall(function()
			f:RegisterEvent("PLAYER_TALENT_UPDATE")
		end)
		pcall(function()
			f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
	end
	self.RegisterTotemFrameEvents = RegisterTotemFrameEvents
	RegisterTotemFrameEvents(frame)
	frame:SetScript("OnEvent", function()
		WhoaUF:UpdateTotemFrame()
	end)

	playerFrame.TotemFrame = frame
	self:AnchorTotemFrame()
	self:UpdateTotemFrame()
end

function WhoaUF:ApplyTotemFrameArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.TotemFrame
	if not frame or not frame.buttons then
		return
	end
	local path = self:GetClassPowerTexture("Interface\\CharacterFrame\\TotemBorder")
	for i = 1, #frame.buttons do
		local btn = frame.buttons[i]
		if btn and btn.Border then
			btn.Border:SetTexture(path)
		end
	end
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "SHAMAN",
		load = function()
			return GetTotemInfo ~= nil
		end,
		init = function(uf, player)
			uf:InitTotemFrame(player)
		end,
		refresh = function(uf)
			uf:UpdateTotemFrame()
		end,
		applyArt = function(uf)
			uf:ApplyTotemFrameArt()
		end,
		frameKey = "TotemFrame",
		registerEvents = "RegisterTotemFrameEvents",
		-- Totems sit under pet via AnchorTotemFrame, not the exclusive class slot.
		layout = {
			slot = "overlay",
			frameKey = "TotemFrame",
			anchor = "AnchorTotemFrame",
		},
	})
end
