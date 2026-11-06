--[[
	Unit frame coordinator: create surfaces, vehicle transitions, visibility, init.
	Update pipeline: Frames/UnitFrameUpdate.lua
	Events: Frames/UnitFrameEvents.lua
]]

local UF = WhoaUF._UF
local frames = UF.frames

-- UnitFrameClassic.xml geometry (PlayerFrame.xml / TargetFrame.xml bar slots).
local function CreateTemplateBars(frame, point, x)
	local health = UF.CreateTextStatusBar(frame)
	health:SetSize(119, 12)
	health:SetPoint(point, x, -45)
	frame.Health = health

	local power = UF.CreateTextStatusBar(frame)
	power:SetSize(119, 12)
	power:SetPoint(point, x, -56)
	power:Hide()
	frame.Power = power
end

local function CreatePlayerVisual(name)
	local frame = UF.CreateUnitButton(name, "WhoaUFClassicPlayerButtonTemplate")
	CreateTemplateBars(frame, "TOPLEFT", 90)
	frame.unit = "player"
	frame.kind = "player"
	UF.SetupSecureUnitButton(frame, "player")

	local overlay = frame.Overlay
	overlay:SetFrameLevel(frame:GetFrameLevel() + 3)
	frame.FrameTexture = overlay.FrameTexture
	frame.VehicleTexture = overlay.VehicleTexture
	if WhoaUF.ApplyPlayerFrameBorderArt then
		WhoaUF:ApplyPlayerFrameBorderArt(frame)
	elseif WhoaUF.GetFrameTexture then
		frame.FrameTexture:SetTexture(WhoaUF:GetFrameTexture("player"))
	end
	if overlay.Name then
		overlay.Name:Hide()
	end

	frame.state = "player"

	-- Name + numeric threat sit above overlay chrome (overlay +3; name host +8).
	local nameHost = CreateFrame("Frame", nil, frame)
	nameHost:SetAllPoints(frame)
	nameHost:SetFrameLevel(frame:GetFrameLevel() + 8)
	frame.NameHost = nameHost

	local nameText = nameHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameText:SetSize(100, 12)
	nameText:SetPoint("CENTER", 34, 15)
	frame.Name = nameText

	local levelText = overlay:CreateFontString(nil, "BORDER", "GameNormalNumberFont")
	-- MoP Classic PlayerFrame.xml: RIGHT + BOTTOMLEFT 35.25, 30 (no Era UpdateLevelTextAnchor).
	levelText:SetJustifyH("RIGHT")
	levelText:SetJustifyV("MIDDLE")
	levelText:SetPoint("CENTER", frame, "BOTTOMLEFT", 35.25, 30)
	frame.Level = levelText

	-- PlayerStatusTexture (PlayerFrame.xml). OVERLAY so it draws above frame border art;
	-- LayoutPlayerCombatGlow re-anchors when alt mana is shown.
	local statusTexture = overlay:CreateTexture(nil, "OVERLAY")
	statusTexture:SetSize(190, 66)
	statusTexture:SetPoint("TOPLEFT", 19, -12)
	if WhoaUF.GetPlayerStatusTexture then
		statusTexture:SetTexture(WhoaUF:GetPlayerStatusTexture(frame))
		statusTexture:SetTexCoord(WhoaUF:GetPlayerStatusTexCoord(frame))
	else
		statusTexture:SetTexture("Interface\\CharacterFrame\\UI-Player-Status")
		statusTexture:SetTexCoord(0, 0.74609375, 0, 0.53125)
	end
	statusTexture:SetBlendMode("ADD")
	statusTexture:Hide()
	frame.StatusTexture = statusTexture

	local restIcon = overlay:CreateTexture(nil, "OVERLAY")
	restIcon:SetSize(31, 33)
	restIcon:SetPoint("TOPLEFT", 19.5, -52)
	restIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
	restIcon:SetTexCoord(0, 0.5, 0, 0.421875)
	restIcon:Hide()
	frame.RestIcon = restIcon

	local attackIcon = overlay:CreateTexture(nil, "OVERLAY")
	attackIcon:SetSize(32, 32)
	attackIcon:SetPoint("TOPLEFT", restIcon, "TOPLEFT", 1, 0)
	attackIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
	attackIcon:SetTexCoord(0.5, 1.0, 0, 0.484375)
	attackIcon:Hide()
	frame.AttackIcon = attackIcon

	local attackBackground = overlay:CreateTexture(nil, "ARTWORK")
	attackBackground:SetSize(32, 32)
	attackBackground:SetPoint("TOPLEFT", 19, -54)
	attackBackground:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-AttackBackground")
	attackBackground:SetVertexColor(0.8, 0.1, 0.1)
	attackBackground:SetAlpha(0.4)
	attackBackground:Hide()
	frame.AttackBackground = attackBackground

	-- PlayerStatusGlow (PlayerFrame.xml): pulsing rest/combat halo on the portrait badge.
	local statusGlow = CreateFrame("Frame", nil, overlay)
	statusGlow:SetSize(32, 32)
	statusGlow:SetPoint("TOPLEFT", restIcon, "TOPLEFT", 0, 0)
	statusGlow:SetFrameLevel(overlay:GetFrameLevel() + 3)
	statusGlow:Hide()
	frame.StatusGlow = statusGlow

	local restGlow = statusGlow:CreateTexture(nil, "OVERLAY")
	restGlow:SetSize(32, 32)
	restGlow:SetPoint("TOPLEFT")
	restGlow:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
	restGlow:SetTexCoord(0, 0.5, 0.5, 1.0)
	restGlow:SetBlendMode("ADD")
	restGlow:Hide()
	frame.RestGlow = restGlow

	local attackGlow = statusGlow:CreateTexture(nil, "OVERLAY")
	attackGlow:SetSize(32, 32)
	attackGlow:SetPoint("TOPLEFT", 1, 0)
	attackGlow:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
	attackGlow:SetTexCoord(0.5, 1.0, 0.5, 1.0)
	attackGlow:SetBlendMode("ADD")
	attackGlow:SetVertexColor(1, 0, 0)
	attackGlow:Hide()
	frame.AttackGlow = attackGlow

	local pvpIcon = overlay:CreateTexture(nil, "ARTWORK")
	pvpIcon:SetSize(64, 64)
	pvpIcon:SetPoint("TOPLEFT", 2, -24)
	pvpIcon:Hide()
	frame.PvPIcon = pvpIcon

	local leaderIcon = overlay:CreateTexture(nil, "OVERLAY")
	leaderIcon:SetSize(16, 16)
	leaderIcon:SetPoint("TOPLEFT", 28, -14)
	leaderIcon:SetTexture(
		(WhoaUF.GetLeaderIconTexture and WhoaUF:GetLeaderIconTexture())
			or "Interface\\GroupFrame\\UI-Group-LeaderIcon"
	)
	leaderIcon:Hide()
	frame.LeaderIcon = leaderIcon

	-- Raid subgroup indicator: Media\shared\{light|dark}\UI-GroupIndicator.blp
	-- Parent unit button (not Overlay): above threat BACKGROUND flash, under FrameTexture.
	-- Tunables live with LayoutGroupIndicator in UnitFrameUpdate.lua.
	local groupIndicator = CreateFrame("Frame", nil, frame)
	groupIndicator:SetSize(64, 32)
	groupIndicator:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
	groupIndicator:Hide()
	frame.GroupIndicator = groupIndicator

	local groupTex = groupIndicator:CreateTexture(nil, "BACKGROUND")
	groupTex:SetAllPoints()
	if WhoaUF.GetGroupIndicatorTexture then
		groupTex:SetTexture(WhoaUF:GetGroupIndicatorTexture())
	else
		groupTex:SetTexture("Interface\\AddOns\\WhoaUnitFrames\\Media\\shared\\light\\UI-GroupIndicator")
	end
	groupIndicator.Texture = groupTex

	local groupText = groupIndicator:CreateFontString(nil, "ARTWORK")
	groupText:SetJustifyH("CENTER")
	groupText:SetPoint("CENTER", 0, -1)
	-- Yellow like GameFontNormal; face/size follow Settings → status-bar font.
	if NORMAL_FONT_COLOR then
		groupText:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	else
		groupText:SetTextColor(1, 0.82, 0)
	end
	groupIndicator.Text = groupText
	if WhoaUF.ApplyStatusBarTextFont then
		WhoaUF:ApplyStatusBarTextFont(groupText)
	end

	if UF.LayoutGroupIndicator then
		UF.LayoutGroupIndicator(frame)
	end

	-- PlayerHitIndicator (PlayerFrame.xml OVERLAY): portrait combat feedback text.
	local hitIndicator = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
	hitIndicator:SetPoint("CENTER", frame, "TOPLEFT", 57, -46)
	hitIndicator:Hide()
	frame.HitIndicator = hitIndicator

	frame.statusCounter = 0
	frame.statusSign = -1
	-- Pulse on a plain Frame — SetScript OnUpdate on SecureUnitButton taints clicks
	-- and surfaces as "Interface action failed because of an Addon" after combat.
	-- OnUpdate is only registered while StatusTexture is shown (see UpdatePlayerStatus).
	local statusPulse = CreateFrame("Frame", nil, UIParent)
	local function StatusPulse_OnUpdate(_, elapsed)
		local counter = frame.statusCounter + elapsed
		local sign = frame.statusSign
		if counter > 0.5 then
			sign = -sign
			frame.statusSign = sign
		end
		counter = counter % 0.5
		frame.statusCounter = counter
		local alpha
		if sign == 1 then
			alpha = (55 + (counter * 400)) / 255
		else
			alpha = (255 - (counter * 400)) / 255
		end
		frame.StatusTexture:SetAlpha(alpha)
		local glowHost = frame.StatusGlow
		if glowHost and glowHost:IsShown() then
			glowHost:SetAlpha(alpha)
		end
	end
	statusPulse.OnUpdate = StatusPulse_OnUpdate
	frame.statusPulse = statusPulse

	UF.AttachCombatFeedback(frame, hitIndicator)

	local health = frame.Health
	health:SetStatusBarColor(0, 1, 0)
	UF.SetupTextStatusBar(health, overlay, UF.PLAYER_HEALTH_TEXT, "STATUS_TEXT_PLAYER")
	if health.SetBarTextPrefix and HEALTH then
		health:SetBarTextPrefix(HEALTH)
	end
	health.unit = frame.unit or "player"
	UF.ArmFrequentHealthBar(health, frame)
	frame.Health = health

	local power = frame.Power
	UF.SetupTextStatusBar(power, overlay, UF.PLAYER_POWER_TEXT, "STATUS_TEXT_PLAYER")
	power.unit = frame.unit or "player"
	if UF.ArmFrequentPowerBar then
		UF.ArmFrequentPowerBar(power, frame)
	end
	frame.Power = power

	UF.SetSecureUnit(frame, "player")

	-- Health-loss trail + power builder/spender + full-power spikes (spikes above border).
	if WhoaUF.AttachStatusBarAnims then
		WhoaUF:AttachStatusBarAnims(frame)
	end

	-- Dead / Ghost label sits in the health-bar slot. Ghost reuses DeadText.
	local deadText = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	deadText:SetJustifyH("CENTER")
	deadText:SetPoint("CENTER", health, "CENTER")
	deadText:SetText(DEAD or "Dead")
	deadText:Hide()
	frame.DeadText = deadText

	frame:Hide()
	return frame
end

local function CreateTargetVisual(name, unit, kind)
	local frame = UF.CreateUnitButton(name, "WhoaUFClassicTargetButtonTemplate")
	CreateTemplateBars(frame, "TOPRIGHT", -90)
	frame.unit = unit
	frame.kind = kind
	UF.SetupSecureUnitButton(frame, unit)

	local overlay = frame.Overlay
	overlay:SetFrameLevel(frame:GetFrameLevel() + 3)
	frame.FrameTexture = overlay.FrameTexture
	frame.Name = overlay.Name
	frame.Level = overlay.Level
	frame.Level:SetJustifyH("CENTER")
	frame.Level:SetJustifyV("MIDDLE")

	-- Bind style pack chrome immediately so the first Show is not Blizzard→addon swap.
	if WhoaUF.GetFrameTexture then
		local path = WhoaUF:GetFrameTexture("normal")
		if path then
			frame.FrameTexture:SetTexture(path)
		end
	end
	frame.whoaChromePainted = nil

	local highLevel = overlay:CreateTexture(nil, "ARTWORK")
	highLevel:SetSize(16, 16)
	highLevel:SetPoint("CENTER", frame.Level, "CENTER")
	highLevel:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
	highLevel:Hide()
	frame.HighLevelTexture = highLevel

	local pvpIcon = overlay:CreateTexture(nil, "ARTWORK")
	pvpIcon:SetSize(64, 64)
	pvpIcon:SetPoint("TOPRIGHT", 19, -24)
	pvpIcon:Hide()
	frame.PvPIcon = pvpIcon

	local leaderIcon = overlay:CreateTexture(nil, "ARTWORK")
	leaderIcon:SetSize(16, 16)
	leaderIcon:SetPoint("TOPRIGHT", -28, -14)
	leaderIcon:SetTexture(
		(WhoaUF.GetLeaderIconTexture and WhoaUF:GetLeaderIconTexture())
			or "Interface\\GroupFrame\\UI-Group-LeaderIcon"
	)
	leaderIcon:Hide()
	frame.LeaderIcon = leaderIcon

	local raidTargetIcon = overlay:CreateTexture(nil, "ARTWORK")
	raidTargetIcon:SetSize(26, 26)
	raidTargetIcon:SetPoint("CENTER", frame, "TOPRIGHT", -57, -18)
	raidTargetIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	raidTargetIcon:Hide()
	frame.RaidTargetIcon = raidTargetIcon

	-- TargetHitIndicator: mirror PlayerHitIndicator on the right-side portrait.
	local hitIndicator = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
	hitIndicator:SetPoint("CENTER", frame, "TOPRIGHT", -56, -46)
	hitIndicator:Hide()
	frame.HitIndicator = hitIndicator
	UF.AttachCombatFeedback(frame, hitIndicator)

	local health = frame.Health
	health:SetStatusBarColor(0, 1, 0)
	UF.SetupTextStatusBar(health, overlay, UF.TARGET_HEALTH_TEXT, "STATUS_TEXT_TARGET")
	health.unit = unit
	UF.ArmFrequentHealthBar(health, frame)
	frame.Health = health

	local deadText = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	deadText:SetJustifyH("CENTER")
	deadText:SetPoint("CENTER", health, "CENTER")
	deadText:SetText(DEAD or "Dead")
	deadText:Hide()
	frame.DeadText = deadText

	local unconsciousText = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	unconsciousText:SetJustifyH("CENTER")
	unconsciousText:SetPoint("CENTER", health, "CENTER")
	unconsciousText:SetText(UNCONSCIOUS or "Unconscious")
	unconsciousText:Hide()
	frame.UnconsciousText = unconsciousText

	-- Offline lightning over the portrait (same asset as party Disconnect).
	local disconnect = overlay:CreateTexture(nil, "OVERLAY")
	disconnect:SetSize(64, 64)
	disconnect:SetPoint("CENTER", frame.Portrait, "CENTER")
	disconnect:SetTexture("Interface\\CharacterFrame\\Disconnect-Icon")
	disconnect:Hide()
	frame.Disconnect = disconnect

	local power = frame.Power
	UF.SetupTextStatusBar(power, overlay, UF.TARGET_POWER_TEXT, "STATUS_TEXT_TARGET")
	power.unit = unit
	power:Hide()
	if UF.ArmFrequentPowerBar then
		UF.ArmFrequentPowerBar(power, frame)
	end
	frame.Power = power

	if WhoaUF.AttachHealPrediction then
		WhoaUF:AttachHealPrediction(frame)
	end

	-- Power-hold + chrome reveal live on the plain show watcher (no HookScript
	-- on SecureUnitButton — that taints click/menu paths).
	UF.AttachUnitFrameShowWatcher(frame)
	frame:Hide()
	return frame
end

UF.CreateTargetVisual = CreateTargetVisual

-- Target/focus Overlay (+3) holds the classification border; Elite / Rare sheets hang
-- into the ToT corner. Keep ToT above that Overlay so HP/mana are never covered
-- (same idea as ApplyPetFrameLevel vs player Elite chrome).
-- Skip when already correct — repeated SetFrameLevel churn ramps addon memory.
function WhoaUF:ApplyToTFrameLevel(frame, parent)
	frame = frame or (parent and parent.totFrame)
	parent = parent or (frame and frame:GetParent())
	if not frame or not parent then
		return
	end
	local base = parent:GetFrameLevel() or 0
	local parentOverlay = parent.Overlay
	if parentOverlay then
		base = math.max(base, parentOverlay:GetFrameLevel() or 0)
	end
	local level = base + 1
	if frame:GetFrameLevel() ~= level then
		frame:SetFrameLevel(level)
	end
	if frame.Health and frame.Health:GetFrameLevel() ~= level + 1 then
		frame.Health:SetFrameLevel(level + 1)
	end
	if frame.Power and frame.Power:GetFrameLevel() ~= level + 1 then
		frame.Power:SetFrameLevel(level + 1)
	end
	if frame.Overlay and frame.Overlay:GetFrameLevel() ~= level + 3 then
		frame.Overlay:SetFrameLevel(level + 3)
	end
end

local function CreateToTVisual(parent, name, unit, kind)
	local frame = CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")
	frame:SetSize(93, 45)
	frame:SetFrameStrata("LOW")
	frame.unit = unit
	frame.kind = kind
	UF.SetupSecureUnitButton(frame, unit)
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -16, -14)
	parent.totFrame = frame

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetSize(46, 15)
	background:SetPoint("BOTTOMLEFT", 42, 13)
	background:SetColorTexture(0, 0, 0, 0.5)
	frame.Background = background

	local portrait = frame:CreateTexture(nil, "BORDER")
	portrait:SetSize(35, 35)
	portrait:SetPoint("TOPLEFT", 4.5, -6)
	frame.Portrait = portrait

	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	frame.Overlay = overlay

	local texture = overlay:CreateTexture(nil, "BORDER")
	texture:SetAllPoints()
	texture:SetTexture(UF.GetTargetFrameTexture("tot"))
	texture:SetTexCoord(0.015625, 0.7265625, 0, 0.703125)
	frame.FrameTexture = texture

	-- Pet-style attack glow on the ToT portrait (Blizzard ToT has none).
	-- UI-Player-AttackStatus is authored for a 76x64 draw; the ring sits in the
	-- upper-left of that slice — CENTER + offset keeps it on the 35px portrait
	-- when the draw size changes (pet TOPLEFT math alone lands ~10px bot-right).
	local attack = overlay:CreateTexture(nil, "ARTWORK")
	attack:SetSize(86, 70)
	attack:SetPoint("CENTER", portrait, "CENTER", 21, -17)
	attack:SetTexture("Interface\\TargetingFrame\\UI-Player-AttackStatus")
	attack:SetTexCoord(0.703125, 1, 0, 1)
	attack:SetBlendMode("ADD")
	attack:Hide()
	frame.AttackMode = attack

	frame.attackModeCounter = 0
	frame.attackModeSign = -1
	-- Pulse on UIParent — do not SetScript OnUpdate on SecureUnitButton.
	local attackPulse = CreateFrame("Frame", nil, UIParent)
	local function AttackPulse_OnUpdate(_, elapsed)
		local counter = frame.attackModeCounter + elapsed
		local sign = frame.attackModeSign
		if counter > 0.5 then
			sign = -sign
			frame.attackModeSign = sign
		end
		counter = counter % 0.5
		frame.attackModeCounter = counter
		local alpha
		if sign == 1 then
			alpha = (55 + (counter * 400)) / 255
		else
			alpha = (255 - (counter * 400)) / 255
		end
		frame.AttackMode:SetVertexColor(1, 1, 1, alpha)
	end
	attackPulse.OnUpdate = AttackPulse_OnUpdate
	frame.attackPulse = attackPulse

	-- OVERLAY keeps name/state above chrome.
	local nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameText:SetSize(100, 10)
	nameText:SetJustifyH("LEFT")
	nameText:SetPoint("BOTTOMLEFT", 42, 2)
	frame.Name = nameText

	local hitIndicator = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalHuge")
	hitIndicator:SetPoint("CENTER", portrait, "CENTER", 0, 0)
	hitIndicator:Hide()
	frame.HitIndicator = hitIndicator
	UF.AttachCombatFeedback(frame, hitIndicator, 22)

	local totBars = WhoaUF.GetFrameBarLayout and WhoaUF:GetFrameBarLayout(kind or "tot")
	local healthGeom = totBars and totBars.health
	local powerGeom = totBars and totBars.power
	local health = CreateFrame("StatusBar", name .. "Health", frame)
	health:SetSize(healthGeom and healthGeom.width or 46, healthGeom and healthGeom.height or 7)
	health:SetPoint(
		healthGeom and healthGeom.point or "TOPRIGHT",
		healthGeom and healthGeom.x or -2,
		healthGeom and healthGeom.y or -15
	)
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	health:EnableMouse(false)
	health.unit = unit
	frame.Health = health
	if UF.ArmFrequentHealthBar then
		UF.ArmFrequentHealthBar(health, frame)
	end

	local power = CreateFrame("StatusBar", name .. "Power", frame)
	power:SetSize(powerGeom and powerGeom.width or 46, powerGeom and powerGeom.height or 7)
	power:SetPoint(
		powerGeom and powerGeom.point or "TOPRIGHT",
		powerGeom and powerGeom.x or -2,
		powerGeom and powerGeom.y or -23
	)
	power:SetMinMaxValues(0, 1)
	power:SetValue(1)
	power:EnableMouse(false)
	power.unit = unit
	power:Hide()
	frame.Power = power
	if UF.ArmFrequentPowerBar then
		UF.ArmFrequentPowerBar(power, frame)
	end

	-- Dead / Ghost / Unconscious in the ToT health-bar slot.
	local deadText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	deadText:SetJustifyH("CENTER")
	deadText:SetPoint("CENTER", health, "CENTER")
	deadText:SetText(DEAD or "Dead")
	deadText:Hide()
	frame.DeadText = deadText

	local unconsciousText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	unconsciousText:SetJustifyH("CENTER")
	unconsciousText:SetPoint("CENTER", health, "CENTER")
	unconsciousText:SetText(UNCONSCIOUS or "Unconscious")
	unconsciousText:Hide()
	frame.UnconsciousText = unconsciousText

	-- Scaled disconnect bolt over the small ToT portrait.
	local disconnect = overlay:CreateTexture(nil, "OVERLAY")
	disconnect:SetSize(40, 40)
	disconnect:SetPoint("CENTER", portrait, "CENTER")
	disconnect:SetTexture("Interface\\CharacterFrame\\Disconnect-Icon")
	disconnect:Hide()
	frame.Disconnect = disconnect

	-- Own bars: apply Whoa texture/color directly (no stock UnitFrameHealthBar_Update green).
	if WhoaUF.ApplyFrameStatusBars then
		WhoaUF:ApplyFrameStatusBars(frame)
	else
		local hp = WhoaUF.ReactionColors.default
		local mana = WhoaUF:GetPowerBarColor("MANA")
		health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		health:SetStatusBarColor(hp.r, hp.g, hp.b)
		power:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		power:SetStatusBarColor(mana.r, mana.g, mana.b)
	end

	if UnitFrame_OnEnter and UnitFrame_OnLeave then
		frame:SetScript("OnEnter", UnitFrame_OnEnter)
		frame:SetScript("OnLeave", UnitFrame_OnLeave)
	end

	if WhoaUF.AttachHealPrediction then
		WhoaUF:AttachHealPrediction(frame)
	end

	-- After Health/Power exist: pin above parent Overlay (elite border) and
	-- under ToT Overlay chrome. CreateSpellbar reads this level next.
	WhoaUF:ApplyToTFrameLevel(frame, parent)

	-- Same show/GUID poller as target/focus — RegisterUnitWatch can lag the
	-- UNIT_TARGET paint, and ToT/ToF often swap GUID while staying shown.
	UF.AttachUnitFrameShowWatcher(frame)
	frame:Hide()
	return frame
end
local function HidePlayerClassPowerBars()
	local player = UF.frames.player
	if not player then
		return
	end
	local list = WhoaUF.GetRegisteredClassBars and WhoaUF:GetRegisteredClassBars()
	if list then
		for i = 1, #list do
			local def = list[i]
			local key = def.frameKey or (def.layout and def.layout.frameKey)
			if key and player[key] then
				player[key]:Hide()
			end
		end
	end
end

function WhoaUF:HidePlayerClassPowerBars()
	HidePlayerClassPowerBars()
end

-- True when the player seat should show vehicle player-frame UI.
-- Requires both the HasUI flag and a live "vehicle" unit — abrupt quest exits
-- (Lou's House, etc.) can leave HasUI true after the vehicle token is gone.
local function PlayerVehicleSeatActive()
	if not (UnitHasVehiclePlayerFrameUI and UnitHasVehiclePlayerFrameUI("player")) then
		return false
	end
	return UnitExists("vehicle")
end

function WhoaUF:PlayerVehicleSeatActive()
	return PlayerVehicleSeatActive()
end

-- Combat-safe partial restore when exiting a vehicle seat under lockdown (full
-- PlayerFrameToPlayerArt waits for REGEN for secure unit/token swaps).
function WhoaUF:RestorePlayerVehicleVisualsOnly()
	local frame = UF.frames.player
	if not frame then
		return
	end
	frame.state = "player"
	-- Queue secure unit → "player" (SetAttribute waits for REGEN). Paint from
	-- "player" so UpdateUnitFrame does not ClearUnitFrameVisuals on a stale
	-- "vehicle" token while clicks still use the deferred attribute.
	UF.SetSecureUnit(frame, "player")
	if UF.frames.pet then
		UF.SetSecureUnit(UF.frames.pet, "pet")
	end
	if frame.forceVehiclePreview then
		frame.forceVehiclePreview = nil
	end
	if frame.VehicleTexture then
		frame.VehicleTexture:Hide()
	end
	if self.RefreshPlayerFrameFromOptions then
		self:RefreshPlayerFrameFromOptions(frame)
	elseif self.RestorePlayerFrameChrome then
		self:RestorePlayerFrameChrome(frame)
		if self.RestorePlayerClassPowerBars then
			self:RestorePlayerClassPowerBars()
		end
		if self.UpdateFrameThreat then
			self:UpdateFrameThreat(frame)
		end
		self:UpdateUnitFrame(frame)
	end
	if self.SchedulePlayerFrameOptionsRefresh then
		self:SchedulePlayerFrameOptionsRefresh()
	end
end

-- Texture/bar-only vehicle chrome (combat-safe; no secure unit swap).
function WhoaUF:ApplyPlayerVehicleVisuals(vehicleType)
	local frame = UF.frames.player
	if not frame then
		return
	end
	if not PlayerVehicleSeatActive() then
		return
	end
	frame.state = "vehicle"
	vehicleType = vehicleType or (UnitVehicleSkinType and UnitVehicleSkinType("player")) or "Mechanical"

	if self.ApplyDeathKnightPlayerArt then
		self:ApplyDeathKnightPlayerArt(frame)
	end
	if self.ApplyPlayerVehicleChrome then
		self:ApplyPlayerVehicleChrome(frame, vehicleType)
	end

	HidePlayerClassPowerBars()
	self:UpdateUnitFrame(frame)
end

-- DevTools force-show: paint vehicle chrome on the player frame without a seat.
-- Does not swap secure units. Real vehicle seats always win.
function WhoaUF:ApplyForceShowVehicleArt()
	local frame = UF.frames.player
	if not frame then
		return
	end
	if PlayerVehicleSeatActive() then
		-- Live seat owns art; keep db for when the seat ends.
		return
	end
	local skin = self.GetForceShowVehicleType and self:GetForceShowVehicleType()
	if not skin then
		if frame.forceVehiclePreview then
			frame.forceVehiclePreview = nil
			if self.RestorePlayerVehicleVisualsOnly then
				self:RestorePlayerVehicleVisualsOnly()
			elseif self.PlayerFrameToPlayerArt and not InCombatLockdown() then
				self:PlayerFrameToPlayerArt()
			end
		end
		return
	end

	frame.forceVehiclePreview = skin
	if self.ApplyDeathKnightPlayerArt then
		self:ApplyDeathKnightPlayerArt(frame)
	end
	if self.ApplyPlayerVehicleChrome then
		self:ApplyPlayerVehicleChrome(frame, skin)
	end
	HidePlayerClassPowerBars()
	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end
	self:UpdateUnitFrame(frame)
end

-- Strip DK/stock player chrome as soon as a vehicle seat is active (safe in combat).
function WhoaUF:SuppressPlayerVehicleChrome()
	local player = UF.frames.player
	if not player then
		return
	end
	if self.ApplyDeathKnightPlayerArt then
		self:ApplyDeathKnightPlayerArt(player)
	end
	self:HidePlayerClassPowerBars()
end

-- Enter/exit/reload vehicle sync (Blizzard PlayerFrame_UpdateArt + immediate suppress).
function WhoaUF:ApplyPlayerVehicleTransition()
	local frame = UF.frames.player
	if not frame then
		return
	end
	local inVehicle = PlayerVehicleSeatActive()
	if inVehicle then
		self:SuppressPlayerVehicleChrome()
		if InCombatLockdown() then
			UF.pendingVehicleArtApply = true
			-- Set frame.unit before paint; SetAttribute waits for REGEN.
			UF.SetSecureUnit(frame, "vehicle")
			if UF.frames.pet then
				UF.SetSecureUnit(UF.frames.pet, "player")
			end
			if self.ApplyPlayerVehicleVisuals then
				self:ApplyPlayerVehicleVisuals()
			end
			return
		end
	end
	self:UpdatePlayerFrameArt()
end

-- Defer retry: UnitHasVehiclePlayerFrameUI / UnitExists("vehicle") can lag
-- UNIT_EXITED_VEHICLE on scripted seats and leave the player frame wiped.
-- Generation counter so EXITING and EXITED each schedule a retry.
function WhoaUF:SchedulePlayerVehicleTransition()
	UF.vehicleTransitionGen = (UF.vehicleTransitionGen or 0) + 1
	local gen = UF.vehicleTransitionGen
	C_Timer.After(0, function()
		if gen ~= UF.vehicleTransitionGen then
			return
		end
		if WhoaUF.ApplyPlayerVehicleTransition then
			WhoaUF:ApplyPlayerVehicleTransition()
		end
		-- Second tick: HasUI can clear one frame after the vehicle token.
		C_Timer.After(0, function()
			if gen ~= UF.vehicleTransitionGen then
				return
			end
			if WhoaUF.ApplyPlayerVehicleTransition then
				WhoaUF:ApplyPlayerVehicleTransition()
			end
		end)
	end)
end

local function RestorePlayerClassPowerBars()
	local player = UF.frames.player
	if not player then
		return
	end
	if WhoaUF.RefreshPlayerClassBars then
		WhoaUF:RefreshPlayerClassBars()
	end
end

function WhoaUF:RestorePlayerClassPowerBars()
	RestorePlayerClassPowerBars()
end

-- Mirror PlayerFrame_ToVehicleArt (Classic/PlayerFrame.lua).
-- Pet unit → "player"; visibility still gated by PetUsesPetFrame() / vehicleHidesPet.
function WhoaUF:PlayerFrameToVehicleArt(vehicleType)
	local frame = UF.frames.player
	if not frame then
		return
	end
	if not PlayerVehicleSeatActive() then
		self:PlayerFrameToPlayerArt()
		return
	end

	frame.state = "vehicle"
	UF.SetSecureUnit(frame, "vehicle")
	if UF.frames.pet then
		UF.SetSecureUnit(UF.frames.pet, "player")
	end
	if self.ApplyPetFrameVisibility then
		self:ApplyPetFrameVisibility()
	end

	frame.FrameTexture:Hide()
	if self.ApplyDeathKnightPlayerArt then
		self:ApplyDeathKnightPlayerArt(frame)
	end
	if self.ApplyPlayerVehicleChrome then
		self:ApplyPlayerVehicleChrome(frame, vehicleType)
	end

	HidePlayerClassPowerBars()
	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end

	self:UpdateUnitFrame(frame)
	if self.UpdatePetFrame then
		self:UpdatePetFrame()
	end
	if self.UpdateComboFrame then
		self:UpdateComboFrame()
	end
end

-- Mirror PlayerFrame_ToPlayerArt.
function WhoaUF:PlayerFrameToPlayerArt()
	local frame = UF.frames.player
	if not frame then
		return
	end

	frame.state = "player"
	UF.SetSecureUnit(frame, "player")
	if frame.forceVehiclePreview then
		frame.forceVehiclePreview = nil
	end
	if UF.frames.pet then
		UF.SetSecureUnit(UF.frames.pet, "pet")
	end
	if self.ApplyPetFrameVisibility then
		self:ApplyPetFrameVisibility()
	end

	if frame.whoaVehicleCombatHidden and frame.SetAlpha then
		frame:SetAlpha(1)
		frame.whoaVehicleCombatHidden = nil
	end

	-- Full options refresh: style HP/mana geom, textures, fonts, DK/alt/class chrome.
	if self.RefreshPlayerFrameFromOptions then
		self:RefreshPlayerFrameFromOptions(frame)
	elseif self.RestorePlayerFrameChrome then
		self:RestorePlayerFrameChrome(frame)
		RestorePlayerClassPowerBars()
		if self.LayoutPlayerBottomFrames then
			self:LayoutPlayerBottomFrames()
		end
		if self.RefreshAlternateManaBar then
			self:RefreshAlternateManaBar()
		end
		self:UpdateUnitFrame(frame)
	else
		frame.FrameTexture:Show()
		if frame.VehicleTexture then
			frame.VehicleTexture:Hide()
		end
		if WhoaUF.ApplyFrameBarLayout then
			WhoaUF:ApplyFrameBarLayout(frame, true)
		end
		self:UpdateUnitFrame(frame)
	end

	-- Seat/HasUI can lag EXITED; re-apply style bars next frame.
	if self.SchedulePlayerFrameOptionsRefresh then
		self:SchedulePlayerFrameOptionsRefresh()
	end

	if self.UpdatePetFrame then
		self:UpdatePetFrame()
	end
	if self.UpdateComboFrame then
		self:UpdateComboFrame()
	end
end

-- Mirror PlayerFrame_UpdateArt (skip animate-out; apply seat state immediately).
function WhoaUF:UpdatePlayerFrameArt()
	local frame = UF.frames.player
	if not frame then
		return
	end
	if InCombatLockdown() then
		UF.pendingVehicleArtApply = true
		if PlayerVehicleSeatActive() then
			self:SuppressPlayerVehicleChrome()
			-- Set frame.unit before paint; SetAttribute waits for REGEN.
			UF.SetSecureUnit(frame, "vehicle")
			if UF.frames.pet then
				UF.SetSecureUnit(UF.frames.pet, "player")
			end
			if self.ApplyPlayerVehicleVisuals then
				self:ApplyPlayerVehicleVisuals()
			end
		elseif self.RestorePlayerVehicleVisualsOnly then
			self:RestorePlayerVehicleVisualsOnly()
		end
		return
	end
	UF.pendingVehicleArtApply = nil

	if PlayerVehicleSeatActive() then
		local skin = (UnitVehicleSkinType and UnitVehicleSkinType("player")) or "Mechanical"
		self:PlayerFrameToVehicleArt(skin)
	elseif self.GetForceShowVehicleType and self:GetForceShowVehicleType() then
		if self.ApplyForceShowVehicleArt then
			self:ApplyForceShowVehicleArt()
		end
	else
		self:PlayerFrameToPlayerArt()
	end
end
-- PlayerStatusTexture stays on the player overlay. Player threat border lives on a
-- UIParent host at playerLevel-1 (below the player frame and all class bars).
-- Alt-mana Y nudge applied below.
local PLAYER_FLASH_X = -3
local PLAYER_FLASH_Y = -3
local PLAYER_FLASH_Y_ALT_MANA = -1

function WhoaUF:LayoutPlayerCombatGlow(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	if not frame then
		return
	end
	local altShown = self.IsAlternateManaBarShown and self:IsAlternateManaBarShown()
	local altStacked = altShown and self.IsAlternateManaBarStackedStyle and self:IsAlternateManaBarStackedStyle()
	local altStock = altShown and not altStacked
	local altBar = frame.AlternateManaBar
	local overlay = frame.Overlay
	local overlayLevel = overlay and overlay:GetFrameLevel() or (frame:GetFrameLevel() + 3)

	-- Stock Druid/Monk alt strip above overlay chrome (same stacking as combo tray).
	if altStock and altBar and altBar:IsShown() and altBar:GetAlpha() > 0 then
		if not (InCombatLockdown() and altBar:IsProtected()) then
			local barLevel = overlayLevel + 1
			altBar:SetFrameLevel(barLevel)
			if altBar.Chrome then
				altBar.Chrome:SetFrameLevel(barLevel + 5)
			end
		end
	end

	local status = frame.StatusTexture
	if status and overlay then
		if self.IsDkAlphaPlayerArtActive and self:IsDkAlphaPlayerArtActive(frame) then
			if self.LayoutDkAlphaPlayerStatus then
				self:LayoutDkAlphaPlayerStatus(frame)
			end
		else
			if self.ApplyPlayerStatusTexture then
				self:ApplyPlayerStatusTexture(frame)
			end
		end
	end

	local flash = frame.threatIndicator
	if flash then
		if self.ApplyThreatFlashStrata then
			self:ApplyThreatFlashStrata(frame)
		end
		-- DK Alpha / BlizzCon keep the mirrored PlayerFrameFlash (numeric stays target-only).
		if self.ApplyPlayerThreatFlashArt then
			self:ApplyPlayerThreatFlashArt(frame)
		end
		flash:ClearAllPoints()
		flash:SetPoint("TOPLEFT", frame, "TOPLEFT", PLAYER_FLASH_X, altStock and PLAYER_FLASH_Y_ALT_MANA or PLAYER_FLASH_Y)
	end

	-- Combo after threat/overlay levels: both sit above the under-player threat host.
	local combo = frame.ComboPointPlayerBar or frame.RogueComboPointBar or frame.DruidComboPointBar
	if combo then
		if frame.DruidComboPointBar and combo == frame.DruidComboPointBar and self.AnchorDruidComboPointBar then
			self:AnchorDruidComboPointBar()
		elseif self.AnchorComboPointPlayerBar then
			self:AnchorComboPointPlayerBar()
		end
	end

	if WhoaUF.SyncPlayerNumericThreatAnchor then
		WhoaUF:SyncPlayerNumericThreatAnchor(frame)
	end
end
local function UsesUnitWatch(frame)
	return frame.kind == "target"
		or frame.kind == "focus"
		or frame.kind == "tot"
		or frame.kind == "focustot"
		or frame.kind == "pet"
		or frame.kind == "boss"
end

local function ShouldWatchToT()
	return GetCVarBool("showTargetOfTarget")
end

function WhoaUF:ApplyUnitFrames()
	if InCombatLockdown() then
		UF.pendingUnitFramesApply = true
		return
	end
	UF.pendingUnitFramesApply = nil

	local show = self.db and self.db.enabled
	if show and self.editModePreviewActive and self.ApplyEditModePreviewVisibility then
		self:ApplyEditModePreviewVisibility()
		if UF.frames.target and UF.frames.target.spellbar and self.AdjustSpellBar then
			self:AdjustSpellBar(UF.frames.target)
		end
		if UF.frames.focus and UF.frames.focus.spellbar and self.AdjustSpellBar then
			self:AdjustSpellBar(UF.frames.focus)
		end
		self:SetRuntimeActive(show)
		return
	end

	local showToT = show and ShouldWatchToT()
	for key, frame in pairs(UF.frames) do
		if key == "party" or frame.kind == "party" then
			-- Visibility handled by LayoutPartyFrames.
		elseif frame.kind == "boss" then
			-- Visibility handled by LayoutBossFrames.
		elseif frame.kind == "raidgroup" or frame.kind == "raidmember" then
			-- Visibility handled by LayoutRaidGroupFrames.
		elseif show then
			local force = self:IsForceShowFrame(frame.kind)
			if frame.kind == "tot" or frame.kind == "focustot" then
				if force or showToT then
					if force then
						UnregisterUnitWatch(frame)
						frame:Show()
					else
						RegisterUnitWatch(frame)
					end
				else
					UnregisterUnitWatch(frame)
					frame:Hide()
				end
			elseif UsesUnitWatch(frame) then
				if frame.kind == "pet" and self.ApplyPetFrameVisibility then
					self:ApplyPetFrameVisibility()
				elseif force then
					UnregisterUnitWatch(frame)
					frame:Show()
				else
					RegisterUnitWatch(frame)
				end
			else
				frame:Show()
			end
			self:UpdateUnitFrame(frame)
			if force and self.ApplyForceShowPlaceholder then
				self:ApplyForceShowPlaceholder(frame)
			end
		else
			if UsesUnitWatch(frame) then
				UnregisterUnitWatch(frame)
			end
			frame:Hide()
		end
	end
	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end
	if self.LayoutPartyFrames then
		self:LayoutPartyFrames()
	end
	if self.LayoutBossFrames then
		self:LayoutBossFrames()
	end
	if self.LayoutRaidGroupFrames then
		self:LayoutRaidGroupFrames()
	end
	if self.ApplyForceShowVehicleArt then
		self:ApplyForceShowVehicleArt()
	end
	if self.IsForceShowThreatIndicator and self:IsForceShowThreatIndicator() and self.ApplyForceShowThreatIndicators then
		self:ApplyForceShowThreatIndicators()
	end
	if self.IsForceShowGroupIndicator and self:IsForceShowGroupIndicator() and self.ApplyForceShowGroupIndicator then
		self:ApplyForceShowGroupIndicator()
	end
	if UF.frames.target and UF.frames.target.spellbar and self.AdjustSpellBar then
		self:AdjustSpellBar(UF.frames.target)
	end
	if UF.frames.focus and UF.frames.focus.spellbar and self.AdjustSpellBar then
		self:AdjustSpellBar(UF.frames.focus)
	end
	self:SetRuntimeActive(show)
end

local function StopPulse(pulse)
	if pulse and pulse.whoaActive then
		pulse:SetScript("OnUpdate", nil)
		pulse.whoaActive = false
	end
end

local function ReleaseFrameRuntime(self, frame)
	if not frame then
		return
	end
	StopPulse(frame.statusPulse)
	StopPulse(frame.attackPulse)
	if UF.StopCombatFeedbackPulse then
		UF.StopCombatFeedbackPulse(frame)
	end
	if frame.HitIndicator then
		frame.HitIndicator:Hide()
	end
	if frame.kind == "party" then
		frame:SetScript("OnUpdate", nil)
		local pulse = frame.memberPulse
		if pulse and pulse.whoaActive then
			pulse:SetScript("OnUpdate", nil)
			pulse.whoaActive = false
		end
	end
	if self.ClearStatusBarAnims then
		self:ClearStatusBarAnims(frame)
	end
	if self.ReleaseThreatRuntime then
		self:ReleaseThreatRuntime(frame)
		if frame.PetFrame then
			self:ReleaseThreatRuntime(frame.PetFrame)
		end
	end
	if self.ReleaseSpellbarRuntime then
		self:ReleaseSpellbarRuntime(frame)
	end
	if self.ReleaseToTAuraWatcher then
		self:ReleaseToTAuraWatcher(frame)
	end
	if UF.ReleaseUnitFrameShowWatcher then
		UF.ReleaseUnitFrameShowWatcher(frame)
	end
end

local function ResumeFrameRuntime(self, frame)
	if not frame then
		return
	end
	if frame.kind == "party" and self.ResumePartyMemberOnUpdate then
		self:ResumePartyMemberOnUpdate(frame)
	end
	if self.ResumeThreatRuntime then
		self:ResumeThreatRuntime(frame)
		if frame.PetFrame then
			self:ResumeThreatRuntime(frame.PetFrame)
		end
	end
	if self.ResumeSpellbarRuntime then
		self:ResumeSpellbarRuntime(frame)
	end
	if self.SyncToTAuraWatcher then
		self:SyncToTAuraWatcher(frame)
	end
	if UF.SyncUnitFrameShowWatcher then
		UF.SyncUnitFrameShowWatcher(frame)
	end
end

local function SetModuleEvents(frame, enabled, registerFn)
	if not frame then
		return
	end
	if enabled then
		if registerFn then
			registerFn(frame)
		end
	else
		frame:UnregisterAllEvents()
		frame:SetScript("OnUpdate", nil)
	end
end

-- Exclusive Whoa runtime: register watchers/modules when on; UnregisterAllEvents +
-- clear OnUpdates when off (hide alone still leaves duplicate work running).
function WhoaUF:SetRuntimeActive(active)
	if self.runtimeActive == active then
		return
	end
	self.runtimeActive = active

	if self.unitFrameWatcher then
		if active then
			if self.RegisterUnitFrameWatcherEvents then
				self.RegisterUnitFrameWatcherEvents(self.unitFrameWatcher, self.unitFrameWatcherB)
			end
		else
			self.unitFrameWatcher:UnregisterAllEvents()
			if self.unitFrameWatcherB then
				self.unitFrameWatcherB:UnregisterAllEvents()
			end
		end
	end
	if UF.SetCombatFeedbackRuntime then
		UF.SetCombatFeedbackRuntime(active)
	end
	if self.petWatcher then
		if active then
			if self.RegisterPetWatcherEvents then
				self.RegisterPetWatcherEvents(self.petWatcher)
			end
		else
			self.petWatcher:UnregisterAllEvents()
		end
	end
	if self.partyWatcher then
		if active then
			if self.RegisterPartyWatcherEvents then
				self.RegisterPartyWatcherEvents(self.partyWatcher)
			end
		else
			self.partyWatcher:UnregisterAllEvents()
		end
	end

	local player = UF.frames.player
	local target = UF.frames.target
	if player then
		if self.SetPlayerClassBarRuntime then
			self:SetPlayerClassBarRuntime(active)
		end
		-- Totem button OnUpdates are per-slot; class-bar setRuntime clears the parent only.
		if not active and player.TotemFrame and player.TotemFrame.buttons then
			for _, btn in pairs(player.TotemFrame.buttons) do
				btn:SetScript("OnUpdate", nil)
			end
		elseif active and player.TotemFrame and player.TotemFrame.buttons and self.TotemButton_OnUpdate then
			for _, btn in pairs(player.TotemFrame.buttons) do
				if btn.slot then
					btn:SetScript("OnUpdate", self.TotemButton_OnUpdate)
				end
			end
		end
	end
	if target then
		SetModuleEvents(target.ComboFrame, active, self.RegisterComboFrameEvents)
		if not active and target.ComboFrame then
			target.ComboFrame:Hide()
		end
	end

	if self.petCastingBar then
		if active then
			self.petCastingBar:RegisterEvent("UNIT_PET")
			if self.petCastingBar.SetUnit then
				self.petCastingBar:SetUnit("pet", false, false)
			end
		else
			self.petCastingBar:UnregisterAllEvents()
			self.petCastingBar:Hide()
		end
	end

	for _, frame in pairs(UF.frames) do
		if type(frame) == "table" and frame.GetObjectType then
			if active then
				ResumeFrameRuntime(self, frame)
			else
				ReleaseFrameRuntime(self, frame)
			end
		end
	end

	if active then
		self:RefreshAllUnitFrames()
		if self.UpdateComboFrame then
			self:UpdateComboFrame()
		end
		if self.RefreshPlayerClassBars then
			self:RefreshPlayerClassBars()
		end
	else
		if self.RequestIdleCollect then
			-- Addon disabled: force reclaim pollers/aura/text runtime churn.
			self:RequestIdleCollect(true)
		end
	end
end

local function ApplyAnchor(frame, cfg)
	if not frame or not cfg then
		return
	end
	if InCombatLockdown() and frame:IsProtected() then
		return
	end
	local relativeTo
	if WhoaUF.ResolveEditModeRelativeFrame then
		relativeTo = WhoaUF:ResolveEditModeRelativeFrame(cfg.relativeTo or "UIParent")
	else
		relativeTo = _G[cfg.relativeTo or "UIParent"] or UIParent
	end
	frame:ClearAllPoints()
	frame:SetPoint(
		cfg.point or "TOPLEFT",
		relativeTo,
		cfg.relativePoint or cfg.point or "TOPLEFT",
		cfg.x or 0,
		cfg.y or 0
	)
end

local function CopyAnchorToDb(cfg, anchor)
	cfg.point = anchor.point
	cfg.relativeTo = anchor.relativeTo or "UIParent"
	cfg.relativePoint = anchor.relativePoint or anchor.point
	cfg.x = anchor.x or 0
	cfg.y = anchor.y or 0
end

local POSITION_SYNC_ORDER = { "player", "target", "focus", "party" }

function WhoaUF:SyncUnitFramePositions()
	if not UF.frames.player then
		return
	end

	local db = self.db and self.db.frames
	for i = 1, #POSITION_SYNC_ORDER do
		local key = POSITION_SYNC_ORDER[i]
		local frame = UF.frames[key]
		if frame and frame.whoaUFEditModeOwner then
			-- EditMode_*.lua registered owner: its SetPoint/SetScale is the layout source.
		elseif frame and frame.kind ~= "tot" and frame.kind ~= "focustot" and frame.kind ~= "pet" and frame.kind ~= "party" then
			local anchor = self.GetBlizzardUnitFrameAnchor and self:GetBlizzardUnitFrameAnchor(key)
			if anchor then
				if db and db[key] then
					CopyAnchorToDb(db[key], anchor)
				end
				ApplyAnchor(frame, anchor)
			elseif db and db[key] then
				ApplyAnchor(frame, db[key])
			end
		end
	end

	-- Party container: EditMode_*.lua owner supplies layout; else mirror stock PartyFrame anchor.
	if UF.frames.party and not UF.frames.party.whoaUFEditModeOwner then
		local anchor = self.GetBlizzardUnitFrameAnchor and self:GetBlizzardUnitFrameAnchor("party")
		if anchor then
			if db and db.party then
				CopyAnchorToDb(db.party, anchor)
			end
			ApplyAnchor(UF.frames.party, anchor)
		elseif db and db.party then
			ApplyAnchor(UF.frames.party, db.party)
		end
	end

	if UF.frames.player and self.LayoutPlayerCombatGlow then
		self:LayoutPlayerCombatGlow(UF.frames.player)
	end
	if UF.frames.player and self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end
	if self.AnchorComboFrame then
		self:AnchorComboFrame()
	end
end
function WhoaUF:InitUnitFrames()
	if UF.frames.player then
		return
	end

	UF.frames.player = CreatePlayerVisual("WhoaUFPlayerFrame")
	UF.frames.target = CreateTargetVisual("WhoaUFTargetFrame", "target", "target")
	UF.frames.tot = CreateToTVisual(UF.frames.target, "WhoaUFToTFrame", "targettarget", "tot")
	-- Classic Era has no focus unit; skip Whoa focus surfaces there.
	local hasFocus = not self.HasFocusUnit or self:HasFocusUnit()
	if hasFocus then
		UF.frames.focus = CreateTargetVisual("WhoaUFFocusFrame", "focus", "focus")
		UF.frames.focustot = CreateToTVisual(UF.frames.focus, "WhoaUFFocusToTFrame", "focustarget", "focustot")
	end
	self.unitFrames = UF.frames

	if self.InitPlayerClassBars then
		self:InitPlayerClassBars(UF.frames.player)
	end
	if self.ApplyDeathKnightPlayerArt then
		self:ApplyDeathKnightPlayerArt(UF.frames.player)
	end
	if self.InitPetFrame then
		UF.frames.pet = self:InitPetFrame(UF.frames.player)
	end
	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end
	if self.InitComboFrame then
		self:InitComboFrame(UF.frames.target)
	end
	if self.InitPartyFrames then
		self.unitFrames = UF.frames
		self:InitPartyFrames()
		for i = 1, 4 do
			local partyFrame = self.partyFrames and self.partyFrames[i]
			UF.frames["party" .. i] = partyFrame
			if partyFrame and self.InitPartyThreat then
				pcall(function()
					self:InitPartyThreat(partyFrame)
				end)
				if partyFrame.PetFrame then
					pcall(function()
						self:InitPartyThreat(partyFrame.PetFrame)
					end)
				end
			end
		end
		UF.frames.party = self.partyContainer
	end
	-- Boss: watchers only (frames on encounter / force-show). Raid: force-show only.
	if self.InitBossFrames then
		self:InitBossFrames()
	end
	if self.InitFrameAuras then
		self:InitFrameAuras(UF.frames.target)
		if UF.frames.focus then
			self:InitFrameAuras(UF.frames.focus)
		end
	end
	if self.AttachToTAuraHooks then
		self:AttachToTAuraHooks(UF.frames.tot, UF.frames.target)
		if UF.frames.focustot and UF.frames.focus then
			self:AttachToTAuraHooks(UF.frames.focustot, UF.frames.focus)
		end
	end
	if self.InitToTDebuffs then
		self:InitToTDebuffs(UF.frames.tot)
		if UF.frames.focustot then
			self:InitToTDebuffs(UF.frames.focustot)
		end
	end
	if self.InitPlayerThreat then
		pcall(function()
			self:InitPlayerThreat(UF.frames.player)
		end)
	end
	if UF.frames.pet and self.InitPartyThreat then
		pcall(function()
			self:InitPartyThreat(UF.frames.pet)
		end)
	end
	if self.LayoutPlayerCombatGlow then
		self:LayoutPlayerCombatGlow(UF.frames.player)
	end
	if self.InitCastAndThreat then
		pcall(function()
			self:InitCastAndThreat(UF.frames.target, "PLAYER_TARGET_CHANGED")
		end)
		if UF.frames.focus then
			pcall(function()
				self:InitCastAndThreat(UF.frames.focus, "PLAYER_FOCUS_CHANGED")
			end)
		end
	end
	if self.InitSpellDiminish then
		pcall(function()
			self:InitSpellDiminish()
		end)
	end
	if self.ApplyStatusBarFonts then
		self:ApplyStatusBarFonts()
	end

	self:SyncUnitFramePositions()

	if self.InitUnitFrameEvents then
		self:InitUnitFrameEvents()
	end
	if self.InitUnitFrameCombatFlush then
		self:InitUnitFrameCombatFlush()
	end

	self.unitFrames = UF.frames
	self:ApplyUnitFrames()
	if self.ApplyStatusBarTextures then
		self:ApplyStatusBarTextures()
	end
	if self.ApplyFrameStyle then
		self:ApplyFrameStyle()
	end
	self:ApplyPlayerVehicleTransition()

	-- After reload init: defer one full GC once the frame tree has settled.
	-- Settings category is deferred a beat so Esc→Options still works without inflating the /reload peak.
	if self.RequestIdleCollect then
		C_Timer.After(0, function()
			if WhoaUF.RequestIdleCollect then
				WhoaUF:RequestIdleCollect(true)
			end
			C_Timer.After(2, function()
				if WhoaUF.RegisterOptions and not WhoaUF.settingsCategory then
					WhoaUF:RegisterOptions()
				end
			end)
		end)
	elseif self.RegisterOptions and not self.settingsCategory then
		C_Timer.After(2, function()
			if WhoaUF.RegisterOptions and not WhoaUF.settingsCategory then
				WhoaUF:RegisterOptions()
			end
		end)
	end
end

