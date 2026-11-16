--[[
	Secret-safe heal prediction + damage absorbs for Mainline / Forever / Camelot.

	Classic PlaceBarSegment math cannot run on secret health/heal values. Mirror
	Stormx: CreateUnitHealPredictionCalculator + UnitGetDetailedHealPrediction,
	feed results straight into StatusBar SetMinMaxValues/SetValue (no Lua compare
	or arithmetic on those numbers).

	Layout: prediction StatusBar spans from the live health fill's right edge to
	the bar end (remaining missing-health space). Absorb StatusBar chains from
	the prediction fill's right edge so stacking needs no secret math.

	Visual parity with stock absorb: Shield-Fill StatusBar (secret-safe SetValue)
	+ Shield-Overlay tiled via wrap/SetAllPoints on the fill (CUF-style — no
	GetWidth/TexCoord math) + OverAbsorbGlow from calculator clamped bool
	(IsAccessibleTrue). Same idea as native target auras: C APIs / engine layout,
	never Lua measure of secret geometry.
]]

local WhoaUF = WhoaUF

local MY_HEAL_R, MY_HEAL_G, MY_HEAL_B, MY_HEAL_A = 0, 0.827, 0.129, 0.85
local ABSORB_R, ABSORB_G, ABSORB_B, ABSORB_A = 0.85, 0.85, 1, 0.7
local ABSORB_FILL = "Interface\\RaidFrame\\Shield-Fill"
local ABSORB_OVERLAY = "Interface\\RaidFrame\\Shield-Overlay"
local OVER_ABSORB_GLOW = "Interface\\RaidFrame\\Shield-Overshield"

local function NativeApiReady()
	return type(CreateUnitHealPredictionCalculator) == "function"
		and type(UnitGetDetailedHealPrediction) == "function"
end

local function IncomingHealsEnabled()
	if not GetCVar then
		return true
	end
	local ok, value = pcall(GetCVar, "unitFramesDisplayIncomingHeals")
	return not ok or value ~= "0"
end

local function SyncBarTexture(bar, health)
	if not bar or not health then
		return
	end
	local tex
	if WhoaUF.GetResolvedStatusBarTexture then
		tex = WhoaUF:GetResolvedStatusBarTexture(health)
	end
	if type(tex) == "string" and tex ~= "" and bar.whoaHealTex ~= tex then
		bar.whoaHealTex = tex
		bar:SetStatusBarTexture(tex)
	end
end

-- CUF: overlay SetAllPoints(absorb fill) + wrap tile — never read fill size.
local function SyncAbsorbOverlay(absorb, overlay)
	if not overlay then
		return
	end
	if not absorb or not absorb:IsShown() then
		overlay:Hide()
		return
	end
	local fill = absorb.GetStatusBarTexture and absorb:GetStatusBarTexture()
	if not fill then
		overlay:Hide()
		return
	end
	overlay:ClearAllPoints()
	overlay:SetAllPoints(fill)
	overlay:Show()
end

local function HideRegion(region)
	if region then
		region:Hide()
	end
end

local function HideOverlays(frame, health)
	health = health or (frame and frame.Health)
	if not health then
		return
	end
	HideRegion(health.whoaNativeHealPrediction)
	HideRegion(health.whoaNativeAbsorb)
	HideRegion(health.whoaNativeAbsorbOverlay)
	if frame then
		HideRegion(frame.OverAbsorbGlow)
	else
		HideRegion(health.whoaNativeOverAbsorbGlow)
	end
end

local function AnchorOverAbsorbGlow(health, glow)
	if not health or not glow then
		return
	end
	glow:ClearAllPoints()
	glow:SetPoint("TOPLEFT", health, "TOPRIGHT", -7, 0)
	glow:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT", -7, 0)
end

function WhoaUF:AttachHealPrediction(frame)
	if not NativeApiReady() then
		return
	end
	local health = frame and frame.Health
	if not health or health.whoaNativeHealPredictionAttached then
		return
	end
	health.whoaNativeHealPredictionAttached = true

	if health.SetClipsChildren then
		pcall(health.SetClipsChildren, health, true)
	end

	local calc = CreateUnitHealPredictionCalculator()
	if calc and calc.SetToDefaults then
		pcall(calc.SetToDefaults, calc)
	end
	health.whoaHealPredictionCalculator = calc

	local predict = CreateFrame("StatusBar", nil, health)
	predict:SetStatusBarColor(MY_HEAL_R, MY_HEAL_G, MY_HEAL_B, MY_HEAL_A)
	predict:SetFrameLevel(health:GetFrameLevel() + 2)
	predict:Hide()
	health.whoaNativeHealPrediction = predict
	SyncBarTexture(predict, health)

	local absorb = CreateFrame("StatusBar", nil, health)
	absorb:SetStatusBarTexture(ABSORB_FILL)
	absorb:SetStatusBarColor(ABSORB_R, ABSORB_G, ABSORB_B, ABSORB_A)
	absorb:SetFrameLevel(health:GetFrameLevel() + 3)
	absorb:Hide()
	health.whoaNativeAbsorb = absorb

	-- Diagonal shield lines: engine wrap-tile on the fill (no Lua size→TexCoord).
	local overlay = absorb:CreateTexture(nil, "ARTWORK", nil, 1)
	overlay:SetTexture(ABSORB_OVERLAY, "REPEAT", "REPEAT")
	if overlay.SetHorizTile then
		overlay:SetHorizTile(true)
		overlay:SetVertTile(true)
	end
	overlay:Hide()
	health.whoaNativeAbsorbOverlay = overlay

	local glowParent = frame.Overlay or health:GetParent() or frame
	local overAbsorbGlow = glowParent:CreateTexture(nil, "OVERLAY", nil, 0)
	overAbsorbGlow:SetTexture(OVER_ABSORB_GLOW)
	overAbsorbGlow:SetBlendMode("ADD")
	overAbsorbGlow:SetWidth(16)
	overAbsorbGlow:Hide()
	frame.OverAbsorbGlow = overAbsorbGlow
	health.whoaNativeOverAbsorbGlow = overAbsorbGlow
	AnchorOverAbsorbGlow(health, overAbsorbGlow)
end

function WhoaUF:HideHealPrediction(frame)
	HideOverlays(frame, frame and frame.Health)
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
			local health = frame.Health
			SyncBarTexture(health.whoaNativeHealPrediction, health)
			self:UpdateHealPrediction(frame)
		end
	end
end

function WhoaUF:UpdateHealPrediction(frame)
	if not NativeApiReady() then
		return
	end
	local health = frame and frame.Health
	if not health then
		return
	end
	if not health.whoaNativeHealPredictionAttached then
		self:AttachHealPrediction(frame)
	end

	local calc = health.whoaHealPredictionCalculator
	local predict = health.whoaNativeHealPrediction
	local absorb = health.whoaNativeAbsorb
	local overlay = health.whoaNativeAbsorbOverlay
	local overAbsorbGlow = frame.OverAbsorbGlow or health.whoaNativeOverAbsorbGlow
	if not calc or not predict then
		return
	end

	local unit = frame.unit
	if not unit or not WhoaUF:IsAccessibleTrue(UnitExists(unit)) then
		HideOverlays(frame, health)
		return
	end

	local fill = health.GetStatusBarTexture and health:GetStatusBarTexture()
	if not fill then
		HideOverlays(frame, health)
		return
	end

	SyncBarTexture(predict, health)
	AnchorOverAbsorbGlow(health, overAbsorbGlow)

	-- Prediction frame = remaining health space (fill end → bar end).
	predict:ClearAllPoints()
	predict:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
	predict:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)

	local healsOk = false
	if IncomingHealsEnabled() then
		local ok, updated = pcall(function()
			UnitGetDetailedHealPrediction(unit, "player", calc)
			if calc.GetMaximumIncomingHeals and calc.GetTotalIncomingHeals then
				predict:SetMinMaxValues(0, calc:GetMaximumIncomingHeals())
				predict:SetValue(calc:GetTotalIncomingHeals())
			elseif calc.GetMaximumHealth and calc.GetIncomingHeals then
				predict:SetMinMaxValues(0, calc:GetMaximumHealth())
				predict:SetValue(calc:GetIncomingHeals())
			else
				return false
			end
			return true
		end)
		healsOk = ok and updated == true
	end
	predict:SetShown(healsOk)

	if not absorb then
		return
	end

	-- Absorbs chain after the prediction fill (0-width when no heals / bar hidden).
	local predictFill = predict:GetStatusBarTexture()
	local absorbAnchor = (healsOk and predictFill) or fill
	absorb:ClearAllPoints()
	absorb:SetPoint("TOPLEFT", absorbAnchor, "TOPRIGHT", 0, 0)
	absorb:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)

	local absorbOk = false
	local overAbsorb = false
	local okA, updatedA = pcall(function()
		-- Calculator already refreshed above when heals ran; refresh when heals skipped.
		if not healsOk then
			UnitGetDetailedHealPrediction(unit, "player", calc)
		end
		if calc.GetMaximumDamageAbsorbs and calc.GetDamageAbsorbs then
			absorb:SetMinMaxValues(0, calc:GetMaximumDamageAbsorbs())
			-- amount may be secret; clamped is the overshield signal (use IsAccessibleTrue).
			local amount, clamped = calc:GetDamageAbsorbs()
			absorb:SetValue(amount)
			overAbsorb = WhoaUF:IsAccessibleTrue(clamped)
		elseif calc.GetMaximumHealth and calc.GetTotalDamageAbsorbs then
			absorb:SetMinMaxValues(0, calc:GetMaximumHealth())
			absorb:SetValue(calc:GetTotalDamageAbsorbs())
			overAbsorb = false
		else
			return false
		end
		return true
	end)
	absorbOk = okA and updatedA == true
	absorb:SetShown(absorbOk)
	SyncAbsorbOverlay(absorb, overlay)
	if overAbsorbGlow then
		overAbsorbGlow:SetShown(absorbOk and overAbsorb)
	end
end
