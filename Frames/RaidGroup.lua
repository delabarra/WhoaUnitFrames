--[[
	CompactRaid-style group for DevTools force-show preview (not a live raid replacement).
	Reference: reference/Blizzard_UnitFrame/Shared/CompactRaidGroup.lua,
	           CompactUnitFrame NATIVE 72×36
	Real raids still use stock CompactRaid / CUF until a full Whoa raid surface exists.
]]

local MEMBERS_PER_RAID_GROUP = 5
local MEMBER_W, MEMBER_H = 72, 36
local GROUP_GAP = 2

local UF = WhoaUF._UF
local raidGroup
local memberFrames = {}

local function CreateRaidMember(parent, index)
	local frame = CreateFrame("Button", parent:GetName() .. "Member" .. index, parent, "SecureUnitButtonTemplate")
	frame:SetSize(MEMBER_W, MEMBER_H)
	frame.kind = "raidmember"
	frame.raidIndex = index
	frame.unit = "raid" .. index

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.8)
	frame.Background = bg

	local health = CreateFrame("StatusBar", nil, frame)
	health:SetPoint("TOPLEFT", 1, -1)
	health:SetPoint("BOTTOMRIGHT", -1, 1)
	health:SetMinMaxValues(0, 1)
	health:SetValue(1)
	health:SetStatusBarColor(0, 1, 0)
	local tex = WhoaUF.GetStatusBarTexturePaths and WhoaUF:GetStatusBarTexturePaths()
	health:SetStatusBarTexture(tex or "Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
	frame.Health = health

	local name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	name:SetPoint("TOPLEFT", 4, -2)
	name:SetPoint("TOPRIGHT", -4, -2)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	frame.Name = name

	local status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	status:SetPoint("BOTTOMLEFT", 4, 2)
	status:SetPoint("BOTTOMRIGHT", -4, 2)
	status:SetJustifyH("LEFT")
	frame.Status = status

	local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	if border.SetBackdrop then
		border:SetAllPoints()
		border:SetBackdrop({
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 8,
			insets = { left = 1, right = 1, top = 1, bottom = 1 },
		})
		border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	end
	frame.Border = border

	frame:Hide()
	return frame
end

local function PaintRaidMemberPlaceholder(frame, index)
	frame.Name:SetText("Raid " .. index)
	frame.Status:SetText("")
	if frame.Health then
		frame.Health:SetMinMaxValues(0, 1)
		frame.Health:SetValue(1)
		frame.Health:SetStatusBarColor(0.2, 0.7, 0.2)
	end
end

local function UpdateRaidMember(frame)
	if not frame then
		return
	end
	local unit = frame.unit
	if UnitExists(unit) then
		frame.Name:SetText(UnitName(unit) or ("Raid " .. (frame.raidIndex or "")))
		local max = UnitHealthMax(unit)
		local cur = UnitHealth(unit)
		if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(max) then
			if max <= 0 then
				max = 1
			end
		elseif max == nil then
			max = 1
		end
		frame.Health:SetMinMaxValues(0, max)
		frame.Health:SetValue(cur)
		if WhoaUF.ApplyHealthBarColor then
			WhoaUF:ApplyHealthBarColor(frame.Health, unit)
		end
		if not UnitIsConnected(unit) then
			frame.Status:SetText(PLAYER_OFFLINE or "Offline")
		elseif UnitIsDeadOrGhost(unit) then
			frame.Status:SetText(DEAD or "Dead")
		else
			frame.Status:SetText("")
		end
	else
		PaintRaidMemberPlaceholder(frame, frame.raidIndex or 0)
	end
end

function WhoaUF:UpdateRaidGroupFrames()
	for i = 1, MEMBERS_PER_RAID_GROUP do
		UpdateRaidMember(memberFrames[i])
	end
end

function WhoaUF:LayoutRaidGroupFrames()
	if InCombatLockdown() then
		return
	end
	local show = self.db and self.db.enabled and self:IsForceShowFrame("raidgroup")
	-- Lazy-create the shell only when DevTools force-show raidgroup is enabled.
	if show and not raidGroup then
		self:InitRaidGroupFrames()
	end
	if not raidGroup then
		return
	end
	raidGroup:SetShown(show and true or false)
	if not show then
		for i = 1, MEMBERS_PER_RAID_GROUP do
			local frame = memberFrames[i]
			if frame then
				UnregisterUnitWatch(frame)
				frame:Hide()
			end
		end
		return
	end

	for i = 1, MEMBERS_PER_RAID_GROUP do
		local frame = memberFrames[i]
		if frame then
			UnregisterUnitWatch(frame)
			frame:Show()
			UpdateRaidMember(frame)
			if not UnitExists(frame.unit) then
				PaintRaidMemberPlaceholder(frame, i)
			end
		end
	end
end

function WhoaUF:InitRaidGroupFrames()
	if raidGroup then
		return
	end

	raidGroup = CreateFrame("Frame", "WhoaUFRaidGroup1", UIParent)
	raidGroup:SetSize(MEMBER_W, (MEMBER_H * MEMBERS_PER_RAID_GROUP) + 16)
	raidGroup:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -180)
	raidGroup:SetFrameStrata("LOW")
	raidGroup.kind = "raidgroup"

	local title = raidGroup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 0, 0)
	if GROUP_NUMBER then
		title:SetFormattedText(GROUP_NUMBER, 1)
	else
		title:SetText("Group 1")
	end
	raidGroup.Title = title

	for i = 1, MEMBERS_PER_RAID_GROUP do
		local member = CreateRaidMember(raidGroup, i)
		if i == 1 then
			member:SetPoint("TOPLEFT", raidGroup, "TOPLEFT", 0, -title:GetHeight())
		else
			member:SetPoint("TOPLEFT", memberFrames[i - 1], "BOTTOMLEFT", 0, -GROUP_GAP)
		end
		-- Force-show uses raid1–5 tokens when present; placeholders otherwise.
		member.unit = "raid" .. i
		pcall(function()
			SecureUnitButton_OnLoad(member, member.unit)
			member:SetAttribute("*type2", "togglemenu")
			member:SetAttribute("menu-function", nil)
		end)
		memberFrames[i] = member
		UF.frames["raid" .. i] = member
	end

	UF.frames.raidgroup = raidGroup
	self.raidGroupFrame = raidGroup
	self.raidGroupMembers = memberFrames
	raidGroup:Hide()
end
