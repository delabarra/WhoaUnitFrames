--[[
	Target/focus auras (buffs + debuffs) + ToT/focus-ToT debuffs.
	Classic: mirrors TargetFrameMixin:UpdateAuras + TargetOfTarget AuraUtil.RefreshAuras.
	Mainline: same index paint via ForEachUnitAuraByIndex with secret-safe
	SetTexture / SetCooldownFromExpirationTime / GetAuraApplicationDisplayCount.
	Queries still gated by AreUnitAuraQueriesRestricted (never GetAuraSlots).
	Reference: reference/Blizzard_UnitFrame/Classic/TargetFrame.lua
]]

local MAX_BUFFS = 32
local MAX_DEBUFFS = 16
local MAX_TOT_DEBUFFS = 4
-- Match Classic TargetFrame.lua aura placement constants.
local AURA_START_X = 21
local AURA_START_Y = 28
local AURA_START_Y_MIRROR = -19
local AURA_OFFSET_Y = 1
local LARGE_AURA_SIZE = 21
local SMALL_AURA_SIZE = 17
local AURA_ROW_WIDTH = 122
local TOT_AURA_ROW_WIDTH = 101
-- Stock Classic: two ToT-narrow rows, then full AURA_ROW_WIDTH.
-- Ref: TargetFrame.lua NUM_TOT_AURA_ROWS / FocusFrame.TOT_AURA_ROW_WIDTH (80 when small).
local NUM_TOT_AURA_ROWS = 2
local SMALL_FOCUS_TOT_AURA_ROW_WIDTH = 80
local AURA_ROW_GAP = 3

-- Cached SetPoint args — avoid `point .. "LEFT"` strings every UNIT_AURA.
local TOPLEFT = "TOPLEFT"
local BOTTOMLEFT = "BOTTOMLEFT"
local TOPRIGHT = "TOPRIGHT"
local BOTTOMRIGHT = "BOTTOMRIGHT"
local EMPTY_DEBUFF_TYPE = ""

local UnitIsOwnerOrControllerOfUnit = UnitIsOwnerOrControllerOfUnit

-- wipe() each UNIT_AURA — reuse tables, no fresh {} per event.
local largeBuffList = {}
local largeDebuffList = {}

local function GetAuraSizes()
	if WhoaUF.GetAuraIconSizes then
		return WhoaUF:GetAuraIconSizes()
	end
	return LARGE_AURA_SIZE, SMALL_AURA_SIZE, 12
end

local function UnitExistsOk(unit)
	return unit and WhoaUF:IsAccessibleTrue(UnitExists(unit))
end

local function ShouldAuraBeLarge(caster)
	if GetCVarBool and not GetCVarBool("showDynamicBuffSize") then
		return true
	end
	if not caster then
		return false
	end
	if WhoaUF:UnitMatchesToken(caster, "player")
		or WhoaUF:UnitMatchesToken(caster, "vehicle")
		or WhoaUF:UnitMatchesToken(caster, "pet")
	then
		return true
	end
	if UnitIsOwnerOrControllerOfUnit then
		if WhoaUF:IsAccessibleTrue(UnitIsOwnerOrControllerOfUnit("player", caster))
			or WhoaUF:IsAccessibleTrue(UnitIsOwnerOrControllerOfUnit("vehicle", caster))
			or WhoaUF:IsAccessibleTrue(UnitIsOwnerOrControllerOfUnit("pet", caster))
		then
			return true
		end
	end
	return false
end

local function ShouldShowDebuff(unit, caster, nameplateShowAll, casterIsPlayer)
	if GetCVarBool and GetCVarBool("noBuffDebuffFilterOnTarget") then
		return true
	end
	if WhoaUF:IsAccessibleTrue(nameplateShowAll) then
		return true
	end
	if caster
		and (WhoaUF:UnitMatchesToken("player", caster)
			or (UnitIsOwnerOrControllerOfUnit and WhoaUF:IsAccessibleTrue(UnitIsOwnerOrControllerOfUnit("player", caster))))
	then
		return true
	end
	if WhoaUF:UnitMatchesToken("player", unit) then
		return true
	end
	-- Secret unit flags: cannot filter — show rather than Lua-test secrets.
	if WhoaUF:NeedsSecretSafeNumberOps(casterIsPlayer)
		or not WhoaUF:CanAccessValue(UnitCanAttack("player", unit))
		or not WhoaUF:CanAccessValue(UnitIsPlayer(unit))
	then
		return true
	end
	local targetIsFriendly = not UnitCanAttack("player", unit)
	local targetIsAPlayer = UnitIsPlayer(unit)
	local targetIsAPlayerPet = UnitIsOtherPlayersPet and WhoaUF:IsAccessibleTrue(UnitIsOtherPlayersPet(unit))
	if not targetIsAPlayer and not targetIsAPlayerPet and not targetIsFriendly and casterIsPlayer then
		return false
	end
	return true
end

local function SetDebuffBorderColor(border, debuffType)
	if AuraUtil and AuraUtil.SetAuraBorderColor then
		AuraUtil.SetAuraBorderColor(border, debuffType)
		return
	end
	local color = WhoaUF:GetDebuffTypeColor(debuffType)
	border:SetVertexColor(color.r, color.g, color.b)
end

-- SetTexture accepts secret fileIDs. Skip only when icon is nil.
local function PaintAuraIcon(button, icon)
	if icon == nil then
		return false
	end
	local iconTex = button.Icon
	if not iconTex then
		return false
	end
	-- Cache compare is unsafe on secrets — always paint when inaccessible.
	if WhoaUF:NeedsSecretSafeNumberOps(icon) then
		button.whoaIcon = nil
		iconTex:SetTexture(icon)
		return true
	end
	if button.whoaIcon ~= icon then
		button.whoaIcon = icon
		iconTex:SetTexture(icon)
	end
	return true
end

-- Prefer GetAuraApplicationDisplayCount (Blizzard-formatted, secret-safe).
local function PaintAuraCount(button, count, showAuraCount, unit, auraInstanceID)
	local countFS = button.Count
	if not countFS then
		return
	end
	if not showAuraCount then
		button.whoaCount = nil
		countFS:Hide()
		return
	end

	if unit and auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
		local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, 2)
		if ok then
			button.whoaCount = nil
			if text and text ~= "" then
				countFS:SetText(text)
				countFS:Show()
			else
				countFS:Hide()
			end
			return
		end
	end

	if WhoaUF:NeedsSecretSafeNumberOps(count) then
		-- Without GetAuraApplicationDisplayCount we cannot prove count > 1.
		button.whoaCount = nil
		countFS:Hide()
		return
	end
	if count and count > 1 then
		if button.whoaCount ~= count then
			button.whoaCount = count
			countFS:SetText(count)
		end
		countFS:Show()
	else
		button.whoaCount = nil
		countFS:Hide()
	end
end

-- SetCooldownFromExpirationTime accepts secrets (no Lua duration math).
local function PaintAuraCooldown(button, duration, expirationTime)
	local cooldown = button.Cooldown
	if not cooldown then
		return
	end
	if WhoaUF:NeedsSecretSafeNumberOps(duration, expirationTime) then
		button.whoaCdStart = nil
		button.whoaCdDuration = nil
		button.whoaCdEnable = nil
		if duration ~= nil and expirationTime ~= nil and cooldown.SetCooldownFromExpirationTime then
			cooldown:SetCooldownFromExpirationTime(expirationTime, duration)
		elseif CooldownFrame_Set then
			CooldownFrame_Set(cooldown, 0, 0, false, true)
		end
		return
	end
	if not CooldownFrame_Set then
		return
	end
	duration = duration or 0
	expirationTime = expirationTime or 0
	local start = expirationTime - duration
	local enable = duration > 0
	if button.whoaCdStart == start and button.whoaCdDuration == duration and button.whoaCdEnable == enable then
		return
	end
	button.whoaCdStart = start
	button.whoaCdDuration = duration
	button.whoaCdEnable = enable
	CooldownFrame_Set(cooldown, start, duration, enable, true)
end

local function PaintDebuffType(button, debuffType)
	local border = button.Border
	if not border then
		return
	end
	-- DebuffTypeColor table keys must be accessible; secret type → leave border.
	if debuffType ~= nil and not WhoaUF:CanAccessValue(debuffType) then
		return
	end
	local key = debuffType or EMPTY_DEBUFF_TYPE
	if button.whoaDebuffType == key then
		return
	end
	button.whoaDebuffType = key
	SetDebuffBorderColor(border, debuffType)
end

local function ClearAuraPaintCache(button)
	button.whoaIcon = nil
	button.whoaCount = nil
	button.whoaCdStart = nil
	button.whoaCdDuration = nil
	button.whoaCdEnable = nil
	button.whoaDebuffType = nil
end

local function SetAuraSize(button, size)
	if button.whoaSize == size then
		return
	end
	button.whoaSize = size
	button:SetSize(size, size)
	local border = button.Border
	if border then
		local borderSize = size + 2
		if button.whoaBorderSize ~= borderSize then
			button.whoaBorderSize = borderSize
			border:SetSize(borderSize, borderSize)
		end
	end
end

local function EnsureAuraButton(parent, kind, index)
	local listKey = kind == "buff" and "whoaBuffs" or "whoaDebuffs"
	local buttons = parent[listKey]
	local button = buttons[index]
	if button then
		return button
	end

	-- WhoaUF* templates (Frames/Auras.xml): Mainline has no Target*FrameTemplate.
	local template = kind == "buff" and "WhoaUFBuffFrameTemplate" or "WhoaUFDebuffFrameTemplate"
	local name = parent:GetName() .. (kind == "buff" and "Buff" or "Debuff") .. index
	button = CreateFrame("Button", name, parent, template)
	button.unit = parent.unit
	-- Cache template children once — avoid GetName().. lookups every UNIT_AURA.
	button.Icon = _G[name .. "Icon"]
	button.Count = _G[name .. "Count"]
	button.Cooldown = _G[name .. "Cooldown"]
	button.Stealable = _G[name .. "Stealable"]
	button.Border = _G[name .. "Border"]
	buttons[index] = button
	return button
end

local function HideTrailingAuras(parent, kind, fromIndex, maxCount)
	local listKey = kind == "buff" and "whoaBuffs" or "whoaDebuffs"
	local buttons = parent[listKey]
	for i = fromIndex, maxCount do
		local button = buttons[i]
		if not button then
			break
		end
		if button:IsShown() then
			ClearAuraPaintCache(button)
			button:Hide()
		end
	end
end

local function ResolveBuffsOnTop(frame)
	if frame.kind == "target" or frame.kind == "focus" then
		if frame.buffsOnTop ~= nil then
			return frame.buffsOnTop
		end
		if WhoaUF.GetEditModeBuffsOnTop then
			return WhoaUF:GetEditModeBuffsOnTop(frame.kind)
		end
	end
	if GetCVarBool then
		return GetCVarBool("buffsOnTop")
	end
	return false
end

local function UseEditModeSampleAuras(frame)
	return WhoaUF.editModePreviewActive
		and WhoaUF.IsEditModeActive
		and WhoaUF:IsEditModeActive()
		and AuraUtil
		and AuraUtil.ForEachAura
		and AuraUtil.CreateFilterString
		and AuraUtil.AuraFilters
		and (frame.kind == "target" or frame.kind == "focus")
end

local function GetMirrorAuraLayout(frame, mirrorVertically, offsetY)
	local point, relativePoint, startY, auraOffsetY
	if mirrorVertically then
		point = BOTTOMLEFT
		relativePoint = TOPLEFT
		startY = AURA_START_Y_MIRROR
		local threat = frame.threatNumericIndicator
		if threat and threat.IsShown and threat:IsShown() then
			startY = startY + threat:GetHeight()
		end
		offsetY = -offsetY
		auraOffsetY = -AURA_OFFSET_Y
	else
		point = TOPLEFT
		relativePoint = BOTTOMLEFT
		startY = AURA_START_Y
		auraOffsetY = AURA_OFFSET_Y
	end
	return point, relativePoint, startY, auraOffsetY, offsetY
end

local function UpdateBuffAnchor(frame, index, numDebuffs, anchorIndex, size, offsetX, offsetY, mirrorVertically)
	local buff = frame.whoaBuffs[index]
	local point, relativePoint, startY, auraOffsetY, rowOffsetY = GetMirrorAuraLayout(frame, mirrorVertically, offsetY)

	if index == 1 then
		if UnitIsFriend("player", frame.unit) or numDebuffs == 0 then
			buff:SetPoint(point, frame, relativePoint, AURA_START_X, startY)
		else
			buff:SetPoint(point, frame.debuffs, relativePoint, 0, -rowOffsetY)
		end
		frame.buffs:SetPoint(point, buff, point, 0, 0)
		frame.buffs:SetPoint(relativePoint, buff, relativePoint, 0, -auraOffsetY)
		frame.spellbarAnchor = buff
	elseif anchorIndex ~= (index - 1) then
		buff:SetPoint(point, frame.whoaBuffs[anchorIndex], relativePoint, 0, -rowOffsetY)
		frame.buffs:SetPoint(relativePoint, buff, relativePoint, 0, -auraOffsetY)
		frame.spellbarAnchor = buff
	else
		local prev = frame.whoaBuffs[anchorIndex]
		local attachPoint = mirrorVertically and BOTTOMLEFT or TOPLEFT
		local prevAttach = mirrorVertically and BOTTOMRIGHT or TOPRIGHT
		buff:SetPoint(attachPoint, prev, prevAttach, offsetX, 0)
	end

	SetAuraSize(buff, size)
end

local function UpdateDebuffAnchor(frame, index, numBuffs, anchorIndex, size, offsetX, offsetY, isFriend, mirrorVertically)
	local debuff = frame.whoaDebuffs[index]
	local point, relativePoint, startY, auraOffsetY, rowOffsetY = GetMirrorAuraLayout(frame, mirrorVertically, offsetY)

	if index == 1 then
		if isFriend and numBuffs > 0 then
			debuff:SetPoint(point, frame.buffs, relativePoint, 0, -rowOffsetY)
		else
			debuff:SetPoint(point, frame, relativePoint, AURA_START_X, startY)
		end
		frame.debuffs:SetPoint(point, debuff, point, 0, 0)
		frame.debuffs:SetPoint(relativePoint, debuff, relativePoint, 0, -auraOffsetY)
		if isFriend or numBuffs == 0 then
			frame.spellbarAnchor = debuff
		end
	elseif anchorIndex ~= (index - 1) then
		debuff:SetPoint(point, frame.whoaDebuffs[anchorIndex], relativePoint, 0, -rowOffsetY)
		frame.debuffs:SetPoint(relativePoint, debuff, relativePoint, 0, -auraOffsetY)
		if isFriend or numBuffs == 0 then
			frame.spellbarAnchor = debuff
		end
	else
		local prev = frame.whoaDebuffs[index - 1]
		local attachPoint = mirrorVertically and BOTTOMLEFT or TOPLEFT
		local prevAttach = mirrorVertically and BOTTOMRIGHT or TOPRIGHT
		debuff:SetPoint(attachPoint, prev, prevAttach, offsetX, 0)
	end

	SetAuraSize(debuff, size)
end

local function LayoutAuras(frame, auraKind, numAuras, numOpposite, largeList, maxRowWidth, offsetX, largeSize, smallSize, isFriend, mirrorVertically)
	local updateFunc = auraKind == "buff" and UpdateBuffAnchor or UpdateDebuffAnchor
	local offsetY = AURA_OFFSET_Y
	local rowWidth = 0
	local firstOnRow = 1

	for i = 1, numAuras do
		local size
		if largeList[i] then
			size = largeSize
			offsetY = AURA_OFFSET_Y + AURA_OFFSET_Y
		else
			size = smallSize
		end

		if i == 1 then
			rowWidth = size
			frame.auraRows = frame.auraRows + 1
		else
			rowWidth = rowWidth + size + offsetX
		end

		if rowWidth > maxRowWidth then
			if auraKind == "buff" then
				updateFunc(frame, i, numOpposite, firstOnRow, size, offsetX, offsetY, mirrorVertically)
			else
				updateFunc(frame, i, numOpposite, firstOnRow, size, offsetX, offsetY, isFriend, mirrorVertically)
			end
			rowWidth = size
			frame.auraRows = frame.auraRows + 1
			firstOnRow = i
			offsetY = AURA_OFFSET_Y
			if frame.auraRows > NUM_TOT_AURA_ROWS then
				maxRowWidth = AURA_ROW_WIDTH
			end
		else
			if auraKind == "buff" then
				updateFunc(frame, i, numOpposite, i - 1, size, offsetX, offsetY, mirrorVertically)
			else
				updateFunc(frame, i, numOpposite, i - 1, size, offsetX, offsetY, isFriend, mirrorVertically)
			end
		end
	end
end

local function HasVisibleToT(frame)
	if WhoaUF.SyncHaveToT then
		return WhoaUF:SyncHaveToT(frame) and true or false
	end
	local tot = frame.totFrame
	return tot and tot:IsShown()
end

function WhoaUF:InitFrameAuras(frame)
	if not frame or frame.whoaBuffs then
		return
	end

	frame.whoaBuffs = {}
	frame.whoaDebuffs = {}
	frame.showAuraCount = true
	frame.auraRows = 0

	frame.TOT_AURA_ROW_WIDTH = TOT_AURA_ROW_WIDTH

	frame.buffs = CreateFrame("Frame", nil, frame)
	frame.buffs:SetSize(10, 10)

	frame.debuffs = CreateFrame("Frame", nil, frame)
	frame.debuffs:SetSize(10, 10)
end

function WhoaUF:SetTotAuraRowWidth(frame, smallFocus)
	if not frame then
		return
	end
	if smallFocus then
		frame.TOT_AURA_ROW_WIDTH = SMALL_FOCUS_TOT_AURA_ROW_WIDTH
	else
		frame.TOT_AURA_ROW_WIDTH = TOT_AURA_ROW_WIDTH
	end
end

function WhoaUF:AttachToTAuraHooks(totFrame, parent)
	if not totFrame or totFrame.whoaAuraHooks then
		return
	end
	totFrame.whoaAuraHooks = true
	parent.totFrame = totFrame
	-- Watch show/hide on a plain Frame — HookScript on SecureUnitButton taints.
	-- OnUpdate is only armed while the parent target/focus frame is shown.
	local watcher = CreateFrame("Frame", nil, UIParent)
	local wasShown = totFrame:IsShown()
	local lastTotGuid = nil
	local lastParentAlive = nil
	local auraElapsed = 0
	local pendingAuraRefresh = false
	local function Watcher_OnUpdate(_, elapsed)
		if not parent:IsShown() then
			watcher:SetScript("OnUpdate", nil)
			watcher.whoaActive = false
			wasShown = totFrame:IsShown()
			lastTotGuid = nil
			lastParentAlive = nil
			pendingAuraRefresh = false
			auraElapsed = 0
			return
		end
		local unit = totFrame.unit
		local exists = unit and UnitExists(unit)
		local shown = totFrame:IsShown()
		local shownChanged = shown ~= wasShown
		-- Mainline: never compare UnitGUID (secret in instances). Classic only.
		local guidChanged = false
		if not (WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues()) then
			local guid = exists and UnitGUID(unit) or nil
			if guid ~= lastTotGuid then
				guidChanged = true
				lastTotGuid = guid
			end
		elseif lastTotGuid ~= nil then
			lastTotGuid = nil
		end
		-- Blizzard hides ToT when parent is dead; RegisterUnitWatch does not.
		local parentAlive = UnitExists(parent.unit)
		if parentAlive then
			if UnitIsDeadOrGhost and WhoaUF:IsAccessibleTrue(UnitIsDeadOrGhost(parent.unit)) then
				parentAlive = false
			else
				local parentHealth = UnitHealth(parent.unit)
				if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(parentHealth) and parentHealth <= 0 then
					parentAlive = false
				end
			end
		end
		local parentAliveChanged = parentAlive ~= lastParentAlive
		if shownChanged then
			wasShown = shown
			-- Match TargetOfTargetMixin:Update — move castbar immediately.
			local hadToT = parent.haveToT
			if WhoaUF.SyncHaveToT then
				WhoaUF:SyncHaveToT(parent)
			elseif shown then
				parent.haveToT = true
			else
				parent.haveToT = nil
			end
			if parent.haveToT ~= hadToT and WhoaUF.AdjustSpellBar then
				WhoaUF:AdjustSpellBar(parent)
			end
			-- Debuff host is on UIParent (does not inherit ToT alpha). Gate on the
			-- same ShouldShowToTFrame rules as the pin — RegisterUnitWatch can leave
			-- ToT shown while alpha-hidden (self-target / parent dead / CVar off).
			local host = totFrame.whoaToTDebuffHost
			if host then
				local showDebuffs = shown
					and WhoaUF.ShouldShowToTFrame
					and WhoaUF:ShouldShowToTFrame(totFrame)
				if showDebuffs then
					host:Show()
				else
					host:Hide()
				end
			end
			pendingAuraRefresh = true
			auraElapsed = 0
		end
		if parentAliveChanged then
			lastParentAlive = parentAlive
		end
		-- Blizzard parent OnUpdate refreshes ToT when show/existence drifts; also
		-- catch GUID swaps that leave the pin shown (UNIT_TARGET can miss a frame),
		-- and parent death (ToT must hide while the token may still exist).
		if shownChanged or guidChanged or parentAliveChanged then
			WhoaUF:UpdateUnitFrame(totFrame)
			if parentAliveChanged then
				local hadToT = parent.haveToT
				if WhoaUF.SyncHaveToT then
					WhoaUF:SyncHaveToT(parent)
				end
				if parent.haveToT ~= hadToT and WhoaUF.AdjustSpellBar then
					WhoaUF:AdjustSpellBar(parent)
				end
				pendingAuraRefresh = true
				auraElapsed = 0
			end
		end
		if not pendingAuraRefresh then
			return
		end
		auraElapsed = auraElapsed + elapsed
		if auraElapsed < 0.05 then
			return
		end
		pendingAuraRefresh = false
		auraElapsed = 0
		WhoaUF:UpdateUnitAuras(parent)
	end
	watcher.OnUpdate = Watcher_OnUpdate
	totFrame.whoaAuraWatcher = watcher
	parent.whoaToTAuraWatcher = watcher
end

function WhoaUF:SyncToTAuraWatcher(parent)
	local watcher = parent and parent.whoaToTAuraWatcher
	if not watcher then
		return
	end
	if parent:IsShown() then
		if not watcher.whoaActive then
			watcher:SetScript("OnUpdate", watcher.OnUpdate)
			watcher.whoaActive = true
		end
	elseif watcher.whoaActive then
		watcher:SetScript("OnUpdate", nil)
		watcher.whoaActive = false
	end
end

function WhoaUF:ReleaseToTAuraWatcher(parent)
	local watcher = parent and parent.whoaToTAuraWatcher
	if not watcher then
		return
	end
	watcher:SetScript("OnUpdate", nil)
	watcher.whoaActive = false
end

-- Classic TargetofTargetFrameTemplate Debuff1–4 layout.
-- Host on UIParent: ToT is SecureUnitButton — child Show/Hide under lockdown fails, and
-- AuraUtil.RefreshDebuffs reading Whoa-named globals taints (taint.log).
function WhoaUF:InitToTDebuffs(frame)
	if not frame or frame.whoaToTDebuffs then
		return
	end

	local host = CreateFrame("Frame", nil, UIParent)
	host:SetSize(1, 1)
	host:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
	host:SetFrameStrata(frame:GetFrameStrata() or "LOW")
	host:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
	host:Hide()
	frame.whoaToTDebuffHost = host

	local debuffs = {}
	local baseName = (frame:GetName() or "WhoaUFToT") .. "Debuff"
	for i = 1, MAX_TOT_DEBUFFS do
		local name = baseName .. i
		local button = CreateFrame("Frame", name, host, "WhoaUFToTDebuffFrameTemplate")
		button:SetID(i)
		button.Icon = _G[name .. "Icon"]
		button.Border = _G[name .. "Border"]
		button.Cooldown = _G[name .. "Cooldown"]
		if i == 1 then
			button:SetPoint(TOPLEFT, host, TOPLEFT, 4, -10)
		elseif i == 2 then
			button:SetPoint("LEFT", debuffs[1], "RIGHT", 1, 0)
		elseif i == 3 then
			button:SetPoint(TOPLEFT, debuffs[1], BOTTOMLEFT, 0, -1)
		else
			button:SetPoint("LEFT", debuffs[3], "RIGHT", 1, 0)
		end
		button:Hide()
		debuffs[i] = button
	end
	frame.whoaToTDebuffs = debuffs
end

local function HideToTDebuffs(frame)
	local debuffs = frame and frame.whoaToTDebuffs
	if not debuffs then
		return
	end
	for i = 1, MAX_TOT_DEBUFFS do
		local button = debuffs[i]
		if button:IsShown() then
			ClearAuraPaintCache(button)
			button:Hide()
		end
	end
	local host = frame.whoaToTDebuffHost
	if host then
		host.unit = nil
		host:Hide()
	end
end

-- Manual paint only — do not call AuraUtil.RefreshAuras (taints on Whoa globals + Show on secure kids).
-- Prefer C_UnitAuras.GetAuraDataByIndex (WhoaUF:ForEachUnitAuraByIndex); avoid GetAuraSlots/ForEachAura on Mainline.
local function RefreshToTDebuffsManual(frame, unit)
	local useRaidFilter = GetCVarBool and GetCVarBool("showDispelDebuffs")
		and WhoaUF:IsAccessibleTrue(UnitCanAssist("player", unit))
	local isEnemy = WhoaUF:IsAccessibleTrue(UnitCanAttack("player", unit))
	local showCastable = SHOW_CASTABLE_DEBUFFS
	local shown = 0
	local host = frame.whoaToTDebuffHost
	if host then
		-- TargetofTargetDebuffFrameTemplate OnEnter reads self:GetParent().unit
		host.unit = unit
		host:Show()
	end

	local filter
	if WhoaUF.CreateAuraFilterString and AuraUtil and AuraUtil.AuraFilters then
		if useRaidFilter then
			filter = WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Harmful, AuraUtil.AuraFilters.Raid)
		else
			filter = WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Harmful)
		end
	else
		filter = useRaidFilter and "HARMFUL|RAID" or "HARMFUL"
	end

	local walked = WhoaUF.ForEachUnitAuraByIndex
		and WhoaUF:ForEachUnitAuraByIndex(unit, filter, MAX_TOT_DEBUFFS * 2, function(index, name, icon, _, debuffType, duration, expirationTime, caster)
			if shown >= MAX_TOT_DEBUFFS then
				return true
			end
			local casterOk = caster == nil or WhoaUF:CanAccessValue(caster)
			if showCastable ~= "0" and isEnemy and casterOk and caster ~= "player" then
				return false
			end
			local button = frame.whoaToTDebuffs[shown + 1]
			if not button or not PaintAuraIcon(button, icon) then
				return false
			end
			shown = shown + 1
			button:SetID(index or shown)
			PaintDebuffType(button, debuffType)
			PaintAuraCooldown(button, duration, expirationTime)
			button:Show()
			return shown >= MAX_TOT_DEBUFFS
		end)

	if not walked then
		HideToTDebuffs(frame)
		return
	end

	for i = shown + 1, MAX_TOT_DEBUFFS do
		local button = frame.whoaToTDebuffs[i]
		if button:IsShown() then
			ClearAuraPaintCache(button)
			button:Hide()
		end
	end
end

function WhoaUF:UpdateToTDebuffs(frame)
	if not frame or not frame.whoaToTDebuffs then
		return
	end
	if not (self.db and self.db.enabled) then
		return
	end
	if frame.kind ~= "tot" and frame.kind ~= "focustot" then
		return
	end

	local unit = frame.unit
	-- Mirror TargetOfTargetMixin:Update — not merely UnitExists / IsShown.
	-- RegisterUnitWatch keeps ToT shown for self-target / dead parent while the
	-- pin is alpha-hidden; debuffs live on UIParent and would otherwise leak.
	local shouldShow = frame:IsShown() and UnitExistsOk(unit)
	if shouldShow and self.ShouldShowToTFrame then
		shouldShow = self:ShouldShowToTFrame(frame)
	end
	if not shouldShow then
		HideToTDebuffs(frame)
		if self.RequestIdleCollect then
			self:RequestIdleCollect()
		end
		return
	end

	RefreshToTDebuffsManual(frame, unit)
	if self.ApplyToTAuraSizes then
		self:ApplyToTAuraSizes(frame)
	end
end

function WhoaUF:RefreshEditModePreviewAuras()
	if not self.editModePreviewActive or not self.unitFrames then
		return
	end
	if self.unitFrames.target then
		self:UpdateUnitAuras(self.unitFrames.target)
	end
	if self.unitFrames.focus and self.HasEditModeFocusSupport and self:HasEditModeFocusSupport() then
		self:UpdateUnitAuras(self.unitFrames.focus)
	end
end

function WhoaUF:UpdateUnitAuras(frame)
	if not frame or not frame.whoaBuffs then
		return
	end
	if not (self.db and self.db.enabled) then
		return
	end
	if frame.kind ~= "target" and frame.kind ~= "focus" then
		return
	end

	local unit = frame.unit
	local useSampleAuras = UseEditModeSampleAuras(frame)
	if not UnitExistsOk(unit) and not useSampleAuras then
		HideTrailingAuras(frame, "buff", 1, MAX_BUFFS)
		HideTrailingAuras(frame, "debuff", 1, MAX_DEBUFFS)
		if self.RequestIdleCollect then
			self:RequestIdleCollect()
		end
		return
	end

	frame.buffsOnTop = ResolveBuffsOnTop(frame)
	local mirrorAurasVertically = frame.buffsOnTop and true or false

	wipe(largeBuffList)
	wipe(largeDebuffList)

	local playerIsTarget = UnitExistsOk(unit) and WhoaUF:UnitMatchesToken(unit, "player")
	local isFriend = UnitExistsOk(unit) and WhoaUF:IsAccessibleTrue(UnitIsFriend("player", unit))
	local maxBuffs = frame.maxBuffs or MAX_BUFFS
	local maxDebuffs = frame.maxDebuffs or MAX_DEBUFFS
	local numBuffs = 0
	local numDebuffs = 0
	local showAuraCount = frame.showAuraCount
	local largeSize, smallSize = GetAuraSizes()

	local buffFilter = (WhoaUF.CreateAuraFilterString and AuraUtil and AuraUtil.AuraFilters)
		and WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Helpful)
		or "HELPFUL"
	local debuffFilter = (WhoaUF.CreateAuraFilterString and AuraUtil and AuraUtil.AuraFilters)
		and WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Harmful, AuraUtil.AuraFilters.IncludeNameplateOnly)
		or "HARMFUL|INCLUDE_NAME_PLATE_ONLY"

	-- EditMode_*.lua sample auras still use AuraUtil.ForEachAura; live units use index APIs.
	local useForEachAura = useSampleAuras and AuraUtil and AuraUtil.ForEachAura
	local useIndexApi = not useForEachAura and WhoaUF.ForEachUnitAuraByIndex

	if useIndexApi then
		local buffsOk = WhoaUF:ForEachUnitAuraByIndex(unit, buffFilter, maxBuffs, function(index, name, icon, count, _, duration, expirationTime, caster, canStealOrPurge, _, _, _, _, _, _, _, auraInstanceID)
			if numBuffs >= maxBuffs then
				return true
			end
			local button = EnsureAuraButton(frame, "buff", numBuffs + 1)
			if not button or not PaintAuraIcon(button, icon) then
				return false
			end
			numBuffs = numBuffs + 1
			button.unit = unit
			button:SetID(index or numBuffs)
			PaintAuraCount(button, count, showAuraCount, unit, auraInstanceID)
			PaintAuraCooldown(button, duration, expirationTime)
			local stealable = button.Stealable
			if stealable then
				if not playerIsTarget and WhoaUF:IsAccessibleTrue(canStealOrPurge) then
					stealable:Show()
				else
					stealable:Hide()
				end
			end
			largeBuffList[numBuffs] = ShouldAuraBeLarge(caster)
			button:ClearAllPoints()
			button:Show()
			return numBuffs >= maxBuffs
		end)

		local shownDebuffSlot = 0
		local debuffsOk = WhoaUF:ForEachUnitAuraByIndex(unit, debuffFilter, maxDebuffs * 2, function(index, name, icon, count, debuffType, duration, expirationTime, caster, _, _, _, _, _, casterIsPlayer, nameplateShowAll, _, auraInstanceID)
			if shownDebuffSlot >= maxDebuffs then
				return true
			end
			if not ShouldShowDebuff(unit, caster, nameplateShowAll, casterIsPlayer) then
				return false
			end
			local button = EnsureAuraButton(frame, "debuff", shownDebuffSlot + 1)
			if not button or not PaintAuraIcon(button, icon) then
				return false
			end
			shownDebuffSlot = shownDebuffSlot + 1
			numDebuffs = shownDebuffSlot
			button.unit = unit
			button:SetID(index or shownDebuffSlot)
			PaintAuraCount(button, count, showAuraCount, unit, auraInstanceID)
			PaintAuraCooldown(button, duration, expirationTime)
			PaintDebuffType(button, debuffType)
			largeDebuffList[shownDebuffSlot] = ShouldAuraBeLarge(caster)
			button:ClearAllPoints()
			button:Show()
			return shownDebuffSlot >= maxDebuffs
		end)

		if not buffsOk and not debuffsOk then
			HideTrailingAuras(frame, "buff", 1, MAX_BUFFS)
			HideTrailingAuras(frame, "debuff", 1, MAX_DEBUFFS)
			numBuffs = 0
			numDebuffs = 0
		end
	elseif useForEachAura then
		AuraUtil.ForEachAura(unit, buffFilter, maxBuffs, function(name, icon, count, _, duration, expirationTime, caster, canStealOrPurge)
			if not name or not icon then
				return false
			end
			if numBuffs >= maxBuffs then
				return true
			end
			numBuffs = numBuffs + 1
			local button = EnsureAuraButton(frame, "buff", numBuffs)
			button.unit = unit
			button:SetID(numBuffs)
			PaintAuraIcon(button, icon)
			PaintAuraCount(button, count, showAuraCount)
			PaintAuraCooldown(button, duration, expirationTime)
			local stealable = button.Stealable
			if stealable then
				if not playerIsTarget and WhoaUF:IsAccessibleTrue(canStealOrPurge) then
					stealable:Show()
				else
					stealable:Hide()
				end
			end
			largeBuffList[numBuffs] = ShouldAuraBeLarge(caster)
			button:ClearAllPoints()
			button:Show()
			return numBuffs >= maxBuffs
		end)

		local shownDebuffSlot = 0
		AuraUtil.ForEachAura(unit, debuffFilter, maxDebuffs, function(name, icon, count, debuffType, duration, expirationTime, caster, _, _, _, _, _, casterIsPlayer, nameplateShowAll)
			if not name then
				return false
			end
			if shownDebuffSlot >= maxDebuffs then
				return true
			end
			if icon and ShouldShowDebuff(unit, caster, nameplateShowAll, casterIsPlayer) then
				shownDebuffSlot = shownDebuffSlot + 1
				numDebuffs = shownDebuffSlot
				local button = EnsureAuraButton(frame, "debuff", shownDebuffSlot)
				button.unit = unit
				button:SetID(shownDebuffSlot)
				PaintAuraIcon(button, icon)
				PaintAuraCount(button, count, showAuraCount)
				PaintAuraCooldown(button, duration, expirationTime)
				PaintDebuffType(button, debuffType)
				largeDebuffList[shownDebuffSlot] = ShouldAuraBeLarge(caster)
				button:ClearAllPoints()
				button:Show()
			end
			return shownDebuffSlot >= maxDebuffs
		end)
	elseif UnitBuff then
		for i = 1, MAX_BUFFS do
			if numBuffs >= maxBuffs then
				break
			end
			local name, icon, count, _, duration, expirationTime, caster, canStealOrPurge = UnitBuff(unit, i)
			if not name then
				break
			end
			if icon then
				numBuffs = numBuffs + 1
				local button = EnsureAuraButton(frame, "buff", numBuffs)
				button.unit = unit
				button:SetID(i)

				PaintAuraIcon(button, icon)
				PaintAuraCount(button, count, showAuraCount)
				PaintAuraCooldown(button, duration, expirationTime)

				local stealable = button.Stealable
				if stealable then
					if not playerIsTarget and WhoaUF:IsAccessibleTrue(canStealOrPurge) then
						stealable:Show()
					else
						stealable:Hide()
					end
				end

				largeBuffList[numBuffs] = ShouldAuraBeLarge(caster)
				button:ClearAllPoints()
				button:Show()
			end
		end

		local shownDebuffSlot = 0
		for i = 1, MAX_DEBUFFS do
			if shownDebuffSlot >= maxDebuffs then
				break
			end
			local name, icon, count, debuffType, duration, expirationTime, caster, _, _, _, _, _, casterIsPlayer, nameplateShowAll = UnitDebuff(unit, i)
			if not name then
				break
			end
			if icon and ShouldShowDebuff(unit, caster, nameplateShowAll, casterIsPlayer) then
				shownDebuffSlot = shownDebuffSlot + 1
				numDebuffs = shownDebuffSlot
				local button = EnsureAuraButton(frame, "debuff", shownDebuffSlot)
				button.unit = unit
				button:SetID(i)

				PaintAuraIcon(button, icon)
				PaintAuraCount(button, count, showAuraCount)
				PaintAuraCooldown(button, duration, expirationTime)
				PaintDebuffType(button, debuffType)

				largeDebuffList[shownDebuffSlot] = ShouldAuraBeLarge(caster)
				button:ClearAllPoints()
				button:Show()
			end
		end
	end
	HideTrailingAuras(frame, "buff", numBuffs + 1, MAX_BUFFS)
	HideTrailingAuras(frame, "debuff", numDebuffs + 1, MAX_DEBUFFS)

	frame.auraRows = 0
	frame.spellbarAnchor = nil
	frame.haveToT = HasVisibleToT(frame)
	local totRowWidth = frame.TOT_AURA_ROW_WIDTH or TOT_AURA_ROW_WIDTH
	local buffRowWidth = frame.haveToT and totRowWidth or AURA_ROW_WIDTH
	LayoutAuras(frame, "buff", numBuffs, numDebuffs, largeBuffList, buffRowWidth, AURA_ROW_GAP, largeSize, smallSize, isFriend, mirrorAurasVertically)

	local debuffRowWidth = (frame.haveToT and frame.auraRows < NUM_TOT_AURA_ROWS and totRowWidth) or AURA_ROW_WIDTH
	LayoutAuras(frame, "debuff", numDebuffs, numBuffs, largeDebuffList, debuffRowWidth, AURA_ROW_GAP, largeSize, smallSize, isFriend, mirrorAurasVertically)

	if WhoaUF.AdjustSpellBar then
		WhoaUF:AdjustSpellBar(frame)
	end
end
