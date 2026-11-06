--[[
	Party member frames (classic layout).
	Reference: reference/Blizzard_UnitFrame/Classic/PartyFrameTemplates.xml,
	           Classic/PartyMemberFrame.lua, Shared/PartyFrame.lua
]]

local MAX_PARTY_MEMBERS = 4
local DEFAULT_PARTY_SPACING = 10
local PARTY_PET_SPACING = 26
local MAX_PARTY_AURAS = 4
local PARTY_AURA_SIZE = 15
local PARTY_AURA_SPACING = 2
local PARTY_AURA_ANCHOR_X = 48
local PARTY_AURA_ANCHOR_Y = -32
local PARTY_PET_AURA_ANCHOR_X = 24
local PARTY_PET_AURA_ANCHOR_Y = -16
local PARTY_BUFF_TOOLTIP_MAX = 16
local PARTY_BUFF_TOOLTIP_ROW = 8

local partyContainer
local partyFrames = {}
local lastPartyMemberCount = 0
local partyBuffTooltip
local partyBuffTooltipIcons = {}
local SyncPartyMemberPulse
local pendingPartyLayout
local pendingPartyPetUpdate

local function ForceShowPartyPets()
	return WhoaUF.IsForceShowFrame and WhoaUF:IsForceShowFrame("partypet")
end

local function GetPartySpacing()
	if ForceShowPartyPets() or (GetCVarBool and GetCVarBool("showPartyPets")) then
		return PARTY_PET_SPACING
	end
	return DEFAULT_PARTY_SPACING
end

local function ShouldShowPartyPets()
	if ForceShowPartyPets() then
		return true
	end
	if GetCVarBool then
		return GetCVarBool("showPartyPets")
	end
	return true
end

local function GetPartyUnit(frame)
	return frame.overrideUnit or frame.unit
end

local function GetAuraWarningAlpha()
	if BuffFrame and BuffFrame.AuraContainer and BuffFrame.AuraContainer.GetAuraWarningAlphaForDuration then
		return BuffFrame.AuraContainer:GetAuraWarningAlphaForDuration(0)
	end
	local t = GetTime() * 4
	return 0.35 + (math.abs((t % 1) - 0.5) * 2) * 0.65
end

local function SetDebuffBorderColor(border, debuffType)
	if AuraUtil and AuraUtil.SetAuraBorderColor then
		AuraUtil.SetAuraBorderColor(border, debuffType)
		return
	end
	local color = WhoaUF:GetDebuffTypeColor(debuffType)
	border:SetVertexColor(color.r, color.g, color.b)
end

local function GetPartyDebuffFilter(unit)
	if GetCVarBool and GetCVarBool("showDispelDebuffs") and UnitCanAssist("player", unit) then
		if WhoaUF.CreateAuraFilterString and AuraUtil and AuraUtil.AuraFilters then
			return WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Harmful, AuraUtil.AuraFilters.Raid)
		end
		return "HARMFUL|RAID"
	end
	if WhoaUF.CreateAuraFilterString and AuraUtil and AuraUtil.AuraFilters then
		return WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Harmful)
	end
	return "HARMFUL"
end

local function ShouldShowPartyDebuff(unit, caster)
	if SHOW_CASTABLE_DEBUFFS == "0" then
		return true
	end
	-- Secret can-attack / caster: show rather than Lua-test secrets.
	if not WhoaUF:CanAccessValue(UnitCanAttack("player", unit)) then
		return true
	end
	if UnitCanAttack("player", unit) then
		if caster == nil then
			return false
		end
		if not WhoaUF:CanAccessValue(caster) then
			return true
		end
		if caster ~= "player" then
			return false
		end
	end
	return true
end

local function CreatePartyAuraButton(parent, index)
	local name = parent:GetName() .. "Aura" .. index
	local btn = CreateFrame("Button", name, parent)
	btn:SetSize(PARTY_AURA_SIZE, PARTY_AURA_SIZE)
	btn:EnableMouse(true)
	btn:Hide()

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	btn.Icon = icon

	local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", 5, 0)
	count:Hide()
	btn.Count = count

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(17, 17)
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
	border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
	border:Hide()
	btn.DebuffBorder = border

	local cooldown = CreateFrame("Cooldown", name .. "Cooldown", btn, "CooldownFrameTemplate")
	cooldown:SetPoint("CENTER", 0, -1)
	cooldown:Hide()
	btn.Cooldown = cooldown

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.isBuff then
			GameTooltip:SetUnitBuff(self.unit, self.auraIndex)
		else
			GameTooltip:SetUnitDebuff(self.unit, self.auraIndex, self.debuffFilter)
		end
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)

	return btn
end

local function LayoutPartyAuraButtons(frame, shown)
	if frame.whoaAuraShown == shown then
		return
	end
	frame.whoaAuraShown = shown
	local host = frame.AuraHost or frame
	for i = 1, MAX_PARTY_AURAS do
		local btn = frame.whoaAuras[i]
		if i <= shown then
			local x = PARTY_AURA_ANCHOR_X + ((i - 1) * (PARTY_AURA_SIZE + PARTY_AURA_SPACING))
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", host, "TOPLEFT", x, PARTY_AURA_ANCHOR_Y)
			btn:Show()
		elseif btn:IsShown() then
			btn:Hide()
		end
	end
end

local function LayoutPartyPetAuraButtons(frame, shown)
	if frame.whoaAuraShown == shown then
		return
	end
	frame.whoaAuraShown = shown
	for i = 1, MAX_PARTY_AURAS do
		local btn = frame.whoaAuras[i]
		if i <= shown then
			local x = PARTY_PET_AURA_ANCHOR_X + ((i - 1) * (PARTY_AURA_SIZE + PARTY_AURA_SPACING))
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", frame, "TOPLEFT", x, PARTY_PET_AURA_ANCHOR_Y)
			btn:Show()
		elseif btn:IsShown() then
			btn:Hide()
		end
	end
end

local function PaintPartyAuraButton(btn, unit, auraIndex, icon, count, debuffType, duration, expirationTime, isBuff, debuffFilter, auraInstanceID)
	btn.unit = unit
	btn.auraIndex = auraIndex
	btn.isBuff = isBuff
	btn.debuffFilter = debuffFilter
	-- SetTexture accepts secret fileIDs.
	if icon ~= nil then
		btn.Icon:SetTexture(icon)
	end
	local countFS = btn.Count
	if countFS then
		local painted = false
		if unit and auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
			local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, auraInstanceID, 2)
			if ok then
				painted = true
				if text and text ~= "" then
					countFS:SetText(text)
					countFS:Show()
				else
					countFS:Hide()
				end
			end
		end
		if not painted then
			if WhoaUF:NeedsSecretSafeNumberOps(count) then
				-- Without GetAuraApplicationDisplayCount we cannot prove count > 1.
				countFS:Hide()
			elseif count and count > 1 then
				countFS:SetText(count >= 100 and (BUFF_STACKS_OVERFLOW or "99") or count)
				countFS:Show()
			else
				countFS:Hide()
			end
		end
	end
	if isBuff then
		btn.DebuffBorder:Hide()
	else
		btn.DebuffBorder:Show()
		if debuffType == nil or WhoaUF:CanAccessValue(debuffType) then
			SetDebuffBorderColor(btn.DebuffBorder, debuffType)
		end
	end
	local cooldown = btn.Cooldown
	if cooldown then
		if WhoaUF:NeedsSecretSafeNumberOps(duration, expirationTime) then
			if duration ~= nil and expirationTime ~= nil and cooldown.SetCooldownFromExpirationTime then
				cooldown:SetCooldownFromExpirationTime(expirationTime, duration)
			elseif CooldownFrame_Clear then
				CooldownFrame_Clear(cooldown)
			end
		elseif CooldownFrame_Set and duration and expirationTime and duration > 0 and expirationTime > 0 then
			CooldownFrame_Set(cooldown, expirationTime - duration, duration, true)
		elseif CooldownFrame_Clear then
			CooldownFrame_Clear(cooldown)
		end
	end
end

local function HidePartyAuras(frame)
	if not frame or not frame.whoaAuras then
		return
	end
	frame.whoaAuraShown = 0
	for i = 1, MAX_PARTY_AURAS do
		local btn = frame.whoaAuras[i]
		if btn and btn:IsShown() then
			btn:Hide()
		end
	end
end

local function UpdatePartyAuras(frame)
	if not frame or not frame.whoaAuras then
		return
	end
	local unit = GetPartyUnit(frame)
	if not UnitExists(unit) or not frame:IsShown() then
		HidePartyAuras(frame)
		frame.hasDispellable = nil
		frame.debuffCountdown = 0
		if frame.Status then
			frame.Status:Hide()
		end
		if frame.kind == "party" then
			SyncPartyMemberPulse(frame)
		end
		return
	end

	local showBuffs = frame.showBuffs
	local shown = 0
	if not WhoaUF.ForEachUnitAuraByIndex then
		HidePartyAuras(frame)
		return
	end
	if showBuffs then
		local filter = (GetCVarBool and GetCVarBool("showCastableBuffs") and UnitCanAssist("player", unit)) and "HELPFUL|RAID" or "HELPFUL"
		if WhoaUF.CreateAuraFilterString and AuraUtil and AuraUtil.AuraFilters then
			if GetCVarBool and GetCVarBool("showCastableBuffs") and UnitCanAssist("player", unit) then
				filter = WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Helpful, AuraUtil.AuraFilters.Raid)
			else
				filter = WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Helpful)
			end
		end
		local ok = WhoaUF:ForEachUnitAuraByIndex(unit, filter, 40, function(i, _, icon, count, _, duration, expirationTime, _, _, _, _, _, _, _, _, _, auraInstanceID)
			if shown >= MAX_PARTY_AURAS then
				return true
			end
			if icon == nil then
				return false
			end
			shown = shown + 1
			PaintPartyAuraButton(frame.whoaAuras[shown], unit, i, icon, count, nil, duration, expirationTime, true, filter, auraInstanceID)
			return shown >= MAX_PARTY_AURAS
		end)
		if not ok then
			HidePartyAuras(frame)
			return
		end
		frame.hasDispellable = nil
		frame.debuffCountdown = 0
		if frame.Status then
			frame.Status:Hide()
		end
	else
		local filter = GetPartyDebuffFilter(unit)
		local statusColor
		frame.hasDispellable = nil
		local ok = WhoaUF:ForEachUnitAuraByIndex(unit, filter, 40, function(i, _, icon, count, debuffType, duration, expirationTime, caster, _, _, _, _, _, _, _, _, auraInstanceID)
			if shown >= MAX_PARTY_AURAS then
				return true
			end
			if icon == nil then
				return false
			end
			local showDebuff = true
			if caster == nil or WhoaUF:CanAccessValue(caster) then
				showDebuff = ShouldShowPartyDebuff(unit, caster)
			end
			if not showDebuff then
				return false
			end
			shown = shown + 1
			PaintPartyAuraButton(frame.whoaAuras[shown], unit, i, icon, count, debuffType, duration, expirationTime, false, filter, auraInstanceID)
			if frame.Status and debuffType and WhoaUF:CanAccessValue(debuffType) then
				statusColor = WhoaUF:GetDebuffTypeColor(debuffType)
				frame.hasDispellable = true
			end
			return shown >= MAX_PARTY_AURAS
		end)
		if not ok then
			HidePartyAuras(frame)
			return
		end
		if frame.Status then
			if statusColor then
				frame.Status:SetVertexColor(statusColor.r, statusColor.g, statusColor.b)
				if shown >= MAX_PARTY_AURAS then
					frame.debuffCountdown = 30
				else
					frame.debuffCountdown = 0
				end
			else
				frame.debuffCountdown = 0
				frame.Status:Hide()
			end
		end
	end

	if frame.kind == "partypet" then
		LayoutPartyPetAuraButtons(frame, shown)
	else
		LayoutPartyAuraButtons(frame, shown)
		SyncPartyMemberPulse(frame)
	end
end

local function EnsurePartyBuffTooltip()
	if partyBuffTooltip then
		return partyBuffTooltip
	end
	local tip = CreateFrame("Frame", "WhoaUFPartyBuffTooltip", UIParent, "BackdropTemplate")
	tip:SetFrameStrata("TOOLTIP")
	tip:SetSize(1, 1)
	tip:Hide()
	tip.icons = partyBuffTooltipIcons
	partyBuffTooltip = tip
	return tip
end

function WhoaUF:ShowPartyBuffTooltip(frame)
	if not frame or not frame:IsShown() then
		return
	end
	local unit = GetPartyUnit(frame)
	if not UnitExists(unit) then
		return
	end
	local tip = EnsurePartyBuffTooltip()
	local filter = (GetCVarBool and GetCVarBool("showCastableBuffs") and UnitCanAssist("player", unit)) and "HELPFUL|RAID" or "HELPFUL"
	if WhoaUF.CreateAuraFilterString and AuraUtil and AuraUtil.AuraFilters then
		if GetCVarBool and GetCVarBool("showCastableBuffs") and UnitCanAssist("player", unit) then
			filter = WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Helpful, AuraUtil.AuraFilters.Raid)
		else
			filter = WhoaUF:CreateAuraFilterString(AuraUtil.AuraFilters.Helpful)
		end
	end
	local shown = 0
	for i = 1, PARTY_BUFF_TOOLTIP_MAX do
		local btn = tip.icons[i]
		if not btn then
			btn = CreatePartyAuraButton(tip, i)
			btn:SetScript("OnEnter", nil)
			btn:SetScript("OnLeave", nil)
			tip.icons[i] = btn
		end
		btn:Hide()
	end
	if WhoaUF.ForEachUnitAuraByIndex then
		WhoaUF:ForEachUnitAuraByIndex(unit, filter, PARTY_BUFF_TOOLTIP_MAX, function(_, _, icon)
			if shown >= PARTY_BUFF_TOOLTIP_MAX then
				return true
			end
			if icon == nil then
				return false
			end
			shown = shown + 1
			local btn = tip.icons[shown]
			btn.Icon:SetTexture(icon)
			btn.DebuffBorder:Hide()
			btn.Count:Hide()
			if btn.Cooldown then
				CooldownFrame_Clear(btn.Cooldown)
			end
			local col = (shown - 1) % PARTY_BUFF_TOOLTIP_ROW
			local row = math.floor((shown - 1) / PARTY_BUFF_TOOLTIP_ROW)
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", tip, "TOPLEFT", 8 + (col * (PARTY_AURA_SIZE + PARTY_AURA_SPACING)), -8 - (row * (PARTY_AURA_SIZE + PARTY_AURA_SPACING)))
			btn:Show()
			return shown >= PARTY_BUFF_TOOLTIP_MAX
		end)
	end
	if shown == 0 then
		tip:Hide()
		return
	end
	local rows = math.ceil(shown / PARTY_BUFF_TOOLTIP_ROW)
	local cols = math.min(PARTY_BUFF_TOOLTIP_ROW, shown)
	tip:SetSize((cols * (PARTY_AURA_SIZE + PARTY_AURA_SPACING)) + 7, (rows * (PARTY_AURA_SIZE + PARTY_AURA_SPACING)) + 7)
	tip:ClearAllPoints()
	tip:SetPoint("TOPLEFT", frame, "TOPLEFT", 47, -30)
	tip:Show()
end

function WhoaUF:HidePartyBuffTooltip()
	if partyBuffTooltip then
		partyBuffTooltip:Hide()
	end
end

local function UpdatePartyReadyCheck(frame)
	local ready = frame.ReadyCheck
	if not ready then
		return
	end
	local unit = GetPartyUnit(frame)
	local readyCheckStatus = GetReadyCheckStatus and GetReadyCheckStatus(unit)
	if UnitName(unit) and WhoaUF:IsAccessibleTrue(UnitIsConnected(unit)) and readyCheckStatus then
		if readyCheckStatus == "ready" and ReadyCheck_Confirm then
			ReadyCheck_Confirm(ready, 1)
		elseif readyCheckStatus == "notready" and ReadyCheck_Confirm then
			ReadyCheck_Confirm(ready, 0)
		elseif ReadyCheck_Start then
			ReadyCheck_Start(ready)
		end
	else
		ready:Hide()
	end
end

local function UpdatePartyMasterLooter(frame)
	local icon = frame.MasterIcon
	if not icon then
		return
	end
	if WhoaUF.GetMasterLooterIconTexture then
		icon:SetTexture(WhoaUF:GetMasterLooterIconTexture())
	end
	local lootMaster
	if C_PartyInfo and C_PartyInfo.GetLootMethod then
		_, lootMaster = C_PartyInfo.GetLootMethod()
	elseif GetLootMethod then
		_, lootMaster = GetLootMethod()
	end
	if lootMaster and lootMaster == frame.partyIndex then
		icon:Show()
	else
		icon:Hide()
	end
end

-- 2x2 sheet (guide | healer / tank | damager).
-- Ref: Blizzard_SharedXMLBase/TextureUtil.lua GetTexCoordsForOldRoleSmallCircle
local ROLE_ICON_COORDS = {
	TANK = { 0, 19 / 64, 22 / 64, 41 / 64 },
	HEALER = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
	DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
-- Ref: Blizzard_UnitFrame/Classic/PartyFrameTemplates.xml GuideIcon TexCoords
local GUIDE_ICON_COORDS = { 0, 19 / 64, 1 / 64, 20 / 64 }

local function GetPartyRoleIconTexture()
	if WhoaUF.GetPortraitRoleIconTexture then
		return WhoaUF:GetPortraitRoleIconTexture()
	end
	return "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
end

-- Role shares the top-left slot with the leader crown (16px) / guide (19px);
-- sit just right of whichever shows. Master looter stays at its stock x=32.
local function LayoutPartyRoleIcon(frame, icon)
	local x, y = 0, 0
	if frame.GuideIcon and frame.GuideIcon:IsShown() then
		x = 17
	elseif frame.LeaderIcon and frame.LeaderIcon:IsShown() then
		x, y = 14, 1
	end
	if icon.whoaLayoutX == x then
		return
	end
	icon.whoaLayoutX = x
	icon:ClearAllPoints()
	icon:SetPoint("TOPLEFT", x, y)
end

local function UpdatePartyRoleIcon(frame)
	local icon = frame.RoleIcon
	if not icon then
		return
	end
	LayoutPartyRoleIcon(frame, icon)
	local unit = GetPartyUnit(frame)

	-- Prefer Whoa Media\shared\{light|dark}\UI-LFG-ICON-PORTRAITROLES when role is readable.
	if UnitGroupRolesAssigned then
		local role = UnitGroupRolesAssigned(unit)
		if WhoaUF:CanAccessValue(role) then
			if role and role ~= "NONE" and ROLE_ICON_COORDS[role] then
				local coords = ROLE_ICON_COORDS[role]
				icon:SetTexture(GetPartyRoleIconTexture())
				icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
				icon:Show()
			else
				icon:Hide()
			end
			return
		end
	end

	-- Secret role (12.1.5+): UnitFrameUtil CUF atlases. Live retail: false → hide.
	if WhoaUF.TryUpdateUnitRoleIcon and WhoaUF:TryUpdateUnitRoleIcon(icon, unit, false) then
		return
	end
	icon:Hide()
end

local function UpdatePartyNotPresent(frame)
	local icon = frame.NotPresentIcon
	if not icon then
		return
	end
	local unit = GetPartyUnit(frame)
	local tooltip
	if UnitInOtherParty and UnitInOtherParty(unit) then
		frame:SetAlpha(0.6)
		icon.texture:SetTexture("Interface\\LFGFrame\\LFG-Eye")
		icon.texture:SetTexCoord(0.125, 0.25, 0.25, 0.5)
		if icon.Border then
			icon.Border:Show()
		end
		tooltip = PARTY_IN_PUBLIC_GROUP_MESSAGE
	elseif WhoaUF:IsAccessibleTrue(UnitIsConnected(unit)) and UnitPhaseReason and UnitPhaseReason(unit) then
		local phaseReason = UnitPhaseReason(unit)
		frame:SetAlpha(0.6)
		icon.texture:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon")
		icon.texture:SetTexCoord(0.15625, 0.84375, 0.15625, 0.84375)
		if icon.Border then
			icon.Border:Hide()
		end
		if PartyUtil and PartyUtil.GetPhasedReasonString then
			tooltip = PartyUtil.GetPhasedReasonString(phaseReason, unit)
		end
	else
		frame:SetAlpha(1)
		icon:Hide()
		return
	end
	icon.tooltip = tooltip
	icon:Show()
end

local function PartyMemberHealthCheck(frame)
	local bar = frame.Health
	if not bar or not frame.Portrait then
		return
	end
	local unit = GetPartyUnit(frame)
	-- Mainline: StatusBar GetValue/GetMinMax inherit secrets after SetValue — never
	-- cur/max or coalesce (`or 0`). Skip low-HP tint/pulse; dead/ghost stay Unit* flags.
	if WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues() then
		frame.unitHPPercent = nil
		if WhoaUF:IsAccessibleTrue(UnitIsDead(unit)) then
			frame.Portrait:SetVertexColor(0.35, 0.35, 0.35, 1)
		elseif WhoaUF:IsAccessibleTrue(UnitIsGhost(unit)) then
			frame.Portrait:SetVertexColor(0.2, 0.2, 0.75, 1)
		else
			frame.Portrait:SetVertexColor(1, 1, 1)
		end
		return
	end
	local max = select(2, bar:GetMinMaxValues()) or 0
	local cur = bar:GetValue() or 0
	local pct = (max > 0) and (cur / max) or 0
	frame.unitHPPercent = pct
	if WhoaUF:IsAccessibleTrue(UnitIsDead(unit)) then
		frame.Portrait:SetVertexColor(0.35, 0.35, 0.35, 1)
	elseif WhoaUF:IsAccessibleTrue(UnitIsGhost(unit)) then
		frame.Portrait:SetVertexColor(0.2, 0.2, 0.75, 1)
	elseif pct > 0 and pct <= 0.2 then
		frame.Portrait:SetVertexColor(1, 0, 0)
	else
		frame.Portrait:SetVertexColor(1, 1, 1)
	end
end

local function UpdatePartyMemberHealthPulse(frame, elapsed)
	-- Mainline: unitHPPercent is nil; still clear alpha if a Classic session left pulse state.
	if (WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues())
		or not frame.unitHPPercent
		or frame.unitHPPercent <= 0
		or frame.unitHPPercent > 0.2
	then
		if WhoaUF._UF and WhoaUF._UF.SetPortraitAlpha then
			WhoaUF._UF.SetPortraitAlpha(frame, 1)
		elseif frame.Portrait then
			frame.Portrait:SetAlpha(1)
		end
		return
	end
	frame.statusCounter = (frame.statusCounter or 0) + elapsed
	local sign = frame.statusSign or -1
	if frame.statusCounter > 0.5 then
		sign = -sign
		frame.statusSign = sign
		frame.statusCounter = frame.statusCounter % 0.5
	end
	local alpha
	if sign == 1 then
		alpha = (127 + (frame.statusCounter * 256)) / 255
	else
		alpha = (255 - (frame.statusCounter * 256)) / 255
	end
	if WhoaUF._UF and WhoaUF._UF.SetPortraitAlpha then
		WhoaUF._UF.SetPortraitAlpha(frame, alpha)
	elseif frame.Portrait then
		frame.Portrait:SetAlpha(alpha)
	end
end

local function UpdatePartyDispellableStatus(frame, elapsed)
	local status = frame.Status
	if not status then
		return
	end
	-- Status chrome only stays up while debuffCountdown is armed (4+ debuffs).
	if frame.hasDispellable and frame.debuffCountdown and frame.debuffCountdown > 0 then
		status:Show()
		status:SetAlpha(GetAuraWarningAlpha())
		frame.debuffCountdown = frame.debuffCountdown - elapsed
		if frame.debuffCountdown <= 0 then
			frame.debuffCountdown = 0
			status:Hide()
		end
	elseif status:IsShown() then
		status:Hide()
	end
end

-- Pulse only while low-HP portrait throb or dispellable status countdown is active.
local function PartyMemberNeedsPulse(frame)
	if not frame or not frame:IsShown() then
		return false
	end
	-- Mainline: no low-HP throb (unitHPPercent never set from secret bar values).
	if not (WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues())
		and frame.unitHPPercent
		and frame.unitHPPercent > 0
		and frame.unitHPPercent <= 0.2
	then
		return true
	end
	if frame.hasDispellable and frame.debuffCountdown and frame.debuffCountdown > 0 then
		return true
	end
	return false
end

local function SyncPartyMemberPulse_Impl(frame)
	local pulse = frame.memberPulse
	if not pulse then
		return
	end
	local need = PartyMemberNeedsPulse(frame)
	if need then
		if not pulse.whoaActive then
			pulse:SetScript("OnUpdate", pulse.OnUpdate)
			pulse.whoaActive = true
		end
	elseif pulse.whoaActive then
		pulse:SetScript("OnUpdate", nil)
		pulse.whoaActive = false
	end
end
SyncPartyMemberPulse = SyncPartyMemberPulse_Impl

local function UpdatePartyPetHealth(frame)
	local unit = frame.unit
	local bar = frame.Health
	if not bar then
		return
	end
	bar.unit = unit
	local max = UnitHealthMax(unit)
	local cur = UnitHealth(unit)
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(max) and max == 0 then
		max = 1
	elseif max == nil then
		max = 1
	end
	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	bar.whoaFrequentMax = max
	if WhoaUF.ApplyHealthBarColor then
		WhoaUF:ApplyHealthBarColor(bar, unit)
	else
		bar.whoaHR, bar.whoaHG, bar.whoaHB = nil, nil, nil
		bar:SetStatusBarColor(0, 1, 0)
	end
	WhoaUF:UpdateBarTextString(bar)
end

local function SetPartyPetShown(pet, show)
	if not pet then
		return
	end
	local setMouse = WhoaUF._UF and WhoaUF._UF.SetSecureMouseEnabled
	if InCombatLockdown() then
		-- SecureUnitButton Show/Hide blocked in combat — alpha-fade until REGEN flush.
		-- Disable mouse while alpha-hidden so clicks do not hit an invisible pet.
		if show then
			if pet:IsShown() and pet:GetAlpha() ~= 1 then
				pet:SetAlpha(1)
				if setMouse then
					setMouse(pet, true)
				end
			elseif not pet:IsShown() then
				pendingPartyPetUpdate = true
			end
		elseif pet:IsShown() then
			if pet:GetAlpha() ~= 0 then
				pet:SetAlpha(0)
			end
			if setMouse then
				setMouse(pet, false)
			end
			pendingPartyPetUpdate = true
		end
		return
	end
	if pet:GetAlpha() ~= 1 then
		pet:SetAlpha(1)
	end
	if setMouse then
		setMouse(pet, true)
	end
	pet:SetShown(show and true or false)
end

local function UpdatePartyPet(frame)
	if not frame or not frame.PetFrame then
		return
	end
	local pet = frame.PetFrame
	local unit = GetPartyUnit(frame)
	local forcePets = ForceShowPartyPets()
	-- Secret connected flag counts as online (same as UpdatePartyOnline).
	local connected = UnitIsConnected(unit)
	local provenOffline = WhoaUF:CanAccessValue(connected) and not connected
	local realPet = UnitExists(unit) and not provenOffline and UnitExists(pet.unit)
	if realPet and ShouldShowPartyPets() then
		SetPartyPetShown(pet, true)
		if not pet:IsShown() then
			return
		end
		if WhoaUF._UF and WhoaUF._UF.UpdatePortrait then
			WhoaUF._UF.UpdatePortrait(pet, pet.unit)
		else
			SetPortraitTexture(pet.Portrait, pet.unit)
		end
		UpdatePartyPetHealth(pet)
		UpdatePartyAuras(pet)
		if WhoaUF.UpdateFrameThreat then
			WhoaUF:UpdateFrameThreat(pet)
		end
	elseif forcePets and ShouldShowPartyPets() then
		-- Dev force-show: empty party-pet chrome (real pet path above when unit exists).
		SetPartyPetShown(pet, true)
		if not pet:IsShown() then
			return
		end
		if pet.Portrait then
			pet.Portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
		end
		if pet.Health then
			pet.Health:SetMinMaxValues(0, 1)
			pet.Health:SetValue(1)
			pet.Health.whoaHR, pet.Health.whoaHG, pet.Health.whoaHB = nil, nil, nil
			if WhoaUF.ApplyHealthBarColor then
				WhoaUF:ApplyHealthBarColor(pet.Health, "player")
			else
				pet.Health:SetStatusBarColor(0, 1, 0)
			end
		end
		HidePartyAuras(pet)
	else
		SetPartyPetShown(pet, false)
		HidePartyAuras(pet)
	end
end

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

local function SetupPartyStatusBar(bar, overlay, centerX, centerY, leftX, rightX)
	local texture
	if WhoaUF.GetStatusBarTexturePaths then
		texture = WhoaUF:GetStatusBarTexturePaths()
	end
	bar:SetStatusBarTexture(texture or "Interface\\TargetingFrame\\UI-StatusBar")
	bar.textLockable = true
	bar.cvar = "statusText"
	bar.cvarLabel = "STATUS_TEXT_PARTY"
	bar.lockShow = bar.lockShow or 0
	bar.capNumericDisplay = true
	bar.controlsShownState = false
	if bar.EnableMouseMotion then
		bar:EnableMouseMotion(true)
	else
		bar:EnableMouse(false)
	end

	local center = CreateBarFontString(overlay)
	center:SetPoint("CENTER", overlay, "TOPLEFT", centerX, centerY)
	local left = CreateBarFontString(overlay, "LEFT")
	left:SetPoint("LEFT", overlay, "TOPLEFT", leftX, centerY)
	local right = CreateBarFontString(overlay, "RIGHT")
	right:SetPoint("RIGHT", overlay, "TOPLEFT", rightX, centerY)
	bar:SetBarText(center, left, right)
	if WhoaUF.InstallStatusBarText then
		WhoaUF:InstallStatusBarText(bar)
	end
	WhoaUF:UpdateBarTextString(bar)
end

local function ShouldShowWhoaPartyFrames()
	-- Mainline: never call ShouldShowPartyFrames() — it does
	-- EditModeManagerFrame:ArePartyFramesForcedShown() and object-taints the
	-- manager → CompactParty RefreshMembers → CUF secret oldR.
	if WhoaUF.IsMainline and WhoaUF:IsMainline() then
		local force = WhoaUF.AreEditModePartyFramesForcedShown and WhoaUF:AreEditModePartyFramesForcedShown()
		local show = force or (IsInGroup() and not IsInRaid()) or (ShouldShowArenaParty and ShouldShowArenaParty())
		if show and WhoaUF.IsRaidStylePartyFramesEnabled and WhoaUF:IsRaidStylePartyFramesEnabled() then
			show = false
		end
		return show
	end
	if ShouldShowPartyFrames then
		local show = ShouldShowPartyFrames()
		if WhoaUF.IsRaidStylePartyFramesEnabled then
			show = show and not WhoaUF:IsRaidStylePartyFramesEnabled()
		end
		return show
	end
	return IsInGroup() and not IsInRaid()
end

-- Dev force-show: sample cur/max so status text can preview Interface display mode
-- (NUMERIC / PERCENT / BOTH / NONE) without a real party member.
local FORCE_SHOW_PARTY_PREVIEW_MAX = 100

local function PaintPartyForceShowBars(frame)
	local textDisplay = GetCVar and GetCVar("statusTextDisplay")
	local hideText = textDisplay == "NONE"
	-- Preview keeps text visible for non-NONE modes even if statusText is off.
	local forceShow = not hideText

	local health = frame.Health
	if health then
		health.forceHideText = hideText
		health.forceShow = forceShow or nil
		health.showNumeric = false
		health.showPercentage = false
		health.unit = frame.unit
		health:SetMinMaxValues(0, FORCE_SHOW_PARTY_PREVIEW_MAX)
		health:SetValue(FORCE_SHOW_PARTY_PREVIEW_MAX)
		-- Preview follows Colors options (class tint via player; else Classic green).
		health.whoaHR, health.whoaHG, health.whoaHB = nil, nil, nil
		if WhoaUF.ApplyHealthBarColor then
			WhoaUF:ApplyHealthBarColor(health, "player")
		else
			health:SetStatusBarColor(0, 1, 0)
		end
		health:SetAlpha(1)
		WhoaUF:UpdateBarTextString(health)
	end
	local power = frame.Power
	if power then
		power.forceHideText = hideText
		power.forceShow = forceShow or nil
		power.showNumeric = false
		power.showPercentage = false
		power.zeroText = nil
		power.powerToken = "MANA"
		local mana = WhoaUF:GetPowerBarColor("MANA")
		power:SetStatusBarColor(mana.r, mana.g, mana.b)
		power:SetMinMaxValues(0, FORCE_SHOW_PARTY_PREVIEW_MAX)
		power:SetValue(FORCE_SHOW_PARTY_PREVIEW_MAX)
		power:SetAlpha(1)
		WhoaUF:UpdateBarTextString(power)
	end
	if frame.Disconnect then
		frame.Disconnect:Hide()
	end
	if frame.Portrait then
		frame.Portrait:SetVertexColor(1, 1, 1)
	end
	frame.unitHPPercent = 1
end

local function ClearPartyForceShowBarFlags(bar)
	if not bar then
		return
	end
	-- Force-show paints may leave whoaH* out of sync with the StatusBar color.
	if bar.forceShow then
		bar.whoaHR, bar.whoaHG, bar.whoaHB = nil, nil, nil
	end
	bar.forceShow = nil
end

local function UpdatePartyPower(frame)
	local unit = frame.unit
	local bar = frame.Power
	if not bar then
		return
	end
	ClearPartyForceShowBarFlags(bar)
	local powerType, powerToken, altR, altG, altB = UnitPowerType(unit)
	local max = UnitPowerMax(unit, powerType)
	local cur = UnitPower(unit, powerType)

	bar.unit = unit
	-- Never assign secret tokens/types into fields used as table keys later.
	if WhoaUF:CanAccessValue(powerType) then
		bar.powerType = powerType
	end
	if WhoaUF:CanAccessValue(powerToken) then
		bar.powerToken = powerToken
	else
		bar.powerToken = nil
	end
	bar.showPercentage = false
	bar.pauseUpdates = false
	-- CanAccessValue first — `powerToken ~= nil` / == compare errors on secret strings.
	local tokenOk = WhoaUF:CanAccessValue(powerToken) and powerToken ~= nil
	if tokenOk and (powerToken == "RAGE" or powerToken == "RUNIC_POWER") then
		bar.zeroText = ""
	else
		bar.zeroText = nil
	end

	local info = WhoaUF:GetPowerBarColor(powerToken, powerType)
	if not bar.lockColor then
		local hasToken = tokenOk and WhoaUF.PowerBarColor and WhoaUF.PowerBarColor[powerToken]
		if hasToken then
			bar:SetStatusBarColor(info.r, info.g, info.b, 1)
		elseif altR then
			bar:SetStatusBarColor(altR, altG, altB, 1)
		else
			bar:SetStatusBarColor(info.r, info.g, info.b, 1)
		end
	end

	local maxAccessible = WhoaUF:CanAccessValue(max)
	-- Proven empty resource only — secret max still paints via SetMinMaxValues/SetValue.
	if maxAccessible and max == 0 then
		bar.whoaPowerPainted = nil
		bar.currValue = nil
		bar.whoaFrequentMax = 0
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		bar:Hide()
		return
	end

	bar:SetMinMaxValues(0, max)
	bar.whoaFrequentMax = max
	-- Only gray-out when we can prove offline; secret connected ≠ disconnected.
	local connected = UnitIsConnected(unit)
	local provenOffline = WhoaUF:CanAccessValue(connected) and not connected
	if provenOffline then
		bar:SetValue(max)
		bar.currValue = max
		if not bar.lockColor then
			bar:SetStatusBarColor(0.5, 0.5, 0.5, 1)
		end
	else
		bar:SetValue(cur)
		bar.currValue = cur
	end
	bar.whoaPowerPainted = true
	if not bar:IsShown() and not (InCombatLockdown() and bar:IsProtected()) then
		bar:Show()
	end
	bar:SetAlpha(provenOffline and 0.5 or 1)
	WhoaUF:UpdateBarTextString(bar)
end

local function UpdatePartyHealth(frame)
	local unit = frame.unit
	local bar = frame.Health
	ClearPartyForceShowBarFlags(bar)
	bar.unit = unit
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
	-- Absolute HP from UnitHealthMax when available; max==100 stays client-scaled.

	bar:SetMinMaxValues(0, max)
	bar:SetValue(cur)
	bar.whoaFrequentMax = max
	if WhoaUF.ApplyHealthBarColor then
		WhoaUF:ApplyHealthBarColor(bar, unit)
	elseif not WhoaUF:IsAccessibleTrue(UnitIsConnected(unit)) then
		bar.whoaHR, bar.whoaHG, bar.whoaHB = nil, nil, nil
		bar:SetStatusBarColor(0.5, 0.5, 0.5)
	else
		bar.whoaHR, bar.whoaHG, bar.whoaHB = nil, nil, nil
		bar:SetStatusBarColor(0, 1, 0)
	end
	WhoaUF:UpdateBarTextString(bar)
	if WhoaUF.UpdateHealPrediction then
		WhoaUF:UpdateHealPrediction(frame)
	end
	PartyMemberHealthCheck(frame)
	SyncPartyMemberPulse(frame)
end

local function UpdatePartyLeader(frame)
	local icon = frame.LeaderIcon
	if not icon then
		return
	end
	if WhoaUF.GetLeaderIconTexture then
		icon:SetTexture(WhoaUF:GetLeaderIconTexture())
	end
	local guide = frame.GuideIcon
	local unit = GetPartyUnit(frame)
	if WhoaUF:IsAccessibleTrue(UnitIsGroupLeader and UnitIsGroupLeader(unit))
		or WhoaUF:IsAccessibleTrue(UnitIsPartyLeader and UnitIsPartyLeader(unit))
	then
		-- Retail stock swaps the crown for the guide in Group Finder groups;
		-- Classic stock never shows its GuideIcon.
		local useGuide = guide
			and WhoaUF.IsMainline and WhoaUF:IsMainline()
			and WhoaUF:IsAccessibleTrue(HasLFGRestrictions and HasLFGRestrictions())
		if useGuide then
			guide:SetTexture(GetPartyRoleIconTexture())
			guide:Show()
			icon:Hide()
		else
			icon:Show()
			if guide then
				guide:Hide()
			end
		end
	else
		icon:Hide()
		if guide then
			guide:Hide()
		end
	end
end

local function UpdatePartyPvP(frame)
	local unit = GetPartyUnit(frame)
	local icon = frame.PvPIcon
	if not icon then
		return
	end

	local ffa = WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("pvpFFA")
		or "Interface\\TargetingFrame\\UI-PVP-FFA"
	local alliance = WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("pvpAlliance")
	local horde = WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("pvpHorde")

	-- Prefer Whoa Media PvP sheets when flags are readable.
	local factionGroup = UnitFactionGroup(unit)
	local factionOk = factionGroup ~= nil and WhoaUF:CanAccessValue(factionGroup)
	local ffaFlag = UnitIsPVPFreeForAll and UnitIsPVPFreeForAll(unit)
	local pvpFlag = UnitIsPVP and UnitIsPVP(unit)
	if WhoaUF:CanAccessValue(ffaFlag) and WhoaUF:CanAccessValue(pvpFlag) and (factionOk or WhoaUF:IsAccessibleTrue(ffaFlag)) then
		if WhoaUF:IsAccessibleTrue(ffaFlag) then
			icon:SetTexture(ffa)
			icon:SetTexCoord(0, 1, 0, 1)
			icon:Show()
			return
		elseif factionOk
			and factionGroup ~= "Neutral"
			and WhoaUF:IsAccessibleTrue(pvpFlag)
		then
			local path
			if WhoaUF.GetFrameStyle and WhoaUF:GetFrameStyle() ~= "classic" then
				path = (factionGroup == "Alliance") and alliance
					or (factionGroup == "Horde") and horde
			end
			icon:SetTexture(path or ("Interface\\GroupFrame\\UI-Group-PVP-" .. factionGroup))
			icon:SetTexCoord(0, 1, 0, 1)
			icon:Show()
			return
		else
			icon:Hide()
			return
		end
	end

	if WhoaUF.TryUpdateUnitPvPIndicator
		and WhoaUF:TryUpdateUnitPvPIndicator(icon, unit, false, ffa, alliance, horde)
	then
		return
	end
	icon:Hide()
end

local function UpdatePartyOnline(frame)
	local unit = GetPartyUnit(frame)
	local connected = UnitIsConnected(unit)
	-- Secret connected flag: keep online chrome (do not treat as offline).
	local provenOffline = WhoaUF:CanAccessValue(connected) and not connected
	if not provenOffline then
		frame.Disconnect:Hide()
		frame.Health:SetAlpha(1)
		if frame.Power then
			frame.Power:SetAlpha(1)
		end
	else
		frame.Disconnect:Show()
		frame.Portrait:SetVertexColor(0.5, 0.5, 0.5)
		frame.Health:SetAlpha(0.5)
		if frame.Power then
			frame.Power:SetAlpha(0.5)
		end
		if frame.PetFrame then
			SetPartyPetShown(frame.PetFrame, false)
		end
	end
end

function WhoaUF:PartyMemberOnUpdate(frame, elapsed)
	UpdatePartyMemberHealthPulse(frame, elapsed)
	UpdatePartyDispellableStatus(frame, elapsed)
	if not PartyMemberNeedsPulse(frame) then
		SyncPartyMemberPulse(frame)
	end
end

function WhoaUF:ResumePartyMemberOnUpdate(frame)
	if frame and frame.kind == "party" then
		SyncPartyMemberPulse(frame)
	end
end

function WhoaUF:UpdatePartyMemberFrame(frame)
	if not frame or not frame:IsShown() then
		return
	end
	local unit = frame.unit
	local force = self.db and self.db.forceShowPartyFrames
	if self.AreEditModePartyFramesForcedShown and self:AreEditModePartyFramesForcedShown() then
		force = true
	end
	if not UnitExists(unit) and not force then
		return
	end

	if UnitExists(unit) then
		frame.Name:SetText(UnitName(unit) or "")
		if WhoaUF._UF and WhoaUF._UF.UpdatePortrait then
			WhoaUF._UF.UpdatePortrait(frame, unit)
		else
			SetPortraitTexture(frame.Portrait, unit)
		end
		UpdatePartyHealth(frame)
		UpdatePartyPower(frame)
		UpdatePartyLeader(frame)
		UpdatePartyMasterLooter(frame)
		UpdatePartyRoleIcon(frame)
		UpdatePartyPvP(frame)
		UpdatePartyOnline(frame)
		UpdatePartyNotPresent(frame)
		UpdatePartyReadyCheck(frame)
		UpdatePartyAuras(frame)
	else
		-- Dev force-show empty slot: name + full bars with status numbers (not offline chrome).
		frame.Name:SetText("Party " .. (frame.partyIndex or ""))
		if frame.Portrait then
			frame.Portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
		end
		if frame:GetAlpha() ~= 1 then
			frame:SetAlpha(1)
		end
		PaintPartyForceShowBars(frame)
		if frame.LeaderIcon then
			frame.LeaderIcon:Hide()
		end
		if frame.GuideIcon then
			frame.GuideIcon:Hide()
		end
		if frame.MasterIcon then
			frame.MasterIcon:Hide()
		end
		if frame.RoleIcon then
			frame.RoleIcon:Hide()
		end
		if frame.PvPIcon then
			frame.PvPIcon:Hide()
		end
		if frame.NotPresentIcon then
			frame.NotPresentIcon:Hide()
		end
		if frame.ReadyCheck then
			frame.ReadyCheck:Hide()
		end
		HidePartyAuras(frame)
	end
	UpdatePartyPet(frame)
	if self.UpdateFrameThreat then
		self:UpdateFrameThreat(frame)
	end
	SyncPartyMemberPulse(frame)
end

function WhoaUF:UpdateAllPartyFrames()
	for i = 1, MAX_PARTY_MEMBERS do
		local frame = partyFrames[i]
		if frame then
			self:UpdatePartyMemberFrame(frame)
		end
	end
	self:UpdatePartyMemberBackground()
end

function WhoaUF:UpdatePartyMemberBackground()
	if not partyContainer or not partyContainer.Background then
		return
	end
	local bg = partyContainer.Background
	local showParty = partyContainer:IsShown()
	local showBg
	if self.ShouldShowEditModePartyFrameBackground then
		showBg = self:ShouldShowEditModePartyFrameBackground()
	elseif not (self.IsMainline and self:IsMainline()) then
		showBg = EditModeManagerFrame
			and EditModeManagerFrame.ShouldShowPartyFrameBackground
			and EditModeManagerFrame:ShouldShowPartyFrameBackground()
	end
	if not showParty or not showBg then
		bg:Hide()
		return
	end

	local force = self.db and self.db.forceShowPartyFrames
	if self.AreEditModePartyFramesForcedShown and self:AreEditModePartyFramesForcedShown() then
		force = true
	end
	local numMembers = force and MAX_PARTY_MEMBERS or (GetNumSubgroupMembers() or 0)
	if numMembers <= 0 then
		bg:Hide()
		return
	end

	local lastFrame = partyFrames[numMembers]
	if not lastFrame then
		bg:Hide()
		return
	end

	bg:ClearAllPoints()
	bg:SetPoint("TOPLEFT", partyContainer, "TOPLEFT", -5, 6)
	local pet = lastFrame.PetFrame
	if pet and pet:IsShown() then
		bg:SetPoint("BOTTOMLEFT", lastFrame, "BOTTOMLEFT", -5, -21)
	else
		bg:SetPoint("BOTTOMLEFT", lastFrame, "BOTTOMLEFT", -5, -5)
	end
	bg:Show()
end

function WhoaUF:LayoutPartyFrames()
	if not partyContainer then
		return
	end
	if InCombatLockdown() then
		pendingPartyLayout = true
		return
	end
	pendingPartyLayout = nil

	local force = self.db and self.db.forceShowPartyFrames
	if self.AreEditModePartyFramesForcedShown and self:AreEditModePartyFramesForcedShown() then
		force = true
	end
	-- Raid-style suppresses classic Whoa party even when Edit Mode force-shows party.
	-- EditMode_Classic.lua owns UseRaidStylePartyFrames fallback; Party must not call it.
	local raidStyle = false
	if self.IsRaidStylePartyFramesEnabled then
		raidStyle = self:IsRaidStylePartyFramesEnabled()
	end
	local show = self.db and self.db.enabled and not raidStyle and (force or ShouldShowWhoaPartyFrames())
	partyContainer:SetShown(show)
	if not show then
		for i = 1, MAX_PARTY_MEMBERS do
			local frame = partyFrames[i]
			if frame then
				UnregisterUnitWatch(frame)
				frame:Hide()
				SyncPartyMemberPulse(frame)
			end
		end
		if WhoaUF.HidePartyBuffTooltip then
			WhoaUF:HidePartyBuffTooltip()
		end
		if partyContainer.Background then
			partyContainer.Background:Hide()
		end
		-- Party container hidden: RequestIdleCollect after last slot freed.
		if lastPartyMemberCount > 0 and self.RequestIdleCollect then
			self:RequestIdleCollect()
		end
		lastPartyMemberCount = 0
		return
	end

	local memberCount = GetNumSubgroupMembers() or 0
	local spacing = GetPartySpacing()
	for i = 1, MAX_PARTY_MEMBERS do
		local frame = partyFrames[i]
		if frame then
			if i > 1 then
				frame:ClearAllPoints()
				frame:SetPoint("TOPLEFT", partyFrames[i - 1], "BOTTOMLEFT", 0, -spacing)
			end
			if force then
				-- UnitWatch would hide empty partyN slots; force preview shows chrome.
				UnregisterUnitWatch(frame)
				frame:Show()
				if not UnitExists(frame.unit) then
					frame.Name:SetText("Party " .. i)
					if frame.Portrait then
						frame.Portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
					end
				end
			else
				RegisterUnitWatch(frame)
			end
		end
	end
	self:UpdateAllPartyFrames()
	-- Member left while party still shown: RequestIdleCollect.
	if memberCount < lastPartyMemberCount and self.RequestIdleCollect then
		self:RequestIdleCollect()
	end
	lastPartyMemberCount = memberCount
end

local function CreatePartyPetVisual(parent, index)
	local unit = "partypet" .. index
	local pet = CreateFrame("Button", parent:GetName() .. "Pet", parent, "SecureUnitButtonTemplate")
	pet:SetSize(64, 26)
	pet:SetFrameStrata("LOW")
	pet:SetPoint("TOPLEFT", 23, -43)
	pet.unit = unit
	pet.kind = "partypet"
	pet.partyIndex = index
	pet:SetHitRectInsets(3, 33, 3, 3)
	SecureUnitButton_OnLoad(pet, unit)
	pet:SetAttribute("*type2", "togglemenu")
	pet:SetAttribute("menu-function", nil)

	local flash = pet:CreateTexture(nil, "BACKGROUND")
	flash:SetSize(64, 32)
	flash:SetPoint("TOPLEFT", -1, 1)
	-- Party-pet always uses client flash (whoa/thick shared flash is member-only).
	flash:SetTexture(
		(WhoaUF.GetPartyPetFlashTexture and WhoaUF:GetPartyPetFlashTexture())
			or "Interface\\TargetingFrame\\UI-PartyFrame-Flash"
	)
	flash:Hide()
	pet.Flash = flash

	local portrait = pet:CreateTexture(nil, "BACKGROUND")
	portrait:SetSize(18, 18)
	portrait:SetPoint("TOPLEFT", 3, -3)
	pet.Portrait = portrait

	local texture = pet:CreateTexture(nil, "ARTWORK")
	texture:SetSize(64, 32)
	texture:SetPoint("TOPLEFT", 0, -1)
	-- Same classic UI-PartyFrame sheet for every style (party-pet is too small for whoa chrome).
	texture:SetTexture(
		(WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("partyPet"))
			or "Interface\\TargetingFrame\\UI-PartyFrame"
	)
	pet.FrameTexture = texture

	local health = WhoaUF:CreateTextStatusBar(pet)
	health:SetSize(35, 4)
	health:SetPoint("TOPLEFT", 23, -6)
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	health.unit = unit
	health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	pet.Health = health
	if WhoaUF.ApplyFrameStatusBars then
		WhoaUF:ApplyFrameStatusBars(pet)
	else
		health:SetStatusBarColor(0, 1, 0)
	end

	pet.whoaAuras = {}
	for i = 1, MAX_PARTY_AURAS do
		pet.whoaAuras[i] = CreatePartyAuraButton(pet, i)
	end

	pet:Hide()
	return pet
end

local function CreatePartyMemberVisual(parent, index)
	local unit = "party" .. index
	local frame = CreateFrame("Button", "WhoaUFPartyMemberFrame" .. index, parent, "SecureUnitButtonTemplate")
	frame:SetSize(128, 53)
	frame:SetFrameStrata("LOW")
	frame.unit = unit
	frame.kind = "party"
	frame.partyIndex = index
	frame.debuffCountdown = 0
	frame.statusCounter = 0
	frame.statusSign = -1
	frame.unitHPPercent = 1
	frame:SetHitRectInsets(7, 85, 6, 7)

	-- togglemenu: addon UnitPopup_OpenMenu taints protected menu clicks.
	SecureUnitButton_OnLoad(frame, unit)
	frame:SetAttribute("*type2", "togglemenu")
	frame:SetAttribute("menu-function", nil)
	frame:SetScript("OnEnter", function(self)
		if UnitFrame_OnEnter then
			UnitFrame_OnEnter(self)
		end
		WhoaUF:ShowPartyBuffTooltip(self)
	end)
	frame:SetScript("OnLeave", function(self)
		if UnitFrame_OnLeave then
			UnitFrame_OnLeave(self)
		end
		WhoaUF:HidePartyBuffTooltip()
	end)

	-- Pulse on a plain child Frame — never SetScript OnUpdate on SecureUnitButton.
	-- Armed only while low-HP throb or dispellable status countdown is active.
	local memberPulse = CreateFrame("Frame", nil, frame)
	memberPulse.OnUpdate = function(_, elapsed)
		WhoaUF:PartyMemberOnUpdate(frame, elapsed)
	end
	frame.memberPulse = memberPulse

	local flash = frame:CreateTexture(nil, "BACKGROUND")
	flash:SetSize(128, 64)
	flash:SetPoint("TOPLEFT", -3, 2)
	flash:SetTexture(
		(WhoaUF.GetPartyFlashTexture and WhoaUF:GetPartyFlashTexture())
			or "Interface\\TargetingFrame\\UI-PartyFrame-Flash"
	)
	flash:Hide()
	frame.Flash = flash

	local portrait = frame:CreateTexture(nil, "BACKGROUND")
	portrait:SetSize(37, 37)
	portrait:SetPoint("TOPLEFT", 7, -6)
	frame.Portrait = portrait

	local background = frame:CreateTexture(nil, "BACKGROUND")
	background:SetSize(72, 20)
	background:SetPoint("TOPLEFT", 45, -11)
	background:SetColorTexture(0, 0, 0, 0.5)
	frame.Background = background

	-- Overlay (+3): chrome/icons/auras above StatusBars (+1). Party sheets use
	-- alpha holes so the rim frames HP/power (see ApplyPartyChromeLayering).
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(frame:GetFrameLevel() + 3)
	frame.AuraHost = overlay
	frame.Overlay = overlay

	local texture = overlay:CreateTexture(nil, "BORDER", nil, 0)
	texture:SetSize(128, 64)
	texture:SetPoint("TOPLEFT", 0, -2)
	texture:SetTexture(
		(WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("party"))
			or "Interface\\TargetingFrame\\UI-PartyFrame"
	)
	frame.FrameTexture = texture

	local status = overlay:CreateTexture(nil, "ARTWORK")
	status:SetSize(36, 36)
	status:SetPoint("CENTER", portrait, "CENTER")
	status:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
	status:SetTexCoord(0, 0.2734375, 0, 0.5625)
	status:Hide()
	frame.Status = status

	-- Name above Overlay chrome (same +8 host as player).
	local nameHost = CreateFrame("Frame", nil, frame)
	nameHost:SetAllPoints(frame)
	nameHost:SetFrameLevel(frame:GetFrameLevel() + 8)
	frame.NameHost = nameHost

	local nameText = nameHost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameText:SetJustifyH("LEFT")
	nameText:SetPoint("BOTTOMLEFT", 50, 43)
	frame.Name = nameText

	local leaderIcon = overlay:CreateTexture(nil, "OVERLAY")
	leaderIcon:SetSize(16, 16)
	leaderIcon:SetPoint("TOPLEFT")
	leaderIcon:SetTexture(
		(WhoaUF.GetLeaderIconTexture and WhoaUF:GetLeaderIconTexture())
			or "Interface\\GroupFrame\\UI-Group-LeaderIcon"
	)
	leaderIcon:Hide()
	frame.LeaderIcon = leaderIcon

	local guideIcon = overlay:CreateTexture(nil, "OVERLAY")
	guideIcon:SetSize(19, 19)
	guideIcon:SetPoint("TOPLEFT")
	guideIcon:SetTexture(GetPartyRoleIconTexture())
	guideIcon:SetTexCoord(GUIDE_ICON_COORDS[1], GUIDE_ICON_COORDS[2], GUIDE_ICON_COORDS[3], GUIDE_ICON_COORDS[4])
	guideIcon:Hide()
	frame.GuideIcon = guideIcon

	local masterIcon = overlay:CreateTexture(nil, "OVERLAY")
	masterIcon:SetSize(16, 16)
	masterIcon:SetPoint("TOPLEFT", 32, 0)
	masterIcon:SetTexture(
		(WhoaUF.GetMasterLooterIconTexture and WhoaUF:GetMasterLooterIconTexture())
			or "Interface\\GroupFrame\\UI-Group-MasterLooter"
	)
	masterIcon:Hide()
	frame.MasterIcon = masterIcon

	local roleIcon = overlay:CreateTexture(nil, "OVERLAY")
	roleIcon:SetSize(19, 19)
	roleIcon:SetPoint("TOPLEFT")
	roleIcon:Hide()
	frame.RoleIcon = roleIcon

	local pvpIcon = overlay:CreateTexture(nil, "OVERLAY")
	pvpIcon:SetSize(32, 32)
	pvpIcon:SetPoint("TOPLEFT", -9, -15)
	pvpIcon:Hide()
	frame.PvPIcon = pvpIcon

	local disconnect = overlay:CreateTexture(nil, "OVERLAY")
	disconnect:SetSize(64, 64)
	disconnect:SetPoint("LEFT", -7, -1)
	disconnect:SetTexture("Interface\\CharacterFrame\\Disconnect-Icon")
	disconnect:Hide()
	frame.Disconnect = disconnect

	local readyCheck
	local ok, rc = pcall(CreateFrame, "Frame", nil, frame, "ReadyCheckStatusTemplate")
	if ok and rc then
		readyCheck = rc
	else
		readyCheck = CreateFrame("Frame", nil, frame)
		readyCheck.Texture = readyCheck:CreateTexture(nil, "OVERLAY")
		readyCheck.Texture:SetAllPoints()
		readyCheck.Texture:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
	end
	readyCheck:SetSize(32, 32)
	readyCheck:SetPoint("CENTER", portrait, "CENTER")
	readyCheck:Hide()
	frame.ReadyCheck = readyCheck

	local notPresent = CreateFrame("Frame", nil, frame)
	notPresent:SetSize(25, 25)
	notPresent:SetPoint("LEFT", frame, "RIGHT", -7, 5)
	notPresent:Hide()
	notPresent.texture = notPresent:CreateTexture(nil, "ARTWORK")
	notPresent.texture:SetAllPoints()
	notPresent.Border = notPresent:CreateTexture(nil, "OVERLAY")
	notPresent.Border:SetAllPoints()
	notPresent.Border:SetTexture("Interface\\Common\\RingBorder")
	notPresent:SetScript("OnEnter", function(self)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	notPresent:SetScript("OnLeave", GameTooltip_Hide)
	frame.NotPresentIcon = notPresent

	local partyBars = WhoaUF.GetFrameBarLayout and WhoaUF:GetFrameBarLayout("party")
	local healthGeom = partyBars and partyBars.health
	local powerGeom = partyBars and partyBars.power
	local health = WhoaUF:CreateTextStatusBar(frame)
	health:SetSize(healthGeom and healthGeom.width or 70, healthGeom and healthGeom.height or 8)
	health:SetPoint(
		healthGeom and healthGeom.point or "TOPLEFT",
		healthGeom and healthGeom.x or 47,
		healthGeom and healthGeom.y or -12
	)
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	health.unit = unit
	-- Below Overlay (+3) chrome so bar fills sit behind the rim.
	health:SetFrameLevel(frame:GetFrameLevel() + 1)
	SetupPartyStatusBar(health, overlay, 82, -16, 47, 117)
	frame.Health = health
	if WhoaUF._UF.ArmFrequentHealthBar then
		WhoaUF._UF.ArmFrequentHealthBar(health, frame)
	end

	local power = WhoaUF:CreateTextStatusBar(frame)
	power:SetSize(powerGeom and powerGeom.width or 70, powerGeom and powerGeom.height or 8)
	power:SetPoint(
		powerGeom and powerGeom.point or "TOPLEFT",
		powerGeom and powerGeom.x or 47,
		powerGeom and powerGeom.y or -21
	)
	power:SetMinMaxValues(0, 1)
	power:SetValue(1)
	power.unit = unit
	power:SetFrameLevel(frame:GetFrameLevel() + 1)
	SetupPartyStatusBar(power, overlay, 82, -25, 47, 117)
	frame.Power = power
	if WhoaUF._UF.ArmFrequentPowerBar then
		WhoaUF._UF.ArmFrequentPowerBar(power, frame)
	end

	-- Texture + Colors options (class / hostility) — same path as player/target.
	if WhoaUF.ApplyFrameStatusBars then
		WhoaUF:ApplyFrameStatusBars(frame)
	else
		local hp = WhoaUF.ReactionColors and WhoaUF.ReactionColors.default
		local mana = WhoaUF:GetPowerBarColor("MANA")
		health:SetStatusBarColor(hp and hp.r or 0, hp and hp.g or 1, hp and hp.b or 0)
		power:SetStatusBarColor(mana.r, mana.g, mana.b)
	end

	frame.whoaAuras = {}
	for i = 1, MAX_PARTY_AURAS do
		frame.whoaAuras[i] = CreatePartyAuraButton(frame, i)
	end

	frame.PetFrame = CreatePartyPetVisual(frame, index)

	if WhoaUF.ApplyPartyChromeLayering then
		WhoaUF:ApplyPartyChromeLayering(frame)
	end

	if index == 1 then
		frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	else
		frame:SetPoint("TOPLEFT", partyFrames[index - 1], "BOTTOMLEFT", 0, -GetPartySpacing())
	end

	frame:Hide()
	return frame
end

local function UpdatePartyContainerSize()
	if not partyContainer then
		return
	end
	if InCombatLockdown() then
		-- Edit Mode registration can protect WhoaUFPartyFrame; SetSize is blocked in combat.
		pendingPartyLayout = true
		return
	end
	local spacing = GetPartySpacing()
	local memberPitch = 53 + spacing
	partyContainer:SetSize(128, (memberPitch * MAX_PARTY_MEMBERS) - spacing)
end

function WhoaUF:InitPartyFrames()
	if partyContainer then
		return
	end

	partyContainer = CreateFrame("Frame", "WhoaUFPartyFrame", UIParent)
	UpdatePartyContainerSize()
	partyContainer:SetFrameStrata("LOW")
	partyContainer:SetToplevel(true)

	-- Match PartyFrame.xml default; SyncUnitFramePositions / Edit Mode may override.
	partyContainer:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -160)

	-- Classic party rim; visibility follows EditMode_Classic.lua ShowPartyFrameBackground.
	-- Ref: Blizzard_UnitFrame/Shared/PartyFrame.xml PartyFrame.Background
	local bgTemplate = BackdropTemplate and "BackdropTemplate" or nil
	local background = CreateFrame("Frame", nil, partyContainer, bgTemplate)
	background:SetSize(144, 10)
	background:SetPoint("TOPLEFT", -5, 6)
	background:Hide()
	if background.SetBackdrop and BACKDROP_PARTY_32_32 then
		background:SetBackdrop(BACKDROP_PARTY_32_32)
	end
	partyContainer.Background = background

	for i = 1, MAX_PARTY_MEMBERS do
		partyFrames[i] = CreatePartyMemberVisual(partyContainer, i)
		if self.unitFrames then
			self.unitFrames["party" .. i] = partyFrames[i]
		end
	end

	local watcher = CreateFrame("Frame")
	local watcherPets = CreateFrame("Frame")
	local function RegisterPartyWatcherEvents(w, wPets)
		wPets = wPets or WhoaUF.partyWatcherPets
		w:RegisterEvent("PLAYER_ENTERING_WORLD")
		w:RegisterEvent("PLAYER_REGEN_ENABLED")
		w:RegisterEvent("GROUP_ROSTER_UPDATE")
		w:RegisterEvent("PARTY_LEADER_CHANGED")
		w:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
		w:RegisterEvent("READY_CHECK")
		w:RegisterEvent("READY_CHECK_CONFIRM")
		w:RegisterEvent("READY_CHECK_FINISHED")
		w:RegisterEvent("PARTY_MEMBER_ENABLE")
		w:RegisterEvent("PARTY_MEMBER_DISABLE")
		w:RegisterEvent("UNIT_FLAGS")
		w:RegisterEvent("UNIT_OTHER_PARTY_CHANGED")
		w:RegisterEvent("CVAR_UPDATE")
		-- RegisterUnitEvent accepts at most 4 units; pets need a second watcher.
		local function RegisterPartyUnitEvent(event)
			w:RegisterUnitEvent(event, "party1", "party2", "party3", "party4")
			if wPets then
				wPets:RegisterUnitEvent(event, "partypet1", "partypet2", "partypet3", "partypet4")
			end
		end
		RegisterPartyUnitEvent("UNIT_HEALTH")
		pcall(function()
			RegisterPartyUnitEvent("UNIT_HEALTH_FREQUENT")
		end)
		RegisterPartyUnitEvent("UNIT_MAXHEALTH")
		RegisterPartyUnitEvent("UNIT_POWER_UPDATE")
		pcall(function()
			RegisterPartyUnitEvent("UNIT_POWER_FREQUENT")
		end)
		RegisterPartyUnitEvent("UNIT_MAXPOWER")
		RegisterPartyUnitEvent("UNIT_DISPLAYPOWER")
		RegisterPartyUnitEvent("UNIT_PORTRAIT_UPDATE")
		RegisterPartyUnitEvent("UNIT_NAME_UPDATE")
		RegisterPartyUnitEvent("UNIT_FACTION")
		RegisterPartyUnitEvent("UNIT_CONNECTION")
		RegisterPartyUnitEvent("UNIT_AURA")
		RegisterPartyUnitEvent("UNIT_PET")
		pcall(function()
			w:RegisterUnitEvent("UNIT_PHASE", "party1", "party2", "party3", "party4")
		end)
		-- Heal prediction is Classic-only (Frames/HealPrediction_Classic.lua); members only, like stock.
		if WhoaUF.UpdateHealPrediction then
			pcall(function()
				w:RegisterUnitEvent("UNIT_HEAL_PREDICTION", "party1", "party2", "party3", "party4")
			end)
			pcall(function()
				w:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "party1", "party2", "party3", "party4")
			end)
			pcall(function()
				w:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "party1", "party2", "party3", "party4")
			end)
		end
		pcall(function()
			w:RegisterEvent("PLAYER_ROLES_ASSIGNED")
		end)
	end
	self.RegisterPartyWatcherEvents = RegisterPartyWatcherEvents
	RegisterPartyWatcherEvents(watcher, watcherPets)
	self.partyWatcher = watcher
	self.partyWatcherPets = watcherPets

	local function PartyFrameForUnit(u)
		if type(u) ~= "string" then
			return nil, nil
		end
		local index = tonumber(u:match("^party(%d)$"))
		if index then
			return partyFrames[index], false
		end
		index = tonumber(u:match("^partypet(%d)$"))
		if index then
			local frame = partyFrames[index]
			return frame and frame.PetFrame, true
		end
		return nil, nil
	end

	local function ForEachShownPartyFrame(fn)
		for i = 1, MAX_PARTY_MEMBERS do
			local frame = partyFrames[i]
			if frame and frame:IsShown() then
				fn(frame)
			end
		end
	end

	local function FlushPendingPartyCombatWork()
		if pendingPartyLayout then
			UpdatePartyContainerSize()
			WhoaUF:LayoutPartyFrames()
		end
		if pendingPartyPetUpdate then
			pendingPartyPetUpdate = nil
			for i = 1, MAX_PARTY_MEMBERS do
				local frame = partyFrames[i]
				if frame and frame:IsShown() then
					UpdatePartyPet(frame)
				end
			end
		end
	end

	watcher:SetScript("OnEvent", function(_, event, unit)
		if event == "PLAYER_REGEN_ENABLED" then
			FlushPendingPartyCombatWork()
			return
		end
		if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
			UpdatePartyContainerSize()
			WhoaUF:LayoutPartyFrames()
			return
		end
		if event == "CVAR_UPDATE" then
			if unit == "statusText" or unit == "statusTextDisplay" then
				WhoaUF:UpdateAllPartyFrames()
			elseif unit == "showPartyPets" then
				UpdatePartyContainerSize()
				WhoaUF:LayoutPartyFrames()
			end
			return
		end
		if event == "PARTY_LEADER_CHANGED" then
			ForEachShownPartyFrame(function(frame)
				UpdatePartyLeader(frame)
				UpdatePartyRoleIcon(frame)
			end)
			return
		end
		if event == "PARTY_LOOT_METHOD_CHANGED" then
			ForEachShownPartyFrame(UpdatePartyMasterLooter)
			return
		end
		if event == "PLAYER_ROLES_ASSIGNED" then
			ForEachShownPartyFrame(UpdatePartyRoleIcon)
			return
		end
		if event == "READY_CHECK" or event == "READY_CHECK_CONFIRM" then
			ForEachShownPartyFrame(UpdatePartyReadyCheck)
			return
		end
		if event == "READY_CHECK_FINISHED" then
			local finishTime = DEFAULT_READY_CHECK_STAY_TIME or 0
			for i = 1, MAX_PARTY_MEMBERS do
				local frame = partyFrames[i]
				if frame and frame.ReadyCheck and UnitExists(frame.unit) and ReadyCheck_Finish then
					ReadyCheck_Finish(frame.ReadyCheck, finishTime)
				end
			end
			return
		end
		if event == "PARTY_MEMBER_ENABLE" or event == "PARTY_MEMBER_DISABLE" then
			ForEachShownPartyFrame(function(frame)
				UpdatePartyOnline(frame)
				UpdatePartyNotPresent(frame)
			end)
			return
		end
		if event == "UNIT_FLAGS" or event == "UNIT_OTHER_PARTY_CHANGED" or event == "UNIT_PHASE" then
			local index = type(unit) == "string" and tonumber(unit:match("^party(%d)$"))
			local frame = index and partyFrames[index]
			if frame then
				UpdatePartyNotPresent(frame)
			end
			return
		end
		if event == "UNIT_PET" then
			local index = type(unit) == "string" and tonumber(unit:match("^party(%d)$"))
			local frame = index and partyFrames[index]
			if frame then
				UpdatePartyPet(frame)
			end
			return
		end
		if event == "UNIT_AURA" then
			local auraFrame = PartyFrameForUnit(unit)
			if auraFrame and auraFrame:IsShown() then
				UpdatePartyAuras(auraFrame)
			end
			return
		end
		if event == "UNIT_HEALTH"
			or event == "UNIT_HEALTH_FREQUENT"
			or event == "UNIT_MAXHEALTH"
		then
			local target, isPet = PartyFrameForUnit(unit)
			if not target or not target:IsShown() then
				return
			end
			if isPet then
				UpdatePartyPetHealth(target)
			else
				UpdatePartyHealth(target)
			end
			return
		end
		if event == "UNIT_HEAL_PREDICTION"
			or event == "UNIT_ABSORB_AMOUNT_CHANGED"
			or event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
		then
			local target, isPet = PartyFrameForUnit(unit)
			if target and not isPet and target:IsShown() and WhoaUF.UpdateHealPrediction then
				WhoaUF:UpdateHealPrediction(target)
			end
			return
		end
		if event == "UNIT_POWER_UPDATE"
			or event == "UNIT_POWER_FREQUENT"
			or event == "UNIT_MAXPOWER"
			or event == "UNIT_DISPLAYPOWER"
		then
			local target, isPet = PartyFrameForUnit(unit)
			if target and not isPet and target:IsShown() then
				UpdatePartyPower(target)
			end
			return
		end
		if event == "UNIT_PORTRAIT_UPDATE" then
			local target = PartyFrameForUnit(unit)
			if target and target:IsShown() and target.Portrait then
				if WhoaUF._UF and WhoaUF._UF.UpdatePortrait then
					WhoaUF._UF.UpdatePortrait(target, target.unit)
				else
					SetPortraitTexture(target.Portrait, target.unit)
				end
			end
			return
		end
		if event == "UNIT_NAME_UPDATE" then
			local target, isPet = PartyFrameForUnit(unit)
			if target and not isPet and target:IsShown() and target.Name then
				target.Name:SetText(UnitName(unit) or "")
			end
			return
		end
		if event == "UNIT_FACTION" then
			local target, isPet = PartyFrameForUnit(unit)
			if target and not isPet and target:IsShown() then
				UpdatePartyPvP(target)
			end
			return
		end
		if event == "UNIT_CONNECTION" then
			local target, isPet = PartyFrameForUnit(unit)
			if target and not isPet and target:IsShown() then
				UpdatePartyOnline(target)
				UpdatePartyNotPresent(target)
				UpdatePartyPet(target)
			end
			return
		end
	end)

	watcherPets:SetScript("OnEvent", watcher:GetScript("OnEvent"))

	self.partyFrames = partyFrames
	self.partyContainer = partyContainer
end
