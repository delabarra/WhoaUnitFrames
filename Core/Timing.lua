--[[
	Timing: shared CLEU fan-out, spark driver, grids, and spark visuals for
	ManaTickGlow / PowerTickGlow / SwingTickGlow. Docs: docs/timing/architecture.md
	Never call module Refresh* / LayoutPlayer* from here.
]]

local WhoaUF = WhoaUF

local Timing = {}
WhoaUF.Timing = Timing

---------------------------------------------------------------------------
-- Client gating
---------------------------------------------------------------------------

-- Classic: TOC interface (not WOW_PROJECT_ID — wrong ID breaks Cata/MoP tables).
-- Mainline: WOW_PROJECT_ID so Interface ~12xxxx is not MoP+. Camelot: 16001 band /
-- WOW_PROJECT_CAMELOT (Classic content, no CLEU, secrets). Destructure GetBuildInfo
-- (six returns; select(4) would pass locale into tonumber base).
local _, _, _, interfaceVersion = GetBuildInfo()
local TOC = tonumber(interfaceVersion) or 0
local IS_CAMELOT = (WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)
	or (TOC >= 16000 and TOC < 20000)
local IS_MAINLINE = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and not IS_CAMELOT
-- Never RegisterEvent CLEU on Mainline/Forever (pcall still ADDON_ACTION_FORBIDDEN).
local CLEU_ALLOWED = not IS_MAINLINE and not IS_CAMELOT
local API_LEVEL = (IS_MAINLINE or IS_CAMELOT) and 0 or math.floor(TOC / 10000) -- 1 Era … 5 MoP

Timing.tocVersion = TOC
Timing.apiLevel = API_LEVEL
Timing.isMainline = IS_MAINLINE
Timing.isCamelot = IS_CAMELOT
Timing.cleuAllowed = CLEU_ALLOWED
Timing.isEra = not IS_MAINLINE and not IS_CAMELOT and API_LEVEL <= 1
Timing.isTBC = not IS_MAINLINE and not IS_CAMELOT and API_LEVEL == 2
Timing.isWrath = not IS_MAINLINE and not IS_CAMELOT and API_LEVEL == 3
Timing.isCata = not IS_MAINLINE and not IS_CAMELOT and API_LEVEL == 4
Timing.isMoP = not IS_MAINLINE and not IS_CAMELOT and API_LEVEL >= 5

-- 3.0.2: no 2s tick; 4.0.1: no FSR / on-next-swing; 5.0.4: no ranged slot.
-- Cata/MoP: optional combat mana pulse (not a fake 2s tick). Mainline/Forever: off.
if IS_MAINLINE or IS_CAMELOT then
	Timing.hasRegenTick = false
	Timing.hasFiveSecondRule = false
	Timing.hasCombatManaPulse = false
	Timing.tickClockResets = false
	Timing.hasOnNextSwing = false
	Timing.castResetsSwing = false
	Timing.hasRangedSlot = false
else
	Timing.hasRegenTick = API_LEVEL <= 2
	Timing.hasFiveSecondRule = API_LEVEL <= 3
	Timing.hasCombatManaPulse = API_LEVEL >= 4 -- Cata/MoP in-combat 5s mana pulse
	Timing.tickClockResets = API_LEVEL == 2 -- TBC 2.2 per-player resettable clock
	Timing.hasOnNextSwing = API_LEVEL <= 3
	Timing.castResetsSwing = API_LEVEL <= 3
	Timing.hasRangedSlot = API_LEVEL <= 4
end

Timing.REGEN_PERIOD = 2
Timing.FIVE_SECOND_RULE = 5
-- Cata quotes mana per 5s; MoP restores closer to 1/s — pulse the blue glow to match.
Timing.COMBAT_MANA_PULSE = Timing.isMoP and 1 or 5

---------------------------------------------------------------------------
-- Shared option shape (on / off)
-- Legacy "combat" / "only in combat" values migrate to "on" so OOC healing
-- still shows mana/energy ticks and the five-second rule.
---------------------------------------------------------------------------

function Timing.NormalizeMode(value)
	if value == true or value == 1 or value == "1" then
		return "on"
	end
	if type(value) == "string" then
		local lower = value:lower()
		if lower == "on" or lower == "always" or lower == "combat" or lower == "only in combat" then
			return "on"
		end
	end
	return "off"
end

function Timing.ModeAllows(mode, _frame)
	return mode == "on"
end

function Timing.ModeToBool(value)
	return Timing.NormalizeMode(value) == "on"
end

---------------------------------------------------------------------------
-- Phase-locked grid
---------------------------------------------------------------------------

-- A 2-second server grid reconstructed from observed arrivals. Observations are
-- blended into a persistent anchor rather than snapping it, so network jitter
-- does not make the spark jump, and a missed tick keeps predicting.
-- Docs: docs/timing/mana-regen.md §5.3
local Grid = {}
Grid.__index = Grid

function Timing:NewGrid(period, gain, staleAfter)
	period = period or Timing.REGEN_PERIOD
	return setmetatable({
		period = period,
		gain = gain or 0.15,
		staleAfter = staleAfter or (period * 2.5),
	}, Grid)
end

function Grid:Reset()
	self.anchor = nil
	self.lastObserved = nil
end

function Grid:Seed(now)
	self.anchor = now or GetTime()
	self.lastObserved = nil
end

function Grid:IsLocked()
	return self.anchor ~= nil
end

function Grid:IsStale(now)
	if not self.anchor then
		return true
	end
	local last = self.lastObserved
	return last ~= nil and ((now or GetTime()) - last) > self.staleAfter
end

function Grid:Observe(now)
	now = now or GetTime()
	local period = self.period
	-- No lock, aged out, or provisional Seed only → hard re-anchor.
	if not self.anchor or self:IsStale(now) or not self.lastObserved then
		self.anchor = now
	else
		local phase = (now - self.anchor) % period
		if phase > period * 0.5 then
			phase = phase - period
		end
		self.anchor = self.anchor + phase * self.gain
		local elapsed = now - self.anchor
		if elapsed >= period then
			self.anchor = self.anchor + period * math.floor(elapsed / period)
		end
	end
	self.lastObserved = now
end

--- 0..1 inside the current period, or nil while stale.
--- Free-running watchdog: advances by whole periods instead of snapping to now,
--- which would accumulate a frame of drift per synthetic tick. This is what
--- holds phase while at full power, when no deltas arrive at all.
--- Pass ignoreStale at full power, where the absence of deltas is expected
--- rather than evidence that the anchor went bad.
function Grid:Progress(now, ignoreStale)
	if not self.anchor then
		return nil
	end
	now = now or GetTime()
	if not ignoreStale and self:IsStale(now) then
		return nil
	end
	local period = self.period
	local elapsed = now - self.anchor
	if elapsed >= period then
		self.anchor = self.anchor + period * math.floor(elapsed / period)
		elapsed = now - self.anchor
	end
	if elapsed < 0 then
		return 0
	end
	return elapsed / period
end

function Grid:SinceObserved(now)
	if not self.lastObserved then
		return nil
	end
	return (now or GetTime()) - self.lastObserved
end

function Grid:NextBoundary(t)
	if not self.anchor then
		return nil
	end
	local steps = math.ceil((t - self.anchor) / self.period)
	if steps < 0 then
		steps = 0
	end
	return self.anchor + steps * self.period
end

---------------------------------------------------------------------------
-- Single spark driver
---------------------------------------------------------------------------

-- Shared spark OnUpdate; fn(now) → false removes the entry.
local DRIVER_INTERVAL = 0.02

local driver
local driverEntries = {}
local driverCount = 0
local driverNextRun = 0

local function DriverOnUpdate()
	local now = GetTime()
	if now < driverNextRun then
		return
	end
	driverNextRun = now + DRIVER_INTERVAL
	for key, fn in pairs(driverEntries) do
		if fn(now) == false then
			driverEntries[key] = nil
			driverCount = driverCount - 1
		end
	end
	if driverCount <= 0 then
		driver:SetScript("OnUpdate", nil)
	end
end

function Timing:AddSpark(key, fn)
	if not key or type(fn) ~= "function" then
		return
	end
	if not driver then
		driver = CreateFrame("Frame")
	end
	if driverEntries[key] == nil then
		driverCount = driverCount + 1
	end
	driverEntries[key] = fn
	if driver:GetScript("OnUpdate") ~= DriverOnUpdate then
		driverNextRun = 0
		driver:SetScript("OnUpdate", DriverOnUpdate)
	end
end

function Timing:RemoveSpark(key)
	if key == nil or driverEntries[key] == nil then
		return
	end
	driverEntries[key] = nil
	driverCount = driverCount - 1
	if driverCount <= 0 and driver then
		driver:SetScript("OnUpdate", nil)
	end
end

function Timing:HasSpark(key)
	return key ~= nil and driverEntries[key] ~= nil
end

---------------------------------------------------------------------------
-- Combat log dispatcher
---------------------------------------------------------------------------

-- Single CLEU frame; RegisterEvent only while subscribers exist (docs/timing/swing-timer.md §8).
-- Mainline/Forever: never RegisterEvent (see CLEU_ALLOWED).
local combatLogSubs = {}
local combatLogCount = 0
local combatLogFrame

local function CombatLogOnEvent()
	if combatLogCount <= 0 then
		return
	end
	local timestamp, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _,
		p12, p13, p14, p15, p16, p17, p18, p19, p20, p21 = CombatLogGetCurrentEventInfo()
	for _, fn in pairs(combatLogSubs) do
		fn(timestamp, subevent, sourceGUID, destGUID, p12, p13, p14, p15, p16, p17, p18, p19, p20, p21)
	end
end

local function SyncCombatLogRegistration()
	if not CLEU_ALLOWED or not combatLogFrame then
		return
	end
	if combatLogCount > 0 then
		combatLogFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	else
		combatLogFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

if CLEU_ALLOWED then
	combatLogFrame = CreateFrame("Frame")
	combatLogFrame:SetScript("OnEvent", CombatLogOnEvent)
end

--- True while Whoa is enabled and SetRuntimeActive has not muted runtime.
function Timing.IsAddonRuntimeActive()
	return WhoaUF.db and WhoaUF.db.enabled and WhoaUF.runtimeActive ~= false
end

function Timing:SubscribeCombatLog(key, fn)
	if not key or type(fn) ~= "function" or not CLEU_ALLOWED then
		return
	end
	if combatLogSubs[key] == nil then
		combatLogCount = combatLogCount + 1
	end
	combatLogSubs[key] = fn
	SyncCombatLogRegistration()
end

function Timing:UnsubscribeCombatLog(key)
	if key == nil or combatLogSubs[key] == nil then
		return
	end
	combatLogSubs[key] = nil
	combatLogCount = combatLogCount - 1
	if combatLogCount < 0 then
		combatLogCount = 0
	end
	SyncCombatLogRegistration()
end

---------------------------------------------------------------------------
-- Latency
---------------------------------------------------------------------------

-- GetNetStats is slow; re-read every 5s (not spike-accurate).
local latencySeconds = 0
local latencyStamp = 0

function Timing:WorldLatency()
	local now = GetTime()
	if now - latencyStamp > 5 then
		latencyStamp = now
		local _, _, _, lagWorld = GetNetStats()
		latencySeconds = (tonumber(lagWorld) or 0) / 1000
	end
	return latencySeconds
end

---------------------------------------------------------------------------
-- Spark visuals
---------------------------------------------------------------------------

local SPARK_TEXTURE = "Interface\\CastingBar\\UI-CastingBar-Spark"
local SPARK_WIDTH = 20
local SPARK_HEIGHT_RATIO = 2.2 -- oversized; host SetClipsChildren crops to bar
local SPARK_ALPHA = 0.75

-- Lane levels unique per host (-8..7). FSR white; swings untinted (OH lower alpha).
-- Docs: docs/timing/architecture.md §4
local SUBLEVEL_MIN, SUBLEVEL_MAX = -8, 7

Timing.LANE = {
	regen = { level = 6, fromPower = "MANA" },
	fsr = { level = 7, r = 1.00, g = 1.00, b = 1.00 },
	energy = { level = 6, fromPower = "ENERGY" },
	swingMain = { level = 5, noColor = true },
	swingOff = { level = 6, noColor = true, alpha = 0.55 },
	swingRanged = { level = 7, noColor = true },
}

local function BarHeight(bar)
	local h = bar and bar:GetHeight()
	if not h or h < 1 then
		return 12
	end
	return h
end

local function ClampColor(c)
	if c < 0 then
		return 0
	end
	if c > 1 then
		return 1
	end
	return c
end

function Timing:SparkColor(bar, lane)
	if not lane or lane.noColor then
		return nil
	end
	local r, g, b = lane.r, lane.g, lane.b
	if lane.fromPower then
		local info = WhoaUF.PowerBarColor and WhoaUF.PowerBarColor[lane.fromPower]
		if info then
			r, g, b = info.r, info.g, info.b
		end
	elseif lane.fromBar and bar and bar.GetStatusBarColor then
		r, g, b = bar:GetStatusBarColor()
	end
	if not (r and g and b) then
		return nil
	end
	local shade = lane.shade or 1
	return ClampColor(r * shade), ClampColor(g * shade), ClampColor(b * shade)
end

function Timing:ApplySparkVisual(spark, bar, lane)
	if not spark or not bar then
		return
	end
	spark:SetTexture(SPARK_TEXTURE)
	spark:SetBlendMode("ADD")
	spark:SetWidth(SPARK_WIDTH)
	spark:SetHeight(BarHeight(bar) * SPARK_HEIGHT_RATIO)
	if lane and lane.noColor then
		spark:SetVertexColor(1, 1, 1)
	else
		local r, g, b = self:SparkColor(bar, lane)
		if r then
			spark:SetVertexColor(r, g, b)
		end
	end
	spark:SetAlpha((lane and lane.alpha) or SPARK_ALPHA)
end

function Timing:TintSpark(spark, bar, lane)
	if not spark or (lane and lane.noColor) then
		return
	end
	local r, g, b = self:SparkColor(bar, lane)
	if r then
		spark:SetVertexColor(r, g, b)
	end
end

function Timing:CreateSpark(host, bar, lane)
	local level = (lane and lane.level) or 6
	-- Clamp rather than trust the lane: CreateTexture throws outside -8..7, and
	-- one bad lane value would take down the whole module's boot.
	if level < SUBLEVEL_MIN then
		level = SUBLEVEL_MIN
	elseif level > SUBLEVEL_MAX then
		level = SUBLEVEL_MAX
	end
	local spark = host:CreateTexture(nil, "OVERLAY", nil, level)
	self:ApplySparkVisual(spark, bar, lane)
	spark:Hide()
	return spark
end

function Timing:PositionSpark(spark, bar, progress, lane)
	if not spark or not bar then
		return
	end
	if not progress or progress < 0 then
		progress = 0
	elseif progress > 1 then
		progress = 1
	end
	local width = bar:GetWidth()
	if not width or width < 1 then
		width = 1
	end
	spark:ClearAllPoints()
	local x = progress * width
	spark:SetPoint("CENTER", bar, "LEFT", x, 0)
end

---------------------------------------------------------------------------
-- Host frames
---------------------------------------------------------------------------

function Timing:AnchorHost(host, frame, bar, opts)
	if not host or not frame or not bar then
		return
	end
	host:ClearAllPoints()
	host:SetPoint("TOPLEFT", bar, "TOPLEFT")
	host:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
	if host.SetClipsChildren then
		local clip = not (opts and opts.clip == false)
		host:SetClipsChildren(clip)
	end
	local overlay = frame.Overlay
	local borderLevel = (overlay and overlay:GetFrameLevel()) or (frame:GetFrameLevel() + 3)
	host:SetFrameLevel(borderLevel + 2)
	host.bar = bar
end

function Timing:BarReady(frame, bar)
	if not frame or frame.kind ~= "player" or not bar then
		return false
	end
	if bar.pauseUpdates or not bar:IsShown() or bar:GetAlpha() <= 0 then
		return false
	end
	local unit = bar.unit or frame.unit or "player"
	if not UnitIsConnected(unit) then
		return false
	end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Misc helpers
---------------------------------------------------------------------------

function Timing.PlayerClass()
	return (select(2, UnitClass("player")))
end

function Timing.SpellName(spellId)
	if not spellId then
		return nil
	end
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(spellId)
	end
	if GetSpellInfo then
		return (GetSpellInfo(spellId))
	end
	return nil
end

function Timing.SpellNameSet(ids)
	local set = {}
	for i = 1, #ids do
		local name = Timing.SpellName(ids[i])
		if name then
			set[name] = true
		end
	end
	return set
end

function Timing.DeferRefresh(fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, fn)
	else
		fn()
	end
end
