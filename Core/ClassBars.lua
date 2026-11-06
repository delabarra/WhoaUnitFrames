--[[
	Class power bar registry.

	Prefer flavor TOCs (WhoaUnitFrames_Vanilla.toc … _Mainline.toc) so clients
	never parse bars that cannot exist on that expansion. Fallback / Classic
	TOCs use [AllowLoadGameType …]; modules also early-return on Has* gates.

	Wrong-class modules return before RegisterClassBar. Init / runtime / layout
	iterate only registered bars.
]]

local bars = {}
local playerClass

-- Overlay bars that anchor outside the bottom managed slot.
local OVERLAY_ANCHORS = {
	TotemFrame = "AnchorTotemFrame",
	MonkStaggerBar = "AnchorMonkStaggerBar",
	AlternateManaBar = "AnchorAlternateManaBar",
	ComboPointPlayerBar = "AnchorComboPointPlayerBar",
	RogueComboPointBar = "AnchorComboPointPlayerBar",
	DruidComboPointBar = "AnchorDruidComboPointBar",
}

-- Cache player class once it is known; never sticky-cache nil/empty.
local function GetPlayerClass()
	if playerClass and playerClass ~= "" then
		return playerClass
	end
	local _, class = UnitClass("player")
	if class and class ~= "" then
		playerClass = class
	end
	return playerClass
end

local function ClassMatches(classes, class)
	if not class or not classes then
		return false
	end
	if type(classes) == "string" then
		return classes == class
	end
	return classes[class] and true or false
end

local function SetModuleEvents(frame, enabled, registerFn)
	if not frame then
		return
	end
	if enabled then
		if registerFn then
			registerFn(frame)
		end
	else
		frame:UnregisterAllEvents()
		frame:SetScript("OnUpdate", nil)
	end
end

local function GetBarFrameKey(def)
	if not def then
		return nil
	end
	return def.frameKey or (def.layout and def.layout.frameKey)
end

local function GetBarFrame(player, def)
	local key = GetBarFrameKey(def)
	if not key or not player then
		return nil
	end
	return player[key]
end

-- Visible player chrome for class-bar anchoring.
function WhoaUF:GetClassPowerAnchorFrame()
	return self.unitFrames and self.unitFrames.player
end

function WhoaUF:GetClassPowerBarParent()
	local player = self.unitFrames and self.unitFrames.player
	return player or UIParent
end

function WhoaUF:ApplyComboPointPlayerBarStrata(player)
	player = player or (self.unitFrames and self.unitFrames.player)
	if not player then
		return
	end
	local frame = player.ComboPointPlayerBar or player.RogueComboPointBar or player.DruidComboPointBar
	if not frame then
		return
	end
	local druidStacked = self.IsDruidStackedPlayerFrameActive and self:IsDruidStackedPlayerFrameActive(player)
	if druidStacked then
		-- Child of the player: above under-player threat host, under Overlay rim.
		if not (InCombatLockdown() and frame.IsProtected and frame:IsProtected()) then
			if frame:GetParent() ~= player then
				frame:SetParent(player)
			end
		end
		frame:SetFrameStrata(player:GetFrameStrata() or "LOW")
		local base = player:GetFrameLevel() or 0
		local overlay = player.Overlay
		local overlayLevel = overlay and (overlay:GetFrameLevel() or (base + 3)) or (base + 3)
		-- One level under Overlay so stacked chrome still covers the tray top.
		frame:SetFrameLevel(math.max(base, overlayLevel - 1))
		return
	end
	-- Above overlay chrome (overlay is player + 3). UIParent sibling for lockdown-safe Show/Hide.
	if not (InCombatLockdown() and frame.IsProtected and frame:IsProtected()) then
		if frame:GetParent() ~= UIParent then
			frame:SetParent(UIParent)
		end
	end
	local base = player:GetFrameLevel() or 0
	local overlay = player.Overlay
	if overlay then
		base = math.max(base, overlay:GetFrameLevel() or 0)
	end
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(base + 5)
end

function WhoaUF:ApplyClassPowerFrameLevel(frame, extra)
	local player = self.unitFrames and self.unitFrames.player
	if not frame or not player then
		return
	end
	if frame == player.ComboPointPlayerBar or frame == player.RogueComboPointBar or frame == player.DruidComboPointBar then
		self:ApplyComboPointPlayerBarStrata(player)
		return
	end
	extra = extra or 5
	local base = player:GetFrameLevel() or 0
	local overlay = player.Overlay
	if overlay then
		base = math.max(base, overlay:GetFrameLevel() or 0)
	end
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(base + extra)
end

function WhoaUF:ReparentClassPowerBarIfNeeded(frame)
	if not frame then
		return
	end
	-- Combo + stock alt-mana manage their own parents (UIParent or secure stacked).
	if frame.whoaUnitFrame then
		local parent = frame:GetParent()
		if parent == UIParent or parent == frame.whoaUnitFrame then
			return
		end
	end
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
		return
	end
	local wantParent = self:GetClassPowerBarParent()
	if frame:GetParent() ~= wantParent then
		frame:SetParent(wantParent)
	end
end

-- def.classes = "PALADIN" or { PALADIN = true, ... }
-- def.load = optional () -> bool (expansion gate)
-- def.init(uf, playerFrame)
-- def.refresh(uf)
-- def.setRuntime(uf, active)  -- optional; default uses frameKey + registerEvents
-- def.frameKey = "PaladinPowerBar" on player frame
-- def.registerEvents = "RegisterPaladinPowerBarEvents" method name on WhoaUF
-- def.watcherKey = "warlockPowerWatcher" (optional alternate to frameKey events)
-- def.layout = {
--   slot = "bottom" | "overlay" (overlay: custom anchor; excluded from bottom stack),
--   order = number,
--   frameKey = "...",
--   style = "top" | "shard",
--   getAnchor = "GetPaladinPowerBarAnchor",
--   defaultX, defaultY,
-- }
function WhoaUF:RegisterClassBar(def)
	if not def then
		return
	end
	if def.load and not def.load() then
		return
	end
	local class = GetPlayerClass()
	-- Class unknown at ADDON_LOADED: still register; Init/Refresh filter by class.
	if class and not ClassMatches(def.classes, class) then
		return
	end
	bars[#bars + 1] = def
end

function WhoaUF:GetRegisteredClassBars()
	return bars
end

function WhoaUF:InitPlayerClassBars(playerFrame)
	local class = GetPlayerClass()
	-- Wait until UnitClass is known so class-gated bars are not created for the wrong class.
	if not class then
		return
	end
	for i = 1, #bars do
		local def = bars[i]
		if not ClassMatches(def.classes, class) then
			-- skip
		elseif def.init then
			local ok, err = pcall(def.init, self, playerFrame)
			if not ok and DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage("|cffff6666WhoaUF class bar init failed:|r " .. tostring(err))
			end
		end
	end
end

function WhoaUF:RefreshPlayerClassBars()
	if self.editModePreviewActive then
		return
	end
	if self.IsVehiclePlayerArtActive and self:IsVehiclePlayerArtActive() then
		if self.HidePlayerClassPowerBars then
			self:HidePlayerClassPowerBars()
		end
		return
	end
	local class = GetPlayerClass()
	if not class then
		return
	end
	for i = 1, #bars do
		local def = bars[i]
		if not ClassMatches(def.classes, class) then
			-- skip
		elseif def.refresh then
			local ok, err = pcall(def.refresh, self)
			if not ok and DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage("|cffff6666WhoaUF class bar refresh failed:|r " .. tostring(err))
			end
		end
	end
end

-- Rebind class-power sheets after light/dark (or style) changes without recreating bars.
function WhoaUF:ApplyPlayerClassPowerArt()
	local player = self.unitFrames and self.unitFrames.player
	if not player then
		return
	end
	for i = 1, #bars do
		local def = bars[i]
		if def.applyArt then
			local ok, err = pcall(def.applyArt, self)
			if not ok and DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage("|cffff6666WhoaUF class bar art failed:|r " .. tostring(err))
			end
		else
			local frame = GetBarFrame(player, def)
			local sheet = frame and frame.whoaClassPowerSheet
			if frame and sheet and self.ApplyClassPowerSheetRecursive then
				self:ApplyClassPowerSheetRecursive(frame, sheet)
			end
		end
	end
end

function WhoaUF:SetPlayerClassBarRuntime(active)
	local player = self.unitFrames and self.unitFrames.player
	for i = 1, #bars do
		local def = bars[i]
		if def.setRuntime then
			def.setRuntime(self, active)
		elseif def.watcherKey then
			local watcher = self[def.watcherKey]
			if watcher then
				if active then
					local reg = def.registerEvents and self[def.registerEvents]
					if reg then
						reg(watcher)
					end
				else
					watcher:UnregisterAllEvents()
				end
			end
		elseif def.frameKey and player then
			local reg = def.registerEvents and self[def.registerEvents]
			SetModuleEvents(player[def.frameKey], active, reg)
		end
	end
end

local function LayoutOverlayBar(self, player, def, stack, spacing)
	local layout = def.layout
	local frameKey = layout.frameKey or def.frameKey
	local frame = frameKey and player[frameKey]
	if not frame then
		return
	end
	self:ReparentClassPowerBarIfNeeded(frame)
	if not frame:IsShown() then
		return
	end
	local anchorName = layout.anchor or (frameKey and OVERLAY_ANCHORS[frameKey])
	local anchor = anchorName and self[anchorName]
	if anchor then
		if anchorName == "AnchorTotemFrame" then
			anchor(self, stack, spacing)
		else
			anchor(self)
		end
	elseif layout.getAnchor then
		local anchorFrame = self:GetClassPowerAnchorFrame() or player
		frame:ClearAllPoints()
		local x, y = self[layout.getAnchor](self)
		frame:SetPoint("TOP", anchorFrame, "BOTTOM", x, y)
	end
	-- Stacked druid/mon alt mana parents to the player frame; SetLook owns strata/level.
	local stackedAltMana = frameKey == "AlternateManaBar"
		and self.IsAlternateManaBarStackedStyle
		and self:IsAlternateManaBarStackedStyle()
	if not stackedAltMana then
		self:ApplyClassPowerFrameLevel(frame)
	end
end

-- Place overlay + bottom-slot class bars; returns the bottom stack frame (or nil).
-- Overlay bars sit on player chrome and must not push pet/totems.
function WhoaUF:LayoutPlayerClassBars(player, stack, spacing)
	if not player then
		return stack
	end
	spacing = spacing or 2
	local anchorFrame = self:GetClassPowerAnchorFrame() or player

	-- Overlay: sit on the player rim (e.g. Legion ComboPointPlayerFrame).
	local overlays = self._classBarOverlayOrder
	if not overlays then
		overlays = {}
		for i = 1, #bars do
			local def = bars[i]
			if def.layout and def.layout.slot == "overlay" then
				overlays[#overlays + 1] = def
			end
		end
		self._classBarOverlayOrder = overlays
	end
	for i = 1, #overlays do
		LayoutOverlayBar(self, player, overlays[i], stack, spacing)
	end

	-- Stable order without allocating a sorted copy every layout.
	local ordered = self._classBarLayoutOrder
	if not ordered then
		ordered = {}
		for i = 1, #bars do
			local def = bars[i]
			if def.layout and def.layout.slot == "bottom" then
				ordered[#ordered + 1] = def
			end
		end
		table.sort(ordered, function(a, b)
			return (a.layout.order or 100) < (b.layout.order or 100)
		end)
		self._classBarLayoutOrder = ordered
	end

	for i = 1, #ordered do
		if stack then
			break
		end
		local def = ordered[i]
		local layout = def.layout
		local frameKey = layout.frameKey or def.frameKey
		local frame = frameKey and player[frameKey]
		if frame and frame:IsShown() then
			self:ReparentClassPowerBarIfNeeded(frame)
			if layout.style == "shard" and self.AnchorShardBar then
				self:AnchorShardBar(nil, spacing)
			elseif layout.anchor and self[layout.anchor] then
				self[layout.anchor](self)
			else
				frame:ClearAllPoints()
				local x = layout.defaultX or 0
				local y = layout.defaultY or 36
				local getter = layout.getAnchor and self[layout.getAnchor]
				if getter then
					x, y = getter(self)
				end
				frame:SetPoint("TOP", anchorFrame, "BOTTOM", x, y)
			end
			self:ApplyClassPowerFrameLevel(frame)
			stack = frame
		end
	end
	return stack
end
