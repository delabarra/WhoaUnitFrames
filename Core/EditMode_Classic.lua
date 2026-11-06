--[[
	Edit Mode (Classic): claims UnitFrame slots for player / target / focus / party.
	Pet / class-power stay on Blizzard systems and are restored only while Edit
	Mode is open (see Core/Blizzard_Classic.lua swap helpers).

	Classic Era has no focus unit — skip Focus registration.

	EvictMainlineOwnedEditModeSystems / RestoreMainlineOwnedEditModeSystems are
	no-op stubs so shared callers stay flavor-safe.

	Ref: Blizzard_EditMode/Shared/EditModeManager.lua, EditModeSystemTemplates.lua
	     Blizzard_CompactRaidFrames/.../CompactRaidFrameContainer.lua EditMode.Exit
]]
if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	return
end

local hooked
local pendingSync
local pendingEditModeSync
local pendingAttach
local attached
local evictedBlizzard = {}
-- Combat: park Whoa frames off registeredSystemFrames so UpdateSystems
-- cannot ClearAllPoints/SetPoint them (blocked taint).
local parkedForCombat = {}

local SMALL_FOCUS_SCALE = 0.75

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

-- Classic: claim player / target / focus / party.
local SYSTEM_SPECS = {
	player = {
		indexKey = "Player",
		label = "HUD_EDIT_MODE_PLAYER_FRAME_LABEL",
		defaultHideSelection = false,
	},
	target = {
		indexKey = "Target",
		label = "HUD_EDIT_MODE_TARGET_FRAME_LABEL",
		defaultHideSelection = true,
	},
	focus = {
		indexKey = "Focus",
		label = "HUD_EDIT_MODE_FOCUS_FRAME_LABEL",
		defaultHideSelection = true,
		requiresFocus = true,
	},
	party = {
		indexKey = "Party",
		label = "HUD_EDIT_MODE_PARTY_FRAMES_LABEL",
		defaultHideSelection = true,
		alwaysUseTopLeftAnchor = true,
		breakSnappedFramesOnSave = true,
	},
}

local LAYOUT_SYSTEM_INDEX = {}

-- Edit Mode layout writes (displayValue on settingMap) must stay untainted:
-- PartyFrame:ShouldShow → UseRaidStylePartyFrames reads those fields in combat.
local function SecureEditModeCall(func, ...)
	if type(func) ~= "function" then
		return
	end
	if securecall then
		return securecall(func, ...)
	end
	return func(...)
end

local function SecureUpdateEditModeSystems()
	if not EditModeManagerFrame or not EditModeManagerFrame.UpdateSystems then
		return
	end
	SecureEditModeCall(EditModeManagerFrame.UpdateSystems, EditModeManagerFrame)
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
		-- Layout sync only — Whoa never RegisterSystemFrame for Boss.
		LAYOUT_SYSTEM_INDEX.boss = Enum.EditModeUnitFrameSystemIndices.Boss
	end
	return LAYOUT_SYSTEM_INDEX[key]
end

local function GetEditModeAccountSettingChecked(setting, checkButtonKey)
	if not EditModeManagerFrame or not Enum or not Enum.EditModeAccountSetting then
		return false
	end
	if EditModeManagerFrame.GetAccountSettingValueBool then
		return EditModeManagerFrame:GetAccountSettingValueBool(setting)
	end
	local accountSettings = EditModeManagerFrame.AccountSettings
	local checkButton = accountSettings
		and accountSettings.settingsCheckButtons
		and accountSettings.settingsCheckButtons[checkButtonKey]
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

-- Prefer layout-info read; Classic-safe fallback to UseRaidStylePartyFrames when
-- layout APIs are missing or the layout value is false-ish.
function WhoaUF:IsRaidStylePartyFramesEnabled()
	local raidStyle = false
	local layoutApis =
		EditModeManagerFrame
		and EditModeManagerFrame.GetActiveLayoutSystemInfo
		and Enum
		and Enum.EditModeSystem
		and Enum.EditModeUnitFrameSystemIndices
		and Enum.EditModeUnitFrameSetting
	if layoutApis then
		local systemInfo = EditModeManagerFrame:GetActiveLayoutSystemInfo(
			Enum.EditModeSystem.UnitFrame,
			Enum.EditModeUnitFrameSystemIndices.Party
		)
		raidStyle = GetLayoutSettingValue(systemInfo, Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames) == 1
	end
	if not raidStyle and EditModeManagerFrame and EditModeManagerFrame.UseRaidStylePartyFrames then
		return EditModeManagerFrame:UseRaidStylePartyFrames() and true or false
	end
	return raidStyle and true or false
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
	return EditModeManagerFrame
		and EditModeManagerFrame.IsEditModeActive
		and EditModeManagerFrame:IsEditModeActive()
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

function WhoaUF:AreEditModePartyFramesForcedShown()
	return EditModeManagerFrame
		and EditModeManagerFrame.ArePartyFramesForcedShown
		and EditModeManagerFrame:ArePartyFramesForcedShown()
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
	return _G[relativeToName] or UIParent
end

function WhoaUF:CaptureEditModeLayoutAnchor(key, blizzFrame)
	if not EditModeManagerFrame or not EditModeManagerFrame.GetActiveLayoutSystemInfo then
		return nil
	end
	if not Enum or not Enum.EditModeSystem then
		return nil
	end
	local systemIndex = ResolveLayoutSystemIndex(key)
	if not systemIndex then
		return nil
	end
	local systemInfo = EditModeManagerFrame:GetActiveLayoutSystemInfo(Enum.EditModeSystem.UnitFrame, systemIndex)
	if not systemInfo or not systemInfo.anchorInfo then
		return nil
	end
	return AnchorFromLayoutInfo(systemInfo.anchorInfo, blizzFrame)
end

function WhoaUF:GetEditModeBuffsOnTop(key)
	if key ~= "target" and key ~= "focus" then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	if not EditModeManagerFrame or not EditModeManagerFrame.GetActiveLayoutSystemInfo then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	if not Enum or not Enum.EditModeSystem or not Enum.EditModeUnitFrameSetting then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	local systemIndex = ResolveLayoutSystemIndex(key)
	if not systemIndex then
		return GetCVarBool and GetCVarBool("buffsOnTop")
	end
	local systemInfo = EditModeManagerFrame:GetActiveLayoutSystemInfo(Enum.EditModeSystem.UnitFrame, systemIndex)
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

local function EvictBlizzardSystem(system, systemIndex)
	local list = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
	if not list then
		return
	end
	for i = #list, 1, -1 do
		local frame = list[i]
		if frame
			and not frame.whoaUFEditModeOwner
			and frame.system == system
			and frame.systemIndex == systemIndex
		then
			evictedBlizzard[systemIndex] = frame
			frame.whoaUFBlizzardEvicted = true
			if frame.Selection then
				frame.Selection:Hide()
			end
			table.remove(list, i)
		end
	end
end

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

-- Empty bodies for shared Mainline callers; Classic never evicts stock P/T/F this way.
function WhoaUF:EvictMainlineOwnedEditModeSystems()
end

function WhoaUF:RestoreMainlineOwnedEditModeSystems()
end


local function WhoaUpdateSystemSettingBuffsOnTop(self)
	self.buffsOnTop = self:GetSettingValueBool(Enum.EditModeUnitFrameSetting.BuffsOnTop)
	if WhoaUF.UpdateUnitAuras then
		WhoaUF:UpdateUnitAuras(self)
	end
end

local function WhoaUpdateSystemSettingUseLargerFrame(self)
	if self.systemIndex == Enum.EditModeUnitFrameSystemIndices.Focus then
		if WhoaUF.SetFocusFrameScale then
			WhoaUF:SetFocusFrameScale(WhoaUF:GetEffectiveFrameScale(self))
		else
			local scale = (WhoaUF.GetEffectiveFrameScale and WhoaUF:GetEffectiveFrameScale(self))
				or ((WhoaUF.GetFrameScale and WhoaUF:GetFrameScale()) or 1)
			if scale and scale > 0 then
				self:SetScale(scale)
			end
		end
		if WhoaUF.UpdateUnitAuras then
			WhoaUF:UpdateUnitAuras(self)
		end
		return
	end
	EditModeUnitFrameSystemMixin.UpdateSystemSettingUseLargerFrame(self)
end

local function WhoaUpdateSystemSettingFrameSize(self)
	local base = (WhoaUF.GetFrameScale and WhoaUF:GetFrameScale()) or 1
	if self.systemIndex == Enum.EditModeUnitFrameSystemIndices.Focus
		and self:HasSetting(Enum.EditModeUnitFrameSetting.UseLargerFrame)
		and not self:GetSettingValueBool(Enum.EditModeUnitFrameSetting.UseLargerFrame)
	then
		if WhoaUF.SetFocusFrameScale then
			WhoaUF:SetFocusFrameScale(SMALL_FOCUS_SCALE * base)
		else
			self:SetScale(SMALL_FOCUS_SCALE * base)
		end
		return
	end
	if self:HasSetting(Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames)
		and self:GetSettingValueBool(Enum.EditModeUnitFrameSetting.UseRaidStylePartyFrames)
	then
		self:SetScale(1)
		return
	end
	-- Prefer Whoa Settings frameScale over Edit Mode FrameSize so one control owns size.
	self:SetScale(base)
end

local function WhoaUpdateSystemSettingUseRaidStylePartyFrames(self)
	if WhoaUF.LayoutPartyFrames then
		WhoaUF:LayoutPartyFrames()
	end
	-- Combat: stock party Show/Hide/SetAttribute are protected once Whoa muted PartyFrame.
	if not InCombatLockdown() then
		if UpdateRaidAndPartyFrames then
			UpdateRaidAndPartyFrames()
		end
	end
	if self.UpdateSelectionVerticalState then
		self:UpdateSelectionVerticalState()
	end
	self:UpdateSystemSettingFrameSize()
end

local function WhoaUpdateSystemSettingShowPartyFrameBackground(self)
	if WhoaUF.UpdatePartyMemberBackground then
		WhoaUF:UpdatePartyMemberBackground()
	end
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

-- Edit Mode stores relativeTo as Blizzard global names; remap to Whoa frames.
local function WhoaApplySystemAnchor(self)
	if not self.systemInfo or not self.systemInfo.anchorInfo then
		return
	end
	-- SecureUnitButton: ClearAllPoints/SetPoint blocked in combat (taint.log).
	if InCombatLockdown() then
		pendingEditModeSync = true
		return
	end

	local info = self.systemInfo.anchorInfo
	local clear = self.ClearAllPointsBase or self.ClearAllPoints
	local set = self.SetPointBase or self.SetPoint

	clear(self)

	local scale = self:GetScale()
	if not scale or scale <= 0 then
		scale = 1
	end
	local relativeTo = WhoaUF:ResolveEditModeRelativeFrame(info.relativeTo or "UIParent")
	set(
		self,
		info.point,
		relativeTo,
		info.relativePoint or info.point,
		(info.offsetX or 0) / scale,
		(info.offsetY or 0) / scale
	)

	if self.systemInfo.anchorInfo2 then
		local info2 = self.systemInfo.anchorInfo2
		local relativeTo2 = WhoaUF:ResolveEditModeRelativeFrame(info2.relativeTo or "UIParent")
		set(
			self,
			info2.point,
			relativeTo2,
			info2.relativePoint or info2.point,
			(info2.offsetX or 0) / scale,
			(info2.offsetY or 0) / scale
		)
	end
end

local function EnsureSelection(frame)
	if frame.Selection then
		return frame.Selection
	end
	local template = "EditModeSystemSelectionDoubleLabelTemplate"
	local selection = CreateFrame("Frame", nil, frame, template)
	selection:SetAllPoints(frame)
	selection:Hide()
	frame.Selection = selection
	return selection
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

local function AttachWhoaSystem(frame, key, spec)
	if not frame or frame.whoaUFEditModeOwner then
		return false
	end
	if spec.requiresFocus and not WhoaUF:HasEditModeFocusSupport() then
		return false
	end
	local indices = Enum.EditModeUnitFrameSystemIndices
	local systemIndex = indices[spec.indexKey]
	if not systemIndex then
		return false
	end

	frame.system = Enum.EditModeSystem.UnitFrame
	frame.systemIndex = systemIndex
	frame.systemNameString = _G[spec.label] or key
	frame.defaultHideSelection = spec.defaultHideSelection and true or false
	frame.whoaUFEditModeOwner = true
	frame.whoaUFEditModeKey = key
	if spec.alwaysUseTopLeftAnchor then
		frame.alwaysUseTopLeftAnchor = true
	end
	if spec.breakSnappedFramesOnSave then
		frame.breakSnappedFramesOnSave = true
	end

	if frame.SetMovable then
		frame:SetMovable(true)
	end
	if frame.SetClampedToScreen then
		frame:SetClampedToScreen(true)
	end

	EvictBlizzardSystem(frame.system, systemIndex)

	if not frame.whoaUFEditModeLoaded then
		EnsureSelection(frame)
		Mixin(frame, EditModeSystemMixin)
		Mixin(frame, EditModeUnitFrameSystemMixin)
		frame.UpdateSystemSettingBuffsOnTop = WhoaUpdateSystemSettingBuffsOnTop
		frame.UpdateSystemSettingUseLargerFrame = WhoaUpdateSystemSettingUseLargerFrame
		frame.UpdateSystemSettingFrameSize = WhoaUpdateSystemSettingFrameSize
		frame.UpdateSystemSettingUseRaidStylePartyFrames = WhoaUpdateSystemSettingUseRaidStylePartyFrames
		frame.UpdateSystemSettingShowPartyFrameBackground = WhoaUpdateSystemSettingShowPartyFrameBackground
		frame.ApplySystemAnchor = WhoaApplySystemAnchor
		-- Skip visibility wrappers; OnSystemLoad still stores *Base for position.
		frame.SetupVisibilityFunctionOverrides = function() end
		-- Guards BEFORE OnSystemLoad / RegisterSystemFrame: layout UpdateSystems
		-- can run immediately and Mixined CUF refreshers would taint CompactParty.
		frame:OnSystemLoad()
		frame.SetupVisibilityFunctionOverrides = EditModeSystemMixin.SetupVisibilityFunctionOverrides
		ClearSecureEditModeOverrides(frame)
		if WhoaUF.editModePreviewActive then
			InstallEditModePositionOverrides(frame)
		end
		frame.whoaUFEditModeLoaded = true
	else
		frame.ApplySystemAnchor = WhoaApplySystemAnchor
		ClearSecureEditModeOverrides(frame)
		if WhoaUF.editModePreviewActive then
			InstallEditModePositionOverrides(frame)
		end
		EditModeManagerFrame:RegisterSystemFrame(frame)
		if frame.Selection and frame.Selection.SetSystem then
			frame.Selection:SetSystem(frame)
		end
	end
	return true
end

local function DetachWhoaSystem(frame)
	if not frame or not frame.whoaUFEditModeOwner then
		return
	end
	local systemIndex = frame.systemIndex
	if frame.isSelected and EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
		EditModeManagerFrame:ClearSelectedSystem()
	end
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
	if not self.db or not self.db.enabled or not EditModeAvailable() then
		return
	end
	if InCombatLockdown() then
		pendingAttach = true
		return
	end
	pendingAttach = nil

	local unitFrames = self.unitFrames
	if not unitFrames then
		return
	end

	local any
	for key, spec in pairs(SYSTEM_SPECS) do
		local frame = unitFrames[key]
		-- Already-attached frames still need native methods for unit watch.
		if frame and frame.whoaUFEditModeOwner then
			ClearSecureVisibilityOverrides(frame)
			if not WhoaUF.editModePreviewActive then
				ClearEditModePositionOverrides(frame)
			end
		end
		if AttachWhoaSystem(frame, key, spec) then
			any = true
		end
	end
	attached = any and true or attached

	if any then
		SecureUpdateEditModeSystems()
	end
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

	SecureUpdateEditModeSystems()
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
	-- Party is claimed by Whoa.
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
	-- Claim Whoa Edit Mode slots.
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

local function IsUnitFrameSystem(systemFrame)
	return systemFrame
		and Enum
		and Enum.EditModeSystem
		and systemFrame.system == Enum.EditModeSystem.UnitFrame
end

local function HookEditMode()
	if hooked or not EditModeAvailable() then
		return
	end
	hooked = true

	local accountSettings = EditModeManagerFrame.AccountSettings
	if accountSettings then
		if accountSettings.RefreshTargetAndFocus then
			hooksecurefunc(accountSettings, "RefreshTargetAndFocus", OnEditModeAccountPreviewRefresh)
		end
		if accountSettings.RefreshPetFrame then
			hooksecurefunc(accountSettings, "RefreshPetFrame", OnEditModeAccountPreviewRefresh)
		end
		if accountSettings.RefreshPartyFrames then
			hooksecurefunc(accountSettings, "RefreshPartyFrames", OnEditModeAccountPreviewRefresh)
		end
		if accountSettings.RefreshBossFrames then
			hooksecurefunc(accountSettings, "RefreshBossFrames", OnEditModeAccountPreviewRefresh)
		end
	end

	-- Edit Mode hints still target Blizzard frame globals — forward to Whoa.
	if accountSettings and accountSettings.SetTargetAndFocusMouseOver then
		hooksecurefunc(accountSettings, "SetTargetAndFocusMouseOver", function(_, ...)
			if not WhoaUF.editModePreviewActive then
				return
			end
			local unitFrames = WhoaUF.unitFrames
			if unitFrames and unitFrames.target and unitFrames.target.ShowEditInstructions then
				unitFrames.target:ShowEditInstructions(...)
			end
			if WhoaUF:HasEditModeFocusSupport()
				and unitFrames
				and unitFrames.focus
				and unitFrames.focus.ShowEditInstructions
			then
				unitFrames.focus:ShowEditInstructions(...)
			end
		end)
	end
	if accountSettings and accountSettings.SetPartyFramesMouseOver then
		hooksecurefunc(accountSettings, "SetPartyFramesMouseOver", function(_, ...)
			if not WhoaUF.editModePreviewActive then
				return
			end
			local party = WhoaUF.unitFrames and WhoaUF.unitFrames.party or WhoaUF.partyContainer
			if party and party.ShowEditInstructions then
				party:ShowEditInstructions(...)
			end
		end)
	end

	hooksecurefunc(EditModeManagerFrame, "OnSystemPositionChange", function(_, systemFrame)
		if IsUnitFrameSystem(systemFrame) then
			ScheduleEditModeSync()
		end
	end)
	hooksecurefunc(EditModeManagerFrame, "OnEditModeSystemAnchorChanged", ScheduleEditModeSync)
	-- Whoa systems are registered; sync after Blizzard UpdateSystems.
	hooksecurefunc(EditModeManagerFrame, "UpdateSystems", ScheduleEditModeSync)

	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", OnEditModeEnter, WhoaUF)
		EventRegistry:RegisterCallback("EditMode.Exit", OnEditModeExit, WhoaUF)
	end

	if EditModeManagerFrame:IsEditModeActive() then
		OnEditModeEnter()
	elseif WhoaUF.db and WhoaUF.db.enabled then
		WhoaUF:AttachWhoaEditModeSystems()
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
	elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", TryHookEditMode)
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
			-- Layout may have changed while parked; re-apply system anchors.
			SecureUpdateEditModeSystems()
			ScheduleEditModeSync()
		end
	end)
	if InCombatLockdown() then
		ParkWhoaSystemsForCombat()
	end
end
