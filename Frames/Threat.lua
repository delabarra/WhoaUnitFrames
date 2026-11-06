--[[
	Threat flash / numeric indicators + ToT-driven spellbar positioning.

	Threat flash (all frames): same as TargetFrame — threatIndicator texture,
	  UpdateThreatIndicator on events, plus 0.5s poll while shown.
	Numeric threat: Whoa option numericThreatFrame — player (name slot) or target/focus (above frame).
	While numeric threat is visible, Whoa/Thick hide the unit name on that frame;
	Classic keeps the name (Blizzard parity). DK Alpha keeps the player name (no collision).
	Art:
	  - Target/focus: UI-TargetingFrame-Flash (TargetFrame.xml)
	  - Player: mirrored Blizzard flash; custom druid flash only on stacked druid frame
	  - ToT/ToF: no threat flash
	  - Target/focus/pet/party: BACKGROUND on the unit button under Overlay so the
	    flash peeks around chrome
	  - Player: UIParent threatFlashHost at playerLevel-1 — below the whole player
	    frame and every class bar (which sit at/above the player)
	  - NumericThreatBorder: light → client; dark → Media\shared\dark\

	UpdateThreatIndicator keeps BOTH Classic (`status > 0`) and Mainline
	secret-safe branches (NeedsSecretSafeNumberOps / UsesSecretValues). Threat
	paint stays shared across flavors; cast bars live in CastBar_*.lua.

	Spellbar position (AdjustSpellBar / haveToT) lives here because ToT sync
	drives cast-bar placement. Flavor CastBar modules call WhoaUF:AdjustSpellBar
	(or spellbar.AdjustPosition → same). InitCastAndThreat creates threat chrome,
	then CastBar_*.lua CreateUnitSpellbar when that module is loaded.
]]

local THREAT_ANCHOR_X = -6
local THREAT_ANCHOR_Y = -3
local THREAT_ELITE_ANCHOR_X = -4
local THREAT_ELITE_ANCHOR_Y = 6

-- TargetFrame.xml NumericalThreat: BOTTOM -> TOP at -50,-22 (50px left of center).
-- Whoa: -2px lower than stock so it sits cleaner on custom chrome.
local TARGET_NUMERIC_ANCHOR_X = -50
local TARGET_NUMERIC_ANCHOR_Y = -25

-- Player mirror: same inset from the right edge.
local PLAYER_NUMERIC_ANCHOR_X = 50
local PLAYER_NUMERIC_ANCHOR_Y = -25

-- PlayerFrameFlash (mirrored target flash; see PlayerFrame.xml).
-- Raised +1 vs stock (-4) so the glow hugs Whoa chrome; alt-mana nudge in LayoutPlayerCombatGlow.
local PLAYER_FLASH_X = -3
local PLAYER_FLASH_Y = -3

-- Threat flash strata.
-- Player: UIParent sibling host at playerLevel-1 so the threat border paints under
-- the whole player frame and under class bars (overlay+5 / stacked under Overlay).
-- A texture on the player button cannot sit under the player frame itself — child
-- frames always composite above parent textures.
-- Target/focus/boss/pet/party: BACKGROUND on the unit button under Overlay chrome.
function WhoaUF:ApplyThreatFlashStrata(frame)
	local flash = frame and frame.threatIndicator
	if not flash then
		return
	end

	local overlay = frame.Overlay or frame.AuraHost
	local base = frame:GetFrameLevel() or 0
	if overlay then
		local wantOverlay = base + 3
		if overlay:GetFrameLevel() ~= wantOverlay then
			overlay:SetFrameLevel(wantOverlay)
		end
	end

	if frame.kind == "player" then
		local host = frame.threatFlashHost
		if not host then
			host = CreateFrame("Frame", nil, UIParent)
			host:EnableMouse(false)
			frame.threatFlashHost = host
		end
		-- Stay under the player even when SetToplevel raises it — re-pin each apply.
		if not (InCombatLockdown() and host.IsProtected and host:IsProtected()) then
			if host:GetParent() ~= UIParent then
				host:SetParent(UIParent)
			end
		end
		host:SetFrameStrata(frame:GetFrameStrata() or "LOW")
		local wantHost = math.max(0, base - 1)
		if host:GetFrameLevel() ~= wantHost then
			host:SetFrameLevel(wantHost)
		end
		host:ClearAllPoints()
		host:SetAllPoints(frame)
		if flash:GetParent() ~= host then
			flash:SetParent(host)
		end
		flash:SetDrawLayer("ARTWORK", 0)

		local nameHost = frame.NameHost
		if nameHost then
			local wantName = base + 8
			if nameHost:GetFrameLevel() ~= wantName then
				nameHost:SetFrameLevel(wantName)
			end
		end
		return
	end

	-- Target / focus / boss / pet / party: BACKGROUND under Overlay.
	if flash:GetParent() ~= frame then
		flash:SetParent(frame)
	end
	flash:SetDrawLayer("BACKGROUND", 0)

	-- Party NameHost (+8) must stay above bars when the unit button level moves.
	local nameHost = frame.NameHost
	if nameHost then
		local want = base + 8
		if nameHost:GetFrameLevel() ~= want then
			nameHost:SetFrameLevel(want)
		end
	end

	-- Non-player: pin any leftover host under the unit button.
	local host = frame.threatFlashHost
	if host then
		if host:GetFrameLevel() ~= base then
			host:SetFrameLevel(base)
		end
	end
end

-- Mirror TargetOfTargetMixin:Update show rules (Classic/TargetFrame.lua).
-- RegisterUnitWatch only tracks token existence — parent dead / self-target /
-- CVar off must be applied separately (combat-safe via alpha in UpdateToTFrame).
local function ShouldShowToTFrame(totFrame)
	if not totFrame then
		return false
	end
	if WhoaUF.IsForceShowFrame and WhoaUF:IsForceShowFrame(totFrame.kind) then
		return true
	end
	if not GetCVarBool("showTargetOfTarget") then
		return false
	end
	local parent = totFrame:GetParent()
	if not parent or not parent.unit then
		return false
	end
	if not UnitExists(parent.unit) or not UnitExists(totFrame.unit) then
		return false
	end
	-- Hide ToT when the parent is dead (Blizzard: UnitHealth(parent.unit) > 0).
	if UnitIsDeadOrGhost and WhoaUF:IsAccessibleTrue(UnitIsDeadOrGhost(parent.unit)) then
		return false
	end
	local parentHealth = UnitHealth(parent.unit)
	if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(parentHealth) and parentHealth <= 0 then
		return false
	end
	-- Hide when targeting yourself / your vehicle seat (Blizzard: PlayerFrame.unit).
	local playerFrame = WhoaUF.unitFrames and WhoaUF.unitFrames.player
	local playerUnit = (playerFrame and playerFrame.unit) or "player"
	if WhoaUF.UnitMatchesToken and WhoaUF:UnitMatchesToken(playerUnit, parent.unit) then
		return false
	end
	return true
end

local function SyncHaveToT(parentFrame)
	if not parentFrame then
		return nil
	end
	if ShouldShowToTFrame(parentFrame.totFrame) then
		parentFrame.haveToT = true
	else
		parentFrame.haveToT = nil
	end
	return parentFrame.haveToT
end

-- Mirror TargetSpellBarMixin:AdjustPosition (TargetFrame.lua).
local function AdjustSpellBarPosition(self)
	local parentFrame = self:GetParent()
	if not parentFrame then
		return
	end
	local haveToT = SyncHaveToT(parentFrame)
	local xOffset = self.xOffset or 0
	self:ClearAllPoints()
	if self.boss then
		self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 43 + xOffset, 6)
	elseif haveToT then
		if parentFrame.buffsOnTop or (parentFrame.auraRows or 0) <= 1 then
			self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 43 + xOffset, -25)
		elseif parentFrame.spellbarAnchor then
			self:SetPoint("TOPLEFT", parentFrame.spellbarAnchor, "BOTTOMLEFT", 22 + xOffset, -15)
		else
			self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 43 + xOffset, -25)
		end
	elseif parentFrame.haveElite then
		if parentFrame.buffsOnTop or (parentFrame.auraRows or 0) <= 1 then
			self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 43 + xOffset, -9)
		elseif parentFrame.spellbarAnchor then
			self:SetPoint("TOPLEFT", parentFrame.spellbarAnchor, "BOTTOMLEFT", 22 + xOffset, -15)
		else
			self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 43 + xOffset, -9)
		end
	else
		if (not parentFrame.buffsOnTop) and (parentFrame.auraRows or 0) > 0 and parentFrame.spellbarAnchor then
			self:SetPoint("TOPLEFT", parentFrame.spellbarAnchor, "BOTTOMLEFT", 22 + xOffset, -15)
		else
			self:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 43 + xOffset, 3)
		end
	end
end

function WhoaUF:UpdateThreatFlashLayout(frame)
	local flash = frame.threatIndicator
	if not flash then
		return
	end

	-- Always re-assert strata (party/pet/player styles skip art layout below).
	WhoaUF:ApplyThreatFlashStrata(frame)
	if frame.threatFlashStyle then
		return
	end

	if frame.kind == "boss" then
		local path = WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("bossFlash")
		flash:SetTexture(path or "Interface\\TargetingFrame\\UI-UnitFrame-Boss-Flash")
		flash:SetTexCoord(0.0, 0.945, 0.0, 0.73125)
		flash:SetSize(242, 93)
		flash:ClearAllPoints()
		flash:SetPoint("TOPLEFT", frame, "TOPLEFT", THREAT_ANCHOR_X, THREAT_ANCHOR_Y)
		return
	end
	flash:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Flash")
	local isMinus = frame.isMinus or (WhoaUF.IsMinusUnit and WhoaUF:IsMinusUnit(frame.unit))
	if isMinus then
		flash:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Minus-Flash")
		flash:SetTexCoord(0, 1, 0, 1)
		flash:SetSize(256, 128)
		flash:ClearAllPoints()
		flash:SetPoint("TOPLEFT", frame, "TOPLEFT", THREAT_ANCHOR_X, THREAT_ANCHOR_Y)
		frame.haveElite = nil
	elseif frame.haveElite then
		flash:SetTexCoord(0, 0.9453125, 0.181640625, 0.400390625)
		flash:SetSize(242, 112)
		flash:ClearAllPoints()
		flash:SetPoint("TOPLEFT", frame, "TOPLEFT", THREAT_ELITE_ANCHOR_X, THREAT_ELITE_ANCHOR_Y)
	else
		flash:SetTexCoord(0, 0.9453125, 0, 0.181640625)
		flash:SetSize(242, 93)
		flash:ClearAllPoints()
		flash:SetPoint("TOPLEFT", frame, "TOPLEFT", THREAT_ANCHOR_X, THREAT_ANCHOR_Y)
	end
end

-- Local copy of UnitFrame_UpdateThreatIndicator so we never enter Blizzard's
-- CVarCallbackRegistry path from an insecure poller (taint / combat-exit fail).
local function NumericThreatEnabledForFrame(frame)
	if not frame or not WhoaUF.GetNumericThreatFrame then
		return false
	end
	local location = WhoaUF:GetNumericThreatFrame()
	if not location then
		return false
	end
	if location == "player" and frame.kind == "player" then
		return true
	end
	if location == "target" and (frame.kind == "target" or frame.kind == "focus") then
		return true
	end
	return false
end

local function GetNumericThreatIndicator(frame)
	if not NumericThreatEnabledForFrame(frame) then
		return nil
	end
	return frame.threatNumericIndicator
end

local function OnNumericThreatVisibilityChanged(frame)
	if WhoaUF.SyncFrameNameWithNumericThreat then
		WhoaUF:SyncFrameNameWithNumericThreat(frame)
	end
	if frame.kind == "target" or frame.kind == "focus" then
		if WhoaUF.UpdateUnitAuras then
			WhoaUF:UpdateUnitAuras(frame)
		end
	end
end

local function HookNumericThreatIndicator(numeric, frame)
	numeric:SetScript("OnShow", function()
		OnNumericThreatVisibilityChanged(frame)
	end)
	numeric:SetScript("OnHide", function()
		OnNumericThreatVisibilityChanged(frame)
	end)
end

local function CreateNumericThreatIndicator(parent, name, frame)
	local numeric = CreateFrame("Frame", name, parent)
	numeric:SetSize(49, 18)
	numeric:Hide()

	local text = numeric:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOP", 0, -4)
	numeric.text = text

	-- Same black plate as unit-frame Background (ToT bars, etc.).
	local background = numeric:CreateTexture(nil, "BACKGROUND", nil, -1)
	background:SetSize(37, 14)
	background:SetPoint("TOP", 0, -3)
	background:SetColorTexture(0, 0, 0, 0.5)
	numeric.background = background

	-- Threat tint fill: shown only for status > 0 (hide Blizzard grey).
	local bg = numeric:CreateTexture(nil, "BACKGROUND", nil, 0)
	bg:SetSize(37, 14)
	bg:SetPoint("TOP", 0, -3)
	bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bg:SetAlpha(0.5)
	bg:Hide()
	numeric.bg = bg

	local border = numeric:CreateTexture(nil, "ARTWORK")
	border:SetAllPoints()
	border:SetTexCoord(0, 0.765625, 0, 0.5625)
	numeric.border = border
	if WhoaUF.ApplyNumericThreatArt then
		WhoaUF:ApplyNumericThreatArt(numeric)
	else
		border:SetTexture("Interface\\TargetingFrame\\NumericThreatBorder")
	end

	if frame then
		HookNumericThreatIndicator(numeric, frame)
	end

	return numeric
end

function WhoaUF:SyncPlayerNumericThreatAnchor(frame)
	if not frame or frame.kind ~= "player" then
		return
	end
	local numeric = frame.threatNumericIndicator
	if not numeric then
		return
	end
	numeric:ClearAllPoints()
	numeric:SetPoint("BOTTOM", frame, "TOP", PLAYER_NUMERIC_ANCHOR_X, PLAYER_NUMERIC_ANCHOR_Y)
end

function WhoaUF:SyncFrameNameWithNumericThreat(frame)
	if not frame or not frame.Name then
		return
	end
	if WhoaUF.ShouldDisplayUnitName and WhoaUF:ShouldDisplayUnitName(frame) then
		frame.Name:Show()
		frame.Name:SetText(UnitName(frame.unit) or "")
	else
		frame.Name:SetText("")
		frame.Name:Hide()
	end
	if WhoaUF.SyncNameBackgroundForFrame then
		WhoaUF:SyncNameBackgroundForFrame(frame)
	end
end

function WhoaUF:SyncPlayerNameWithNumericThreat(frame)
	self:SyncFrameNameWithNumericThreat(frame)
end

-- Fill tint: hide Blizzard grey (status 0 / no aggro); show colored statuses at 50% alpha.
-- Black alpha plate (numeric.background) stays visible whenever the % frame is shown.
local function ApplyNumericThreatFill(numericIndicator, status)
	local bg = numericIndicator and numericIndicator.bg
	if not bg then
		return
	end
	if WhoaUF.CanAccessValue and not WhoaUF:CanAccessValue(status) then
		bg:Hide()
		return
	end
	if status and status > 0 and GetThreatStatusColor then
		bg:SetVertexColor(GetThreatStatusColor(status))
		bg:SetAlpha(0.5)
		bg:Show()
	else
		bg:Hide()
	end
end

local function UpdateThreatIndicator(indicator, numericIndicator, filterUnit)
	if not indicator then
		return
	end
	if filterUnit and filterUnit ~= indicator.feedbackUnit then
		return
	end

	local force = WhoaUF.IsForceShowThreatIndicator and WhoaUF:IsForceShowThreatIndicator()
	local status
	if force then
		-- Tanking (status 3) flash + 100% numeric for layout preview.
		status = 3
	elseif indicator.feedbackUnit ~= indicator.unit then
		status = UnitThreatSituation(indicator.feedbackUnit, indicator.unit)
	else
		status = UnitThreatSituation(indicator.feedbackUnit)
	end

	local statusOk = status == nil or (not WhoaUF.CanAccessValue or WhoaUF:CanAccessValue(status))
	local warningOn = force or (not IsThreatWarningEnabled or IsThreatWarningEnabled())
	if warningOn then
		if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(status) then
			-- Mainline: status may be secret — cannot Lua-test `status > 0`.
			-- Pass through to GetThreatStatusColor / SetVertexColor (C APIs).
			if GetThreatStatusColor then
				indicator:SetVertexColor(GetThreatStatusColor(status))
				indicator:Show()
			else
				indicator:Hide()
			end
		elseif statusOk and status and status > 0 and GetThreatStatusColor then
			indicator:SetVertexColor(GetThreatStatusColor(status))
			indicator:Show()
		else
			indicator:Hide()
		end

		if numericIndicator then
			if force then
				numericIndicator.text:SetText("100%")
				ApplyNumericThreatFill(numericIndicator, status)
				numericIndicator:Show()
			elseif WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues() then
				-- Mainline: threat % / isTanking often secret — cut numeric; flash still above.
				numericIndicator:Hide()
			else
				local fbUnit = numericIndicator.feedbackUnit or indicator.feedbackUnit
				local threatUnit = numericIndicator.threatUnit or indicator.unit
				local isMinus = WhoaUF.IsMinusUnit and WhoaUF:IsMinusUnit(threatUnit)
				local showNumeric = UnitDetailedThreatSituation
					and not isMinus
					and UnitExists(threatUnit)
				if showNumeric then
					local isTanking, detailedStatus, _, rawPercentage =
						UnitDetailedThreatSituation(fbUnit, threatUnit)
					local display = rawPercentage
					if isTanking and UnitThreatPercentageOfLead then
						display = UnitThreatPercentageOfLead(fbUnit, threatUnit)
					end
					if WhoaUF.NeedsSecretSafeNumberOps
						and WhoaUF:NeedsSecretSafeNumberOps(display, detailedStatus, isTanking)
					then
						numericIndicator:Hide()
					elseif display and display ~= 0 then
						local maxPct = MAX_DISPLAYED_THREAT_PERCENT or 999
						display = math.min(display, maxPct)
						numericIndicator.text:SetText(string.format("%1.0f%%", display))
						ApplyNumericThreatFill(numericIndicator, detailedStatus)
						numericIndicator:Show()
					else
						numericIndicator:Hide()
					end
				else
					numericIndicator:Hide()
				end
			end
		end
	else
		indicator:Hide()
		if numericIndicator then
			numericIndicator:Hide()
		end
	end
end

-- Poll on a plain UIParent Frame — never SetScript/HookScript the SecureUnitButton
-- (that triggers "Interface action failed because of an Addon").
-- OnUpdate runs only while the frame is shown and threat chrome is visible;
-- UNIT_THREAT_SITUATION_UPDATE covers idle / threat-appear cases.
local function SyncThreatPoll(frame)
	local poller = frame.threatPoller
	if not poller then
		return
	end
	local indicator = frame.threatIndicator
	local needPoll = frame:IsShown() and indicator and indicator:IsShown()
	if needPoll then
		if not poller.whoaActive then
			poller:SetScript("OnUpdate", poller.OnUpdate)
			poller.whoaActive = true
			frame.threatElapsed = 0
		end
	elseif poller.whoaActive then
		poller:SetScript("OnUpdate", nil)
		poller.whoaActive = false
	end
end

local function AttachThreatPoll(frame)
	if frame.threatPollAttached then
		return
	end
	frame.threatPollAttached = true
	frame.threatElapsed = 0

	local poller = CreateFrame("Frame", nil, UIParent)
	poller.OnUpdate = function(_, elapsed)
		if not frame:IsShown() then
			SyncThreatPoll(frame)
			return
		end
		frame.threatElapsed = (frame.threatElapsed or 0) + elapsed
		if frame.threatElapsed > 0.5 then
			frame.threatElapsed = 0
			WhoaUF:UpdateFrameThreat(frame)
		end
	end
	-- UNIT_THREAT_SITUATION_UPDATE between 0.5s poll ticks.
	pcall(function()
		poller:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	end)
	poller:SetScript("OnEvent", function(_, event, unit)
		if event ~= "UNIT_THREAT_SITUATION_UPDATE" then
			return
		end
		-- Only this frame's units (do not match bare "player" — that refreshed every
		-- party/pet threat poller on each player threat tick).
		local numericUnit = frame.threatNumericIndicator and frame.threatNumericIndicator.threatUnit
		if not unit
			or unit == frame.unit
			or unit == frame.feedbackUnit
			or unit == numericUnit
		then
			WhoaUF:UpdateFrameThreat(frame)
		end
	end)
	frame.threatPoller = poller
end

function WhoaUF:SyncThreatPoll(frame)
	SyncThreatPoll(frame)
end

function WhoaUF:UpdateFrameThreat(frame)
	if not frame or not frame.threatIndicator then
		return
	end
	if frame.showThreat == false then
		frame.threatIndicator:Hide()
		if frame.threatNumericIndicator then
			frame.threatNumericIndicator:Hide()
		end
		return
	end
	local forceThreat = self.IsForceShowThreatIndicator and self:IsForceShowThreatIndicator()
	-- DK Alpha / BlizzCon still show the player threat flash; numeric on player
	-- is allowed for Alpha (name does not collide). BlizzCon stays target-only
	-- via GetNumericThreatFrame.
	local numeric = GetNumericThreatIndicator(frame)
	-- Force-preview: show numeric on this frame even when the Settings location
	-- would normally hide it (so flash+numeric are visible for layout).
	if forceThreat and frame.threatNumericIndicator then
		numeric = frame.threatNumericIndicator
	end
	if frame.threatNumericIndicator and frame.threatNumericIndicator ~= numeric then
		frame.threatNumericIndicator:Hide()
	end
	UpdateThreatIndicator(frame.threatIndicator, numeric, frame.feedbackUnit)
	-- Pet/party flash must stay under Overlay like player (re-assert each paint).
	if frame.threatFlashStyle == "party" or frame.threatFlashStyle == "player" then
		self:ApplyThreatFlashStrata(frame)
	end
	SyncThreatPoll(frame)
	self:SyncFrameNameWithNumericThreat(frame)
end

-- DevTools: refresh threat chrome on every Whoa frame that has it.
function WhoaUF:ApplyForceShowThreatIndicators()
	local uf = self.unitFrames
	if uf then
		for _, frame in pairs(uf) do
			if type(frame) == "table" and frame.threatIndicator then
				self:UpdateFrameThreat(frame)
			end
		end
	end
	if self.partyFrames then
		for i = 1, 4 do
			local frame = self.partyFrames[i]
			if frame and frame.threatIndicator then
				self:UpdateFrameThreat(frame)
			end
			if frame and frame.PetFrame and frame.PetFrame.threatIndicator then
				self:UpdateFrameThreat(frame.PetFrame)
			end
		end
	end
end

function WhoaUF:ReleaseThreatRuntime(frame)
	local poller = frame and frame.threatPoller
	if not poller then
		return
	end
	poller:UnregisterAllEvents()
	poller:SetScript("OnUpdate", nil)
	poller.whoaActive = false
	if frame.threatIndicator then
		frame.threatIndicator:Hide()
	end
	if frame.threatNumericIndicator then
		frame.threatNumericIndicator:Hide()
	end
end

function WhoaUF:ResumeThreatRuntime(frame)
	local poller = frame and frame.threatPoller
	if not poller then
		return
	end
	pcall(function()
		poller:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	end)
	self:UpdateFrameThreat(frame)
end

function WhoaUF:AdjustSpellBar(frame)
	if frame and frame.spellbar then
		AdjustSpellBarPosition(frame.spellbar)
	end
end

function WhoaUF:ShouldShowToTFrame(totFrame)
	return ShouldShowToTFrame(totFrame)
end

function WhoaUF:SyncHaveToT(parentFrame)
	return SyncHaveToT(parentFrame)
end

-- Shared TargetFrame threat wiring: indicator.unit / feedbackUnit + poll.
local function WireThreatIndicator(frame, flash, feedbackUnit, style)
	flash:Hide()
	flash.unit = frame.unit
	flash.feedbackUnit = feedbackUnit
	frame.threatIndicator = flash
	frame.feedbackUnit = feedbackUnit
	frame.threatFlashStyle = style
	AttachThreatPoll(frame)
end

-- Player: TargetFrame threat API + mirrored PlayerFrameFlash art.
-- Classic Blizzard leaves flash unwired; numeric threat uses the player name slot when selected.
function WhoaUF:InitPlayerThreat(frame)
	if not frame then
		return
	end

	if not frame.threatIndicator then
		local flash = frame:CreateTexture(nil, "BACKGROUND")
		flash:SetSize(242, 93)
		flash:SetPoint("TOPLEFT", PLAYER_FLASH_X, PLAYER_FLASH_Y)
		-- feedbackUnit "player" + unit "player" => UnitThreatSituation("player")
		WireThreatIndicator(frame, flash, "player", "player")
	end
	WhoaUF:ApplyThreatFlashStrata(frame)
	if WhoaUF.ApplyPlayerThreatFlashArt then
		WhoaUF:ApplyPlayerThreatFlashArt(frame)
	end

	if not frame.threatNumericIndicator then
		local host = frame.NameHost or frame.Overlay or frame
		local numeric = CreateNumericThreatIndicator(host, frame:GetName() .. "NumericalThreat", frame)
		numeric:SetFrameLevel(host:GetFrameLevel() + 2)
		numeric.feedbackUnit = "player"
		numeric.threatUnit = "target"
		frame.threatNumericIndicator = numeric
		self:SyncPlayerNumericThreatAnchor(frame)
	end
end

-- Party / party-pet / player-pet: stock Flash texture + UnitThreatSituation(unit).
function WhoaUF:InitPartyThreat(frame)
	if not frame or frame.threatIndicator then
		return
	end
	local flash = frame.Flash
	if not flash then
		return
	end
	WireThreatIndicator(frame, flash, frame.unit, "party")
	WhoaUF:ApplyThreatFlashStrata(frame)
end

function WhoaUF:InitCastAndThreat(frame, updateEvent)
	if not frame then
		return
	end

	-- Threat flash once; spellbar from CastBar_*.lua CreateUnitSpellbar.
	if not frame.threatIndicator then
		local flash = frame:CreateTexture(nil, "BACKGROUND")
		flash:SetSize(242, 93)
		flash:SetPoint("TOPLEFT", -6, -3)
		flash:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Flash")
		flash:SetTexCoord(0, 0.9453125, 0, 0.181640625)
		WireThreatIndicator(frame, flash, "player", nil)
		WhoaUF:ApplyThreatFlashStrata(frame)
		frame.threatAnchorX = THREAT_ANCHOR_X
		frame.threatAnchorY = THREAT_ANCHOR_Y
		frame.threatEliteAnchorX = THREAT_ELITE_ANCHOR_X
		frame.threatEliteAnchorY = THREAT_ELITE_ANCHOR_Y
	end

	if not frame.threatNumericIndicator then
		local numeric = CreateNumericThreatIndicator(frame, frame:GetName() .. "NumericalThreat", frame)
		numeric:SetFrameLevel(frame:GetFrameLevel() + 4)
		numeric:SetPoint("BOTTOM", frame, "TOP", TARGET_NUMERIC_ANCHOR_X, TARGET_NUMERIC_ANCHOR_Y)
		numeric.feedbackUnit = "player"
		numeric.threatUnit = frame.unit
		frame.threatNumericIndicator = numeric
	end

	if not frame.spellbar and WhoaUF.CreateUnitSpellbar then
		WhoaUF:CreateUnitSpellbar(frame, updateEvent)
	end
end
