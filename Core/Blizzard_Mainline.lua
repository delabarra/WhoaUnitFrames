-- Mainline mute/conceal/restore. Conceal = alpha 0 + mouse off + UnregisterAllEvents.
-- Never Hide/Show/SetParent/SetScript on stock frames (OnHide/OnShow/OnLoad taint →
-- Edit Mode UpdateSystems / secret compares). Never touch PartyFrame /
-- CompactPartyFrame / CompactRaidFrame* (CUF). MemberFrame1-4 + Background via
-- ConcealStockParty only; Forever may UnregisterAllEvents on MemberFrame1-4.
-- Classic party mute lives only in Blizzard_Classic.lua.
-- _G Classic names are often mixins on Mainline (use *Frame widgets, e.g. PaladinPowerBarFrame).
local function IsUIFrame(frame)
	return frame ~= nil and type(frame.GetParent) == "function" and type(frame.Hide) == "function"
end

local originals = {}
local pendingApply
local capturedAnchors = {}

-- Class-power names Whoa replaces are always listed. Retail-only hosts Whoa does
-- not implement (InsanityBarFrame, EssencePlayerFrame, MageArcaneChargesFrame,
-- Evoker, ClassPowerBar containers, CompactArenaFrame, …) stay unmuted.
-- Never mute/reparent PartyFrame (owns CompactPartyFrame — CUF taint).
local blizzardFrames = {
	"PlayerFrame",
	"PlayerFrameGroupIndicator",
	"PlayerFrameMultiGroupFrame",
	"PlayerFrameAlternateManaBar",
	"PlayerPowerBarAlt",
	"AlternatePowerBar",
	"PetFrame",
	"PetCastingBarFrame",
	"TargetFrame",
	"FocusFrame",
	-- Parented to UIParent (only anchored to TargetFrame); shows when comboPointLocation == "1".
	"ComboFrame",
	"TotemFrame",
	"WarlockPowerFrame",
	"MonkStaggerBar",
	"RuneFrame",
	-- Boss1-5TargetFrame: stay unmuted while HasBossFrames is false (no Whoa boss chrome).
	-- Mainline class-power *Frame widgets (mixin tables keep the old names).
	"PaladinPowerBarFrame",
	"MonkHarmonyBarFrame",
	"RogueComboPointBarFrame",
	"DruidComboPointBarFrame",
}

-- Named bars that can sit in _G even when the parent is already muted.
local extraMuteGlobals = {
	"PlayerFrameHealthBar",
	"PlayerFrameManaBar",
	"TargetFrameHealthBar",
	"TargetFrameManaBar",
	"FocusFrameHealthBar",
	"FocusFrameManaBar",
	"PetFrameHealthBar",
	"PetFrameManaBar",
	"TargetFrameToTHealthBar",
	"TargetFrameToTManaBar",
	"FocusFrameToTHealthBar",
	"FocusFrameToTManaBar",
}

-- Mirror stock frame screen anchors from the active Edit Mode / layout.
-- Never read PartyFrame (owns CompactPartyFrame; any contact can taint CUF).
local unitFrameAnchorSources = {
	player = "PlayerFrame",
	target = "TargetFrame",
	focus = "FocusFrame",
}

-- Hidden while Whoa runs; stock shown again only during Edit Mode preview swap
-- (player/target/focus stock stays muted — Whoa owns those surfaces).
local swappableBlizzardFrameNames = {
	"PetFrame",
	"PetCastingBarFrame",
	"TotemFrame",
	"WarlockPowerFrame",
	"MonkStaggerBar",
	"PlayerFrameAlternateManaBar",
	"AlternatePowerBar",
	"RuneFrame",
	"PaladinPowerBarFrame",
	"MonkHarmonyBarFrame",
	"RogueComboPointBarFrame",
	"DruidComboPointBarFrame",
}

local function VisitSwappableBlizzardFrames(visitor)
	for i = 1, #swappableBlizzardFrameNames do
		visitor(_G[swappableBlizzardFrameNames[i]], swappableBlizzardFrameNames[i])
	end
	if TargetFrame and TargetFrame.totFrame then
		visitor(TargetFrame.totFrame, "TargetFrameToT")
	end
	if FocusFrame and FocusFrame.totFrame then
		visitor(FocusFrame.totFrame, "FocusFrameToT")
	end
end

local editModeSwapActive
local pendingEditModeSwapDisconnect

local function ShouldHideDefaults()
	return WhoaUF.db and WhoaUF.db.enabled
end

local function CaptureFrameAnchor(frame)
	if not frame or frame:GetNumPoints() < 1 then
		return nil
	end

	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		return nil
	end

	local relativeName = "UIParent"
	if relativeTo and relativeTo.GetName then
		relativeName = relativeTo:GetName() or "UIParent"
	end

	return {
		point = point,
		relativeTo = relativeName,
		relativePoint = relativePoint or point,
		x = x or 0,
		y = y or 0,
	}
end

-- Fallback when the stock frame has no restorable points.
-- Edit Mode stores layout offsets in systemInfo; ApplySystemAnchor divides by scale.
local function CaptureSystemAnchorInfo(frame)
	if not frame or not frame.systemInfo or not frame.systemInfo.anchorInfo then
		return nil
	end
	local info = frame.systemInfo.anchorInfo
	if not info.point then
		return nil
	end
	local scale = (frame.GetScale and frame:GetScale()) or 1
	if scale == 0 then
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

function WhoaUF:CaptureBlizzardUnitFrameAnchors()
	if InCombatLockdown() then
		return
	end

	for key, frameName in pairs(unitFrameAnchorSources) do
		local frame = _G[frameName]
		if frame then
			local anchor
			if WhoaUF.editModePreviewActive then
				anchor = CaptureFrameAnchor(frame) or CaptureSystemAnchorInfo(frame)
				if not anchor and WhoaUF.CaptureEditModeLayoutAnchor then
					anchor = WhoaUF:CaptureEditModeLayoutAnchor(key, frame)
				end
			else
				if WhoaUF.CaptureEditModeLayoutAnchor then
					anchor = WhoaUF:CaptureEditModeLayoutAnchor(key, frame)
				end
				anchor = anchor or CaptureFrameAnchor(frame) or CaptureSystemAnchorInfo(frame)
			end
			if anchor then
				capturedAnchors[key] = anchor
			end
		end
	end

	-- Party: Edit Mode layout fields only (never PartyFrame).
	if WhoaUF.CaptureEditModeLayoutAnchor then
		local anchor = WhoaUF:CaptureEditModeLayoutAnchor("party")
		if anchor then
			capturedAnchors.party = anchor
		end
	end
end

function WhoaUF:GetBlizzardUnitFrameAnchor(key)
	return capturedAnchors[key]
end

-- ---------------------------------------------------------------------------
-- Mute stock unit-frame runtime while Whoa is enabled.
-- Mainline: UnregisterAllEvents only — do not SetScript on stock unit chrome
-- (Scripts / EventRegistrations Swatter). Concealing alone leaves
-- PLAYER_TARGET_CHANGED etc. running Whoa-object-tainted Update →
-- UnitFrameHealthBar_Update secret maxValue compares.
-- ---------------------------------------------------------------------------

-- securecall only blocks taint from reaching the caller; the callee still runs
-- with Whoa's taint. Never use it to clear Mainline stock Update paths
-- that Lua-compare secret UnitHealth/UnitPower (see docs/retail-phase1.md).
local function SecureBlizzardCall(func, ...)
	if type(func) ~= "function" then
		return
	end
	if securecall then
		return securecall(func, ...)
	end
	return func(...)
end

local function SecureFrameMethod(frame, method, ...)
	if not frame then
		return
	end
	local fn = frame[method]
	if type(fn) ~= "function" then
		return
	end
	return SecureBlizzardCall(fn, frame, ...)
end

local mainlineClassPowerMuteNames = {
	WarlockPowerFrame = true,
	PaladinPowerBarFrame = true,
	MonkHarmonyBarFrame = true,
	MonkStaggerBar = true,
	RuneFrame = true,
	PlayerFrameAlternateManaBar = true,
	AlternatePowerBar = true,
	RogueComboPointBarFrame = true,
	DruidComboPointBarFrame = true,
	ComboPointPlayerFrame = true,
}

local function UnregisterEventsOnly(f)
	if not f or not f.UnregisterAllEvents then
		return
	end
	if f.IsForbidden and f:IsForbidden() then
		return
	end
	f:UnregisterAllEvents()
end

-- Silence stock unit-frame event paths without SetScript.
local function MuteMainlineUnitFrameEvents(frame)
	if not IsUIFrame(frame) then
		return
	end
	UnregisterEventsOnly(frame)
	UnregisterEventsOnly(frame.HealthBar or frame.healthbar)
	UnregisterEventsOnly(frame.PowerBar or frame.ManaBar or frame.manabar)
	UnregisterEventsOnly(frame.spellbar or frame.SpellBar)
	UnregisterEventsOnly(frame.petFrame or frame.PetFrame)
	local tot = frame.totFrame
	if tot then
		UnregisterEventsOnly(tot)
		UnregisterEventsOnly(tot.HealthBar or tot.healthbar)
		UnregisterEventsOnly(tot.PowerBar or tot.ManaBar or tot.manabar)
	end
	UnregisterEventsOnly(frame.PowerBarAlt)
	-- Mainline Target/Focus nest bars under TargetFrameContent (not legacy globals).
	local content = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
	if content then
		local bars = content.HealthBarsContainer
		if bars then
			UnregisterEventsOnly(bars.HealthBar)
			UnregisterEventsOnly(bars.TempMaxHealthLoss)
		end
		UnregisterEventsOnly(content.ManaBar)
	end
	if frame == PlayerFrame then
		if PlayerFrame_GetHealthBar then
			UnregisterEventsOnly(PlayerFrame_GetHealthBar())
		end
		if PlayerFrame_GetManaBar then
			UnregisterEventsOnly(PlayerFrame_GetManaBar())
		end
	end
end

local function MuteMainlineClassPowerEvents(frame)
	if not IsUIFrame(frame) or not frame.UnregisterAllEvents then
		return
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end
	local name = frame.GetName and frame:GetName()
	if not name or not mainlineClassPowerMuteNames[name] then
		return
	end
	-- Unregister only — do not SetScript(nil) on Mainline stock widgets.
	frame:UnregisterAllEvents()
end

local function MuteFrameRuntime(frame)
	if not IsUIFrame(frame) then
		return
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end
	local orig = originals[frame]
	if not orig then
		return
	end
	-- Hide alone is not enough: TargetFrame still receives PLAYER_TARGET_CHANGED
	-- and runs Update while object-tainted from Whoa's SetParent/Hide.
	-- Re-run unregister every mute (events can return via Blizzard paths).
	MuteMainlineUnitFrameEvents(frame)
	for i = 1, #extraMuteGlobals do
		UnregisterEventsOnly(_G[extraMuteGlobals[i]])
	end
	orig.mutedBucket = nil
	orig.runtimeMuted = true
end

local function UnmuteFrameRuntime(frame)
	local orig = originals[frame]
	if not orig or not orig.runtimeMuted then
		return
	end
	orig.mutedBucket = nil
	orig.runtimeMuted = false
end

local function ReregisterStatusBars(unit, healthbar, manabar)
	-- Mainline mute never clears scripts — only re-Register events. SetScript
	-- from Whoa would taint the stock OnEvent/OnUpdate path.
	if healthbar and unit then
		pcall(function()
			if not (healthbar.frequentUpdates and UnitFrameHealthBar_OnUpdate) then
				healthbar:RegisterUnitEvent("UNIT_HEALTH", unit)
			end
			healthbar:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
		end)
	end
	if manabar then
		if manabar.frequentUpdates and UnitFrameManaBar_UnregisterDefaultEvents then
			-- keep OnUpdate; default events stay off while frequent
		elseif UnitFrameManaBar_RegisterDefaultEvents then
			UnitFrameManaBar_RegisterDefaultEvents(manabar)
		end
		pcall(function()
			manabar:RegisterEvent("UNIT_DISPLAYPOWER")
		end)
	end
end

local function ReregisterUnitFrameBase(frame, unit)
	if not frame or not unit then
		return
	end
	pcall(function()
		frame:RegisterEvent("UNIT_NAME_UPDATE")
		frame:RegisterEvent("UNIT_DISPLAYPOWER")
		frame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
		frame:RegisterEvent("PORTRAITS_UPDATED")
	end)
	local health = frame.HealthBar or frame.healthbar
	local mana = frame.PowerBar or frame.ManaBar or frame.manabar
	ReregisterStatusBars(unit, health, mana)
end

local function ReregisterSpellbar(spellbar, updateEvent)
	if not spellbar then
		return
	end
	pcall(function()
		spellbar:RegisterEvent("CVAR_UPDATE")
		spellbar:RegisterEvent("VARIABLES_LOADED")
		if updateEvent then
			spellbar.updateEvent = updateEvent
			spellbar:RegisterEvent(updateEvent)
		elseif spellbar.updateEvent then
			spellbar:RegisterEvent(spellbar.updateEvent)
		end
	end)
end

local function ReregisterPlayerFrame()
	local self = PlayerFrame
	if not self then
		return
	end
	pcall(function()
		self:RegisterEvent("UNIT_LEVEL")
		self:RegisterEvent("UNIT_FACTION")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("PLAYER_ENTER_COMBAT")
		self:RegisterEvent("PLAYER_LEAVE_COMBAT")
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("PLAYER_UPDATE_RESTING")
		self:RegisterEvent("PARTY_LEADER_CHANGED")
		self:RegisterEvent("GROUP_ROSTER_UPDATE")
		self:RegisterEvent("READY_CHECK")
		self:RegisterEvent("READY_CHECK_CONFIRM")
		self:RegisterEvent("READY_CHECK_FINISHED")
		self:RegisterEvent("UNIT_ENTERED_VEHICLE")
		self:RegisterEvent("UNIT_ENTERING_VEHICLE")
		self:RegisterEvent("UNIT_EXITING_VEHICLE")
		self:RegisterEvent("UNIT_EXITED_VEHICLE")
		self:RegisterEvent("PLAYER_FLAGS_CHANGED")
		self:RegisterEvent("PLAYTIME_CHANGED")
		self:RegisterUnitEvent("UNIT_COMBAT", "player", "vehicle")
		self:RegisterUnitEvent("UNIT_MAXPOWER", "player", "vehicle")
	end)
	ReregisterUnitFrameBase(self, self.unit or "player")
	local health = PlayerFrame_GetHealthBar and PlayerFrame_GetHealthBar() or self.HealthBar
	local mana = PlayerFrame_GetManaBar and PlayerFrame_GetManaBar() or self.ManaBar
	ReregisterStatusBars(self.unit or "player", health, mana)
end

local function ReregisterTargetLikeFrame(frame, unit, changedEvent)
	if not frame or not unit then
		return
	end
	pcall(function()
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		frame:RegisterEvent("UNIT_HEALTH")
		if frame.showLevel then
			frame:RegisterEvent("UNIT_LEVEL")
		end
		frame:RegisterEvent("UNIT_FACTION")
		if frame.showClassification then
			frame:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
		end
		if frame.showLeader then
			frame:RegisterEvent("PLAYER_FLAGS_CHANGED")
		end
		frame:RegisterEvent("GROUP_ROSTER_UPDATE")
		frame:RegisterEvent("RAID_TARGET_UPDATE")
		frame:RegisterUnitEvent("UNIT_AURA", unit)
		frame:RegisterUnitEvent("UNIT_TARGET", unit)
		if changedEvent then
			frame:RegisterEvent(changedEvent)
		end
	end)
	ReregisterUnitFrameBase(frame, unit)
	ReregisterSpellbar(frame.spellbar, changedEvent)
	local tot = frame.totFrame
	if tot then
		ReregisterUnitFrameBase(tot, tot.unit)
	end
end

local function ReregisterPetFrame()
	local self = PetFrame
	if not self then
		return
	end
	pcall(function()
		self:RegisterUnitEvent("UNIT_PET", "player")
		self:RegisterEvent("PET_ATTACK_START")
		self:RegisterEvent("PET_ATTACK_STOP")
		self:RegisterEvent("PET_UI_UPDATE")
		self:RegisterEvent("UNIT_HAPPINESS")
		self:RegisterEvent("UNIT_MAXPOWER")
		self:RegisterUnitEvent("UNIT_COMBAT", "pet", "player")
		self:RegisterUnitEvent("UNIT_AURA", "pet", "player")
	end)
	ReregisterUnitFrameBase(self, self.unit or "pet")
	if PetCastingBarFrame and PetCastingBarFrame.OnLoad then
		pcall(function()
			PetCastingBarFrame:OnLoad()
		end)
	end
end

local function ReregisterPartyMemberFrame(frame)
	if not frame then
		return
	end
	local unit = frame.unitToken or frame.unit
	pcall(function()
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		frame:RegisterEvent("GROUP_ROSTER_UPDATE")
		frame:RegisterEvent("UPDATE_ACTIVE_BATTLEFIELD")
		frame:RegisterEvent("PARTY_LEADER_CHANGED")
		frame:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
		frame:RegisterEvent("UNIT_FACTION")
		frame:RegisterEvent("VARIABLES_LOADED")
		frame:RegisterEvent("READY_CHECK")
		frame:RegisterEvent("READY_CHECK_CONFIRM")
		frame:RegisterEvent("READY_CHECK_FINISHED")
		frame:RegisterEvent("UNIT_CONNECTION")
		frame:RegisterEvent("PARTY_MEMBER_ENABLE")
		frame:RegisterEvent("PARTY_MEMBER_DISABLE")
		frame:RegisterEvent("UNIT_PHASE")
		frame:RegisterEvent("UNIT_FLAGS")
		frame:RegisterEvent("UNIT_OTHER_PARTY_CHANGED")
		if unit then
			frame:RegisterUnitEvent("UNIT_AURA", unit, frame.petUnitToken)
			frame:RegisterUnitEvent("UNIT_PET", unit, frame.petUnitToken)
		end
	end)
	if unit then
		ReregisterUnitFrameBase(frame, unit)
	end
end

local function ReregisterTotemFrame()
	local self = TotemFrame
	if not self then
		return
	end
	pcall(function()
		self:RegisterEvent("PLAYER_TOTEM_UPDATE")
		self:RegisterEvent("PLAYER_ENTERING_WORLD")
		self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		self:RegisterEvent("PLAYER_TALENT_UPDATE")
		self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	end)
end

local function ReregisterComboFrame()
	local frame = ComboFrame
	if not frame then
		return
	end
	-- Mirrors ComboFrame_OnLoad: stock target gems only run when the CVar asks for them.
	if GetCVar and GetCVar("comboPointLocation") ~= "1" then
		return
	end
	pcall(function()
		frame:RegisterEvent("PLAYER_TARGET_CHANGED")
		pcall(function()
			frame:RegisterEvent("COMBO_TARGET_CHANGED")
		end)
		frame:RegisterEvent("UNIT_POWER_FREQUENT")
		frame:RegisterEvent("UNIT_MAXPOWER")
		frame:RegisterEvent("PLAYER_ENTERING_WORLD")
		pcall(function()
			frame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
			frame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
		end)
	end)
	-- Init state without ComboFrame_UpdateMax/Update (writes COMBO_FRAME_LAST_NUM_POINTS).
	SecureBlizzardCall(function()
		if frame.ComboPoints and frame.ComboPoints[1] then
			frame.ComboPoints[1].Highlight:SetAlpha(0)
			frame.ComboPoints[1].Shine:SetAlpha(0)
		end
		frame.unit = "player"
		local comboPower = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
		frame.maxComboPoints = UnitPowerMax("player", comboPower)
		COMBO_FRAME_LAST_NUM_POINTS = 0
	end)
end

local function ReregisterClassPowerFrames()
	local frames = {
		PaladinPowerBarFrame,
		ShardBarFrame,
		WarlockPowerFrame,
		EclipseBarFrame,
		PriestBarFrame,
		MonkHarmonyBarFrame,
		MonkStaggerBar,
		RuneFrame,
	}
	for i = 1, #frames do
		local frame = frames[i]
		if IsUIFrame(frame) and frame.OnLoad then
			pcall(function()
				frame:OnLoad()
			end)
		end
	end
end

local function ReregisterBlizzardUnitFrames()
	ReregisterPlayerFrame()
	ReregisterTargetLikeFrame(TargetFrame, "target", "PLAYER_TARGET_CHANGED")
	ReregisterTargetLikeFrame(FocusFrame, "focus", "PLAYER_FOCUS_CHANGED")
	ReregisterPetFrame()
	ReregisterTotemFrame()
	ReregisterComboFrame()
	ReregisterClassPowerFrames()
	for i = 1, 4 do
		ReregisterPartyMemberFrame(_G["PartyMemberFrame" .. i])
	end
end

-- Concealed frames stay shown and parented where Blizzard put them; only alpha
-- and mouse change. Stock frames share LOW strata with Whoa frames (TargetFrame
-- sits at level 500), so invisible stock chrome would still eat clicks/hover.
local MOUSE_SCAN_DEPTH = 8

-- Concealed on their own; a parent's mouse scan skips them so Edit Mode preview
-- can re-enable one (e.g. PetFrame under PlayerFrame) without its parent.
local concealRootNames = {
	TargetFrameToT = true,
	FocusFrameToT = true,
	TargetFrameSpellBar = true,
	FocusFrameSpellBar = true,
}
for i = 1, #blizzardFrames do
	concealRootNames[blizzardFrames[i]] = true
end
for i = 1, #swappableBlizzardFrameNames do
	concealRootNames[swappableBlizzardFrameNames[i]] = true
end

-- IsMouseEnabled / IsForbidden can return secret booleans (bars with secret
-- values). Never `if frame:IsMouseEnabled() then` — use CanAccessValue /
-- IsAccessibleTrue. Secret or true → snapshot for EnableMouse(false) while
-- concealed; restore turns those back on (same idea as DisableStockPartyMouse).
local function CollectMouseChildren(root, frame, list, depth)
	if depth > MOUSE_SCAN_DEPTH then
		return
	end
	local children = { frame:GetChildren() }
	for i = 1, #children do
		local child = children[i]
		local name = child.GetName and child:GetName()
		local forbidden = child.IsForbidden and child:IsForbidden()
		if child ~= root.Selection
			and not (name and concealRootNames[name])
			and not WhoaUF:IsAccessibleTrue(forbidden)
		then
			local enabled = child.IsMouseEnabled and child:IsMouseEnabled()
			if (not WhoaUF:CanAccessValue(enabled)) or WhoaUF:IsAccessibleTrue(enabled) then
				list[#list + 1] = child
			end
			CollectMouseChildren(root, child, list, depth + 1)
		end
	end
end

local function SnapshotMouseEnabled(frame)
	if not frame or not frame.IsMouseEnabled then
		return false
	end
	local enabled = frame:IsMouseEnabled()
	if not WhoaUF:CanAccessValue(enabled) then
		return true
	end
	return WhoaUF:IsAccessibleTrue(enabled)
end

local function EnsureOriginals(frame)
	if not IsUIFrame(frame) then
		return nil
	end
	local orig = originals[frame]
	if not orig then
		orig = {
			mouse = SnapshotMouseEnabled(frame),
			mouseChildren = {},
		}
		if frame.GetChildren then
			CollectMouseChildren(frame, frame, orig.mouseChildren, 1)
		end
		originals[frame] = orig
	end
	return orig
end

local function ConcealFrame(frame, orig)
	frame:SetAlpha(0)
	if orig.mouse then
		frame:EnableMouse(false)
	end
	local children = orig.mouseChildren
	for i = 1, #children do
		children[i]:EnableMouse(false)
	end
	orig.concealed = true
end

local function RevealFrame(frame, orig)
	if not orig.concealed then
		return
	end
	frame:SetAlpha(1)
	if orig.mouse then
		frame:EnableMouse(true)
	end
	local children = orig.mouseChildren
	for i = 1, #children do
		children[i]:EnableMouse(true)
	end
	orig.concealed = nil
end

-- Selection is ignoreParentAlpha, so it stays visible and clickable in Edit
-- Mode over a concealed parent unless concealed too. It has no OnHide/OnShow;
-- alpha + mouse still avoids fighting Blizzard's Show on Edit Mode enter.
-- While Edit Mode is open, Whoa reveals Selection on stock P/T/F/Party so the
-- registered Blizzard systems stay draggable under Whoa chrome (CUF-safe —
-- Whoa never RegisterSystemFrame). ApplyBlizzardFrames must not re-conceal it.
--
-- Target/Focus use defaultHideSelection + ShouldShowTargetFrame Hide when the
-- unit is gone. Whoa also mutes their Update, so AccountSettings RefreshTargetAndFocus
-- TargetUnit("player") never Shows the stock parent — Selection stays inert.
-- EnsureEditModeStockTargetFocusParents Shows the concealed parents while preview
-- is on so Blizzard HighlightSystem / Selection hits work (Player always Shown).
local editModeSelectionInteractive

local function ConcealEditModeChrome(frame, orig)
	if editModeSelectionInteractive then
		return
	end
	local selection = frame.Selection
	if not selection then
		return
	end
	if orig.selectionMouse == nil then
		orig.selectionMouse = SnapshotMouseEnabled(selection)
	end
	selection:SetAlpha(0)
	if orig.selectionMouse then
		selection:EnableMouse(false)
	end
end

local function RevealEditModeChrome(frame, orig)
	local selection = frame.Selection
	if not selection then
		return
	end
	if orig.selectionMouse == nil then
		orig.selectionMouse = SnapshotMouseEnabled(selection)
	end
	selection:SetAlpha(1)
	if orig.selectionMouse then
		selection:EnableMouse(true)
	end
end

-- Stock UnitFrame systems Whoa mirrors in Edit Mode (never claim these slots).
local editModeSelectionOwners = {
	"PlayerFrame",
	"TargetFrame",
	"FocusFrame",
	"PartyFrame",
}

local editModeTargetFocusParents = {
	"TargetFrame",
	"FocusFrame",
}

-- Show concealed Target/Focus parents so Selection can receive Edit Mode input.
-- Art stays alpha 0; events stay muted. Do not call HighlightSystem (taint).
function WhoaUF:EnsureEditModeStockTargetFocusParents()
	if InCombatLockdown() then
		return
	end
	local show = editModeSelectionInteractive
		and self.IsEditModeTargetFocusPreviewEnabled
		and self:IsEditModeTargetFocusPreviewEnabled()
	for i = 1, #editModeTargetFocusParents do
		local frame = _G[editModeTargetFocusParents[i]]
		if IsUIFrame(frame) then
			if show then
				if not frame:IsShown() then
					frame:Show()
				end
			elseif frame:IsShown() and frame.unit and not UnitExists(frame.unit) then
				-- Preview off / exit path may leave a mute-stuck Show; hide if empty.
				frame:Hide()
			end
		end
	end
end

-- Reveal Selection only (art stays alpha 0). PartyFrame is never ConcealBlizzardFrame'd —
-- touch its Selection directly; do not EnsureOriginals (MemberFrame mouse walk).
function WhoaUF:SetEditModeSystemSelectionInteractive(interactive)
	editModeSelectionInteractive = interactive and true or nil
	for i = 1, #editModeSelectionOwners do
		local name = editModeSelectionOwners[i]
		local frame = _G[name]
		if not (IsUIFrame(frame) and frame.Selection) then
			-- skip
		elseif interactive then
			local orig = originals[frame]
			if not orig and name ~= "PartyFrame" then
				orig = EnsureOriginals(frame)
			end
			local selection = frame.Selection
			if orig then
				RevealEditModeChrome(frame, orig)
			else
				selection:SetAlpha(1)
				selection:EnableMouse(true)
			end
			-- Sit above Whoa LOW-strata chrome so Selection receives drag/select.
			if orig and orig.selectionLevel == nil then
				orig.selectionLevel = selection:GetFrameLevel()
			elseif not orig and selection.whoaUFSelectionLevel == nil then
				selection.whoaUFSelectionLevel = selection:GetFrameLevel()
			end
			selection:SetFrameLevel(10000)
		else
			local orig = originals[frame]
			local selection = frame.Selection
			if orig then
				-- Force conceal even though the interactive flag cleared above.
				if orig.selectionMouse == nil then
					orig.selectionMouse = SnapshotMouseEnabled(selection)
				end
				selection:SetAlpha(0)
				if orig.selectionMouse then
					selection:EnableMouse(false)
				end
				if orig.selectionLevel ~= nil then
					selection:SetFrameLevel(orig.selectionLevel)
					orig.selectionLevel = nil
				end
			else
				selection:SetAlpha(0)
				selection:EnableMouse(false)
				if selection.whoaUFSelectionLevel ~= nil then
					selection:SetFrameLevel(selection.whoaUFSelectionLevel)
					selection.whoaUFSelectionLevel = nil
				end
			end
		end
	end
	if interactive then
		self:EnsureEditModeStockTargetFocusParents()
	end
end

local function RestoreDefaultFrame(frame)
	if not IsUIFrame(frame) then
		return
	end
	local orig = originals[frame]
	if not orig then
		return
	end
	UnmuteFrameRuntime(frame)
	RevealEditModeChrome(frame, orig)
	RevealFrame(frame, orig)
end

-- ToT / spellbar stay parented to TargetFrame / FocusFrame (spellbar OnShow →
-- AdjustPosition reads the parent's auraRows). Events off + conceal only.
local function MuteTargetSubframe(subframe)
	if not IsUIFrame(subframe) then
		return
	end
	local orig = EnsureOriginals(subframe)
	MuteFrameRuntime(subframe)
	ConcealFrame(subframe, orig)
end

local function ConcealBlizzardFrame(frame)
	if not IsUIFrame(frame) then
		return
	end
	if frame.IsForbidden and WhoaUF:IsAccessibleTrue(frame:IsForbidden()) then
		return
	end
	local orig = EnsureOriginals(frame)
	MuteFrameRuntime(frame)
	MuteMainlineClassPowerEvents(frame)
	ConcealEditModeChrome(frame, orig)
	ConcealFrame(frame, orig)
end

-- PartyFrame / CompactPartyFrame / CompactRaidFrameContainer are Blizzard-owned.
-- Never HidePartyFrames, hook/replace UpdatePartyFrames / RefreshMembers, or
-- call UseRaidStylePartyFrames() from Whoa — object/execution taint poisons
-- CompactParty → CUF secret oldR and EditModeFrameSetup → CooldownViewer /
-- DamageMeter. Classic mutes/guards party in Blizzard_Classic.lua only.
-- API kept as a no-op so shared Party.lua callers never nil-error.
function WhoaUF:SuppressMainlineStockClassicParty()
end

-- ---------------------------------------------------------------------------
-- Forever/Camelot only: event mute on MemberFrame1-4. Cuts the MemberFrame
-- OnEvent(GROUP_ROSTER) → UpdateMember path. Does NOT replace PartyFrame /
-- CompactPartyFrame methods (Edit Mode enter taint).
-- ---------------------------------------------------------------------------

local function IsCamelotClient()
	return WhoaUF.IsCamelot and WhoaUF:IsCamelot()
end

local function CamelotRaidStylePartyActive()
	if WhoaUF.IsRaidStylePartyFramesEnabled then
		return WhoaUF:IsRaidStylePartyFramesEnabled()
	end
	return false
end

local function CamelotWhoaOwnsClassicParty()
	return ShouldHideDefaults() and not CamelotRaidStylePartyActive()
end

local function MuteStockPartyMemberEvents()
	local party = PartyFrame
	if not party then
		return
	end
	for i = 1, 4 do
		local frame = party["MemberFrame" .. i]
		if IsUIFrame(frame) then
			UnregisterEventsOnly(frame)
			UnregisterEventsOnly(frame.PetFrame)
			local health = frame.HealthBarContainer and frame.HealthBarContainer.HealthBar
			UnregisterEventsOnly(health)
			UnregisterEventsOnly(frame.ManaBar)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Stock classic-style party members (PartyFrame.MemberFrame1-4: pooled, no
-- globals) and PartyFrame.Background overlap Whoa party when raid-style is off.
-- Conceal = alpha 0 + mouse off. Field reads only on PartyFrame; never call its
-- methods or touch CompactPartyFrame. Never Hide/Show/SetParent the members
-- (OnShow/OnHide → Edit Mode taint / CUF oldR). Forever also mutes MemberFrame
-- events (MuteStockPartyMemberEvents) — not method stubs.
--
-- Do NOT hooksecurefunc MemberFrame SetAlpha: UpdateMember calls
-- UpdateNotPresentIcon → SetAlpha mid-function, then UpdateArt →
-- UnitFrame_SetUnit → UnitFrameHealthBar_Update. A SetAlpha post-hook that
-- re-enters SetAlpha from Whoa leaves that same UpdateMember turn tainted on
-- Forever, so secret maxValue/currValue compares fail (Edit Mode
-- RefreshPartyFrames → UpdateRaidAndPartyFrames). Re-zero via deferred
-- UpdateRaidAndPartyFrames / roster / aura conceal only.
-- Mouse writes on secure members are combat-protected.
-- Ref: Blizzard_UnitFrame/Shared/PartyFrame.lua, Mainline/PartyMemberFrame.lua
-- ---------------------------------------------------------------------------

local stockPartyKeys = { "MemberFrame1", "MemberFrame2", "MemberFrame3", "MemberFrame4", "Background" }
-- Restore flags: 1 = click only, 2 = motion only, 3 = both, 0 = unknown.
-- Bars holding secret values return secret mouse getters (no boolean test, and
-- the setters reject secrets), so unknown stays off until /reload.
local MOUSE_UNKNOWN, MOUSE_CLICK_ONLY, MOUSE_MOTION_ONLY, MOUSE_BOTH = 0, 1, 2, 3
local stockPartyConcealed
local pendingStockPartyMouse
local stockPartyQueued
local stockPartyQueuedForceMouse
local stockPartyLastMouseWalk = 0
-- Join floods UNIT_AURA as stock aura buttons spawn; full mouse walks hitch.
local STOCK_PARTY_MOUSE_WALK_GAP = 0.35
local stockPartySeen = {}
local stockPartyAlpha = {}
local stockPartyMouse = {}
local stockPartyPostHooks

local function DisableStockPartyMouse(...)
	for i = 1, select("#", ...) do
		local frame = select(i, ...)
		if frame and not (frame.IsForbidden and frame:IsForbidden()) then
			local enabled = frame.IsMouseEnabled and frame:IsMouseEnabled()
			if not WhoaUF:CanAccessValue(enabled) then
				if stockPartyMouse[frame] == nil then
					stockPartyMouse[frame] = MOUSE_UNKNOWN
				end
				frame:EnableMouse(false)
			elseif enabled then
				if stockPartyMouse[frame] == nil then
					local click = frame:IsMouseClickEnabled()
					local motion = frame:IsMouseMotionEnabled()
					if not (WhoaUF:CanAccessValue(click) and WhoaUF:CanAccessValue(motion)) then
						stockPartyMouse[frame] = MOUSE_UNKNOWN
					else
						stockPartyMouse[frame] = (click and motion and MOUSE_BOTH)
							or (click and MOUSE_CLICK_ONLY)
							or MOUSE_MOTION_ONLY
					end
				end
				frame:EnableMouse(false)
			end
			if frame.GetChildren then
				DisableStockPartyMouse(frame:GetChildren())
			end
		end
	end
end

-- forceMouse: walk EnableMouse off (new aura buttons / first conceal / post-combat).
-- Roster churn while already concealed only re-zeros alpha — Blizzard UpdateMember /
-- UpdateNotPresentIcon can restore opacity, but mouse state usually sticks.
local function ConcealStockParty(forceMouse)
	local party = PartyFrame
	if not party then
		return
	end
	local wasConcealed = stockPartyConcealed
	stockPartyConcealed = true
	local mouseAllowed = not InCombatLockdown()
	local walkMouse = mouseAllowed and (forceMouse or not wasConcealed or pendingStockPartyMouse)
	for i = 1, #stockPartyKeys do
		local frame = party[stockPartyKeys[i]]
		if IsUIFrame(frame) and not (frame.IsForbidden and frame:IsForbidden()) then
			local isNew = not stockPartySeen[frame]
			if isNew then
				stockPartySeen[frame] = true
				local alpha = frame:GetAlpha()
				stockPartyAlpha[frame] = WhoaUF:CanAccessValue(alpha) and alpha or 1
			end
			frame:SetAlpha(0)
			if mouseAllowed and (walkMouse or isNew) then
				DisableStockPartyMouse(frame)
				stockPartyLastMouseWalk = GetTime()
			end
		end
	end
	-- Forever: drop MemberFrame GROUP_ROSTER/UNIT_* so OnEvent cannot UpdateMember.
	if IsCamelotClient() and CamelotWhoaOwnsClassicParty() then
		MuteStockPartyMemberEvents()
	end
	-- Combat blocks EnableMouse on secure members; replay a full mouse walk on regen.
	pendingStockPartyMouse = (not mouseAllowed) or nil
end

local function RevealStockParty()
	if not stockPartyConcealed then
		return
	end
	stockPartyConcealed = nil
	pendingStockPartyMouse = nil
	stockPartyQueuedForceMouse = nil
	for frame in pairs(stockPartySeen) do
		local alpha = stockPartyAlpha[frame]
		frame:SetAlpha((alpha and alpha > 0) and alpha or 1)
	end
	for frame, flags in pairs(stockPartyMouse) do
		if flags ~= MOUSE_UNKNOWN then
			frame:SetMouseClickEnabled(flags ~= MOUSE_MOTION_ONLY)
			frame:SetMouseMotionEnabled(flags ~= MOUSE_CLICK_ONLY)
		end
	end
	wipe(stockPartyMouse)
end

-- Next frame: Blizzard's own handler for the same event may Acquire members or
-- create aura buttons first.
local function RunQueuedStockPartyConceal()
	stockPartyQueued = nil
	local forceMouse = stockPartyQueuedForceMouse
	stockPartyQueuedForceMouse = nil
	if ShouldHideDefaults() then
		ConcealStockParty(forceMouse)
	end
end

local function QueueStockPartyConceal(forceMouse)
	if not ShouldHideDefaults() then
		return
	end
	if forceMouse then
		stockPartyQueuedForceMouse = true
	end
	if stockPartyQueued then
		return
	end
	stockPartyQueued = true
	C_Timer.After(0, RunQueuedStockPartyConceal)
end

-- After Blizzard finishes UpdateRaidAndPartyFrames (Edit Mode RefreshPartyFrames
-- included). Never hook MemberFrame SetAlpha or mixin UpdateMember helpers —
-- those share the UpdateMember turn with ToPlayerArt → secret health compares.
local function InstallStockPartyPostHooks()
	if stockPartyPostHooks then
		return
	end
	stockPartyPostHooks = true
	if UpdateRaidAndPartyFrames then
		hooksecurefunc("UpdateRaidAndPartyFrames", function()
			if stockPartyConcealed or ShouldHideDefaults() then
				QueueStockPartyConceal(false)
			end
		end)
	end
end

InstallStockPartyPostHooks()

local stockPartyWatcher = CreateFrame("Frame")
stockPartyWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
stockPartyWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
stockPartyWatcher:RegisterUnitEvent("UNIT_AURA", "party1", "party2", "party3", "party4")
stockPartyWatcher:SetScript("OnEvent", function(_, event)
	-- New aura buttons need a mouse walk; defer in combat. Debounce: join aura
	-- storms were walking the full MemberFrame tree every event.
	if event == "UNIT_AURA" then
		if InCombatLockdown() then
			if stockPartyConcealed then
				pendingStockPartyMouse = true
			end
			return
		end
		if stockPartyConcealed
			and (GetTime() - stockPartyLastMouseWalk) < STOCK_PARTY_MOUSE_WALK_GAP
		then
			return
		end
		QueueStockPartyConceal(true)
		return
	end
	-- PEW: full conceal. Roster: alpha re-zero; mouse only if not yet concealed.
	QueueStockPartyConceal(event == "PLAYER_ENTERING_WORLD")
end)

local function RefreshSwappableBlizzardFrames()
	-- Events only; Blizzard's own OnEvent refreshes the preview. Never call stock
	-- OnLoad / Show / Update from Whoa: ClassPowerBar:Setup writes
	-- PlayerFrame.classPowerBar and OnLoad re-registers EventRegistry callbacks
	-- tainted; Show fires OnShow (ManagedFrameMixin) tainted.
	ReregisterTotemFrame()
end

function WhoaUF:IsEditModeBlizzardSwapActive()
	return editModeSwapActive and true or false
end

function WhoaUF:RestoreBlizzardEditModeSwapFrames()
	if not ShouldHideDefaults() or InCombatLockdown() then
		return
	end
	if editModeSwapActive then
		RefreshSwappableBlizzardFrames()
		return
	end
	editModeSwapActive = true

	-- Blizzard Edit Mode owns their shown state (e.g. RefreshPetFrame SetShown);
	-- Whoa only reveals alpha / mouse.
	VisitSwappableBlizzardFrames(RestoreDefaultFrame)
	RefreshSwappableBlizzardFrames()
end

function WhoaUF:DisconnectBlizzardEditModeSwapFrames()
	if not editModeSwapActive and not pendingEditModeSwapDisconnect then
		return
	end
	editModeSwapActive = false
	if not ShouldHideDefaults() then
		pendingEditModeSwapDisconnect = nil
		return
	end
	if InCombatLockdown() then
		pendingEditModeSwapDisconnect = true
		return
	end
	pendingEditModeSwapDisconnect = nil

	VisitSwappableBlizzardFrames(ConcealBlizzardFrame)
end

function WhoaUF:HideWhoaEditModeSwapFrames()
	-- Hide + UnregisterUnitWatch are protected on secure unit buttons.
	if InCombatLockdown() then
		return
	end
	local unitFrames = self.unitFrames
	if not unitFrames then
		return
	end
	local function hideFrame(frame)
		if not frame then
			return
		end
		if UnregisterUnitWatch then
			UnregisterUnitWatch(frame)
		end
		frame:Hide()
	end
	hideFrame(unitFrames.pet)
	hideFrame(unitFrames.tot)
	hideFrame(unitFrames.focustot)
	local player = unitFrames.player
	if player and self.GetRegisteredClassBars then
		local barDefs = self:GetRegisteredClassBars()
		for i = 1, #barDefs do
			local key = barDefs[i].frameKey
			if key and player[key] then
				player[key]:Hide()
			end
		end
	end
	local target = unitFrames.target
	if target and target.ComboFrame then
		target.ComboFrame:Hide()
	end
end

local function RefreshDefaultFrames()
	if WhoaUF.ApplyStockTargetStatusText then
		WhoaUF:ApplyStockTargetStatusText()
	end
	-- Never invoke stock UnitFrame Update from Whoa (secret compares).
	-- Events restored by ReregisterBlizzardUnitFrames refresh bars on the next tick.
end

local function IsSwappableBlizzardFrameName(name)
	if not name then
		return false
	end
	for i = 1, #swappableBlizzardFrameNames do
		if swappableBlizzardFrameNames[i] == name then
			return true
		end
	end
	return false
end

function WhoaUF:ApplyBlizzardFrames()
	if InCombatLockdown() then
		pendingApply = true
		return
	end
	pendingApply = nil

	if ShouldHideDefaults() then
		self:CaptureBlizzardUnitFrameAnchors()
		for _, name in ipairs(blizzardFrames) do
			if not (editModeSwapActive and IsSwappableBlizzardFrameName(name)) then
				ConcealBlizzardFrame(_G[name])
			end
		end
		-- HasBossFrames false: ensure stock Boss1-5 are not left muted from an older session.
		if not (self.HasBossFrames and self:HasBossFrames()) then
			for i = 1, 5 do
				RestoreDefaultFrame(_G["Boss" .. i .. "TargetFrame"])
			end
		end
		if not editModeSwapActive then
			if TargetFrame then
				MuteTargetSubframe(TargetFrame.totFrame)
				MuteTargetSubframe(TargetFrame.spellbar)
				MuteTargetSubframe(_G.TargetFrameSpellBar)
			end
			if FocusFrame then
				MuteTargetSubframe(FocusFrame.totFrame)
				MuteTargetSubframe(FocusFrame.spellbar)
				MuteTargetSubframe(_G.FocusFrameSpellBar)
			end
		end
		-- Members + Background only; PartyFrame / CompactParty untouched on retail.
		ConcealStockParty(true)
		if self.SyncUnitFramePositions then
			self:SyncUnitFramePositions()
		end
		if self.ApplyVehicleXpBarVisibility then
			self:ApplyVehicleXpBarVisibility()
		end
		return
	end

	RevealStockParty()
	if next(originals) then
		for _, name in ipairs(blizzardFrames) do
			RestoreDefaultFrame(_G[name])
		end
		if TargetFrame then
			RestoreDefaultFrame(TargetFrame.totFrame)
			RestoreDefaultFrame(TargetFrame.spellbar)
		end
		if FocusFrame then
			RestoreDefaultFrame(FocusFrame.totFrame)
			RestoreDefaultFrame(FocusFrame.spellbar)
		end
		ReregisterBlizzardUnitFrames()
		RefreshDefaultFrames()
	end
	if self.ApplyVehicleXpBarVisibility then
		self:ApplyVehicleXpBarVisibility()
	end
end

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
combatWatcher:SetScript("OnEvent", function()
	if pendingApply then
		WhoaUF:ApplyBlizzardFrames()
	end
	if pendingEditModeSwapDisconnect then
		WhoaUF:DisconnectBlizzardEditModeSwapFrames()
	end
	if pendingStockPartyMouse and ShouldHideDefaults() then
		ConcealStockParty(true)
	end
end)

-- ---------------------------------------------------------------------------
-- Vehicle XP: OverrideActionBar.UpdateXpBar can show an XP strip on the
-- vehicle bar. Only touch OverrideActionBar.xpBar (alpha).
--
-- Do NOT hooksecurefunc OverrideActionBar.UpdateXpBar — same nil-call class as
-- StatusTrackingBarManager / MainActionBar.UpdateEndCaps / stock SetLook:
-- ActionBarController_UpdateAll → UpdateSkin → Setup → CalcSize → UpdateXpBar
-- crashes with "attempt to call a nil value" when that method is post-hooked.
-- Do NOT hook StatusTrackingBarManager / containers or MainActionBar.UpdateEndCaps.
-- Use xpBar OnShow + vehicle enter/exit events instead.
-- Stock XP on UIParent during vehicle is left to Blizzard.
-- Ref: OverrideActionBar.lua UpdateXpBar / CalcSize, ActionBarController_UpdateAll
-- ---------------------------------------------------------------------------

local function HasVehicleActionBar()
	return C_ActionBar and C_ActionBar.HasVehicleActionBar and C_ActionBar.HasVehicleActionBar()
end

local applyingVehicleXp
local vehicleXpInited

function WhoaUF:ApplyVehicleXpBarVisibility()
	if applyingVehicleXp then
		return
	end
	applyingVehicleXp = true

	local hide = ShouldHideDefaults() and HasVehicleActionBar()
	local overrideXpBar = OverrideActionBar and OverrideActionBar.xpBar
	if overrideXpBar then
		overrideXpBar:SetAlpha(hide and 0 or 1)
	end

	applyingVehicleXp = false
end

local function OnOverrideXpBarShow()
	WhoaUF:ApplyVehicleXpBarVisibility()
end

local vehicleXpHooked

local function HookOverrideActionBarXp()
	if vehicleXpHooked then
		return
	end
	local overrideXpBar = OverrideActionBar and OverrideActionBar.xpBar
	if not overrideXpBar then
		return
	end
	overrideXpBar:HookScript("OnShow", OnOverrideXpBarShow)
	vehicleXpHooked = true
	WhoaUF:ApplyVehicleXpBarVisibility()
end

function WhoaUF:InitVehicleXpBarHide()
	if vehicleXpInited then
		HookOverrideActionBarXp()
		return
	end
	vehicleXpInited = true

	HookOverrideActionBarXp()
	if not vehicleXpHooked then
		WhoaUF:ContinueOnAddOnLoaded("Blizzard_OverrideActionBar", HookOverrideActionBarXp)
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
	pcall(function()
		watcher:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
		watcher:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
	end)
	watcher:SetScript("OnEvent", function()
		WhoaUF:ApplyVehicleXpBarVisibility()
	end)

	WhoaUF:ApplyVehicleXpBarVisibility()
end

-- Keep the old name so earlier load-order call sites still work.
function WhoaUF:InitOverrideActionBarXpHide()
	self:InitVehicleXpBarHide()
end
