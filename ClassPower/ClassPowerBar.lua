--[[
	Whoa ClassPowerBar mixin — Mainline framework for player class-resource trays.
	Reference: reference/future-classpower/framework/ClassPowerBar.lua
	Never sets PlayerFrame.classPowerBar; trays attach to WhoaUFPlayerFrame only.
]]

do
	if not WhoaUF:IsMainline() then
		return
	end
end

local ClassPowerBar = WhoaUF.ClassPowerBar or {}
WhoaUF.ClassPowerBar = ClassPowerBar

function ClassPowerBar:OnLoad()
	self:Setup()
end

function ClassPowerBar:GetUnit()
	if self.unit then
		return self.unit
	end
	local parent = self:GetParent()
	if parent then
		if parent.unit then
			return parent.unit
		end
		local grand = parent.GetParent and parent:GetParent()
		if grand and grand.unit then
			return grand.unit
		end
	end
	return "player"
end

function ClassPowerBar:SetTooltip(tooltipTitle, tooltip)
	self.tooltipTitle = tooltipTitle
	self.tooltip = tooltip
	if self.tooltipTitle and self.tooltip then
		self:SetScript("OnEnter", self.OnEnter)
		self:SetScript("OnLeave", self.OnLeave)
	else
		self:SetScript("OnEnter", nil)
		self:SetScript("OnLeave", nil)
	end
end

function ClassPowerBar:SetPowerTokens(...)
	local tokens = {}
	for i = 1, select("#", ...) do
		tokens[select(i, ...)] = true
	end
	self.powerTokens = tokens
end

function ClassPowerBar:UsesPowerToken(tokenType)
	return self.powerTokens and self.powerTokens[tokenType]
end

function ClassPowerBar:OnEvent(event, ...)
	if event == "UNIT_POWER_FREQUENT" then
		local unitToken, powerToken = ...
		if unitToken ~= self:GetUnit() then
			return false
		end
		if self:UsesPowerToken(powerToken) and self.UpdatePower then
			self:UpdatePower()
		end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_DISPLAYPOWER" then
		if self.UpdatePower then
			self:UpdatePower()
		end
	elseif event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
		self:Setup()
		if self.UpdatePower then
			self:UpdatePower()
		end
	else
		return false
	end
	return true
end

function ClassPowerBar:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetText(self.tooltipTitle, 1, 1, 1)
	GameTooltip:AddLine(self.tooltip, nil, nil, nil, true)
	GameTooltip:Show()
end

function ClassPowerBar:OnLeave()
	GameTooltip:Hide()
end

function ClassPowerBar:Setup()
	local _, class = UnitClass("player")
	local showBar = false
	local spec
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		spec = C_SpecializationInfo.GetSpecialization()
	elseif GetSpecialization then
		spec = GetSpecialization()
	end

	if class == self.class then
		if not self.spec or spec == self.spec then
			self:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
			self:RegisterEvent("PLAYER_ENTERING_WORLD")
			self:RegisterEvent("UNIT_DISPLAYPOWER")
			showBar = true
		else
			self:UnregisterEvent("UNIT_POWER_FREQUENT")
			self:UnregisterEvent("PLAYER_ENTERING_WORLD")
			self:UnregisterEvent("UNIT_DISPLAYPOWER")
		end
		self:RegisterEvent("PLAYER_TALENT_UPDATE")
		pcall(function()
			self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
	end

	-- Optional per-bar gate lives on ClassResourceBar (shouldShowBarFunc / ShouldShowBar).
	-- Do not hide here — Blizzard ClassPowerBar only gates on class/spec.
	self:SetShown(showBar)
	return showBar
end

function ClassPowerBar:TurnOn(frame, texture, toAlpha)
	if not frame or not texture then
		return
	end
	local alphaValue = texture:GetAlpha()
	if frame.Fadein then
		frame.Fadein:Stop()
	end
	if frame.Fadeout then
		frame.Fadeout:Stop()
	end
	texture:SetAlpha(alphaValue)
	frame.on = true
	if alphaValue < toAlpha then
		if texture:IsVisible() and frame.Fadein and frame.Fadein.AlphaAnim then
			frame.Fadein.AlphaAnim:SetFromAlpha(alphaValue)
			frame.Fadein:Play()
		else
			texture:SetAlpha(toAlpha)
		end
	end
end

function ClassPowerBar:TurnOff(frame, texture, toAlpha)
	if not frame or not texture then
		return
	end
	local alphaValue = texture:GetAlpha()
	if frame.Fadein then
		frame.Fadein:Stop()
	end
	if frame.Fadeout then
		frame.Fadeout:Stop()
	end
	texture:SetAlpha(alphaValue)
	frame.on = false
	if alphaValue > toAlpha then
		if texture:IsVisible() and frame.Fadeout and frame.Fadeout.AlphaAnim then
			frame.Fadeout.AlphaAnim:SetFromAlpha(alphaValue)
			frame.Fadeout:Play()
		else
			texture:SetAlpha(toAlpha)
		end
	end
end
