--[[
	Mainline + Forever/Camelot target+focus auras.

	CustomAuraContainer + AddAuraGroup is what Stormx uses, but Whoa's create
	path was not producing visible icons. Stock TargetFrame/FocusFrame ship a
	working TargetFrameAuraContainer — rehost that onto the Whoa frame
	(SetParent/SetPoint are still allowed; only CustomAuraContainer locks
	UntrustedLayoutScriptExecution after AddAuraGroup). Secure/native paint
	keeps icons visible when Lua aura queries are restricted (encounter / M+ /
	PvP / instanced secrecy).

	Stock TargetFrame is alpha-hidden by Whoa; IgnoreParentAlpha keeps icons
	visible if reparent fails. Driver: SetEnabled + Configure + UpdateAllAuras.

	Placement mirrors TargetFrameMixin:AnchorAuraContainer (Mainline/Forever).
	Stock uses FrameTexture+(5,9) / mirrored -6 on the HUD atlas (~192x67,
	centered on the 232x100 button). Whoa target/focus still use Classic chrome
	(UnitFrameClassic.xml 230x99 @ CENTER 18.5,-4), so those offsets are
	translated onto the unit button to match stock screen position.
]]

-- Mainline TargetFrame.lua AURA_START_* translated onto the 232x100 button:
--   x = (232-192)/2 + 5 = 25,  y = (100-67)/2 + 9 = 25.5
--   mirrored y = -(100-67)/2 + (-6) = -22.5
local AURA_START_X = 25
local AURA_START_Y = 26
local AURA_MIRRORED_START_Y = -23
local AURA_LINE_WIDTH = 122
-- TargetFrameAuraContainerDefaults.FlowLayoutLineSpacing (Mainline/Forever).
local AURA_LINE_SPACING = 3
-- TargetSpellBarMixin aura-container gap (AdjustPosition pointY when anchored).
local SPELLBAR_AURA_GAP_Y = 10
local NUM_TOT_CONSTRAINED_ROWS = 2
local SETTLE_DELAY = 0.05

local UNIT_KIND = {
	target = "target",
	focus = "focus",
}

local STOCK_FRAME = {
	target = function()
		return TargetFrame
	end,
	focus = function()
		return FocusFrame
	end,
}

-- kind → { container, savedParent, savedPoints, savedEnabled, owned }
local stateByKind = {}
local generationByKind = { target = 0, focus = 0 }
local waitingByKind = { target = false, focus = false }
local apiReady

-- Forward decl: AcquireStockContainer wires this before the definition below.
local WireAuraContainerSpellbarCallback
local SyncSpellbarAnchor
local AnchorAuraContainer

local function CanAccess(value)
	return WhoaUF:CanAccessValue(value)
end

local function SafeBool(fn, ...)
	if type(fn) ~= "function" then
		return false
	end
	local ok, value = pcall(fn, ...)
	return ok and WhoaUF:IsAccessibleTrue(value)
end

local function UnitExistsOk(unit)
	return unit and WhoaUF:IsAccessibleTrue(UnitExists(unit))
end

local function GetStockAuraContainer(stockFrame)
	if not stockFrame then
		return nil
	end
	local content = stockFrame.TargetFrameContent
	local contextual = content and content.TargetFrameContentContextual
	local container = contextual and contextual.Auras
	if not container then
		return nil
	end
	if type(container.SetUnit) ~= "function" or type(container.UpdateAllAuras) ~= "function" then
		return nil
	end
	return container
end

local function ProbeNativeAuraApi()
	if apiReady == false then
		return false
	end
	if apiReady == true then
		return true
	end
	-- apiReady nil: still probing (TargetFrame may not exist at file load).
	-- Capability gate: stock TargetFrameAuraContainer (Mainline + Forever).
	if not (WhoaUF.IsMainline and WhoaUF:IsMainline()) and not (WhoaUF.IsCamelot and WhoaUF:IsCamelot()) then
		apiReady = false
		return false
	end
	if GetStockAuraContainer(TargetFrame) then
		apiReady = true
		return true
	end
	-- Not ready yet — retry later; do not cache failure.
	return false
end

function WhoaUF:UsesNativeAuraContainer()
	return ProbeNativeAuraApi()
end

local function SnapshotPoints(frame)
	local points = {}
	if not frame or type(frame.GetNumPoints) ~= "function" then
		return points
	end
	-- GetNumPoints can be secret on Camelot; never use it as a raw for-limit.
	local okN, n = pcall(frame.GetNumPoints, frame)
	if not okN or not CanAccess(n) or type(n) ~= "number" or n < 1 then
		return points
	end
	for i = 1, n do
		local ok, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, i)
		if ok then
			points[i] = { point, relativeTo, relativePoint, x, y }
		end
	end
	return points
end

local function RestorePoints(frame, points)
	if not frame or not points then
		return
	end
	pcall(frame.ClearAllPoints, frame)
	for i = 1, #points do
		local p = points[i]
		if p then
			pcall(frame.SetPoint, frame, p[1], p[2], p[3], p[4], p[5])
		end
	end
end

local function EnsureState(kind)
	local state = stateByKind[kind]
	if state then
		return state
	end
	state = {}
	stateByKind[kind] = state
	return state
end

local function ClearAuraContainerSpellbarCallback(container)
	if container and type(container.SetAuraContainerAnchorsChangedCallback) == "function" then
		pcall(container.SetAuraContainerAnchorsChangedCallback, container, nil)
	end
end

local function ReleaseStockContainer(kind)
	local state = stateByKind[kind]
	if not state or not state.container then
		return
	end
	local container = state.container
	ClearAuraContainerSpellbarCallback(container)
	if state.owned then
		if state.savedParent then
			pcall(container.SetParent, container, state.savedParent)
		end
		RestorePoints(container, state.savedPoints)
		if state.savedEnabled ~= nil and type(container.SetEnabled) == "function" then
			pcall(container.SetEnabled, container, state.savedEnabled)
		end
	end
	state.owned = false
	state.container = nil
	state.savedParent = nil
	state.savedPoints = nil
	state.savedEnabled = nil
end

local function AcquireStockContainer(kind, whoaFrame)
	if InCombatLockdown and InCombatLockdown() then
		local state = stateByKind[kind]
		return state and state.owned and state.container or nil
	end

	local stockFrame = STOCK_FRAME[kind] and STOCK_FRAME[kind]()
	local container = GetStockAuraContainer(stockFrame)
	if not container or not whoaFrame then
		return nil
	end

	local state = EnsureState(kind)
	if state.container == container and state.owned then
		return container
	end

	-- First claim: snapshot Blizzard placement/enabled so we can restore.
	if not state.savedParent then
		state.savedParent = container:GetParent()
		state.savedPoints = SnapshotPoints(container)
		if type(container.IsEnabled) == "function" then
			local ok, enabled = pcall(container.IsEnabled, container)
			if ok and type(enabled) == "boolean" then
				state.savedEnabled = enabled
			end
		end
	end

	state.container = container
	state.owned = true

	if container.SetIgnoreParentAlpha then
		pcall(container.SetIgnoreParentAlpha, container, true)
	end
	if type(container.SetEnabled) == "function" then
		pcall(container.SetEnabled, container, true)
	end

	-- Prefer Whoa as parent so TargetFrame alpha-0 cannot hide icons.
	local parented = pcall(container.SetParent, container, whoaFrame)
	if not parented then
		-- Keep stock parent; IgnoreParentAlpha + SetPoint to Whoa still works.
		pcall(container.SetParent, container, state.savedParent)
	end

	AnchorAuraContainer(container, whoaFrame)

	local level = 70
	if whoaFrame.GetFrameLevel then
		local ok, fl = pcall(whoaFrame.GetFrameLevel, whoaFrame)
		if ok and CanAccess(fl) and type(fl) == "number" then
			level = math.max(1, math.floor(fl) + 20)
		end
	end
	pcall(container.SetFrameStrata, container, "LOW")
	pcall(container.SetFrameLevel, container, level)

	WireAuraContainerSpellbarCallback(kind, container)

	return container
end

-- Mirror TargetFrameMixin:AnchorAuraContainer, button-relative (see AURA_START_*).
AnchorAuraContainer = function(container, whoaFrame)
	if not container or not whoaFrame then
		return
	end

	local onTop = whoaFrame.buffsOnTop
	if onTop == nil and GetCVarBool then
		onTop = GetCVarBool("buffsOnTop")
	end

	local point, relativePoint, offsetY
	if onTop then
		point = "BOTTOMLEFT"
		relativePoint = "TOPLEFT"
		offsetY = AURA_MIRRORED_START_Y
		local numeric = whoaFrame.threatNumericIndicator
		if numeric and numeric.IsShown and numeric:IsShown() and numeric.GetHeight then
			local ok, h = pcall(numeric.GetHeight, numeric)
			if ok and CanAccess(h) and type(h) == "number" then
				offsetY = offsetY + h
			end
		end
	else
		point = "TOPLEFT"
		relativePoint = "BOTTOMLEFT"
		offsetY = AURA_START_Y
	end

	pcall(container.ClearAllPoints, container)
	pcall(container.SetPoint, container, point, whoaFrame, relativePoint, AURA_START_X, offsetY)
end

local function ConfigureContainer(container, kind, whoaFrame)
	local unit = UNIT_KIND[kind]
	if type(container.SetUnit) == "function" then
		-- Same token is a no-op; only set when different or unset.
		local current
		if type(container.GetUnit) == "function" then
			local ok, token = pcall(container.GetUnit, container)
			if ok then
				current = token
			end
		end
		if current ~= unit then
			pcall(container.SetUnit, container, unit)
		end
	end

	if type(container.SetPlayerIsTarget) == "function" then
		pcall(container.SetPlayerIsTarget, container, SafeBool(UnitIsUnit, "player", unit))
	end
	if type(container.SetTargetIsFriendly) == "function" then
		local friendly = SafeBool(UnitIsFriend, "player", unit)
			or SafeBool(UnitCanAssist, "player", unit)
		pcall(container.SetTargetIsFriendly, container, friendly and not SafeBool(UnitCanAttack, "player", unit))
	end
	if type(container.SetShowAuraCount) == "function" then
		pcall(container.SetShowAuraCount, container, whoaFrame.showAuraCount ~= false)
	end
	if type(container.SetFlowLayoutMirroredVertically) == "function" then
		local onTop = whoaFrame.buffsOnTop
		if onTop == nil and GetCVarBool then
			onTop = GetCVarBool("buffsOnTop")
		end
		pcall(container.SetFlowLayoutMirroredVertically, container, onTop and true or false)
	end

	-- Re-anchor every configure (buffsOnTop / threat numeric can change after acquire).
	AnchorAuraContainer(container, whoaFrame)

	-- Wire Appearance auraIconSize → stock TargetFrameAuraContainer sizes.
	if WhoaUF.GetAuraIconSizes then
		local large, small = WhoaUF:GetAuraIconSizes()
		if type(large) == "number" and type(container.SetLargeAuraSize) == "function" then
			pcall(container.SetLargeAuraSize, container, large)
		end
		if type(small) == "number" and type(container.SetSmallAuraSize) == "function" then
			pcall(container.SetSmallAuraSize, container, small)
		end
	end

	local maxBuffs = whoaFrame.maxBuffs or 32
	local maxDebuffs = whoaFrame.maxDebuffs or 16
	if type(container.SetMaxBuffs) == "function" then
		pcall(container.SetMaxBuffs, container, maxBuffs)
	end
	if type(container.SetMaxDebuffs) == "function" then
		pcall(container.SetMaxDebuffs, container, maxDebuffs)
	end
	if type(container.SetFlowLayoutMaximumLineSize) == "function" then
		pcall(container.SetFlowLayoutMaximumLineSize, container, AURA_LINE_WIDTH)
	end

	local totShown = whoaFrame.totFrame and whoaFrame.totFrame:IsShown()
	local totWidth = whoaFrame.TOT_AURA_ROW_WIDTH or 101
	if type(container.SetConstrainedFlowLayoutLineSize) == "function" then
		pcall(container.SetConstrainedFlowLayoutLineSize, container, totShown and totWidth or AURA_LINE_WIDTH)
	end
	if type(container.SetNumConstrainedFlowLayoutLines) == "function" then
		pcall(container.SetNumConstrainedFlowLayoutLines, container, totShown and NUM_TOT_CONSTRAINED_ROWS or 0)
	end
end

local function HideLegacyAuraButtons(frame)
	if not frame then
		return
	end
	local buffs = frame.whoaBuffs
	if buffs then
		for i = 1, #buffs do
			local b = buffs[i]
			if b and b:IsShown() then
				b:Hide()
			end
		end
	end
	local debuffs = frame.whoaDebuffs
	if debuffs then
		for i = 1, #debuffs do
			local b = debuffs[i]
			if b and b:IsShown() then
				b:Hide()
			end
		end
	end
end

-- Plain Whoa proxy for castbar SetPoint. Stock AuraContainer carries
-- UntrustedLayoutScriptExecution; addon frames cannot AddForbiddenAspects
-- the way TargetSpellBarMixin does before anchoring to it (Forever/Mainline).
local function EnsureSpellbarProxy(frame)
	local proxy = frame.whoaNativeAuraSpellbarAnchor
	if proxy then
		return proxy
	end
	proxy = CreateFrame("Frame", nil, frame)
	proxy:SetSize(AURA_LINE_WIDTH, 1)
	frame.whoaNativeAuraSpellbarAnchor = proxy
	return proxy
end

-- Row count for CastBar_Mainline ShouldAnchorSpellBarToAuraContainer (auraRows).
local function VisibleAuraRows(container)
	if not container or type(container.GetNumVisibleFlowLayoutLines) ~= "function" then
		return 0
	end
	local ok, n = pcall(container.GetNumVisibleFlowLayoutLines, container)
	if not ok or n == nil then
		return 0
	end
	if WhoaUF:CanAccessValue(n) then
		return type(n) == "number" and n or 0
	end
	-- Secret line count (encounter secrecy): assume multi-row so castbar clears auras.
	return 3
end

local function AccessibleHeight(container)
	if not container or type(container.GetHeight) ~= "function" then
		return nil
	end
	local ok, h = pcall(container.GetHeight, container)
	if ok and WhoaUF:CanAccessValue(h) and type(h) == "number" and h > 0 then
		return h
	end
	return nil
end

local function EstimatedAuraHeight(rows)
	-- Prefer Whoa auraIconSize (Appearance rescaler); stock LargeAuraSize is 21.
	local large = 21
	if WhoaUF.GetAuraIconSizes then
		local l = WhoaUF:GetAuraIconSizes()
		if type(l) == "number" and l > 0 then
			large = l
		end
	end
	rows = math.max(0, rows or 0)
	if rows <= 0 then
		return 1
	end
	-- rows * icon + (rows-1) * FlowLayoutLineSpacing — matches stock layout pitch.
	return rows * large + math.max(0, rows - 1) * AURA_LINE_SPACING
end

-- Size proxy from container layout metrics; never SetPoint to the container.
-- whoaSpellbarAuraClearY = parent BOTTOMLEFT Y for castbar TOPLEFT to sit
-- SPELLBAR_AURA_GAP_Y below the (possibly rescaled) aura block — used when
-- CastBar keeps the frame/ToT anchor (rows ≤ 2 with ToT) but icons are taller
-- than stock 21px.
SyncSpellbarAnchor = function(frame, container)
	if not frame then
		return
	end

	local proxy = frame.whoaNativeAuraSpellbarAnchor
	if not container then
		if proxy then
			proxy:Hide()
			proxy:ClearAllPoints()
		end
		frame.spellbarAnchor = nil
		frame.auraRows = 0
		frame.whoaSpellbarAuraClearY = nil
	else
		local rows = VisibleAuraRows(container)
		frame.auraRows = rows
		local onTop = frame.buffsOnTop
		if onTop == nil and GetCVarBool then
			onTop = GetCVarBool("buffsOnTop")
		end
		-- Proxy sized whenever bottom auras exist; CastBar_Mainline AdjustPosition
		-- gates use (ToT needs rows > 2; else rows > 0) — same as stock.
		if rows <= 0 or onTop then
			if proxy then
				proxy:Hide()
				proxy:ClearAllPoints()
			end
			frame.spellbarAnchor = nil
			frame.whoaSpellbarAuraClearY = nil
		else
			proxy = EnsureSpellbarProxy(frame)
			-- Readable layout height when possible; else estimate from auraIconSize
			-- + FlowLayoutLineSpacing (Appearance rescaler / secret GetHeight).
			local height = AccessibleHeight(container) or EstimatedAuraHeight(rows)
			proxy:ClearAllPoints()
			proxy:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", AURA_START_X, AURA_START_Y)
			proxy:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", AURA_START_X + AURA_LINE_WIDTH, AURA_START_Y - height)
			proxy:Show()
			frame.spellbarAnchor = proxy
			frame.whoaSpellbarAuraClearY = AURA_START_Y - height - SPELLBAR_AURA_GAP_Y
		end
	end

	if WhoaUF.AdjustSpellBar then
		pcall(WhoaUF.AdjustSpellBar, WhoaUF, frame)
	end
end

-- Stock signals after ApplyLayout (SetSize + line count). Re-sync castbar then.
WireAuraContainerSpellbarCallback = function(kind, container)
	if not container or type(container.SetAuraContainerAnchorsChangedCallback) ~= "function" then
		return
	end
	pcall(container.SetAuraContainerAnchorsChangedCallback, container, function()
		local frames = WhoaUF._UF and WhoaUF._UF.frames
		local frame = frames and frames[kind]
		local state = stateByKind[kind]
		if frame and state and state.container == container and state.owned then
			SyncSpellbarAnchor(frame, container)
		end
	end)
end

local function HideKind(kind)
	waitingByKind[kind] = false
	local state = stateByKind[kind]
	if state and state.container then
		state.container:SetAlpha(0)
		state.container:Hide()
	end
end

local function ShowKind(kind, container)
	container:SetAlpha(1)
	container:Show()
	pcall(container.UpdateAllAuras, container)
end

local function UpdateKind(kind, readyGeneration)
	if readyGeneration ~= nil then
		if readyGeneration ~= generationByKind[kind] then
			return false
		end
		waitingByKind[kind] = false
	end

	local frames = WhoaUF._UF and WhoaUF._UF.frames
	local frame = frames and frames[kind]
	local unit = UNIT_KIND[kind]
	local whoaOn = WhoaUF.db and WhoaUF.db.enabled and WhoaUF.runtimeActive ~= false

	if not whoaOn or not frame or not ProbeNativeAuraApi() then
		HideKind(kind)
		ReleaseStockContainer(kind)
		SyncSpellbarAnchor(frame, nil)
		return false
	end

	if waitingByKind[kind] then
		HideLegacyAuraButtons(frame)
		return true
	end

	if not UnitExistsOk(unit) then
		HideKind(kind)
		HideLegacyAuraButtons(frame)
		SyncSpellbarAnchor(frame, nil)
		if WhoaUF.RequestIdleCollect then
			WhoaUF:RequestIdleCollect()
		end
		return true
	end

	local container = AcquireStockContainer(kind, frame)
	if not container then
		-- Could not claim stock container (e.g. combat before first acquire).
		return false
	end

	HideLegacyAuraButtons(frame)
	ConfigureContainer(container, kind, frame)
	ShowKind(kind, container)
	-- Immediate attempt; layout callback re-syncs once flow size/lines settle.
	SyncSpellbarAnchor(frame, container)
	return true
end

function WhoaUF:RebuildNativeUnitAuras(kind, waitForUnit)
	if kind ~= "target" and kind ~= "focus" then
		return nil
	end
	if not ProbeNativeAuraApi() then
		return nil
	end
	generationByKind[kind] = (generationByKind[kind] or 0) + 1
	waitingByKind[kind] = waitForUnit == true
	HideKind(kind)
	return generationByKind[kind]
end

function WhoaUF:UpdateNativeUnitAuras(frame, readyGeneration)
	if not frame or (frame.kind ~= "target" and frame.kind ~= "focus") then
		return false
	end
	if not ProbeNativeAuraApi() then
		return false
	end
	if self.editModePreviewActive and self.IsEditModeActive and self:IsEditModeActive() then
		return false
	end
	-- true = native owns paint (even while waiting / empty unit).
	-- false = fall through to Lua index paint.
	return UpdateKind(frame.kind, readyGeneration)
end

function WhoaUF:OnNativeUnitChanged(kind)
	if kind ~= "target" and kind ~= "focus" then
		return
	end
	if not ProbeNativeAuraApi() then
		return
	end
	local ticket = self:RebuildNativeUnitAuras(kind, true)
	if not ticket then
		return
	end
	local function settle()
		local frames = WhoaUF._UF and WhoaUF._UF.frames
		local frame = frames and frames[kind]
		if frame then
			WhoaUF:UpdateNativeUnitAuras(frame, ticket)
		end
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(SETTLE_DELAY, settle)
	else
		settle()
	end
end

function WhoaUF:SetNativeAuraContainersActive(active)
	if not ProbeNativeAuraApi() then
		return
	end
	if not active then
		HideKind("target")
		HideKind("focus")
		ReleaseStockContainer("target")
		ReleaseStockContainer("focus")
		local frames = self._UF and self._UF.frames
		if frames then
			SyncSpellbarAnchor(frames.target, nil)
			SyncSpellbarAnchor(frames.focus, nil)
		end
		return
	end
	local frames = self._UF and self._UF.frames
	if frames and frames.target then
		UpdateKind("target")
	end
	if frames and frames.focus then
		UpdateKind("focus")
	end
end
