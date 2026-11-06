--[[
	Unit frame update pipeline: classification, health, power, identity, ToT, UpdateUnitFrame.
]]

local UF = WhoaUF._UF
local frames = UF.frames
local function UpdateClassification(frame)
	if frame.kind == "boss" then
		local path = WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("boss")
		if path and frame.FrameTexture then
			frame.FrameTexture:SetTexture(path)
		end
		return
	end
	if frame.kind ~= "target" and frame.kind ~= "focus" then
		return
	end

	-- Blizzard TargetFrame:Update() runs CheckClassification every refresh, not only
	-- when classification changes — whoa/thick bar geometry must re-snap for minus.
	if WhoaUF.ApplyTargetClassificationChrome then
		WhoaUF:ApplyTargetClassificationChrome(frame)
	end

	-- Power visibility follows life status; chrome path sets pauseUpdates for minus.
	local power = frame.Power
	if not power then
		return
	end
	local lifeStatus = UF.GetUnitLifeStatus(frame.unit)
	local lifeHidesPower = lifeStatus == "dead" or lifeStatus == "ghost" or lifeStatus == "offline"
	if frame.isMinus then
		power.pauseUpdates = true
		UF.SetUnitPowerBarVisible(frame, false)
	elseif lifeHidesPower then
		power.pauseUpdates = false
		UF.SetPowerBarShownForStatus(frame, false)
	else
		power.pauseUpdates = false
	end
end

local function UpdateHealth(frame, unit)
	local max = UnitHealthMax(unit)
	local cur = UnitHealth(unit)
	local bar = frame.Health
	bar.unit = unit
	local previous = bar.currValue
	local maxAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(max)
	local curAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(cur)

	-- Match Classic UnitFrameHealthBar_Update percentage + forceHideText rules.
	bar.showNumeric = false
	if GetClassicExpansionLevel and LE_EXPANSION_BURNING_CRUSADE
		and GetClassicExpansionLevel() <= LE_EXPANSION_BURNING_CRUSADE then
		bar.showPercentage = false
	end

	local lifeStatus = UF.GetUnitLifeStatus(unit)
	if lifeStatus then
		bar.forceHideText = true
	elseif maxAccessible and max == 0 then
		max = 1
		bar.forceHideText = true
	else
		bar.forceHideText = false
		-- Do NOT set showPercentage from ShouldKnowUnitHealth. Stock UI does that for
		-- period authenticity; Classic API still returns absolute HP for many NPCs.
		-- Enemy players stay max==100. Honor statusTextDisplay on the raw API values.
		-- Reference: Blizzard_UnitFrame/Classic/UnitFrame.lua UnitFrameHealthBar_Update
	end

	-- StatusBars accept secret values; never coalesce with `or 0`.
	-- Dirty SetValue without poking to max (that flashes a full bar).
	bar:SetMinMaxValues(0, max)
	bar.whoaFrequentMax = max
	if maxAccessible and curAccessible and max > 0 then
		if cur == 0 then
			bar:SetValue(max > 1 and 1 or 0)
		else
			bar:SetValue(0)
		end
	end
	bar:SetValue(cur)

	if WhoaUF.ApplyHealthBarColor then
		WhoaUF:ApplyHealthBarColor(bar, unit)
	elseif not WhoaUF:IsAccessibleTrue(UnitIsConnected(unit)) then
		bar:SetStatusBarColor(0.5, 0.5, 0.5)
	else
		bar:SetStatusBarColor(0, 1, 0)
	end

	UF.UpdateBarTextString(bar)

	-- Skip loss trail until after the first valid paint / on unit swap (reload first-target red flash).
	local unitChanged = bar.whoaHealthUnit ~= unit
	if unitChanged then
		bar.whoaHealthPainted = nil
		local loss = frame.AnimatedLossBar or (bar and bar.AnimatedLossBar)
		if loss and loss.CancelAnimation then
			loss:CancelAnimation()
		end
	end
	bar.whoaHealthUnit = unit
	local canAnimate = maxAccessible
		and curAccessible
		and previous ~= nil
		and WhoaUF:CanAccessValue(previous)
		and max > 0
	if WhoaUF.NotifyHealthBarAnimated and bar.whoaHealthPainted and not unitChanged and canAnimate then
		WhoaUF:NotifyHealthBarAnimated(frame, previous, cur)
	end
	if (not maxAccessible or max > 0) and not bar.forceHideText then
		bar.whoaHealthPainted = true
	end
	bar.currValue = cur
	if WhoaUF.UpdateHealPrediction then
		WhoaUF:UpdateHealPrediction(frame)
	end
end

local function UpdateNameBackground(frame, unit)
	if not frame.NameBackground then
		return
	end
	-- Tap grey is a status cue (Blizzard CheckFaction), independent of color options.
	if not WhoaUF:IsAccessibleTrue(UnitPlayerControlled(unit))
		and WhoaUF:IsAccessibleTrue(UnitIsTapDenied(unit))
	then
		frame.NameBackground:SetVertexColor(0.5, 0.5, 0.5)
		if frame.Portrait then
			frame.Portrait:SetVertexColor(0.5, 0.5, 0.5)
		end
		return
	end

	-- Match health-bar tint options (custom / class / reaction / Classic green).
	local r, g, b
	if WhoaUF.GetHealthBarColor then
		r, g, b = WhoaUF:GetHealthBarColor(unit)
	end
	if WhoaUF:CanAccessValue(r) and not r then
		local c = WhoaUF.ReactionColors and WhoaUF.ReactionColors.default
		r, g, b = c and c.r or 0, c and c.g or 1, c and c.b or 0
	end
	frame.NameBackground:SetVertexColor(r, g, b)
	-- Offline / dead / ghost portrait tint is owned by ApplyUnitStatusOverlay.
	if frame.Portrait
		and not (WhoaUF:IsAccessibleTrue(UnitIsPlayer(unit)) and not WhoaUF:IsAccessibleTrue(UnitIsConnected(unit)))
	then
		frame.Portrait:SetVertexColor(1, 1, 1)
	end
end

local function UpdatePower(frame, unit)
	local bar = frame.Power
	if not bar then
		return
	end
	-- Alpha: stock power bar stays hidden; portrait runic/rage fill owns the resource.
	if frame.kind == "player" and WhoaUF.IsDkAlphaPlayerArtActive and WhoaUF:IsDkAlphaPlayerArtActive(frame) then
		bar.pauseUpdates = true
		UF.SetUnitPowerBarVisible(frame, false)
		if WhoaUF.UpdateDkAlphaRunicPower then
			WhoaUF:UpdateDkAlphaRunicPower(frame)
		end
		return
	end
	if bar.pauseUpdates then
		return
	end

	local lifeStatus = UF.GetUnitLifeStatus(unit)
	if lifeStatus == "dead" or lifeStatus == "ghost" or lifeStatus == "offline" then
		bar.forceHideText = true
		if bar.TextString then
			bar.TextString:Hide()
		end
		if bar.LeftText then
			bar.LeftText:Hide()
		end
		if bar.RightText then
			bar.RightText:Hide()
		end
		return
	end
	bar.forceHideText = false

	-- Classic: UnitPowerType("target") can lag one frame on self-target (shows RAGE
	-- before RUNIC_POWER). Prefer "player" when GUID matches — UnitIsUnit can lag too.
	-- Reference: Blizzard_UnitFrame/Classic/UnitFrame.lua UnitFrameManaBar_UpdateType
	local powerUnit = unit
	local isPlayerPower = WhoaUF.UnitMatchesToken and WhoaUF:UnitMatchesToken(unit, "player")
	if not isPlayerPower and not WhoaUF.UnitMatchesToken and UnitIsUnit then
		isPlayerPower = WhoaUF:IsAccessibleTrue(UnitIsUnit(unit, "player"))
	end
	if isPlayerPower then
		powerUnit = "player"
	end

	local unitChanged = bar.whoaPowerUnit ~= unit
	if unitChanged then
		bar.whoaPowerPainted = nil
		if bar.FeedbackFrame and bar.FeedbackFrame.StopFeedbackAnim then
			bar.FeedbackFrame:StopFeedbackAnim()
		end
		local full = bar.FullPowerFrame
		if full and full.RemoveAnims then
			full:RemoveAnims()
		end
	end
	bar.unit = unit

	-- UpdateType first (Blizzard ManaBar_Update), then max/cur from bar.powerType.
	local powerType, powerToken, altR, altG, altB = UnitPowerType(powerUnit)
	local tokenInfo = WhoaUF:GetPowerBarColor(powerToken, powerType)
	-- GetPowerBarColor falls back to MANA; treat unknown token as missing for player lag gate.
	local hasToken = powerToken ~= nil
		and WhoaUF:CanAccessValue(powerToken)
		and WhoaUF.PowerBarColor
		and WhoaUF.PowerBarColor[powerToken]

	-- Self-target: token can lag (RAGE index before RUNIC_POWER). Stay hidden until the
	-- real token arrives — never color by numeric powerType alone on the player.
	if not hasToken and not altR then
		if isPlayerPower then
			UF.SetUnitPowerBarVisible(frame, false)
			return
		end
		-- NPCs may only expose a type index / alt colors (Blizzard UpdateType fallback).
	end

	bar.whoaPowerUnit = unit

	local typeChanged = WhoaUF.ValuesDiffer and WhoaUF:ValuesDiffer(bar.powerType, powerType)
		or (not WhoaUF.ValuesDiffer and bar.powerType ~= powerType)
	if typeChanged then
		bar.powerType = WhoaUF:CanAccessValue(powerType) and powerType or bar.powerType
		bar.powerToken = WhoaUF:CanAccessValue(powerToken) and powerToken or nil
		local full = bar.FullPowerFrame
		if full and full.RemoveAnims then
			full:RemoveAnims()
		end
		bar.currValue = UnitPower(powerUnit, powerType)
	else
		bar.powerToken = WhoaUF:CanAccessValue(powerToken) and powerToken or bar.powerToken
	end

	local max = UnitPowerMax(powerUnit, bar.powerType)
	local cur = UnitPower(powerUnit, bar.powerType)
	local maxAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(max)

	-- NPCs / no resource (PetFrame rule). Hide without ever revealing a wrong type.
	if maxAccessible and max == 0 then
		bar.pauseUpdates = true
		bar.forceHideText = true
		bar.whoaPowerPainted = nil
		bar.currValue = nil
		bar.whoaFrequentMax = 0
		bar.whoaPowerUnit = nil
		if bar.FeedbackFrame and bar.FeedbackFrame.StopFeedbackAnim then
			bar.FeedbackFrame:StopFeedbackAnim()
		end
		UF.SetUnitPowerBarVisible(frame, false)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		return
	end

	bar.pauseUpdates = false
	local previous = bar.currValue
	bar.showPercentage = false
	local tokenOk = powerToken ~= nil and WhoaUF:CanAccessValue(powerToken)
	if tokenOk and (powerToken == "RAGE" or powerToken == "RUNIC_POWER") then
		bar.zeroText = ""
	else
		bar.zeroText = nil
	end

	local prefix = tokenOk and _G[powerToken] or nil
	if bar.SetBarTextPrefix then
		bar:SetBarTextPrefix(prefix)
	else
		bar.prefix = prefix
	end

	-- Blizzard UpdateType: color by token first; alt RGB next; else type index / MANA.
	-- Always pass alpha 1 — a prior transparent reset must not stick on 3-arg SetStatusBarColor.
	if not bar.lockColor then
		if hasToken and tokenInfo then
			bar:SetStatusBarColor(tokenInfo.r, tokenInfo.g, tokenInfo.b, 1)
		elseif altR then
			bar:SetStatusBarColor(altR, altG, altB, 1)
		else
			local info = WhoaUF:GetPowerBarColor(powerToken, powerType)
			bar:SetStatusBarColor(info.r, info.g, info.b, 1)
		end
	end

	bar:SetMinMaxValues(0, max)
	bar.whoaFrequentMax = max
	if not WhoaUF:IsAccessibleTrue(UnitIsConnected(unit)) then
		cur = max
		if not bar.lockColor then
			bar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
		end
	end
	bar:SetValue(cur)
	bar.currValue = cur
	bar.forceUpdate = true
	if not maxAccessible or max > 0 then
		bar.whoaPowerPainted = true
	end

	-- Player/pet never use the retarget hold.
	if frame.kind == "player" or frame.kind == "pet" or frame.kind == "party" then
		bar.whoaPowerHoldReveal = nil
	end

	-- Hold: paint at alpha 0 (bar shown) so custom textures accept SetValue.
	if bar.whoaPowerHoldReveal then
		UF.SetUnitPowerBarVisible(frame, true)
		return
	end

	-- Blizzard CheckClassification shows the manabar only after UnitFrame_Update painted it.
	UF.SetUnitPowerBarVisible(frame, true)
	UF.UpdateBarTextString(bar)

	local curAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(cur)
	local canAnimate = not unitChanged
		and not typeChanged
		and previous ~= nil
		and maxAccessible
		and curAccessible
		and WhoaUF:CanAccessValue(previous)
		and (not maxAccessible or max > 0)
		and previous ~= cur
	if WhoaUF.NotifyPowerBarAnimated then
		if canAnimate then
			WhoaUF:NotifyPowerBarAnimated(frame, previous, cur, max)
		else
			WhoaUF:NotifyPowerBarAnimated(frame, nil, cur, max)
		end
	end
	if frame.kind == "player" and WhoaUF.LayoutDkBlizzconPower and WhoaUF.IsDkBlizzconPlayerArtActive and WhoaUF:IsDkBlizzconPlayerArtActive(frame) then
		WhoaUF:LayoutDkBlizzconPower(frame)
	end
end

local function UpdateIdentity(frame, unit)
	if WhoaUF.ShouldDisplayUnitName and not WhoaUF:ShouldDisplayUnitName(frame) then
		frame.Name:SetText("")
		frame.Name:Hide()
	else
		frame.Name:Show()
		frame.Name:SetText(UnitName(unit) or "")
	end
	if WhoaUF.SyncNameBackgroundForFrame then
		WhoaUF:SyncNameBackgroundForFrame(frame)
	end

	local level = UnitLevel(unit)
	if frame.kind == "target" or frame.kind == "focus" or frame.kind == "boss" then
		if UnitIsCorpse and WhoaUF:IsAccessibleTrue(UnitIsCorpse(unit)) then
			frame.Level:Hide()
			frame.Level:SetText("")
			frame.HighLevelTexture:Show()
		elseif WhoaUF:CanAccessValue(level) and level > 0 then
			frame.Level:SetText(tostring(level))
			if WhoaUF:IsAccessibleTrue(UnitCanAttack("player", unit)) and GetCreatureDifficultyColor then
				local color = GetCreatureDifficultyColor(level)
				frame.Level:SetVertexColor(color.r, color.g, color.b)
			elseif UNIT_LEVEL_NON_ATTACKABLE then
				frame.Level:SetVertexColor(
					UNIT_LEVEL_NON_ATTACKABLE.r,
					UNIT_LEVEL_NON_ATTACKABLE.g,
					UNIT_LEVEL_NON_ATTACKABLE.b
				)
			else
				frame.Level:SetVertexColor(1, 0.82, 0)
			end
			frame.Level:Show()
			frame.HighLevelTexture:Hide()
		else
			frame.Level:Hide()
			frame.Level:SetText("")
			frame.HighLevelTexture:Show()
		end
	else
		if level and level > 0 then
			frame.Level:SetText(tostring(level))
		else
			frame.Level:SetText("")
		end
	end
end

-- Secure unit swap (PlayerFrame UnitFrame_SetUnit). Defer attribute writes in combat.
-- Track pending frames so REGEN can SetAttribute even if vehicle-art apply is skipped.
local pendingSecureUnitFrames = {}

local function SetSecureUnit(frame, unit)
	if not frame then
		return
	end
	frame.unit = unit
	if frame.Health then
		frame.Health.unit = unit
	end
	if frame.Power then
		frame.Power.unit = unit
	end
	if frame.AnimatedLossBar then
		frame.AnimatedLossBar.unit = unit
	elseif frame.Health and frame.Health.AnimatedLossBar then
		frame.Health.AnimatedLossBar.unit = unit
	end
	if frame.threatIndicator then
		frame.threatIndicator.unit = unit
	end
	if InCombatLockdown() then
		frame._pendingSecureUnit = unit
		pendingSecureUnitFrames[frame] = true
		UF.pendingVehicleArtApply = true
		return
	end
	frame._pendingSecureUnit = nil
	pendingSecureUnitFrames[frame] = nil
	frame:SetAttribute("unit", unit)
end

local function FlushPendingSecureUnits()
	if InCombatLockdown() then
		return
	end
	for frame in pairs(pendingSecureUnitFrames) do
		local unit = frame and frame._pendingSecureUnit
		if unit and frame.SetAttribute then
			frame:SetAttribute("unit", unit)
		end
		if frame then
			frame._pendingSecureUnit = nil
		end
		pendingSecureUnitFrames[frame] = nil
	end
end
local function UpdatePlayerStatus(frame)
	local status = frame.StatusTexture
	local rest = frame.RestIcon
	local attack = frame.AttackIcon
	local attackBg = frame.AttackBackground
	local statusGlow = frame.StatusGlow
	local restGlow = frame.RestGlow
	local attackGlow = frame.AttackGlow
	if not status then
		return
	end

	local function SetStatusPulse(active)
		local pulse = frame.statusPulse
		if not pulse then
			return
		end
		if active then
			if not pulse.whoaActive then
				pulse:SetScript("OnUpdate", pulse.OnUpdate)
				pulse.whoaActive = true
			end
		elseif pulse.whoaActive then
			pulse:SetScript("OnUpdate", nil)
			pulse.whoaActive = false
		end
	end

	-- Vehicle UI hides resting/combat status chrome (PlayerFrame_UpdateStatus).
	if WhoaUF.PlayerVehicleSeatActive and WhoaUF:PlayerVehicleSeatActive() then
		status:Hide()
		rest:Hide()
		attack:Hide()
		attackBg:Hide()
		if statusGlow then
			statusGlow:Hide()
		end
		if restGlow then
			restGlow:Hide()
		end
		if attackGlow then
			attackGlow:Hide()
		end
		SetStatusPulse(false)
		return
	end

	if IsResting and IsResting() then
		status:SetVertexColor(1.0, 0.88, 0.25, 1.0)
		status:Show()
		rest:Show()
		attack:Hide()
		attackBg:Hide()
		if restGlow then
			restGlow:Show()
		end
		if attackGlow then
			attackGlow:Hide()
		end
		if statusGlow then
			statusGlow:Show()
		end
		SetStatusPulse(true)
	elseif frame.inCombat then
		status:SetVertexColor(1.0, 0.0, 0.0, 1.0)
		status:Show()
		attack:Show()
		rest:Hide()
		attackBg:Show()
		if restGlow then
			restGlow:Hide()
		end
		if attackGlow then
			attackGlow:Show()
		end
		if statusGlow then
			statusGlow:Show()
		end
		SetStatusPulse(true)
	elseif frame.onHateList then
		attack:Show()
		rest:Hide()
		status:Hide()
		attackBg:Hide()
		if statusGlow then
			statusGlow:Hide()
		end
		if restGlow then
			restGlow:Hide()
		end
		if attackGlow then
			attackGlow:Hide()
		end
		SetStatusPulse(false)
	else
		status:Hide()
		rest:Hide()
		attack:Hide()
		attackBg:Hide()
		if statusGlow then
			statusGlow:Hide()
		end
		if restGlow then
			restGlow:Hide()
		end
		if attackGlow then
			attackGlow:Hide()
		end
		SetStatusPulse(false)
	end

	if WhoaUF.LayoutPlayerCombatGlow then
		WhoaUF:LayoutPlayerCombatGlow(frame)
	end
end

local function UpdatePvPIcon(frame, unit)
	local icon = frame.PvPIcon
	if not icon then
		return
	end

	local ffa = UF.GetTargetFrameTexture("pvpFFA")
	local alliance = UF.GetTargetFrameTexture("pvpAlliance")
	local horde = UF.GetTargetFrameTexture("pvpHorde")

	-- Prefer Whoa Media\shared\{light|dark}\UI-PVP-* when flags are readable.
	local factionGroup = UnitFactionGroup(unit)
	local factionOk = factionGroup ~= nil and WhoaUF:CanAccessValue(factionGroup)
	local ffaFlag = UnitIsPVPFreeForAll and UnitIsPVPFreeForAll(unit)
	local pvpFlag = UnitIsPVP and UnitIsPVP(unit)
	if WhoaUF:CanAccessValue(ffaFlag) and WhoaUF:CanAccessValue(pvpFlag) and (factionOk or WhoaUF:IsAccessibleTrue(ffaFlag)) then
		if WhoaUF:IsAccessibleTrue(ffaFlag) then
			icon:SetTexture(ffa)
			icon:Show()
			return
		elseif factionOk
			and factionGroup ~= "Neutral"
			and WhoaUF:IsAccessibleTrue(pvpFlag)
		then
			local path = (factionGroup == "Alliance") and alliance
				or (factionGroup == "Horde") and horde
				or nil
			if path then
				icon:SetTexture(path)
				icon:Show()
				return
			end
		else
			icon:Hide()
			return
		end
	end

	-- Secret identity / flags (12.1.5+): UnitFrameUtil. Live retail: helper returns false → hide.
	if WhoaUF.TryUpdateUnitPvPIndicator
		and WhoaUF:TryUpdateUnitPvPIndicator(icon, unit, unit == "player", ffa, alliance, horde)
	then
		return
	end
	icon:Hide()
end

local function UpdateLeaderIcon(frame, unit)
	local icon = frame.LeaderIcon
	if not icon then
		return
	end
	if WhoaUF.GetLeaderIconTexture then
		icon:SetTexture(WhoaUF:GetLeaderIconTexture())
	end
	if WhoaUF:IsAccessibleTrue(UnitIsGroupLeader and UnitIsGroupLeader(unit)) then
		icon:Show()
	else
		icon:Hide()
	end
end

-- Player raid subgroup indicator (Media\shared\{light|dark}\UI-GroupIndicator.blp).
-- Tune here; texture path is WhoaUF:GetGroupIndicatorTexture().
local GROUP_INDICATOR_W = 64
local GROUP_INDICATOR_H = 32
-- Container offset: LEFT of indicator → RIGHT of player Health.
local GROUP_INDICATOR_CONTAINER_X = -26
local GROUP_INDICATOR_CONTAINER_Y = -2.5
-- G# text offset: CENTER of indicator.
local GROUP_INDICATOR_TEXT_X = 6
local GROUP_INDICATOR_TEXT_Y = 2

local function LayoutGroupIndicator(frame)
	local indicator = frame and frame.GroupIndicator
	if not indicator then
		return
	end
	-- Keep strata: threat flash (frame BACKGROUND) < indicator < Overlay FrameTexture (+3).
	if indicator:GetParent() ~= frame then
		indicator:SetParent(frame)
	end
	indicator:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
	local health = frame.Health
	indicator:SetSize(GROUP_INDICATOR_W, GROUP_INDICATOR_H)
	indicator:ClearAllPoints()
	if health then
		indicator:SetPoint("LEFT", health, "RIGHT", GROUP_INDICATOR_CONTAINER_X, GROUP_INDICATOR_CONTAINER_Y)
	else
		indicator:SetPoint("TOPLEFT", frame, "TOPLEFT", 209, -41)
	end
	if indicator.Text then
		indicator.Text:ClearAllPoints()
		indicator.Text:SetPoint("CENTER", GROUP_INDICATOR_TEXT_X, GROUP_INDICATOR_TEXT_Y)
		if WhoaUF.ApplyStatusBarTextFont then
			WhoaUF:ApplyStatusBarTextFont(indicator.Text)
		end
		if NORMAL_FONT_COLOR then
			indicator.Text:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
		else
			indicator.Text:SetTextColor(1, 0.82, 0)
		end
	end
	if indicator.Texture and WhoaUF.GetGroupIndicatorTexture then
		indicator.Texture:SetTexture(WhoaUF:GetGroupIndicatorTexture())
	end
end

local function UpdateGroupIndicator(frame)
	local indicator = frame and frame.GroupIndicator
	if not indicator then
		return
	end
	LayoutGroupIndicator(frame)

	local force = WhoaUF.IsForceShowGroupIndicator and WhoaUF:IsForceShowGroupIndicator()
	local subgroup
	if IsInRaid and IsInRaid() and GetRaidRosterInfo and GetNumGroupMembers then
		local numGroupMembers = GetNumGroupMembers() or 0
		local maxMembers = MAX_RAID_MEMBERS or 40
		local playerName = UnitName("player")
		for i = 1, maxMembers do
			if i <= numGroupMembers then
				local name, _, sub = GetRaidRosterInfo(i)
				if name == playerName then
					subgroup = sub
					break
				end
			end
		end
	end

	if not force and not subgroup then
		indicator:Hide()
		return
	end

	if indicator.Text then
		-- Force-show preview uses max raid groups (NUM_RAID_GROUPS) so text fits G8.
		local maxGroups = NUM_RAID_GROUPS or MAX_RAID_GROUPS or 8
		indicator.Text:SetText("G" .. (subgroup or maxGroups))
		indicator.Text:Show()
	end
	if indicator.Texture then
		indicator.Texture:Show()
	end
	indicator:Show()
end

local function UpdateRaidTargetIcon(frame, unit)
	local icon = frame.RaidTargetIcon
	if not icon then
		return
	end
	local index = GetRaidTargetIndex and GetRaidTargetIndex(unit)
	-- Mainline may return a secret index (no compares). Non-nil means marked;
	-- SetRaidTargetIconTexture → SetSpriteSheetCell accepts the secret.
	local marked
	if index == nil then
		marked = false
	elseif not WhoaUF:CanAccessValue(index) then
		marked = true
	else
		marked = index > 0
	end
	if marked then
		if SetRaidTargetIconTexture then
			SetRaidTargetIconTexture(icon, index)
		end
		icon:Show()
	else
		icon:Hide()
	end
end

local function UpdateDeadText(frame, unit)
	UF.ApplyUnitStatusOverlay(frame, UF.GetUnitLifeStatus(unit))
end

local function UpdateToTAttackMode(frame, unit)
	unit = unit or frame.unit
	local inCombat = unit and UnitExists(unit) and UnitAffectingCombat(unit)
	if UF.SetAttackModeShown then
		UF.SetAttackModeShown(frame, inCombat and true or false)
	end
end

local function UpdateToTFrame(frame)
	local unit = frame.unit
	local shouldShow = true
	if WhoaUF.ShouldShowToTFrame then
		shouldShow = WhoaUF:ShouldShowToTFrame(frame)
	elseif not UnitExists(unit) then
		shouldShow = false
	end

	-- RegisterUnitWatch only tracks token existence. Parent-dead / self-target /
	-- CVar-off must hide the pin without emptying it under combat lockdown
	-- (SetShown is blocked; alpha is combat-safe).
	if not shouldShow then
		if frame:GetAlpha() ~= 0 then
			frame:SetAlpha(0)
		end
		UF.SetSecureMouseEnabled(frame, false)
		if UF.SetAttackModeShown then
			UF.SetAttackModeShown(frame, false)
		end
		local parent = frame:GetParent()
		if parent then
			local hadToT = parent.haveToT
			if WhoaUF.SyncHaveToT then
				WhoaUF:SyncHaveToT(parent)
			else
				parent.haveToT = nil
			end
			if parent.haveToT ~= hadToT then
				if parent.spellbar and WhoaUF.AdjustSpellBar then
					WhoaUF:AdjustSpellBar(parent)
				end
				if WhoaUF.UpdateUnitAuras then
					WhoaUF:UpdateUnitAuras(parent)
				end
			end
		end
		-- Only wipe once the secure watch has actually hidden the frame.
		-- Clearing while still shown (watch lag / parent-dead) empties the pin.
		if not UnitExists(unit) and not frame:IsShown() then
			UF.ClearUnitFrameVisuals(frame)
		end
		return
	end

	if frame:GetAlpha() ~= 1 then
		frame:SetAlpha(1)
	end
	UF.SetSecureMouseEnabled(frame, true)

	frame.Name:SetText(UnitName(unit) or "")
	UF.UpdatePortrait(frame, unit)

	local max = UnitHealthMax(unit)
	local cur = UnitHealth(unit)
	local maxAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(max)
	if not maxAccessible or max > 0 then
		frame.Health:SetMinMaxValues(0, max)
		frame.Health:SetValue(cur)
	else
		frame.Health:SetMinMaxValues(0, 1)
		frame.Health:SetValue(0)
	end
	if WhoaUF.ApplyHealthBarColor then
		WhoaUF:ApplyHealthBarColor(frame.Health, unit)
	end
	if WhoaUF.UpdateHealPrediction then
		WhoaUF:UpdateHealPrediction(frame)
	end

	local status = UF.GetUnitLifeStatus(unit)

	local powerUnit = unit
	if WhoaUF.UnitMatchesToken and WhoaUF:UnitMatchesToken(unit, "player") then
		powerUnit = "player"
	elseif not WhoaUF.UnitMatchesToken and UnitIsUnit and WhoaUF:IsAccessibleTrue(UnitIsUnit(unit, "player")) then
		powerUnit = "player"
	end
	local powerType, powerToken, altR, altG, altB = UnitPowerType(powerUnit)
	local pmax = UnitPowerMax(powerUnit, powerType)
	local pcur = UnitPower(powerUnit, powerType)
	local pmaxAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(pmax)
	if pmaxAccessible and pmax == 0 then
		frame.Power.whoaPowerPainted = nil
		frame.Power.currValue = nil
		UF.SetUnitPowerBarVisible(frame, false)
		frame.Power:SetMinMaxValues(0, 1)
		frame.Power:SetValue(0)
	else
		local info = WhoaUF:GetPowerBarColor(powerToken, powerType)
		local tokenOk = powerToken ~= nil
			and WhoaUF:CanAccessValue(powerToken)
			and WhoaUF.PowerBarColor
			and WhoaUF.PowerBarColor[powerToken]
		if not tokenOk and altR then
			frame.Power:SetStatusBarColor(altR, altG, altB, 1)
		else
			frame.Power:SetStatusBarColor(info.r, info.g, info.b, 1)
		end
		frame.Power:SetMinMaxValues(0, pmax)
		frame.Power.currValue = pcur
		frame.Power.whoaPowerPainted = true
		if not status or status == "unconscious" then
			UF.SetUnitPowerBarVisible(frame, true)
			if frame.Power:IsShown() then
				if UF.SnapStatusBarValue then
					UF.SnapStatusBarValue(frame.Power, pcur)
				else
					frame.Power:SetValue(pcur)
				end
			else
				frame.Power:SetValue(pcur)
			end
		else
			frame.Power:SetValue(pcur)
			UF.SetUnitPowerBarVisible(frame, false)
		end
	end

	if status then
		frame.Background:SetAlpha(0.9)
	else
		frame.Background:SetAlpha(1)
	end
	UF.ApplyUnitStatusOverlay(frame, status)

	-- Low-HP portrait tint uses cur/max; skipped on Mainline (secret values).
	if not status then
		if WhoaUF:IsAccessibleTrue(UnitIsPlayer(unit))
			and not (WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues())
		then
			local curAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(cur)
			if maxAccessible and curAccessible and max > 0 then
				local pct = cur / max
				if pct > 0 and pct <= 0.2 then
					frame.Portrait:SetVertexColor(1, 0, 0)
				else
					frame.Portrait:SetVertexColor(1, 1, 1)
				end
			else
				frame.Portrait:SetVertexColor(1, 1, 1)
			end
		elseif frame.Portrait then
			frame.Portrait:SetVertexColor(1, 1, 1)
		end
	end

	UpdateToTAttackMode(frame, unit)

	-- Match TargetOfTargetMixin:Update — keep parent castbar clear of ToT.
	local parent = frame:GetParent()
	if parent and parent.spellbar then
		local hadToT = parent.haveToT
		if WhoaUF.SyncHaveToT then
			WhoaUF:SyncHaveToT(parent)
		else
			parent.haveToT = frame:IsShown() and true or nil
		end
		if parent.haveToT ~= hadToT and WhoaUF.AdjustSpellBar then
			WhoaUF:AdjustSpellBar(parent)
		end
	end
end

function WhoaUF:UpdateUnitFrame(frame)
	if not frame then
		return
	end
	if not (self.db and self.db.enabled) then
		return
	end

	local unit = frame.unit
	if not UnitExists(unit) then
		local previewUnit = self.GetEditModePreviewUnit and self:GetEditModePreviewUnit(frame)
		if previewUnit and UnitExists(previewUnit) then
			unit = previewUnit
		end
	end
	if not UnitExists(unit) then
		-- Stale vehicle token after quest/scripted seat loss: restore player art
		-- instead of wiping the frame (ClearUnitFrameVisuals).
		if frame.kind == "player" and (unit == "vehicle" or frame.state == "vehicle") then
			local seatActive = self.PlayerVehicleSeatActive and self:PlayerVehicleSeatActive()
			if not seatActive then
				if InCombatLockdown() then
					UF.pendingVehicleArtApply = true
					if self.RestorePlayerVehicleVisualsOnly then
						self:RestorePlayerVehicleVisualsOnly()
					end
				elseif self.PlayerFrameToPlayerArt then
					self:PlayerFrameToPlayerArt()
				end
				return
			end
		end
		-- Pet is SecureUnitButton driven by ApplyPetFrameVisibility (not unit watch).
		-- Death/dismiss can clear UnitExists while combat lockdown keeps the frame shown;
		-- wiping visuals here empties the pet pin until REGEN.
		if frame.kind == "pet" then
			if self.ApplyPetFrameVisibility then
				self:ApplyPetFrameVisibility()
			end
			return
		end
		-- ToT/ToF: RegisterUnitWatch can lag Hide by a frame. Clearing while still
		-- shown empties the pin; UpdateToTFrame owns clear-after-hide + parent-dead alpha.
		if frame.kind == "tot" or frame.kind == "focustot" then
			UpdateToTFrame(frame)
			if self.UpdateToTDebuffs then
				self:UpdateToTDebuffs(frame)
			end
			return
		end
		UF.ClearUnitFrameVisuals(frame)
		if frame.Health then
			frame.Health.currValue = nil
			frame.Health.whoaHealthUnit = nil
			frame.Health.whoaHealthPainted = nil
		end
		if frame.Power then
			frame.Power.currValue = nil
			frame.Power.whoaPowerUnit = nil
			frame.Power.whoaPowerPainted = nil
		end
		if self.ClearStatusBarAnims then
			self:ClearStatusBarAnims(frame)
		end
		if self.UpdateHealPrediction then
			self:UpdateHealPrediction(frame)
		end
		-- Visibility for target/focus/ToT is handled by RegisterUnitWatch (combat-safe).
		if frame.threatIndicator then
			frame.threatIndicator:Hide()
			if frame.threatNumericIndicator then
				frame.threatNumericIndicator:Hide()
			end
			if self.SyncThreatPoll then
				self:SyncThreatPoll(frame)
			end
		end
		-- Clear aura buttons + idle GC (orphan aura/text churn from the last unit).
		if self.UpdateUnitAuras then
			self:UpdateUnitAuras(frame)
		end
		if self.UpdateToTDebuffs then
			self:UpdateToTDebuffs(frame)
		end
		if self.SyncToTAuraWatcher then
			self:SyncToTAuraWatcher(frame)
		end
		if frame.HitIndicator then
			frame.HitIndicator:Hide()
		end
		if UF.StopCombatFeedbackPulse then
			UF.StopCombatFeedbackPulse(frame)
		end
		UF.SyncUnitFrameShowWatcher(frame)
		return
	end

	UF.SyncUnitFrameShowWatcher(frame)

	UF.SyncFrameUnitGuid(frame, unit)

	if frame.kind == "party" then
		if self.UpdatePartyMemberFrame then
			self:UpdatePartyMemberFrame(frame)
		end
		if self.UpdateFrameThreat then
			self:UpdateFrameThreat(frame)
		end
		return
	end

	if frame.kind == "raidmember" or frame.kind == "raidgroup" then
		if self.UpdateRaidGroupFrames then
			self:UpdateRaidGroupFrames()
		end
		return
	end

	if frame.kind == "pet" then
		if self.UpdatePetFrame then
			self:UpdatePetFrame()
		end
		return
	end

	if frame.kind == "tot" or frame.kind == "focustot" then
		UpdateToTFrame(frame)
		if self.UpdateToTDebuffs then
			self:UpdateToTDebuffs(frame)
		end
		if self.UpdateFrameThreat then
			self:UpdateFrameThreat(frame)
		end
		return
	end

	-- Classification chrome before identity/bars so the border is not a late pop-in.
	UpdateClassification(frame)
	UpdateIdentity(frame, unit)
	-- Portrait first so GUID resets cannot wipe tap/name-bg tint set below.
	UF.UpdatePortrait(frame, unit)
	UpdateNameBackground(frame, unit)
	UpdateHealth(frame, unit)
	UF.UpdatePower(frame, unit)
	UF.UpdatePvPIcon(frame, unit)
	UF.UpdateLeaderIcon(frame, unit)
	UF.UpdateRaidTargetIcon(frame, unit)
	UpdateDeadText(frame, unit)
	if frame.kind == "player" then
		UF.UpdatePlayerStatus(frame)
		UF.UpdateGroupIndicator(frame)
	end
	if self.UpdateUnitAuras then
		self:UpdateUnitAuras(frame)
	end
	if self.SyncToTAuraWatcher then
		self:SyncToTAuraWatcher(frame)
	end
	if self.UpdateFrameThreat then
		self:UpdateFrameThreat(frame)
	end
end

function WhoaUF:RefreshAllUnitFrames()
	for _, frame in pairs(frames) do
		self:UpdateUnitFrame(frame)
	end
end

--- Health + name-background + absorb tint only (no full frame rebuild).
--- Used when faction / PvP / flags / connection change UnitSelectionColor without a health event.
function WhoaUF:RefreshUnitTint(frame)
	if not frame or not frame.unit or not UnitExists(frame.unit) then
		return
	end
	local unit = frame.unit
	local health = frame.Health
	if health then
		-- Drop cache so a forced repaint wins even if RGB matches a stale bar paint.
		health.whoaHR, health.whoaHG, health.whoaHB = nil, nil, nil
		if self.ApplyHealthBarColor then
			self:ApplyHealthBarColor(health, unit)
		end
	end
	UpdateNameBackground(frame, unit)
	if UF.UpdateDeadText then
		UF.UpdateDeadText(frame, unit)
	end
	if self.UpdateHealPrediction then
		self:UpdateHealPrediction(frame)
	end
end

--- Player PvP / faction flips change UnitSelectionColor on current target/focus (and ToT).
function WhoaUF:RefreshPlayerSelectionDependentTints()
	local keys = { "target", "focus", "tot", "focustot", "pet" }
	for i = 1, #keys do
		self:RefreshUnitTint(frames[keys[i]])
	end
end

UF.UpdateHealth = UpdateHealth
UF.UpdatePower = UpdatePower
UF.UpdateClassification = UpdateClassification
UF.UpdateIdentity = UpdateIdentity
UF.UpdateDeadText = UpdateDeadText
UF.UpdatePlayerStatus = UpdatePlayerStatus
UF.UpdatePvPIcon = UpdatePvPIcon
UF.UpdateLeaderIcon = UpdateLeaderIcon
UF.UpdateGroupIndicator = UpdateGroupIndicator
UF.LayoutGroupIndicator = LayoutGroupIndicator
UF.UpdateRaidTargetIcon = UpdateRaidTargetIcon
UF.UpdateNameBackground = UpdateNameBackground
UF.UpdateToTAttackMode = UpdateToTAttackMode
UF.UpdateToTFrame = UpdateToTFrame
UF.SetSecureUnit = SetSecureUnit
UF.FlushPendingSecureUnits = FlushPendingSecureUnits

