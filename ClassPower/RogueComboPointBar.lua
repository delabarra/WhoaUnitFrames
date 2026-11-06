--[[
	Legion ComboPointPlayerFrame under the Whoa player frame.
	Reference: reference/ComboFramePlayer_7.3.5/ComboFramePlayer.lua|.xml
	Art: ComboPoints-* atlases (tray + red orbs). Classic target combo stays in Frames/ComboPoints.lua.
	Dark edits: Media\shared\dark\classpower\ (ComboPoint.blp, ClassOverlayComboPoints.blp).
	ComboPoints-* always remap to ClassOverlayComboPoints (Classic + Mainline).
]]

do
	-- Class gate is RegisterClassBar (not file load) so UnitClass timing at
	-- ADDON_LOADED cannot skip defining Init/Refresh. Loads on Classic + Mainline.
	if not WhoaUF:HasPlayerComboPointBar() then
		return
	end
end

local MAX_COMBO_UI = 6
local MAX_BONUS_UI = 5
local DEFAULT_MAX = 5
local COMBO_POINT_CLIENT = "Interface\\ComboFrame\\ComboPoint"

local ATLAS = {
	bg = "ComboPoints-AllPointsBG",
	pointOff = "ComboPoints-PointBg",
	pointOn = "ComboPoints-ComboPoint",
	fxCircle = "ComboPoints-FX-Circle",
	fxStar = "ComboPoints-FX-Star",
	dashOff = "ComboPoints-ComboPointDash-Bg",
	dashOn = "ComboPoints-ComboPointDash",
	fxDash = "ComboPoints-FX-Dash",
}

local function GetComboPointTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(COMBO_POINT_CLIENT)
	end
	return COMBO_POINT_CLIENT
end

local function SetComboAtlas(tex, atlas, useSize)
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

local function ClearAtlas(tex)
	if not tex or not tex.SetAtlas then
		return
	end
	if tex.GetAtlas then
		local atlas = tex:GetAtlas()
		if not atlas or atlas == "" then
			return
		end
	end
	pcall(function()
		tex:SetAtlas(nil)
	end)
end

local function SetComboPointSheet(tex, path, left, right, top, bottom)
	if not tex or not path then
		return
	end
	-- Clear atlas so light↔dark SetTexture wins after ComboPoints-* atlases.
	ClearAtlas(tex)
	tex:SetTexture(path)
	tex:SetTexCoord(left, right, top, bottom)
end

local function ApplyComboPointTextures(point, useAtlas)
	if not point then
		return
	end
	if useAtlas then
		SetComboAtlas(point.PointOff, ATLAS.pointOff, false)
		SetComboAtlas(point.Point, ATLAS.pointOn, false)
		SetComboAtlas(point.CircleBurst, ATLAS.fxCircle, true)
		SetComboAtlas(point.Star, ATLAS.fxStar, true)
		if point.Star then
			point.Star:Show()
		end
	else
		local path = GetComboPointTex()
		SetComboPointSheet(point.PointOff, path, 0, 0.375, 0, 1)
		SetComboPointSheet(point.Point, path, 0.375, 0.5625, 0, 1)
		SetComboPointSheet(point.CircleBurst, path, 0.5625, 1, 0, 1)
		if point.Star then
			point.Star:Hide()
		end
		-- Fixed Classic gem size (atlas useAtlasSize may have changed these).
		point:SetSize(20, 21)
		point.PointOff:SetSize(20, 21)
		point.Point:SetSize(20, 21)
	end
end

local function ApplyBonusPointTextures(bonus, useAtlas)
	if not bonus then
		return
	end
	if useAtlas then
		SetComboAtlas(bonus.PointOff, ATLAS.dashOff, true)
		SetComboAtlas(bonus.Point, ATLAS.dashOn, true)
		SetComboAtlas(bonus.DashBurst, ATLAS.fxDash, true)
	end
end

local comboPointMaxToLayout = {
	[5] = { width = 20, height = 21, xOffs = 1 },
	[6] = { width = 18, height = 19, xOffs = -1 },
}

local function GetComboPowerType()
	return (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
end

local function GetEnergyPowerType()
	return (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
end

-- Classic ComboFrame uses GetComboPoints(unit, "target"); UnitPower ComboPoints on Mainline+.
local function GetNumComboPoints()
	if (WhoaUF.IsMainline and WhoaUF:IsMainline()) or not GetComboPoints then
		local n = UnitPower("player", GetComboPowerType())
		if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(n) then
			return nil
		end
		return n or 0
	end
	return GetComboPoints("player", "target") or 0
end

local function GetMaxComboPoints()
	if UnitPowerMax then
		local max = UnitPowerMax("player", GetComboPowerType())
		if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(max) then
			return DEFAULT_MAX
		end
		if max and max > 0 then
			return max
		end
	end
	return DEFAULT_MAX
end

local function AtlasExists(name)
	if C_Texture and C_Texture.GetAtlasInfo then
		return C_Texture.GetAtlasInfo(name) ~= nil
	end
	if GetAtlasInfo then
		return GetAtlasInfo(name) ~= nil
	end
	return false
end

local function HasComboAtlases()
	return AtlasExists(ATLAS.bg) and AtlasExists(ATLAS.pointOn) and AtlasExists(ATLAS.pointOff)
end

local function AddAlpha(group, target, fromAlpha, toAlpha, duration, order, startDelay, smoothing)
	local anim = group:CreateAnimation("Alpha")
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(toAlpha)
	anim:SetDuration(duration)
	anim:SetOrder(order or 1)
	if startDelay and startDelay > 0 and anim.SetStartDelay then
		anim:SetStartDelay(startDelay)
	end
	if smoothing and anim.SetSmoothing then
		anim:SetSmoothing(smoothing)
	end
	if target and anim.SetTarget then
		anim:SetTarget(target)
	end
	return anim
end

local function AddScale(group, target, fromX, fromY, toX, toY, duration, order, startDelay, smoothing)
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
	if startDelay and startDelay > 0 and anim.SetStartDelay then
		anim:SetStartDelay(startDelay)
	end
	if smoothing and anim.SetSmoothing then
		anim:SetSmoothing(smoothing)
	end
	if target and anim.SetTarget then
		anim:SetTarget(target)
	end
	return anim
end

local function AddRotation(group, target, degrees, duration, order, startDelay, smoothing)
	local ok, anim = pcall(function()
		return group:CreateAnimation("Rotation")
	end)
	if not ok or not anim then
		return nil
	end
	anim:SetDegrees(degrees)
	anim:SetDuration(duration)
	anim:SetOrder(order or 1)
	if startDelay and startDelay > 0 and anim.SetStartDelay then
		anim:SetStartDelay(startDelay)
	end
	if smoothing and anim.SetSmoothing then
		anim:SetSmoothing(smoothing)
	end
	if target and anim.SetTarget then
		anim:SetTarget(target)
	end
	return anim
end

local function CreatePointAnims(point)
	local pointAnim = point:CreateAnimationGroup()
	if pointAnim.SetToFinalAlpha then
		pointAnim:SetToFinalAlpha(true)
	end
	AddAlpha(pointAnim, point.Point, 0, 1, 0.25, 1)
	AddScale(pointAnim, point.Point, 0.8, 0.8, 1, 1, 0.25, 1, nil, "OUT")
	point.PointAnim = pointAnim

	local animIn = point:CreateAnimationGroup()
	if animIn.SetToFinalAlpha then
		animIn:SetToFinalAlpha(true)
	end
	AddScale(animIn, point.Star, 0.25, 0.25, 0.9, 0.9, 0.5, 1, 0.1, "OUT")
	AddRotation(animIn, point.Star, -60, 0.8, 1, 0.1, "OUT")
	AddAlpha(animIn, point.Star, 0.75, 0, 0.4, 1, 0.5, "IN")
	AddAlpha(animIn, point.CircleBurst, 0, 1, 0.1, 1)
	AddScale(animIn, point.CircleBurst, 1.25, 1.25, 0.75, 0.75, 0.25, 1, nil, "OUT")
	AddAlpha(animIn, point.CircleBurst, 1, 0, 0.25, 1, 0.25, "IN")
	point.AnimIn = animIn

	local animOut = point:CreateAnimationGroup()
	if animOut.SetToFinalAlpha then
		animOut:SetToFinalAlpha(true)
	end
	AddAlpha(animOut, point.CircleBurst, 0, 1, 0.1, 1)
	AddScale(animOut, point.CircleBurst, 0.8, 0.8, 0.6, 0.6, 0.4, 1, nil, "OUT")
	AddAlpha(animOut, point.CircleBurst, 1, 0, 0.25, 1, 0.25, "IN")
	-- AnimOut: fade lit gem after finisher spend.
	AddAlpha(animOut, point.Point, 1, 0, 0.2, 1)
	point.AnimOut = animOut
end

local function CreateBonusAnims(bonus)
	local animIn = bonus:CreateAnimationGroup()
	if animIn.SetToFinalAlpha then
		animIn:SetToFinalAlpha(true)
	end
	AddAlpha(animIn, bonus.Point, 0, 1, 0.1, 1)
	AddScale(animIn, bonus.Point, 0.8, 0.8, 1, 1, 0.25, 1, nil, "OUT")
	AddAlpha(animIn, bonus.DashBurst, 0, 1, 0.1, 1)
	AddScale(animIn, bonus.DashBurst, 0.5, 1, 1.1, 1, 0.25, 1, nil, "OUT")
	AddAlpha(animIn, bonus.DashBurst, 1, 0, 0.25, 1, 0.25, "IN")
	bonus.AnimIn = animIn

	local animOut = bonus:CreateAnimationGroup()
	if animOut.SetToFinalAlpha then
		animOut:SetToFinalAlpha(true)
	end
	AddAlpha(animOut, bonus.Point, 1, 0, 0.2, 1)
	bonus.AnimOut = animOut
end

local function CreateComboPoint(parent, useAtlas)
	local point = CreateFrame("Frame", nil, parent)
	point:SetSize(20, 21)
	point.on = false

	local off = point:CreateTexture(nil, "BACKGROUND")
	off:SetSize(20, 21)
	off:SetPoint("CENTER")
	point.PointOff = off

	local on = point:CreateTexture(nil, "ARTWORK")
	on:SetSize(20, 21)
	on:SetPoint("CENTER")
	on:SetAlpha(0)
	on:SetBlendMode("BLEND")
	point.Point = on

	local burst = point:CreateTexture(nil, "ARTWORK")
	burst:SetPoint("CENTER")
	burst:SetAlpha(0)
	burst:SetBlendMode("BLEND")
	point.CircleBurst = burst

	local star = point:CreateTexture(nil, "OVERLAY")
	star:SetPoint("CENTER")
	star:SetAlpha(0)
	star:SetBlendMode("ADD")
	point.Star = star

	if useAtlas then
		ApplyComboPointTextures(point, true)
	else
		-- No Legion atlases: ComboPoint texture coords.
		ApplyComboPointTextures(point, false)
		star:Hide()
	end

	CreatePointAnims(point)
	return point
end

local function CreateBonusPoint(parent, useAtlas)
	local bonus = CreateFrame("Frame", nil, parent)
	bonus:SetSize(9, 10)
	bonus.on = false
	bonus:Hide()

	local off = bonus:CreateTexture(nil, "BACKGROUND")
	off:SetPoint("CENTER")
	bonus.PointOff = off

	local on = bonus:CreateTexture(nil, "ARTWORK")
	on:SetPoint("CENTER")
	on:SetAlpha(0)
	on:SetBlendMode("BLEND")
	bonus.Point = on

	local dash = bonus:CreateTexture(nil, "ARTWORK", nil, 2)
	dash:SetPoint("CENTER", 0, -1)
	dash:SetAlpha(0)
	dash:SetBlendMode("BLEND")
	bonus.DashBurst = dash

	if useAtlas then
		ApplyBonusPointTextures(bonus, true)
	else
		off:Hide()
		on:Hide()
		dash:Hide()
	end

	CreateBonusAnims(bonus)
	return bonus
end

local function UpdateComboPointLayout(maxUsablePoints, comboPoint, previousComboPoint)
	local layout = comboPointMaxToLayout[maxUsablePoints] or comboPointMaxToLayout[5]
	comboPoint:SetSize(layout.width, layout.height)
	comboPoint.PointOff:SetSize(layout.width, layout.height)
	comboPoint.Point:SetSize(layout.width, layout.height)
	if previousComboPoint then
		comboPoint:ClearAllPoints()
		comboPoint:SetPoint("LEFT", previousComboPoint, "RIGHT", layout.xOffs, 0)
	end
end

local function DetermineComboBonusVisibility(comboBonusIndex, max)
	if max < 8 then
		return false
	end
	if comboBonusIndex <= 3 then
		return true
	end
	if comboBonusIndex == 4 and max >= 9 then
		return true
	end
	if comboBonusIndex == 5 and max >= 10 then
		return true
	end
	return false
end

local function AnimIn(self, frame)
	if frame.on then
		return
	end
	frame.on = true
	if frame.AnimOut and frame.AnimOut:IsPlaying() then
		frame.AnimOut:Stop()
	end
	frame.Point:SetAlpha(0)
	if frame.AnimIn then
		if frame.AnimIn.Restart then
			frame.AnimIn:Restart()
		else
			frame.AnimIn:Play()
		end
	end
	if frame.PointAnim then
		if frame.PointAnim.Restart then
			frame.PointAnim:Restart()
		else
			frame.PointAnim:Play()
		end
	else
		frame.Point:SetAlpha(1)
	end
end

local function AnimOut(self, frame)
	if not frame.on then
		return
	end
	frame.on = false
	if frame.PointAnim then
		-- Finisher spend: stop PointAnim before AnimOut (ComboFramePlayer.lua).
		frame.PointAnim:Stop()
		frame.Point:SetAlpha(0)
	end
	if frame.AnimIn then
		frame.AnimIn:Stop()
	end
	if frame.AnimOut then
		if frame.AnimOut.Restart then
			frame.AnimOut:Restart()
		else
			frame.AnimOut:Play()
		end
	else
		frame.Point:SetAlpha(0)
	end
end

local function SetPointInstant(frame, on)
	if frame.AnimIn then
		frame.AnimIn:Stop()
	end
	if frame.AnimOut then
		frame.AnimOut:Stop()
	end
	if frame.PointAnim then
		frame.PointAnim:Stop()
	end
	frame.on = on
	frame.Point:SetAlpha(on and 1 or 0)
	if frame.CircleBurst then
		frame.CircleBurst:SetAlpha(0)
	end
	if frame.Star then
		frame.Star:SetAlpha(0)
	end
	if frame.DashBurst then
		frame.DashBurst:SetAlpha(0)
	end
end

local function UpdateMaxPower(self)
	local maxComboPoints = GetMaxComboPoints()
	if not maxComboPoints or maxComboPoints < 1 then
		maxComboPoints = DEFAULT_MAX
	end

	self.ComboPoints[6]:SetShown(maxComboPoints == 6)
	for i = 1, MAX_BONUS_UI do
		self.ComboBonus[i]:SetShown(DetermineComboBonusVisibility(i, maxComboPoints))
	end

	if maxComboPoints == 5 or maxComboPoints == 8 or maxComboPoints == 10 then
		self.maxUsablePoints = 5
	elseif maxComboPoints == 6 then
		self.maxUsablePoints = 6
	else
		self.maxUsablePoints = math.min(maxComboPoints, DEFAULT_MAX)
	end

	for i = 1, self.maxUsablePoints do
		UpdateComboPointLayout(self.maxUsablePoints, self.ComboPoints[i], self.ComboPoints[i - 1])
	end
end

local function UpdatePower(self, instant)
	if self.delayedUpdate then
		return
	end

	local force = WhoaUF.IsForceShowClassPowerFor
		and (
			WhoaUF:IsForceShowClassPowerFor("ROGUE")
			or (WhoaUF:IsForceShowClassPowerFor("DRUID") and not WhoaUF:HasClassPowerBarFramework())
		)
	local comboPoints, maxComboPoints
	if force then
		comboPoints = DEFAULT_MAX
		maxComboPoints = DEFAULT_MAX
		self.maxUsablePoints = DEFAULT_MAX
	else
		comboPoints = GetNumComboPoints()
		maxComboPoints = GetMaxComboPoints()
		if comboPoints == nil then
			return
		end
	end

	if instant then
		for i = 1, self.maxUsablePoints do
			SetPointInstant(self.ComboPoints[i], i <= comboPoints)
		end
		if maxComboPoints >= 8 then
			for i = 1, MAX_BONUS_UI do
				local idx = i + 5
				SetPointInstant(self.ComboBonus[i], comboPoints >= idx)
			end
		end
		self.lastPower = comboPoints
		return
	end

	-- Spent a finishing move after > maxUsablePoints: fade top row, then rebuild.
	if self.lastPower and self.lastPower > self.maxUsablePoints and comboPoints == self.lastPower - self.maxUsablePoints then
		for i = 1, self.maxUsablePoints do
			AnimOut(self, self.ComboPoints[i])
		end
		self.delayedUpdate = true
		self.lastPower = nil
		C_Timer.After(0.45, function()
			self.delayedUpdate = false
			UpdatePower(self)
		end)
		return
	end

	for i = 1, math.min(comboPoints, self.maxUsablePoints) do
		AnimIn(self, self.ComboPoints[i])
	end
	for i = comboPoints + 1, self.maxUsablePoints do
		AnimOut(self, self.ComboPoints[i])
	end

	if maxComboPoints >= 8 then
		for i = 6, comboPoints do
			AnimIn(self, self.ComboBonus[i - 5])
		end
		for i = math.max(comboPoints + 1, 6), maxComboPoints do
			local bonus = self.ComboBonus[i - 5]
			if bonus then
				AnimOut(self, bonus)
			end
		end
	end

	self.lastPower = comboPoints
end

local function ShouldShowComboPointPlayerBar()
	if WhoaUF.IsForceShowClassPowerFor then
		if WhoaUF:IsForceShowClassPowerFor("ROGUE") then
			return true
		end
		-- Classic feral: DruidComboPointBar.lua is Mainline-only; DevTools force-show uses this tray.
		if WhoaUF:IsForceShowClassPowerFor("DRUID") and not WhoaUF:HasClassPowerBarFramework() then
			return true
		end
	end
	if UnitHasVehiclePlayerFrameUI and UnitHasVehiclePlayerFrameUI("player") then
		return false
	end
	local _, class = UnitClass("player")
	if class == "ROGUE" then
		return true
	end
	-- Classic feral druid: same Legion player-rim tray (no separate DruidComboPointBar module).
	if class == "DRUID" and not WhoaUF:HasClassPowerBarFramework() then
		local energy = (Enum and Enum.PowerType and Enum.PowerType.Energy) or 3
		return UnitPowerType("player") == energy
	end
	return false
end

local pendingShown

local function RefreshVisibility(self)
	local show = ShouldShowComboPointPlayerBar()
	if InCombatLockdown() then
		pendingShown = show
		if self:IsShown() then
			self:SetAlpha(show and 1 or 0)
			if show then
				if WhoaUF.AnchorComboPointPlayerBar then
					WhoaUF:AnchorComboPointPlayerBar()
				end
				UpdateMaxPower(self)
				UpdatePower(self, true)
			end
		end
		return
	end
	pendingShown = nil
	-- Stacked druid: parent to player so tray sits above under-player threat host.
	-- Otherwise UIParent for lockdown-safe Show/Hide while points lock to Whoa player.
	local wantParent = UIParent
	local owner = self.whoaUnitFrame
	if owner and WhoaUF.IsDruidStackedPlayerFrameActive and WhoaUF:IsDruidStackedPlayerFrameActive(owner) then
		wantParent = owner
	end
	if self:GetParent() ~= wantParent then
		self:SetParent(wantParent)
	end
	self:SetAlpha(1)
	self:SetShown(show)
	if show then
		if WhoaUF.AnchorComboPointPlayerBar then
			WhoaUF:AnchorComboPointPlayerBar()
		end
		UpdateMaxPower(self)
		UpdatePower(self, true)
	end
	if WhoaUF.LayoutPlayerBottomFrames then
		WhoaUF:LayoutPlayerBottomFrames()
	end
end

function WhoaUF:GetComboPointPlayerBarAnchor()
	local bars = self.GetRegisteredClassBars and self:GetRegisteredClassBars()
	local x, y = 0, 0
	if bars then
		for i = 1, #bars do
			local layout = bars[i].layout
			if layout and (layout.frameKey == "ComboPointPlayerBar" or layout.frameKey == "RogueComboPointBar") then
				x = layout.defaultX or 0
				y = layout.defaultY or 0
				break
			end
		end
	end
	-- Classic feral sits slightly lower so stacked druid rim clears the tray.
	local _, class = UnitClass("player")
	if class == "DRUID" and not WhoaUF:HasClassPowerBarFramework() then
		y = 22
	end
	return x, y
end

function WhoaUF:GetRogueComboPointBarAnchor()
	return self:GetComboPointPlayerBarAnchor()
end

-- Legion ComboPointPlayerFrame sits on the player rim (not in the pet/totem stack).
function WhoaUF:AnchorComboPointPlayerBar()
	local player = self.unitFrames and self.unitFrames.player
	local anchorFrame = self:GetClassPowerAnchorFrame() or player
	local frame = player and (player.ComboPointPlayerBar or player.RogueComboPointBar)
	if not frame or not anchorFrame then
		return
	end
	local x, y = self:GetComboPointPlayerBarAnchor()
	frame:ClearAllPoints()
	frame:SetPoint("TOP", anchorFrame, "BOTTOM", x, y)
	if self.ApplyComboPointPlayerBarStrata then
		self:ApplyComboPointPlayerBarStrata(player)
	elseif self.ApplyClassPowerFrameLevel then
		self:ApplyClassPowerFrameLevel(frame)
	end
end

function WhoaUF:RefreshComboPointPlayerBar()
	local player = self.unitFrames and self.unitFrames.player
	if not player then
		return
	end
	if not player.ComboPointPlayerBar and not player.RogueComboPointBar then
		self:InitComboPointPlayerBar(player)
	end
	local frame = player.ComboPointPlayerBar or player.RogueComboPointBar
	if frame then
		RefreshVisibility(frame)
	end
end

function WhoaUF:RefreshRogueComboPointBar()
	self:RefreshComboPointPlayerBar()
end

function WhoaUF:InitComboPointPlayerBar(playerFrame)
	if not playerFrame or playerFrame.ComboPointPlayerBar or playerFrame.RogueComboPointBar then
		return
	end
	-- Visibility is ShouldShowComboPointPlayerBar; RegisterClassBar filters class.
	-- Do not early-return on UnitClass here — nil at first init would skip forever.

	local useAtlas = HasComboAtlases()
	local frame = CreateFrame("Frame", "WhoaUFComboPointPlayerBar", UIParent)
	frame.whoaUnitFrame = playerFrame
	frame:SetSize(126, 18)
	frame:Hide()
	frame.ComboPoints = {}
	frame.ComboBonus = {}
	frame.maxUsablePoints = DEFAULT_MAX
	frame.lastPower = nil
	frame.delayedUpdate = false
	frame.whoaBottomPadding = -4
	frame.useAtlas = useAtlas

	local bg = frame:CreateTexture(nil, "OVERLAY")
	bg:SetPoint("TOPLEFT")
	frame.Background = bg
	if useAtlas then
		SetComboAtlas(bg, ATLAS.bg, true)
	else
		bg:Hide()
	end

	for i = 1, MAX_COMBO_UI do
		local cp = CreateComboPoint(frame, useAtlas)
		frame.ComboPoints[i] = cp
		if i == 1 then
			cp:SetPoint("TOPLEFT", 12, -2)
		else
			cp:SetPoint("LEFT", frame.ComboPoints[i - 1], "RIGHT", 1, 0)
		end
		if i == 6 then
			cp:Hide()
		end
	end

	for i = 1, MAX_BONUS_UI do
		local bonus = CreateBonusPoint(frame, useAtlas)
		frame.ComboBonus[i] = bonus
		if i == 1 then
			bonus:SetPoint("TOPLEFT", 7, 0)
		else
			bonus:SetPoint("LEFT", frame.ComboBonus[i - 1], "RIGHT", 12, 0)
		end
	end

	if useAtlas then
		frame:EnableMouse(true)
		frame:SetScript("OnEnter", function(self)
			if GameTooltip_SetDefaultAnchor then
				GameTooltip_SetDefaultAnchor(GameTooltip, self)
			else
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
			end
			GameTooltip:SetText(COMBO_POINTS_POWER or COMBO_POINTS or "Combo Points", 1, 1, 1)
			local _, playerClass = UnitClass("player")
			local tip
			if playerClass == "ROGUE" then
				tip = COMBO_POINTS_ROGUE_TOOLTIP
			elseif playerClass == "DRUID" then
				tip = COMBO_POINTS_DRUID_TOOLTIP
			end
			if tip then
				GameTooltip:AddLine(tip, nil, nil, nil, true)
			end
			GameTooltip:Show()
		end)
		frame:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	local function RegisterComboPointPlayerBarEvents(f)
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("UNIT_DISPLAYPOWER")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		f:RegisterEvent("PLAYER_TARGET_CHANGED")
		f:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
		f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		f:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		pcall(function()
			f:RegisterEvent("COMBO_TARGET_CHANGED")
		end)
		pcall(function()
			f:RegisterEvent("PLAYER_TALENT_UPDATE")
		end)
	end
	self.RegisterComboPointPlayerBarEvents = RegisterComboPointPlayerBarEvents
	self.RegisterRogueComboPointBarEvents = RegisterComboPointPlayerBarEvents
	RegisterComboPointPlayerBarEvents(frame)

	frame:SetScript("OnEvent", function(self, event, unit, powerToken)
		if event == "PLAYER_REGEN_ENABLED" then
			if pendingShown ~= nil then
				RefreshVisibility(self)
			end
			return
		end
		if event == "PLAYER_ENTERING_WORLD"
			or event == "UNIT_DISPLAYPOWER"
			or event == "UPDATE_SHAPESHIFT_FORM"
			or event == "PLAYER_TALENT_UPDATE"
			or event == "UPDATE_VEHICLE_ACTIONBAR"
		then
			RefreshVisibility(self)
			return
		end
		-- GetComboPoints tracks the current target; retarget must refresh counts.
		if event == "PLAYER_TARGET_CHANGED" or event == "COMBO_TARGET_CHANGED" then
			if self:IsShown() and self:GetAlpha() > 0 then
				UpdatePower(self, true)
			else
				RefreshVisibility(self)
			end
			return
		end
		if event == "UNIT_MAXPOWER" then
			if unit == "player" and self:IsShown() and self:GetAlpha() > 0 then
				UpdateMaxPower(self)
				UpdatePower(self, true)
			end
			return
		end
		if event == "UNIT_POWER_FREQUENT" then
			if unit ~= "player" then
				return
			end
			if powerToken and powerToken ~= "COMBO_POINTS" and powerToken ~= GetComboPowerType() then
				return
			end
			if self:IsShown() and self:GetAlpha() > 0 then
				UpdatePower(self)
			else
				RefreshVisibility(self)
			end
		end
	end)

	playerFrame.ComboPointPlayerBar = frame
	-- ComboPointPlayerBar name alias — ClassBars registry still keys RogueComboPointBar.
	playerFrame.RogueComboPointBar = frame
	self:AnchorComboPointPlayerBar()
	RefreshVisibility(frame)
end

function WhoaUF:InitRogueComboPointBar(playerFrame)
	self:InitComboPointPlayerBar(playerFrame)
end

function WhoaUF:ApplyComboPointPlayerBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and (player.ComboPointPlayerBar or player.RogueComboPointBar)
	if not frame then
		return
	end
	-- Re-detect atlases so dark pack / client updates apply after theme toggle.
	local useAtlas = HasComboAtlases()
	frame.useAtlas = useAtlas
	if frame.Background then
		if useAtlas then
			frame.Background:Show()
			SetComboAtlas(frame.Background, ATLAS.bg, true)
		else
			frame.Background:Hide()
		end
	end
	if frame.ComboPoints then
		for i = 1, #frame.ComboPoints do
			ApplyComboPointTextures(frame.ComboPoints[i], useAtlas)
		end
	end
	if frame.ComboBonus then
		for i = 1, #frame.ComboBonus do
			ApplyBonusPointTextures(frame.ComboBonus[i], useAtlas)
		end
	end
	-- Re-apply layout sizes after atlas↔sheet / light↔dark swaps.
	local maxPoints = frame.maxUsablePoints or DEFAULT_MAX
	if frame.ComboPoints then
		for i = 1, math.min(maxPoints, #frame.ComboPoints) do
			UpdateComboPointLayout(maxPoints, frame.ComboPoints[i], frame.ComboPoints[i - 1])
		end
	end
end

function WhoaUF:ApplyRogueComboPointBarArt()
	self:ApplyComboPointPlayerBarArt()
end

if WhoaUF.RegisterClassBar then
	-- Mainline: Rogue only (Druid uses DruidComboPointBar). Classic: Rogue + feral Druid.
	local comboClasses = "ROGUE"
	if not WhoaUF:HasClassPowerBarFramework() then
		comboClasses = { ROGUE = true, DRUID = true }
	end
	WhoaUF:RegisterClassBar({
		classes = comboClasses,
		init = function(uf, player)
			uf:InitComboPointPlayerBar(player)
		end,
		refresh = function(uf)
			uf:RefreshComboPointPlayerBar()
		end,
		applyArt = function(uf)
			uf:ApplyComboPointPlayerBarArt()
		end,
		frameKey = "ComboPointPlayerBar",
		registerEvents = "RegisterComboPointPlayerBarEvents",
		layout = {
			-- Overlay: on player rim like Legion; must not push pet/totem stack.
			-- Classic player chrome: center under 119px status bars (not Legion 50, 38).
			slot = "overlay",
			frameKey = "ComboPointPlayerBar",
			anchor = "AnchorComboPointPlayerBar",
			getAnchor = "GetComboPointPlayerBarAnchor",
			defaultX = 33,
			defaultY = 33,
		},
	})
end
