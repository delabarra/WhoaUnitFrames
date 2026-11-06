--[[
	Pet frame under Whoa player + possession cast bar.
	Reference: reference/Blizzard_UnitFrame/Classic/PetFrame.xml, PetFrame.lua
	  PetCastingBarMixin — CastingBarFrameTemplate on "pet", shown only while possessed.
]]

local UF = WhoaUF._UF

local PET_TEXTURE = "Interface\\TargetingFrame\\UI-SmallTargetingFrame"
local PET_TEXTURE_NO_MANA = "Interface\\TargetingFrame\\UI-SmallTargetingFrame-NoMana"
-- Alpha fill behind the bars (PetFrame.xml): HP 69×8 @ 47,-22; mana under it @ -29.
-- With mana cover both slots (15); no-mana shrink to the HP slot only (8).
local PET_BG_W, PET_BG_H_MANA, PET_BG_H_NO_MANA = 69, 15, 8

local function GetPetFrameTexture(hasMana)
	if WhoaUF.GetFrameTexture then
		return WhoaUF:GetFrameTexture(hasMana and "pet" or "petNoMana")
	end
	return hasMana and PET_TEXTURE or PET_TEXTURE_NO_MANA
end

local function SyncPetBarBackground(frame, hasMana)
	local bg = frame and frame.Background
	if not bg then
		return
	end
	local width, height = PET_BG_W, hasMana and PET_BG_H_MANA or PET_BG_H_NO_MANA
	if WhoaUF.GetFrameBarLayout then
		local layout = WhoaUF:GetFrameBarLayout("pet")
		if layout then
			if hasMana and layout.background then
				width, height = layout.background.width, layout.background.height
			elseif not hasMana and layout.health then
				width, height = layout.health.width, layout.health.height
			end
		end
	end
	bg:SetSize(width, height)
end

function WhoaUF:SyncPetBarBackground(frame, hasMana)
	SyncPetBarBackground(frame, hasMana)
end

function WhoaUF:ApplyPetFrameArt(frame)
	frame = frame or (self.unitFrames and self.unitFrames.pet)
	if not frame or not frame.FrameTexture then
		return
	end
	local unit = frame.unit or "pet"
	local hasMana = true
	if UnitExists(unit) then
		local powerType = UnitPowerType(unit)
		local pmax = UnitPowerMax(unit, powerType)
		if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(pmax) then
			hasMana = pmax > 0
		else
			-- Secret max: leave mana chrome shown; UpdatePetPower fixes when readable.
			hasMana = true
		end
	elseif frame.Power and frame.Power.IsShown then
		hasMana = frame.Power:IsShown()
	end
	frame.FrameTexture:SetTexture(GetPetFrameTexture(hasMana))
	SyncPetBarBackground(frame, hasMana)
end

-- Pet dismiss: rely on *type2=togglemenu (SetupSecureUnitButton) so UnitPopup is
-- built from Blizzard SecureTemplates. Do not patch UnitPopupPetDismissButtonMixin
-- globally — that taints every pet-dismiss menu entry for the whole UI.

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

local function SetupPetStatusBar(bar, overlay, centerX, centerY, leftX, rightX)
	local texture
	if WhoaUF.GetStatusBarTexturePaths then
		texture = WhoaUF:GetStatusBarTexturePaths()
	end
	bar:SetStatusBarTexture(texture or "Interface\\TargetingFrame\\UI-StatusBar")
	bar.textLockable = true
	bar.cvar = "statusText"
	bar.cvarLabel = "STATUS_TEXT_PET"
	bar.lockShow = bar.lockShow or 0
	bar.capNumericDisplay = true
	bar.controlsShownState = false
	if bar.EnableMouseMotion then
		bar:EnableMouseMotion(true)
	else
		bar:EnableMouse(false)
	end

	-- Stock PetFrame.xml: center/left/right relative to frame TOPLEFT.
	local center = CreateBarFontString(overlay)
	center:SetPoint("CENTER", overlay, "TOPLEFT", centerX, centerY)

	local left = CreateBarFontString(overlay, "LEFT")
	left:SetPoint("LEFT", overlay, "TOPLEFT", leftX, centerY)

	local right = CreateBarFontString(overlay, "RIGHT")
	right:SetPoint("RIGHT", overlay, "TOPLEFT", rightX, centerY)

	bar:SetBarText(center, left, right)
	bar.TextString = center
	bar.LeftText = left
	bar.RightText = right
	if WhoaUF.InstallStatusBarText then
		WhoaUF:InstallStatusBarText(bar)
	end
	WhoaUF:UpdateBarTextString(bar)
end

-- Re-apply PetFrame.xml mana text anchors (ApplyBarTextToBar would pull them onto the bar).
-- BOTH left/right sit on the 69px fill edges (stock was 46 / 113).
function WhoaUF:ApplyPetPowerTextStock(frame)
	local power = frame and frame.Power
	if not power then
		return
	end
	local y = -38
	if self.GetStatusBarFontTextOffset then
		y = y + self:GetStatusBarFontTextOffset()
	end
	if power.TextString then
		power.TextString:ClearAllPoints()
		power.TextString:SetPoint("CENTER", frame, "TOPLEFT", 82, y)
	end
	if power.LeftText then
		power.LeftText:ClearAllPoints()
		power.LeftText:SetPoint("LEFT", frame, "TOPLEFT", 47, y)
	end
	if power.RightText then
		power.RightText:ClearAllPoints()
		power.RightText:SetPoint("RIGHT", frame, "TOPLEFT", 115, y)
	end
end

local function UpdatePetHappiness(frame)
	local happinessFrame = frame.Happiness
	if not happinessFrame then
		return
	end

	if not GetPetHappiness or not HasPetUI then
		happinessFrame:Hide()
		return
	end

	local happiness, damagePercentage, loyaltyRate = GetPetHappiness()
	local hasPetUI, isHunterPet = HasPetUI()
	if not happiness or not isHunterPet then
		happinessFrame:Hide()
		return
	end

	happinessFrame:Show()
	local tex = happinessFrame.Texture
	if happiness == 1 then
		tex:SetTexCoord(0.375, 0.5625, 0, 0.359375)
	elseif happiness == 2 then
		tex:SetTexCoord(0.1875, 0.375, 0, 0.359375)
	else
		tex:SetTexCoord(0, 0.1875, 0, 0.359375)
	end

	happinessFrame.tooltip = _G["PET_HAPPINESS" .. happiness]
	if PET_DAMAGE_PERCENTAGE and damagePercentage then
		happinessFrame.tooltipDamage = format(PET_DAMAGE_PERCENTAGE, damagePercentage)
	else
		happinessFrame.tooltipDamage = nil
	end

	if loyaltyRate and loyaltyRate < 0 then
		happinessFrame.tooltipLoyalty = _G["LOSING_LOYALTY"]
	elseif loyaltyRate and loyaltyRate > 0 then
		happinessFrame.tooltipLoyalty = _G["GAINING_LOYALTY"]
	else
		happinessFrame.tooltipLoyalty = nil
	end
end

local function UpdatePetPower(frame)
	local unit = frame.unit
	local bar = frame.Power
	if not bar then
		return
	end
	local powerType, powerToken, altR, altG, altB = UnitPowerType(unit)
	local max = UnitPowerMax(unit, powerType)
	local cur = UnitPower(unit, powerType)
	local maxAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(max)

	-- No-resource pets (Blizzard PetFrame NoMana chrome). Clear paint flags so
	-- ApplyUnitStatusOverlay → SetPowerBarShownForStatus cannot re-show an empty bar.
	if maxAccessible and max == 0 then
		frame.FrameTexture:SetTexture(GetPetFrameTexture(false))
		SyncPetBarBackground(frame, false)
		bar.pauseUpdates = true
		bar.forceHideText = true
		bar.whoaPowerPainted = nil
		bar.currValue = nil
		bar.whoaFrequentMax = 0
		bar.whoaPowerUnit = nil
		if UF.SetUnitPowerBarVisible then
			UF.SetUnitPowerBarVisible(frame, false)
		else
			bar:Hide()
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
		return
	end

	frame.FrameTexture:SetTexture(GetPetFrameTexture(true))
	SyncPetBarBackground(frame, true)
	bar.pauseUpdates = false
	bar.forceHideText = false
	bar.unit = unit
	bar.whoaPowerUnit = unit
	bar.powerType = powerType
	bar.powerToken = powerToken
	-- Pet skips retarget alpha-hold; clear flag so Show can reveal power.
	bar.whoaPowerHoldReveal = nil
	bar.showPercentage = false
	local tokenOk = powerToken ~= nil and WhoaUF:CanAccessValue(powerToken)
	if tokenOk and (powerToken == "RAGE" or powerToken == "RUNIC_POWER") then
		bar.zeroText = ""
	else
		bar.zeroText = nil
	end

	-- Always pass alpha 1 — a prior transparent reset must not stick on 3-arg color.
	if not bar.lockColor then
		local tokenInfo = tokenOk and WhoaUF.PowerBarColor and WhoaUF.PowerBarColor[powerToken]
		if tokenInfo then
			bar:SetStatusBarColor(tokenInfo.r, tokenInfo.g, tokenInfo.b, 1)
		elseif altR then
			bar:SetStatusBarColor(altR, altG, altB, 1)
		else
			local info = WhoaUF:GetPowerBarColor(powerToken, powerType)
			bar:SetStatusBarColor(info.r, info.g, info.b, 1)
		end
	end

	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	bar.currValue = cur
	bar.whoaFrequentMax = max
	-- Required: ApplyUnitStatusOverlay runs after UpdatePetPower and will hide any
	-- bar that is neither whoaPowerPainted nor has currValue (unpainted fill guard).
	if not maxAccessible or max > 0 then
		bar.whoaPowerPainted = true
	end
	if UF.SetUnitPowerBarVisible then
		UF.SetUnitPowerBarVisible(frame, true)
	else
		bar:Show()
	end
	WhoaUF:UpdateBarTextString(bar)
end

local function UpdatePetHealth(frame)
	local unit = frame.unit
	local bar = frame.Health
	local max = UnitHealthMax(unit)
	local cur = UnitHealth(unit)
	local maxAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(max)

	bar.showNumeric = false
	if GetClassicExpansionLevel and LE_EXPANSION_BURNING_CRUSADE
		and GetClassicExpansionLevel() <= LE_EXPANSION_BURNING_CRUSADE then
		bar.showPercentage = false
	end

	bar.forceHideText = false
	if maxAccessible and max == 0 then
		max = 1
		bar.forceHideText = true
	end
	-- Do not force showPercentage from ShouldKnowUnitHealth (stock authenticity).
	-- Absolute NPC HP comes from UnitHealthMax; max==100 stays client-scaled.

	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	bar.whoaFrequentMax = max
	if WhoaUF.ApplyHealthBarColor then
		WhoaUF:ApplyHealthBarColor(bar, unit)
	else
		bar:SetStatusBarColor(0, 1, 0)
	end
	WhoaUF:UpdateBarTextString(bar)
	if WhoaUF.UpdateHealPrediction then
		WhoaUF:UpdateHealPrediction(frame)
	end
end

function WhoaUF:UpdatePetFrame()
	local frame = self.unitFrames and self.unitFrames.pet
	if not frame or not frame:IsShown() then
		return
	end

	local unit = frame.unit or "pet"
	-- Secure pet pin can remain shown under combat lockdown after dismiss/death
	-- while UnitExists is already false. Do not wipe name/portrait/bars here —
	-- ApplyPetFrameVisibility (or pending REGEN flush) owns hide + clear.
	if not UnitExists(unit) then
		if self.ApplyPetFrameVisibility then
			self:ApplyPetFrameVisibility()
		end
		-- Combat: SetShown is blocked. Fade the pin so it does not look like a
		-- living empty frame; REGEN flush will Hide + ClearUnitFrameVisuals.
		if InCombatLockdown() and frame:IsShown() then
			if frame:GetAlpha() ~= 0 then
				frame:SetAlpha(0)
			end
			if UF.SetSecureMouseEnabled then
				UF.SetSecureMouseEnabled(frame, false)
			end
		end
		return
	end

	if frame:GetAlpha() ~= 1 then
		frame:SetAlpha(1)
	end
	if UF.SetSecureMouseEnabled then
		UF.SetSecureMouseEnabled(frame, true)
	elseif frame.EnableMouse and not InCombatLockdown() then
		frame:EnableMouse(true)
	end

	frame.Name:SetText(UnitName(unit) or "")
	if WhoaUF._UF and WhoaUF._UF.UpdatePortrait then
		WhoaUF._UF.UpdatePortrait(frame, unit)
	else
		SetPortraitTexture(frame.Portrait, unit)
	end
	UpdatePetHealth(frame)
	UpdatePetPower(frame)
	UpdatePetHappiness(frame)
	-- Dead pet: grey portrait + hide power (Blizzard UnitFrame path). No DeadText
	-- on stock PetFrame — empty HP bar is intentional.
	if UF.ApplyUnitStatusOverlay and UF.GetUnitLifeStatus then
		local status = UF.GetUnitLifeStatus(unit)
		UF.ApplyUnitStatusOverlay(frame, status)
		if not status and frame.Portrait then
			frame.Portrait:SetVertexColor(1, 1, 1)
		end
	end
end

-- Mirror PetFrameMixin:UpdateShownState (Classic/PetFrame.lua):
--   SetShown(UnitIsVisible(unit) and PetUsesPetFrame() and not vehicleHidesPet)
-- Do not force-show just because vehicle art set unit to "player" — many vehicles
-- (e.g. Darkmoon carousel) keep vehicleHidesPet false but PetUsesPetFrame() false.
-- Mirror PetFrame GetPoint using EditMode_*.lua captured pet anchor (skip LayoutPlayerBottomFrames).
function WhoaUF:SyncEditModePetPosition()
	local pet = self.unitFrames and self.unitFrames.pet
	if not pet or not self.editModePreviewActive or not PetFrame then
		return
	end
	if InCombatLockdown() then
		return
	end

	local anchor = self.CaptureEditModeLayoutAnchor and self:CaptureEditModeLayoutAnchor("pet", PetFrame)
	if not anchor and PetFrame:GetNumPoints() > 0 then
		local point, relativeTo, relativePoint, x, y = PetFrame:GetPoint(1)
		if point then
			local relativeName = "UIParent"
			if relativeTo == PlayerFrame then
				relativeName = "PlayerFrame"
			elseif relativeTo and relativeTo.GetName then
				relativeName = relativeTo:GetName() or "UIParent"
			end
			anchor = {
				point = point,
				relativeTo = relativeName,
				relativePoint = relativePoint or point,
				x = x or 0,
				y = y or 0,
			}
		end
	end
	if not anchor then
		return
	end

	local relativeTo = self.ResolveEditModeRelativeFrame
		and self:ResolveEditModeRelativeFrame(anchor.relativeTo)
		or UIParent
	pet:ClearAllPoints()
	pet:SetPoint(
		anchor.point or "TOPLEFT",
		relativeTo,
		anchor.relativePoint or anchor.point or "TOPLEFT",
		anchor.x or 0,
		anchor.y or 0
	)
end

-- Mirror PetFrameMixin:OnShow/Update — not fabricated 1/1 bar placeholders.
function WhoaUF:ApplyEditModePetPreviewUpdate(frame)
	if not frame then
		return
	end

	local unit = frame.unit or "pet"
	if UnitExists(unit) then
		self:UpdatePetFrame()
		return
	end

	-- PetFrameMixin:Update() when the slot is shown without a visible pet.
	local powerMax = UnitPowerMax(unit)
	local powerMaxAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(powerMax)
	if frame.FrameTexture then
		if powerMaxAccessible and powerMax == 0 then
			frame.FrameTexture:SetTexture(GetPetFrameTexture(false))
			if frame.Power then
				if frame.Power.TextString then
					frame.Power.TextString:Hide()
				end
				if frame.Power.LeftText then
					frame.Power.LeftText:Hide()
				end
				if frame.Power.RightText then
					frame.Power.RightText:Hide()
				end
			end
		else
			frame.FrameTexture:SetTexture(GetPetFrameTexture(true))
		end
	end
	if frame.AttackMode then
		frame.AttackMode:Hide()
	end
	UpdatePetHappiness(frame)

	if frame.Name then
		frame.Name:SetText("")
	end
	if frame.Portrait then
		if WhoaUF._UF and WhoaUF._UF.UpdatePortrait then
			WhoaUF._UF.UpdatePortrait(frame, unit)
		else
			SetPortraitTexture(frame.Portrait, unit)
		end
	end

	local healthMax = UnitHealthMax(unit)
	local healthMaxAccessible = WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(healthMax)
	if frame.Health then
		if not healthMaxAccessible or healthMax > 0 then
			frame.Health:SetMinMaxValues(0, healthMax)
			frame.Health:SetValue(UnitHealth(unit))
		else
			frame.Health:SetMinMaxValues(0, 1)
			frame.Health:SetValue(0)
		end
		if frame.Health.TextString then
			frame.Health.TextString:Show()
		end
		WhoaUF:UpdateBarTextString(frame.Health)
	end

	if frame.Power and (not powerMaxAccessible or powerMax > 0) then
		frame.Power:SetMinMaxValues(0, powerMax)
		frame.Power:SetValue(UnitPower(unit))
		if frame.Power.TextString then
			frame.Power.TextString:Show()
		end
		WhoaUF:UpdateBarTextString(frame.Power)
	elseif frame.Power then
		frame.Power:SetMinMaxValues(0, 1)
		frame.Power:SetValue(0)
	end
end

function WhoaUF:ApplyPetFrameVisibility()
	local frame = self.unitFrames and self.unitFrames.pet
	if not frame then
		return
	end
	if InCombatLockdown() then
		-- Secure SetShown is blocked; defer until REGEN (UnitFrameCombatFlush).
		UF.pendingPetVisibility = true
		return
	end
	UF.pendingPetVisibility = nil

	local enabled = self.db and self.db.enabled
	local player = self.unitFrames.player
	local hidesPet = player and player.vehicleHidesPet

	-- Unit watch fights manual SetShown; Blizzard drives visibility from UpdateShownState.
	UnregisterUnitWatch(frame)

	local wasShown = frame:IsShown()

	if not enabled then
		frame:Hide()
		if self.LayoutPlayerBottomFrames then
			self:LayoutPlayerBottomFrames()
		end
		if wasShown and self.RequestIdleCollect then
			self:RequestIdleCollect()
		end
		return
	end

	local unit = frame.unit or "pet"
	local force = self.IsForceShowFrame and self:IsForceShowFrame("pet")
	local usesPetFrame = true
	if PetUsesPetFrame then
		usesPetFrame = PetUsesPetFrame() and true or false
	end
	-- Edit Mode pet preview is owned by ApplyEditModePreviewVisibility (EditMode_*.lua).
	if self.editModePreviewActive then
		return
	end
	-- Mirror PetFrameMixin:UpdateShownState — UnitIsVisible (dead pets near you stay).
	local shouldShow = force or (UnitIsVisible(unit) and usesPetFrame and not hidesPet)
	frame:SetShown(shouldShow)
	if shouldShow then
		if frame:GetAlpha() ~= 1 then
			frame:SetAlpha(1)
		end
		if frame.EnableMouse then
			frame:EnableMouse(true)
		end
	else
		-- Reset combat fade so the next summon is fully visible.
		if frame:GetAlpha() ~= 1 then
			frame:SetAlpha(1)
		end
		if frame.EnableMouse then
			frame:EnableMouse(true)
		end
	end
	if force and self.ApplyForceShowPlaceholder then
		self:ApplyForceShowPlaceholder(frame)
	elseif shouldShow and UnitExists(unit) and self.UpdatePetFrame then
		self:UpdatePetFrame()
	elseif not shouldShow then
		-- Clear visuals only after Hide succeeds — not while combat left pin shown.
		if UF.ClearUnitFrameVisuals then
			UF.ClearUnitFrameVisuals(frame)
		end
	end

	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end

	-- Pet just hid: RequestIdleCollect drops pet UI allocations.
	if wasShown and not shouldShow and self.RequestIdleCollect then
		self:RequestIdleCollect()
	end
end

-- Pet is parented under the player; Elite / Rare Elite chrome is larger and hangs
-- below the rim. Keep the pet above player Overlay (+3) so that border never
-- covers the pet portrait. Class power uses overlay+5 and stays on top.
-- Skip when already correct — repeated SetFrameLevel churn ramps addon memory.
-- When the button level does change, re-pin Health/Power/Overlay so threat flash
-- (BACKGROUND on the button) stays under chrome like the player flash.
function WhoaUF:ApplyPetFrameLevel(frame, player)
	frame = frame or (self.unitFrames and self.unitFrames.pet)
	player = player or (self.unitFrames and self.unitFrames.player)
	if not frame or not player then
		return
	end
	local base = player:GetFrameLevel() or 0
	local playerOverlay = player.Overlay
	if playerOverlay then
		base = math.max(base, playerOverlay:GetFrameLevel() or 0)
	end
	local level = base + 1
	if frame:GetFrameLevel() ~= level then
		frame:SetFrameLevel(level)
	end
	-- Relative child levels can drift; only SetFrameLevel when wrong (no churn).
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

function WhoaUF:LayoutPlayerBottomFrames()
	local player = self.unitFrames and self.unitFrames.player
	if not player then
		return
	end
	-- Pet is SecureUnitButton — never ClearAllPoints/SetPoint under lockdown.
	if InCombatLockdown() then
		return
	end

	-- Blizzard PlayerFrameBottomManagedFramesContainer (VerticalLayoutFrame, spacing 2):
	-- class resource → pet → totems. Only this character's registered bars exist.
	local pet = self.unitFrames.pet
	local spacing = 2
	local stack
	if self.LayoutPlayerClassBars then
		stack = self:LayoutPlayerClassBars(player, nil, spacing)
	end
	-- PetFrame layoutIndex 48: under class power when that bar is actually shown.
	-- Vertical: stack below class bar. Horizontal: always container center (Player BOTTOM
	-- x=10) — do not inherit shard/rune TOP center (shards are left-padded).
	if pet then
		self:ApplyPetFrameLevel(pet, player)
		if not self.editModePreviewActive then
			pet:ClearAllPoints()
			if not stack then
				local containerX = 10
				local containerY = 36
				pet:SetPoint("TOP", player, "BOTTOM", containerX, containerY)
			else
				local containerX = 10
				local petWidth = pet:GetWidth() or 128
				local playerWidth = player:GetWidth() or 232
				local petLeft = (playerWidth * 0.5) + containerX - (petWidth * 0.5)
				pet:SetPoint("LEFT", player, "BOTTOMLEFT", petLeft, 0)
				-- Mirror VerticalLayoutFrame child bottomPadding (e.g. Monk -10, Priest -20).
				local bottomPad = stack.whoaBottomPadding or 0
				pet:SetPoint("TOP", stack, "BOTTOM", 0, -spacing - bottomPad)
			end
		end
		if pet:IsShown() then
			stack = pet
		end
	end

	if self.AnchorTotemFrame then
		self:AnchorTotemFrame(stack, spacing)
	end
end

local function CreatePetVisual(playerFrame)
	local frame = CreateFrame("Button", "WhoaUFPetFrame", playerFrame, "SecureUnitButtonTemplate")
	frame:SetSize(128, 53)
	frame:SetFrameStrata("LOW")
	frame.unit = "pet"
	frame.kind = "pet"
	frame:SetHitRectInsets(7, 66, 6, 7)
	-- Raise above player Overlay before children so their +N levels stay correct.
	WhoaUF:ApplyPetFrameLevel(frame, playerFrame)

	SecureUnitButton_OnLoad(frame, "pet")
	frame:SetAttribute("*type2", "togglemenu")
	frame:SetAttribute("menu-function", nil)
	if UnitFrame_OnEnter and UnitFrame_OnLeave then
		frame:SetScript("OnEnter", UnitFrame_OnEnter)
		frame:SetScript("OnLeave", UnitFrame_OnLeave)
	end

	local flash = frame:CreateTexture(nil, "BACKGROUND")
	flash:SetSize(128, 64)
	flash:SetPoint("TOPLEFT", -4, 11)
	flash:SetTexture("Interface\\TargetingFrame\\UI-PartyFrame-Flash")
	flash:SetTexCoord(0, 1, 1, 0)
	flash:Hide()
	frame.Flash = flash

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetSize(69, 15)
	background:SetPoint("TOPLEFT", 47, -22)
	background:SetColorTexture(0, 0, 0, 0.5)
	frame.Background = background

	local portrait = frame:CreateTexture(nil, "BACKGROUND")
	portrait:SetSize(37, 37)
	portrait:SetPoint("TOPLEFT", 7, -6)
	frame.Portrait = portrait

	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(frame:GetFrameLevel() + 3)
	frame.Overlay = overlay

	local texture = overlay:CreateTexture(nil, "BORDER")
	texture:SetSize(128, 64)
	texture:SetPoint("TOPLEFT", 0, -2)
	texture:SetTexture(GetPetFrameTexture(true))
	frame.FrameTexture = texture

	local nameText = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	nameText:SetJustifyH("LEFT")
	nameText:SetSize(64, 12)
	nameText:SetPoint("BOTTOMLEFT", 52, 33)
	if nameText.SetWordWrap then
		nameText:SetWordWrap(false)
	end
	frame.Name = nameText

	local attack = overlay:CreateTexture(nil, "ARTWORK")
	attack:SetSize(76, 64)
	attack:SetPoint("TOPLEFT", 6, -9)
	attack:SetTexture("Interface\\TargetingFrame\\UI-Player-AttackStatus")
	attack:SetTexCoord(0.703125, 1, 0, 1)
	attack:SetBlendMode("ADD")
	attack:Hide()
	frame.AttackMode = attack

	local petBars = WhoaUF.GetFrameBarLayout and WhoaUF:GetFrameBarLayout("pet")
	local healthGeom = petBars and petBars.health
	local powerGeom = petBars and petBars.power
	local health = UF.CreateTextStatusBar(frame, "WhoaUFPetFrameHealth")
	health:SetSize(healthGeom and healthGeom.width or 69, healthGeom and healthGeom.height or 8)
	health:SetPoint(
		healthGeom and healthGeom.point or "TOPLEFT",
		healthGeom and healthGeom.x or 47,
		healthGeom and healthGeom.y or -22
	)
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	health:SetStatusBarColor(0, 1, 0)
	-- Above parent BACKGROUND (black fill / portrait); below overlay chrome (+3).
	health:SetFrameLevel(frame:GetFrameLevel() + 1)
	SetupPetStatusBar(health, overlay, 82, -26, 47, 115)
	frame.Health = health
	if WhoaUF._UF.ArmFrequentHealthBar then
		WhoaUF._UF.ArmFrequentHealthBar(health, frame)
	end

	local power = UF.CreateTextStatusBar(frame, "WhoaUFPetFramePower")
	power:SetSize(powerGeom and powerGeom.width or 69, powerGeom and powerGeom.height or 8)
	power:SetPoint(
		powerGeom and powerGeom.point or "TOPLEFT",
		powerGeom and powerGeom.x or 47,
		powerGeom and powerGeom.y or -29
	)
	power:SetMinMaxValues(0, 1)
	power:SetValue(1)
	local mana = WhoaUF:GetPowerBarColor("MANA")
	power:SetStatusBarColor(mana.r, mana.g, mana.b)
	power:SetFrameLevel(frame:GetFrameLevel() + 1)
	SetupPetStatusBar(power, overlay, 82, -38, 47, 115)
	power.unit = "pet"
	frame.Power = power
	if WhoaUF._UF.ArmFrequentPowerBar then
		WhoaUF._UF.ArmFrequentPowerBar(power, frame)
	end

	if WhoaUF.ApplyFrameBarLayout then
		WhoaUF:ApplyFrameBarLayout(frame)
	end
	WhoaUF:ApplyPetPowerTextStock(frame)

	local happiness = CreateFrame("Frame", nil, frame)
	happiness:SetSize(24, 23)
	happiness:SetPoint("LEFT", frame, "RIGHT", -7, -4)
	happiness:EnableMouse(true)
	local happinessTex = happiness:CreateTexture(nil, "BACKGROUND")
	happinessTex:SetAllPoints()
	happinessTex:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
	happinessTex:SetTexCoord(0, 0.1875, 0, 0.359375)
	happiness.Texture = happinessTex
	happiness:SetScript("OnEnter", function(self)
		if not self.tooltip then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tooltip)
		if self.tooltipDamage then
			GameTooltip:AddLine(self.tooltipDamage, 1, 1, 1)
		end
		if self.tooltipLoyalty then
			GameTooltip:AddLine(self.tooltipLoyalty, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	happiness:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	happiness:Hide()
	frame.Happiness = happiness

	frame.attackModeCounter = 0
	frame.attackModeSign = -1
	-- Pulse on UIParent — do not SetScript OnUpdate on SecureUnitButton.
	-- OnUpdate only while AttackMode is shown (PET_ATTACK_START/STOP).
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

	frame:Hide()
	return frame
end

-- Mirror PetCastingBarMixin:OnEvent (PetFrame.lua).
local function PetCastingBar_OnEvent(self, event, ...)
	local arg1 = ...
	if event == "UNIT_PET" then
		if arg1 == "player" then
			self.showCastbar = UnitIsPossessed("pet")
			if not self.showCastbar then
				self:Hide()
			elseif self.casting or self.channeling then
				self:Show()
			end
		end
		return
	end
	CastingBarMixin.OnEvent(self, event, ...)
end

-- Mirror PetCastingBarFrame (PetFrame.xml) + PetCastingBarMixin:OnLoad.
function WhoaUF:InitPetCastingBar()
	if self.petCastingBar then
		return self.petCastingBar
	end

	local bar = CreateFrame("StatusBar", "WhoaUFPetCastingBarFrame", UIParent, "CastingBarFrameTemplate")
	bar:SetSize(195, 13)
	bar:SetToplevel(true)
	bar:Hide()

	-- Template OnLoad ran with nil unit; re-init like PetCastingBarMixin.
	CastingBarMixin.OnLoad(bar, "pet", false, false)
	if bar.Icon then
		bar.Icon:Hide()
	end
	bar:RegisterEvent("UNIT_PET")
	bar.showCastbar = UnitIsPossessed("pet")
	bar:SetScript("OnEvent", PetCastingBar_OnEvent)

	-- Stock: BOTTOM of PlayerCastingBarFrame TOP (0, 12). Leave player cast bar alone.
	if PlayerCastingBarFrame then
		bar:ClearAllPoints()
		bar:SetPoint("BOTTOM", PlayerCastingBarFrame, "TOP", 0, 12)
	end

	self.petCastingBar = bar
	return bar
end

function WhoaUF:InitPetFrame(playerFrame)
	if not playerFrame then
		return nil
	end

	local frame = CreatePetVisual(playerFrame)
	self:InitPetCastingBar()

	local watcher = CreateFrame("Frame")
	local function RegisterPetWatcherEvents(w)
		-- Blizzard PetFrameMixin:OnLoad — UNIT_PET filtered to player.
		w:RegisterUnitEvent("UNIT_PET", "player")
		w:RegisterEvent("PET_ATTACK_START")
		w:RegisterEvent("PET_ATTACK_STOP")
		w:RegisterEvent("PET_UI_UPDATE")
		pcall(function()
			w:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
		end)
		local function RegisterPetUnitEvent(event)
			w:RegisterUnitEvent(event, "pet", "vehicle")
		end
		RegisterPetUnitEvent("UNIT_HEALTH")
		pcall(function()
			RegisterPetUnitEvent("UNIT_HEALTH_FREQUENT")
		end)
		RegisterPetUnitEvent("UNIT_MAXHEALTH")
		RegisterPetUnitEvent("UNIT_POWER_UPDATE")
		pcall(function()
			RegisterPetUnitEvent("UNIT_POWER_FREQUENT")
		end)
		RegisterPetUnitEvent("UNIT_MAXPOWER")
		RegisterPetUnitEvent("UNIT_DISPLAYPOWER")
		RegisterPetUnitEvent("UNIT_PORTRAIT_UPDATE")
		RegisterPetUnitEvent("UNIT_NAME_UPDATE")
		pcall(function()
			RegisterPetUnitEvent("UNIT_CONNECTION")
		end)
		pcall(function()
			w:RegisterUnitEvent("UNIT_HAPPINESS", "pet")
		end)
		w:RegisterEvent("CVAR_UPDATE")
	end
	self.RegisterPetWatcherEvents = RegisterPetWatcherEvents
	RegisterPetWatcherEvents(watcher)
	self.petWatcher = watcher
	watcher:SetScript("OnEvent", function(_, event, unit)
		if event == "PET_ATTACK_START" then
			frame.AttackMode:SetVertexColor(1, 1, 1, 1)
			frame.AttackMode:Show()
			local pulse = frame.attackPulse
			if pulse and not pulse.whoaActive then
				pulse:SetScript("OnUpdate", pulse.OnUpdate)
				pulse.whoaActive = true
			end
			return
		end
		if event == "PET_ATTACK_STOP" then
			frame.AttackMode:Hide()
			local pulse = frame.attackPulse
			if pulse and pulse.whoaActive then
				pulse:SetScript("OnUpdate", nil)
				pulse.whoaActive = false
			end
			return
		end
		if event == "CVAR_UPDATE" then
			if unit == "statusText" or unit == "statusTextDisplay" then
				WhoaUF:UpdatePetFrame()
			end
			return
		end
		-- Mirror PetFrameMixin:OnEvent — UNIT_PET / EXITED_VEHICLE / PET_UI_UPDATE.
		if event == "UNIT_PET" or event == "PET_UI_UPDATE" or event == "UNIT_EXITED_VEHICLE" then
			-- While vehicle art is up, pet displays the player — don't snap back to "pet".
			local player = WhoaUF.unitFrames and WhoaUF.unitFrames.player
			if not (player and player.state == "vehicle") then
				if not InCombatLockdown() then
					frame.unit = "pet"
					frame.Health.unit = "pet"
					frame.Power.unit = "pet"
					frame:SetAttribute("unit", "pet")
				end
			end
			WhoaUF:ApplyPetFrameVisibility()
			if not InCombatLockdown() then
				WhoaUF:LayoutPlayerBottomFrames()
			end
			-- Paint while UnitExists (dead hunter pet near you still counts).
			-- When gone, still UpdatePetFrame so combat can alpha-fade the pin
			-- without wiping bars (UpdatePetFrame skips ClearUnitFrameVisuals when !UnitExists).
			WhoaUF:UpdatePetFrame()
			return
		end
		if unit == frame.unit or event == "UNIT_HAPPINESS" then
			WhoaUF:UpdatePetFrame()
		end
	end)

	return frame
end
