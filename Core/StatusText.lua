--[[
	Classic target/focus status numbers (stock Blizzard + Whoa TextStatusBars).

	API (Classic Era+): UnitHealth/UnitHealthMax return absolute HP for many NPCs;
	enemy players stay 0–100 scaled. Stock UnitFrameHealthBar_Update still sets
	showPercentage when max==100 OR not ShouldKnowUnitHealth — period authenticity,
	not API availability. Whoa bars honor statusTextDisplay on the raw API values
	(never force showPercentage from ShouldKnowUnitHealth). Stock-bar post-process
	rewrites NUMERIC to cur/max even when Blizzard set showPercentage, so absolute
	NPC HP is visible.

	Mainline (Midnight+): Blizzard-intended display path — no Lua math on secrets.
	  PERCENT → UnitHealthPercent / UnitPowerPercent (+ CurveConstants.ScaleTo100)
	  NUMERIC → FormatStatusNumber (numberAbbreviation; C abbreviators when secret)
	  BOTH    → percent via Unit*Percent + abbreviated cur on the side
	Install WhoaUF:InstallStatusBarText on Whoa bars only — never replace global
	TextStatusBarMixin (nameplates/CUF share it inside CompactUnitFrame_UpdateAll).

	Reference: Blizzard_UnitFrame/Classic/UnitFrame.lua UnitFrameHealthBar_Update
	           Blizzard_SharedXMLBase/CurveConstants.lua
]]

local IS_MAINLINE = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local STOCK_TARGET_HEALTH_TEXT = { centerX = -33, centerY = -1, leftX = 25, rightX = -93 }
local STOCK_TARGET_POWER_TEXT = { centerX = -33, centerY = -12, leftX = 25, rightX = -93 }

local STOCK_FRAMES = {
	"TargetFrame",
	"FocusFrame",
}

local function GetStockTextureOverlay(frame)
	if not frame then
		return nil
	end
	return frame.textureFrame or _G[frame:GetName() .. "TextureFrame"]
end

local function GetStockHealthBar(frame)
	if not frame then
		return nil
	end
	return frame.HealthBar or frame.healthbar or _G[frame:GetName() .. "HealthBar"]
end

local function GetStockPowerBar(frame)
	if not frame then
		return nil
	end
	return frame.PowerBar or frame.ManaBar or frame.manabar or _G[frame:GetName() .. "ManaBar"]
end

local function AnchorStockFontString(fs, overlay, anchors, point, justify)
	if not fs or not overlay or not anchors then
		return
	end
	fs:ClearAllPoints()
	if point == "CENTER" then
		fs:SetPoint("CENTER", overlay, "CENTER", anchors.centerX, anchors.centerY)
	elseif point == "LEFT" then
		fs:SetPoint("LEFT", overlay, "LEFT", anchors.leftX, anchors.centerY)
		if justify then
			fs:SetJustifyH(justify)
		end
	elseif point == "RIGHT" then
		fs:SetPoint("RIGHT", overlay, "RIGHT", anchors.rightX, anchors.centerY)
		if justify then
			fs:SetJustifyH(justify)
		end
	end
	if WhoaUF.ApplyStatusBarTextFont then
		WhoaUF:ApplyStatusBarTextFont(fs)
	end
end

local function SyncStockBarText(bar, overlay, anchors, centerKey, leftKey, rightKey)
	if not bar or not overlay then
		return
	end

	local center = overlay[centerKey]
	local left = overlay[leftKey]
	local right = overlay[rightKey]
	if not center or not left or not right then
		return
	end

	AnchorStockFontString(center, overlay, anchors, "CENTER")
	AnchorStockFontString(left, overlay, anchors, "LEFT", "LEFT")
	AnchorStockFontString(right, overlay, anchors, "RIGHT", "RIGHT")

	bar.TextString = center
	bar.LeftText = left
	bar.RightText = right
	if bar.SetBarText then
		bar:SetBarText(center, left, right)
	end
	if WhoaUF.UpdateBarTextString then
		WhoaUF:UpdateBarTextString(bar)
	end
end

local function SyncStockTargetLikeFrame(frame)
	local overlay = GetStockTextureOverlay(frame)
	if not overlay then
		return
	end

	SyncStockBarText(
		GetStockHealthBar(frame),
		overlay,
		STOCK_TARGET_HEALTH_TEXT,
		"HealthBarText",
		"HealthBarTextLeft",
		"HealthBarTextRight"
	)
	SyncStockBarText(
		GetStockPowerBar(frame),
		overlay,
		STOCK_TARGET_POWER_TEXT,
		"ManaBarText",
		"ManaBarTextLeft",
		"ManaBarTextRight"
	)
end

function WhoaUF:ApplyStockTargetStatusText()
	-- Stock Target/Focus text sync is Classic-only (Mainline hides those frames).
	if IS_MAINLINE then
		return
	end
	for i = 1, #STOCK_FRAMES do
		SyncStockTargetLikeFrame(_G[STOCK_FRAMES[i]])
	end
end

local function SuppressStatusBarText(statusFrame, textString)
	if textString then
		textString:SetText("")
		textString:Hide()
	end
	if statusFrame and statusFrame.LeftText then
		statusFrame.LeftText:SetText("")
		statusFrame.LeftText:Hide()
	end
	if statusFrame and statusFrame.RightText then
		statusFrame.RightText:SetText("")
		statusFrame.RightText:Hide()
	end
end

local function ClearSideTexts(statusFrame)
	if statusFrame.LeftText and statusFrame.RightText then
		statusFrame.LeftText:SetText("")
		statusFrame.RightText:SetText("")
		statusFrame.LeftText:Hide()
		statusFrame.RightText:Hide()
	end
end

local function ShouldShowStatusBarText(statusFrame)
	if (statusFrame.cvar and GetCVar(statusFrame.cvar) == "1" and statusFrame.textLockable)
		or statusFrame.forceShow
	then
		return true
	end
	if statusFrame.lockShow and statusFrame.lockShow > 0 and not statusFrame.forceHideText then
		return true
	end
	return false
end

local function FormatBarNumber(statusFrame, value)
	local abbreviate = statusFrame.capNumericDisplay and true or false
	if statusFrame.numericDisplayTransformFunc then
		-- numericDisplayTransformFunc needs accessible numbers — skip when secret.
		return nil
	end
	return WhoaUF:FormatStatusNumber(value, abbreviate)
end

local function WriteFormatted(fs, pattern, ...)
	if not fs then
		return
	end
	fs:SetFormattedText(pattern, ...)
	fs:Show()
end

local function ResolveBarPercent(statusFrame, value, valueMax)
	local unit = statusFrame.unit
	if unit then
		local powerType = statusFrame.powerType
		if statusFrame.powerToken ~= nil or powerType ~= nil then
			local pct = WhoaUF:GetUnitStatusPercent(unit, powerType or UnitPowerType(unit))
			if pct ~= nil then
				return pct
			end
		else
			local pct = WhoaUF:GetUnitStatusPercent(unit)
			if pct ~= nil then
				return pct
			end
		end
	end
	if WhoaUF:CanAccessValue(value) and WhoaUF:CanAccessValue(valueMax) and valueMax > 0 then
		return math.ceil((value / valueMax) * 100)
	end
	return nil
end

local function WritePercentText(fs, pct, prefix)
	if pct == nil or not fs then
		return false
	end
	if WhoaUF:CanAccessValue(pct) then
		local n = math.ceil(pct)
		if prefix then
			WriteFormatted(fs, "%s %d%%", prefix, n)
		else
			WriteFormatted(fs, "%d%%", n)
		end
		return true
	end
	-- Secret percent: pass through C formatters / SetFormattedText (no Lua math).
	local trunc = C_StringUtil and C_StringUtil.TruncateWhenZero
	local shown = trunc and trunc(pct) or pct
	if prefix then
		WriteFormatted(fs, "%s %s%%", prefix, shown)
	else
		WriteFormatted(fs, "%s%%", shown)
	end
	return true
end

local function WriteNumericText(statusFrame, textString, valueDisplay, valueMaxDisplay, prefix)
	local disableMax = statusFrame.disableMaxValue
	if prefix then
		if disableMax then
			WriteFormatted(textString, "%s %s", prefix, valueDisplay)
		else
			WriteFormatted(textString, "%s %s / %s", prefix, valueDisplay, valueMaxDisplay)
		end
	elseif disableMax then
		WriteFormatted(textString, "%s", valueDisplay)
	else
		WriteFormatted(textString, "%s / %s", valueDisplay, valueMaxDisplay)
	end
end

--- Classic + Mainline status text on Whoa bars.
--- Mainline uses Unit*Percent / AbbreviateNumbers (no Lua math on secrets).
local function WriteStatusBarText(statusFrame, textString, value, valueMin, valueMax)
	if not statusFrame or not textString then
		return
	end
	if statusFrame.forceHideText then
		SuppressStatusBarText(statusFrame, textString)
		return
	end

	ClearSideTexts(statusFrame)

	local secret = WhoaUF:NeedsSecretSafeNumberOps(value, valueMax, valueMin)
	local maxOk
	if secret then
		-- Inaccessible max: bar already SetValue'd — still format via C display APIs.
		maxOk = true
	else
		maxOk = (tonumber(valueMax) ~= valueMax or valueMax > 0) and not statusFrame.pauseUpdates
	end

	if not maxOk or statusFrame.pauseUpdates then
		textString:Hide()
		textString:SetText("")
		if not statusFrame.alwaysShow and statusFrame.controlsShownState ~= false then
			statusFrame:Hide()
		end
		return
	end

	if statusFrame.controlsShownState ~= false then
		statusFrame:Show()
	end

	if not ShouldShowStatusBarText(statusFrame) then
		textString:SetText("")
		textString:Hide()
		return
	end

	local shouldUsePrefix = statusFrame.prefix
		and (statusFrame.alwaysPrefix
			or not (statusFrame.cvar and GetCVar(statusFrame.cvar) == "1" and statusFrame.textLockable))
	local prefix = shouldUsePrefix and statusFrame.prefix or nil

	local textDisplay = GetCVar("statusTextDisplay")
	local showNumeric = statusFrame.showNumeric
	local showPercentage = statusFrame.showPercentage
	if showNumeric then
		textDisplay = "NUMERIC"
	elseif showPercentage then
		textDisplay = "PERCENT"
	end

	-- Mainline: prefer percent when Unit*Percent exists and display is PERCENT/BOTH.
	-- NUMERIC still uses AbbreviateNumbers (accepts secrets).

	-- zeroText only when we can prove value == 0
	if statusFrame.zeroText and WhoaUF:CanAccessValue(value) and value == 0 then
		textString:SetText(statusFrame.zeroText)
		statusFrame.isZero = 1
		textString:Show()
		return
	end
	statusFrame.isZero = nil

	local valueDisplay, valueMaxDisplay
	if not secret and statusFrame.numericDisplayTransformFunc then
		valueDisplay, valueMaxDisplay = statusFrame.numericDisplayTransformFunc(value, valueMax)
	else
		-- Mainline secrets: AbbreviateNumbers (C API accepts secrets). Classic: honor bar flag.
		if secret or WhoaUF:UsesSecretValues() then
			valueDisplay = WhoaUF:FormatStatusNumber(value, true)
			valueMaxDisplay = WhoaUF:FormatStatusNumber(valueMax, true)
		else
			valueDisplay = FormatBarNumber(statusFrame, value)
			valueMaxDisplay = FormatBarNumber(statusFrame, valueMax)
		end
	end

	-- NUMERIC / NONE: cur/max from API values (absolute NPC HP or 0–100 players).
	if textDisplay == "NUMERIC" or textDisplay == "NONE" or showNumeric then
		WriteNumericText(statusFrame, textString, valueDisplay, valueMaxDisplay, prefix)
		return
	end

	if textDisplay == "BOTH" then
		local pct = ResolveBarPercent(statusFrame, value, valueMax)
		if statusFrame.LeftText and statusFrame.RightText then
			local token = statusFrame.powerToken
			local showLeftPct = token == nil
				or (WhoaUF:CanAccessValue(token) and token == "MANA")
			if showLeftPct and pct ~= nil then
				WritePercentText(statusFrame.LeftText, pct)
			end
			WriteFormatted(statusFrame.RightText, "%s", valueDisplay)
			textString:Hide()
			textString:SetText("")
		elseif pct ~= nil then
			if WhoaUF:CanAccessValue(pct) then
				WriteFormatted(
					textString,
					"(%d%%) %s / %s",
					math.ceil(pct),
					valueDisplay,
					valueMaxDisplay
				)
			else
				local trunc = C_StringUtil and C_StringUtil.TruncateWhenZero
				if trunc then
					WriteFormatted(textString, "(%s%%) %s / %s", trunc(pct), valueDisplay, valueMaxDisplay)
				else
					-- SetFormattedText accepts secret numbers as %s via tostring-like path.
					WriteFormatted(textString, "(%s%%) %s / %s", pct, valueDisplay, valueMaxDisplay)
				end
			end
		else
			WriteNumericText(statusFrame, textString, valueDisplay, valueMaxDisplay, prefix)
		end
		return
	end

	-- PERCENT (and default percent path)
	local pct = ResolveBarPercent(statusFrame, value, valueMax)
	if pct ~= nil then
		WritePercentText(textString, pct, prefix)
	else
		WriteNumericText(statusFrame, textString, valueDisplay, valueMaxDisplay, prefix)
	end
end

-- Post-hook for Classic stock bars: honor statusTextDisplay on API values.
-- Blizzard may set showPercentage via ShouldKnowUnitHealth even when UnitHealthMax
-- is absolute NPC HP — override that so NUMERIC/BOTH can show real numbers.
local function PostProcessStatusBarText(statusFrame, textString, value, valueMin, valueMax)
	if not statusFrame or not textString then
		return
	end
	if WhoaUF:NeedsSecretSafeNumberOps(value, valueMax, valueMin) then
		return
	end
	if statusFrame.forceHideText then
		SuppressStatusBarText(statusFrame, textString)
		return
	end

	if statusFrame.LeftText and statusFrame.RightText then
		statusFrame.LeftText:SetText("")
		statusFrame.RightText:SetText("")
		statusFrame.LeftText:Hide()
		statusFrame.RightText:Hide()
	end

	local valueDisplay = value
	local valueMaxDisplay = valueMax
	if statusFrame.capNumericDisplay then
		valueDisplay = WhoaUF:FormatStatusNumber(value, true)
		valueMaxDisplay = WhoaUF:FormatStatusNumber(valueMax, true)
	elseif BreakUpLargeNumbers then
		valueDisplay = BreakUpLargeNumbers(value)
		valueMaxDisplay = BreakUpLargeNumbers(valueMax)
	end

	if (tonumber(valueMax) ~= valueMax or valueMax > 0) and not statusFrame.pauseUpdates then
		if statusFrame.controlsShownState ~= false then
			statusFrame:Show()
		end

		if (statusFrame.cvar and GetCVar(statusFrame.cvar) == "1" and statusFrame.textLockable)
			or statusFrame.forceShow then
			textString:Show()
		elseif statusFrame.lockShow > 0 and not statusFrame.forceHideText then
			textString:Show()
		else
			textString:SetText("")
			textString:Hide()
			return
		end

		local textDisplay = GetCVar("statusTextDisplay")
		if value and valueMax > 0 and textDisplay ~= "NUMERIC" and textDisplay ~= "NONE" and not statusFrame.showNumeric then
			if value == 0 and statusFrame.zeroText then
				textString:SetText(statusFrame.zeroText)
				statusFrame.isZero = 1
				textString:Show()
			elseif textDisplay == "BOTH" then
				if statusFrame.LeftText and statusFrame.RightText then
					if not statusFrame.powerToken or statusFrame.powerToken == "MANA" then
						statusFrame.LeftText:SetText(math.ceil((value / valueMax) * 100) .. "%")
						statusFrame.LeftText:Show()
					end
					statusFrame.RightText:SetText(valueDisplay)
					statusFrame.RightText:Show()
					textString:Hide()
				else
					valueDisplay = "(" .. math.ceil((value / valueMax) * 100) .. "%) " .. valueDisplay .. " / " .. valueMaxDisplay
					textString:SetText(valueDisplay)
				end
			else
				valueDisplay = math.ceil((value / valueMax) * 100) .. "%"
				if statusFrame.prefix and (statusFrame.alwaysPrefix
					or not (statusFrame.cvar and GetCVar(statusFrame.cvar) == "1" and statusFrame.textLockable)) then
					textString:SetText(statusFrame.prefix .. " " .. valueDisplay)
				else
					textString:SetText(valueDisplay)
				end
			end
		elseif value == 0 and statusFrame.zeroText then
			textString:SetText(statusFrame.zeroText)
			statusFrame.isZero = 1
			textString:Show()
		else
			statusFrame.isZero = nil
			local numeric
			if statusFrame.GetNumericDisplay then
				numeric = statusFrame:GetNumericDisplay(valueDisplay, valueMaxDisplay)
			elseif statusFrame.disableMaxValue then
				numeric = valueDisplay
			else
				numeric = valueDisplay .. " / " .. valueMaxDisplay
			end
			if statusFrame.prefix and (statusFrame.alwaysPrefix
				or not (statusFrame.cvar and GetCVar(statusFrame.cvar) == "1" and statusFrame.textLockable)) then
				textString:SetText(statusFrame.prefix .. " " .. numeric)
			else
				textString:SetText(numeric)
			end
			textString:Show()
		end
	else
		textString:Hide()
		textString:SetText("")
		if not statusFrame.alwaysShow and statusFrame.controlsShownState ~= false then
			statusFrame:Hide()
		elseif statusFrame:GetValue() ~= 0 then
			statusFrame:SetValue(0)
		end
	end
end

local initDone

-- Per-bar only. Never replace TextStatusBarMixin / TextStatusBar_* globals on
-- Mainline: nameplates and CompactUnitFrame share those paths inside
-- CompactUnitFrame_UpdateAll; a tainted mixin call leaves the rest of UpdateAll
-- (e.g. UpdateHealPrediction maxHealth <= 0) unable to compare secrets.
local function StatusBarTextFromMixin(self, textString, value, valueMin, valueMax)
	WriteStatusBarText(self, textString, value, valueMin, valueMax)
end

--- Install Whoa status writer on a Whoa bar only (never global TextStatusBarMixin).
--- Classic + Mainline: NUMERIC / PERCENT / BOTH via secret-safe formatters on retail.
function WhoaUF:InstallStatusBarText(bar)
	if not bar or bar.whoaStatusTextInstalled then
		return
	end
	bar.whoaStatusTextInstalled = true
	bar.whoaWriteStatusBarText = WriteStatusBarText

	-- Instance overrides so SetValue → OnStatusBarValueChanged never enters
	-- Blizzard TextStatusBarMixin:UpdateTextStringWithValues (secret compares).
	local function WhoaUpdateTextString(self)
		local textString = self.TextString
		if not textString then
			return
		end
		local valueMin, valueMax = self:GetMinMaxValues()
		WriteStatusBarText(self, textString, self:GetValue(), valueMin, valueMax)
	end

	bar.UpdateTextStringWithValues = StatusBarTextFromMixin
	bar.UpdateTextString = WhoaUpdateTextString
	bar.OnStatusBarValueChanged = function(self)
		WhoaUpdateTextString(self)
		if self.Spark and self.Spark.OnBarValuesUpdated then
			self.Spark:OnBarValuesUpdated(self)
		end
	end
end

function WhoaUF:InitStatusText()
	if initDone then
		self:ApplyStockTargetStatusText()
		return
	end
	initDone = true

	-- Classic only: post-process stock bars for NUMERIC cur/max (known HP only).
	-- Mainline must not hook TextStatusBarMixin (taints CUF/nameplate UpdateAll).
	if not IS_MAINLINE then
		if TextStatusBarMixin and TextStatusBarMixin.UpdateTextStringWithValues then
			hooksecurefunc(TextStatusBarMixin, "UpdateTextStringWithValues", function(statusFrame, textString, value, valueMin, valueMax)
				if statusFrame and statusFrame.whoaStatusTextInstalled then
					return
				end
				PostProcessStatusBarText(statusFrame, textString, value, valueMin, valueMax)
			end)
		elseif TextStatusBar_UpdateTextStringWithValues then
			hooksecurefunc("TextStatusBar_UpdateTextStringWithValues", function(statusFrame, textString, value, valueMin, valueMax)
				if statusFrame and statusFrame.whoaStatusTextInstalled then
					return
				end
				PostProcessStatusBarText(statusFrame, textString, value, valueMin, valueMax)
			end)
		end

		local function SuppressForceHidden(statusFrame)
			if statusFrame and statusFrame.forceHideText then
				SuppressStatusBarText(statusFrame, statusFrame.TextString)
			end
		end
		if TextStatusBarMixin and TextStatusBarMixin.ShowStatusBarText then
			hooksecurefunc(TextStatusBarMixin, "ShowStatusBarText", SuppressForceHidden)
		end
		if TextStatusBarMixin and TextStatusBarMixin.OnStatusBarEnter then
			hooksecurefunc(TextStatusBarMixin, "OnStatusBarEnter", SuppressForceHidden)
		end
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:SetScript("OnEvent", function()
		WhoaUF:ApplyStockTargetStatusText()
	end)

	self:ApplyStockTargetStatusText()
end

WhoaUF.InitStockTargetStatusText = WhoaUF.InitStatusText
WhoaUF.WriteStatusBarText = WriteStatusBarText
