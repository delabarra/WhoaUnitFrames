--[[
	Heal prediction + absorb overlays on Whoa health bars (Classic flavors only).
	Reference:
	  reference/Blizzard_UnitFrame/Classic/UnitFrame.lua (UnitFrameHealPredictionBars_Update)
	  reference/Blizzard_UnitFrame/Shared/UnitFrame.xml (overlay templates)
	Mainline does not load this file: incoming heals / absorbs are secret there and
	the Lua math below would taint.
]]

local WhoaUF = WhoaUF

local max = math.max
local MAX_INCOMING_HEAL_OVERFLOW = 1.0

local MY_HEAL_R, MY_HEAL_G, MY_HEAL_B, MY_HEAL_A = 0, 0.827, 0.129, 1
local OTHER_HEAL_R, OTHER_HEAL_G, OTHER_HEAL_B, OTHER_HEAL_A = 0, 0.631, 0.557, 1

local ABSORB_FILL = "Interface\\RaidFrame\\Shield-Fill"
local ABSORB_OVERLAY = "Interface\\RaidFrame\\Shield-Overlay"
local HEAL_ABSORB_FILL = "Interface\\RaidFrame\\Absorb-Fill"
local HEAL_ABSORB_EDGE = "Interface\\RaidFrame\\Absorb-Edge"
local OVER_ABSORB_GLOW = "Interface\\RaidFrame\\Shield-Overshield"
local OVER_HEAL_ABSORB_GLOW = "Interface\\RaidFrame\\Absorb-Overabsorb"
local ABSORB_OVERLAY_TILE = 32

local HAS_ABSORB_API = UnitGetTotalAbsorbs ~= nil and UnitGetTotalHealAbsorbs ~= nil

local function GetHealFillTexture(health)
	return WhoaUF:GetResolvedStatusBarTexture(health)
end

local function CreateOverlayTexture(parent, layer, subLevel)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, subLevel or 2)
	tex:Hide()
	return tex
end

local function CreateHealFill(health, r, g, b, a)
	local fill = CreateOverlayTexture(health, "ARTWORK", 1)
	fill:SetVertexColor(r, g, b, a)
	return fill
end

local function SetLayerAbove(region, layer, subLevel, offset)
	if region then
		local sub = subLevel + offset
		if sub > 7 then
			sub = 7
		end
		region:SetDrawLayer(layer, sub)
	end
end

-- StatusBarOverlaySegmentMixin:Initialize — fills one sublevel above the bar
-- texture, tiled overlays / shadows two above.
local function SyncOverlayDrawLayers(health)
	local fill = health:GetStatusBarTexture()
	if not fill then
		return
	end
	local layer, subLevel = fill:GetDrawLayer()
	layer = layer or "ARTWORK"
	subLevel = subLevel or 0
	SetLayerAbove(health.MyHealPrediction, layer, subLevel, 1)
	SetLayerAbove(health.OtherHealPrediction, layer, subLevel, 1)
	SetLayerAbove(health.HealAbsorbBar, layer, subLevel, 1)
	SetLayerAbove(health.TotalAbsorbBar, layer, subLevel, 1)
	SetLayerAbove(health.HealAbsorbLeftShadow, layer, subLevel, 2)
	SetLayerAbove(health.HealAbsorbRightShadow, layer, subLevel, 2)
	SetLayerAbove(health.TotalAbsorbOverlay, layer, subLevel, 2)
end

-- Heal fills reuse the health bar art; resync only when that art changes.
local function SyncHealFillTexture(health)
	local tex = GetHealFillTexture(health)
	if health.whoaHealFillTexture == tex then
		return
	end
	health.whoaHealFillTexture = tex
	health.MyHealPrediction:SetTexture(tex)
	health.OtherHealPrediction:SetTexture(tex)
	SyncOverlayDrawLayers(health)
end

local function AnchorAbsorbGlows(health, overAbsorbGlow, overHealAbsorbGlow)
	overAbsorbGlow:ClearAllPoints()
	overAbsorbGlow:SetPoint("TOPLEFT", health, "TOPRIGHT", -7, 0)
	overAbsorbGlow:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT", -7, 0)
	overHealAbsorbGlow:ClearAllPoints()
	overHealAbsorbGlow:SetPoint("TOPRIGHT", health, "TOPLEFT", 7, 0)
	overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", health, "BOTTOMLEFT", 7, 0)
end

local function HideRegion(region)
	if region then
		region:Hide()
	end
end

local function HideOverlays(frame, health)
	HideRegion(health.MyHealPrediction)
	HideRegion(health.OtherHealPrediction)
	HideRegion(health.HealAbsorbBar)
	HideRegion(health.HealAbsorbLeftShadow)
	HideRegion(health.HealAbsorbRightShadow)
	HideRegion(health.TotalAbsorbBar)
	HideRegion(health.TotalAbsorbOverlay)
	HideRegion(frame.OverAbsorbGlow)
	HideRegion(frame.OverHealAbsorbGlow)
end

-- Places tex over [startPercent, startPercent + amount/maxHealth] of the bar
-- (clamped to the bar end) and returns the segment's end percent.
local function PlaceBarSegment(tex, health, maxHealth, amount, startPercent)
	if amount <= 0 or startPercent >= 1 then
		tex:Hide()
		return startPercent
	end

	local barW = health:GetWidth()
	local barH = health:GetHeight()
	if barW <= 0 or barH <= 0 then
		tex:Hide()
		return startPercent
	end

	local endPercent = startPercent + (amount / maxHealth)
	if endPercent > 1 then
		endPercent = 1
	end

	local startX = startPercent * barW
	local w = (endPercent - startPercent) * barW
	if w <= 0 then
		tex:Hide()
		return startPercent
	end

	tex:SetWidth(w)
	tex:SetHeight(barH)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", health, "TOPLEFT", startX, 0)
	tex:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", startX, 0)
	tex:SetTexCoord(startPercent, endPercent, 0, 1)
	tex:Show()
	return endPercent
end

local function SyncTotalAbsorbOverlay(overlay, absorbTex, barH)
	if not overlay then
		return
	end
	if not absorbTex:IsShown() then
		overlay:Hide()
		return
	end
	local w = absorbTex:GetWidth()
	if not w or w <= 0 then
		overlay:Hide()
		return
	end
	overlay:ClearAllPoints()
	overlay:SetAllPoints(absorbTex)
	overlay:SetTexCoord(0, w / ABSORB_OVERLAY_TILE, 0, barH / ABSORB_OVERLAY_TILE)
	overlay:Show()
end

local function SyncHealAbsorbShadows(health, showLeft, showRight)
	local healAbsorbTex = health.HealAbsorbBar
	local leftShadow = health.HealAbsorbLeftShadow
	local rightShadow = health.HealAbsorbRightShadow
	if not healAbsorbTex:IsShown() then
		leftShadow:Hide()
		rightShadow:Hide()
		return
	end
	if showLeft then
		leftShadow:ClearAllPoints()
		leftShadow:SetPoint("TOPLEFT", healAbsorbTex, "TOPLEFT", 0, 0)
		leftShadow:SetPoint("BOTTOMLEFT", healAbsorbTex, "BOTTOMLEFT", 0, 0)
		leftShadow:Show()
	else
		leftShadow:Hide()
	end
	if showRight then
		rightShadow:ClearAllPoints()
		rightShadow:SetPoint("TOPLEFT", healAbsorbTex, "TOPRIGHT", -8, 0)
		rightShadow:SetPoint("BOTTOMLEFT", healAbsorbTex, "BOTTOMRIGHT", -8, 0)
		rightShadow:Show()
	else
		rightShadow:Hide()
	end
end

function WhoaUF:AttachHealPrediction(frame)
	local health = frame and frame.Health
	if not health or health.whoaHealPredictionAttached then
		return
	end
	health.whoaHealPredictionAttached = true
	if health.SetClipsChildren then
		health:SetClipsChildren(true)
	end

	health.MyHealPrediction = CreateHealFill(health, MY_HEAL_R, MY_HEAL_G, MY_HEAL_B, MY_HEAL_A)
	health.OtherHealPrediction = CreateHealFill(health, OTHER_HEAL_R, OTHER_HEAL_G, OTHER_HEAL_B, OTHER_HEAL_A)
	SyncHealFillTexture(health)

	if not HAS_ABSORB_API then
		return
	end

	local healAbsorb = CreateOverlayTexture(health, "ARTWORK", 2)
	healAbsorb:SetTexture(HEAL_ABSORB_FILL)
	health.HealAbsorbBar = healAbsorb

	local leftShadow = CreateOverlayTexture(health, "ARTWORK", 3)
	leftShadow:SetTexture(HEAL_ABSORB_EDGE)
	health.HealAbsorbLeftShadow = leftShadow

	local rightShadow = CreateOverlayTexture(health, "ARTWORK", 3)
	rightShadow:SetTexture(HEAL_ABSORB_EDGE)
	rightShadow:SetTexCoord(1, 0, 0, 1)
	health.HealAbsorbRightShadow = rightShadow

	local totalAbsorb = CreateOverlayTexture(health, "ARTWORK", 2)
	totalAbsorb:SetTexture(ABSORB_FILL)
	health.TotalAbsorbBar = totalAbsorb

	local totalOverlay = CreateOverlayTexture(health, "ARTWORK", 3)
	totalOverlay:SetTexture(ABSORB_OVERLAY, "REPEAT", "REPEAT")
	health.TotalAbsorbOverlay = totalOverlay

	local glowParent = frame.Overlay or health:GetParent() or frame
	local overAbsorbGlow = CreateOverlayTexture(glowParent, "OVERLAY", 0)
	overAbsorbGlow:SetTexture(OVER_ABSORB_GLOW)
	overAbsorbGlow:SetBlendMode("ADD")
	overAbsorbGlow:SetWidth(16)
	frame.OverAbsorbGlow = overAbsorbGlow

	local overHealAbsorbGlow = CreateOverlayTexture(glowParent, "OVERLAY", 0)
	overHealAbsorbGlow:SetTexture(OVER_HEAL_ABSORB_GLOW)
	overHealAbsorbGlow:SetBlendMode("ADD")
	overHealAbsorbGlow:SetWidth(16)
	frame.OverHealAbsorbGlow = overHealAbsorbGlow

	AnchorAbsorbGlows(health, overAbsorbGlow, overHealAbsorbGlow)
	SyncOverlayDrawLayers(health)
end

function WhoaUF:HideHealPrediction(frame)
	local health = frame and frame.Health
	if health then
		HideOverlays(frame, health)
	end
end

function WhoaUF:SyncHealPredictionLayout(frame)
	if frame then
		self:UpdateHealPrediction(frame)
	end
end

function WhoaUF:ApplyHealPredictionTextures()
	local uf = self.unitFrames
	if not uf then
		return
	end
	for _, frame in pairs(uf) do
		if type(frame) == "table" and frame.Health then
			self:UpdateHealPrediction(frame)
		end
	end
end

function WhoaUF:UpdateHealPrediction(frame)
	local health = frame and frame.Health
	if not health then
		return
	end
	if not health.whoaHealPredictionAttached then
		self:AttachHealPrediction(frame)
	end

	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		HideOverlays(frame, health)
		return
	end

	local _, maxHealth = health:GetMinMaxValues()
	local cur = health:GetValue() or 0
	if not maxHealth or maxHealth <= 0 or health:GetWidth() <= 0 then
		HideOverlays(frame, health)
		return
	end

	local myIncomingHeal = 0
	local allIncomingHeal = 0
	if UnitGetIncomingHeals and GetCVar("unitFramesDisplayIncomingHeals") ~= "0" then
		myIncomingHeal = UnitGetIncomingHeals(unit, "player") or 0
		allIncomingHeal = UnitGetIncomingHeals(unit) or 0
	end

	local healAbsorbFill = health.HealAbsorbBar
	local totalAbsorb = 0
	local myCurrentHealAbsorb = 0
	if healAbsorbFill then
		totalAbsorb = UnitGetTotalAbsorbs(unit) or 0
		myCurrentHealAbsorb = UnitGetTotalHealAbsorbs(unit) or 0

		-- Heal absorbs never fill outside the health bar; overHealAbsorbGlow shows instead.
		if cur < myCurrentHealAbsorb then
			frame.OverHealAbsorbGlow:Show()
			myCurrentHealAbsorb = cur
		else
			frame.OverHealAbsorbGlow:Hide()
		end
	end

	if cur - myCurrentHealAbsorb + allIncomingHeal > maxHealth * MAX_INCOMING_HEAL_OVERFLOW then
		allIncomingHeal = maxHealth * MAX_INCOMING_HEAL_OVERFLOW - cur + myCurrentHealAbsorb
	end

	local otherIncomingHeal = 0
	if allIncomingHeal >= myIncomingHeal then
		otherIncomingHeal = allIncomingHeal - myIncomingHeal
	else
		myIncomingHeal = allIncomingHeal
	end

	-- Absorbs never fill outside the health bar; overAbsorbGlow shows instead.
	local overAbsorb = false
	if cur - myCurrentHealAbsorb + allIncomingHeal + totalAbsorb >= maxHealth or cur + totalAbsorb >= maxHealth then
		if totalAbsorb > 0 then
			overAbsorb = true
		end
		if allIncomingHeal > myCurrentHealAbsorb then
			totalAbsorb = max(0, maxHealth - (cur - myCurrentHealAbsorb + allIncomingHeal))
		else
			totalAbsorb = max(0, maxHealth - cur)
		end
	end
	if frame.OverAbsorbGlow then
		frame.OverAbsorbGlow:SetShown(overAbsorb)
	end

	if healAbsorbFill then
		-- Incoming heals larger than the heal absorb fully cover it.
		if myCurrentHealAbsorb > allIncomingHeal then
			local shownHealAbsorb = myCurrentHealAbsorb - allIncomingHeal
			PlaceBarSegment(healAbsorbFill, health, maxHealth, shownHealAbsorb, (cur - shownHealAbsorb) / maxHealth)
			SyncHealAbsorbShadows(health, allIncomingHeal <= 0, totalAbsorb > 0)
		else
			healAbsorbFill:Hide()
			SyncHealAbsorbShadows(health, false, false)
		end
	end

	SyncHealFillTexture(health)
	local chainEndPercent = (cur - myCurrentHealAbsorb) / maxHealth
	chainEndPercent = PlaceBarSegment(health.MyHealPrediction, health, maxHealth, myIncomingHeal, chainEndPercent)
	chainEndPercent = PlaceBarSegment(health.OtherHealPrediction, health, maxHealth, otherIncomingHeal, chainEndPercent)

	local totalAbsorbFill = health.TotalAbsorbBar
	if totalAbsorbFill then
		-- Append after the heal absorb (which ends at current health) or the incoming heals.
		local healthEndPercent = cur / maxHealth
		if chainEndPercent < healthEndPercent then
			chainEndPercent = healthEndPercent
		end
		PlaceBarSegment(totalAbsorbFill, health, maxHealth, totalAbsorb, chainEndPercent)
		SyncTotalAbsorbOverlay(health.TotalAbsorbOverlay, totalAbsorbFill, health:GetHeight())
	end
end
