--[[
	Whoa ClassResourceBar mixin — pooled point layout on top of ClassPowerBar.
	Reference: reference/future-classpower/framework/ClassResourceBarTemplate.lua
	Mainline only. Layout is manual (no HorizontalLayoutFrame dependency).
]]

do
	if not WhoaUF:IsMainline() then
		return
	end
end

local ClassPowerBar = WhoaUF.ClassPowerBar
if not ClassPowerBar then
	return
end

local ClassResourceBar = WhoaUF.ClassResourceBar or {}
WhoaUF.ClassResourceBar = ClassResourceBar

local DEFAULT_MAX = 5
local DEFAULT_SPACING = 4

function ClassResourceBar:OnLoad()
	self.classResourceButtonTable = self.classResourceButtonTable or {}
	self.maxUsablePoints = self.maxUsablePoints or DEFAULT_MAX
	self.spacing = self.spacing or DEFAULT_SPACING
	self.resourceBarMixin = self.resourceBarMixin or ClassPowerBar

	if self.powerToken then
		if self.powerToken2 then
			self:SetPowerTokens(self.powerToken, self.powerToken2)
		else
			self:SetPowerTokens(self.powerToken)
		end
	end
	if self.showTooltip and self.tooltip1 then
		self:SetTooltip(self.tooltip1, self.tooltip2)
	end

	self.resourceBarMixin.OnLoad(self)
end

function ClassResourceBar:OnEvent(event, arg1, arg2)
	if event == "PLAYER_LEVEL_UP" then
		local unit = self:GetUnit()
		if self.requiredShownLevel and UnitLevel(unit) >= self.requiredShownLevel then
			self:UnregisterEvent("PLAYER_LEVEL_UP")
			self:HandleBarSetup()
		end
	elseif event == "UNIT_DISPLAYPOWER" or event == "PLAYER_ENTERING_WORLD" then
		self:Setup()
	elseif event == "UNIT_MAXPOWER" then
		self:UpdateMaxPower()
	elseif event == "UNIT_POWER_POINT_CHARGE" then
		if self.UpdateChargedPowerPoints then
			self:UpdateChargedPowerPoints()
		elseif self.UpdatePower then
			self:UpdatePower()
		end
	else
		self.resourceBarMixin.OnEvent(self, event, arg1, arg2)
	end
end

function ClassResourceBar:HandleBarSetup()
	local parent = self:GetParent()
	local frameLevel = parent and (parent:GetFrameLevel() + 2) or self:GetFrameLevel()
	self:SetFrameLevel(frameLevel)
	if self.showBarFunc then
		self.showBarFunc(self)
	else
		self:Show()
	end
	self:UpdateMaxPower()
	if self.UpdatePower then
		self:UpdatePower()
	end
end

function ClassResourceBar:Setup()
	local showBar = false
	if UnitInVehicle and UnitInVehicle("player") and PlayerVehicleHasComboPoints then
		showBar = PlayerVehicleHasComboPoints()
	else
		showBar = self.resourceBarMixin.Setup(self)
		if self.shouldShowBarFunc then
			showBar = self.shouldShowBarFunc(self)
		elseif self.ShouldShowBar then
			showBar = self:ShouldShowBar()
		end
	end

	if showBar then
		self.unit = self:GetUnit()
		self:RegisterUnitEvent("UNIT_POWER_FREQUENT", self.unit)
		self:RegisterUnitEvent("UNIT_MAXPOWER", self.unit)
		pcall(function()
			self:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", self.unit)
		end)
		if self.unit == "player" and self.requiredShownLevel and UnitLevel(self.unit) < self.requiredShownLevel then
			self:RegisterEvent("PLAYER_LEVEL_UP")
		else
			self:HandleBarSetup()
		end
	else
		if self.hideBarFunc then
			self.hideBarFunc(self)
		else
			self:Hide()
		end
		self:UnregisterEvent("UNIT_POWER_FREQUENT")
		self:UnregisterEvent("UNIT_MAXPOWER")
		pcall(function()
			self:UnregisterEvent("UNIT_POWER_POINT_CHARGE")
		end)
	end
	return showBar
end

function ClassResourceBar:LayoutPoints()
	local points = self.classResourceButtonTable
	local n = #points
	if n < 1 then
		return
	end
	local spacing = self.spacing or DEFAULT_SPACING
	local totalW = 0
	for i = 1, n do
		totalW = totalW + points[i]:GetWidth()
		if i < n then
			totalW = totalW + spacing
		end
	end
	local x = -totalW / 2
	for i = 1, n do
		local p = points[i]
		local w = p:GetWidth()
		p:ClearAllPoints()
		p:SetPoint("LEFT", self, "CENTER", x, self.pointYOffset or 0)
		x = x + w + spacing
	end
end

function ClassResourceBar:AcquirePoint()
	if self.CreateResourcePoint then
		return self:CreateResourcePoint()
	end
	return CreateFrame("Frame", nil, self)
end

function ClassResourceBar:UpdateMaxPower()
	local oldMax = self.maxUsablePoints
	self.unit = self:GetUnit()
	local maxPoints = UnitPowerMax(self.unit, self.powerType)
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(maxPoints) then
		maxPoints = self.maxUsablePoints or DEFAULT_MAX
	end
	if not maxPoints or maxPoints < 1 then
		maxPoints = DEFAULT_MAX
	end
	-- Cap runaway max (Blizzard assertsafe < 100).
	if maxPoints > 10 then
		maxPoints = 10
	end
	self.maxUsablePoints = maxPoints

	local table = self.classResourceButtonTable
	if oldMax and maxPoints == oldMax and #table == maxPoints then
		return
	end

	for i = 1, #table do
		table[i]:Hide()
	end

	for i = 1, maxPoints do
		local point = table[i]
		if not point then
			point = self:AcquirePoint()
			table[i] = point
		end
		if self.resourcePointSetupFunc then
			self.resourcePointSetupFunc(point)
		elseif point.Setup then
			point:Setup()
		end
		point.layoutIndex = i
		point:Show()
	end
	for i = maxPoints + 1, #table do
		table[i]:Hide()
	end

	self:LayoutPoints()
	if self.UpdatePower then
		self:UpdatePower()
	end
end
