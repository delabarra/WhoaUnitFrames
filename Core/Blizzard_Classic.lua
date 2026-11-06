-- Classic-only: mute/hide/restore stock Blizzard unit frames for Classic clients.
-- SetScript clear + UnregisterAllEvents; PartyFrame mute and Classic party guards.
-- Mainline paths live in Blizzard_Mainline.lua (do not load both).
--
-- Why Classic still Hide/reparent (not Mainline alpha-conceal):
--   Classic Edit Mode preview swaps stock ↔ Whoa and needs a real Hide/Show cycle;
--   Classic has no CUF secret `oldR` / Mainline SetClampRectInsets combat path that
--   made Hide under Whoa taint fatal on retail. Mitigations below: clear OnHide/OnShow
--   around SetParent, MuteFrameRuntime, and classicPartyGuards for PartyFrame stubs.
--   A Mainline-style conceal port is a separate project — do not half-apply it here.
if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
	return
end

-- Parent to UIParent: ClassPowerBar:GetUnit walks parent.parent.unit; without
-- this, reparenting to hiddenParent nil-indexs. unit="player" covers one-hop bars.
local hiddenParent = CreateFrame("Frame", nil, UIParent)
hiddenParent:Hide()
hiddenParent:EnableMouse(false)
hiddenParent.unit = "player"

-- TargetOfTargetMixin OnShow/OnHide call parent:ConfigureAuraContainer() /
-- UpdateAuras(). During SetParent that parent is already hiddenParent,
-- so Classic briefly clears those scripts.

local function IsUIFrame(frame)
	return frame ~= nil and type(frame.GetParent) == "function" and type(frame.Hide) == "function"
end

local function ReparentToHiddenParent(frame)
	if not IsUIFrame(frame) then
		return
	end
	local onHide = frame:GetScript("OnHide")
	local onShow = frame:GetScript("OnShow")
	frame:SetScript("OnHide", nil)
	frame:SetScript("OnShow", nil)
	frame:SetParent(hiddenParent)
	frame:SetScript("OnHide", onHide)
	frame:SetScript("OnShow", onShow)
end

local originals = {}
local pendingApply
local capturedAnchors = {}

-- Stock PartyFrame / PartyMember* muted while Whoa party runs.
-- CompactPartyFrame is a child of PartyFrame (CompactPartyFrame_Generate).
-- Classic may mute PartyFrame + PartyMember* as before.
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
	"TotemFrame",
	"WarlockPowerFrame",
	"MonkStaggerBar",
	"RuneFrame",
	-- Boss1-5TargetFrame: stay unmuted while HasBossFrames is false (no Whoa boss chrome).
	"PartyFrame",
	-- Classic class-power frame names (mixin-less).
	"PaladinPowerBar",
	"ShardBarFrame",
	"MonkHarmonyBar",
	-- Classic-only stock chrome.
	"ComboFrame",
	"EclipseBarFrame",
	"PriestBarFrame",
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
local unitFrameAnchorSources = {
	player = "PlayerFrame",
	target = "TargetFrame",
	focus = "FocusFrame",
	party = "PartyFrame",
}

-- Hidden while Whoa runs; stock shown again only during Edit Mode preview swap
-- (player/target/focus/party stay muted — Whoa owns those surfaces).
local swappableBlizzardFrameNames = {
	"PetFrame",
	"PetCastingBarFrame",
	"TotemFrame",
	"WarlockPowerFrame",
	"MonkStaggerBar",
	"PlayerFrameAlternateManaBar",
	"AlternatePowerBar",
	"RuneFrame",
	"PaladinPowerBar",
	"ShardBarFrame",
	"MonkHarmonyBar",
	"ComboFrame",
	"EclipseBarFrame",
	"PriestBarFrame",
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

local function ShowStockFrame(frame)
	if not IsUIFrame(frame) then
		return
	end
	-- Native Show only — never call through addon-replaced Show/SetShown slots
	-- (those taint CompactPartyFrame/PartyFrame combat updates; see EnsureOriginals).
	frame:Show()
	if frame.SetAlpha then
		frame:SetAlpha(1)
	end
end

local function CaptureFrameAnchor(frame)
	if not frame or frame:GetNumPoints() < 1 then
		return nil
	end

	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		return nil
	end
	-- Parent may be hiddenParent while the anchor still targets UIParent / a real frame.
	if relativeTo == hiddenParent then
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

-- Fallback when the stock frame sits under hiddenParent without restorable points.
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
end

function WhoaUF:GetBlizzardUnitFrameAnchor(key)
	return capturedAnchors[key]
end

-- ---------------------------------------------------------------------------
-- Mute stock unit-frame runtime (events + OnUpdate) while Whoa is enabled.
-- Hide alone still leaves Blizzard handling UNIT_AURA / health ticks invisible.
-- Restore reattaches scripts then re-registers events (UnregisterAllEvents is
-- not reversible without an explicit register pass).
-- ---------------------------------------------------------------------------

-- securecall only blocks taint from reaching the caller; the callee still runs
-- with Whoa's taint. Classic: securecall still helps Edit Mode paths that touch
-- TargetFrameBuff1. ComboFrame_Update assigns COMBO_FRAME_LAST_NUM_POINTS —
-- never invoke that chain from addon/settings restore; re-register events and
-- reset the global only.
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

local function MuteOne(f, bucket)
	if not f or not f.UnregisterAllEvents then
		return
	end
	if f.IsForbidden and f:IsForbidden() then
		return
	end
	for i = 1, #bucket do
		if bucket[i].frame == f then
			return
		end
	end
	bucket[#bucket + 1] = {
		frame = f,
		OnEvent = f:GetScript("OnEvent"),
		OnUpdate = f:GetScript("OnUpdate"),
	}
	f:UnregisterAllEvents()
	f:SetScript("OnEvent", nil)
	f:SetScript("OnUpdate", nil)
end

local function CollectUnitFrameMuteTargets(frame, bucket, depth)
	if not frame or (depth or 0) > 8 then
		return
	end
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end
	MuteOne(frame, bucket)
	MuteOne(frame.HealthBar or frame.healthbar, bucket)
	MuteOne(frame.PowerBar or frame.ManaBar or frame.manabar, bucket)
	MuteOne(frame.spellbar or frame.SpellBar, bucket)
	MuteOne(frame.petFrame or frame.PetFrame, bucket)
	MuteOne(frame.totFrame, bucket)
	MuteOne(frame.PowerBarAlt, bucket)
	if frame.GetChildren then
		local children = { frame:GetChildren() }
		for i = 1, #children do
			CollectUnitFrameMuteTargets(children[i], bucket, (depth or 0) + 1)
		end
	end
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
	if orig.runtimeMuted then
		return
	end
	local bucket = {}
	CollectUnitFrameMuteTargets(frame, bucket, 0)
	if frame == PlayerFrame then
		if PlayerFrame_GetHealthBar then
			MuteOne(PlayerFrame_GetHealthBar(), bucket)
		end
		if PlayerFrame_GetManaBar then
			MuteOne(PlayerFrame_GetManaBar(), bucket)
		end
	end
	for i = 1, #extraMuteGlobals do
		MuteOne(_G[extraMuteGlobals[i]], bucket)
	end
	orig.mutedBucket = bucket
	orig.runtimeMuted = true
end

local function UnmuteFrameRuntime(frame)
	local orig = originals[frame]
	if not orig or not orig.runtimeMuted then
		return
	end
	local bucket = orig.mutedBucket
	if bucket then
		for i = 1, #bucket do
			local entry = bucket[i]
			local f = entry.frame
			if f and not (f.IsForbidden and f:IsForbidden()) then
				f:SetScript("OnEvent", entry.OnEvent)
				f:SetScript("OnUpdate", entry.OnUpdate)
			end
		end
	end
	orig.mutedBucket = nil
	orig.runtimeMuted = false
end

local function ReregisterStatusBars(unit, healthbar, manabar)
	if healthbar then
		if healthbar.frequentUpdates and UnitFrameHealthBar_OnUpdate then
			healthbar:SetScript("OnUpdate", UnitFrameHealthBar_OnUpdate)
		elseif unit then
			pcall(function()
				healthbar:RegisterUnitEvent("UNIT_HEALTH", unit)
			end)
		end
		if unit then
			pcall(function()
				healthbar:RegisterUnitEvent("UNIT_MAXHEALTH", unit)
			end)
		end
		if UnitFrameHealthBar_OnEvent then
			healthbar:SetScript("OnEvent", UnitFrameHealthBar_OnEvent)
		end
	end
	if manabar then
		if manabar.frequentUpdates and UnitFrameManaBar_OnUpdate then
			manabar:SetScript("OnUpdate", UnitFrameManaBar_OnUpdate)
			if UnitFrameManaBar_UnregisterDefaultEvents then
				UnitFrameManaBar_UnregisterDefaultEvents(manabar)
			end
		elseif UnitFrameManaBar_RegisterDefaultEvents then
			UnitFrameManaBar_RegisterDefaultEvents(manabar)
		end
		pcall(function()
			manabar:RegisterEvent("UNIT_DISPLAYPOWER")
		end)
		if UnitFrameManaBar_OnEvent then
			manabar:SetScript("OnEvent", UnitFrameManaBar_OnEvent)
		end
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
		PaladinPowerBar,
		ShardBarFrame,
		WarlockPowerFrame,
		EclipseBarFrame,
		PriestBarFrame,
		MonkHarmonyBar,
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

-- Clear Lua Show/SetShown shadows so the widget metatable's native C methods
-- are used. Replacing those slots (old Whoa hide-guard) permanently taints
-- Blizzard combat paths: UpdateRaidAndPartyFrames → CompactPartyFrame:SetShown
-- → PartyFrame:UpdatePartyFrames → SetAttribute/Show blocked (taint.log).
-- Visibility while Whoa runs comes from mute + reparent to hiddenParent instead;
-- Blizzard Show/SetShown under a hidden parent stays off-screen.
local function ClearStockVisibilityOverrides(frame)
	if not IsUIFrame(frame) then
		return
	end
	frame.Show = nil
	frame.SetShown = nil
end

local function EnsureOriginals(frame)
	if not IsUIFrame(frame) then
		return nil
	end
	if not originals[frame] then
		originals[frame] = {
			parent = frame:GetParent(),
			mouse = frame.IsMouseEnabled and frame:IsMouseEnabled(),
		}
	end
	ClearStockVisibilityOverrides(frame)
	return originals[frame]
end

local function MuteHitTesting(frame, depth)
	if not IsUIFrame(frame) or (depth or 0) > 8 or (frame.IsForbidden and frame:IsForbidden()) then
		return
	end
	if frame.EnableMouse then
		frame:EnableMouse(false)
	end
	if frame.SetMouseClickEnabled then
		frame:SetMouseClickEnabled(false)
	end
	if frame.SetMouseMotionEnabled then
		frame:SetMouseMotionEnabled(false)
	end
	if frame.GetChildren then
		local children = { frame:GetChildren() }
		for i = 1, #children do
			MuteHitTesting(children[i], (depth or 0) + 1)
		end
	end
end

-- Selection is frameStrata MEDIUM, toplevel, ignoreParentAlpha — it stays in
-- fstack/hit-testing after the unit frame is hidden unless we mute it too.
local function MuteEditModeChrome(frame)
	local selection = frame and frame.Selection
	if not selection then
		return
	end
	local orig = originals[frame]
	if orig and orig.selectionParent == nil then
		orig.selectionParent = selection:GetParent()
		orig.selectionMouse = selection.IsMouseEnabled and selection:IsMouseEnabled()
	end
	MuteHitTesting(selection)
	selection:Hide()
	ReparentToHiddenParent(selection)
end

local function RestoreEditModeChrome(frame, orig)
	local selection = frame and frame.Selection
	if not selection then
		return
	end
	if orig and orig.selectionParent then
		selection:SetParent(orig.selectionParent)
	end
	if orig and orig.selectionMouse ~= false and selection.EnableMouse then
		selection:EnableMouse(true)
	end
	if selection.SetMouseClickEnabled then
		selection:SetMouseClickEnabled(true)
	end
end

local function RestoreHitTesting(frame, orig, depth)
	if not frame or (depth or 0) > 8 then
		return
	end
	if (not orig or orig.mouse ~= false) and frame.EnableMouse then
		frame:EnableMouse(true)
	end
	if frame.SetMouseClickEnabled then
		frame:SetMouseClickEnabled(true)
	end
	if frame.GetChildren then
		local children = { frame:GetChildren() }
		for i = 1, #children do
			RestoreHitTesting(children[i], nil, (depth or 0) + 1)
		end
	end
end

local function RestoreDefaultFrame(frame)
	if not IsUIFrame(frame) then
		return
	end
	local orig = originals[frame]
	ClearStockVisibilityOverrides(frame)
	if not orig then
		if frame:GetParent() == hiddenParent then
			frame:SetParent(UIParent)
		end
		UnmuteFrameRuntime(frame)
		return
	end
	UnmuteFrameRuntime(frame)
	RestoreEditModeChrome(frame, orig)
	local parent = orig.parent
	if frame:GetParent() ~= parent then
		frame:SetParent(parent)
	end
	RestoreHitTesting(frame, orig, 0)
end

-- TargetFrameToT / SpellBar stay parented to TargetFrame so spellbar OnShow →
-- AdjustPosition still sees TargetFrame (auraRows), not hiddenParent.
local function MuteTargetSubframe(subframe)
	if not IsUIFrame(subframe) then
		return
	end
	MuteFrameRuntime(subframe)
	subframe:Hide()
end

local function RestoreTargetSubframe(subframe)
	if not IsUIFrame(subframe) then
		return
	end
	UnmuteFrameRuntime(subframe)
end

local function HideSwappableBlizzardFrame(frame)
	if not IsUIFrame(frame) then
		return
	end
	EnsureOriginals(frame)
	MuteFrameRuntime(frame)
	if UnregisterUnitWatch then
		UnregisterUnitWatch(frame)
	end
	MuteHitTesting(frame, 0)
	MuteEditModeChrome(frame)
	ReparentToHiddenParent(frame)
	frame:Hide()
end

-- Classic: after Whoa mutes PartyFrame, UIParent GROUP_ROSTER_UPDATE still runs
-- UpdateRaidAndPartyFrames → PartyFrame:UpdatePartyFrames / CompactParty RefreshMembers.
-- Object taint from Hide/mute makes Show/Hide/SetAttribute/SetSize lockdown errors.
-- Stub those methods to skip protected work while Whoa owns stock party chrome.
--
-- UpdateRaidAndPartyFrames order (Classic RaidFrame.lua):
--   PartyFrame:HidePartyFrames() → CompactRaidFrameManager_UpdateShown → PartyFrame:UpdatePartyFrames()
-- Whoa's HidePartyFrames stub taints the rest of that call, so
-- CompactRaidFrameManager:SetShown() is blocked in combat — defer to PLAYER_REGEN_ENABLED.
local classicPartyGuardsInstalled
local pendingCompactRaidManagerUpdate

local function WhoaOwnsStockPartyChrome()
	return ShouldHideDefaults()
end

local function ClassicRaidStylePartyActive()
	if WhoaUF.IsRaidStylePartyFramesEnabled then
		return WhoaUF:IsRaidStylePartyFramesEnabled()
	end
	return EditModeManagerFrame
		and EditModeManagerFrame.UseRaidStylePartyFrames
		and EditModeManagerFrame:UseRaidStylePartyFrames()
end

--- Shared API name: Mainline used to hide stock classic PartyMember frames here.
--- That path object-tainted PartyFrame → CompactParty CUF oldR errors; Mainline
--- implementation is a permanent no-op in Blizzard_Mainline.lua. Classic no-op too.
function WhoaUF:SuppressMainlineStockClassicParty()
end

local function GuardCompactPartyFrame(frame)
	if not frame or frame.whoaUFCombatGuarded then
		return
	end
	frame.whoaUFCombatGuarded = true

	local origRefresh = frame.RefreshMembers
	local origVisibility = frame.UpdateVisibility

	frame.RefreshMembers = function(self)
		if WhoaOwnsStockPartyChrome() then
			-- Classic Whoa party (non-raid-style): keep CompactParty idle/hidden.
			if not ClassicRaidStylePartyActive() then
				if not InCombatLockdown() then
					self:Hide()
				end
				return
			end
			-- Raid-style CompactParty still cannot resize/attribute in combat once tainted.
			if InCombatLockdown() then
				return
			end
		elseif InCombatLockdown() then
			return
		end
		if type(origRefresh) == "function" then
			return origRefresh(self)
		end
	end

	frame.UpdateVisibility = function(self)
		if WhoaOwnsStockPartyChrome() then
			if not ClassicRaidStylePartyActive() then
				if not InCombatLockdown() then
					self:Hide()
				end
				return
			end
			if InCombatLockdown() then
				return
			end
		elseif InCombatLockdown() then
			return
		end
		if type(origVisibility) == "function" then
			return origVisibility(self)
		end
	end
end

local function FlushPendingCompactRaidManagerUpdate()
	if not pendingCompactRaidManagerUpdate or InCombatLockdown() then
		return
	end
	pendingCompactRaidManagerUpdate = nil
	if CompactRaidFrameManager_UpdateShown and CompactRaidFrameManager then
		CompactRaidFrameManager_UpdateShown(CompactRaidFrameManager)
	end
end

local function InstallClassicPartyUpdateGuards()
	if classicPartyGuardsInstalled or not PartyFrame then
		return
	end
	classicPartyGuardsInstalled = true

	local origUpdatePartyFrames = PartyFrame.UpdatePartyFrames
	local origHidePartyFrames = PartyFrame.HidePartyFrames
	local origUpdatePadding = PartyFrame.UpdatePaddingAndLayout

	PartyFrame.UpdatePartyFrames = function(self)
		if WhoaOwnsStockPartyChrome() then
			-- Never Show/UpdateMember stock classic party while Whoa owns it.
			if not InCombatLockdown() and type(origHidePartyFrames) == "function" then
				origHidePartyFrames(self)
			end
			return
		end
		if InCombatLockdown() then
			return
		end
		if type(origUpdatePartyFrames) == "function" then
			return origUpdatePartyFrames(self)
		end
	end

	PartyFrame.HidePartyFrames = function(self)
		if InCombatLockdown() then
			return
		end
		if type(origHidePartyFrames) == "function" then
			return origHidePartyFrames(self)
		end
	end

	PartyFrame.UpdatePaddingAndLayout = function(self)
		if InCombatLockdown() then
			return
		end
		if type(origUpdatePadding) == "function" then
			return origUpdatePadding(self)
		end
	end

	if CompactPartyFrame then
		GuardCompactPartyFrame(CompactPartyFrame)
	end
	if CompactPartyFrame_Generate then
		hooksecurefunc("CompactPartyFrame_Generate", function()
			GuardCompactPartyFrame(CompactPartyFrame)
		end)
	end

	-- CompactRaidFrameManager_UpdateShown runs mid-UpdateRaidAndPartyFrames after
	-- Whoa's HidePartyFrames stub; skip SetShown in combat, replay on PLAYER_REGEN_ENABLED.
	if CompactRaidFrameManager_UpdateShown then
		local origUpdateShown = CompactRaidFrameManager_UpdateShown
		CompactRaidFrameManager_UpdateShown = function(self)
			if InCombatLockdown() then
				pendingCompactRaidManagerUpdate = true
				return
			end
			pendingCompactRaidManagerUpdate = nil
			if type(origUpdateShown) == "function" then
				return origUpdateShown(self)
			end
		end
	end
end

local function RefreshSwappableBlizzardFrames()
	ReregisterPetFrame()
	ReregisterTotemFrame()
	ReregisterComboFrame()
	ReregisterClassPowerFrames()
	if PetFrame then
		ShowStockFrame(PetFrame)
		SecureFrameMethod(PetFrame, "Update", true)
	end
	if TotemFrame then
		ShowStockFrame(TotemFrame)
		SecureFrameMethod(TotemFrame, "Update")
	end
	if ComboFrame then
		ShowStockFrame(ComboFrame)
	end
end

local function HideDefaultFrame(frame)
	HideSwappableBlizzardFrame(frame)
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

	VisitSwappableBlizzardFrames(function(frame, name)
		if not frame then
			return
		end
		RestoreDefaultFrame(frame)
		ShowStockFrame(frame)
	end)
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

	VisitSwappableBlizzardFrames(HideSwappableBlizzardFrame)
end

function WhoaUF:HideWhoaEditModeSwapFrames()
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
	if PlayerFrame then
		PlayerFrame:Show()
	end
	if PlayerFrame_Update then
		SecureBlizzardCall(PlayerFrame_Update)
	end
	SecureFrameMethod(TargetFrame, "Update")
	SecureFrameMethod(FocusFrame, "Update")
	-- TotemFrame was Hide()'d under the hidden parent; Update() SetShown's active totems.
	SecureFrameMethod(TotemFrame, "Update")
	SecureFrameMethod(PetFrame, "Update")
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
		InstallClassicPartyUpdateGuards()
		for _, name in ipairs(blizzardFrames) do
			if not (editModeSwapActive and IsSwappableBlizzardFrameName(name)) then
				HideDefaultFrame(_G[name])
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
			-- Classic: PartyMember* globals need an explicit mute.
			for i = 1, 4 do
				HideDefaultFrame(_G["PartyMemberFrame" .. i])
				HideDefaultFrame(_G["PartyMemberFrame" .. i .. "PetFrame"])
			end
		end
		if self.SyncUnitFramePositions then
			self:SyncUnitFramePositions()
		end
		if self.ApplyVehicleXpBarVisibility then
			self:ApplyVehicleXpBarVisibility()
		end
		return
	end

	if next(originals) then
		for _, name in ipairs(blizzardFrames) do
			RestoreDefaultFrame(_G[name])
		end
		if TargetFrame then
			RestoreTargetSubframe(TargetFrame.totFrame)
			RestoreTargetSubframe(TargetFrame.spellbar)
		end
		if FocusFrame then
			RestoreTargetSubframe(FocusFrame.totFrame)
			RestoreTargetSubframe(FocusFrame.spellbar)
		end
		for i = 1, 4 do
			RestoreDefaultFrame(_G["PartyMemberFrame" .. i])
			RestoreDefaultFrame(_G["PartyMemberFrame" .. i .. "PetFrame"])
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
	FlushPendingCompactRaidManagerUpdate()
end)

-- ---------------------------------------------------------------------------
-- Vehicle XP: stock StatusTrackingBar stays up because it is parented to
-- UIParent and only anchored to MainMenuBar. Vehicle hides MainMenuBar via
-- MainActionBar.OnHide → UpdateEndCaps(true), which does not hide the XP bar.
-- OverrideActionBar.UpdateXpBar also shows XP on the vehicle bar (retail hides
-- it when HasVehicleActionBar). Alpha 0 + Hide: FadeIn would restore alpha,
-- and an invisible bar still eats mouse. Non-vehicle override bars unchanged.
-- Ref: MainActionBarOverrides.lua UpdateEndCaps, OverrideActionBar.lua UpdateXpBar
-- ---------------------------------------------------------------------------

local function HasVehicleActionBar()
	return C_ActionBar and C_ActionBar.HasVehicleActionBar and C_ActionBar.HasVehicleActionBar()
end

local applyingVehicleXp
local vehicleXpInited

local function SetStockXpBarHidden(hidden)
	if hidden then
		if MainStatusTrackingBarContainer and MainStatusTrackingBarContainer.FadeInAnimation then
			MainStatusTrackingBarContainer.FadeInAnimation:Stop()
		end
		if SecondaryStatusTrackingBarContainer and SecondaryStatusTrackingBarContainer.FadeInAnimation then
			SecondaryStatusTrackingBarContainer.FadeInAnimation:Stop()
		end
	end

	if StatusTrackingBarManager then
		StatusTrackingBarManager:SetAlpha(hidden and 0 or 1)
		if hidden then
			StatusTrackingBarManager:Hide()
		else
			StatusTrackingBarManager:Show()
		end
	end

	-- Legacy globals: alpha only — Show/Hide is owned by Blizzard.
	if MainMenuExpBar then
		MainMenuExpBar:SetAlpha(hidden and 0 or 1)
	end
	if ReputationWatchBar then
		ReputationWatchBar:SetAlpha(hidden and 0 or 1)
	end
end

function WhoaUF:ApplyVehicleXpBarVisibility()
	if applyingVehicleXp then
		return
	end
	applyingVehicleXp = true

	local hide = ShouldHideDefaults() and HasVehicleActionBar()

	if hide and OverrideActionBar and OverrideActionBar.xpBar then
		OverrideActionBar.xpBar:Hide()
	end

	SetStockXpBarHidden(hide)
	if not hide and StatusTrackingBarManager and StatusTrackingBarManager.UpdateBarsShown then
		StatusTrackingBarManager:UpdateBarsShown()
	end

	applyingVehicleXp = false
end

local function OnOverrideActionBarUpdateXpBar(self)
	WhoaUF:ApplyVehicleXpBarVisibility()
end

local vehicleXpHooked

local function HookOverrideActionBarXp()
	if vehicleXpHooked then
		return
	end
	if not (OverrideActionBar and OverrideActionBar.UpdateXpBar) then
		return
	end
	hooksecurefunc(OverrideActionBar, "UpdateXpBar", OnOverrideActionBarUpdateXpBar)
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
	if not vehicleXpHooked and EventUtil and EventUtil.ContinueOnAddOnLoaded then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_OverrideActionBar", HookOverrideActionBarXp)
	end

	if StatusTrackingBarManager and StatusTrackingBarManager.UpdateBarsShown then
		hooksecurefunc(StatusTrackingBarManager, "UpdateBarsShown", function()
			if ShouldHideDefaults() and HasVehicleActionBar() then
				SetStockXpBarHidden(true)
			end
		end)
	end

	if MainActionBar and MainActionBar.UpdateEndCaps then
		hooksecurefunc(MainActionBar, "UpdateEndCaps", function()
			WhoaUF:ApplyVehicleXpBarVisibility()
		end)
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
