--[[
	Warlock soul shard bar on Whoa player frame.
	Reference: reference/Blizzard_UnitFrame/Cata/ShardBar.lua|.xml
	           reference/Blizzard_UnitFrame/Mists/ShardBar.lua|.xml (Affliction shards)
	MoP Demonology / Destruction live in WarlockPower.lua.
]]

do
	if not WhoaUF:HasSoulShards() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "WARLOCK" then
		return
	end
end

local SHARD_BAR_NUM_SHARDS_CATA = 3
local SHARD_BAR_NUM_SHARDS_MAX = 4
local SHARDBAR_SHOW_LEVEL = 10
local TEX_CLIENT = "Interface\\PlayerFrame\\UI-WarlockShard"

local function GetShardTex()
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(TEX_CLIENT)
	end
	return TEX_CLIENT
end

local function IsMists()
	-- 4-shard Affliction layout on MoP Classic and Mainline.
	return WhoaUF:HasMoPArt()
end

local function IsCataOrLater()
	return WhoaUF:HasSoulShards()
end

local function GetSoulShardType()
	return (Enum and Enum.PowerType and Enum.PowerType.SoulShards) or 7
end

local function GetPowerUnit()
	local player = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	return (player and player.unit) or "player"
end

local function IsWarlock()
	local _, class = UnitClass("player")
	return class == "WARLOCK"
end

function WhoaUF:GetShardBarAnchor()
	-- Managed container: PlayerFrame BOTTOM (10, 36), width 160, ShardBar leftPadding 44, topPadding 6.
	-- Effective TOPLEFT ≈ BOTTOMLEFT (containerLeft+44, 30). See Cata/Mists ShardBar.xml.
	return 44, 30
end

-- Match PlayerFrameBottomManagedFramesContainer + ShardBar leftPadding/topPadding.
function WhoaUF:AnchorShardBar(stackAbove, spacing)
	local player = self.unitFrames and self.unitFrames.player
	local anchorFrame = self:GetClassPowerAnchorFrame() or player
	local frame = player and player.ShardBar
	if not frame or not anchorFrame then
		return
	end

	local containerX = 10
	local containerY = 36
	local containerWidth = 160
	local leftPadding = 44
	local topPadding = 6
	local playerWidth = anchorFrame:GetWidth() or 232
	local containerLeft = (playerWidth * 0.5) + containerX - (containerWidth * 0.5)
	local x = containerLeft + leftPadding
	local y = containerY - topPadding

	frame:ClearAllPoints()
	if stackAbove then
		frame:SetPoint("LEFT", anchorFrame, "BOTTOMLEFT", x, 0)
		frame:SetPoint("TOP", stackAbove, "BOTTOM", 0, -(spacing or 2))
	else
		frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", x, y)
	end
	self:ApplyClassPowerFrameLevel(frame)
end

local function CreateShard(parent, index)
	-- Named frames required: ClassPower.xml Alpha/Rotation targets `$parent*`.
	local shard = CreateFrame("Frame", "WhoaUFShardBarShard" .. (index or 1), parent, "WhoaUFShardTemplate")
	shard.active = false
	if WhoaUF.ApplyClassPowerSheetToRegions then
		WhoaUF:ApplyClassPowerSheetToRegions(shard, TEX_CLIENT)
	end
	return shard
end

local function SetShard(shard, active, instant)
	if active then
		if shard.animOut:IsPlaying() then
			shard.animOut:Stop()
		end
		if instant then
			shard.animIn:Stop()
			shard.shardFill:Show()
			shard.shardFill:SetAlpha(1)
			shard.shardGlow:SetAlpha(0)
			shard.active = true
		elseif not shard.active and not shard.animIn:IsPlaying() then
			if shard.animIn.Restart then
				shard.animIn:Restart()
			else
				shard.animIn:Play()
			end
			shard.active = true
		end
	else
		if shard.animIn:IsPlaying() then
			shard.animIn:Stop()
		end
		if instant then
			shard.animOut:Stop()
			shard.shardFill:Hide()
			shard.shardGlow:SetAlpha(0)
			shard.shardSmokeA:SetAlpha(0)
			shard.shardSmokeB:SetAlpha(0)
			shard.active = false
		elseif shard.active and not shard.animOut:IsPlaying() then
			if shard.animOut.Restart then
				shard.animOut:Restart()
			else
				shard.animOut:Play()
			end
			shard.active = false
		end
	end
end

local function GetMaxShards(unit)
	local powerType = GetSoulShardType()
	local maxShards = UnitPowerMax and UnitPowerMax(unit, powerType) or SHARD_BAR_NUM_SHARDS_CATA
	if not maxShards or maxShards < 1 then
		return 0
	end
	return math.min(maxShards, SHARD_BAR_NUM_SHARDS_MAX)
end

local function UpdateShardBar(self, instant)
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("WARLOCK") then
		local previewCount = IsMists() and SHARD_BAR_NUM_SHARDS_MAX or SHARD_BAR_NUM_SHARDS_CATA
		for i = 1, SHARD_BAR_NUM_SHARDS_MAX do
			local shard = self.shards[i]
			if shard then
				if i <= previewCount then
					shard:Show()
					SetShard(shard, true, true)
				else
					SetShard(shard, false, true)
					shard:Hide()
				end
			end
		end
		local step = self.shardStep or 35
		self:SetWidth(math.max(52 + (previewCount - 1) * step, 110))
		return
	end

	local unit = GetPowerUnit()
	local powerType = GetSoulShardType()
	local numShards = UnitPower(unit, powerType)
	local maxShards = GetMaxShards(unit)
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(numShards, maxShards) then
		return
	end
	numShards = numShards or 0

	for i = 1, SHARD_BAR_NUM_SHARDS_MAX do
		local shard = self.shards[i]
		if shard then
			if i <= maxShards then
				shard:Show()
				SetShard(shard, i <= numShards, instant)
			else
				SetShard(shard, false, true)
				shard:Hide()
			end
		end
	end

	-- Cata: 35px step; MoP: 30px step. Width ≈ first shard + (n-1)*step.
	local step = self.shardStep or 35
	local width = maxShards > 0 and (52 + (maxShards - 1) * step) or 52
	self:SetWidth(math.max(width, 110))
end

local function IsSpellKnownSafe(id)
	if not id then
		return true
	end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		return C_SpellBook.IsSpellKnown(id)
	end
	if IsPlayerSpell then
		return IsPlayerSpell(id)
	end
	if IsSpellKnown then
		return IsSpellKnown(id)
	end
	return true
end

local function ShouldShowShardBar()
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("WARLOCK") then
		-- DevTools force-show on MoP: shards for Cata / Affliction only (Demo uses Fury bar).
		if IsMists() then
			local spec = nil
			if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
				spec = C_SpecializationInfo.GetSpecialization()
			elseif GetSpecialization then
				spec = GetSpecialization()
			end
			local aff = SPEC_WARLOCK_AFFLICTION or 1
			return spec == aff
		end
		return IsCataOrLater()
	end
	if not IsWarlock() or not IsCataOrLater() then
		return false
	end
	-- MoP: only Affliction uses soul shards; Demo/Destro use Whoa WarlockPower bars.
	if IsMists() then
		local spec = nil
		if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
			spec = C_SpecializationInfo.GetSpecialization()
		elseif GetSpecialization then
			spec = GetSpecialization()
		end
		local aff = SPEC_WARLOCK_AFFLICTION or 1
		if spec and spec ~= aff then
			return false
		end
		-- Blizzard Affliction gate: Soulburn known (Mists ShardBar.lua SetUpCurrentPower).
		local soulburn = WARLOCK_SOULBURN or 74434
		if not IsSpellKnownSafe(soulburn) then
			return false
		end
		return GetMaxShards(GetPowerUnit()) > 0
	end
	return true
end

local function RefreshShardBarVisibility(self)
	if not ShouldShowShardBar() then
		self:Hide()
		if WhoaUF.LayoutPlayerBottomFrames then
			WhoaUF:LayoutPlayerBottomFrames()
		end
		return
	end

	local force = WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("WARLOCK")
	if force then
		self:UnregisterEvent("PLAYER_LEVEL_UP")
		self:Show()
		self:SetAlpha(1)
		UpdateShardBar(self, true)
		if WhoaUF.LayoutPlayerBottomFrames then
			WhoaUF:LayoutPlayerBottomFrames()
		end
		return
	end

	-- Blizzard keeps Shown+Alpha(0) below SHARDBAR_SHOW_LEVEL so VerticalLayoutFrame
	-- still reserves a gap. Whoa Hides instead — pet sits flush until level 10, then
	-- showAnim + Layout push pet down (Cata ShardBar.lua PLAYER_LEVEL_UP).
	local level = UnitLevel("player") or 1
	if level < SHARDBAR_SHOW_LEVEL then
		self:Hide()
		self:SetAlpha(0)
		self:RegisterEvent("PLAYER_LEVEL_UP")
		if WhoaUF.LayoutPlayerBottomFrames then
			WhoaUF:LayoutPlayerBottomFrames()
		end
		return
	end

	self:UnregisterEvent("PLAYER_LEVEL_UP")
	self:Show()
	if self:GetAlpha() < 1 and not (self.showAnim and self.showAnim:IsPlaying()) then
		self:SetAlpha(1)
	end
	UpdateShardBar(self, true)
	if WhoaUF.LayoutPlayerBottomFrames then
		WhoaUF:LayoutPlayerBottomFrames()
	end
end

function WhoaUF:RefreshShardBar()
	local frame = self.unitFrames and self.unitFrames.player and self.unitFrames.player.ShardBar
	if frame then
		RefreshShardBarVisibility(frame)
	end
end

function WhoaUF:InitShardBar(playerFrame)
	if not playerFrame or playerFrame.ShardBar then
		return
	end
	if not IsCataOrLater() or not IsWarlock() then
		return
	end

	local mists = IsMists()
	local frame = CreateFrame("Frame", "WhoaUFShardBar", playerFrame)
	frame:SetSize(110, 25)
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(playerFrame:GetFrameLevel() + 5)
	frame:EnableMouse(true)
	frame:SetHitRectInsets(mists and -10 or 0, mists and 9 or 0, 0, 3)
	frame.shardStep = mists and 30 or 35
	frame.shards = {}

	local showAnim = frame:CreateAnimationGroup()
	local showAlpha = showAnim:CreateAnimation("Alpha")
	showAlpha:SetFromAlpha(0)
	showAlpha:SetToAlpha(1)
	showAlpha:SetDuration(0.5)
	showAlpha:SetOrder(1)
	showAnim:SetScript("OnFinished", function(self)
		self:GetParent():SetAlpha(1)
	end)
	frame.showAnim = showAnim

	local prev
	local defaultCount = mists and SHARD_BAR_NUM_SHARDS_MAX or SHARD_BAR_NUM_SHARDS_CATA
	for i = 1, SHARD_BAR_NUM_SHARDS_MAX do
		local shard = CreateShard(frame, i)
		if i == 1 then
			shard:SetPoint("TOPLEFT", mists and -10 or 0, 0)
		else
			shard:SetPoint("TOPLEFT", prev, "TOPLEFT", frame.shardStep, 0)
		end
		frame.shards[i] = shard
		prev = shard
		if i > defaultCount then
			shard:Hide()
		end
	end

	frame:SetScript("OnEnter", function(self)
		if GameTooltip_SetDefaultAnchor then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		GameTooltip:SetText(SOUL_SHARDS_POWER or SOUL_SHARDS or "Soul Shards", 1, 1, 1)
		if SOUL_SHARDS_TOOLTIP then
			GameTooltip:AddLine(SOUL_SHARDS_TOOLTIP, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	-- Initial point; LayoutPlayerBottomFrames / AnchorShardBar refine to managed-container slot.
	local _, anchorY = self:GetShardBarAnchor()
	frame:SetPoint("TOPLEFT", playerFrame, "BOTTOMLEFT", 90, anchorY)

	frame:SetScript("OnEvent", function(self, event, arg1, arg2)
		if event == "PLAYER_LEVEL_UP" then
			local level = arg1
			if level and level >= SHARDBAR_SHOW_LEVEL then
				self:UnregisterEvent("PLAYER_LEVEL_UP")
				self:Show()
				self:SetAlpha(0)
				self.showAnim:Play()
				UpdateShardBar(self)
				if WhoaUF.LayoutPlayerBottomFrames then
					WhoaUF:LayoutPlayerBottomFrames()
				end
			end
			return
		end

		if event == "PLAYER_ENTERING_WORLD"
			or event == "PLAYER_LOGIN"
			or event == "UNIT_DISPLAYPOWER"
			or event == "PLAYER_TALENT_UPDATE"
			or event == "PLAYER_SPECIALIZATION_CHANGED"
			or event == "SPELLS_CHANGED"
		then
			RefreshShardBarVisibility(self)
			return
		end

		if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
			local unit = GetPowerUnit()
			if arg1 == unit or arg1 == "player" then
				if arg2 == "SOUL_SHARDS" or arg2 == GetSoulShardType() then
					UpdateShardBar(self)
				end
			end
		end
	end)

	local function RegisterShardBarEvents(f)
		f:RegisterEvent("PLAYER_ENTERING_WORLD")
		f:RegisterEvent("PLAYER_LOGIN")
		f:RegisterEvent("UNIT_DISPLAYPOWER")
		f:RegisterEvent("UNIT_POWER_UPDATE")
		pcall(function()
			f:RegisterEvent("UNIT_POWER_FREQUENT")
		end)
		pcall(function()
			f:RegisterEvent("PLAYER_TALENT_UPDATE")
		end)
		pcall(function()
			f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
		pcall(function()
			f:RegisterEvent("SPELLS_CHANGED")
		end)
	end
	self.RegisterShardBarEvents = RegisterShardBarEvents
	RegisterShardBarEvents(frame)

	playerFrame.ShardBar = frame
	frame.whoaClassPowerSheet = TEX_CLIENT
	RefreshShardBarVisibility(frame)
end

function WhoaUF:ApplyShardBarArt()
	local player = self.unitFrames and self.unitFrames.player
	local frame = player and player.ShardBar
	if not frame then
		return
	end
	if self.ApplyClassPowerSheetRecursive then
		self:ApplyClassPowerSheetRecursive(frame, TEX_CLIENT)
	end
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "WARLOCK",
		init = function(uf, player)
			uf:InitShardBar(player)
		end,
		refresh = function(uf)
			uf:RefreshShardBar()
		end,
		applyArt = function(uf)
			uf:ApplyShardBarArt()
		end,
		frameKey = "ShardBar",
		registerEvents = "RegisterShardBarEvents",
		layout = {
			slot = "bottom",
			order = 80,
			frameKey = "ShardBar",
			style = "shard",
		},
	})
end
