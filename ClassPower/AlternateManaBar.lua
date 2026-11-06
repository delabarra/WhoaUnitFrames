--[[
	Alternate mana bar overlay on Whoa player frame (Wrath+).
	Primarily druids in forms; Mistweaver monks on MoP.
	Reference: reference/Blizzard_UnitFrame/Wrath|Mists/AlternatePowerBar.lua|.xml
]]

do
	if not WhoaUF:HasAlternateMana() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "DRUID" and playerClass ~= "MONK" then
		return
	end
end

local MANA_POWER_INDEX = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
-- Stock alt-mana border (Wrath/MoP). Distinct from raid-subgroup Media\shared\*\UI-GroupIndicator.
local GROUP_INDICATOR_CLIENT = "Interface\\CharacterFrame\\UI-CharacterFrame-GroupIndicator"
local MONK_MANA_BAR_CLIENT = "Interface\\PlayerFrame\\MonkManaBar"
local PLAYER_FRAME_TEXTURE_FALLBACK = "Interface\\TargetingFrame\\UI-TargetingFrame"

local function GetGroupIndicatorChromeTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(GROUP_INDICATOR_CLIENT)
	end
	return GROUP_INDICATOR_CLIENT
end

local function GetMonkManaBarTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(MONK_MANA_BAR_CLIENT)
	end
	return MONK_MANA_BAR_CLIENT
end
-- Default stacked slot when FRAME_STYLE_BARS.player.alternateMana is absent.
local STACKED_BAR_W, STACKED_BAR_H = 119, 12
local STACKED_BAR_X, STACKED_BAR_Y = 90, -67
-- Match ApplyBarTextToBar (Appearance.lua): text sits on the bar with same L/R insets as HP/mana.
local STACKED_TEXT_PAD = 5

local pendingAltManaShown


local function IsWrathOrLater()
	return WhoaUF:HasAlternateMana()
end

local function IsMists()
	return WhoaUF:HasMoPArt()
end

local function GetSpec()
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		return C_SpecializationInfo.GetSpecialization()
	end
	if GetSpecialization then
		return GetSpecialization()
	end
	return nil
end

local function GetPowerUnit()
	local player = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	return (player and player.unit) or "player"
end

local function GetPlayerClass()
	local _, class = UnitClass("player")
	return class
end

-- Blizzard AlternatePowerBar_SpecializationCheck: Mistweaver-only for monks.
local function SpecAllowed()
	local class = GetPlayerClass()
	if class ~= "MONK" then
		return true
	end
	local mist = SPEC_MONK_MISTWEAVER or 2
	return GetSpec() == mist
end

local function UseMonkLook()
	if not IsMists() then
		return false
	end
	local class = GetPlayerClass()
	if class ~= "MONK" then
		return false
	end
	local mist = SPEC_MONK_MISTWEAVER or 2
	return GetSpec() == mist
end

local function ApplyBarTexture(bar)
	local path
	if WhoaUF.GetStatusBarTexturePaths then
		local _, mana = WhoaUF:GetStatusBarTexturePaths()
		path = mana
	end
	bar:SetStatusBarTexture(path or "Interface\\TargetingFrame\\UI-StatusBar")
end

local function ApplyManaColor(bar)
	local info = WhoaUF:GetPowerBarColor("MANA")
	bar:SetStatusBarColor(info.r, info.g, info.b)
end

local function SetChromeLevel(bar)
	if bar.Chrome then
		bar.Chrome:SetFrameLevel(bar:GetFrameLevel() + 5)
	end
end

local function ShowDefaultChrome(bar)
	if bar.DefaultBackground then
		bar.DefaultBackground:Show()
	end
	if bar.WrathBorder then
		bar.WrathBorder:Show()
		if bar.DefaultBorder then
			bar.DefaultBorder:Hide()
		end
		if bar.DefaultBorderLeft then
			bar.DefaultBorderLeft:Hide()
		end
		if bar.DefaultBorderRight then
			bar.DefaultBorderRight:Hide()
		end
	else
		if bar.DefaultBorder then
			bar.DefaultBorder:Show()
		end
		if bar.DefaultBorderLeft then
			bar.DefaultBorderLeft:Show()
		end
		if bar.DefaultBorderRight then
			bar.DefaultBorderRight:Show()
		end
	end
	if bar.MonkBackground then
		bar.MonkBackground:Hide()
		bar.MonkBorder:Hide()
	end
end

local function ShowMonkChrome(bar)
	if bar.DefaultBackground then
		bar.DefaultBackground:Hide()
	end
	if bar.DefaultBorder then
		bar.DefaultBorder:Hide()
	end
	if bar.DefaultBorderLeft then
		bar.DefaultBorderLeft:Hide()
	end
	if bar.DefaultBorderRight then
		bar.DefaultBorderRight:Hide()
	end
	if bar.WrathBorder then
		bar.WrathBorder:Hide()
	end
	if bar.MonkBackground then
		bar.MonkBackground:Show()
		bar.MonkBorder:Show()
	end
end

local function HideAllChrome(bar)
	if bar.DefaultBackground then
		bar.DefaultBackground:Hide()
	end
	if bar.DefaultBorder then
		bar.DefaultBorder:Hide()
	end
	if bar.DefaultBorderLeft then
		bar.DefaultBorderLeft:Hide()
	end
	if bar.DefaultBorderRight then
		bar.DefaultBorderRight:Hide()
	end
	if bar.WrathBorder then
		bar.WrathBorder:Hide()
	end
	if bar.MonkBackground then
		bar.MonkBackground:Hide()
	end
	if bar.MonkBorder then
		bar.MonkBorder:Hide()
	end
	-- Entire chrome host off — GroupIndicator must not sit in the third-bar slot.
	if bar.Chrome then
		bar.Chrome:Hide()
	end
	if bar.StockText then
		bar.StockText:Hide()
	end
end

local function ShowChromeHost(bar)
	if bar.Chrome then
		bar.Chrome:Show()
	end
end

local function IsStackedStyle()
	if not WhoaUF.db or WhoaUF.db.altManaBarStyle == nil then
		return true
	end
	return WhoaUF.db.altManaBarStyle ~= "stock"
end

function WhoaUF:IsAlternateManaBarStackedStyle()
	return IsStackedStyle()
end

function WhoaUF:IsDruidStackedPlayerFrameActive(frame)
	local _, class = UnitClass("player")
	if class ~= "DRUID" then
		return false
	end
	if not self:IsAlternateManaBarShown() or not self:IsAlternateManaBarStackedStyle() then
		return false
	end
	frame = frame or (self.unitFrames and self.unitFrames.player)
	return frame and frame.kind == "player" and true or false
end

-- Third bar slot: fixed druid-frame row from FRAME_STYLE_BARS.player.alternateMana.
local function GetStackedBarGeometry()
	if WhoaUF.GetFrameBarLayout then
		local layout = WhoaUF:GetFrameBarLayout("player")
		local alt = layout and layout.alternateMana
		if alt then
			return alt.x or STACKED_BAR_X, alt.y or STACKED_BAR_Y, alt.width or STACKED_BAR_W, alt.height or STACKED_BAR_H
		end
	end
	return STACKED_BAR_X, STACKED_BAR_Y, STACKED_BAR_W, STACKED_BAR_H
end

local function CreateOverlayBarText(overlay, justify)
	local fs = overlay:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	if justify then
		fs:SetJustifyH(justify)
	end
	if WhoaUF.ApplyStatusBarTextFont then
		WhoaUF:ApplyStatusBarTextFont(fs)
	end
	return fs
end

-- Same numeric text path as HP/mana: Overlay layer on the Whoa player frame, anchored to this bar.
local function ApplyStackedBarText(bar, owner)
	local overlay = owner and owner.Overlay
	if not overlay then
		return
	end
	if not bar.StackedCenter then
		bar.StackedCenter = CreateOverlayBarText(overlay)
		bar.StackedLeft = CreateOverlayBarText(overlay, "LEFT")
		bar.StackedRight = CreateOverlayBarText(overlay, "RIGHT")
	end
	bar.StackedCenter:Show()
	bar.StackedLeft:Show()
	bar.StackedRight:Show()
	bar:SetBarText(bar.StackedCenter, bar.StackedLeft, bar.StackedRight)
	bar.TextString = bar.StackedCenter
	bar.LeftText = bar.StackedLeft
	bar.RightText = bar.StackedRight
	if WhoaUF.InstallStatusBarText then
		WhoaUF:InstallStatusBarText(bar)
	end
	if WhoaUF.ApplyBarTextToBar then
		WhoaUF:ApplyBarTextToBar(bar, STACKED_TEXT_PAD)
	else
		WhoaUF:UpdateBarTextString(bar)
	end
end

local function ApplyStockBarText(bar)
	if bar.StackedCenter then
		bar.StackedCenter:Hide()
		bar.StackedLeft:Hide()
		bar.StackedRight:Hide()
	end
	local text = bar.StockText
	if not text then
		return
	end
	text:Show()
	bar:SetBarText(text)
	bar.TextString = text
	bar.LeftText = nil
	bar.RightText = nil
	if WhoaUF.InstallStatusBarText then
		WhoaUF:InstallStatusBarText(bar)
	end
	WhoaUF:UpdateBarTextString(bar)
end

-- Stock PlayerFrameAlternateManaBar anchors (DefaultBarSize/Offset) vs Whoa SetLook() geometry:
--   Wrath/Cata AlternatePowerBar.xml → 78×12 at (114, 23), single GroupIndicator
--   Mists AlternatePowerBar.xml / MonkStaggerBar.xml → 104×12 at (96, 19), three-piece
--   SetLook() monk branch → 94×12 at (100, 0), MonkManaBar chrome
-- Stock bar stays on UIParent (combat-safe Show/Hide/SetPoint).
-- Stacked bar parents to the player frame so it shares Health/Power strata/level.
local function DefaultBarSize()
	if IsMists() then
		return 104, 12
	end
	return 78, 12
end

local function DefaultBarOffset()
	-- Exact PlayerFrameAlternateManaBar anchors from flavor XML.
	if IsMists() then
		return 96, 19 -- Mists/AlternatePowerBar.xml
	end
	return 114, 23 -- Wrath/AlternatePowerBar.xml (also Cata)
end

local function ApplyThreatFlashArt(owner, stackedActive)
	if not owner then
		return
	end
	if WhoaUF.ApplyPlayerThreatFlashArt then
		WhoaUF:ApplyPlayerThreatFlashArt(owner)
	end
end

-- Stacked style: show alt mana + swap player chrome only (HP/power stay on active frame style).
-- Pass stackedActive from SetLook() — it runs before SetBarShown, so IsDruidStackedPlayerFrameActive
-- (:IsShown) is still false and must not gate the druid rim swap here.
local function ApplyPlayerStackedFrameArt(owner, stackedActive)
	if not owner or not owner.FrameTexture then
		return
	end
	-- Vehicle art owns FrameTexture visibility; do not fight it.
	if WhoaUF.IsVehiclePlayerArtActive and WhoaUF:IsVehiclePlayerArtActive(owner) then
		return
	end
	-- DK sword border owns FrameTexture when dkPlayerArt is active.
	if owner.dkPlayerArt and WhoaUF.GetDeathKnightPlayerArt and WhoaUF:GetDeathKnightPlayerArt() ~= "off" then
		return
	end
	local _, class = UnitClass("player")
	local druidFrame = stackedActive and class == "DRUID" and owner.kind == "player"
	if druidFrame then
		if WhoaUF.ApplyDruidStackedPlayerFrameArt then
			WhoaUF:ApplyDruidStackedPlayerFrameArt(owner)
		elseif WhoaUF.GetDruidPlayerFrameTexture then
			owner.FrameTexture:SetTexture(WhoaUF:GetDruidPlayerFrameTexture())
			local layout = WhoaUF.GetPlayerFrameBorderLayout and WhoaUF:GetPlayerFrameBorderLayout()
			if layout then
				local c = layout.coords
				owner.FrameTexture:SetSize(layout.width, layout.height)
				owner.FrameTexture:ClearAllPoints()
				owner.FrameTexture:SetPoint("CENTER", layout.x, layout.y)
				owner.FrameTexture:SetTexCoord(c[1], c[2], c[3], c[4])
			end
			owner.FrameTexture:Show()
		end
	elseif WhoaUF.ApplyPlayerFrameBorderArt then
		WhoaUF:ApplyPlayerFrameBorderArt(owner)
	elseif WhoaUF.GetFrameTexture then
		owner.FrameTexture:SetTexture(WhoaUF:GetFrameTexture("player"))
	else
		owner.FrameTexture:SetTexture(PLAYER_FRAME_TEXTURE_FALLBACK)
	end
	-- Druid border + matching flash; bar geometry follows the active frame style.
	ApplyThreatFlashArt(owner, druidFrame)
end

-- Parent stacked bar to the player SecureUnitButton (same tree as Health/Power).
-- Stock strip stays on UIParent so form Show/Hide/SetPoint stay combat-safe.
local function ApplyBarParenting(bar, owner, stacked)
	if InCombatLockdown() then
		return
	end
	if stacked then
		if bar:GetParent() ~= owner then
			bar:SetParent(owner)
		end
		bar:SetFrameStrata(owner:GetFrameStrata())
		bar:SetFrameLevel(owner:GetFrameLevel())
	else
		if bar:GetParent() ~= UIParent then
			bar:SetParent(UIParent)
		end
		bar:SetFrameStrata("LOW")
		bar:SetFrameLevel(owner:GetFrameLevel() + 2)
	end
end

local function SetBarShown(bar, show)
	-- Protected StatusBar under SecureUnitButton: no Show/Hide in combat — alpha only.
	if InCombatLockdown() and bar:IsProtected() then
		pendingAltManaShown = show
		if bar:IsShown() then
			bar:SetAlpha(show and 1 or 0)
		end
		return
	end
	pendingAltManaShown = nil
	bar:SetAlpha(1)
	if show then
		bar:Show()
	else
		bar:Hide()
	end
end

local refreshVisibilityDepth = 0

local function ApplyAlternateManaBarAnchor(bar)
	local owner = bar.whoaUnitFrame
	if not owner then
		return
	end
	if InCombatLockdown() and bar:IsProtected() then
		return
	end
	local anchorFrame = WhoaUF.GetClassPowerAnchorFrame and WhoaUF:GetClassPowerAnchorFrame() or owner
	local stacked = IsStackedStyle()
	bar:ClearAllPoints()
	if stacked then
		local x, y, w, h = GetStackedBarGeometry()
		ApplyBarParenting(bar, owner, true)
		bar:SetSize(w, h)
		bar:SetPoint("TOPLEFT", owner, "TOPLEFT", x, y)
	else
		ApplyBarParenting(bar, owner, false)
		local monk = UseMonkLook()
		if monk then
			bar:SetSize(94, 12)
			bar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", 100, 0)
		else
			local w, h = DefaultBarSize()
			local x, y = DefaultBarOffset()
			bar:SetSize(w, h)
			bar:SetPoint("BOTTOMLEFT", anchorFrame, "BOTTOMLEFT", x, y)
		end
	end
	SetChromeLevel(bar)
end

local function SetLook(bar)
	local owner = bar.whoaUnitFrame
	if not owner then
		return
	end
	local stacked = IsStackedStyle()
	local locked = InCombatLockdown() and bar:IsProtected()
	if not locked then
		ApplyAlternateManaBarAnchor(bar)
	end
	if stacked then
		HideAllChrome(bar)
		ApplyStackedBarText(bar, owner)
		ApplyPlayerStackedFrameArt(owner, true)
	else
		ApplyPlayerStackedFrameArt(owner, false)
		ShowChromeHost(bar)
		ApplyStockBarText(bar)
		local monk = UseMonkLook()
		if monk then
			ShowMonkChrome(bar)
			if not locked then
				bar:SetFrameLevel(owner:GetFrameLevel() + 100)
			end
		else
			ShowDefaultChrome(bar)
			if not locked then
				-- FrameLevel above overlay chrome (+3), same as combo tray.
				local overlay = owner.Overlay
				local glowLevel = overlay and overlay:GetFrameLevel() or (owner:GetFrameLevel() + 3)
				local barLevel = owner:GetFrameLevel() + 2
				barLevel = math.max(barLevel, glowLevel + 1)
				bar:SetFrameLevel(barLevel)
			end
		end
		SetChromeLevel(bar)
	end
	-- Re-entrant SetLook: restack combo strata only (skip LayoutPlayerCombatGlow).
	if WhoaUF.ApplyComboPointPlayerBarStrata then
		WhoaUF:ApplyComboPointPlayerBarStrata(owner)
	end
end

local function UpdateValue(bar)
	local unit = GetPowerUnit()
	local maxMana = UnitPowerMax(unit, MANA_POWER_INDEX)
	local cur = UnitPower(unit, MANA_POWER_INDEX)
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(maxMana) then
		if maxMana < 1 then
			maxMana = 1
		end
	elseif maxMana == nil then
		maxMana = 1
	end
	bar:SetMinMaxValues(0, maxMana)
	bar:SetValue(cur)
	WhoaUF:UpdateBarTextString(bar)
end

local function ShouldShow()
	local class = GetPlayerClass()
	if class ~= "DRUID" and class ~= "MONK" then
		return false
	end
	if not SpecAllowed() then
		return false
	end
	if UnitHasVehiclePlayerFrameUI and UnitHasVehiclePlayerFrameUI("player") then
		return false
	end
	local unit = GetPowerUnit()
	local maxMana = UnitPowerMax(unit, MANA_POWER_INDEX)
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(maxMana) then
		if maxMana == 0 then
			return false
		end
	elseif maxMana == nil then
		return false
	end
	-- Hide when primary power is mana — do not stack a third bar on the mana bar.
	if UnitPowerType(unit) == MANA_POWER_INDEX then
		return false
	end
	return true
end

local function RefreshVisibility(bar)
	-- Re-entrant RefreshVisibility: anchor/look only (outer call runs bottom layout).
	local nested = refreshVisibilityDepth > 0
	refreshVisibilityDepth = refreshVisibilityDepth + 1
	local show = ShouldShow()
	if show then
		SetLook(bar)
		ApplyBarTexture(bar)
		ApplyManaColor(bar)
		UpdateValue(bar)
		SetBarShown(bar, true)
		-- Blizzard AlternatePowerBar uses OnUpdate for mana regen ticks.
		bar:SetScript("OnUpdate", function(self)
			UpdateValue(self)
		end)
	else
		bar:SetScript("OnUpdate", nil)
		SetBarShown(bar, false)
		if bar.StackedCenter then
			bar.StackedCenter:Hide()
			bar.StackedLeft:Hide()
			bar.StackedRight:Hide()
		end
		ApplyPlayerStackedFrameArt(bar.whoaUnitFrame, false)
		-- Hide path / re-entrant SetLook: restack combo strata without LayoutPlayerCombatGlow.
		if WhoaUF.ApplyComboPointPlayerBarStrata then
			WhoaUF:ApplyComboPointPlayerBarStrata(bar.whoaUnitFrame)
		end
	end
	if not nested then
		-- Player combo / pet stack share the under-frame slot; restack on show or style change.
		if WhoaUF.LayoutPlayerBottomFrames then
			WhoaUF:LayoutPlayerBottomFrames()
		end
		-- Combat/rest + threat glow layout; stock alt strip is raised above the flash host.
		if WhoaUF.LayoutPlayerCombatGlow then
			WhoaUF:LayoutPlayerCombatGlow()
		end
	end
	refreshVisibilityDepth = refreshVisibilityDepth - 1
end

function WhoaUF:IsAlternateManaBarShown()
	local bar = self.unitFrames and self.unitFrames.player and self.unitFrames.player.AlternateManaBar
	if not bar then
		return false
	end
	-- Stacked in combat: IsShown true but alpha 0 (no Show/Hide).
	return bar:IsShown() and bar:GetAlpha() > 0 and true or false
end

function WhoaUF:RefreshAlternateManaBar()
	local frame = self.unitFrames and self.unitFrames.player and self.unitFrames.player.AlternateManaBar
	if frame then
		RefreshVisibility(frame)
	end
end

function WhoaUF:SyncAlternateManaBarLayout(frame)
	if not IsStackedStyle() then
		return
	end
	frame = frame or (self.unitFrames and self.unitFrames.player)
	local bar = frame and frame.AlternateManaBar
	if not bar or not bar:IsShown() or bar:GetAlpha() <= 0 then
		return
	end
	ApplyAlternateManaBarAnchor(bar)
	ApplyStackedBarText(bar, frame)
end

function WhoaUF:AnchorAlternateManaBar()
	local bar = self.unitFrames and self.unitFrames.player and self.unitFrames.player.AlternateManaBar
	if not bar or not bar:IsShown() then
		return
	end
	ApplyAlternateManaBarAnchor(bar)
	if IsStackedStyle() then
		ApplyStackedBarText(bar, bar.whoaUnitFrame)
	end
end

function WhoaUF:InitAlternateManaBar(playerFrame)
	if not playerFrame or playerFrame.AlternateManaBar then
		return
	end
	if not IsWrathOrLater() then
		return
	end

	-- UIParent parent: form shifts call Show/Hide/SetPoint in combat; player SecureUnitButton children cannot.
	local bar = WhoaUF:CreateTextStatusBar(UIParent, "WhoaUFAlternateManaBar")
	bar.whoaUnitFrame = playerFrame
	local initW, initH = DefaultBarSize()
	local initX, initY = DefaultBarOffset()
	bar:SetSize(initW, initH)
	bar:SetPoint("BOTTOMLEFT", playerFrame, "BOTTOMLEFT", initX, initY)
	bar:SetFrameStrata("LOW")
	bar:SetFrameLevel(playerFrame:GetFrameLevel() + 2)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar:Hide()
	bar.unit = "player"
	bar.controlsShownState = false
	bar.textLockable = true
	bar.cvar = "statusText"
	bar.cvarLabel = "STATUS_TEXT_PLAYER"
	bar.lockShow = 0
	bar.capNumericDisplay = true
	if bar.EnableMouseMotion then
		bar:EnableMouseMotion(true)
	else
		bar:EnableMouse(false)
	end

	-- Background on the bar (under the fill).
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)
	bar.DefaultBackground = bg

	-- Border/text on a child frame so they draw above the StatusBar fill.
	local chrome = CreateFrame("Frame", nil, bar)
	chrome:SetAllPoints()
	bar.Chrome = chrome
	SetChromeLevel(bar)

	if IsMists() then
		-- MoP three-piece GroupIndicator border (Mists AlternatePowerBar.xml).
		local chromeTex = GetGroupIndicatorChromeTex()
		local border = chrome:CreateTexture(nil, "OVERLAY")
		border:SetTexture(chromeTex)
		border:SetHeight(16)
		border:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, 0)
		border:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -4, 0)
		border:SetTexCoord(0.125, 0.250, 1.0, 0.0)
		bar.DefaultBorder = border

		local borderLeft = chrome:CreateTexture(nil, "OVERLAY")
		borderLeft:SetTexture(chromeTex)
		borderLeft:SetSize(16, 16)
		borderLeft:SetPoint("RIGHT", border, "LEFT")
		borderLeft:SetTexCoord(0, 0.125, 1.0, 0.0)
		bar.DefaultBorderLeft = borderLeft

		local borderRight = chrome:CreateTexture(nil, "OVERLAY")
		borderRight:SetTexture(chromeTex)
		borderRight:SetSize(16, 16)
		borderRight:SetPoint("LEFT", border, "RIGHT")
		borderRight:SetTexCoord(0.125, 0, 1.0, 0.0)
		bar.DefaultBorderRight = borderRight

		local monkBg = bar:CreateTexture(nil, "BACKGROUND")
		monkBg:SetTexture(GetMonkManaBarTex())
		monkBg:SetSize(128, 16)
		monkBg:SetPoint("TOPLEFT", -17, 0)
		monkBg:SetTexCoord(0, 1, 0.5, 1)
		monkBg:SetVertexColor(0, 0, 0, 0.5)
		monkBg:Hide()
		bar.MonkBackground = monkBg

		local monkBorder = chrome:CreateTexture(nil, "OVERLAY")
		monkBorder:SetTexture(GetMonkManaBarTex())
		monkBorder:SetSize(128, 16)
		monkBorder:SetPoint("TOPLEFT", bar, "TOPLEFT", -17, 0)
		monkBorder:SetTexCoord(0, 1, 0, 0.5)
		monkBorder:Hide()
		bar.MonkBorder = monkBorder
	else
		-- Wrath/Cata single-piece border (Wrath AlternatePowerBar.xml).
		local wrathBorder = chrome:CreateTexture(nil, "OVERLAY")
		wrathBorder:SetTexture(GetGroupIndicatorChromeTex())
		wrathBorder:SetSize(97, 16)
		wrathBorder:SetPoint("TOPLEFT", bar, "TOPLEFT", -10, 0)
		wrathBorder:SetTexCoord(0.0234375, 0.6875, 1.0, 0.0)
		bar.WrathBorder = wrathBorder
	end

	local text = chrome:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	text:SetPoint("CENTER", bar, "CENTER")
	if WhoaUF.ApplyStatusBarTextFont then
		WhoaUF:ApplyStatusBarTextFont(text)
	end
	bar.StockText = text
	bar:SetBarText(text)
	ApplyBarTexture(bar)
	ApplyManaColor(bar)

	local function RegisterAlternateManaBarEvents(f)
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("UNIT_DISPLAYPOWER")
		f:RegisterEvent("UNIT_MAXPOWER")
		f:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
		f:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		f:RegisterEvent("PLAYER_REGEN_ENABLED")
		pcall(function()
			f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
		f:RegisterEvent("PLAYER_TALENT_UPDATE")
	end
	self.RegisterAlternateManaBarEvents = RegisterAlternateManaBarEvents
	RegisterAlternateManaBarEvents(bar)

	bar:SetScript("OnEvent", function(self, event, arg1)
		if event == "PLAYER_REGEN_ENABLED" then
			if pendingAltManaShown ~= nil then
				RefreshVisibility(self)
			end
			return
		end
		if event == "UNIT_MAXPOWER" and arg1 and arg1 ~= GetPowerUnit() then
			return
		end
		RefreshVisibility(self)
	end)

	playerFrame.AlternateManaBar = bar
	RefreshVisibility(bar)
end

function WhoaUF:ApplyAlternateManaBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local bar = player and player.AlternateManaBar
	if not bar then
		return
	end
	local chrome = GetGroupIndicatorChromeTex()
	if bar.DefaultBorder then
		bar.DefaultBorder:SetTexture(chrome)
	end
	if bar.DefaultBorderLeft then
		bar.DefaultBorderLeft:SetTexture(chrome)
	end
	if bar.DefaultBorderRight then
		bar.DefaultBorderRight:SetTexture(chrome)
	end
	if bar.WrathBorder then
		bar.WrathBorder:SetTexture(chrome)
	end
	local monk = GetMonkManaBarTex()
	if bar.MonkBackground then
		bar.MonkBackground:SetTexture(monk)
	end
	if bar.MonkBorder then
		bar.MonkBorder:SetTexture(monk)
	end
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = { DRUID = true, MONK = true },
		load = IsWrathOrLater,
		init = function(uf, player)
			uf:InitAlternateManaBar(player)
		end,
		refresh = function(uf)
			uf:RefreshAlternateManaBar()
		end,
		applyArt = function(uf)
			uf:ApplyAlternateManaBarArt()
		end,
		frameKey = "AlternateManaBar",
		registerEvents = "RegisterAlternateManaBarEvents",
		layout = {
			slot = "overlay",
			frameKey = "AlternateManaBar",
			anchor = "AnchorAlternateManaBar",
		},
	})
end
