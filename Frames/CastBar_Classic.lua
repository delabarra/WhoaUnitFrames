--[[
	Classic target/focus cast bars (CastingBarMixin).

	Whoa clone of TargetFrameMixin:CreateSpellbar / TargetSpellBarMixin
	(SmallCastingBarFrameTemplate + own OnEvent). Wired on target
	(PLAYER_TARGET_CHANGED) and focus (PLAYER_FOCUS_CHANGED).

	Classic: CastingBarMixin.OnEvent (safe; notInterruptible is nil/plain).
	Does NOT include Mainline secret-safe cast code.

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
-- Classic spellbar (CastingBarMixin) — notInterruptible is nil/plain.
---------------------------------------------------------------------------

local function SpellBar_OnEvent(self, event, ...)
	local arg1 = ...

	if event == "VARIABLES_LOADED" or (event == "CVAR_UPDATE" and arg1 == "showTargetCastbar") then
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
	elseif event == self.updateEvent then
		local nameChannel = UnitChannelInfo(self.unit)
		local nameSpell = UnitCastingInfo(self.unit)
		if nameChannel then
			event = "UNIT_SPELLCAST_CHANNEL_START"
			arg1 = self.unit
		elseif nameSpell then
			event = "UNIT_SPELLCAST_START"
			arg1 = self.unit
		else
			self.casting = nil
			self.channeling = nil
			self:SetMinMaxValues(0, 0)
			self:SetValue(0)
			self:Hide()
			return
		end
		AdjustSpellBarPosition(self)
	end

	CastingBarMixin.OnEvent(self, event, arg1, select(2, ...))
end


local CAST_FILL_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local CAST_COLOR_STANDARD = { 1.0, 0.7, 0.0 }
local CAST_COLOR_CHANNEL = { 0.0, 1.0, 0.0 }

local function ApplyWhoaCastFill(bar, isChannel)
	if not bar then
		return
	end
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
	spellbar.whoaSecretSafeCast = nil

	if updateEvent then
		spellbar.updateEvent = updateEvent
	end

	spellbar:SetScript("OnEvent", SpellBar_OnEvent)
	spellbar:HookScript("OnShow", AdjustSpellBarPosition)
	spellbar:RegisterEvent("CVAR_UPDATE")
	spellbar:RegisterEvent("VARIABLES_LOADED")
	if spellbar.SetUnit then
		spellbar:SetUnit(frame.unit, false, true)
	end
	if updateEvent then
		spellbar:RegisterEvent(updateEvent)
	end
	if GetCVar("showTargetCastbar") == "0" then
		spellbar.showCastbar = false
	else
		spellbar.showCastbar = true
	end

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
	bar:Hide()
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
