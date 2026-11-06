--[[
	Mainline secret-safe target/focus cast bars.

	Whoa clone of TargetFrameMixin:CreateSpellbar / TargetSpellBarMixin
	(SmallCastingBarFrameTemplate + own OnEvent). Wired on target
	(PLAYER_TARGET_CHANGED) and focus (PLAYER_FOCUS_CHANGED).

	Mainline: Whoa secret-safe path — UnitCastingDuration + SetTimerDuration,
	pass-through SetText/SetTexture, shield via SetAlphaFromBoolean. Never call
	CastingBarMixin.HandleCastStart (branches on secret notInterruptible / times).

	Does NOT include Classic CastingBarMixin.OnEvent path.

	Requires Frames/Threat.lua first (WhoaUF:AdjustSpellBar / SyncHaveToT).
]]

-- Thin shim: Threat owns real AdjustSpellBarPosition.
local function AdjustSpellBarPosition(self)
	local parent = self and self:GetParent()
	if parent and WhoaUF.AdjustSpellBar then
		WhoaUF:AdjustSpellBar(parent)
	end
end

---------------------------------------------------------------------------
-- Mainline secret-safe spellbar — no CastingBarMixin cast handlers.
---------------------------------------------------------------------------

local TIMER_ELAPSED = (Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime)
	or (StatusBarTimerDirection and StatusBarTimerDirection.ElapsedTime)
	or 0
local TIMER_REMAINING = (Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime)
	or (StatusBarTimerDirection and StatusBarTimerDirection.RemainingTime)
	or 1
local TIMER_IMMEDIATE = (Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate)
	or (StatusBarInterpolation and StatusBarInterpolation.Immediate)
	or 0

local CAST_FILL_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
-- Classic small-bar colors (CastingBarTypeInfo classicFillColor).
local CAST_COLOR_STANDARD = { 1.0, 0.7, 0.0 }
local CAST_COLOR_CHANNEL = { 0.0, 1.0, 0.0 }

local function ApplyWhoaCastFill(bar, isChannel)
	if not bar then
		return
	end
	-- SpellbarArt_*.lua owns Classic geometry + dark/light chrome (SetLook + file textures).
	if WhoaUF.ApplySpellbarArt then
		WhoaUF:ApplySpellbarArt(bar)
	elseif WhoaUF.ApplySpellbarClassicLayout then
		WhoaUF:ApplySpellbarClassicLayout(bar)
	end
	if bar.SetStatusBarTexture then
		bar:SetStatusBarTexture(CAST_FILL_TEXTURE)
	end
	local c = isChannel and CAST_COLOR_CHANNEL or CAST_COLOR_STANDARD
	if bar.SetStatusBarColor then
		bar:SetStatusBarColor(c[1], c[2], c[3])
	end
end

local WHOA_SPELLBAR_UNIT_EVENTS = {
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE",
	"UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	"UNIT_SPELLCAST_EMPOWER_START",
	"UNIT_SPELLCAST_EMPOWER_UPDATE",
	"UNIT_SPELLCAST_EMPOWER_STOP",
}

-- Border = interruptible chrome; BorderShield = uninterruptible. Drive via
-- SetAlphaFromBoolean — never `if notInterruptible then` (secret on Mainline).
local function ApplyInterruptibleChrome(bar, notInterruptible)
	if not bar or bar.showShield == false then
		local shield = bar and bar.BorderShield
		if shield then
			shield:Hide()
		end
		return
	end
	local shield = bar.BorderShield
	local border = bar.Border or bar.BarBorder
	if shield then
		shield:Show()
		if shield.SetAlphaFromBoolean then
			shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
		elseif WhoaUF:CanAccessValue(notInterruptible) then
			shield:SetShown(notInterruptible and true or false)
		end
	end
	if border then
		border:Show()
		if border.SetAlphaFromBoolean then
			border:SetAlphaFromBoolean(notInterruptible, 0, 1)
		elseif WhoaUF:CanAccessValue(notInterruptible) then
			border:SetShown(not notInterruptible)
		end
	end
end

local function ClearWhoaSpellBar(bar)
	if not bar then
		return
	end
	bar.casting = nil
	bar.channeling = nil
	bar.whoaCastBarID = nil
	bar.whoaNotInterruptible = nil
	if bar.ClearTimerDuration then
		bar:ClearTimerDuration()
	elseif bar.SetMinMaxValues then
		bar:SetMinMaxValues(0, 0)
		bar:SetValue(0)
	end
	if bar.Spark then
		bar.Spark:Hide()
	end
	if bar.Flash then
		bar.Flash:Hide()
	end
	bar:Hide()
end

-- castBarID is NeverSecret; name may be secret — never truth-test name alone.
local function CastInfoIsPresent(name, castBarID)
	if castBarID ~= nil then
		return true
	end
	if name == nil then
		return false
	end
	-- Secret name still means an active cast (pass-through only).
	if WhoaUF:IsSecretValue(name) then
		return true
	end
	return WhoaUF:IsAccessibleTrue(name)
end

local function ApplyWhoaCastTimer(bar, unit, isChannel, isEmpowered)
	local duration
	if isEmpowered and UnitEmpoweredChannelDuration then
		duration = UnitEmpoweredChannelDuration(unit)
	elseif isChannel and UnitChannelDuration then
		duration = UnitChannelDuration(unit)
	elseif (not isChannel) and UnitCastingDuration then
		duration = UnitCastingDuration(unit)
	elseif UnitCastingDuration then
		duration = UnitCastingDuration(unit)
	end
	if duration == nil or not bar.SetTimerDuration then
		return false
	end
	local direction = isChannel and TIMER_REMAINING or TIMER_ELAPSED
	local ok = pcall(function()
		bar:SetTimerDuration(duration, TIMER_IMMEDIATE, direction)
	end)
	return ok and true or false
end

local function StartWhoaSpellBar(bar, isChannel, isEmpowered)
	local unit = bar.unit
	if not unit then
		ClearWhoaSpellBar(bar)
		return
	end

	local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID, castBarID
	if isChannel or isEmpowered then
		name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID, _, _, castBarID =
			UnitChannelInfo(unit)
	else
		name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID, castBarID =
			UnitCastingInfo(unit)
	end

	if not CastInfoIsPresent(name, castBarID) then
		ClearWhoaSpellBar(bar)
		return
	end
	-- isTradeSkill is NeverSecret — safe to branch.
	if not bar.showTradeSkills and isTradeSkill then
		ClearWhoaSpellBar(bar)
		return
	end

	bar.casting = (not isChannel) or isEmpowered or nil
	bar.channeling = isChannel and not isEmpowered or nil
	bar.whoaCastBarID = castBarID
	bar.whoaNotInterruptible = notInterruptible

	-- Layout + border art before icon/text so ClearAtlas/layout cannot wipe them.
	ApplyWhoaCastFill(bar, isChannel and not isEmpowered)
	ApplyInterruptibleChrome(bar, notInterruptible)
	-- Shield show is common in instances; rebind dark/light after chrome alpha swap.
	if WhoaUF.ApplySpellbarArt then
		WhoaUF:ApplySpellbarArt(bar)
	end

	if bar.Text then
		bar.Text:SetText(text or name)
	end
	if bar.Icon then
		bar.Icon:SetTexture(texture)
		bar.Icon:Show()
	end

	if not ApplyWhoaCastTimer(bar, unit, isChannel, isEmpowered) then
		-- Fallback only when times are plain (player/pet / unrestricted).
		if WhoaUF:CanAccessValue(startTime) and WhoaUF:CanAccessValue(endTime) then
			local maxValue = (endTime - startTime) / 1000
			local value
			if isChannel then
				value = (endTime / 1000) - GetTime()
			else
				value = GetTime() - (startTime / 1000)
			end
			bar:SetMinMaxValues(0, maxValue)
			bar:SetValue(value)
		else
			-- Secret times + no duration object: still show chrome; fill stays empty.
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(0)
		end
	end

	-- Spark needs GetValue arithmetic — hide under secret timer path.
	if bar.Spark then
		bar.Spark:Hide()
	end
	if bar.Flash then
		bar.Flash:Hide()
	end

	if bar.showCastbar == false then
		bar:Hide()
		return
	end
	AdjustSpellBarPosition(bar)
	bar:Show()
	if WhoaUF.ApplySpellbarArt then
		WhoaUF:ApplySpellbarArt(bar)
	end
end

local function RefreshWhoaSpellBarFromUnit(bar)
	local unit = bar.unit
	if not unit then
		ClearWhoaSpellBar(bar)
		return
	end
	-- Prefer channel then cast; castBarID NeverSecret for presence.
	local name, _, _, _, _, _, _, _, isEmpowered, _, castBarID = UnitChannelInfo(unit)
	if CastInfoIsPresent(name, castBarID) then
		StartWhoaSpellBar(bar, true, WhoaUF:IsAccessibleTrue(isEmpowered))
		return
	end
	name, _, _, _, _, _, _, _, _, castBarID = UnitCastingInfo(unit)
	if CastInfoIsPresent(name, castBarID) then
		StartWhoaSpellBar(bar, false, false)
		return
	end
	ClearWhoaSpellBar(bar)
end

local function WhoaSpellBar_OnEvent(self, event, ...)
	local unit = ...

	if event == "VARIABLES_LOADED" or (event == "CVAR_UPDATE" and unit == "showTargetCastbar") then
		if GetCVar("showTargetCastbar") == "0" then
			self.showCastbar = false
		else
			self.showCastbar = true
		end
		if not self.showCastbar then
			self:Hide()
		elseif self.casting or self.channeling then
			self:Show()
		end
		return
	end

	if event == self.updateEvent then
		AdjustSpellBarPosition(self)
		RefreshWhoaSpellBarFromUnit(self)
		return
	end

	if unit ~= self.unit then
		return
	end

	if event == "UNIT_SPELLCAST_START" then
		StartWhoaSpellBar(self, false, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		StartWhoaSpellBar(self, true, false)
	elseif event == "UNIT_SPELLCAST_EMPOWER_START" then
		StartWhoaSpellBar(self, true, true)
	elseif event == "UNIT_SPELLCAST_STOP"
		or event == "UNIT_SPELLCAST_CHANNEL_STOP"
		or event == "UNIT_SPELLCAST_EMPOWER_STOP"
		or event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_INTERRUPTED" then
		ClearWhoaSpellBar(self)
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		if self.casting then
			StartWhoaSpellBar(self, false, false)
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		if self.channeling then
			StartWhoaSpellBar(self, true, false)
		end
	elseif event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
		if self.casting or self.channeling then
			StartWhoaSpellBar(self, true, true)
		end
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		if not self:IsShown() then
			return
		end
		-- Event name is plain (castID missing on these events). Pass boolean to chrome.
		local notInterruptible = (event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
		self.whoaNotInterruptible = notInterruptible
		ApplyInterruptibleChrome(self, notInterruptible)
		if WhoaUF.ApplySpellbarArt then
			WhoaUF:ApplySpellbarArt(self)
		end
	end
end

local function WhoaSpellBar_SetUnit(self, unit, showTradeSkills, showShield)
	self.unit = unit
	self.showTradeSkills = showTradeSkills and true or false
	self.showShield = showShield ~= false
	self:UnregisterAllEvents()
	self:RegisterEvent("CVAR_UPDATE")
	self:RegisterEvent("VARIABLES_LOADED")
	if self.updateEvent then
		self:RegisterEvent(self.updateEvent)
	end
	if unit then
		for i = 1, #WHOA_SPELLBAR_UNIT_EVENTS do
			local ev = WHOA_SPELLBAR_UNIT_EVENTS[i]
			pcall(function()
				if self.RegisterUnitEvent then
					self:RegisterUnitEvent(ev, unit)
				else
					self:RegisterEvent(ev)
				end
			end)
		end
	end
	if GetCVar("showTargetCastbar") == "0" then
		self.showCastbar = false
	else
		self.showCastbar = true
	end
	RefreshWhoaSpellBarFromUnit(self)
end


local function FinishSpellbarSetup(frame, spellbar, updateEvent)
	-- Mirror TargetFrameMixin:CreateSpellbar (TextureFrame level - 1); stay under ToT chrome.
	if frame.totFrame and WhoaUF.ApplyToTFrameLevel then
		WhoaUF:ApplyToTFrameLevel(frame.totFrame, frame)
	end
	local totLevel = frame.totFrame and frame.totFrame:GetFrameLevel()
	if totLevel then
		spellbar:SetFrameLevel(totLevel - 1)
	else
		local overlay = frame.Overlay
		if overlay then
			spellbar:SetFrameLevel(overlay:GetFrameLevel() - 1)
		else
			spellbar:SetFrameLevel(frame:GetFrameLevel())
		end
	end
	frame.spellbar = spellbar
	frame.auraRows = frame.auraRows or 0
	spellbar.AdjustPosition = AdjustSpellBarPosition
	spellbar.whoaSecretSafeCast = true

	if updateEvent then
		spellbar.updateEvent = updateEvent
	end

	spellbar:SetScript("OnEvent", WhoaSpellBar_OnEvent)
	spellbar:SetScript("OnUpdate", nil)
	spellbar:SetScript("OnShow", AdjustSpellBarPosition)
	spellbar.SetUnit = WhoaSpellBar_SetUnit
	-- Force classic StatusBar fill + Classic small sizes (template is 150x20 modern).
	ApplyWhoaCastFill(spellbar, false)
	-- Do not SetLook here — SpellbarArt_*.lua ApplySpellbarArt owns look + dark/light rebind.
	if WhoaUF.ApplySpellbarArt then
		WhoaUF:ApplySpellbarArt(spellbar)
	end
	WhoaSpellBar_SetUnit(spellbar, frame.unit, false, true)

	-- Opt into Whoa cast chrome (SpellbarArt_*.lua skips unmarked / nameplate bars).
	spellbar.whoaCastArtHooked = true
	spellbar.whoaClassicLookApplied = nil
	if WhoaUF.ApplySpellbarArt then
		WhoaUF:ApplySpellbarArt(spellbar)
	end
	if spellbar.SetLook and not spellbar.whoaCastArtSetLookHooked then
		spellbar.whoaCastArtSetLookHooked = true
		hooksecurefunc(spellbar, "SetLook", function(self)
			if WhoaUF.ApplySpellbarArt then
				WhoaUF:ApplySpellbarArt(self)
			end
		end)
	end
	spellbar:HookScript("OnShow", function(self)
		if WhoaUF.ApplySpellbarArt then
			WhoaUF:ApplySpellbarArt(self)
		end
	end)

	AdjustSpellBarPosition(spellbar)
	return spellbar
end

-- Mirror TargetFrameMixin:CreateSpellbar — Whoa frames only.
local function CreateSpellbar(frame, updateEvent)
	if not frame then
		return nil
	end
	if frame.spellbar then
		return frame.spellbar
	end
	local name = frame:GetName() .. "SpellBar"
	local template = "SmallCastingBarFrameTemplate"
	local spellbar
	local ok
	if not DoesTemplateExist or DoesTemplateExist(template) then
		ok, spellbar = pcall(CreateFrame, "StatusBar", name, frame, template)
	end
	if not ok or not spellbar then
		spellbar = CreateFrame("StatusBar", name, frame)
		spellbar:SetSize(150, 10)
		local bg = spellbar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.5)
		spellbar.Border = spellbar:CreateTexture(nil, "ARTWORK")
		spellbar.Border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
		spellbar.Border:SetHeight(56)
		spellbar.Border:SetPoint("TOPLEFT", -23, 23)
		spellbar.Border:SetPoint("TOPRIGHT", 23, 23)
		spellbar.BorderShield = spellbar:CreateTexture(nil, "OVERLAY")
		spellbar.BorderShield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
		spellbar.BorderShield:SetHeight(56)
		spellbar.BorderShield:SetPoint("TOPLEFT", -28, 23)
		spellbar.BorderShield:SetPoint("TOPRIGHT", 18, 23)
		spellbar.BorderShield:Hide()
		spellbar.Icon = spellbar:CreateTexture(nil, "OVERLAY")
		spellbar.Icon:SetSize(16, 17)
		spellbar.Icon:SetPoint("RIGHT", spellbar, "LEFT", -5, 1)
		spellbar.Text = spellbar:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
		spellbar.Text:SetPoint("TOPLEFT", 0, 4)
		spellbar.Text:SetPoint("TOPRIGHT", 0, 4)
		spellbar.Spark = spellbar:CreateTexture(nil, "OVERLAY")
		spellbar.Spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
		spellbar.Spark:SetSize(32, 32)
		spellbar.Spark:SetBlendMode("ADD")
		spellbar.Spark:SetPoint("CENTER", 0, 0)
		spellbar.Spark:Hide()
		ApplyWhoaCastFill(spellbar, false)
	end
	return FinishSpellbarSetup(frame, spellbar, updateEvent)
end

function WhoaUF:CreateUnitSpellbar(frame, updateEvent)
	return CreateSpellbar(frame, updateEvent)
end

function WhoaUF:ReleaseSpellbarRuntime(frame)
	local bar = frame and frame.spellbar
	if not bar then
		return
	end
	bar:UnregisterAllEvents()
	ClearWhoaSpellBar(bar)
end

function WhoaUF:ResumeSpellbarRuntime(frame)
	local bar = frame and frame.spellbar
	if not bar then
		return
	end
	if bar.SetUnit then
		bar:SetUnit(frame.unit, false, true)
		return
	end
	bar:RegisterEvent("CVAR_UPDATE")
	bar:RegisterEvent("VARIABLES_LOADED")
	if bar.updateEvent then
		bar:RegisterEvent(bar.updateEvent)
	end
end
