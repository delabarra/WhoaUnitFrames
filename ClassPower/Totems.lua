--[[
	Player totem bar (shaman / others with totems).
	Reference: reference/Blizzard_UnitFrame/Classic/TotemFrame.xml, TotemFrame.lua
	Note: stock TotemFrame parents to PlayerFrame, not TargetFrame.
]]

do
	if not WhoaUF:HasTotemFrame() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "SHAMAN" then
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
	seconds = math.ceil(seconds or 0)
	if seconds >= 60 then
		return string.format("%dm", math.floor(seconds / 60))
	elseif seconds > 0 then
		return string.format("%d s", seconds)
	end
	return ""
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
	local left = GetTotemTimeLeft and GetTotemTimeLeft(self.slot) or 0
	local text = FormatTotemDuration(left)
	if self.lastDurationText ~= text then
		self.lastDurationText = text
		self.Duration:SetText(text)
	end
	self.Duration:SetShown(left > 0)
	if GameTooltip:IsOwned(self) and GameTooltip.SetTotem then
		GameTooltip:SetTotem(self.slot)
	end
end

WhoaUF.TotemButton_OnUpdate = TotemButton_OnUpdate

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
		if GetTotemCannotDismiss and GetTotemCannotDismiss(self.slot) then
			return
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
		local haveTotem, _, _, duration, icon = GetTotemInfo(slot)
		if haveTotem and duration and duration > 0 then
			active = active + 1
			btn.slot = slot
			btn.lastDurationText = nil
			btn.durationElapsed = 0.2
			btn.Icon:SetTexture(icon)
			btn.Icon:Show()
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
	local containerY = 36
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
