--[[
	Unit frame shared helpers: life status, hit rects, power visibility, menus, bar setup.
	Internal module — use WhoaUF._UF for cross-module state.
]]

local UF = WhoaUF._UF
local frames = UF.frames
local function GetTargetFrameTexture(key)
	if WhoaUF.GetFrameTexture then
		return WhoaUF:GetFrameTexture(key)
	end
	-- Fallback before Core/Appearance.lua loads.
	local files = {
		normal = "UI-TargetingFrame",
		minus = "UI-TargetingFrame-Minus",
		elite = "UI-TargetingFrame-Elite",
		rareelite = "UI-TargetingFrame-Rare-Elite",
		rare = "UI-TargetingFrame-Rare",
		player = "UI-TargetingFrame",
		tot = "UI-TargetofTargetFrame",
		pvpFFA = "UI-PVP-FFA",
	}
	return "Interface\\TargetingFrame\\" .. (files[key] or files.normal)
end

-- CreatureType.dbc: Critter. Used so Classic critters get the minus (minor) frame.
local CREATURE_TYPE_CRITTER = 8
local critterTypeName

local function GetCritterTypeName()
	if critterTypeName then
		return critterTypeName
	end
	if C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo then
		local info = C_CreatureInfo.GetCreatureTypeInfo(CREATURE_TYPE_CRITTER)
		if info and info.name then
			critterTypeName = info.name
			return critterTypeName
		end
	end
	critterTypeName = "Critter"
	return critterTypeName
end

-- Minus classification, or critter creature type (Classic lacks minus for critters).
function WhoaUF:IsMinusUnit(unit)
	if not unit or not UnitExists(unit) then
		return false
	end
	local classification = UnitClassification(unit)
	if WhoaUF:CanAccessValue(classification) and classification == "minus" then
		return true
	end
	local creatureType, creatureTypeID = UnitCreatureType(unit)
	-- Mainline: creature type/ID are often secret in instances — skip compares.
	if WhoaUF:CanAccessValue(creatureTypeID) and creatureTypeID == CREATURE_TYPE_CRITTER then
		return true
	end
	if WhoaUF:CanAccessValue(creatureType) and creatureType == GetCritterTypeName() then
		return true
	end
	return false
end

-- Dead / Ghost / Unconscious / Offline overlays. Ghost is released-spirit; Dead is corpse.
-- Offline is a disconnected player (same HP-slot label path as Dead). Feign Death is not Dead.
-- Classic often lacks a GHOST global.
local GHOST_LABELS = {
	enUS = "Ghost",
	enGB = "Ghost",
	deDE = "Geist",
	esES = "Fantasma",
	esMX = "Fantasma",
	frFR = "Fant?me",
	itIT = "Fantasma",
	koKR = "??",
	ptBR = "Fantasma",
	ptPT = "Fantasma",
	ruRU = "???????",
	zhCN = "??",
	zhTW = "??",
}

local function GetGhostText()
	if type(GHOST) == "string" and GHOST ~= "" and GHOST ~= "GHOST" then
		return GHOST
	end
	local locale = GetLocale and GetLocale()
	return (locale and GHOST_LABELS[locale]) or GHOST_LABELS.enUS
end

local function GetUnitLifeStatus(unit)
	if not unit or not UnitExists(unit) then
		return nil
	end
	-- Offline wins over dead/ghost — disconnected units report 0 HP but are not corpses.
	-- Mainline: UnitIs* booleans may be secret — never `if UnitIsX(unit) then`.
	local isPlayer = WhoaUF:IsAccessibleTrue(UnitIsPlayer(unit))
	local isConnected = WhoaUF:IsAccessibleTrue(UnitIsConnected(unit))
	if isPlayer and not isConnected then
		return "offline"
	end
	if UnitIsUnconscious and WhoaUF:IsAccessibleTrue(UnitIsUnconscious(unit)) then
		return "unconscious"
	end
	if WhoaUF:IsAccessibleTrue(UnitIsGhost(unit)) then
		return "ghost"
	end
	if UnitIsFeignDeath and WhoaUF:IsAccessibleTrue(UnitIsFeignDeath(unit)) then
		return nil
	end
	if WhoaUF:IsAccessibleTrue(UnitIsDead(unit)) then
		return "dead"
	end
	-- Fallback for clients that leave UnitIsDead false briefly: only when HP is Lua-accessible.
	local health = UnitHealth(unit)
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(health) and health <= 0 then
		return "dead"
	end
	return nil
end

local function HidePowerBarText(bar)
	if not bar then
		return
	end
	if bar.TextString then
		bar.TextString:Hide()
	end
	if bar.LeftText then
		bar.LeftText:Hide()
	end
	if bar.RightText then
		bar.RightText:Hide()
	end
end

local function UpdateBarTextString(bar)
	if not bar then
		return
	end
	-- Prefer Whoa's writer so Mainline never enters Blizzard TextStatusBar Lua
	-- arithmetic on secrets from a tainted Whoa stack.
	local writer = bar.whoaWriteStatusBarText or WhoaUF.WriteStatusBarText
	if writer and bar.TextString then
		local valueMin, valueMax = bar:GetMinMaxValues()
		writer(bar, bar.TextString, bar:GetValue(), valueMin, valueMax)
		return
	end
	if bar.UpdateTextString then
		bar:UpdateTextString()
	elseif TextStatusBar_UpdateTextString then
		TextStatusBar_UpdateTextString(bar)
	end
end

-- Blizzard UnitFrameHealthBar_OnUpdate: poll UnitHealth while the bar is shown.
-- Classic target HP often changes without a timely UNIT_HEALTH; OnUpdate matches stock.
-- Snap SetValue here (do not call full UpdateHealth) so custom bar textures track the
-- game on the same cadence as Blizzard — full rebuilds stay on UNIT_* / unit swap.
-- Also poll max: UNIT_MAXHEALTH can lag a beat on Classic and leave the fill wrong.
local function FrequentHealthBar_OnUpdate(self)
	if self.lockValues or self.disconnected then
		return
	end
	local unit = self.unit
	if not unit or not UnitExists(unit) then
		return
	end
	local currValue = UnitHealth(unit)
	local maxValue = UnitHealthMax(unit)
	-- Secrets: paint via SetValue only (no ~= / loss anim). Skip when unchanged
	-- is unknowable — StatusBars accept repeated secret SetValue.
	if WhoaUF.NeedsSecretSafeNumberOps
		and WhoaUF:NeedsSecretSafeNumberOps(currValue, self.currValue, maxValue, self.whoaFrequentMax)
	then
		self.whoaFrequentMax = maxValue
		self:SetMinMaxValues(0, maxValue)
		self:SetValue(currValue)
		self.currValue = currValue
		UpdateBarTextString(self)
		local frame = self.whoaUnitFrame
		if frame and WhoaUF.UpdateHealPrediction then
			WhoaUF:UpdateHealPrediction(frame)
		end
		return
	end

	local animatedLossBar = self.AnimatedLossBar
	if maxValue ~= self.whoaFrequentMax then
		self.whoaFrequentMax = maxValue
		local maxForBar = maxValue
		if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(maxValue) and maxValue == 0 then
			maxForBar = 1
		end
		self:SetMinMaxValues(0, maxForBar)
		if animatedLossBar and animatedLossBar.UpdateHealthMinMax then
			animatedLossBar:UpdateHealthMinMax()
		end
	end

	if currValue ~= self.currValue then
		if animatedLossBar
			and animatedLossBar.UpdateHealth
			and self.whoaHealthPainted
			and self.currValue ~= nil
		then
			animatedLossBar:UpdateHealth(currValue, self.currValue)
		end
		self:SetValue(currValue)
		self.currValue = currValue
		UpdateBarTextString(self)
		local frame = self.whoaUnitFrame
		if frame and WhoaUF.UpdateHealPrediction then
			WhoaUF:UpdateHealPrediction(frame)
		end
	end

	if animatedLossBar and animatedLossBar.UpdateLossAnimation then
		animatedLossBar:UpdateLossAnimation(currValue)
	end
end

local function ArmFrequentHealthBar(bar, frame)
	if not bar or bar.whoaFrequentHealthArmed then
		return
	end
	bar.whoaFrequentHealthArmed = true
	bar.frequentUpdates = true
	bar.whoaUnitFrame = frame
	if frame and frame.unit and not bar.unit then
		bar.unit = frame.unit
	end
	-- Mainline: UNIT_HEALTH drives UpdateHealth with secret-safe SetValue.
	-- Skip Classic-style OnUpdate poll (avoids per-frame secret SetValue + anim paths).
	if WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues() then
		return
	end
	bar:SetScript("OnUpdate", FrequentHealthBar_OnUpdate)
end

-- Blizzard UnitFrameManaBar_OnUpdate (ManaBarFrequentUpdateUnitTypes): power often
-- moves without a timely UNIT_POWER_* on Classic. Snap the fill like stock — full
-- UpdatePower stays on type/max==0 / unit-swap paths.
local function RefreshFrequentPowerOwner(frame, unit)
	if not frame then
		return
	end
	-- Pet owns paint + mana/no-mana chrome via UpdatePetPower.
	if frame.kind == "pet" and WhoaUF.UpdatePetFrame then
		WhoaUF:UpdatePetFrame()
	elseif UF.UpdatePower then
		UF.UpdatePower(frame, unit)
	end
end

local function FrequentPowerBar_OnUpdate(self)
	if self.pauseUpdates or self.lockValues or self.disconnected then
		return
	end
	local unit = self.unit
	if not unit or not UnitExists(unit) then
		return
	end
	local powerUnit = unit
	if WhoaUF.UnitMatchesToken and WhoaUF:UnitMatchesToken(unit, "player") then
		powerUnit = "player"
	elseif not WhoaUF.UnitMatchesToken and UnitIsUnit and WhoaUF:IsAccessibleTrue(UnitIsUnit(unit, "player")) then
		powerUnit = "player"
	end
	local powerType = UnitPowerType(powerUnit)
	-- Power type may be secret on Mainline — never ~= it; defer to owner refresh.
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(powerType) then
		RefreshFrequentPowerOwner(self.whoaUnitFrame, unit)
		return
	end
	if self.powerType ~= powerType then
		RefreshFrequentPowerOwner(self.whoaUnitFrame, unit)
		return
	end

	local maxValue = UnitPowerMax(powerUnit, powerType)
	local currValue = UnitPower(powerUnit, powerType)
	if WhoaUF.NeedsSecretSafeNumberOps
		and WhoaUF:NeedsSecretSafeNumberOps(currValue, self.currValue, maxValue, self.whoaFrequentMax)
	then
		self.whoaFrequentMax = maxValue
		self:SetMinMaxValues(0, maxValue)
		self:SetValue(currValue)
		self.currValue = currValue
		UpdateBarTextString(self)
		return
	end

	-- No-resource units: UpdatePower / UpdatePetPower owns hide / pauseUpdates.
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(maxValue) and maxValue == 0 then
		RefreshFrequentPowerOwner(self.whoaUnitFrame, unit)
		return
	end

	if maxValue ~= self.whoaFrequentMax then
		self.whoaFrequentMax = maxValue
		self:SetMinMaxValues(0, maxValue)
		local feedback = self.FeedbackFrame
		if feedback and feedback.SetMaxValue then
			feedback:SetMaxValue(maxValue)
		end
		local full = self.FullPowerFrame
		if full and full.SetMaxValue then
			full:SetMaxValue(maxValue)
		end
	end

	if currValue == self.currValue and not self.forceUpdate then
		return
	end
	self.forceUpdate = nil

	local oldValue = self.currValue
	if self.whoaPowerPainted and oldValue ~= nil and currValue ~= oldValue then
		local feedback = self.FeedbackFrame
		local maxForAnim = (feedback and feedback.maxValue) or self.whoaFrequentMax or 0
		if feedback and feedback.StartFeedbackAnim and maxForAnim ~= 0 then
			local info = WhoaUF.GetPowerBarColor and WhoaUF:GetPowerBarColor(self.powerToken, powerType)
			if info and info.fullPowerAnim and math.abs(currValue - oldValue) / maxForAnim > 0.1 then
				feedback:StartFeedbackAnim(oldValue, currValue)
			end
		end
	end
	local full = self.FullPowerFrame
	if full and full.active and full.StartAnimIfFull then
		if full.SyncToPowerBar then
			full:SyncToPowerBar(self)
		end
		full:StartAnimIfFull(currValue)
	end

	self:SetValue(currValue)
	self.currValue = currValue
	UpdateBarTextString(self)
end

local function ArmFrequentPowerBar(bar, frame)
	if not bar or bar.whoaFrequentPowerArmed then
		return
	end
	bar.whoaFrequentPowerArmed = true
	bar.frequentUpdates = true
	bar.whoaUnitFrame = frame
	if frame and frame.unit and not bar.unit then
		bar.unit = frame.unit
	end
	-- Mainline: UNIT_POWER_* / UpdatePower paints secrets; skip Classic OnUpdate poll.
	if WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues() then
		return
	end
	bar:SetScript("OnUpdate", FrequentPowerBar_OnUpdate)
end

local function SetBarTextStrings(bar, center, left, right)
	if bar.SetBarText then
		bar:SetBarText(center, left, right)
	else
		bar.TextString = center
		bar.LeftText = left
		bar.RightText = right
	end
end

-- SecureUnitButton children: combat-safe Show/Hide for target/focus power bars.
-- Custom textures often ignore SetValue while Hidden / same-value after Show.
-- Never poke to max — that paints a full bar (rage red flash) before the real value.
local function SnapStatusBarValue(bar, value)
	if not bar or value == nil or not bar.SetValue then
		return
	end
	-- Mainline: never poke via min/max compares (secrets). SetValue only.
	if WhoaUF.UsesClassicStatusBarSnap and not WhoaUF:UsesClassicStatusBarSnap() then
		bar:SetValue(value)
		return
	end
	-- Defensive: if secrets appear on a Classic build, still skip poke.
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(value) then
		bar:SetValue(value)
		return
	end
	local minV, maxV = bar:GetMinMaxValues()
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(minV, maxV) then
		bar:SetValue(value)
		return
	end
	if maxV and minV and maxV > minV then
		local poke = minV
		if value == minV then
			-- Tiny non-zero poke so SetValue(0) is a real change — not a full fill.
			local span = maxV - minV
			poke = minV + ((span > 100) and 1 or (span * 0.01))
			if poke <= minV or poke >= maxV then
				poke = nil
			end
		end
		if poke ~= nil and poke ~= value then
			bar:SetValue(poke)
		else
			bar:SetMinMaxValues(minV, maxV)
		end
	end
	bar:SetValue(value)
end

local function HideUnitPowerBarNow(power, frame)
	HidePowerBarText(power)
	if InCombatLockdown() and power:IsProtected() then
		UF.pendingPowerVisibility = UF.pendingPowerVisibility or {}
		if frame then
			UF.pendingPowerVisibility[frame] = false
		end
		if power:IsShown() then
			power:SetAlpha(0)
		end
	else
		power:Hide()
		power:SetAlpha(1)
	end
end

-- Unit-swap hold: keep the bar shown at alpha 0 so SetValue sticks on custom textures
-- (fully hidden bars often ignore SetValue and flash a full fill on Show).
local function CloakUnitPowerBarForHold(power, frame)
	HidePowerBarText(power)
	if InCombatLockdown() and power:IsProtected() then
		UF.pendingPowerVisibility = UF.pendingPowerVisibility or {}
		if frame then
			UF.pendingPowerVisibility[frame] = false
		end
		if power:IsShown() then
			power:SetAlpha(0)
			if power.currValue ~= nil then
				SnapStatusBarValue(power, power.currValue)
			end
		end
		return
	end
	power:SetAlpha(0)
	power:Show()
	if power.currValue ~= nil then
		SnapStatusBarValue(power, power.currValue)
	else
		local minV = power:GetMinMaxValues()
		-- Never coalesce secrets (`minV or 0`); SetValue accepts secret min.
		if minV ~= nil then
			power:SetValue(minV)
		else
			power:SetValue(0)
		end
	end
end

local function SetUnitPowerBarVisible(frame, shown)
	local power = frame and frame.Power
	if not power then
		return
	end
	if shown then
		if power.pauseUpdates then
			return
		end
		-- Unit-swap hold: stay at alpha 0 (bar remains shown), never reveal early.
		if power.whoaPowerHoldReveal then
			CloakUnitPowerBarForHold(power, frame)
			return
		end
		-- Never reveal an unpainted bar (TextStatusBar defaults to a full fill).
		if not power.whoaPowerPainted and power.currValue == nil then
			HideUnitPowerBarNow(power, frame)
			return
		end
		if InCombatLockdown() and power:IsProtected() then
			UF.pendingPowerVisibility = UF.pendingPowerVisibility or {}
			UF.pendingPowerVisibility[frame] = true
			if power:IsShown() then
				power:SetAlpha(0)
				SnapStatusBarValue(power, power.currValue)
				power:SetAlpha(1)
			end
		else
			power:SetAlpha(0)
			power:Show()
			SnapStatusBarValue(power, power.currValue)
			power:SetAlpha(1)
			-- Ensure fill vertex alpha survived any prior transparent color reset.
			local tex = power.GetStatusBarTexture and power:GetStatusBarTexture()
			if tex and tex.SetAlpha then
				tex:SetAlpha(1)
			end
			UpdateBarTextString(power)
		end
	else
		HideUnitPowerBarNow(power, frame)
	end
end

local function SetPowerBarShownForStatus(frame, shown)
	local manaBar = frame and frame.Power
	if not manaBar then
		return
	end
	-- Power is a StatusBar child of SecureUnitButton — Show/Hide is locked in combat.
	if shown then
		if manaBar.pauseUpdates then
			return
		end
		if manaBar.whoaPowerHoldReveal then
			CloakUnitPowerBarForHold(manaBar, frame)
			return
		end
		if not manaBar.whoaPowerPainted and manaBar.currValue == nil then
			HideUnitPowerBarNow(manaBar, frame)
			return
		end
		if InCombatLockdown() and manaBar:IsProtected() then
			UF.pendingPowerVisibility = UF.pendingPowerVisibility or {}
			UF.pendingPowerVisibility[frame] = true
			if manaBar:IsShown() then
				manaBar:SetAlpha(0)
				SnapStatusBarValue(manaBar, manaBar.currValue)
				manaBar:SetAlpha(1)
			end
		else
			manaBar:SetAlpha(0)
			manaBar:Show()
			SnapStatusBarValue(manaBar, manaBar.currValue)
			manaBar:SetAlpha(1)
			local tex = manaBar.GetStatusBarTexture and manaBar:GetStatusBarTexture()
			if tex and tex.SetAlpha then
				tex:SetAlpha(1)
			end
			UpdateBarTextString(manaBar)
		end
	else
		if manaBar.TextString then
			manaBar.TextString:Hide()
		end
		if manaBar.LeftText then
			manaBar.LeftText:Hide()
		end
		if manaBar.RightText then
			manaBar.RightText:Hide()
		end
		if InCombatLockdown() and manaBar:IsProtected() then
			UF.pendingPowerVisibility = UF.pendingPowerVisibility or {}
			UF.pendingPowerVisibility[frame] = false
			if manaBar:IsShown() then
				manaBar:SetAlpha(0)
			end
		else
			manaBar:Hide()
			manaBar:SetAlpha(1)
		end
	end
end

local function ApplyUnitStatusOverlay(frame, status)
	if not frame then
		return
	end

	-- Dead / Ghost / Offline share DeadText; Unconscious keeps its own label.
	local deadText = frame.DeadText
	local unconsciousText = frame.UnconsciousText
	if status == "unconscious" and unconsciousText then
		if deadText then
			deadText:Hide()
		end
		if UNCONSCIOUS then
			unconsciousText:SetText(UNCONSCIOUS)
		end
		unconsciousText:Show()
	elseif (status == "dead" or status == "ghost" or status == "offline") and deadText then
		if unconsciousText then
			unconsciousText:Hide()
		end
		if status == "ghost" then
			deadText:SetText(GetGhostText())
		elseif status == "offline" then
			deadText:SetText(PLAYER_OFFLINE or "Offline")
		else
			deadText:SetText(DEAD or "Dead")
		end
		deadText:Show()
	else
		if deadText then
			deadText:Hide()
		end
		if unconsciousText then
			unconsciousText:Hide()
		end
	end

	-- Party/target lightning bolt over the portrait while disconnected.
	if frame.Disconnect then
		frame.Disconnect:SetShown(status == "offline")
	end

	local health = frame.Health
	if health then
		if status then
			-- TextStatusBar hover (lockShow) must not resurrect HP numbers over Dead/Ghost/Offline.
			health.forceHideText = true
			if health.TextString then
				health.TextString:Hide()
			end
			if health.LeftText then
				health.LeftText:Hide()
			end
			if health.RightText then
				health.RightText:Hide()
			end
		else
			health.forceHideText = false
			UpdateBarTextString(health)
		end
	end

	-- Player / target / focus / ToT: hide power while dead, ghost, or offline.
	local hidePower = status == "dead" or status == "ghost" or status == "offline"
	local power = frame.Power
	if power then
		power.forceHideText = hidePower or status == "unconscious"
		if power.forceHideText then
			HidePowerBarText(power)
		end
	end
	SetPowerBarShownForStatus(frame, not hidePower)

	-- Druid/monk alt mana sits under the player frame — hide with primary power.
	if frame.kind == "player" and frame.AlternateManaBar then
		if hidePower then
			frame.AlternateManaBar:Hide()
			frame.AlternateManaBar:SetScript("OnUpdate", nil)
		elseif WhoaUF.RefreshAlternateManaBar then
			WhoaUF:RefreshAlternateManaBar()
		end
	end

	local portrait = frame.Portrait
	if portrait then
		if status == "dead" or status == "unconscious" then
			portrait:SetVertexColor(0.35, 0.35, 0.35)
		elseif status == "ghost" then
			portrait:SetVertexColor(0.2, 0.2, 0.75)
		elseif status == "offline" then
			portrait:SetVertexColor(0.5, 0.5, 0.5)
		elseif frame.kind == "player" then
			portrait:SetVertexColor(1, 1, 1)
		end
		-- target/focus: when clear, UpdateNameBackground already set color.
		-- tot/focustot: low-HP red handled by UpdateToTFrame after this.
	end
end

-- UnitPopup menus: use SetupSecureUnitButton → *type2=togglemenu only.
-- Addon UnitPopup_OpenMenu / menu-function taints SetPVP and other protected clicks.

-- HitRectInsets: template AbsInset only (UnitFrameClassic.xml). No runtime SetHitRectInsets.

-- SecureUnitButton EnableMouse is protected in combat (ToT/pet alpha hide path).
-- Track pending frames explicitly so party pets / nested SecureUnitButtons flush too.
local pendingSecureMouseFrames = {}

local function SetSecureMouseEnabled(frame, enabled)
	if not frame or not frame.EnableMouse then
		return
	end
	enabled = enabled and true or false
	if InCombatLockdown() then
		frame._pendingMouseEnabled = enabled
		pendingSecureMouseFrames[frame] = true
		return
	end
	frame._pendingMouseEnabled = nil
	pendingSecureMouseFrames[frame] = nil
	frame:EnableMouse(enabled)
end

local function FlushPendingSecureMouse()
	for frame in pairs(pendingSecureMouseFrames) do
		if type(frame) == "table" and frame._pendingMouseEnabled ~= nil and frame.EnableMouse then
			frame:EnableMouse(frame._pendingMouseEnabled)
			frame._pendingMouseEnabled = nil
		end
		pendingSecureMouseFrames[frame] = nil
	end
end

local TEMP_PORTRAIT = "Interface\\CharacterFrame\\TempPortrait"
local CLASS_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"

-- One setting for every Whoa frame:
--   normal — Blizzard SetPortraitTexture
--   class  — class circle for players; normal for everyone else
local PORTRAIT_MODE_NORMAL = "normal"
local PORTRAIT_MODE_CLASS = "class"

local function ResetPortraitTexCoord(portrait)
	if portrait and portrait.SetTexCoord then
		portrait:SetTexCoord(0, 1, 0, 1)
	end
end

local function GetPortraitMode()
	local mode = WhoaUF.db and WhoaUF.db.portraitMode
	if mode == PORTRAIT_MODE_CLASS then
		return mode
	end
	return PORTRAIT_MODE_NORMAL
end

local function SetPortraitAlpha(frame, alpha)
	if frame and frame.Portrait then
		frame.Portrait:SetAlpha(alpha)
	end
end

local function ApplyClassIconToPortrait(portrait, unit)
	local _, classFile = UnitClass(unit)
	if not classFile or not CLASS_ICON_TCOORDS then
		return false
	end
	local coords = CLASS_ICON_TCOORDS[string.upper(classFile)]
	if not coords then
		return false
	end
	portrait:SetTexture(CLASS_ICON_TEXTURE)
	portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	return true
end

local function ApplyNormalPortrait(frame, unit)
	local portrait = frame.Portrait
	portrait:Show()
	ResetPortraitTexCoord(portrait)
	portrait:SetVertexColor(1, 1, 1)
	SetPortraitTexture(portrait, unit)
end

local function ApplyClassPortrait(frame, unit)
	local portrait = frame.Portrait
	portrait:Show()
	portrait:SetVertexColor(1, 1, 1)
	if WhoaUF:IsAccessibleTrue(UnitIsPlayer(unit))
		and not (WhoaUF.IsMinusUnit and WhoaUF:IsMinusUnit(unit))
		and ApplyClassIconToPortrait(portrait, unit)
	then
		return
	end
	ResetPortraitTexCoord(portrait)
	SetPortraitTexture(portrait, unit)
end

local function UpdatePortrait(frame, unit)
	if not frame or not frame.Portrait or not unit or not UnitExists(unit) then
		return
	end
	-- Mainline: skip GUID cache (secret); always refresh portrait texture.
	if not (WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues()) then
		local guid = UnitGUID(unit)
		if frame.PortraitLastGuid ~= guid then
			frame.PortraitLastGuid = guid
			frame.PortraitLastUnit = unit
		end
	else
		frame.PortraitLastGuid = nil
		frame.PortraitLastUnit = unit
	end
	if GetPortraitMode() == PORTRAIT_MODE_CLASS then
		ApplyClassPortrait(frame, unit)
	else
		ApplyNormalPortrait(frame, unit)
	end
end

local function ResetFramePortrait(frame)
	if not frame or not frame.Portrait then
		return
	end
	frame.PortraitLastGuid = nil
	frame.PortraitLastUnit = nil
	frame.Portrait:SetTexture(TEMP_PORTRAIT)
	ResetPortraitTexCoord(frame.Portrait)
	frame.Portrait:SetVertexColor(1, 1, 1)
	frame.Portrait:Show()
end

function WhoaUF:RefreshAllPortraits()
	local function bump(frame)
		if not frame or not frame.Portrait then
			return
		end
		frame.PortraitLastGuid = nil
		frame.PortraitLastUnit = nil
		if frame.unit and UnitExists(frame.unit) then
			UpdatePortrait(frame, frame.unit)
		end
	end
	local list = UF.frames
	if list then
		for _, frame in pairs(list) do
			if type(frame) == "table" then
				bump(frame)
			end
		end
	end
	if self.partyFrames then
		for i = 1, #self.partyFrames do
			local pf = self.partyFrames[i]
			bump(pf)
			if pf and pf.PetFrame then
				bump(pf.PetFrame)
			end
		end
	end
	if self.unitFrames and self.unitFrames.pet then
		bump(self.unitFrames.pet)
	end
	if self.bossFrames then
		for i = 1, #self.bossFrames do
			bump(self.bossFrames[i])
		end
	end
end

local function ClearUnitFrameVisuals(frame)
	if not frame then
		return
	end
	if frame.Name then
		frame.Name:SetText("")
	end
	if frame.Level then
		frame.Level:Hide()
		frame.Level:SetText("")
	end
	if frame.HighLevelTexture then
		frame.HighLevelTexture:Hide()
	end
	if frame.Portrait then
		frame.Portrait:SetTexture(nil)
		ResetPortraitTexCoord(frame.Portrait)
		frame.Portrait:SetVertexColor(1, 1, 1)
		frame.Portrait:Show()
		frame.PortraitLastUnit = nil
		frame.PortraitLastGuid = nil
	end
	if frame.Disconnect then
		frame.Disconnect:Hide()
	end
	frame.whoaLastUnitGuid = nil
	if frame.Health then
		frame.Health:SetMinMaxValues(0, 1)
		frame.Health:SetValue(0)
		frame.Health.currValue = nil
		frame.Health.whoaHealthUnit = nil
		frame.Health.whoaHealthPainted = nil
		frame.Health.whoaFrequentMax = nil
	end
	if frame.Power then
		if not frame.Power.pauseUpdates then
			frame.Power:SetMinMaxValues(0, 1)
			frame.Power:SetValue(0)
			frame.Power.currValue = nil
		end
		frame.Power.whoaPowerPainted = nil
		frame.Power.whoaPowerUnit = nil
		frame.Power.whoaFrequentMax = nil
		frame.Power.powerType = nil
		frame.Power.powerToken = nil
		-- Hold only for target-like tokens; player must not stay cloaked forever.
		if frame.kind == "target" or frame.kind == "focus" or frame.kind == "tot" or frame.kind == "focustot" then
			frame.Power.whoaPowerHoldReveal = true
		else
			frame.Power.whoaPowerHoldReveal = nil
		end
		frame.Power.pauseUpdates = false
		HidePowerBarText(frame.Power)
		frame.Power:Hide()
		frame.Power:SetAlpha(1)
	end
	-- Overlay must not re-Show an unpainted power bar (status nil ⇒ “show power”).
	ApplyUnitStatusOverlay(frame, nil)
	if frame.Power then
		frame.Power:Hide()
	end
	if frame.PvPIcon then
		frame.PvPIcon:Hide()
	end
	if frame.LeaderIcon then
		frame.LeaderIcon:Hide()
	end
	if frame.RaidTargetIcon then
		frame.RaidTargetIcon:Hide()
	end
	if frame.HitIndicator then
		frame.HitIndicator:Hide()
	end
	if UF.StopCombatFeedbackPulse then
		UF.StopCombatFeedbackPulse(frame)
	end
	if UF.SetAttackModeShown then
		UF.SetAttackModeShown(frame, false)
	elseif frame.AttackMode then
		frame.AttackMode:Hide()
		local pulse = frame.attackPulse
		if pulse and pulse.whoaActive then
			pulse:SetScript("OnUpdate", nil)
			pulse.whoaActive = false
		end
	end
	frame.whoaChromeKey = nil
	frame.whoaChromePainted = nil
	frame.isMinus = nil
	frame.haveElite = nil
	if frame.kind == "target" or frame.kind == "focus" then
		frame.whoaTargetRevealHold = nil
		frame:SetAlpha(1)
	end
end

-- Pet / ToT AttackMode: show + pulse, or hide + clear OnUpdate (UIParent pulse host).
local function SetAttackModeShown(frame, shown)
	local attack = frame and frame.AttackMode
	if not attack then
		return
	end
	local pulse = frame.attackPulse
	if shown then
		if not attack:IsShown() then
			attack:SetVertexColor(1, 1, 1, 1)
			attack:Show()
			if pulse and pulse.OnUpdate and not pulse.whoaActive then
				pulse:SetScript("OnUpdate", pulse.OnUpdate)
				pulse.whoaActive = true
			end
		end
	else
		if attack:IsShown() then
			attack:Hide()
		end
		if pulse and pulse.whoaActive then
			pulse:SetScript("OnUpdate", nil)
			pulse.whoaActive = false
		end
	end
end

local function ResetFrameHealthPaint(frame)
	if not frame or not frame.Health then
		return
	end
	frame.Health.whoaHealthPainted = nil
	frame.Health.whoaHealthUnit = nil
	frame.Health.currValue = nil
	frame.Health.whoaFrequentMax = nil
	local loss = frame.AnimatedLossBar or frame.Health.AnimatedLossBar
	if loss and loss.CancelAnimation then
		loss:CancelAnimation()
	end
end

-- Hide classification border on unit swap so a stale elite/normal sheet cannot
-- show for a frame before ApplyTargetClassificationChrome paints the new unit.
-- Target/focus only — never touch player/pet/party chrome.
local function ResetFrameChrome(frame)
	if not frame or (frame.kind ~= "target" and frame.kind ~= "focus") then
		return
	end
	frame.whoaChromeKey = nil
	frame.whoaChromePainted = nil
	frame.isMinus = nil
	frame.haveElite = nil
end

-- Addon classification BLPs often finish loading a frame after SetTexture.
-- Only cloak the whole frame when it is newly shown (no target → target).
-- Retarget must stay visible and update in place (Blizzard TargetFrame behavior).
local function HoldTargetFrameReveal(frame)
	if not frame or (frame.kind ~= "target" and frame.kind ~= "focus") then
		return
	end
	frame.whoaTargetRevealHold = true
	frame:SetAlpha(0)
end

local function ReleaseTargetFrameReveal(frame)
	if not frame or (frame.kind ~= "target" and frame.kind ~= "focus") then
		return
	end
	if not frame.whoaTargetRevealHold and frame:GetAlpha() == 1 then
		if frame.FrameTexture then
			frame.FrameTexture:SetAlpha(1)
		end
		return
	end
	frame.whoaTargetRevealHold = nil
	if frame.FrameTexture then
		frame.FrameTexture:SetAlpha(1)
	end
	frame.whoaChromePainted = frame.whoaChromePainted or frame.whoaChromeKey ~= nil
	frame:SetAlpha(1)
end

local function RevealFrameChrome(frame)
	if not frame or (frame.kind ~= "target" and frame.kind ~= "focus") then
		return
	end
	local tex = frame.FrameTexture
	if not tex then
		return
	end
	tex:SetAlpha(1)
	frame.whoaChromePainted = true
end

-- Blank power immediately on unit swap so prior rage/mana fill (and feedback glow)
-- cannot flash for a frame before UpdatePower proves the new unit has a resource.
-- Target/focus/ToT only — player/pet keep a live bar (no hold / no transparent fill).
local function ResetFramePowerPaint(frame)
	local power = frame and frame.Power
	if not power then
		return
	end
	local kind = frame.kind
	if kind ~= "target" and kind ~= "focus" and kind ~= "tot" and kind ~= "focustot" then
		return
	end
	power.whoaPowerPainted = nil
	power.whoaPowerUnit = nil
	power.currValue = nil
	power.whoaFrequentMax = nil
	power.powerType = nil
	power.powerToken = nil
	-- Hold reveal until the deferred retarget pass (UnitPowerType can lag one frame).
	power.whoaPowerHoldReveal = true
	-- Allow UpdatePower to re-evaluate; minus/DK paths re-pause in Classification.
	power.pauseUpdates = false
	if power.FeedbackFrame and power.FeedbackFrame.StopFeedbackAnim then
		power.FeedbackFrame:StopFeedbackAnim()
	end
	local full = power.FullPowerFrame
	if full and full.RemoveAnims then
		full:RemoveAnims()
	end
	power:SetMinMaxValues(0, 1)
	-- Do not SetStatusBarColor(..., 0): a later 3-arg SetStatusBarColor can leave
	-- fill alpha at 0 (mana numbers show, blue fill invisible). Cloak via frame alpha.
	power.currValue = 0
	CloakUnitPowerBarForHold(power, frame)
	power:SetValue(0)
end

local function ReleasePowerBarReveal(frame)
	local power = frame and frame.Power
	if not power then
		return
	end
	power.whoaPowerHoldReveal = nil
end

-- Reset health paint + portrait when the unit behind a stable token changes (target/focus/ToT).
local function SyncFrameUnitGuid(frame, unit)
	if not frame then
		return false
	end
	-- Mainline: UnitGUID often secret — skip identity cache (events still repaint).
	if WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues() then
		if frame.whoaLastUnitGuid ~= nil then
			frame.whoaLastUnitGuid = nil
		end
		return false
	end
	local guid = (unit and UnitExists(unit)) and UnitGUID(unit) or nil
	if frame.whoaLastUnitGuid == guid then
		return false
	end
	frame.whoaLastUnitGuid = guid
	ResetFrameHealthPaint(frame)
	ResetFramePowerPaint(frame)
	ResetFrameChrome(frame)
	ResetFramePortrait(frame)
	return true
end

local function RefreshFocusFrames()
	local focus = frames.focus
	local focustot = frames.focustot
	if not focus then
		return
	end

	local function refreshBoth()
		-- Focus/ToF tokens can swap identity while the frame stays shown.
		ResetFrameHealthPaint(focus)
		ResetFramePowerPaint(focus)
		ResetFrameChrome(focus)
		local acquiring = UnitExists("focus")
		if acquiring and not focus:IsShown() then
			HoldTargetFrameReveal(focus)
		elseif acquiring and not focus.whoaTargetRevealHold then
			focus:SetAlpha(1)
		end
		if acquiring and WhoaUF.ApplyTargetClassificationChrome then
			WhoaUF:ApplyTargetClassificationChrome(focus)
		end
		WhoaUF:UpdateUnitFrame(focus)
		if focustot then
			ResetFrameHealthPaint(focustot)
			ResetFramePowerPaint(focustot)
			WhoaUF:UpdateUnitFrame(focustot)
		end
		if focus.spellbar and WhoaUF.AdjustSpellBar then
			WhoaUF:AdjustSpellBar(focus)
		end
	end

	local function revealAndRefresh()
		-- Release hold from the immediate Reset, then repaint (do not Reset again).
		ReleasePowerBarReveal(focus)
		if focus.whoaTargetRevealHold then
			ReleaseTargetFrameReveal(focus)
		end
		WhoaUF:UpdateUnitFrame(focus)
		if focustot then
			ReleasePowerBarReveal(focustot)
			WhoaUF:UpdateUnitFrame(focustot)
		end
		if focus.spellbar and WhoaUF.AdjustSpellBar then
			WhoaUF:AdjustSpellBar(focus)
		end
	end

	-- Immediate paint (power held) + deferred reveal when UnitPowerType is stable.
	refreshBoth()
	C_Timer.After(0, revealAndRefresh)
	C_Timer.After(0.05, revealAndRefresh)
end

-- Plain UIParent watcher — never HookScript OnShow/OnHide on SecureUnitButton
-- (that taints click/menu paths). Covers power-hold + chrome reveal formerly in
-- AttachPowerRevealOnShow.
local function AttachUnitFrameShowWatcher(frame)
	if not frame or frame.whoaShowWatcher then
		return
	end
	frame.whoaShowWatcher = true
	local watcher = CreateFrame("Frame", nil, UIParent)
	local wasShown = frame:IsShown()
	local lastGuid = nil
	local function Watcher_OnUpdate()
		if not frame.whoaShowWatcherActive then
			return
		end
		local unit = frame.unit
		local exists = unit and UnitExists(unit)
		local shown = frame:IsShown()
		local shownChanged = shown ~= wasShown
		-- Mainline: UnitGUID is often secret in instances — never compare. Shown-only.
		-- Classic: GUID swap detects ToT/ToF identity changes while the pin stays shown.
		local guidChanged = false
		if not (WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues()) then
			local guid = exists and UnitGUID(unit) or nil
			if guid ~= lastGuid then
				guidChanged = true
				lastGuid = guid
			end
		elseif lastGuid ~= nil then
			lastGuid = nil
		end
		if shownChanged then
			wasShown = shown
			-- Mirror former OnHide HookScript: next Show must not inherit hold alpha 0.
			if not shown and (frame.kind == "target" or frame.kind == "focus") then
				frame.whoaTargetRevealHold = nil
				frame.whoaChromePainted = nil
				frame:SetAlpha(1)
			end
		end
		-- RegisterUnitWatch can show a frame after the unit-change event already ran.
		-- Also refresh when the token keeps the frame shown but the GUID swaps (ToT/ToF).
		if shown and (shownChanged or guidChanged) then
			-- Frame Show can precede TARGET_CHANGED; never reveal a stale power fill.
			local power = frame.Power
			if power and (power.whoaPowerHoldReveal or not power.whoaPowerPainted) then
				power.whoaPowerHoldReveal = true
				CloakUnitPowerBarForHold(power, frame)
			end
			if (frame.kind == "target" or frame.kind == "focus")
				and shownChanged
				and not frame.whoaChromePainted
			then
				HoldTargetFrameReveal(frame)
				if unit and exists and WhoaUF.ApplyTargetClassificationChrome then
					WhoaUF:ApplyTargetClassificationChrome(frame)
				end
			end
			WhoaUF:UpdateUnitFrame(frame)
		end
	end
	watcher.OnUpdate = Watcher_OnUpdate
	frame.whoaShowWatcherFrame = watcher
end

local function SyncUnitFrameShowWatcher(frame)
	local watcher = frame and frame.whoaShowWatcherFrame
	if not watcher then
		return
	end
	-- Must stay armed while Whoa is active even when hidden: RegisterUnitWatch
	-- show transitions are invisible if OnUpdate was cleared on Hide.
	local want = WhoaUF.db and WhoaUF.db.enabled and WhoaUF.runtimeActive ~= false
	if want then
		if not frame.whoaShowWatcherActive then
			watcher:SetScript("OnUpdate", watcher.OnUpdate)
			frame.whoaShowWatcherActive = true
		end
	elseif frame.whoaShowWatcherActive then
		watcher:SetScript("OnUpdate", nil)
		frame.whoaShowWatcherActive = false
	end
end

local function ReleaseUnitFrameShowWatcher(frame)
	local watcher = frame and frame.whoaShowWatcherFrame
	if not watcher then
		return
	end
	watcher:SetScript("OnUpdate", nil)
	frame.whoaShowWatcherActive = false
end

local function SetupSecureUnitButton(frame, unit)
	-- SecureUnitButton_OnLoad defaults to type2=menu + menu-function. An addon
	-- menu-function taints UnitPopup (SetPVP, FocusUnit, PetDismiss, …).
	-- togglemenu opens the popup from Blizzard SecureTemplates instead.
	SecureUnitButton_OnLoad(frame, unit)
	frame:SetAttribute("*type2", "togglemenu")
	frame:SetAttribute("menu-function", nil)
	if unit == "player" or unit == "target" or unit == "focus" then
		frame:SetToplevel(true)
	end
	if UnitFrame_OnEnter and UnitFrame_OnLeave then
		frame:SetScript("OnEnter", UnitFrame_OnEnter)
		frame:SetScript("OnLeave", UnitFrame_OnLeave)
	end
end
local function CreateBarFontString(parent, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	if justify then
		fs:SetJustifyH(justify)
	end
	if WhoaUF.ApplyStatusBarTextFont then
		WhoaUF:ApplyStatusBarTextFont(fs)
	end
	return fs
end

local function SetupTextStatusBar(bar, overlay, anchors, cvarLabel)
	-- Blizzard TextStatusBarMixin drives none / numeric / percent / both via statusText + statusTextDisplay.
	local texture
	if WhoaUF.GetStatusBarTexturePaths then
		texture = WhoaUF:GetStatusBarTexturePaths()
	end
	bar:SetStatusBarTexture(texture or "Interface\\TargetingFrame\\UI-StatusBar")
	-- TextStatusBar templates often default to a full fill — blank until Update* paints.
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar.currValue = nil
	bar.whoaFrequentMax = nil
	bar.textLockable = true
	bar.cvar = "statusText"
	bar.cvarLabel = cvarLabel
	bar.lockShow = bar.lockShow or 0
	bar.capNumericDisplay = true
	-- Keep Whoa in charge of Show/Hide; TextStatusBar must not hide bars when max is 0.
	bar.controlsShownState = false
	-- Motion only — EnableMouse would eat clicks meant for SecureUnitButton.
	if bar.EnableMouseMotion then
		bar:EnableMouseMotion(true)
	else
		bar:EnableMouse(false)
	end

	-- Anchors match PlayerFrame.xml / TargetFrame.xml textFrame strings.
	local center = CreateBarFontString(overlay)
	center:SetPoint("CENTER", overlay, "CENTER", anchors.centerX, anchors.centerY)

	local left = CreateBarFontString(overlay, "LEFT")
	left:SetPoint("LEFT", overlay, "LEFT", anchors.leftX, anchors.centerY)

	local right = CreateBarFontString(overlay, "RIGHT")
	right:SetPoint("RIGHT", overlay, "RIGHT", anchors.rightX, anchors.centerY)

	-- BOTH mode needs both or it falls back to "(n%) cur / max" on the center string.
	SetBarTextStrings(bar, center, left, right)
	if WhoaUF.InstallStatusBarText then
		WhoaUF:InstallStatusBarText(bar)
	end
	UpdateBarTextString(bar)
	-- Hover shows HP via lockShow; re-apply dead/ghost overlay after the bar enter handler.
	if bar.HookScript then
		bar:HookScript("OnEnter", function()
			local parent = bar:GetParent()
			if parent and parent.unit then
				local status = GetUnitLifeStatus(parent.unit)
				if status then
					ApplyUnitStatusOverlay(parent, status)
				end
			end
		end)
	end
	return bar
end

-- Mainline TextStatusBar OnLoad (InitializeTextStatusBar) registers PROXY_STATUS_TEXT
-- without an owner, advancing CallbackRegistry's shared owner-ID counter under Whoa
-- taint. Stock nameplate health bars run the same OnLoad inside OnNamePlateAdded,
-- read the tainted counter, and CompactUnitFrame_UpdateAll then fails secret compares.
-- Mainline builds the template by hand and keeps one owned PROXY_STATUS_TEXT refresh.
local USE_TEXT_STATUS_BAR_MIXIN = TextStatusBarMixin and TextStatusBarMixin.InitializeTextStatusBar and true or false
local mixinTextStatusBars = {}
local proxyStatusTextRegistered

local function OnTextStatusBarEvent(self, ...)
	self:TextStatusBarOnEvent(...)
end

local function OnTextStatusBarEnter(self)
	self:OnStatusBarEnter()
end

local function OnTextStatusBarLeave(self)
	self:OnStatusBarLeave()
end

local function OnTextStatusBarValueChanged(self)
	self:OnStatusBarValueChanged()
end

local function OnTextStatusBarMinMaxChanged(self, minValue, maxValue)
	self:OnStatusBarMinMaxChanged(minValue, maxValue)
end

local function RefreshMixinTextStatusBars()
	for i = 1, #mixinTextStatusBars do
		mixinTextStatusBars[i]:UpdateTextString()
	end
end

local function CreateTextStatusBar(parent, name)
	if not USE_TEXT_STATUS_BAR_MIXIN then
		return CreateFrame("StatusBar", name, parent, "TextStatusBar")
	end
	local bar = CreateFrame("StatusBar", name, parent)
	Mixin(bar, TextStatusBarMixin)
	bar:SetScript("OnEvent", OnTextStatusBarEvent)
	bar:SetScript("OnEnter", OnTextStatusBarEnter)
	bar:SetScript("OnLeave", OnTextStatusBarLeave)
	bar:SetScript("OnValueChanged", OnTextStatusBarValueChanged)
	bar:SetScript("OnMinMaxChanged", OnTextStatusBarMinMaxChanged)
	-- Template is enableMouseMotion only; Lua OnEnter must not start eating clicks.
	bar:SetMouseClickEnabled(false)
	bar:SetMouseMotionEnabled(true)
	bar:RegisterEvent("CVAR_UPDATE")
	bar.lockShow = 0
	bar.controlsShownState = true
	mixinTextStatusBars[#mixinTextStatusBars + 1] = bar
	if not proxyStatusTextRegistered then
		proxyStatusTextRegistered = true
		Settings.SetOnValueChangedCallback("PROXY_STATUS_TEXT", RefreshMixinTextStatusBars, mixinTextStatusBars)
	end
	return bar
end

function WhoaUF:CreateTextStatusBar(parent, name)
	return CreateTextStatusBar(parent, name)
end

local function CreateStatusBar(parent, name, width, height)
	local bar = CreateTextStatusBar(parent, name)
	bar:SetSize(width, height)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(1)
	bar:SetFrameLevel(parent:GetFrameLevel())
	return bar
end

local PLAYER_HEALTH_TEXT = { centerX = 34, centerY = -1, leftX = 94, rightX = -24 }
local PLAYER_POWER_TEXT = { centerX = 34, centerY = -12, leftX = 94, rightX = -24 }
local TARGET_HEALTH_TEXT = { centerX = -33, centerY = -1, leftX = 25, rightX = -93 }
local TARGET_POWER_TEXT = { centerX = -33, centerY = -12, leftX = 25, rightX = -93 }

-- Portrait combat feedback (CombatFeedback.lua). OnUpdate stays off SecureUnitButtons.
local function ArmCombatFeedbackPulse(frame)
	local pulse = frame and frame.combatFeedbackPulse
	if not pulse or pulse.whoaActive or not pulse.OnUpdate then
		return
	end
	pulse:SetScript("OnUpdate", pulse.OnUpdate)
	pulse.whoaActive = true
end

local function StopCombatFeedbackPulse(frame)
	local pulse = frame and frame.combatFeedbackPulse
	if not pulse or not pulse.whoaActive then
		return
	end
	pulse:SetScript("OnUpdate", nil)
	pulse.whoaActive = false
end

local function AttachCombatFeedback(frame, hitIndicator, fontHeight)
	if not frame or not hitIndicator or not CombatFeedback_Initialize then
		return
	end
	fontHeight = fontHeight or frame.combatFeedbackFontHeight or 30
	frame.combatFeedbackFontHeight = fontHeight
	CombatFeedback_Initialize(frame, hitIndicator, fontHeight)
	local pulse = frame.combatFeedbackPulse
	if not pulse then
		pulse = CreateFrame("Frame", nil, UIParent)
		frame.combatFeedbackPulse = pulse
	end
	local function Pulse_OnUpdate(_, elapsed)
		if not frame.feedbackText or not CombatFeedback_OnUpdate then
			return
		end
		CombatFeedback_OnUpdate(frame, elapsed)
		local feedbackText = frame.feedbackText
		if feedbackText and not feedbackText:IsShown() then
			StopCombatFeedbackPulse(frame)
		end
	end
	pulse.OnUpdate = Pulse_OnUpdate
end

-- Portrait combat text colors (Combat → Combat text colors).
-- Default matches Blizzard floating combat text over units:
--   white = auto-attack / Auto Shot, yellow = specials, orange = pet, green = heals.
-- School: COMBATLOG school spectrum (fire/frost/shadow/arcane/…).
local COMBAT_FEEDBACK_SCHOOL_COLOR = {
	[0x00] = { 1.00, 1.00, 1.00 }, -- none
	[0x01] = { 1.00, 1.00, 0.00 }, -- physical
	[0x02] = { 1.00, 0.90, 0.50 }, -- holy
	[0x04] = { 1.00, 0.50, 0.00 }, -- fire
	[0x08] = { 0.30, 1.00, 0.30 }, -- nature
	[0x10] = { 0.50, 1.00, 1.00 }, -- frost
	[0x20] = { 0.50, 0.50, 1.00 }, -- shadow
	[0x40] = { 1.00, 0.50, 1.00 }, -- arcane
}
local COMBAT_FEEDBACK_SINGLE_SCHOOLS = { 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40 }
local COMBAT_FEEDBACK_PHYSICAL_MASK = 0x01
if Enum and Enum.Damageclass and Enum.Damageclass.MaskPhysical then
	COMBAT_FEEDBACK_PHYSICAL_MASK = Enum.Damageclass.MaskPhysical
elseif SCHOOL_MASK_PHYSICAL then
	COMBAT_FEEDBACK_PHYSICAL_MASK = SCHOOL_MASK_PHYSICAL
end
-- Classic Auto Shot / Wand Shoot — treated as white auto-attacks in floating CT.
local COMBAT_FEEDBACK_AUTO_SHOT = 75
local COMBAT_FEEDBACK_WAND_SHOOT = 5019

local function UseCombatFeedbackSchoolColors()
	local db = WhoaUF and WhoaUF.db
	return db and db.combatFeedbackColors == "school"
end

-- Secret amounts (Mainline Midnight+): never Lua-compare under Whoa taint.
-- Untainted Blizzard can; we cannot call CombatFeedback_OnCombatEvent with secrets.
local function HasCombatFeedbackAmount(amount)
	if amount == nil then
		return false
	end
	if not WhoaUF:CanAccessValue(amount) then
		return true
	end
	return amount ~= 0
end

local function FormatCombatFeedbackAmount(amount)
	if amount == nil then
		return ""
	end
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(amount)
	end
	if WhoaUF.FormatStatusNumber then
		return WhoaUF:FormatStatusNumber(amount, false)
	end
	if WhoaUF:CanAccessValue(amount) then
		return tostring(amount)
	end
	return ""
end

local function IsPhysicalCombatSchool(school)
	if school == nil or not WhoaUF:CanAccessValue(school) then
		return true
	end
	if type(school) ~= "number" then
		return true
	end
	return school == COMBAT_FEEDBACK_PHYSICAL_MASK or school == 0x01
end

local function GetCombatFeedbackSchoolRGB(school)
	if school == nil or not WhoaUF:CanAccessValue(school) or type(school) ~= "number" then
		return 1, 1, 0
	end
	local color = COMBAT_FEEDBACK_SCHOOL_COLOR[school]
	if color then
		return color[1], color[2], color[3]
	end
	for i = 1, #COMBAT_FEEDBACK_SINGLE_SCHOOLS do
		local mask = COMBAT_FEEDBACK_SINGLE_SCHOOLS[i]
		if bit.band(school, mask) ~= 0 then
			color = COMBAT_FEEDBACK_SCHOOL_COLOR[mask]
			return color[1], color[2], color[3]
		end
	end
	return 1, 1, 0
end

local function CombatFeedbackFlagIs(flags, name)
	return flags ~= nil and WhoaUF:CanAccessValue(flags) and flags == name
end

-- Mirror Blizzard CombatFeedback_OnCombatEvent without secret Lua compares.
local function CombatFeedbackOnCombatEvent(frame, event, flags, amount, school)
	local feedbackText = frame and frame.feedbackText
	if not feedbackText then
		return
	end
	local fontHeight = frame.feedbackFontHeight or 30
	local text = ""
	local r, g, b = 1, 1, 1
	local feedbackTable = CombatFeedbackText

	if event == "IMMUNE" then
		fontHeight = fontHeight * 0.5
		text = feedbackTable and feedbackTable[event] or event
	elseif event == "WOUND" then
		if HasCombatFeedbackAmount(amount) then
			if CombatFeedbackFlagIs(flags, "CRITICAL") or CombatFeedbackFlagIs(flags, "CRUSHING") then
				fontHeight = fontHeight * 1.5
			elseif CombatFeedbackFlagIs(flags, "GLANCING") then
				fontHeight = fontHeight * 0.75
			end
			if not IsPhysicalCombatSchool(school) then
				r, g, b = 1, 1, 0
			end
			text = FormatCombatFeedbackAmount(amount)
			if CombatFeedbackFlagIs(flags, "BLOCK_REDUCED") and COMBAT_TEXT_BLOCK_REDUCED then
				-- Prefer SetFormattedText path below when amount may be secret.
				feedbackText:SetTextHeight(fontHeight)
				feedbackText:SetFormattedText(COMBAT_TEXT_BLOCK_REDUCED, text)
				feedbackText:SetTextColor(r, g, b)
				feedbackText:SetAlpha(0)
				feedbackText:Show()
				frame.feedbackStartTime = GetTime()
				return
			end
		elseif CombatFeedbackFlagIs(flags, "ABSORB") then
			fontHeight = fontHeight * 0.75
			text = feedbackTable and feedbackTable["ABSORB"] or ABSORB or "ABSORB"
		elseif CombatFeedbackFlagIs(flags, "BLOCK") then
			fontHeight = fontHeight * 0.75
			text = feedbackTable and feedbackTable["BLOCK"] or BLOCK or "BLOCK"
		elseif CombatFeedbackFlagIs(flags, "RESIST") then
			fontHeight = fontHeight * 0.75
			text = feedbackTable and feedbackTable["RESIST"] or RESIST or "RESIST"
		else
			text = feedbackTable and feedbackTable["MISS"] or MISS or "MISS"
		end
	elseif event == "BLOCK" then
		fontHeight = fontHeight * 0.75
		text = feedbackTable and feedbackTable[event] or event
	elseif event == "HEAL" then
		text = FormatCombatFeedbackAmount(amount)
		r, g, b = 0, 1, 0
		if CombatFeedbackFlagIs(flags, "CRITICAL") then
			fontHeight = fontHeight * 1.5
		end
	elseif event == "ENERGIZE" then
		text = FormatCombatFeedbackAmount(amount)
		r, g, b = 0.41, 0.8, 0.94
		if CombatFeedbackFlagIs(flags, "CRITICAL") then
			fontHeight = fontHeight * 1.5
		end
	else
		text = (feedbackTable and feedbackTable[event]) or event or ""
	end

	frame.feedbackStartTime = GetTime()
	feedbackText:SetTextHeight(fontHeight)
	feedbackText:SetText(text)
	feedbackText:SetTextColor(r, g, b)
	feedbackText:SetAlpha(0)
	feedbackText:Show()
end

-- kind: "auto" | "special" | "pet" | nil (nil ≈ incoming UNIT_COMBAT via school)
local function ApplyCombatFeedbackColors(frame, event, amount, school, kind)
	local hit = frame and frame.HitIndicator
	if not hit then
		return
	end
	if event == "HEAL" then
		hit:SetTextColor(0, 1, 0)
		return
	end
	if event ~= "WOUND" or not HasCombatFeedbackAmount(amount) then
		return
	end
	if UseCombatFeedbackSchoolColors() then
		hit:SetTextColor(GetCombatFeedbackSchoolRGB(school))
		return
	end
	if kind == "pet" then
		hit:SetTextColor(1, 0.5, 0)
	elseif kind == "special" then
		hit:SetTextColor(1, 1, 0)
	elseif kind == "auto" then
		hit:SetTextColor(1, 1, 1)
	elseif IsPhysicalCombatSchool(school) then
		-- Incoming UNIT_COMBAT: physical ≈ white, magic ≈ yellow.
		hit:SetTextColor(1, 1, 1)
	else
		hit:SetTextColor(1, 1, 0)
	end
end

local function FireCombatFeedback(frame, event, flags, amount, school, kind)
	if not frame or not frame.HitIndicator or not frame.feedbackText then
		return
	end
	CombatFeedbackOnCombatEvent(frame, event, flags, amount, school)
	ApplyCombatFeedbackColors(frame, event, amount, school, kind)
	ArmCombatFeedbackPulse(frame)
end

-- UNIT_COMBAT has no source: only use it for the player/vehicle portrait (what
-- happens to you). Target/focus numbers come from CLEU so we can require the
-- source to be the player, pet, or vehicle — not every hit on that unit.
local function DispatchCombatFeedback(unit, ...)
	if not unit then
		return
	end
	local player = frames.player
	if not player then
		return
	end
	if unit == "player" or unit == "vehicle" or unit == player.unit then
		FireCombatFeedback(player, ...)
	end
end

local COMBAT_FEEDBACK_CLEU_KEY = "combatFeedback"

local function IsFriendlyCombatSource(guid)
	if not guid or not WhoaUF:CanAccessValue(guid) then
		return false
	end
	local playerGuid = UnitGUID("player")
	local petGuid = UnitGUID("pet")
	local vehicleGuid = UnitGUID("vehicle")
	if WhoaUF:CanAccessValue(playerGuid) and guid == playerGuid then
		return true
	end
	if WhoaUF:CanAccessValue(petGuid) and guid == petGuid then
		return true
	end
	if WhoaUF:CanAccessValue(vehicleGuid) and guid == vehicleGuid then
		return true
	end
	return false
end

local function IsPetCombatSource(guid)
	if not guid or not WhoaUF:CanAccessValue(guid) then
		return false
	end
	local petGuid = UnitGUID("pet")
	return WhoaUF:CanAccessValue(petGuid) and guid == petGuid
end

local function OutgoingCombatFeedbackKind(sourceGUID, subevent, spellId)
	if IsPetCombatSource(sourceGUID) then
		return "pet"
	end
	if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
		return "auto"
	end
	if (subevent == "RANGE_DAMAGE" or subevent == "RANGE_MISSED")
		and WhoaUF:CanAccessValue(spellId)
		and (spellId == COMBAT_FEEDBACK_AUTO_SHOT or spellId == COMBAT_FEEDBACK_WAND_SHOOT)
	then
		return "auto"
	end
	return "special"
end

local function CombatFeedbackMissEvent(missType)
	if missType ~= nil and WhoaUF:CanAccessValue(missType) then
		if missType == "ABSORB" or missType == "BLOCK" or missType == "RESIST" then
			return "WOUND", missType
		end
		return missType, nil
	end
	return "MISS", nil
end

local function WoundFlags(critical, glancing, crushing)
	if WhoaUF:IsAccessibleTrue(critical) then
		return "CRITICAL"
	end
	if WhoaUF:IsAccessibleTrue(crushing) then
		return "CRUSHING"
	end
	if WhoaUF:IsAccessibleTrue(glancing) then
		return "GLANCING"
	end
	return nil
end

local function FireOutgoingCombatFeedback(destGUID, event, flags, amount, school, kind)
	if not destGUID or not WhoaUF:CanAccessValue(destGUID) then
		return
	end
	local targetGUID = UnitExists("target") and UnitGUID("target")
	local focusGUID = UnitExists("focus") and UnitGUID("focus")
	local targetOk = WhoaUF:CanAccessValue(targetGUID)
	local focusOk = WhoaUF:CanAccessValue(focusGUID)
	if targetOk and destGUID == targetGUID then
		FireCombatFeedback(frames.target, event, flags, amount, school, kind)
	end
	-- Same unit on both tokens: one portrait pulse is enough.
	if focusOk and destGUID == focusGUID and (not targetOk or focusGUID ~= targetGUID) then
		FireCombatFeedback(frames.focus, event, flags, amount, school, kind)
	end
end

local function OnCombatFeedbackCombatLog(_, subevent, sourceGUID, destGUID, p12, p13, p14, p15, p16, p17, p18, p19, p20, p21)
	if not IsFriendlyCombatSource(sourceGUID) then
		return
	end
	if subevent == "SWING_DAMAGE" then
		local kind = OutgoingCombatFeedbackKind(sourceGUID, subevent)
		FireOutgoingCombatFeedback(destGUID, "WOUND", WoundFlags(p18, p19, p20), p12, p14, kind)
		return
	end
	if subevent == "SPELL_DAMAGE"
		or subevent == "SPELL_PERIODIC_DAMAGE"
		or subevent == "RANGE_DAMAGE"
		or subevent == "DAMAGE_SHIELD"
	then
		local kind = OutgoingCombatFeedbackKind(sourceGUID, subevent, p12)
		FireOutgoingCombatFeedback(destGUID, "WOUND", WoundFlags(p21, nil, nil), p15, p17, kind)
		return
	end
	if subevent == "SWING_MISSED" then
		local kind = OutgoingCombatFeedbackKind(sourceGUID, subevent)
		local eventName, flags = CombatFeedbackMissEvent(p12)
		FireOutgoingCombatFeedback(destGUID, eventName, flags, 0, nil, kind)
		return
	end
	if subevent == "SPELL_MISSED"
		or subevent == "SPELL_PERIODIC_MISSED"
		or subevent == "RANGE_MISSED"
		or subevent == "DAMAGE_SHIELD_MISSED"
	then
		local kind = OutgoingCombatFeedbackKind(sourceGUID, subevent, p12)
		local eventName, flags = CombatFeedbackMissEvent(p15)
		FireOutgoingCombatFeedback(destGUID, eventName, flags, 0, nil, kind)
		return
	end
	if subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
		local healFlags = WhoaUF:IsAccessibleTrue(p18) and "CRITICAL" or nil
		FireOutgoingCombatFeedback(destGUID, "HEAL", healFlags, p15, nil, nil)
	end
end

local function SetCombatFeedbackRuntime(active)
	local timing = WhoaUF.Timing
	if not timing or not timing.SubscribeCombatLog then
		return
	end
	if active then
		timing:SubscribeCombatLog(COMBAT_FEEDBACK_CLEU_KEY, OnCombatFeedbackCombatLog)
	else
		timing:UnsubscribeCombatLog(COMBAT_FEEDBACK_CLEU_KEY)
	end
end

local function CreateUnitButton(name, template)
	if template then
		return CreateFrame("Button", name, UIParent, template)
	end
	return CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
end

function WhoaUF:UpdateBarTextString(bar)
	if not bar then
		return
	end
	local fn = UF.UpdateBarTextString
	if fn then
		fn(bar)
	elseif bar.UpdateTextString then
		bar:UpdateTextString()
	elseif TextStatusBar_UpdateTextString then
		TextStatusBar_UpdateTextString(bar)
	end
end

UF.GetTargetFrameTexture = GetTargetFrameTexture
UF.GetUnitLifeStatus = GetUnitLifeStatus
UF.ApplyUnitStatusOverlay = ApplyUnitStatusOverlay
UF.HidePowerBarText = HidePowerBarText
UF.SetUnitPowerBarVisible = SetUnitPowerBarVisible
UF.SetPowerBarShownForStatus = SetPowerBarShownForStatus
UF.SnapStatusBarValue = SnapStatusBarValue
UF.SetSecureMouseEnabled = SetSecureMouseEnabled
UF.FlushPendingSecureMouse = FlushPendingSecureMouse
UF.ClearUnitFrameVisuals = ClearUnitFrameVisuals
UF.SetAttackModeShown = SetAttackModeShown
UF.RefreshFocusFrames = RefreshFocusFrames
UF.ResetFrameHealthPaint = ResetFrameHealthPaint
UF.ResetFramePowerPaint = ResetFramePowerPaint
UF.ResetFrameChrome = ResetFrameChrome
UF.RevealFrameChrome = RevealFrameChrome
UF.HoldTargetFrameReveal = HoldTargetFrameReveal
UF.ReleaseTargetFrameReveal = ReleaseTargetFrameReveal
UF.ReleasePowerBarReveal = ReleasePowerBarReveal
UF.ResetFramePortrait = ResetFramePortrait
UF.UpdatePortrait = UpdatePortrait
UF.SetPortraitAlpha = SetPortraitAlpha
UF.SyncFrameUnitGuid = SyncFrameUnitGuid
UF.AttachUnitFrameShowWatcher = AttachUnitFrameShowWatcher
UF.SyncUnitFrameShowWatcher = SyncUnitFrameShowWatcher
UF.ReleaseUnitFrameShowWatcher = ReleaseUnitFrameShowWatcher
UF.SetupSecureUnitButton = SetupSecureUnitButton
UF.CreateBarFontString = CreateBarFontString
UF.SetupTextStatusBar = SetupTextStatusBar
UF.UpdateBarTextString = UpdateBarTextString
UF.CreateStatusBar = CreateStatusBar
UF.CreateTextStatusBar = CreateTextStatusBar
UF.ArmFrequentHealthBar = ArmFrequentHealthBar
UF.ArmFrequentPowerBar = ArmFrequentPowerBar
UF.AttachCombatFeedback = AttachCombatFeedback
UF.DispatchCombatFeedback = DispatchCombatFeedback
UF.SetCombatFeedbackRuntime = SetCombatFeedbackRuntime
UF.StopCombatFeedbackPulse = StopCombatFeedbackPulse
UF.CreateUnitButton = CreateUnitButton
UF.PLAYER_HEALTH_TEXT = PLAYER_HEALTH_TEXT
UF.PLAYER_POWER_TEXT = PLAYER_POWER_TEXT
UF.TARGET_HEALTH_TEXT = TARGET_HEALTH_TEXT
UF.TARGET_POWER_TEXT = TARGET_POWER_TEXT
