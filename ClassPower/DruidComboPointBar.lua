--[[
	Druid combo points under the Whoa player frame (Mainline).
	Uses ClassPowerBar + ClassResourceBar; art prefers UF-DruidCP-* atlases
	(sheet UIDruidComboPoints*.blp in Media\shared\dark\classpower\).
	Falls back to ComboPoints-* / ComboPoint.blp when UF atlases are missing.
	Reference: reference/future-classpower/druid-combo/

	Class gate is RegisterClassBar (not file load) so UnitClass timing at
	ADDON_LOADED cannot skip defining Init/Refresh — same pattern as RogueComboPointBar.
]]

do
	if not WhoaUF:HasPlayerComboPointBar() then
		return
	end
	-- Mainline ClassPowerBar + ClassResourceBar framework only.
	if not WhoaUF:HasClassPowerBarFramework() then
		return
	end
end

local ClassPowerBar = WhoaUF.ClassPowerBar
local ClassResourceBar = WhoaUF.ClassResourceBar
if not ClassPowerBar or not ClassResourceBar then
	return
end

local DEFAULT_MAX = 5
local DRUID_COMBO_BAR_Y = 22

local DRUID_ATLAS = {
	bgShadow = "UF-DruidCP-BG-Shadow",
	bgActive = "UF-DruidCP-BG-Active",
	bgInactive = "UF-DruidCP-BG-Dis",
	bgGlow = "UF-DruidCP-BG-Glow",
	icon = "UF-DruidCP-Icon",
	deplete = "UF-DruidCP-Deplete",
	ringGlow = "UF-DruidCP-Ring-Glow",
	smoke = "UF-DruidCP-Smoke",
}

local FALLBACK_ATLAS = {
	pointOff = "ComboPoints-PointBg",
	pointOn = "ComboPoints-ComboPoint",
}

local COMBO_POINT_CLIENT = "Interface\\ComboFrame\\ComboPoint"

local function AtlasExists(name)
	if C_Texture and C_Texture.GetAtlasInfo then
		return C_Texture.GetAtlasInfo(name) ~= nil
	end
	if GetAtlasInfo then
		return GetAtlasInfo(name) ~= nil
	end
	return false
end

local function HasDruidAtlases()
	return AtlasExists(DRUID_ATLAS.bgInactive) and AtlasExists(DRUID_ATLAS.icon)
end

local function SetAtlas(tex, atlas, useSize)
	if not tex or not atlas then
		return false
	end
	if WhoaUF.ApplyClassPowerAtlas then
		return WhoaUF:ApplyClassPowerAtlas(tex, atlas, useSize)
	end
	return pcall(function()
		tex:SetAtlas(atlas, useSize and true or false)
	end)
end

local function GetComboPowerType()
	return (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
end

local function GetEnergyPowerType()
	return (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
end

local function ApplyDruidPointArt(point, useDruidAtlas)
	if useDruidAtlas then
		SetAtlas(point.BG_Shadow, DRUID_ATLAS.bgShadow, true)
		SetAtlas(point.BG_Active, DRUID_ATLAS.bgActive, true)
		SetAtlas(point.BG_Inactive, DRUID_ATLAS.bgInactive, true)
		SetAtlas(point.BG_Glow, DRUID_ATLAS.bgGlow, true)
		SetAtlas(point.Point_Icon, DRUID_ATLAS.icon, true)
		SetAtlas(point.Point_Deplete, DRUID_ATLAS.deplete, true)
		SetAtlas(point.FX_RingGlow, DRUID_ATLAS.ringGlow, true)
		SetAtlas(point.Smoke, DRUID_ATLAS.smoke, true)
	elseif AtlasExists(FALLBACK_ATLAS.pointOn) then
		SetAtlas(point.BG_Inactive, FALLBACK_ATLAS.pointOff, false)
		SetAtlas(point.Point_Icon, FALLBACK_ATLAS.pointOn, false)
	else
		local path = WhoaUF.GetClassPowerTexture and WhoaUF:GetClassPowerTexture(COMBO_POINT_CLIENT) or COMBO_POINT_CLIENT
		local function setSheet(tex, left, right, top, bottom)
			if not tex then
				return
			end
			if tex.SetAtlas and tex.GetAtlas then
				local atlas = tex:GetAtlas()
				if atlas and atlas ~= "" then
					pcall(function()
						tex:SetAtlas(nil)
					end)
				end
			end
			tex:SetTexture(path)
			tex:SetTexCoord(left, right, top, bottom)
		end
		setSheet(point.BG_Inactive, 0, 0.375, 0, 1)
		setSheet(point.Point_Icon, 0.375, 0.5625, 0, 1)
	end
end

local function ResetPointVisuals(point)
	if point.activateAnim then
		point.activateAnim:Stop()
	end
	if point.deactivateAnim then
		point.deactivateAnim:Stop()
	end
	if point.FB_Slash then
		point.FB_Slash:Hide()
	end
	point.BG_Glow:SetAlpha(0)
	point.Point_Deplete:SetAlpha(0)
	point.FX_RingGlow:SetAlpha(0)
	point.Smoke:SetAlpha(0)
	if point.isActive then
		point.BG_Active:SetAlpha(1)
		point.BG_Inactive:SetAlpha(0)
		point.Point_Icon:SetAlpha(1)
	else
		point.BG_Active:SetAlpha(0)
		point.BG_Inactive:SetAlpha(1)
		point.Point_Icon:SetAlpha(0)
	end
end

local function CreateDruidPoint(parent, useDruidAtlas)
	local point = CreateFrame("Frame", nil, parent)
	point:SetSize(20, 20)
	point.isActive = nil
	point.fxTextures = {}

	local function Tex(layer, sub)
		return point:CreateTexture(nil, layer, nil, sub)
	end

	point.BG_Shadow = Tex("BACKGROUND", 1)
	point.BG_Shadow:SetPoint("CENTER", 0, -2)
	point.BG_Active = Tex("BACKGROUND", 1)
	point.BG_Active:SetPoint("CENTER")
	point.BG_Inactive = Tex("BACKGROUND", 1)
	point.BG_Inactive:SetPoint("CENTER")
	point.BG_Glow = Tex("BACKGROUND", 2)
	point.BG_Glow:SetPoint("CENTER")
	point.fxTextures[#point.fxTextures + 1] = point.BG_Glow

	point.Point_Deplete = Tex("ARTWORK")
	point.Point_Deplete:SetPoint("CENTER")
	point.fxTextures[#point.fxTextures + 1] = point.Point_Deplete
	point.Point_Icon = Tex("ARTWORK")
	point.Point_Icon:SetPoint("CENTER")

	point.FX_RingGlow = Tex("OVERLAY")
	point.FX_RingGlow:SetPoint("CENTER")
	point.fxTextures[#point.fxTextures + 1] = point.FX_RingGlow
	point.FB_Slash = Tex("OVERLAY")
	point.FB_Slash:SetSize(26, 41)
	point.FB_Slash:SetPoint("CENTER", 1, 3)
	point.FB_Slash:Hide()
	point.Smoke = Tex("OVERLAY")
	point.Smoke:SetPoint("CENTER", 0, 15)
	point.fxTextures[#point.fxTextures + 1] = point.Smoke

	ApplyDruidPointArt(point, useDruidAtlas)

	local activate = point:CreateAnimationGroup()
	if activate.SetToFinalAlpha then
		activate:SetToFinalAlpha(true)
	end
	local a1 = activate:CreateAnimation("Alpha")
	a1:SetTarget(point.Point_Icon)
	a1:SetFromAlpha(0)
	a1:SetToAlpha(1)
	a1:SetDuration(0.2)
	local a2 = activate:CreateAnimation("Alpha")
	a2:SetTarget(point.BG_Active)
	a2:SetFromAlpha(0)
	a2:SetToAlpha(1)
	a2:SetDuration(0.15)
	local a3 = activate:CreateAnimation("Alpha")
	a3:SetTarget(point.BG_Inactive)
	a3:SetFromAlpha(1)
	a3:SetToAlpha(0)
	a3:SetDuration(0.15)
	point.activateAnim = activate

	local deactivate = point:CreateAnimationGroup()
	if deactivate.SetToFinalAlpha then
		deactivate:SetToFinalAlpha(true)
	end
	local d1 = deactivate:CreateAnimation("Alpha")
	d1:SetTarget(point.Point_Icon)
	d1:SetFromAlpha(1)
	d1:SetToAlpha(0)
	d1:SetDuration(0.2)
	local d2 = deactivate:CreateAnimation("Alpha")
	d2:SetTarget(point.BG_Active)
	d2:SetFromAlpha(1)
	d2:SetToAlpha(0)
	d2:SetDuration(0.2)
	local d3 = deactivate:CreateAnimation("Alpha")
	d3:SetTarget(point.BG_Inactive)
	d3:SetFromAlpha(0)
	d3:SetToAlpha(1)
	d3:SetDuration(0.2)
	point.deactivateAnim = deactivate

	function point:Setup()
		self.isActive = nil
		ResetPointVisuals(self)
		self:Show()
	end

	function point:SetActive(isActive)
		if self.isActive == isActive then
			return
		end
		self.isActive = isActive
		ResetPointVisuals(self)
		if isActive then
			if self.activateAnim.Restart then
				self.activateAnim:Restart()
			else
				self.activateAnim:Play()
			end
		else
			if self.deactivateAnim.Restart then
				self.deactivateAnim:Restart()
			else
				self.deactivateAnim:Play()
			end
		end
	end

	ResetPointVisuals(point)
	return point
end

local function MixinDruidBar(frame)
	for k, v in pairs(ClassPowerBar) do
		if type(v) == "function" then
			frame[k] = v
		end
	end
	for k, v in pairs(ClassResourceBar) do
		if type(v) == "function" then
			frame[k] = v
		end
	end

	frame.class = "DRUID"
	frame.powerToken = "COMBO_POINTS"
	frame.powerType = GetComboPowerType()
	frame.tooltip1 = COMBO_POINTS_POWER or COMBO_POINTS or "Combo Points"
	frame.tooltip2 = COMBO_POINTS_DRUID_TOOLTIP
	frame.showTooltip = true
	frame.spacing = 4
	frame.pointYOffset = 0
	frame.resourceBarMixin = ClassPowerBar
	frame.classResourceButtonTable = {}
	frame.useDruidAtlas = HasDruidAtlases()

	-- Re-apply Whoa rim strata after ClassResourceBar sets level from UIParent.
	frame.showBarFunc = function(bar)
		bar:Show()
		if WhoaUF.AnchorDruidComboPointBar then
			WhoaUF:AnchorDruidComboPointBar()
		end
	end

	function frame:ShouldShowBar()
		if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("DRUID") then
			return true
		end
		local powerType = UnitPowerType(self:GetUnit())
		return powerType == GetEnergyPowerType()
	end

	function frame:CreateResourcePoint()
		return CreateDruidPoint(self, self.useDruidAtlas)
	end

	function frame:UpdatePower()
		local unit = self:GetUnit()
		local comboPoints
		if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("DRUID") then
			comboPoints = self.maxUsablePoints or DEFAULT_MAX
		else
			comboPoints = UnitPower(unit, self.powerType)
			if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(comboPoints) then
				return
			end
		end
		for i = 1, #self.classResourceButtonTable do
			local point = self.classResourceButtonTable[i]
			if point and point.SetActive then
				point:SetActive(i <= (comboPoints or 0))
			end
		end
	end

	function frame:ApplyArt()
		self.useDruidAtlas = HasDruidAtlases()
		for i = 1, #self.classResourceButtonTable do
			ApplyDruidPointArt(self.classResourceButtonTable[i], self.useDruidAtlas)
			ResetPointVisuals(self.classResourceButtonTable[i])
		end
	end
end

function WhoaUF:GetDruidComboPointBarAnchor()
	local bars = self.GetRegisteredClassBars and self:GetRegisteredClassBars()
	if bars then
		for i = 1, #bars do
			local layout = bars[i].layout
			if layout and layout.frameKey == "DruidComboPointBar" then
				return layout.defaultX or 33, layout.defaultY or DRUID_COMBO_BAR_Y
			end
		end
	end
	return 33, DRUID_COMBO_BAR_Y
end

-- Legion-style player-rim tray: UIParent sibling, position locked to Whoa player frame.
function WhoaUF:AnchorDruidComboPointBar()
	local player = self.unitFrames and self.unitFrames.player
	local anchorFrame = self:GetClassPowerAnchorFrame() or player
	local frame = player and player.DruidComboPointBar
	if not frame or not anchorFrame then
		return
	end
	local x, y = self:GetDruidComboPointBarAnchor()
	frame:ClearAllPoints()
	frame:SetPoint("TOP", anchorFrame, "BOTTOM", x, y)
	if self.ApplyComboPointPlayerBarStrata then
		self:ApplyComboPointPlayerBarStrata(player)
	elseif self.ApplyClassPowerFrameLevel then
		self:ApplyClassPowerFrameLevel(frame)
	end
end

function WhoaUF:RefreshDruidComboPointBar()
	local player = self.unitFrames and self.unitFrames.player
	if not player then
		return
	end
	if not player.DruidComboPointBar then
		self:InitDruidComboPointBar(player)
	end
	local frame = player.DruidComboPointBar
	if not frame then
		return
	end
	frame:Setup()
	if frame:IsShown() then
		self:AnchorDruidComboPointBar()
	end
	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end
end

function WhoaUF:ApplyDruidComboPointBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.DruidComboPointBar
	if frame and frame.ApplyArt then
		frame:ApplyArt()
	end
end

function WhoaUF:RegisterDruidComboPointBarEvents(frame)
	if not frame then
		return
	end
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("UNIT_DISPLAYPOWER")
	frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	frame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
	pcall(function()
		frame:RegisterEvent("PLAYER_TALENT_UPDATE")
	end)
	pcall(function()
		frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	end)
end

function WhoaUF:InitDruidComboPointBar(playerFrame)
	if not playerFrame or playerFrame.DruidComboPointBar then
		return
	end
	-- Visibility is ShouldShowBar (energy / force-show); RegisterClassBar filters DRUID.
	-- Do not early-return on UnitClass here — nil at first init would skip forever.

	-- Start on UIParent; ApplyComboPointPlayerBarStrata reparents under stacked druid
	-- so the tray sits above under-player threat host and under Overlay rim.
	local frame = CreateFrame("Frame", "WhoaUFDruidComboPointBar", UIParent)
	frame:SetSize(120, 24)
	frame:Hide()
	frame.whoaUnitFrame = playerFrame
	MixinDruidBar(frame)

	frame:SetScript("OnEvent", function(self, event, ...)
		if event == "UPDATE_SHAPESHIFT_FORM"
			or event == "PLAYER_SPECIALIZATION_CHANGED"
			or event == "PLAYER_TALENT_UPDATE"
		then
			self:Setup()
			if self:IsShown() and WhoaUF.AnchorDruidComboPointBar then
				WhoaUF:AnchorDruidComboPointBar()
			end
			if WhoaUF.LayoutPlayerBottomFrames then
				WhoaUF:LayoutPlayerBottomFrames()
			end
			return
		end
		ClassResourceBar.OnEvent(self, event, ...)
		if (event == "UNIT_DISPLAYPOWER" or event == "PLAYER_ENTERING_WORLD") and WhoaUF.AnchorDruidComboPointBar then
			if self:IsShown() then
				WhoaUF:AnchorDruidComboPointBar()
			end
			if WhoaUF.LayoutPlayerBottomFrames then
				WhoaUF:LayoutPlayerBottomFrames()
			end
		end
	end)

	self:RegisterDruidComboPointBarEvents(frame)
	playerFrame.DruidComboPointBar = frame
	-- ComboPointPlayerBar alias so stacked-druid strata helpers work when RogueComboPointBar is absent.
	playerFrame.ComboPointPlayerBar = playerFrame.ComboPointPlayerBar or frame

	frame:OnLoad()
	self:AnchorDruidComboPointBar()
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "DRUID",
		load = function()
			return WhoaUF:HasPlayerComboPointBar() and WhoaUF:HasClassPowerBarFramework()
		end,
		init = function(uf, player)
			uf:InitDruidComboPointBar(player)
		end,
		refresh = function(uf)
			uf:RefreshDruidComboPointBar()
		end,
		applyArt = function(uf)
			uf:ApplyDruidComboPointBarArt()
		end,
		frameKey = "DruidComboPointBar",
		registerEvents = "RegisterDruidComboPointBarEvents",
		layout = {
			slot = "overlay",
			frameKey = "DruidComboPointBar",
			anchor = "AnchorDruidComboPointBar",
			getAnchor = "GetDruidComboPointBarAnchor",
			defaultX = 33,
			defaultY = DRUID_COMBO_BAR_Y,
		},
	})
end
