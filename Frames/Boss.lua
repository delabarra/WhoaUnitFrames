--[[
	Boss target frames (Classic layout).
	Reference: reference/Blizzard_UnitFrame/Classic/TargetFrame.lua BossTargetFrameMixin,
	           Classic/TargetFrame.xml BossTargetFrameTemplate / Boss1–5TargetFrame
]]

if not WhoaUF:HasBossFrames() then
	return
end

local MAX_BOSS_FRAMES = 5
local BOSS_SCALE = 0.75
local BOSS_STACK_GAP = -30
-- Mirror Boss1TargetFrame TOPRIGHT anchor (TargetFrame.xml).
local BOSS1_POINT, BOSS1_X, BOSS1_Y = "TOPRIGHT", 55, -236

local UF = WhoaUF._UF
local bossFrames = {}

local function ApplyBossChrome(frame)
	if not frame then
		return
	end
	frame.isBossFrame = true
	frame.maxBuffs = 0
	frame.maxDebuffs = 0
	frame.showLevel = true
	frame.showThreat = true
	frame.noTextPrefix = true
	if frame.SetScale then
		local scale = BOSS_SCALE
		if WhoaUF.GetEffectiveFrameScale then
			scale = WhoaUF:GetEffectiveFrameScale(frame)
		elseif WhoaUF.GetFrameScale then
			scale = BOSS_SCALE * WhoaUF:GetFrameScale()
		end
		frame:SetScale(scale)
	end
	local path = WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("boss")
	if path and frame.FrameTexture then
		frame.FrameTexture:SetTexture(path)
	end
	if frame.RaidTargetIcon then
		frame.RaidTargetIcon:ClearAllPoints()
		frame.RaidTargetIcon:SetPoint("RIGHT", -90, 0)
	end
	if frame.Level then
		local _, _, _, _, y = frame.Level:GetPoint(1)
		frame.Level:ClearAllPoints()
		frame.Level:SetPoint("CENTER", 12, y or 0)
	end
	if frame.threatIndicator and WhoaUF.GetFrameTexture then
		local flash = WhoaUF:GetFrameTexture("bossFlash")
		if flash then
			frame.threatIndicator:SetTexture(flash)
			frame.threatIndicator:SetTexCoord(0.0, 0.945, 0.0, 0.73125)
		end
	end
	if frame.threatNumericIndicator and frame.threatNumericIndicator.ClearAllPoints then
		frame.threatNumericIndicator:ClearAllPoints()
		frame.threatNumericIndicator:SetPoint("BOTTOM", frame, "TOP", -85, -24)
	end
end

function WhoaUF:UpdateAllBossFrames()
	for i = 1, MAX_BOSS_FRAMES do
		local frame = bossFrames[i]
		if frame and self.UpdateUnitFrame then
			self:UpdateUnitFrame(frame)
			if self.WantBossFramePreview and self:WantBossFramePreview() and self.ApplyForceShowPlaceholder then
				self:ApplyForceShowPlaceholder(frame)
			end
		end
	end
end

local function NeedBossFrames(self)
	if self.WantBossFramePreview and self:WantBossFramePreview() then
		return true
	end
	if self.IsForceShowFrame and self:IsForceShowFrame("boss") then
		return true
	end
	for i = 1, MAX_BOSS_FRAMES do
		if UnitExists("boss" .. i) then
			return true
		end
	end
	return false
end

local function ApplyBossPreviewPaint(self, frame)
	if not frame then
		return
	end
	if self.UpdateUnitFrame then
		self:UpdateUnitFrame(frame)
	end
	if self.ApplyForceShowPlaceholder then
		self:ApplyForceShowPlaceholder(frame)
	end
end

-- Lazy-init five boss frames on first encounter, DevTools force-show, or EditMode_*.lua preview.
function WhoaUF:EnsureBossFrames()
	if bossFrames[1] then
		return true
	end
	if InCombatLockdown() then
		UF.pendingBossFramesInit = true
		return false
	end
	local create = UF.CreateTargetVisual
	if type(create) ~= "function" then
		return false
	end

	for i = 1, MAX_BOSS_FRAMES do
		local unit = "boss" .. i
		local frame = create("WhoaUFBoss" .. i .. "Frame", unit, "boss")
		frame.bossIndex = i
		frame.unit = unit
		ApplyBossChrome(frame)
		if i == 1 then
			frame:ClearAllPoints()
			frame:SetPoint(BOSS1_POINT, UIParent, BOSS1_POINT, BOSS1_X, BOSS1_Y)
		else
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", bossFrames[i - 1], "BOTTOMLEFT", 0, BOSS_STACK_GAP)
		end
		bossFrames[i] = frame
		UF.frames["boss" .. i] = frame
		if self.InitCastAndThreat then
			pcall(function()
				self:InitCastAndThreat(frame, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
			end)
			if frame.spellbar then
				frame.spellbar.boss = true
			end
		end
		-- Threat flash exists after InitCastAndThreat — re-apply boss flash sheet / anchors.
		ApplyBossChrome(frame)
	end

	self.bossFrames = bossFrames
	UF.pendingBossFramesInit = nil
	return true
end

function WhoaUF:LayoutBossFrames()
	if InCombatLockdown() then
		return
	end
	local show = self.db and self.db.enabled
	local preview = self.WantBossFramePreview and self:WantBossFramePreview()
	if show and NeedBossFrames(self) then
		if not self:EnsureBossFrames() then
			return
		end
	elseif not bossFrames[1] then
		return
	end

	-- Sync boss1 to EditMode_*.lua captured Boss container anchor (we do not register the system).
	if show and bossFrames[1] and self.CaptureEditModeLayoutAnchor then
		local anchor = self:CaptureEditModeLayoutAnchor("boss", _G.BossTargetFrameContainer)
		if anchor then
			local relativeTo = UIParent
			if self.ResolveEditModeRelativeFrame then
				relativeTo = self:ResolveEditModeRelativeFrame(anchor.relativeTo or "UIParent")
			end
			bossFrames[1]:ClearAllPoints()
			bossFrames[1]:SetPoint(
				anchor.point or BOSS1_POINT,
				relativeTo,
				anchor.relativePoint or anchor.point or BOSS1_POINT,
				anchor.x or BOSS1_X,
				anchor.y or BOSS1_Y
			)
		end
	end

	for i = 1, MAX_BOSS_FRAMES do
		local frame = bossFrames[i]
		if frame then
			if show then
				if preview then
					UnregisterUnitWatch(frame)
					frame:Show()
					ApplyBossPreviewPaint(self, frame)
				else
					RegisterUnitWatch(frame)
					if UnitExists(frame.unit) and self.UpdateUnitFrame then
						self:UpdateUnitFrame(frame)
					end
				end
			else
				UnregisterUnitWatch(frame)
				frame:Hide()
			end
		end
	end
end

-- Register boss events at InitBossFrames; CreateTargetVisual deferred to EnsureBossFrames.
function WhoaUF:InitBossFrames()
	if self.bossWatcher then
		return
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	pcall(function()
		watcher:RegisterEvent("UNIT_TARGETABLE_CHANGED")
	end)
	local function RegisterBossUnitEvent(event)
		watcher:RegisterUnitEvent(event, "boss1", "boss2", "boss3", "boss4")
	end
	RegisterBossUnitEvent("UNIT_HEALTH")
	pcall(function()
		RegisterBossUnitEvent("UNIT_HEALTH_FREQUENT")
	end)
	RegisterBossUnitEvent("UNIT_MAXHEALTH")
	RegisterBossUnitEvent("UNIT_POWER_UPDATE")
	pcall(function()
		RegisterBossUnitEvent("UNIT_POWER_FREQUENT")
	end)
	RegisterBossUnitEvent("UNIT_MAXPOWER")
	RegisterBossUnitEvent("UNIT_DISPLAYPOWER")
	RegisterBossUnitEvent("UNIT_LEVEL")
	RegisterBossUnitEvent("UNIT_NAME_UPDATE")
	RegisterBossUnitEvent("UNIT_PORTRAIT_UPDATE")
	RegisterBossUnitEvent("UNIT_CLASSIFICATION_CHANGED")
	RegisterBossUnitEvent("UNIT_FACTION")
	RegisterBossUnitEvent("UNIT_FLAGS")
	local watcherB = CreateFrame("Frame")
	local function RegisterBoss5(event)
		watcherB:RegisterUnitEvent(event, "boss5")
	end
	RegisterBoss5("UNIT_HEALTH")
	pcall(function()
		RegisterBoss5("UNIT_HEALTH_FREQUENT")
	end)
	RegisterBoss5("UNIT_MAXHEALTH")
	RegisterBoss5("UNIT_POWER_UPDATE")
	pcall(function()
		RegisterBoss5("UNIT_POWER_FREQUENT")
	end)
	RegisterBoss5("UNIT_MAXPOWER")
	RegisterBoss5("UNIT_DISPLAYPOWER")
	RegisterBoss5("UNIT_LEVEL")
	RegisterBoss5("UNIT_NAME_UPDATE")
	RegisterBoss5("UNIT_PORTRAIT_UPDATE")
	RegisterBoss5("UNIT_CLASSIFICATION_CHANGED")
	RegisterBoss5("UNIT_FACTION")
	RegisterBoss5("UNIT_FLAGS")

	local function OnBossEvent(_, event, unit)
		if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" or event == "PLAYER_ENTERING_WORLD" then
			WhoaUF:LayoutBossFrames()
			return
		end
		if event == "UNIT_TARGETABLE_CHANGED" then
			if type(unit) == "string" and unit:match("^boss%d$") then
				WhoaUF:LayoutBossFrames()
			end
			return
		end
		if type(unit) == "string" then
			local index = unit:match("^boss(%d)$")
			index = index and tonumber(index)
			local frame = index and bossFrames[index]
			if frame and WhoaUF.UpdateUnitFrame then
				WhoaUF:UpdateUnitFrame(frame)
			elseif index and NeedBossFrames(WhoaUF) then
				WhoaUF:LayoutBossFrames()
			end
		end
	end
	watcher:SetScript("OnEvent", OnBossEvent)
	watcherB:SetScript("OnEvent", OnBossEvent)
	self.bossWatcher = watcher
	self.bossWatcherB = watcherB
end
