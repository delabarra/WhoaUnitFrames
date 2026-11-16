--[[
	Personal Resource Display (PRD):

	1) Dark rim / combo-socket tint (no atlas / BLP remap).
	   Health/power rims: atlas UI-HUD-CoolDownManager-Bar-BG → DarkMode gray + desaturate.
	   Forever RogueComboPointTemplate sockets (BG* / ChargedFrame*): same gray on stock
	   client atlases. Filled Icon*/FX*/Slash* stay Forever stock.
	   frameDark on → tint; frameDark off → restore white vertex + no desaturate.
	   Combo sockets use RGB-only SetVertexColor so RogueComboPoint Alpha anims keep
	   driving visibility (never force alpha to 1 on clear/tint).

	2) Power spender trail + mana-cost prediction: Blizzard inits FeedbackFrame
	   color-only (XML default UI-StatusBar) while HP/power fills use
	   UI-HUD-CoolDownManager-Bar. Re-apply fill atlas after mixin UpdatePowerBar
	   (never hook/replace FeedbackFrame.Initialize; never instance-hooksecurefunc
	   PRD mixin methods — nil original → Swatter on UpdatePowerBar/Initialize/
	   UpdateMaxPower). LossGlow stays UI-StatusBar-Glow.
	   Raise Bar-BG above ARTWORK so the fill/spender trail sits behind the rim.

	3) Rage / runic FullPowerFrame spark+pulse: stock UpdatePowerBar hardcodes
	   FullPowerFrame / Spike / Pulse to 86×6 while Edit Mode power height defaults
	   ~15 (and up to 30). Scale those frames + AlertSpike / Yellow+Soft glow /
	   BigSpike to the live PowerBar size so the trail matches the filler.
	   Never call FullPowerFrame:Initialize / write .active — that taints stock
	   active; PRD OnUpdate → StartAnimIfFull then fails secret newValue compares
	   (BuilderSpenderFrame.lua) as "tainted by WhoaUnitFrames". Layout-only.
	   Reparent FullPowerFrame under the PRD host at PowerBar level-1 so spike/glow
	   paint behind the StatusBar fill and FeedbackFrame spender (stock child draws on top).
]]

local WhoaUF = WhoaUF

-- DarkMode colors.lua DMColorModeValues["Dark"]
local PRD_R, PRD_G, PRD_B, PRD_A = 0.360, 0.360, 0.360, 1
local PRD_BORDER_ATLAS = "UI-HUD-CoolDownManager-Bar-BG"
local PRD_FILL_ATLAS = "UI-HUD-CoolDownManager-Bar"
local FALLBACK_SPENDER_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

-- Stock PersonalResourceDisplayMixin:UpdatePowerBar FullPowerFrame sizes (ref h=6).
local PRD_FULL_REF_H = 6
local PRD_FULL_STOCK_W, PRD_FULL_STOCK_H = 86, 6
local PRD_ALERT_STOCK_W, PRD_ALERT_STOCK_H = 30, 12
local PRD_PULSE_STOCK_W, PRD_PULSE_STOCK_H = 20, 20
-- BigSpikeGlow is useAtlasSize in BuilderSpenderFrame.xml; Classic pulse uses 42×24
-- on a 12px bar → 21×12 at the PRD 6px reference height.
local PRD_SPIKE_STOCK_W, PRD_SPIKE_STOCK_H = 21, 12

-- Forever empty-socket / charged-frame chrome (RogueComboPoint.xml) plus
-- Mainline Druid UF-DruidCP_* keys (BG_Shadow etc.).
local COMBO_BG_KEYS = {
	"BGShadow",
	"BGActive",
	"BGInactive",
	"BGGlow",
	"BG_Shadow",
	"BG_Active",
	"BG_Inactive",
	"BG_Glow",
	"ChargedFrameInactive",
	"ChargedFrameActive",
	"ChargedFrameGlow",
}

local tintActive
local hooked
local watched
local barRegionScratch = {}
local childScratch = {}
local nestedScratch = {}

local function PackVarArgs(into, ...)
	wipe(into)
	local n = select("#", ...)
	for i = 1, n do
		into[i] = select(i, ...)
	end
	return n
end

local function GetPrdFrame()
	local frame = PersonalResourceDisplayFrame
	if WhoaUF:IsLiveFrame(frame) then
		return frame
	end
	return nil
end

-- Bar rim: may set alpha. Combo bg: RGB only (preserve anim alpha).
local function TintTexture(texture, withAlpha)
	if not texture or not texture.SetVertexColor then
		return
	end
	texture.whoaUFPrdTinted = true
	if texture.SetDesaturated then
		pcall(texture.SetDesaturated, texture, true)
	end
	if not texture.whoaUFPrdHooked then
		texture.whoaUFPrdHooked = true
		hooksecurefunc(texture, "SetVertexColor", function(self)
			if self.whoaUFPrdApplying or not tintActive or not self.whoaUFPrdTinted then
				return
			end
			self.whoaUFPrdApplying = true
			if self.whoaUFPrdComboBg then
				self:SetVertexColor(PRD_R, PRD_G, PRD_B)
			else
				self:SetVertexColor(PRD_R, PRD_G, PRD_B, PRD_A)
			end
			self.whoaUFPrdApplying = false
		end)
	end
	texture.whoaUFPrdApplying = true
	if withAlpha then
		pcall(texture.SetVertexColor, texture, PRD_R, PRD_G, PRD_B, PRD_A)
	else
		pcall(texture.SetVertexColor, texture, PRD_R, PRD_G, PRD_B)
	end
	texture.whoaUFPrdApplying = false
end

local function ClearTexture(texture)
	if not texture or not texture.SetVertexColor then
		return
	end
	if texture.SetDesaturated then
		pcall(texture.SetDesaturated, texture, false)
	end
	texture.whoaUFPrdApplying = true
	-- Never pass alpha — combo fxTextures are Alpha-anim driven.
	pcall(texture.SetVertexColor, texture, 1, 1, 1)
	texture.whoaUFPrdApplying = false
end

local function GetPrdBarBorder(bar)
	if not bar then
		return nil
	end
	local cached = bar.whoaUFPrdBorder
	if cached and cached.GetAtlas and (cached.whoaUFPrdTinted or cached:GetAtlas() == PRD_BORDER_ATLAS) then
		return cached
	end
	if not bar.GetRegions then
		return nil
	end
	local ok, regionCount = pcall(function()
		return PackVarArgs(barRegionScratch, bar:GetRegions())
	end)
	if not ok then
		return nil
	end
	for i = 1, regionCount do
		local region = barRegionScratch[i]
		if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.GetAtlas then
			if region:GetAtlas() == PRD_BORDER_ATLAS or region.whoaUFPrdTinted then
				bar.whoaUFPrdBorder = region
				return region
			end
		end
	end
	return nil
end

local function ClearMistintedBarFill(bar)
	if not bar or not bar.GetStatusBarTexture then
		return
	end
	local fill = bar:GetStatusBarTexture()
	if fill and fill.whoaUFPrdHooked and fill ~= bar.whoaUFPrdBorder then
		fill.whoaUFPrdTinted = nil
		ClearTexture(fill)
	end
end

local function ApplyBarBorder(texture, enable)
	if not texture then
		return
	end
	texture.whoaUFPrdComboBg = nil
	if enable then
		TintTexture(texture, true)
	else
		texture.whoaUFPrdTinted = nil
		ClearTexture(texture)
	end
end

-- Stock Bar-BG is BACKGROUND under FeedbackFrame ARTWORK; raise rim over the spender.
local function RaisePrdBarBorder(bar, enable)
	local border = GetPrdBarBorder(bar)
	if not border or not border.SetDrawLayer then
		return
	end
	if enable then
		border:SetDrawLayer("ARTWORK", 7)
	else
		border:SetDrawLayer("BACKGROUND", 0)
	end
end

local function ApplyComboBg(texture, enable)
	if not texture then
		return
	end
	texture.whoaUFPrdComboBg = true
	if enable then
		TintTexture(texture, false)
	else
		texture.whoaUFPrdTinted = nil
		ClearTexture(texture)
	end
end

local function VisitComboOnPoint(point)
	if not point then
		return
	end
	for i = 1, #COMBO_BG_KEYS do
		ApplyComboBg(point[COMBO_BG_KEYS[i]], tintActive)
	end
end

local function VisitComboPoints()
	local frame = GetPrdFrame()
	if not frame then
		return
	end
	local classFrame = frame.classFrame
	local buttons = classFrame and classFrame.classResourceButtonTable
	if buttons then
		for i = 1, #buttons do
			VisitComboOnPoint(buttons[i])
		end
		return
	end
	local container = frame.ClassFrameContainer
	if not container or not container.GetChildren then
		return
	end
	local ok, childCount = pcall(function()
		return PackVarArgs(childScratch, container:GetChildren())
	end)
	if not ok then
		return
	end
	for i = 1, childCount do
		local child = childScratch[i]
		if child then
			VisitComboOnPoint(child)
			if child.GetChildren then
				local nestedOk, nestedCount = pcall(function()
					return PackVarArgs(nestedScratch, child:GetChildren())
				end)
				if nestedOk then
					for j = 1, nestedCount do
						VisitComboOnPoint(nestedScratch[j])
					end
				end
			end
		end
	end
end

local function VisitOnePrdBarBorder(bar, raiseBorder)
	ClearMistintedBarFill(bar)
	ApplyBarBorder(GetPrdBarBorder(bar), tintActive)
	RaisePrdBarBorder(bar, raiseBorder)
end

local function VisitPrdBarBorders(raiseBorder)
	local frame = GetPrdFrame()
	if not frame then
		return
	end
	local health = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar
	VisitOnePrdBarBorder(health, raiseBorder)
	VisitOnePrdBarBorder(frame.PowerBar, raiseBorder)
	VisitOnePrdBarBorder(frame.AlternatePowerBar, raiseBorder)
end

-- Copy the power fill onto a raw Texture (spender BarTexture / mana prediction).
local function ApplyPowerFillToTexture(texture, powerBar, enable)
	if not texture then
		return
	end
	if not enable then
		if texture.SetTexture then
			pcall(texture.SetTexture, texture, FALLBACK_SPENDER_TEXTURE)
		end
		return
	end
	local fill = powerBar and powerBar.GetStatusBarTexture and powerBar:GetStatusBarTexture()
	local atlas = fill and fill.GetAtlas and fill:GetAtlas()
	if atlas and atlas ~= "" and texture.SetAtlas then
		pcall(texture.SetAtlas, texture, atlas, false)
	elseif fill and fill.GetTexture then
		local file = fill:GetTexture()
		if file and texture.SetTexture then
			if texture.SetAtlas then
				pcall(texture.SetAtlas, texture, nil)
			end
			pcall(texture.SetTexture, texture, file)
		elseif texture.SetAtlas then
			pcall(texture.SetAtlas, texture, PRD_FILL_ATLAS, false)
		end
	elseif texture.SetAtlas then
		pcall(texture.SetAtlas, texture, PRD_FILL_ATLAS, false)
	end
	-- Match the StatusBar tint (SetStatusBarColor → fill vertex color).
	if fill and fill.GetVertexColor and texture.SetVertexColor then
		local r, g, b = fill:GetVertexColor()
		if r then
			pcall(texture.SetVertexColor, texture, r, g, b)
		end
	end
end

local function SyncPowerSpenderTexture(enable)
	local frame = GetPrdFrame()
	local powerBar = frame and frame.PowerBar
	if not powerBar then
		return
	end
	local feedback = powerBar.FeedbackFrame
	ApplyPowerFillToTexture(feedback and feedback.BarTexture, powerBar, enable)
	ApplyPowerFillToTexture(powerBar.ManaCostPredictionBar, powerBar, enable)
	RaisePrdBarBorder(powerBar, enable)
end

local function SafeBarSize(powerBar)
	if not powerBar or not powerBar.GetWidth or not powerBar.GetHeight then
		return nil, nil
	end
	local barW, barH = powerBar:GetWidth(), powerBar:GetHeight()
	if WhoaUF.CanAccessValue then
		if not WhoaUF:CanAccessValue(barW) or not WhoaUF:CanAccessValue(barH) then
			return nil, nil
		end
	end
	if type(barW) ~= "number" or type(barH) ~= "number" or barW <= 0 or barH <= 0 then
		return nil, nil
	end
	return barW, barH
end

local function ResolvePrdPowerKeys(frame)
	local powerToken = frame and frame.powerToken
	local powerType = frame and frame.powerType
	if powerToken ~= nil or powerType ~= nil then
		return powerToken, powerType
	end
	if not UnitPowerType then
		return nil, nil
	end
	local ok, pType, pToken = pcall(UnitPowerType, "player")
	if not ok then
		return nil, nil
	end
	return pToken, pType
end

local function ApplyPrdFullPowerStockSize(full)
	local spike = full.SpikeFrame
	local pulse = full.PulseFrame
	full:SetSize(PRD_FULL_STOCK_W, PRD_FULL_STOCK_H)
	if spike then
		spike:SetSize(PRD_FULL_STOCK_W, PRD_FULL_STOCK_H)
		if spike.AlertSpikeStay then
			spike.AlertSpikeStay:SetSize(PRD_ALERT_STOCK_W, PRD_ALERT_STOCK_H)
		end
		if spike.BigSpikeGlow then
			spike.BigSpikeGlow:SetSize(PRD_SPIKE_STOCK_W, PRD_SPIKE_STOCK_H)
		end
	end
	if pulse then
		pulse:SetSize(PRD_FULL_STOCK_W, PRD_FULL_STOCK_H)
		if pulse.YellowGlow then
			pulse.YellowGlow:SetSize(PRD_PULSE_STOCK_W, PRD_PULSE_STOCK_H)
		end
		if pulse.SoftGlow then
			pulse.SoftGlow:SetSize(PRD_PULSE_STOCK_W, PRD_PULSE_STOCK_H)
		end
	end
end

-- Stock: FullPowerFrame is a PowerBar child (draws over fill + FeedbackFrame).
local function RestorePrdFullPowerStockParent(full, powerBar)
	if not full or not powerBar then
		return
	end
	if full.GetParent and full:GetParent() ~= powerBar then
		full:SetParent(powerBar)
	end
	full:ClearAllPoints()
	full:SetPoint("RIGHT")
	full.whoaUFPrdBehindFill = nil
end

-- Sibling under the PRD host, one level below PowerBar, so StatusBar fill and
-- FeedbackFrame (useParentLevel) paint over spike/pulse.
local function PlacePrdFullPowerBehindFill(full, powerBar)
	if not full or not powerBar or not powerBar.GetParent then
		return
	end
	local host = powerBar:GetParent()
	if not host then
		return
	end
	local powerLevel = powerBar:GetFrameLevel()
	if WhoaUF.CanAccessValue and not WhoaUF:CanAccessValue(powerLevel) then
		return
	end
	if type(powerLevel) ~= "number" then
		return
	end
	if full.GetParent and full:GetParent() ~= host then
		full:SetParent(host)
	end
	local level = powerLevel > 0 and (powerLevel - 1) or 0
	full:SetFrameLevel(level)
	if full.PulseFrame then
		full.PulseFrame:SetFrameLevel(level)
	end
	if full.SpikeFrame then
		full.SpikeFrame:SetFrameLevel(level)
	end
	full:ClearAllPoints()
	full:SetPoint("TOPLEFT", powerBar, "TOPLEFT")
	full:SetPoint("BOTTOMRIGHT", powerBar, "BOTTOMRIGHT")
	full.whoaUFPrdBehindFill = true
end

-- Scale FullPowerFrame spark/pulse from Blizzard's hardcoded 6px layout to the live
-- PowerBar fill height (Edit Mode default ~15) for rage/runic only.
-- Layout/reparent only — never FullPowerFrame:Initialize / RemoveAnims / .active
-- writes (taints stock StartAnimIfFull vs secret UnitPower on Midnight).
-- Ref: Blizzard_PersonalResourceDisplay.lua UpdatePowerBar / OnUpdate.
local function SyncPrdFullPowerGlow(enable)
	local frame = GetPrdFrame()
	local powerBar = frame and frame.PowerBar
	-- parentKey survives reparent; always resolve from PowerBar.
	local full = powerBar and powerBar.FullPowerFrame
	if not full then
		return
	end

	local powerToken, powerType = ResolvePrdPowerKeys(frame)
	local wantWhoaGlow = enable and WhoaUF.WantsFullPowerAnim
		and WhoaUF:WantsFullPowerAnim(powerToken, powerType)

	if not wantWhoaGlow then
		-- Leave stock Initialize(info.fullPowerAnim) alone (ENERGY may pulse).
		RestorePrdFullPowerStockParent(full, powerBar)
		ApplyPrdFullPowerStockSize(full)
		return
	end

	local barW, barH = SafeBarSize(powerBar)
	if not barW then
		return
	end
	PlacePrdFullPowerBehindFill(full, powerBar)
	local scale = barH / PRD_FULL_REF_H
	local spike = full.SpikeFrame
	local pulse = full.PulseFrame
	full:SetSize(barW, barH)
	if spike then
		spike:SetSize(barW, barH)
		if spike.AlertSpikeStay then
			spike.AlertSpikeStay:SetSize(PRD_ALERT_STOCK_W * scale, PRD_ALERT_STOCK_H * scale)
		end
		if spike.BigSpikeGlow then
			spike.BigSpikeGlow:SetSize(PRD_SPIKE_STOCK_W * scale, PRD_SPIKE_STOCK_H * scale)
		end
	end
	if pulse then
		pulse:SetSize(barW, barH)
		if pulse.YellowGlow then
			pulse.YellowGlow:SetSize(PRD_PULSE_STOCK_W * scale, PRD_PULSE_STOCK_H * scale)
		end
		if pulse.SoftGlow then
			pulse.SoftGlow:SetSize(PRD_PULSE_STOCK_W * scale, PRD_PULSE_STOCK_H * scale)
		end
	end
end

-- Never touch FeedbackFrame.Initialize (replace or instance hooksecurefunc).
-- Never hooksecurefunc PRD *instance* methods that live only on the mixin —
-- that installs a wrapper whose original is nil (Swatter: attempt to call a
-- nil value on UpdatePowerBar / FeedbackFrame.Initialize / UpdateMaxPower).
-- Hook PersonalResourceDisplayMixin instead; spender atlas via post-hook.
local powerSpenderHooked

local function HookPowerSpender()
	if powerSpenderHooked then
		return
	end
	if not PersonalResourceDisplayMixin then
		return
	end
	powerSpenderHooked = true
	if type(PersonalResourceDisplayMixin.UpdatePowerBar) == "function" then
		hooksecurefunc(PersonalResourceDisplayMixin, "UpdatePowerBar", function()
			local on = WhoaUF.db and WhoaUF.db.enabled and true or false
			SyncPowerSpenderTexture(on)
			SyncPrdFullPowerGlow(on)
		end)
	end
	if type(PersonalResourceDisplayMixin.SetPowerBarHeight) == "function" then
		hooksecurefunc(PersonalResourceDisplayMixin, "SetPowerBarHeight", function()
			local on = WhoaUF.db and WhoaUF.db.enabled and true or false
			SyncPrdFullPowerGlow(on)
		end)
	end
end

local function ApplyTintNow(raiseBorder)
	VisitPrdBarBorders(raiseBorder)
	VisitComboPoints()
end

-- Never hook or overwrite UpdateMaxPower / HandleBarSetup on ClassResourceBarMixin
-- or PRD classFrame instances. Instance/mixin hooksecurefunc on UpdateMaxPower left
-- a nil method slot that HandleBarSetup called (Swatter: attempt to call a nil value).
-- Combo tint only via point Setup + ApplyTintNow visits.
local function EnsureWatchers()
	local frame = GetPrdFrame()
	if not frame then
		return
	end
	HookPowerSpender()
	if watched then
		return
	end
	watched = true

	if DruidComboPointMixin and type(DruidComboPointMixin.Setup) == "function" then
		hooksecurefunc(DruidComboPointMixin, "Setup", function(point)
			if tintActive then
				VisitComboOnPoint(point)
			end
		end)
	end
	if RogueComboPointMixin and type(RogueComboPointMixin.Setup) == "function" then
		hooksecurefunc(RogueComboPointMixin, "Setup", function(point)
			if tintActive then
				VisitComboOnPoint(point)
			end
		end)
	end

	if frame.HookScript then
		pcall(frame.HookScript, frame, "OnShow", function()
			if WhoaUF.ApplyPersonalResourceDisplayTint then
				WhoaUF:ApplyPersonalResourceDisplayTint()
			end
		end)
	end
	-- Hook mixin, not the PRD instance (same nil-original trap as UpdatePowerBar).
	if PersonalResourceDisplayMixin and type(PersonalResourceDisplayMixin.SetupClass) == "function" then
		hooksecurefunc(PersonalResourceDisplayMixin, "SetupClass", function()
			if WhoaUF.ApplyPersonalResourceDisplayTint then
				WhoaUF:ApplyPersonalResourceDisplayTint()
			end
		end)
	end
	if PersonalResourceDisplayMixin and type(PersonalResourceDisplayMixin.SetupClassBar) == "function" then
		hooksecurefunc(PersonalResourceDisplayMixin, "SetupClassBar", function()
			if WhoaUF.ApplyPersonalResourceDisplayTint then
				WhoaUF:ApplyPersonalResourceDisplayTint()
			end
		end)
	end
end

function WhoaUF:ApplyPersonalResourceDisplayTint()
	local enabled = self.db and self.db.enabled and true or false
	local dark = self.IsFrameDarkVariant and self:IsFrameDarkVariant()
	tintActive = enabled and dark and true or false
	if not GetPrdFrame() then
		return
	end
	EnsureWatchers()
	ApplyTintNow(enabled)
	SyncPowerSpenderTexture(enabled)
	SyncPrdFullPowerGlow(enabled)
end

function WhoaUF:InitPersonalResourceDisplayTint()
	if hooked then
		self:ApplyPersonalResourceDisplayTint()
		return
	end
	hooked = true
	if GetPrdFrame() then
		self:ApplyPersonalResourceDisplayTint()
		return
	end
	self:ContinueOnAddOnLoaded("Blizzard_PersonalResourceDisplay", function()
		self:ApplyPersonalResourceDisplayTint()
	end)
end
