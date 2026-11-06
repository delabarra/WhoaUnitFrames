--[[
	Player unit-frame status bar animations.
	Reference:
	  reference/Blizzard_UnitFrame/Mainline/BuilderSpenderFrame.lua
	  reference/Blizzard_UnitFrame/Classic/UnitFrame.lua (AnimatedHealthLossMixin,
	  FeedbackFrame / FullPowerFrame hooks in UnitFrameManaBar_OnUpdate)
]]

local WhoaUF = WhoaUF

local Clamp = Clamp or function(v, minV, maxV)
	if v < minV then
		return minV
	elseif v > maxV then
		return maxV
	end
	return v
end

local Lerp = Lerp or function(a, b, t)
	return a + (b - a) * t
end

local function HasAtlas(atlas)
	if not atlas or atlas == "" then
		return false
	end
	if C_Texture and C_Texture.GetAtlasInfo then
		return C_Texture.GetAtlasInfo(atlas) ~= nil
	end
	return false
end

local function TrySetAtlas(texture, atlas, useAtlasSize)
	if HasAtlas(atlas) then
		texture:SetAtlas(atlas, useAtlasSize)
		return true
	end
	return false
end

--- Raw UnitGetTotalAbsorbs (may be secret on Mainline). Do not `or 0` / compare here.
local function GetTotalAbsorbs(unit)
	if UnitGetTotalAbsorbs then
		return UnitGetTotalAbsorbs(unit)
	end
	return 0
end

---------------------------------------------------------------------------
-- Builder / spender feedback (gain & loss glow on the power fill)
---------------------------------------------------------------------------

WhoaBuilderSpenderMixin = {}

function WhoaBuilderSpenderMixin:OnLoad()
	self.initialized = false
	self.maxValue = 0
end

local FALLBACK_STATUSBAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

-- Prefer the resolved file on a live status bar fill (SetStatusBarTexture may differ from SetTexture).
local function GetResolvedStatusBarTexture(statusBar)
	if statusBar and statusBar.GetStatusBarTexture then
		local fill = statusBar:GetStatusBarTexture()
		if fill and fill.GetTexture then
			local file = fill:GetTexture()
			if file then
				return file
			end
		end
	end
	if WhoaUF.GetStatusBarTexturePaths then
		local path = WhoaUF:GetStatusBarTexturePaths()
		if path then
			return path
		end
	end
	return FALLBACK_STATUSBAR_TEXTURE
end

function WhoaUF:GetResolvedStatusBarTexture(statusBar)
	return GetResolvedStatusBarTexture(statusBar)
end

local function GetFeedbackBarTexture(powerBar)
	return GetResolvedStatusBarTexture(powerBar)
end

function WhoaBuilderSpenderMixin:Initialize(textureInfo, unit, powerType, powerBar)
	if not textureInfo then
		return
	end
	powerBar = powerBar or self:GetParent()
	if textureInfo.atlas then
		self.BarTexture:SetAtlas(textureInfo.atlas, false)
	else
		self.BarTexture:SetTexture(GetFeedbackBarTexture(powerBar))
		self.barR = textureInfo.r or 1
		self.barG = textureInfo.g or 1
		self.barB = textureInfo.b or 1
		self.BarTexture:SetVertexColor(self.barR, self.barG, self.barB)
	end
	local height = self:GetHeight()
	self.BarTexture:SetHeight(height)
	self.LossGlowTexture:SetHeight(height)
	self.GainGlowTexture:SetHeight(height)
	self.unit = unit
	self.powerType = powerType
	self.maxValue = UnitPowerMax(unit, powerType)
	if WhoaUF.CanAccessValue and not WhoaUF:CanAccessValue(self.maxValue) then
		-- Keep secret max for SetMinMax on glow textures; Lua anim paths are gated elsewhere.
	elseif self.maxValue == nil then
		self.maxValue = 0
	end
	self.initialized = true
end

function WhoaBuilderSpenderMixin:SetMaxValue(maxValue)
	if maxValue == nil then
		self.maxValue = 0
	else
		self.maxValue = maxValue
	end
end

function WhoaBuilderSpenderMixin:GetMaxValue()
	if self.maxValue == nil then
		return 0
	end
	return self.maxValue
end

function WhoaBuilderSpenderMixin:EndFeedbackGain()
	self.GainGlowTexture:Hide()
	self.updatingGain = false
end

function WhoaBuilderSpenderMixin:EndFeedbackLoss()
	self.LossGlowTexture:Hide()
	self.BarTexture:Hide()
	self.updatingLoss = false
end

function WhoaBuilderSpenderMixin:StopFeedbackAnim()
	if self.updatingGain then
		self:EndFeedbackGain()
	end
	if self.updatingLoss then
		self:EndFeedbackLoss()
	end
	self:SetScript("OnUpdate", nil)
end

local function OnUpdateFeedbackGain(self)
	local timeEnd = 0.5
	local timeElapsed = GetTime() - self.animGainStartTime

	if timeElapsed > timeEnd then
		self:EndFeedbackGain()
		return
	end

	local currValue = UnitPower(self.unit, self.powerType)
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(currValue, self.newValue) then
		self:EndFeedbackGain()
		return
	end
	currValue = currValue or 0
	if currValue > self.newValue then
		self.newValue = currValue
	end

	local timeElapsedPercent = timeElapsed / timeEnd
	local currentValue = self.oldValue + (self.newValue - self.oldValue) * timeElapsedPercent
	local maxValue = self.maxValue
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(maxValue, currentValue) then
		self:EndFeedbackGain()
		return
	end
	if not maxValue or maxValue <= 0 then
		maxValue = 1
	end

	local parentWidth = self:GetParent():GetWidth()
	local leftPosition = currentValue / maxValue * parentWidth
	local width = (self.newValue - currentValue) / maxValue * self:GetWidth()
	if width < 0.5 then
		self.GainGlowTexture:Hide()
		self.updatingGain = false
		return
	end

	local texMinX = Clamp(currentValue / maxValue, 0, 1)
	local texMaxX = Clamp(self.newValue / maxValue, 0, 1)
	self.GainGlowTexture:ClearAllPoints()
	self.GainGlowTexture:SetPoint("TOPLEFT", leftPosition, 0)
	self.GainGlowTexture:SetHeight(self:GetHeight())
	self.GainGlowTexture:SetWidth(width)
	self.GainGlowTexture:SetTexCoord(texMinX, texMaxX, 0, 1)
	self.GainGlowTexture:Show()
end

local function OnUpdateFeedbackLoss(self)
	local timeGlowFade = 0.25
	local timeBarFade = 0.4
	local timeEnd = 0.6
	local timeElapsed = GetTime() - self.animLossStartTime

	if timeElapsed > timeEnd then
		self:EndFeedbackLoss()
		return
	end

	local glowAlpha
	if timeElapsed < timeGlowFade then
		glowAlpha = Lerp(0, 0.75, timeElapsed / timeGlowFade)
	else
		glowAlpha = Lerp(0.75, 0, (timeElapsed - timeGlowFade) / (timeEnd - timeGlowFade))
	end
	self.LossGlowTexture:SetAlpha(glowAlpha)

	local barAlpha
	if timeElapsed < timeBarFade then
		barAlpha = 1
	else
		barAlpha = Lerp(1, 0, (timeElapsed - timeBarFade) / (timeEnd - timeBarFade))
	end
	self.BarTexture:SetAlpha(barAlpha)
end

local function OnUpdateFeedback(self)
	if self.updatingGain then
		OnUpdateFeedbackGain(self)
	end
	if self.updatingLoss then
		OnUpdateFeedbackLoss(self)
	end
	if not self.updatingGain and not self.updatingLoss then
		self:SetScript("OnUpdate", nil)
	end
end

function WhoaBuilderSpenderMixin:StartFeedbackAnim(oldValue, newValue)
	if not self.initialized then
		return
	end

	local showBuilderFeedback = GetCVarBool("showBuilderFeedback")
	local showSpenderFeedback = GetCVarBool("showSpenderFeedback")
	-- CVars may be absent on some Classic clients; default on like modern UI.
	if showBuilderFeedback == nil then
		showBuilderFeedback = true
	end
	if showSpenderFeedback == nil then
		showSpenderFeedback = true
	end
	if not showBuilderFeedback and not showSpenderFeedback then
		return
	end

	local maxValue = self.maxValue
	if maxValue <= 0 then
		return
	end

	oldValue = Clamp(oldValue or 0, 0, maxValue)
	newValue = math.max(newValue or 0, 0)

	if newValue > oldValue and showBuilderFeedback then
		self.updatingGain = true
		self:SetScript("OnUpdate", OnUpdateFeedback)
		self.oldValue = oldValue
		self.newValue = newValue
		self.animGainStartTime = GetTime()
	elseif newValue < oldValue and showSpenderFeedback then
		local leftPosition = newValue / maxValue * self:GetWidth()
		local width = (oldValue - newValue) / maxValue * self:GetWidth()
		local texMinX = newValue / maxValue
		local texMaxX = oldValue / maxValue
		local height = self:GetHeight()

		local glowTexture = self.LossGlowTexture
		glowTexture:ClearAllPoints()
		glowTexture:SetPoint("TOPLEFT", leftPosition, 0)
		glowTexture:SetHeight(height)
		glowTexture:SetWidth(width)
		glowTexture:SetTexCoord(texMinX, texMaxX, 0, 1)
		glowTexture:Show()
		glowTexture:SetAlpha(0)

		local barTexture = self.BarTexture
		local powerBar = self:GetParent()
		barTexture:SetTexture(GetFeedbackBarTexture(powerBar))
		barTexture:SetVertexColor(self.barR or 1, self.barG or 1, self.barB or 1)
		barTexture:ClearAllPoints()
		barTexture:SetPoint("TOPLEFT", leftPosition, 0)
		barTexture:SetHeight(height)
		barTexture:SetWidth(width)
		barTexture:SetTexCoord(texMinX, texMaxX, 0, 1)
		barTexture:Show()
		barTexture:SetAlpha(1)

		self.updatingLoss = true
		self:SetScript("OnUpdate", OnUpdateFeedback)
		self.animLossStartTime = GetTime()
	end
end

---------------------------------------------------------------------------
-- Full-resource spike + pulse (drawn over the frame border)
-- Reference bar: 119×12 (Classic player power). Nameplate code rescales
-- child frames/textures when the host power bar differs — same approach here.
---------------------------------------------------------------------------

local REF_BAR_W = 119
local REF_BAR_H = 12
local PULSE_TRANSLATION_X = 20

local SPIKE_LAYOUT = {
	BigSpikeGlow = { w = 42, h = 24, point = "RIGHT", relPoint = "RIGHT", x = 21, y = 0 },
	AlertSpikeStay = { w = 30, h = 18, point = "RIGHT", relPoint = "RIGHT", x = 11, y = 0 },
}

local PULSE_LAYOUT = {
	YellowGlow = { w = 20, h = 24, point = "RIGHT", relPoint = "RIGHT", x = -1, y = -1 },
	SoftGlow = { w = 20, h = 24, point = "RIGHT", relPoint = "RIGHT", x = -1, y = -1 },
}

local function ScaleByRef(base, barDim, refDim)
	if not refDim or refDim <= 0 then
		return base
	end
	return base * barDim / refDim
end

local function ApplyTextureGeom(tex, parent, layout, barW, barH)
	if not tex or not layout then
		return
	end
	local w = ScaleByRef(layout.w, barW, REF_BAR_W)
	local h = ScaleByRef(layout.h, barH, REF_BAR_H)
	local x = layout.x and ScaleByRef(layout.x, barW, REF_BAR_W) or 0
	local y = layout.y and ScaleByRef(layout.y, barH, REF_BAR_H) or 0
	tex:SetSize(w, h)
	tex:ClearAllPoints()
	tex:SetPoint(layout.point, parent, layout.relPoint or layout.point, x, y)
end

local function ApplyTextureLayout(tex, parent, layout, barW, barH)
	ApplyTextureGeom(tex, parent, layout, barW, barH)
	if tex then
		tex:SetAlpha(0)
	end
end

-- Stock FullResourcePulse uses :Play() (no Restart). Restarting a looping PulseAnim
-- every power tick would reset the trail; only force-restart one-shot SpikeAnim.
local function PlayAnimGroup(animGroup, forceRestart)
	if not animGroup then
		return
	end
	if forceRestart then
		if animGroup.Restart then
			animGroup:Restart()
		else
			animGroup:Stop()
			animGroup:Play()
		end
		return
	end
	animGroup:Play()
end

local function ForEachAnimation(animGroup, fn)
	if not animGroup or not animGroup.GetNumAnimations then
		return
	end
	for i = 1, animGroup:GetNumAnimations() do
		fn(select(i, animGroup:GetAnimations()))
	end
end

local function ScalePulseTranslations(pulseFrame, barW)
	if not pulseFrame or not pulseFrame.PulseAnim then
		return
	end
	local offsetX = ScaleByRef(PULSE_TRANSLATION_X, barW, REF_BAR_W)
	ForEachAnimation(pulseFrame.PulseAnim, function(anim)
		if anim.GetOffset and anim.SetOffset then
			local _, offsetY = anim:GetOffset()
			anim:SetOffset(offsetX, offsetY or 0)
		end
	end)
end

WhoaFullResourcePulseMixin = {}

function WhoaFullResourcePulseMixin:OnLoad()
	self.active = false
	self.maxValue = 0
	self.wasFull = false
	self:SetAlpha(0)

	-- Prefer Blizzard FullAlert atlases when the client ships them.
	local spike = self.SpikeFrame
	if spike then
		TrySetAtlas(spike.BigSpikeGlow, "FullAlert-BigSpike", true)
		TrySetAtlas(spike.AlertSpikeStay, "FullAlert-FrameGlow", true)
	end
	local pulse = self.PulseFrame
	if pulse then
		TrySetAtlas(pulse.YellowGlow, "FullAlert-YellowCurveGlow", false)
		TrySetAtlas(pulse.SoftGlow, "FullAlert-SoftCurveGlow", false)
	end

	-- Ensure fadeout always clears pulse/spike even if XML OnFinished is flaky.
	self.FadeoutAnim:SetScript("OnFinished", function()
		if self.whoaSecretPulseAnim then
			self.whoaSecretPulseAnim:Stop()
		end
		if self.whoaSecretSpikeAnim then
			self.whoaSecretSpikeAnim:Stop()
		end
		self:ResetPulseVisuals()
		self:ResetSpikeVisuals()
	end)
end

-- Keep FullPower above Overlay (+3), tick hosts (border+2), and NameHost (+8)
-- so spike/pulse paint over the power bar fill — not under chrome or empty hosts.
local function RaiseFullPowerFrame(fullPower, unitFrame)
	if not fullPower or not unitFrame then
		return
	end
	local overlay = unitFrame.Overlay
	local borderLevel = (overlay and overlay:GetFrameLevel()) or (unitFrame:GetFrameLevel() + 3)
	local level = math.max(borderLevel + 2, unitFrame:GetFrameLevel() + 10)
	local nameHost = unitFrame.NameHost
	if nameHost then
		level = math.max(level, nameHost:GetFrameLevel() + 1)
	end
	fullPower:SetFrameLevel(level)
	if fullPower.PulseFrame then
		fullPower.PulseFrame:SetFrameLevel(level + 1)
	end
	if fullPower.SpikeFrame then
		fullPower.SpikeFrame:SetFrameLevel(level + 2)
	end
end

function WhoaFullResourcePulseMixin:SyncToPowerBar(powerBar)
	if not powerBar then
		return
	end
	local unitFrame = self:GetParent()
	if unitFrame then
		RaiseFullPowerFrame(self, unitFrame)
	end
	local barW = powerBar:GetWidth()
	local barH = powerBar:GetHeight()
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(barW, barH) then
		return
	end
	if not barW or barW <= 0 or not barH or barH <= 0 then
		return
	end
	if self.barWidth == barW and self.barHeight == barH then
		return
	end
	self.barWidth = barW
	self.barHeight = barH

	-- Both spike and pulse sit on the power bar (not health).
	local spike = self.SpikeFrame
	local pulse = self.PulseFrame
	if spike then
		spike:ClearAllPoints()
		spike:SetSize(barW, barH)
		spike:SetPoint("TOPRIGHT", powerBar, "TOPRIGHT", -5, 0)
		ApplyTextureGeom(spike.BigSpikeGlow, spike, SPIKE_LAYOUT.BigSpikeGlow, barW, barH)
		ApplyTextureGeom(spike.AlertSpikeStay, spike, SPIKE_LAYOUT.AlertSpikeStay, barW, barH)
	end
	if pulse then
		pulse:ClearAllPoints()
		pulse:SetSize(barW, barH)
		pulse:SetPoint("TOPRIGHT", powerBar, "TOPRIGHT", -5, 0)
		ApplyTextureGeom(pulse.YellowGlow, pulse, PULSE_LAYOUT.YellowGlow, barW, barH)
		ApplyTextureGeom(pulse.SoftGlow, pulse, PULSE_LAYOUT.SoftGlow, barW, barH)
		ScalePulseTranslations(pulse, barW)
	end
end

function WhoaFullResourcePulseMixin:ResetSpikeVisuals()
	local spike = self.SpikeFrame
	if not spike then
		return
	end
	if spike.SpikeAnim then
		spike.SpikeAnim:Stop()
	end
	if spike.BigSpikeGlow then
		spike.BigSpikeGlow:SetAlpha(0)
		if spike.BigSpikeGlow.SetScale then
			spike.BigSpikeGlow:SetScale(1)
		end
	end
	if spike.AlertSpikeStay then
		spike.AlertSpikeStay:SetAlpha(0)
		if spike.AlertSpikeStay.SetScale then
			spike.AlertSpikeStay:SetScale(1)
		end
	end
	if self.barWidth and self.barHeight then
		ApplyTextureLayout(spike.BigSpikeGlow, spike, SPIKE_LAYOUT.BigSpikeGlow, self.barWidth, self.barHeight)
		ApplyTextureLayout(spike.AlertSpikeStay, spike, SPIKE_LAYOUT.AlertSpikeStay, self.barWidth, self.barHeight)
	end
end

function WhoaFullResourcePulseMixin:ResetPulseVisuals()
	local pulse = self.PulseFrame
	if not pulse then
		return
	end
	if pulse.PulseAnim then
		pulse.PulseAnim:Stop()
	end
	if pulse.YellowGlow then
		pulse.YellowGlow:SetAlpha(0)
	end
	if pulse.SoftGlow then
		pulse.SoftGlow:SetAlpha(0)
	end
	if self.barWidth and self.barHeight then
		ApplyTextureLayout(pulse.YellowGlow, pulse, PULSE_LAYOUT.YellowGlow, self.barWidth, self.barHeight)
		ApplyTextureLayout(pulse.SoftGlow, pulse, PULSE_LAYOUT.SoftGlow, self.barWidth, self.barHeight)
	end
end

function WhoaFullResourcePulseMixin:Initialize(active)
	self.active = not not active
	if self.active then
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:SetScript("OnEvent", self.OnEvent)
	else
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		self:SetScript("OnEvent", nil)
		self:RemoveAnims()
	end
end

function WhoaFullResourcePulseMixin:SetMaxValue(maxValue)
	if maxValue == nil then
		self.maxValue = 0
	else
		self.maxValue = maxValue
	end
end

-- Forward-declared; assigned below StartAnimIfFull helpers.
local ClearSecretFullGlow
local SyncSecretFullGlow

function WhoaFullResourcePulseMixin:OnEvent(event)
	if event == "PLAYER_REGEN_ENABLED" then
		self.wasFull = false
		ClearSecretFullGlow(self)
		if self.SpikeFrame.SpikeAnim:IsPlaying() or self.PulseFrame.PulseAnim:IsPlaying() then
			self.FadeoutAnim:Play()
		elseif self:GetAlpha() > 0 then
			self:RemoveAnims()
		end
	end
end

-- Mainline secrets: DK sword-glow SetValue gate. Atlas StatusBars at SoftGlow/Spike
-- sizes (no Lua compare). Alpha AnimationGroups pulse them — XML childKey anims need
-- accessible power compares, so they stay Classic-only.
local FULL_ARM = 100
local FULL_GATE_MIN = FULL_ARM - 1
local FULL_GATE_MAX = FULL_ARM

local SECRET_GLOW = {
	{ key = "SecretBigSpike", frame = "SpikeFrame", src = "BigSpikeGlow", layout = SPIKE_LAYOUT.BigSpikeGlow, atlas = "FullAlert-BigSpike", pulse = false },
	{ key = "SecretAlertSpike", frame = "SpikeFrame", src = "AlertSpikeStay", layout = SPIKE_LAYOUT.AlertSpikeStay, atlas = "FullAlert-FrameGlow", pulse = false },
	{ key = "SecretYellowGlow", frame = "PulseFrame", src = "YellowGlow", layout = PULSE_LAYOUT.YellowGlow, atlas = "FullAlert-YellowCurveGlow", pulse = true },
	{ key = "SecretSoftGlow", frame = "PulseFrame", src = "SoftGlow", layout = PULSE_LAYOUT.SoftGlow, atlas = "FullAlert-SoftCurveGlow", pulse = true },
}

ClearSecretFullGlow = function(self)
	if not self.whoaSecretFullGlow then
		return
	end
	self.whoaSecretFullDefer = nil
	if self.whoaSecretPulseAnim then
		self.whoaSecretPulseAnim:Stop()
	end
	if self.whoaSecretSpikeAnim then
		self.whoaSecretSpikeAnim:Stop()
	end
	for i = 1, #SECRET_GLOW do
		local bar = self[SECRET_GLOW[i].key]
		if bar then
			bar:SetValue(0)
			bar:SetAlpha(1)
			bar:Hide()
		end
	end
	self.whoaSecretFullGlow = nil
end

local function AnimSetTarget(anim, region)
	if anim and region and anim.SetTarget then
		anim:SetTarget(region)
	end
end

-- Stock PulseAnim: one REPEAT group drives Yellow + Soft on the same timeline.
-- Separate 0.5s / 0.7s loops drift and look like a doubled pulse.
local function EnsureStockPulseAnim(host, yellowBar, softBar, offsetX)
	local ag = host.whoaSecretPulseAnim
	if ag then
		ForEachAnimation(ag, function(anim)
			if anim.GetOffset and anim.SetOffset then
				local _, oy = anim:GetOffset()
				anim:SetOffset(offsetX, oy or 0)
			end
		end)
		return ag
	end
	ag = host:CreateAnimationGroup()
	ag:SetLooping("REPEAT")

	local y1 = ag:CreateAnimation("Alpha")
	y1:SetFromAlpha(0)
	y1:SetToAlpha(1)
	y1:SetDuration(0.1)
	y1:SetOrder(1)
	AnimSetTarget(y1, yellowBar)

	local yt = ag:CreateAnimation("Translation")
	yt:SetOffset(offsetX, 0)
	yt:SetDuration(0.5)
	yt:SetSmoothing("OUT")
	yt:SetOrder(1)
	AnimSetTarget(yt, yellowBar)

	local y2 = ag:CreateAnimation("Alpha")
	y2:SetFromAlpha(1)
	y2:SetToAlpha(0)
	y2:SetStartDelay(0.4)
	y2:SetDuration(0.1)
	y2:SetOrder(1)
	AnimSetTarget(y2, yellowBar)

	local s1 = ag:CreateAnimation("Alpha")
	s1:SetFromAlpha(0)
	s1:SetToAlpha(1)
	s1:SetDuration(0.1)
	s1:SetOrder(1)
	AnimSetTarget(s1, softBar)

	local st = ag:CreateAnimation("Translation")
	st:SetOffset(offsetX, 0)
	st:SetDuration(0.7)
	st:SetSmoothing("OUT")
	st:SetOrder(1)
	AnimSetTarget(st, softBar)

	local s2 = ag:CreateAnimation("Alpha")
	s2:SetFromAlpha(1)
	s2:SetToAlpha(0)
	s2:SetStartDelay(0.6)
	s2:SetDuration(0.1)
	s2:SetOrder(1)
	AnimSetTarget(s2, softBar)

	host.whoaSecretPulseAnim = ag
	return ag
end

-- Stock SpikeAnim (setToFinalAlpha): BigSpike alpha+scale + AlertSpikeStay stays.
local function EnsureStockSpikeAnim(host, bigBar, stayBar)
	if host.whoaSecretSpikeAnim then
		return host.whoaSecretSpikeAnim
	end
	local ag = host:CreateAnimationGroup()
	ag:SetLooping("NONE")
	if ag.SetToFinalAlpha then
		ag:SetToFinalAlpha(true)
	end

	local a1 = ag:CreateAnimation("Alpha")
	a1:SetFromAlpha(0)
	a1:SetToAlpha(1)
	a1:SetDuration(0.25)
	a1:SetSmoothing("IN")
	a1:SetOrder(1)
	AnimSetTarget(a1, bigBar)

	-- Scale matches stock XML; skip entirely if the client rejects Scale on StatusBars.
	local scaleOk = pcall(function()
		local s1 = ag:CreateAnimation("Scale")
		s1:SetScaleFrom(0.25, 0.75)
		s1:SetScaleTo(1.4, 0.75)
		s1:SetDuration(0.1)
		s1:SetOrder(1)
		if s1.SetOrigin then
			s1:SetOrigin("LEFT", 0, 0)
		end
		AnimSetTarget(s1, bigBar)

		local s2 = ag:CreateAnimation("Scale")
		s2:SetScaleFrom(1, 1)
		s2:SetScaleTo(0.5, 1)
		s2:SetStartDelay(0.2)
		s2:SetDuration(0.2)
		s2:SetSmoothing("IN")
		s2:SetOrder(1)
		if s2.SetOrigin then
			s2:SetOrigin("LEFT", 0, 0)
		end
		AnimSetTarget(s2, bigBar)
	end)
	if not scaleOk then
		-- Leave alpha-only spike rather than aborting the whole full-power glow.
	end

	local a2 = ag:CreateAnimation("Alpha")
	a2:SetFromAlpha(1)
	a2:SetToAlpha(0)
	a2:SetStartDelay(0.3)
	a2:SetDuration(0.25)
	a2:SetOrder(1)
	AnimSetTarget(a2, bigBar)

	if stayBar then
		local stay = ag:CreateAnimation("Alpha")
		stay:SetFromAlpha(0)
		stay:SetToAlpha(1)
		stay:SetDuration(0.25)
		stay:SetSmoothing("IN")
		stay:SetOrder(1)
		AnimSetTarget(stay, stayBar)
	end

	host.whoaSecretSpikeAnim = ag
	return ag
end

-- After SetValue on a 99–100 gate: true=filled, false=empty, nil=unknown.
-- Unknown must not suppress anims — StatusBar SetValue still gates the pixels.
local function GetGatedGlowFillState(bar)
	if not bar then
		return nil
	end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not tex then
		return nil
	end

	-- Prefer texcoords when the client keeps full size and crops the fill.
	if tex.GetTexCoord then
		local left, _, _, _, right = tex:GetTexCoord()
		if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(left) and WhoaUF:CanAccessValue(right)
			and type(left) == "number" and type(right) == "number" then
			local span = math.abs(right - left)
			if span <= 0.001 then
				return false
			end
			if span >= 0.5 then
				return true
			end
			return false
		end
	end

	local w = tex.GetWidth and tex:GetWidth()
	local bw = bar.GetWidth and bar:GetWidth()
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(w) and WhoaUF:CanAccessValue(bw)
		and type(w) == "number" and type(bw) == "number" and bw > 0 then
		return (w / bw) > 0.5
	end
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(w) and type(w) == "number" then
		return w > 0.5
	end
	return nil
end

local function IsGatedGlowFilled(bar)
	return GetGatedGlowFillState(bar) == true
end

local function ApplyFullGlowBarArt(bar, host, entry)
	local src = host and host[entry.src]
	local atlas = (src and src.GetAtlas and src:GetAtlas()) or nil
	if not atlas or atlas == "" then
		atlas = (entry.atlas and HasAtlas(entry.atlas)) and entry.atlas or nil
	end
	local file = src and src.GetTexture and src:GetTexture()

	bar:SetStatusBarTexture(file or "Interface\\TargetingFrame\\UI-StatusBar-Glow")
	local fill = bar:GetStatusBarTexture()
	if fill then
		if atlas and fill.SetAtlas then
			fill:SetAtlas(atlas, false)
		elseif file then
			fill:SetTexture(file)
		end
		if fill.SetBlendMode then
			fill:SetBlendMode("ADD")
		end
		fill:SetVertexColor(1, 1, 1, 1)
	end
	bar:SetStatusBarColor(1, 1, 1, 1)
end

SyncSecretFullGlow = function(self, powerBar, power)
	if not powerBar then
		return
	end
	self:SyncToPowerBar(powerBar)

	local barW = self.barWidth or REF_BAR_W
	local barH = self.barHeight or REF_BAR_H
	local pw, ph = powerBar:GetWidth(), powerBar:GetHeight()
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(pw) and type(pw) == "number" and pw > 1 then
		barW = pw
	end
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(ph) and type(ph) == "number" and ph > 1 then
		barH = ph
	end
	self.barWidth = barW
	self.barHeight = barH

	local offsetX = ScaleByRef(PULSE_TRANSLATION_X, barW, REF_BAR_W)

	-- Secret max/cur: stop XML spike/pulse; run BuilderSpender-style timed pulse instead.
	local spike = self.SpikeFrame
	local pulse = self.PulseFrame
	if spike then
		if spike.SpikeAnim then
			spike.SpikeAnim:Stop()
		end
		if spike.BigSpikeGlow then
			spike.BigSpikeGlow:SetAlpha(0)
		end
		if spike.AlertSpikeStay then
			spike.AlertSpikeStay:SetAlpha(0)
		end
	end
	if pulse then
		if pulse.PulseAnim then
			pulse.PulseAnim:Stop()
		end
		if pulse.YellowGlow then
			pulse.YellowGlow:SetAlpha(0)
		end
		if pulse.SoftGlow then
			pulse.SoftGlow:SetAlpha(0)
		end
	end

	local bigBar, stayBar, yellowBar, softBar
	for i = 1, #SECRET_GLOW do
		local entry = SECRET_GLOW[i]
		local host = self[entry.frame]
		if host then
			local bar = self[entry.key]
			if not bar then
				bar = CreateFrame("StatusBar", nil, host)
				bar:EnableMouse(false)
				bar:SetOrientation("HORIZONTAL")
				self[entry.key] = bar
			end
			ApplyFullGlowBarArt(bar, host, entry)
			-- Don't re-anchor while pulse is translating — resets the trail mid-cycle.
			if not (self.whoaSecretPulseAnim and self.whoaSecretPulseAnim:IsPlaying()) then
				ApplyTextureGeom(bar, host, entry.layout, barW, barH)
			end
			bar:SetMinMaxValues(FULL_GATE_MIN, FULL_GATE_MAX)
			if power ~= nil then
				bar:SetValue(power)
			else
				bar:SetValue(0)
			end
			if not bar:IsShown() then
				bar:Show()
			end
			if entry.key == "SecretBigSpike" then
				bigBar = bar
			elseif entry.key == "SecretAlertSpike" then
				stayBar = bar
			elseif entry.key == "SecretYellowGlow" then
				yellowBar = bar
			elseif entry.key == "SecretSoftGlow" then
				softBar = bar
			end
		end
	end

	self.whoaSecretFullGlow = true

	-- Fill detection is best-effort (spike-on-enter only). Art visibility comes from
	-- StatusBar SetValue on the 99–100 gate — do not suppress anims on bad reads.
	local definitelyFull = IsGatedGlowFilled(bigBar) or IsGatedGlowFilled(yellowBar)
	local enteringFull = definitelyFull and not self.wasFull
	if definitelyFull then
		self.wasFull = true
	elseif GetGatedGlowFillState(bigBar) == false or GetGatedGlowFillState(yellowBar) == false then
		self.wasFull = false
	end

	if not definitelyFull and power ~= nil and not self.whoaSecretFullDefer and C_Timer and C_Timer.After then
		self.whoaSecretFullDefer = true
		C_Timer.After(0, function()
			self.whoaSecretFullDefer = nil
			if not self.active or not self.whoaSecretFullGlow then
				return
			end
			local affecting = UnitAffectingCombat("player")
			if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(affecting) and not affecting then
				return
			end
			if IsGatedGlowFilled(self.SecretBigSpike) or IsGatedGlowFilled(self.SecretYellowGlow) then
				local parent = self:GetParent()
				local pb = parent and parent.Power
				if pb then
					SyncSecretFullGlow(self, pb, power)
				end
			end
		end)
	end

	local pulseAg = yellowBar and softBar and EnsureStockPulseAnim(self, yellowBar, softBar, offsetX)
	local pulsePlaying = pulseAg and pulseAg:IsPlaying()
	local fadeoutPlaying = self.FadeoutAnim:IsPlaying()

	-- Always drive anims while in combat (caller). SetValue gates the pixels.
	if enteringFull or fadeoutPlaying or not pulsePlaying then
		if bigBar then
			if bigBar.whoaSpikeAnim then
				bigBar.whoaSpikeAnim:Stop()
				bigBar.whoaSpikeAnim = nil
			end
			if stayBar and stayBar.whoaSpikeAnim then
				stayBar.whoaSpikeAnim:Stop()
				stayBar.whoaSpikeAnim = nil
			end
			bigBar:SetAlpha(1)
			if stayBar then
				stayBar:SetAlpha(1)
			end
			local spikeAg = EnsureStockSpikeAnim(self, bigBar, stayBar)
			PlayAnimGroup(spikeAg, true)
		end
	end

	self.FadeoutAnim:Stop()
	self:SetAlpha(1)
	if not self:IsShown() then
		self:Show()
	end

	if yellowBar and softBar then
		if yellowBar.whoaPulseAnim then
			yellowBar.whoaPulseAnim:Stop()
			yellowBar.whoaPulseAnim = nil
		end
		if softBar.whoaPulseAnim then
			softBar.whoaPulseAnim:Stop()
			softBar.whoaPulseAnim = nil
		end
		yellowBar:SetAlpha(1)
		softBar:SetAlpha(1)
		PlayAnimGroup(pulseAg)
	end
end

function WhoaFullResourcePulseMixin:StartAnimIfFull(newValue)
	if not self.active then
		return
	end

	local powerBar = self:GetParent() and self:GetParent().Power
	local affecting = UnitAffectingCombat("player")
	local inCombat = true
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(affecting) then
		inCombat = affecting and true or false
	end

	local secret = WhoaUF.NeedsSecretSafeNumberOps
		and WhoaUF:NeedsSecretSafeNumberOps(newValue, self.maxValue)

	if secret then
		if not inCombat then
			self.wasFull = false
			ClearSecretFullGlow(self)
			self:RemoveAnims()
			return
		end
		SyncSecretFullGlow(self, powerBar, newValue)
		return
	end

	ClearSecretFullGlow(self)
	if powerBar and self.SyncToPowerBar then
		self:SyncToPowerBar(powerBar)
	end

	if not self.maxValue or self.maxValue <= 0 then
		return
	end

	-- Mirror FullResourcePulse:StartAnimIfFull (Mainline/BuilderSpenderFrame.lua).
	if newValue == self.maxValue and inCombat then
		local fadeoutPlaying = self.FadeoutAnim:IsPlaying()
		local pulsePlaying = self.PulseFrame.PulseAnim:IsPlaying()
		if fadeoutPlaying or not pulsePlaying then
			self:ResetSpikeVisuals()
			PlayAnimGroup(self.SpikeFrame.SpikeAnim, true)
		end
		self.FadeoutAnim:Stop()
		self:SetAlpha(1)
		if not self:IsShown() then
			self:Show()
		end
		if not pulsePlaying then
			self:ResetPulseVisuals()
			PlayAnimGroup(self.PulseFrame.PulseAnim, true)
		else
			PlayAnimGroup(self.PulseFrame.PulseAnim)
		end
		self.wasFull = true
	elseif not self.FadeoutAnim:IsPlaying()
		and (self.PulseFrame.PulseAnim:IsPlaying() or self.SpikeFrame.SpikeAnim:IsPlaying()) then
		self.wasFull = false
		self.FadeoutAnim:Play()
	else
		self.wasFull = false
	end
end

function WhoaFullResourcePulseMixin:RemoveAnims()
	self.wasFull = false
	self.FadeoutAnim:Stop()
	ClearSecretFullGlow(self)
	self:ResetPulseVisuals()
	self:ResetSpikeVisuals()
	self:SetAlpha(0)
end

---------------------------------------------------------------------------
-- Animated health loss trail
---------------------------------------------------------------------------

WhoaAnimatedHealthLossMixin = {}

function WhoaAnimatedHealthLossMixin:OnLoad()
	self:SetStatusBarColor(1, 0, 0, 1)
	self:SetDuration(0.25)
	self:SetStartDelay(0.1)
	self:SetPauseDelay(0.05)
	self:SetPostponeDelay(0.05)
end

function WhoaAnimatedHealthLossMixin:SetDuration(duration)
	self.animationDuration = duration or 0
end

function WhoaAnimatedHealthLossMixin:SetStartDelay(delay)
	self.animationStartDelay = delay or 0
end

function WhoaAnimatedHealthLossMixin:SetPauseDelay(delay)
	self.animationPauseDelay = delay or 0
end

function WhoaAnimatedHealthLossMixin:SetPostponeDelay(delay)
	self.animationPostponeDelay = delay or 0
end

function WhoaAnimatedHealthLossMixin:SetUnitHealthBar(unit, healthBar)
	if self.unit ~= unit then
		healthBar.AnimatedLossBar = self
		self.unit = unit
		self:SetAllPoints(healthBar)
		self:UpdateHealthMinMax()
	end
end

function WhoaAnimatedHealthLossMixin:UpdateHealthMinMax()
	local maxValue = UnitHealthMax(self.unit)
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(maxValue) then
		self:SetMinMaxValues(0, maxValue > 0 and maxValue or 1)
	elseif maxValue ~= nil then
		self:SetMinMaxValues(0, maxValue)
	else
		self:SetMinMaxValues(0, 1)
	end
end

function WhoaAnimatedHealthLossMixin:GetHealthLossAnimationData(currentHealth, previousHealth)
	if self.animationStartTime then
		local totalElapsedTime = GetTime() - self.animationStartTime
		if totalElapsedTime > 0 then
			local animCompletePercent = totalElapsedTime / self.animationDuration
			if animCompletePercent < 1 and previousHealth > currentHealth then
				local healthDelta = previousHealth - currentHealth
				local animatedLossAmount = previousHealth - (animCompletePercent * healthDelta)
				return animatedLossAmount, animCompletePercent
			end
		else
			return previousHealth, 0
		end
	end
	return 0, 1
end

function WhoaAnimatedHealthLossMixin:CancelAnimation()
	self:Hide()
	self.animationStartTime = nil
	self.animationCompletePercent = nil
	self:SetScript("OnUpdate", nil)
end

function WhoaAnimatedHealthLossMixin:BeginAnimation(value)
	self.animationStartValue = value
	self.animationStartTime = GetTime() + self.animationStartDelay
	self.animationCompletePercent = 0
	self:Show()
	self:SetValue(self.animationStartValue)
	self:SetScript("OnUpdate", self.OnUpdate)
end

function WhoaAnimatedHealthLossMixin:PostponeStartTime()
	self.animationStartTime = self.animationStartTime + self.animationPostponeDelay
end

function WhoaAnimatedHealthLossMixin:UpdateHealth(currentHealth, previousHealth)
	local delta = currentHealth - previousHealth
	local hasLoss = delta < 0
	local hasBegun = self.animationStartTime ~= nil
	local isAnimating = hasBegun and self.animationCompletePercent and self.animationCompletePercent > 0

	if hasLoss and not hasBegun then
		self:BeginAnimation(previousHealth)
	elseif hasLoss and hasBegun and not isAnimating then
		self:PostponeStartTime()
	elseif hasLoss and isAnimating then
		self.animationStartValue = self:GetHealthLossAnimationData(previousHealth, self.animationStartValue)
		self.animationStartTime = GetTime() + self.animationPauseDelay
	elseif not hasLoss and hasBegun and currentHealth >= self.animationStartValue then
		self:CancelAnimation()
	end
end

function WhoaAnimatedHealthLossMixin:UpdateLossAnimation(currentHealth)
	local absorbs = GetTotalAbsorbs(self.unit)
	-- Secret absorb: cannot compare; cancel loss anim (same as "shield present").
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(absorbs) then
		self:CancelAnimation()
		return
	end
	if absorbs and absorbs > 0 then
		self:CancelAnimation()
		return
	end

	if self.animationStartTime then
		local animationValue, animationCompletePercent = self:GetHealthLossAnimationData(currentHealth, self.animationStartValue)
		self.animationCompletePercent = animationCompletePercent
		if animationCompletePercent >= 1 then
			self:CancelAnimation()
		else
			self:SetValue(animationValue)
		end
	end
end

function WhoaAnimatedHealthLossMixin:OnUpdate()
	local health = UnitHealth(self.unit)
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(health) then
		self:CancelAnimation()
		return
	end
	self:UpdateLossAnimation(health or 0)
end

---------------------------------------------------------------------------
-- Attach / drive from Whoa unit frames
---------------------------------------------------------------------------

local function SyncFeedbackColors(powerBar)
	local feedback = powerBar and powerBar.FeedbackFrame
	if not feedback then
		return
	end
	local unit = powerBar.unit or "player"
	local powerType = powerBar.powerType or UnitPowerType(unit)
	local powerToken = powerBar.powerToken
	local info = WhoaUF:GetPowerBarColor(powerToken, powerType)
	if info then
		feedback:Initialize(info, unit, powerType, powerBar)
	end
	local full = powerBar.FullPowerFrame
	if full then
		full:Initialize(WhoaUF:WantsFullPowerAnim(powerToken, powerType))
	end
end

function WhoaUF:ApplyPowerFeedbackTextures()
	local player = self.unitFrames and self.unitFrames.player
	local power = player and player.Power
	if power then
		SyncFeedbackColors(power)
	end
end

local function AttachAnimatedHealthLoss(frame, unit)
	local health = frame and frame.Health
	if not health or frame.AnimatedLossBar then
		return
	end
	unit = unit or frame.unit or "player"
	local loss = CreateFrame("StatusBar", nil, frame, "WhoaAnimatedHealthLossTemplate")
	loss:SetFrameLevel(health:GetFrameLevel())
	health:SetFrameLevel(loss:GetFrameLevel() + 1)
	if WhoaUF.ShouldUseClassicVehicleStatusBars and frame.kind == "player" and WhoaUF:ShouldUseClassicVehicleStatusBars(frame) then
		loss:SetStatusBarTexture(FALLBACK_STATUSBAR_TEXTURE)
	else
		loss:SetStatusBarTexture(GetResolvedStatusBarTexture(health))
	end
	loss:SetUnitHealthBar(unit, health)
	loss:Hide()
	frame.AnimatedLossBar = loss
end

--- Attach animated loss + power feedback/spikes to a Whoa unit frame.
--- FullPowerFrame is a unit-frame sibling raised above Overlay/NameHost; spike+pulse anchor to Power.
function WhoaUF:AttachStatusBarAnims(frame)
	if not frame or not frame.Health or not frame.Power then
		return
	end
	if frame.statusBarAnimsAttached then
		return
	end

	local health = frame.Health
	local power = frame.Power
	local unit = frame.unit or "player"

	-- Health loss sits under the health fill (created first / same level).
	AttachAnimatedHealthLoss(frame, unit)

	-- Builder/spender glow stays on the power bar (under chrome).
	local feedback = CreateFrame("Frame", nil, power, "WhoaBuilderSpenderFrame")
	feedback:SetAllPoints(power)
	feedback:SetFrameLevel(power:GetFrameLevel() + 1)
	power.FeedbackFrame = feedback

	-- Spikes/pulse: parent to unit frame (sibling of Overlay/Power) so we can
	-- raise above chrome; SyncToPowerBar anchors both to the power bar and
	-- sets level above NameHost so they paint over the fill.
	local fullPower = CreateFrame("Frame", nil, frame, "WhoaFullResourcePulseFrame")
	fullPower:ClearAllPoints()
	fullPower:SetPoint("TOPLEFT", power, "TOPLEFT")
	fullPower:SetPoint("BOTTOMRIGHT", power, "BOTTOMRIGHT")
	RaiseFullPowerFrame(fullPower, frame)
	power.FullPowerFrame = fullPower
	frame.FullPowerFrame = fullPower
	fullPower:SyncToPowerBar(power)

	SyncFeedbackColors(power)

	frame.statusBarAnimsAttached = true
	if self.AttachHealPrediction then
		self:AttachHealPrediction(frame)
	end
end

function WhoaUF:NotifyHealthBarAnimated(frame, previousHealth, currentHealth)
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(previousHealth, currentHealth) then
		return
	end
	local loss = frame and (frame.AnimatedLossBar or (frame.Health and frame.Health.AnimatedLossBar))
	if not loss then
		return
	end
	loss:UpdateHealthMinMax()
	if previousHealth ~= nil and currentHealth ~= nil and previousHealth ~= currentHealth then
		loss:UpdateHealth(currentHealth, previousHealth)
	end
end

function WhoaUF:NotifyPowerBarAnimated(frame, previousPower, currentPower, maxPower)
	-- Alpha hides the power bar; portrait runic/rage fill owns that resource.
	if frame and self.IsDkAlphaPlayerArtActive and self:IsDkAlphaPlayerArtActive(frame) then
		return
	end

	local power = frame and frame.Power
	if not power then
		return
	end

	local secret = WhoaUF.NeedsSecretSafeNumberOps
		and WhoaUF:NeedsSecretSafeNumberOps(previousPower, currentPower, maxPower)

	local feedback = power.FeedbackFrame
	local full = power.FullPowerFrame
	if feedback then
		if maxPower ~= nil then
			feedback:SetMaxValue(maxPower)
		end
		if power.powerType ~= feedback.powerType or power.unit ~= feedback.unit then
			SyncFeedbackColors(power)
		elseif maxPower ~= nil then
			feedback.maxValue = maxPower
		end
	end
	if full and maxPower ~= nil then
		full:SetMaxValue(maxPower)
		local wantActive = WhoaUF:WantsFullPowerAnim(power.powerToken, power.powerType)
		if full.active ~= not not wantActive then
			full:Initialize(wantActive)
		end
	end

	-- Full-power glow: always re-evaluate (secret-safe inside StartAnimIfFull).
	if full and full.active and currentPower ~= nil then
		full:SyncToPowerBar(power)
		full:StartAnimIfFull(currentPower)
	end

	if secret then
		return
	end

	if previousPower == nil or currentPower == nil or previousPower == currentPower then
		return
	end

	local maxValue = (feedback and feedback.maxValue) or maxPower or 0
	local info = WhoaUF:GetPowerBarColor(power.powerToken, power.powerType)
	if feedback and info and info.fullPowerAnim and maxValue ~= 0 and math.abs(currentPower - previousPower) / maxValue > 0.1 then
		feedback:StartFeedbackAnim(previousPower, currentPower)
	end
end

function WhoaUF:SyncFullPowerFrameLayout(powerBar)
	local full = powerBar and powerBar.FullPowerFrame
	if full and full.SyncToPowerBar then
		full:SyncToPowerBar(powerBar)
	end
end

function WhoaUF:SyncTickGlowLayout(frame)
	if self.SyncManaTickGlowLayout then
		self:SyncManaTickGlowLayout(frame)
	end
	if self.SyncPowerTickGlowLayout then
		self:SyncPowerTickGlowLayout(frame)
	end
	if self.SyncSwingTickGlowLayout then
		self:SyncSwingTickGlowLayout(frame)
	end
end

function WhoaUF:ClearStatusBarAnims(frame)
	if not frame then
		return
	end
	local loss = frame.AnimatedLossBar or (frame.Health and frame.Health.AnimatedLossBar)
	if loss and loss.CancelAnimation then
		loss:CancelAnimation()
	end
	local power = frame.Power
	if power and power.FeedbackFrame and power.FeedbackFrame.StopFeedbackAnim then
		power.FeedbackFrame:StopFeedbackAnim()
	end
	if power and self.StopManaTickGlow then
		self:StopManaTickGlow(power)
	end
	if power and self.StopPowerTickGlow then
		self:StopPowerTickGlow(power)
	end
	if power and self.StopSwingTickGlow then
		self:StopSwingTickGlow(power)
	end
	local alt = frame.AlternateManaBar
	if alt and self.StopManaTickGlow then
		self:StopManaTickGlow(alt)
	end
	local full = frame.FullPowerFrame or (power and power.FullPowerFrame)
	if full and full.RemoveAnims then
		full:RemoveAnims()
	end
	if self.HideHealPrediction then
		self:HideHealPrediction(frame)
	end
end
