--[[
	Edit Mode (Mainline): claim NO UnitFrame Edit Mode slots. Registering Whoa
	frames Mixins EditModeUnitFrameSystemMixin; Blizzard UpdateSystems →
	secureexecuterange then runs Whoa-tainted UpdateSystem methods in the same
	pass as Party/Raid, so CompactParty RefreshMembers fails secret oldR compares
	as "tainted by WhoaUnitFrames" (also poisons later CUFProfiles / OnEvent
	paths via object taint).

	CRITICAL: never call EditModeManagerFrame methods (`:GetActiveLayoutSystemInfo`,
	`:ArePartyFramesForcedShown`, `:IsEditModeActive`, `:UpdateSystems`, …).
	Method calls object-taint the manager; CompactPartyFrame:RefreshMembers then
	does EditModeManagerFrame:ArePartyFramesForcedShown() and inherits Whoa taint
	into CompactUnitFrame_UpdateHealthColor (secret oldR). Read layout/account
	fields only (mirror EditModeManager.lua). Never call global ShouldShowPartyFrames
	(it calls ArePartyFramesForcedShown).

	Never write EditModeManagerFrame.registeredSystemFrames. table.remove shifts
	every later entry (PartyFrame, CompactRaidFrameContainer, …) into
	Whoa-written slots; UpdateSystems then runs their UpdateSystem tainted, which
	stores tainted state that CompactParty RefreshMembers reads on
	GROUP_ROSTER_UPDATE → CompactUnitFrame_UpdateHealthColor secret oldR.
	EditMode.Exit work is deferred one frame so CompactRaidFrameContainer's Exit
	callback can CompactUnitFrame_UpdateAll untainted.
	securecall does not clear Whoa taint for secret-value compares.

	AttachWhoaEditModeSystems is a no-op that Detaches any stale Whoa claims left
	from older builds. UpdateSystems / OnSystemPositionChange /
	OnEditModeSystemAnchorChanged are not hooked (CUF taint risk).

	Ref: Blizzard_EditMode/Shared/EditModeManager.lua, EditModeSystemTemplates.lua
	     Blizzard_CompactRaidFrames/.../CompactRaidFrameContainer.lua EditMode.Exit
	     Blizzard_UIParent/.../UIParent.lua ShouldShowPartyFrames
]]

local hooked
local pendingSync
local pendingEditModeSync
local pendingAttach
local attached
local evictedBlizzard = {}
-- Combat: park Whoa frames off registeredSystemFrames so UpdateSystems
-- cannot ClearAllPoints/SetPoint them (blocked taint).
local parkedForCombat = {}

local RELATIVE_FRAME_KEYS = {
	PlayerFrame = "player",
	TargetFrame = "target",
	FocusFrame = "focus",
	PartyFrame = "party",
	PetFrame = "pet",
	WhoaUFPlayerFrame = "player",
	WhoaUFTargetFrame = "target",
	WhoaUFFocusFrame = "focus",
	WhoaUFPartyFrame = "party",
	WhoaUFPetFrame = "pet",
}

-- Never RegisterSystemFrame / Mixin Edit Mode (CUF oldR taint).
-- Empty: SetEditModePositionOverridesActive iterates this table (no-op).
local SYSTEM_SPECS = {}

local LAYOUT_SYSTEM_INDEX = {}

-- Field-only layout reads — never EditModeManagerFrame:Method() (object taint → CUF oldR).
-- Mirrors EditModeManagerFrameMixin:GetActiveLayoutInfo / GetActiveLayoutSystemInfo.
local function GetActiveLayoutInfoRaw()
	local em = EditModeManagerFrame
	if not em then
		return nil
	end
	if em.overrideLayoutInfo then
		return em.overrideLayoutInfo
	end
	local layoutInfo = em.layoutInfo
	if not layoutInfo or not layoutInfo.layouts then
		return nil
	end
	return layoutInfo.layouts[layoutInfo.activeLayout]
end

local function GetActiveLayoutSystemInfoRaw(system, systemIndex)
	local activeLayoutInfo = GetActiveLayoutInfoRaw()
	if not activeLayoutInfo or not activeLayoutInfo.systems then
		return nil
	end
	local systems = activeLayoutInfo.systems
	for i = 1, #systems do
		local systemInfo = systems[i]
		if systemInfo.system == system and systemInfo.systemIndex == systemIndex then
			return systemInfo
		end
	end
end

local function GetAccountSettingValueBoolRaw(setting)
	local em = EditModeManagerFrame
	local map = em and em.accountSettingMap
	local entry = map and map[setting]
	return entry and entry.value == 1
end

local function IsEditModeActiveRaw()
	return EditModeManagerFrame and EditModeManagerFrame.editModeActive and true or false
end

local function ResolveLayoutSystemIndex(key)
	if not Enum or not Enum.EditModeUnitFrameSystemIndices then
		return nil
	end
	if not next(LAYOUT_SYSTEM_INDEX) then
		LAYOUT_SYSTEM_INDEX.player = Enum.EditModeUnitFrameSystemIndices.Player
		LAYOUT_SYSTEM_INDEX.target = Enum.EditModeUnitFrameSystemIndices.Target
		LAYOUT_SYSTEM_INDEX.focus = Enum.EditModeUnitFrameSystemIndices.Focus
		LAYOUT_SYSTEM_INDEX.party = Enum.EditModeUnitFrameSystemIndices.Party
		LAYOUT_SYSTEM_INDEX.pet = Enum.EditModeUnitFrameSystemIndices.Pet
		-- Layout sync only — Whoa never RegisterSystemFrame for Boss (Mainline CUF taint).
		LAYOUT_SYSTEM_INDEX.boss = Enum.EditModeUnitFrameSystemIndices.Boss
	end
	return LAYOUT_SYSTEM_INDEX[key]
end

local function GetEditModeAccountSettingChecked(setting, checkButtonKey)
	if not EditModeManagerFrame or not Enum or not Enum.EditModeAccountSetting then
		return false
	end
	-- Prefer accountSettingMap field read (never :GetAccountSettingValueBool).
	if EditModeManagerFrame.accountSettingMap then
		return GetAccountSettingValueBoolRaw(setting)
	end
	local accountSettings = EditModeManagerFrame.AccountSettings
	local checkButton = accountSettings
		and accountSettings.settingsCheckButtons
		and accountSettings.settingsCheckButtons[checkButtonKey]
	-- IsControlChecked on a check button is OK — not EditModeManagerFrame / PartyFrame.
	return checkButton and checkButton.IsControlChecked and checkButton:IsControlChecked()
end

local function AnchorFromLayoutInfo(info, scaleFrame)
	if not info or not info.point then
		return nil
	end
	local scale = (scaleFrame and scaleFrame.GetScale and scaleFrame:GetScale()) or 1
	if scale <= 0 then
		scale = 1
	end
	return {
		point = info.point,
		relativeTo = info.relativeTo or "UIParent",
		relativePoint = info.relativePoint or info.point,
		x = (info.offsetX or 0) / scale,
		y = (info.offsetY or 0) / scale,
	}
end

local function GetLayoutSettingValue(systemInfo, setting)
	if not systemInfo or not systemInfo.settings then
		return nil
	end
	for i = 1, #systemInfo.settings do
		local entry = systemInfo.settings[i]
		if entry.setting == setting then
			return entry.value
		end
	end
end

-- Read raid-style from layout fields only — never UseRaidStylePartyFrames() /
-- GetActiveLayoutSystemInfo() method calls (EditModeManagerFrame object taint).
function WhoaUF:IsRaidStylePartyFramesEnabled()
	if not EditModeManagerFrame then
		return false
	end
	if not Enum or not Enum.EditModeSystem or not Enum.EditModeUnitFrameSystemIndices then
		return false
	end
	if not Enum.EditModeUnitFrameSetting then
		return false
	end
	local systemInfo = GetActiveLayoutSystemInfoRaw(
		Enum.EditModeSystem.UnitFrame,
		Enum.EditModeUnitFrameSystemIndices.Party
	)
	return GetLayoutSettingValue(systemInfo, Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames) == 1
end

function WhoaUF:ShouldShowEditModePartyFrameBackground()
	if not Enum or not Enum.EditModeSystem or not Enum.EditModeUnitFrameSystemIndices then
		return false
	end
	if not Enum.EditModeUnitFrameSetting then
		return false
	end
	local systemInfo = GetActiveLayoutSystemInfoRaw(
		Enum.EditModeSystem.UnitFrame,
		Enum.EditModeUnitFrameSystemIndices.Party
	)
	return GetLayoutSettingValue(systemInfo, Enum.EditModeUnitFrameSetting.ShowPartyFrameBackground) == 1
end

local function EditModeAvailable()
	return EditModeManagerFrame
		and Enum
		and Enum.EditModeSystem
		and Enum.EditModeUnitFrameSystemIndices
		and EditModeSystemMixin
		and true
		or false
end

function WhoaUF:IsEditModeActive()
	return IsEditModeActiveRaw()
end

function WhoaUF:IsEditModeTargetFocusPreviewEnabled()
	if not Enum or not Enum.EditModeAccountSetting then
		return false
	end
	return GetEditModeAccountSettingChecked(
		Enum.EditModeAccountSetting.ShowTargetAndFocus,
		"TargetAndFocus"
	)
end

function WhoaUF:IsEditModePetPreviewEnabled()
	if not Enum or not Enum.EditModeAccountSetting then
		return false
	end
	return GetEditModeAccountSettingChecked(
		Enum.EditModeAccountSetting.ShowPetFrame,
		"PetFrame"
	)
end

-- Mirror Blizzard AccountSettings ShowBossFrames → BossTargetFrameContainer.isInEditMode.
-- Whoa does not claim the Boss EM system; preview drives Whoa boss1–5 only.
function WhoaUF:IsEditModeBossPreviewEnabled()
	if not self:HasBossFrames() then
		return false
	end
	if not Enum or not Enum.EditModeAccountSetting or not Enum.EditModeAccountSetting.ShowBossFrames then
		return false
	end
	return GetEditModeAccountSettingChecked(
		Enum.EditModeAccountSetting.ShowBossFrames,
		"BossFrames"
	)
end

-- DevTools force-show or Edit Mode "Show Boss Frames" (no live boss unit required).
function WhoaUF:WantBossFramePreview()
	if self.IsForceShowFrame and self:IsForceShowFrame("boss") then
		return true
	end
	return self.editModePreviewActive
		and self.IsEditModeBossPreviewEnabled
		and self:IsEditModeBossPreviewEnabled()
end

-- Mirrors ArePartyFramesForcedShown without calling EditModeManagerFrame methods.
function WhoaUF:AreEditModePartyFramesForcedShown()
	if not IsEditModeActiveRaw() then
		return false
	end
	if not Enum or not Enum.EditModeAccountSetting then
		return false
	end
	return GetEditModeAccountSettingChecked(
		Enum.EditModeAccountSetting.ShowPartyFrames,
		"PartyFrames"
	)
end

-- Classic Edit Mode has no target/focus unit in preview — borrow "player".
function WhoaUF:GetEditModePreviewUnit(frame)
	if not self.editModePreviewActive or not frame or not frame.unit then
		return nil
	end
	if UnitExists(frame.unit) then
		return nil
	end
	if frame.kind ~= "target" and frame.kind ~= "focus" then
		return nil
	end
	if frame.kind == "focus" and not self:HasEditModeFocusSupport() then
		return nil
	end
	if not self:IsEditModeTargetFocusPreviewEnabled() then
		return nil
	end
	if UnitExists("player") then
		return "player"
	end
	return nil
end

function WhoaUF:ResolveEditModeRelativeFrame(relativeToName)
	if not relativeToName or relativeToName == "UIParent" then
		return UIParent
	end
	local key = RELATIVE_FRAME_KEYS[relativeToName]
	if key and self.unitFrames then
		local whoa = self.unitFrames[key]
		if whoa then
			return whoa
		end
	end
	-- Never return stock PartyFrame on Mainline (CompactParty child / CUF taint).
	if relativeToName == "PartyFrame" or relativeToName == "CompactPartyFrame" then
		return UIParent
	end
	return _G[relativeToName] or UIParent
end

function WhoaUF:CaptureEditModeLayoutAnchor(key, blizzFrame)
	if not EditModeManagerFrame then
		return nil
	end
	if not Enum or not Enum.EditModeSystem then
		return nil
	end
	local systemIndex = ResolveLayoutSystemIndex(key)
	if not systemIndex then
		return nil
	end
	local systemInfo = GetActiveLayoutSystemInfoRaw(Enum.EditModeSystem.UnitFrame, systemIndex)
	if not systemInfo or not systemInfo.anchorInfo then
		return nil
	end
	return AnchorFromLayoutInfo(systemInfo.anchorInfo, blizzFrame)
end

function WhoaUF:GetEditModeBuffsOnTop(key)
	if key ~= "target" and key ~= "focus" then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	if not EditModeManagerFrame then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	if not Enum or not Enum.EditModeSystem or not Enum.EditModeUnitFrameSetting then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	local systemIndex = ResolveLayoutSystemIndex(key)
	if not systemIndex then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	local systemInfo = GetActiveLayoutSystemInfoRaw(Enum.EditModeSystem.UnitFrame, systemIndex)
	if not systemInfo then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	local value = GetLayoutSettingValue(systemInfo, Enum.EditModeUnitFrameSetting.BuffsOnTop)
	if value == nil then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	return value == 1
end

-- ---------------------------------------------------------------------------
-- Claim / release UnitFrame system slots
-- ---------------------------------------------------------------------------

local function RestoreEvictedBlizzardSystem(systemIndex)
	local list = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
	local frame = evictedBlizzard[systemIndex]
	evictedBlizzard[systemIndex] = nil
	if not frame or not list then
		return
	end
	if frame.whoaUFBlizzardEvicted then
		frame.whoaUFBlizzardEvicted = nil
	end
	local already
	for i = 1, #list do
		if list[i] == frame then
			already = true
			break
		end
	end
	if not already then
		table.insert(list, frame)
	end
end

-- Stock P/T/F stay in registeredSystemFrames (see header: list writes taint
-- Party/Raid). Kept as no-ops so shared callers never nil-error.
function WhoaUF:EvictMainlineOwnedEditModeSystems()
end

function WhoaUF:RestoreMainlineOwnedEditModeSystems()
end

local function ParkWhoaSystemsForCombat()
	if next(parkedForCombat) then
		return
	end
	local list = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
	if not list then
		return
	end
	for i = #list, 1, -1 do
		local frame = list[i]
		if frame and frame.whoaUFEditModeOwner then
			parkedForCombat[#parkedForCombat + 1] = frame
			table.remove(list, i)
		end
	end
end

local function UnparkWhoaSystemsAfterCombat()
	if not next(parkedForCombat) then
		return
	end
	local list = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
	if list then
		for i = 1, #parkedForCombat do
			local frame = parkedForCombat[i]
			if frame and frame.whoaUFEditModeOwner then
				local already
				for j = 1, #list do
					if list[j] == frame then
						already = true
						break
					end
				end
				if not already then
					list[#list + 1] = frame
				end
			end
		end
	end
	wipe(parkedForCombat)
end

-- EditModeSystemMixin:OnSystemLoad shadows Hide/SetShown/SetPoint/SetScale with
-- Lua wrappers. On Whoa SecureUnitButtons those slots are addon-tainted, so
-- RegisterUnitWatch's combat Show/Hide/SetAttribute path fails (taint.log HideBase).
-- nil restores widget metatable C methods; copying HideBase → Hide keeps a
-- tainted table slot.
-- Visibility wrappers are never needed (unit frames are not layout frames).
-- Position wrappers are installed only while Edit Mode is open.
local function ClearSecureVisibilityOverrides(frame)
	if not frame then
		return
	end
	frame.Hide = nil
	frame.HideBase = nil
	frame.SetShown = nil
	frame.SetShownBase = nil
end

local function ClearEditModePositionOverrides(frame)
	if not frame then
		return
	end
	frame.SetScale = nil
	frame.SetPoint = nil
	frame.ClearAllPoints = nil
end

local function ClearSecureEditModeOverrides(frame)
	ClearSecureVisibilityOverrides(frame)
	ClearEditModePositionOverrides(frame)
end

local function InstallEditModePositionOverrides(frame)
	if not frame or not frame.SetScaleBase then
		return
	end
	frame.SetScale = EditModeSystemMixin.SetScaleOverride
	frame.SetPoint = EditModeSystemMixin.SetPointOverride
	frame.ClearAllPoints = EditModeSystemMixin.ClearAllPointsOverride
end

local function SetEditModePositionOverridesActive(active)
	local unitFrames = WhoaUF.unitFrames
	if not unitFrames then
		return
	end
	for key in pairs(SYSTEM_SPECS) do
		local frame = unitFrames[key]
		if frame and frame.whoaUFEditModeLoaded then
			ClearSecureVisibilityOverrides(frame)
			if active then
				InstallEditModePositionOverrides(frame)
			else
				ClearEditModePositionOverrides(frame)
			end
		end
	end
end

local function DetachWhoaSystem(frame)
	if not frame or not frame.whoaUFEditModeOwner then
		return
	end
	local systemIndex = frame.systemIndex
	-- Never ClearSelectedSystem / UpdateSystems on EditModeManagerFrame (object taint → CUF).
	if frame.Selection then
		frame.Selection:Hide()
	end

	local list = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
	if list then
		for i = #list, 1, -1 do
			if list[i] == frame then
				table.remove(list, i)
			end
		end
	end

	frame.whoaUFEditModeOwner = nil
	frame.whoaUFEditModeKey = nil
	ClearSecureEditModeOverrides(frame)
	for i = #parkedForCombat, 1, -1 do
		if parkedForCombat[i] == frame then
			table.remove(parkedForCombat, i)
		end
	end
	-- Keep system/systemIndex for the next AttachWhoaEditModeSystems pass so
	-- RegisterSystemFrame can run without re-wrapping SetScale/SetPoint (OnSystemLoad is one-shot via whoaUFEditModeLoaded).

	if systemIndex then
		RestoreEvictedBlizzardSystem(systemIndex)
	end
end

function WhoaUF:AttachWhoaEditModeSystems()
	-- Never claim slots. Release any stale claims from older builds.
	self:DetachWhoaEditModeSystems()
end

function WhoaUF:DetachWhoaEditModeSystems()
	pendingAttach = nil
	if not attached and not next(evictedBlizzard) then
		local unitFrames = self.unitFrames
		if unitFrames then
			for _, frame in pairs(unitFrames) do
				if frame and frame.whoaUFEditModeOwner then
					DetachWhoaSystem(frame)
				end
			end
		end
		return
	end
	if InCombatLockdown() then
		return
	end

	local unitFrames = self.unitFrames
	if unitFrames then
		for _, frame in pairs(unitFrames) do
			if frame and frame.whoaUFEditModeOwner then
				DetachWhoaSystem(frame)
			end
		end
	end
	for systemIndex in pairs(evictedBlizzard) do
		RestoreEvictedBlizzardSystem(systemIndex)
	end
	wipe(evictedBlizzard)
	attached = nil
	-- Never UpdateSystems from Whoa on Mainline (EditModeManagerFrame object taint → CUF oldR).
end

-- Anchor sync only; skip full visibility refresh while dragging in Edit Mode.
function WhoaUF:SyncFromEditMode()
	if not self.db or not self.db.enabled then
		return
	end
	if InCombatLockdown() then
		pendingEditModeSync = true
		return
	end
	pendingEditModeSync = nil

	if self.CaptureBlizzardUnitFrameAnchors then
		self:CaptureBlizzardUnitFrameAnchors()
	end
	if self.SyncUnitFramePositions then
		self:SyncUnitFramePositions()
	end
	if self.SyncEditModePetPosition then
		self:SyncEditModePetPosition()
	end
	if self.LayoutPlayerBottomFrames and not self.editModePreviewActive then
		self:LayoutPlayerBottomFrames()
	end
	if self.editModePreviewActive and self.RefreshEditModePreviewAuras then
		self:RefreshEditModePreviewAuras()
	end
end

-- ---------------------------------------------------------------------------
-- Preview visibility
-- ---------------------------------------------------------------------------

function WhoaUF:ApplyEditModePreviewVisibility()
	if not self.editModePreviewActive or not self.db or not self.db.enabled then
		return
	end
	local unitFrames = self.unitFrames
	if not unitFrames then
		return
	end

	local function showPreview(frame)
		if not frame then
			return
		end
		if UnregisterUnitWatch then
			UnregisterUnitWatch(frame)
		end
		frame:Show()
		if self.UpdateUnitFrame then
			self:UpdateUnitFrame(frame)
		end
	end

	local function hidePreview(frame)
		if not frame then
			return
		end
		if UnregisterUnitWatch then
			UnregisterUnitWatch(frame)
		end
		frame:Hide()
	end

	if unitFrames.player then
		unitFrames.player:Show()
	end

	-- Stock RefreshTargetAndFocus highlights Blizzard TargetFrame/FocusFrame (hidden).
	-- Whoa owns those system slots — highlight/clear Whoa chrome instead.
	local function highlightPreview(frame)
		if frame and frame.HighlightSystem then
			frame:HighlightSystem()
		end
	end
	local function clearPreview(frame)
		if frame and frame.ClearHighlight then
			frame:ClearHighlight()
		end
	end

	if self:IsEditModeTargetFocusPreviewEnabled() then
		showPreview(unitFrames.target)
		highlightPreview(unitFrames.target)
		if self:HasEditModeFocusSupport() then
			showPreview(unitFrames.focus)
			highlightPreview(unitFrames.focus)
		else
			hidePreview(unitFrames.focus)
			clearPreview(unitFrames.focus)
		end
	else
		hidePreview(unitFrames.target)
		clearPreview(unitFrames.target)
		hidePreview(unitFrames.focus)
		clearPreview(unitFrames.focus)
	end

	hidePreview(unitFrames.tot)
	hidePreview(unitFrames.focustot)

	-- Pet / class bars: Blizzard swap owns those systems while Edit Mode is open.
	-- No UnitFrame Edit Mode claims; Whoa party still previews via LayoutPartyFrames.
	if self.HideWhoaEditModeSwapFrames then
		self:HideWhoaEditModeSwapFrames()
	else
		hidePreview(unitFrames.pet)
	end

	if self.LayoutPartyFrames then
		self:LayoutPartyFrames()
	end
	local party = unitFrames.party or self.partyContainer
	if party and party:IsShown() and self:AreEditModePartyFramesForcedShown() then
		highlightPreview(party)
	else
		clearPreview(party)
	end

	-- Boss: mirror AccountSettings ShowBossFrames (stock sets container.isInEditMode).
	-- Do not claim Boss EM; LayoutBossFrames owns create/show + placeholders.
	if self.LayoutBossFrames then
		self:LayoutBossFrames()
	end

	if self.RefreshEditModePreviewAuras then
		self:RefreshEditModePreviewAuras()
	end
end

local function OnEditModeEnter()
	if not WhoaUF.db or not WhoaUF.db.enabled then
		return
	end
	WhoaUF.editModePreviewActive = true
	-- Never register Whoa systems (CUF taint). Clear any stale claims.
	if WhoaUF.AttachWhoaEditModeSystems then
		WhoaUF:AttachWhoaEditModeSystems()
	end
	SetEditModePositionOverridesActive(true)
	if WhoaUF.RestoreBlizzardEditModeSwapFrames then
		WhoaUF:RestoreBlizzardEditModeSwapFrames()
	end
	WhoaUF:SyncFromEditMode()
	WhoaUF:ApplyEditModePreviewVisibility()
end

-- Defer one frame: CompactRaidFrameContainer Exit runs CompactUnitFrame_UpdateAll
-- untainted; same-event Whoa work would taint that pass.
local function OnEditModeExit()
	C_Timer.After(0, function()
		WhoaUF:SyncFromEditMode()
		if WhoaUF.DisconnectBlizzardEditModeSwapFrames then
			WhoaUF:DisconnectBlizzardEditModeSwapFrames()
		end
		WhoaUF.editModePreviewActive = nil
		SetEditModePositionOverridesActive(false)
		if WhoaUF.ApplyUnitFrames then
			WhoaUF:ApplyUnitFrames()
		end
		if WhoaUF.LayoutPartyFrames then
			WhoaUF:LayoutPartyFrames()
		end
		if WhoaUF.ApplyPetFrameVisibility then
			WhoaUF:ApplyPetFrameVisibility()
		end
		if WhoaUF.RefreshPlayerClassBars then
			WhoaUF:RefreshPlayerClassBars()
		end
	end)
end

local function OnEditModeAccountPreviewRefresh()
	if not WhoaUF.editModePreviewActive then
		return
	end
	if WhoaUF.RestoreBlizzardEditModeSwapFrames then
		WhoaUF:RestoreBlizzardEditModeSwapFrames()
	end
	if WhoaUF.ApplyEditModePreviewVisibility then
		WhoaUF:ApplyEditModePreviewVisibility()
	end
end

local function ScheduleEditModeSync()
	if pendingSync then
		return
	end
	pendingSync = true
	C_Timer.After(0, function()
		pendingSync = nil
		if WhoaUF.SyncFromEditMode then
			WhoaUF:SyncFromEditMode()
		end
	end)
end

local function HookEditMode()
	if hooked or not EditModeAvailable() then
		return
	end
	hooked = true

	-- Do not hooksecurefunc AccountSettings / EditModeManagerFrame methods.
	-- Any post-hook during Party/Raid refresh or CUFProfiles apply can leave
	-- Whoa taint on CompactParty RefreshMembers → secret oldR.

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, WhoaUF)
		EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, WhoaUF)
	end

	if IsEditModeActiveRaw() then
		OnEditModeEnter()
	elseif WhoaUF.db and WhoaUF.db.enabled then
		-- Clear stale Whoa claims from older builds.
		WhoaUF:DetachWhoaEditModeSystems()
		ScheduleEditModeSync()
	end
end

local function TryHookEditMode()
	if hooked then
		if WhoaUF.db and WhoaUF.db.enabled then
			WhoaUF:AttachWhoaEditModeSystems()
		end
		return
	end
	if EditModeManagerFrame then
		HookEditMode()
	end
end

function WhoaUF:InitEditMode()
	if self.editModeInited then
		TryHookEditMode()
		return
	end
	self.editModeInited = true

	if EditModeManagerFrame then
		TryHookEditMode()
	else
		self:ContinueOnAddOnLoaded("Blizzard_EditMode", TryHookEditMode)
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
	watcher:SetScript("OnEvent", function()
		TryHookEditMode()
		if hooked and WhoaUF.db and WhoaUF.db.enabled then
			ScheduleEditModeSync()
		end
	end)

	local combatWatcher = CreateFrame("Frame")
	combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	combatWatcher:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			-- Combat enter: park Whoa frames before Edit Mode UpdateSystems runs.
			ParkWhoaSystemsForCombat()
			return
		end
		local hadParked = next(parkedForCombat) ~= nil
		UnparkWhoaSystemsAfterCombat()
		if pendingAttach and WhoaUF.db and WhoaUF.db.enabled then
			WhoaUF:AttachWhoaEditModeSystems()
		end
		if pendingEditModeSync then
			WhoaUF:SyncFromEditMode()
		elseif hadParked and WhoaUF.db and WhoaUF.db.enabled then
			-- Layout may have changed while parked; re-sync anchors only.
			ScheduleEditModeSync()
		end
	end)
	if InCombatLockdown() then
		ParkWhoaSystemsForCombat()
	end
end
