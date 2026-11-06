--[[
	Util: shared color DB + lookup helpers for Whoa frames.
	Tables hold final colors (no runtime remaps). Getters only look up + fallback.
]]

WhoaUF = WhoaUF or {}

---------------------------------------------------------------------------
-- Power — Classic UnitFrame PowerBarColor (RGB).
-- fullPowerAnim: Whoa spike/glow + builder/spender feedback — RAGE / RUNIC only.
-- Ref colors: reference/Blizzard_UnitFrame/Classic/UnitFrame.lua
---------------------------------------------------------------------------

local PowerBarColor = {
	MANA = { r = 0.00, g = 0.00, b = 1.00 },
	RAGE = { r = 1.00, g = 0.00, b = 0.00, fullPowerAnim = true },
	FOCUS = { r = 1.00, g = 0.50, b = 0.25 },
	ENERGY = { r = 1.00, g = 1.00, b = 0.00 },
	HAPPINESS = { r = 1.00, g = 0.41, b = 0.96 },
	RUNIC_POWER = { r = 0.00, g = 0.82, b = 1.00, fullPowerAnim = true },
	SOUL_SHARDS = { r = 0.50, g = 0.32, b = 0.55 },
	LUNAR_POWER = { r = 0.30, g = 0.52, b = 0.90 },
	HOLY_POWER = { r = 0.95, g = 0.90, b = 0.60 },
	MAELSTROM = { r = 0.00, g = 0.50, b = 1.00 },
	INSANITY = { r = 0.40, g = 0, b = 0.80 },
	COMBO_POINTS = { r = 1.00, g = 0.96, b = 0.41 },
	CHI = { r = 0.71, g = 1.0, b = 0.92 },
	ARCANE_CHARGES = { r = 0.1, g = 0.1, b = 0.98 },
	FURY = { r = 0.788, g = 0.259, b = 0.992 },
	PAIN = { r = 1, g = 156 / 255, b = 0 },
	AMMOSLOT = { r = 0.80, g = 0.60, b = 0.00 },
	FUEL = { r = 0.0, g = 0.55, b = 0.5 },
	STAGGER = {
		{ r = 0.52, g = 1.0, b = 0.52 },
		{ r = 1.0, g = 0.98, b = 0.72 },
		{ r = 1.0, g = 0.42, b = 0.42 },
	},
}
PowerBarColor[0] = PowerBarColor.MANA
PowerBarColor[1] = PowerBarColor.RAGE
PowerBarColor[2] = PowerBarColor.FOCUS
PowerBarColor[3] = PowerBarColor.ENERGY
PowerBarColor[4] = PowerBarColor.CHI
PowerBarColor[6] = PowerBarColor.RUNIC_POWER
PowerBarColor[7] = PowerBarColor.SOUL_SHARDS
PowerBarColor[8] = PowerBarColor.LUNAR_POWER
PowerBarColor[9] = PowerBarColor.HOLY_POWER
PowerBarColor[11] = PowerBarColor.MAELSTROM
PowerBarColor[13] = PowerBarColor.INSANITY
PowerBarColor[17] = PowerBarColor.FURY
PowerBarColor[18] = PowerBarColor.PAIN

WhoaUF.PowerBarColor = PowerBarColor

--- token → type id → MANA
function WhoaUF:GetPowerBarColor(powerToken, powerType)
	-- Mainline: powerToken/type may be secret — never use as table keys.
	local info
	if powerToken ~= nil and self:CanAccessValue(powerToken) then
		info = PowerBarColor[powerToken]
	end
	if not info and powerType ~= nil and self:CanAccessValue(powerType) then
		info = PowerBarColor[powerType]
	end
	return info or PowerBarColor.MANA
end

--- Full-power spike/glow — RAGE / RUNIC_POWER only (via PowerBarColor.fullPowerAnim).
--- Unknown/secret token+type falls back to MANA → false (never class-guess).
function WhoaUF:WantsFullPowerAnim(powerToken, powerType)
	local info = self:GetPowerBarColor(powerToken, powerType)
	return info and info.fullPowerAnim and true or false
end

---------------------------------------------------------------------------
-- Debuff types — always use live Blizzard DebuffTypeColor / AuraUtil
---------------------------------------------------------------------------

-- Static debuff "none" color only when _G.DebuffTypeColor is absent.
local DEBUFF_NONE_FALLBACK = { r = 0.80, g = 0, b = 0 }

--- Prefer Blizzard DebuffTypeColor so client updates apply automatically.
function WhoaUF:GetDebuffTypeColor(debuffType)
	local colors = _G.DebuffTypeColor
	if colors then
		return colors[debuffType or ""] or colors.none or colors[""] or DEBUFF_NONE_FALLBACK
	end
	return DEBUFF_NONE_FALLBACK
end

---------------------------------------------------------------------------
-- Faction / reaction — live FACTION_BAR_COLORS when present
---------------------------------------------------------------------------

local FactionBarColors = {
	[1] = { r = 0.8, g = 0.3, b = 0.22 },
	[2] = { r = 0.8, g = 0.3, b = 0.22 },
	[3] = { r = 0.75, g = 0.27, b = 0 },
	[4] = { r = 0.9, g = 0.7, b = 0 },
	[5] = { r = 0, g = 0.6, b = 0.1 },
	[6] = { r = 0, g = 0.6, b = 0.1 },
	[7] = { r = 0, g = 0.6, b = 0.1 },
	[8] = { r = 0, g = 0.6, b = 0.1 },
}

local function SeedFactionBarColors()
	local src = _G.FACTION_BAR_COLORS
	if not src then
		return
	end
	for standing, c in pairs(src) do
		FactionBarColors[standing] = { r = c.r, g = c.g, b = c.b }
	end
end

SeedFactionBarColors()
WhoaUF.FactionBarColors = FactionBarColors

---------------------------------------------------------------------------
-- Class — live RAID_CLASS_COLORS / CUSTOM_CLASS_COLORS
---------------------------------------------------------------------------

local ClassColors = {
	-- Fallback when class file is missing / unknown (Blizzard GetClassColor default).
	UNKNOWN = { r = 1, g = 1, b = 1 },
}
WhoaUF.ClassColors = ClassColors

local function CopyColorRGB(c)
	return { r = c.r, g = c.g, b = c.b }
end

function WhoaUF:RefreshClassColors()
	local unknown = ClassColors.UNKNOWN
	wipe(ClassColors)
	ClassColors.UNKNOWN = unknown
	if RAID_CLASS_COLORS then
		for class, c in pairs(RAID_CLASS_COLORS) do
			ClassColors[class] = CopyColorRGB(c)
		end
	end
	if CUSTOM_CLASS_COLORS then
		for class, c in pairs(CUSTOM_CLASS_COLORS) do
			ClassColors[class] = CopyColorRGB(c)
		end
	end
end

WhoaUF:RefreshClassColors()
if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS.RegisterCallback then
	CUSTOM_CLASS_COLORS:RegisterCallback(WhoaUF, "RefreshClassColors")
end

--- classFile → UNKNOWN
function WhoaUF:GetClassColor(classFile)
	if classFile and self:CanAccessValue(classFile) then
		return ClassColors[classFile] or ClassColors.UNKNOWN
	end
	return ClassColors.UNKNOWN
end

--- Mainline: UnitClass is secret for identity-restricted tokens (e.g. targettarget
--- in instances). C_ClassColor accepts secret class names; RGB may come back secret.
local function GetSecretClassColorRGB(classFile)
	local getter = C_ClassColor and C_ClassColor.GetClassColor
	if not getter then
		return
	end
	local c = getter(classFile)
	if not WhoaUF:CanAccessValue(c) or not c then
		return
	end
	return c.r, c.g, c.b
end

---------------------------------------------------------------------------
-- Health / reaction — Whoa color DB (final values)
---------------------------------------------------------------------------

local ReactionColors = {
	tapped = { r = 0.5, g = 0.5, b = 0.5 },
	disconnected = { r = 0.5, g = 0.5, b = 0.5 },
	default = { r = 0, g = 1, b = 0 }, -- Classic green when no class/react tint
	blue = { r = 0, g = 0.9, b = 0 }, -- ours (was Blizzard selection blue)
	[1] = { r = 0.8, g = 0.1, b = 0 },
	[2] = { r = 0.8, g = 0.1, b = 0 },
	[3] = { r = 0.9, g = 0.55, b = 0 },
	[4] = { r = 0.9, g = 0.75, b = 0 },
	[5] = { r = 0, g = 0.6, b = 0.1 },
	[6] = { r = 0, g = 0.6, b = 0.1 },
	[7] = { r = 0, g = 0.6, b = 0.1 },
	[8] = { r = 0, g = 0.6, b = 0.1 },
}
WhoaUF.ReactionColors = ReactionColors

--- reaction index → Whoa palette / FACTION_BAR_COLORS when useBlizz
function WhoaUF:GetReactionColor(reaction, useBlizz)
	local palette = useBlizz and FactionBarColors or ReactionColors
	return (reaction and palette[reaction]) or ReactionColors.blue
end

local function GetOption(key, default)
	local db = WhoaUF.db
	if not db then
		return default
	end
	-- Per-character color overrides when "Local colors" is checked.
	if (key == "classColor" or key == "npcColor"
		or key == "customHealthColor" or key == "customHealthColorPlayerOnly") and db.colorsLocal then
		local store = WhoaUF.GetCharColorStore and WhoaUF:GetCharColorStore(false)
		if store and store[key] ~= nil then
			return store[key]
		end
	end
	if db[key] == nil then
		return default
	end
	return db[key]
end

local function IsClassColorUnit(unit)
	if not unit or unit == "vehicle" then
		return false
	end
	if unit == "player" then
		return true
	end
	return UnitIsPlayer(unit)
end

local function NormalizeClassColorMode(value)
	if value == true then
		return "all"
	end
	if value == false then
		return "none"
	end
	if value == "all" or value == "player" or value == "target" or value == "none" or value == "chromatic" then
		return value
	end
	return "all"
end

local function ClassColorAppliesToUnit(mode, unit)
	mode = NormalizeClassColorMode(mode)
	-- "chromatic" is handled separately (local player cycle), not class tint.
	if mode == "none" or mode == "chromatic" or not IsClassColorUnit(unit) then
		return false
	end
	if mode == "player" then
		return unit == "player" or unit == "vehicle"
	end
	if mode == "target" then
		return unit ~= "player" and unit ~= "vehicle"
	end
	-- mode "all": class tint on every player/vehicle unit
	return true
end

local function NormalizeNpcColorMode(value)
	if value == "hostility" or value == "blizzard" or value == "chromatic" then
		return value
	end
	return "hostility"
end

--- Remap UnitSelectionColor to Whoa's softer hostility palette (legacy whoaUnitFrames).
local function RemapSelectionToWhoa(r, g, b)
	if r >= 0.9 and g >= 0.5 and g <= 0.6 and b == 0 then
		return r, g, b -- orange
	end
	if r >= 0.9 and g >= 0.9 and b == 0 then
		return 0.9, 0.75, 0 -- yellow
	end
	if r >= 0.9 and g == 0 and b == 0 then
		return 0.8, 0.1, 0 -- red
	end
	return 0, 0.6, 0.1 -- green / fallback
end

---------------------------------------------------------------------------
-- Secret values (Mainline Midnight+)
-- Bars accept secrets via SetValue/SetMinMaxValues. Lua must not compare,
-- arithmetic, coalesce (`or 0`), or concatenate them. Display via C APIs:
-- AbbreviateNumbers / BreakUpLargeNumbers / SetFormattedText / Unit*Percent.
---------------------------------------------------------------------------

function WhoaUF:CanAccessValue(value)
	if value == nil then
		return true
	end
	if canaccessvalue then
		local accessible = canaccessvalue(value)
		-- Never `if accessible then` — the API result itself may be secret.
		if issecretvalue and issecretvalue(accessible) then
			return false
		end
		return accessible and true or false
	end
	if issecretvalue then
		return not issecretvalue(value)
	end
	return true
end

function WhoaUF:IsSecretValue(value)
	if value == nil then
		return false
	end
	if issecretvalue then
		return issecretvalue(value) == true
	end
	return false
end

--- True when Lua must not operate on any of the values (use display-only APIs).
function WhoaUF:NeedsSecretSafeNumberOps(...)
	local n = select("#", ...)
	for i = 1, n do
		local value = select(i, ...)
		if value ~= nil and not self:CanAccessValue(value) then
			return true
		end
	end
	return false
end

--- Secret-safe inequality. Never use `==` / `~=` results directly in `if`.
--- Both inaccessible → treat as equal (unknown). Accessibility transition → unequal.
function WhoaUF:ValuesDiffer(a, b)
	local aOk = self:CanAccessValue(a)
	local bOk = self:CanAccessValue(b)
	if not aOk or not bOk then
		return aOk ~= bOk
	end
	local differ = a ~= b
	if not self:CanAccessValue(differ) then
		return false
	end
	if differ then
		return true
	end
	return false
end

--- Prefer UnitIsUnit; GUID equality only when both GUIDs are accessible.
function WhoaUF:UnitMatchesToken(unit, token)
	if unit == nil or token == nil then
		return false
	end
	if not self:CanAccessValue(unit) or not self:CanAccessValue(token) then
		return false
	end
	-- `==` / UnitIsUnit may return a secret boolean — never `if unit == token`.
	if self:IsAccessibleTrue(unit == token) then
		return true
	end
	if UnitIsUnit and self:IsAccessibleTrue(UnitIsUnit(unit, token)) then
		return true
	end
	if not UnitGUID then
		return false
	end
	local a, b = UnitGUID(unit), UnitGUID(token)
	if not self:CanAccessValue(a) or not self:CanAccessValue(b) then
		return false
	end
	return self:IsAccessibleTrue(a == b)
end

--- Secret booleans cannot be used in `if x then`. True only when accessible and truthy.
function WhoaUF:IsAccessibleTrue(value)
	if value == nil then
		return false
	end
	if not self:CanAccessValue(value) then
		return false
	end
	-- value is accessible here — safe to truth-test.
	if value then
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Unit auras (Mainline: prefer C_UnitAuras index APIs; never GetAuraSlots)
-- AuraUtil.ForEachAura → GetAuraSlots hard-errors when auras are secret while
-- tainted. Index queries work in open world with per-field secrets; skip when
-- encounter / M+ / PvP / instanced secrecy blocks tainted access.
---------------------------------------------------------------------------

function WhoaUF:AreUnitAuraQueriesRestricted()
	if not self:IsMainline() then
		return false
	end
	if IsEncounterInProgress and IsEncounterInProgress() then
		return true
	end
	if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
		return true
	end
	if C_PartyInfo and C_PartyInfo.ChallengeModeRestrictionsActive and C_PartyInfo.ChallengeModeRestrictionsActive() then
		return true
	end
	if C_PvP and C_PvP.IsMatchActive and C_PvP.IsMatchActive() then
		return true
	end
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
		local inInstance = IsInInstance and select(1, IsInInstance())
		if inInstance then
			return true
		end
	end
	return false
end

function WhoaUF:CanAccessTable(value)
	if value == nil then
		return true
	end
	if canaccesstable then
		return canaccesstable(value) and true or false
	end
	return not self:IsSecretValue(value)
end

--- AuraData → classic UnitAura returns (+ auraInstanceID). Nil when the table itself is inaccessible.
function WhoaUF:UnpackUnitAuraData(aura)
	if not aura or not self:CanAccessTable(aura) then
		return nil
	end
	if AuraUtil and AuraUtil.UnpackAuraData then
		local name, icon, count, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossAura, isFromPlayerOrPlayerPet, nameplateShowAll, timeMod =
			AuraUtil.UnpackAuraData(aura)
		return name,
			icon,
			count,
			dispelName,
			duration,
			expirationTime,
			sourceUnit,
			isStealable,
			nameplateShowPersonal,
			spellId,
			canApplyAura,
			isBossAura,
			isFromPlayerOrPlayerPet,
			nameplateShowAll,
			timeMod,
			aura.auraInstanceID
	end
	return aura.name,
		aura.icon,
		aura.applications,
		aura.dispelName,
		aura.duration,
		aura.expirationTime,
		aura.sourceUnit,
		aura.isStealable,
		aura.nameplateShowPersonal,
		aura.spellId,
		aura.canApplyAura,
		aura.isBossAura,
		aura.isFromPlayerOrPlayerPet,
		aura.nameplateShowAll,
		aura.timeMod,
		aura.auraInstanceID
end

--- Build filter string (AuraUtil when present).
function WhoaUF:CreateAuraFilterString(...)
	if AuraUtil and AuraUtil.CreateFilterString then
		return AuraUtil.CreateFilterString(...)
	end
	local n = select("#", ...)
	if n <= 0 then
		return "HELPFUL"
	end
	local parts = { ... }
	return table.concat(parts, "|")
end

--- Prefer C_UnitAuras.GetAuraDataByIndex. Returns false if queries are blocked.
--- callback(index, name, icon, count, dispelName, duration, expirationTime, sourceUnit,
---   isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossAura,
---   isFromPlayerOrPlayerPet, nameplateShowAll, timeMod, auraInstanceID) — return true to stop.
function WhoaUF:ForEachUnitAuraByIndex(unit, filter, maxCount, callback)
	if not unit or type(callback) ~= "function" then
		return false
	end
	if self:AreUnitAuraQueriesRestricted() then
		return false
	end
	maxCount = maxCount or 40
	filter = filter or "HELPFUL"

	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, maxCount do
			local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
			if not ok then
				return false
			end
			if not aura then
				break
			end
			local name, icon, count, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossAura, isFromPlayerOrPlayerPet, nameplateShowAll, timeMod, auraInstanceID =
				self:UnpackUnitAuraData(aura)
			if callback(
				i,
				name,
				icon,
				count,
				dispelName,
				duration,
				expirationTime,
				sourceUnit,
				isStealable,
				nameplateShowPersonal,
				spellId,
				canApplyAura,
				isBossAura,
				isFromPlayerOrPlayerPet,
				nameplateShowAll,
				timeMod,
				auraInstanceID
			) then
				break
			end
		end
		return true
	end

	local getter
	if type(filter) == "string" and string.find(filter, "HARMFUL", 1, true) then
		getter = UnitDebuff
	else
		getter = UnitBuff
	end
	if not getter then
		return false
	end
	for i = 1, maxCount do
		local name, icon, count, dispelName, duration, expirationTime, sourceUnit, isStealable, nameplateShowPersonal, spellId, canApplyAura, isBossAura, isFromPlayerOrPlayerPet, nameplateShowAll, timeMod =
			getter(unit, i, filter)
		if name == nil then
			break
		end
		if callback(
			i,
			name,
			icon,
			count,
			dispelName,
			duration,
			expirationTime,
			sourceUnit,
			isStealable,
			nameplateShowPersonal,
			spellId,
			canApplyAura,
			isBossAura,
			isFromPlayerOrPlayerPet,
			nameplateShowAll,
			timeMod,
			nil
		) then
			break
		end
	end
	return true
end

--- Normalize saved abbreviator: "whoa" | "numbers" | "large".
function WhoaUF:GetNumberAbbreviationMode()
	local mode = self.db and self.db.numberAbbreviation
	if mode == "whoa" or mode == "large" or mode == "numbers" then
		return mode
	end
	return self:GetDefaultNumberAbbreviationMode()
end

function WhoaUF:GetDefaultNumberAbbreviationMode()
	return self:IsMainline() and "numbers" or "whoa"
end

-- Classic whoaUnitFrames status abbreviate (Lua math — accessible values only).
local function FormatWhoaNumber(value)
	local k = 1e3
	local m = k * k
	if value > 1e3 and value < 1e5 then
		return format("%1.3f", value / k)
	elseif value >= 1e5 and value < 1e6 then
		return format("%1.0f K", value / k)
	elseif value >= 1e6 and value < 1e9 then
		return format("%1.2f M", value / m)
	elseif value >= 1e9 then
		return format("%1.1f M", value / m)
	end
	return tostring(value)
end

local function FormatBlizzardAbbreviated(value, preferLarge)
	if preferLarge then
		if AbbreviateLargeNumbers then
			return AbbreviateLargeNumbers(value)
		end
		if AbbreviateNumbers then
			return AbbreviateNumbers(value)
		end
	else
		if AbbreviateNumbers then
			return AbbreviateNumbers(value)
		end
		if AbbreviateLargeNumbers then
			return AbbreviateLargeNumbers(value)
		end
	end
	return nil
end

--- Format a combat number for FontString args. C abbreviators accept secrets;
--- Whoa mode uses Lua math and falls back to AbbreviateNumbers when secret.
function WhoaUF:FormatStatusNumber(value, abbreviate)
	if value == nil then
		return ""
	end
	if abbreviate then
		local mode = self:GetNumberAbbreviationMode()
		if mode == "whoa" then
			if self:CanAccessValue(value) then
				return FormatWhoaNumber(value)
			end
			-- Secret value: AbbreviateNumbers instead of Lua math.
			return FormatBlizzardAbbreviated(value, false) or value
		end
		local formatted = FormatBlizzardAbbreviated(value, mode == "large")
		if formatted ~= nil then
			return formatted
		end
	elseif BreakUpLargeNumbers then
		return BreakUpLargeNumbers(value)
	elseif AbbreviateLargeNumbers then
		return AbbreviateLargeNumbers(value)
	end
	if self:CanAccessValue(value) then
		return tostring(value)
	end
	return value
end

--- Health/power percent scaled 0–100 when CurveConstants is present; else accessible math.
function WhoaUF:GetUnitStatusPercent(unit, powerType)
	if not unit then
		return nil
	end
	local scale = CurveConstants and CurveConstants.ScaleTo100
	if powerType ~= nil then
		if UnitPowerPercent and scale then
			return UnitPowerPercent(unit, powerType, false, scale)
		end
		return nil
	end
	if UnitHealthPercent and scale then
		return UnitHealthPercent(unit, true, scale)
	end
	return nil
end

--- True when UnitHealth/Max are percentage-scaled (or secret), not absolute HP.
--- Classic stock UI also forces % via ShouldKnowUnitHealth for "period authenticity"
--- even when UnitHealthMax returns absolute NPC HP (post-2020 API). Whoa must NOT
--- use ShouldKnowUnitHealth for that — trust the API: absolute when max ~= 100.
--- Reference: Blizzard_UnitFrame/Classic/UnitFrame.lua UnitFrameHealthBar_Update
function WhoaUF:ShouldDisplayHealthAsPercentage(unit)
	if not unit or not UnitExists(unit) then
		return false
	end

	if ShouldUnitHealthMaxBeSecret and ShouldUnitHealthMaxBeSecret(unit) then
		return true
	end

	local maxValue = UnitHealthMax(unit)
	if not self:CanAccessValue(maxValue) then
		return true
	end

	-- Client scales enemy players (and similar) to 0–100; NPCs usually return absolute.
	return maxValue == 100
end

--- Hue 0–1, full sat/value → RGB around the chromatic circle (no table alloc).
local function HSVtoRGB(h, s, v)
	if s <= 0 then
		return v, v, v
	end
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local t = v * (1 - s * (1 - f))
	if i == 0 then
		return v, t, p
	elseif i == 1 then
		return q, v, p
	elseif i == 2 then
		return p, v, t
	elseif i == 3 then
		return p, q, v
	elseif i == 4 then
		return t, p, v
	end
	return v, p, q
end

-- Chromatic cycle runtime (no DB reads / tostring on the tick path).
local cycleHealthActive = false
local cycleHealthTintPlayer = false
local cycleHealthTintNpc = false
local cycleHealthRate = 0.2
local cycleHealthR, cycleHealthG, cycleHealthB = 0, 1, 0

-- Custom / chromatic apply to these units only (never party or boss).
local SPECIAL_HEALTH_UNITS_ALL = {
	player = true,
	vehicle = true,
	target = true,
	focus = true,
	targettarget = true,
	focustarget = true,
	pet = true,
}

--- Whether custom/chromatic tint may apply to this unit token.
function WhoaUF:UnitAllowsSpecialHealthColor(unit, playerOnly)
	if not unit then
		return false
	end
	if playerOnly then
		return unit == "player" or unit == "vehicle"
	end
	return SPECIAL_HEALTH_UNITS_ALL[unit] and true or false
end

--- Revolutions/sec from saved speed 1–20 (slow → fast). Default 4 ≈ 5s per loop.
function WhoaUF:GetHealthColorCycleRate()
	local speed = self.db and self.db.healthColorCycleSpeed
	if type(speed) ~= "number" then
		speed = 4
	elseif speed < 1 then
		speed = 1
	elseif speed > 20 then
		speed = 20
	end
	return speed * 0.05
end

--- Cache enable + rate + which surfaces tint when options / driver change (not every frame).
--- tintPlayer: local player/vehicle. tintNpc: non-player units on special frames.
function WhoaUF:SetHealthColorCycleRuntime(active, rate, tintPlayer, tintNpc)
	cycleHealthActive = active and true or false
	cycleHealthTintPlayer = tintPlayer and true or false
	cycleHealthTintNpc = tintNpc and true or false
	if type(rate) == "number" and rate > 0 then
		cycleHealthRate = rate
	else
		cycleHealthRate = self:GetHealthColorCycleRate()
	end
end

function WhoaUF:IsHealthColorCycleActive()
	return cycleHealthActive
end

function WhoaUF:IsHealthColorCycleTintPlayer()
	return cycleHealthTintPlayer
end

function WhoaUF:IsHealthColorCycleTintNpc()
	return cycleHealthTintNpc
end

--- Advance hue once per tick; returns r, g, b (no tables). No-op when cycle is off.
function WhoaUF:AdvanceHealthColorCycle()
	if not cycleHealthActive then
		return cycleHealthR, cycleHealthG, cycleHealthB
	end
	cycleHealthR, cycleHealthG, cycleHealthB = HSVtoRGB(GetTime() * cycleHealthRate, 1, 1)
	return cycleHealthR, cycleHealthG, cycleHealthB
end

--- Current chromatic-circle RGB (last advanced sample).
function WhoaUF:GetCycleHealthBarColor()
	return cycleHealthR, cycleHealthG, cycleHealthB
end

--- Sample chromatic RGB (runtime cache while driver runs; otherwise live HSV).
local function SampleChromaticRGB()
	if cycleHealthActive then
		return cycleHealthR, cycleHealthG, cycleHealthB
	end
	return HSVtoRGB(GetTime() * WhoaUF:GetHealthColorCycleRate(), 1, 1)
end

--- Health + name-background tint.
--- player chromatic → local player; NPC chromatic → NPCs; custom → picker; else class / hostility.
--- Returns nil when no tint option applies (caller uses Classic green).
function WhoaUF:GetHealthBarColor(unit)
	if not unit then
		return
	end

	local classMode = NormalizeClassColorMode(GetOption("classColor", "all"))
	local npcMode = NormalizeNpcColorMode(GetOption("npcColor", "hostility"))
	local isLocalPlayer = unit == "player" or unit == "vehicle"
	local isPlayerUnit = isLocalPlayer or UnitIsPlayer(unit)

	-- Independent chromatic: player option owns local player; NPC option owns non-players.
	if isLocalPlayer and classMode == "chromatic" then
		return SampleChromaticRGB()
	end
	if not isPlayerUnit and npcMode == "chromatic" then
		return SampleChromaticRGB()
	end

	if GetOption("customHealthColor", false)
		and self:UnitAllowsSpecialHealthColor(unit, GetOption("customHealthColorPlayerOnly", false))
		and self.GetHealthBarCustomColor then
		local c = self:GetHealthBarCustomColor()
		if c then
			return c.r, c.g, c.b
		end
	end

	if ClassColorAppliesToUnit(classMode, unit) then
		local _, classFile = UnitClass(unit)
		if not self:CanAccessValue(classFile) then
			-- UNKNOWN is white; never paint that for a hidden class (nil → Classic green).
			return GetSecretClassColorRGB(classFile)
		end
		local c = self:GetClassColor(classFile)
		return c.r, c.g, c.b
	end

	-- Players without class tint keep Classic green (npc modes do not apply).
	if isPlayerUnit then
		return
	end

	local r, g, b
	if UnitIsTapDenied(unit) then
		local c = ReactionColors.tapped
		r, g, b = c.r, c.g, c.b
	elseif UnitIsCivilian and UnitIsCivilian(unit) then
		r, g, b = 1, 1, 1
	else
		r, g, b = UnitSelectionColor(unit)
		-- Mainline: selection RGB may be secret — skip remap math, use defaults.
		if self:NeedsSecretSafeNumberOps(r, g, b) then
			local c = ReactionColors.default
			return c.r, c.g, c.b
		end
		r, g, b = r or 0, g or 0, b or 0
		-- Friendly selection blue → green (even with Blizzard selection colors).
		if b >= 0.9 then
			g, b = 0.9, 0
		end
		if npcMode ~= "blizzard" then
			r, g, b = RemapSelectionToWhoa(r, g, b)
		end
	end
	return r, g, b
end

---------------------------------------------------------------------------
-- Client flavor (Retail, Classic Era, TBC Classic, …)
---------------------------------------------------------------------------

function WhoaUF:IsMainline()
	return WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
end

-- WoW Forever (Camelot / _forever_): Interface 16001, WOW_PROJECT_CAMELOT = 18.
-- Classic content, retail-style addon restrictions (no CLEU, secret Unit*).
function WhoaUF:IsCamelot()
	if WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then
		return true
	end
	local timing = self.Timing
	if timing and timing.isCamelot then
		return true
	end
	local _, _, _, interfaceVersion = GetBuildInfo()
	local toc = tonumber(interfaceVersion) or 0
	return toc >= 16000 and toc < 20000
end

function WhoaUF:IsClassicClient()
	return not self:IsMainline() and not self:IsCamelot()
end

---------------------------------------------------------------------------
-- Mainline build APIs (live retail vs PTR / 12.1.5+)
-- Both are WOW_PROJECT_MAINLINE. Gate by capability; keep retail-safe fallbacks.
-- See .cursor/rules/whoa-unitframes.mdc ("Mainline builds: live retail vs PTR").
---------------------------------------------------------------------------

-- Reused across PvP / role updates — never allocate in the hot path.
local ufPvPElements = { pvpIcon = nil }
local ufPvPTextureMap = {
	pvpIconFreeForAll = nil,
	pvpIconHorde = nil,
	pvpIconAlliance = nil,
}
local ufRoleProxy = {
	roleIcon = nil,
	unit = nil,
	optionTable = {
		displayRoleIcon = true,
		displayRaidRoleIcon = false,
	},
}

--- Secret-safe PvP icon via UnitFrameUtil (12.1.5+). Returns false on live retail.
--- Prefer Whoa Media UI-PVP-* when flags are readable (call sites); use this only when secret.
--- Prestige portrait/badge use client atlases / badgeFileDataID when Whoa wires those widgets.
--- ffa / alliance / horde are optional texture paths or atlases for textureMap overrides.
function WhoaUF:TryUpdateUnitPvPIndicator(pvpIcon, unit, checkMercenary, ffa, alliance, horde)
	if not pvpIcon or not unit then
		return false
	end
	if not (UnitFrameUtil and UnitFrameUtil.UpdateUnitPvPIndicator) then
		return false
	end

	ufPvPElements.pvpIcon = pvpIcon
	ufPvPTextureMap.pvpIconFreeForAll = ffa
	ufPvPTextureMap.pvpIconHorde = horde
	ufPvPTextureMap.pvpIconAlliance = alliance

	local textureMap = (ffa or alliance or horde) and ufPvPTextureMap or nil
	UnitFrameUtil.UpdateUnitPvPIndicator(ufPvPElements, unit, checkMercenary and true or false, textureMap)

	ufPvPElements.pvpIcon = nil
	ufPvPTextureMap.pvpIconFreeForAll = nil
	ufPvPTextureMap.pvpIconHorde = nil
	ufPvPTextureMap.pvpIconAlliance = nil
	return true
end

--- Secret-safe role icon via UnitFrameUtil (12.1.5+). Returns false on live retail.
--- Prefer Whoa Media UI-LFG-ICON-PORTRAITROLES + texcoords when role is readable (call sites);
--- this path uses Blizzard CUF role atlases because the sheet cannot be cropped without the role string.
function WhoaUF:TryUpdateUnitRoleIcon(roleIcon, unit, displayRaidRoleIcon)
	if not roleIcon or not unit then
		return false
	end
	if not (UnitFrameUtil and UnitFrameUtil.UpdateUnitFrameRoleIcon) then
		return false
	end

	ufRoleProxy.roleIcon = roleIcon
	ufRoleProxy.unit = unit
	ufRoleProxy.optionTable.displayRoleIcon = true
	ufRoleProxy.optionTable.displayRaidRoleIcon = displayRaidRoleIcon and true or false

	UnitFrameUtil.UpdateUnitFrameRoleIcon(ufRoleProxy)

	ufRoleProxy.roleIcon = nil
	ufRoleProxy.unit = nil
	return true
end

---------------------------------------------------------------------------
-- Client standards (do not mix)
-- Classic: absolute Unit* values, index aura paint, Lua status math.
-- Mainline: secret-safe SetValue / display APIs; same aura/status writers with
-- AbbreviateNumbers, SetCooldownFromExpirationTime, Unit*Percent, etc.
-- Gate features with these helpers — never "Classic path + secret ifs" on retail.
---------------------------------------------------------------------------

--- True when UnitHealth/Power/auras may be secrets and Lua ops are unsafe.
function WhoaUF:UsesSecretValues()
	return self:IsMainline() or self:IsCamelot()
end

--- Index aura paint (GetAuraDataByIndex / ForEachUnitAuraByIndex).
--- Classic and Mainline both use this; Mainline paint is secret-safe and still
--- respects AreUnitAuraQueriesRestricted.
function WhoaUF:UsesClassicAuraPaint()
	return true
end

--- Classic: Lua-math status formatting. Mainline uses the same writer with
--- Unit*Percent / AbbreviateNumbers instead (see WriteStatusBarText).
function WhoaUF:UsesClassicStatusNumbers()
	return self:IsClassicClient()
end

--- Classic: snap bar fill via min/max compare; Mainline: SetValue only (no compare).
function WhoaUF:UsesClassicStatusBarSnap()
	return self:IsClassicClient()
end

local function ClassicAtLeast(expansion)
	if not expansion then
		return false
	end
	if ClassicExpansionAtLeast then
		return ClassicExpansionAtLeast(expansion)
	end
	if GetClassicExpansionLevel then
		return GetClassicExpansionLevel() >= expansion
	end
	return false
end

local function ClassicAtMost(expansion)
	if not expansion then
		return false
	end
	if ClassicExpansionAtMost then
		return ClassicExpansionAtMost(expansion)
	end
	if GetClassicExpansionLevel then
		return GetClassicExpansionLevel() <= expansion
	end
	return false
end

--- Live features that exist on Mainline and from the matching Classic expansion.
function WhoaUF:HasDeathKnight()
	return self:IsMainline() or ClassicAtLeast(LE_EXPANSION_WRATH_OF_THE_LICH_KING)
end

function WhoaUF:HasRunes()
	return self:HasDeathKnight()
end

-- DK Alpha / BlizzCon player chrome media + module. Forever has no DK class, but
-- loads the same art for the warrior specialty exception (see IsDkSpecialtyPlayerArtEligible).
function WhoaUF:CanUseDkSpecialtyPlayerArt()
	return self:HasDeathKnight() or self:IsCamelot()
end

-- Who may pick Alpha / BlizzCon in Player frame: real DKs, or Forever warriors.
function WhoaUF:IsDkSpecialtyPlayerArtEligible()
	local _, class = UnitClass("player")
	if class == "DEATHKNIGHT" then
		return true
	end
	return self:IsCamelot() and class == "WARRIOR"
end

function WhoaUF:HasTotemFrame()
	-- Blizzard TotemFrame loads from TBC Classic onward (not Era).
	return self:IsMainline() or ClassicAtLeast(LE_EXPANSION_BURNING_CRUSADE)
end

function WhoaUF:HasBossFrames()
	-- Whoa boss1–5 not shipped (stub false); stock BossTargetFrame* stays unmuted.
	-- Re-enable: return self:IsMainline() or ClassicAtLeast(LE_EXPANSION_WRATH_OF_THE_LICH_KING)
	return false
end

function WhoaUF:HasMonkChi()
	return self:IsMainline() or ClassicAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA)
end

function WhoaUF:HasMonkStagger()
	return self:HasMonkChi()
end

function WhoaUF:HasAlternateMana()
	return self:IsMainline() or ClassicAtLeast(LE_EXPANSION_WRATH_OF_THE_LICH_KING)
end

function WhoaUF:HasHolyPower()
	return self:IsMainline() or ClassicAtLeast(LE_EXPANSION_CATACLYSM)
end

function WhoaUF:HasSoulShards()
	return self:IsMainline() or ClassicAtLeast(LE_EXPANSION_CATACLYSM)
end

function WhoaUF:HasPlayerComboPointBar()
	-- Player-rim combo tray (Legion ComboPointPlayerFrame). Available on all
	-- clients; Classic falls back to ComboPoint.blp when ComboPoints-* atlases
	-- are missing. Target ComboFrame stays separate (Frames/ComboPoints.lua).
	return true
end

function WhoaUF:HasClassPowerBarFramework()
	-- ClassPowerBar + ClassResourceBar mixins (Mainline class-resource trays).
	return self:IsMainline()
end

function WhoaUF:HasUntypedRunes()
	-- Retail (and post-typed Classic) runes: no GetRuneType / all runes identical.
	return self:IsMainline() or not GetRuneType
end

function WhoaUF:HasTypedRunes()
	return self:IsClassicClient() and GetRuneType ~= nil
end

--- Classic-only mechanics (false on Mainline).
function WhoaUF:HasEclipseBar()
	return self:IsClassicClient() and ClassicAtLeast(LE_EXPANSION_CATACLYSM)
end

function WhoaUF:HasShadowOrbs()
	return self:IsClassicClient() and ClassicAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA)
end

function WhoaUF:HasMoPWarlockPower()
	return self:IsClassicClient() and ClassicAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA)
end

function WhoaUF:HasMoPArt()
	return self:IsMainline() or ClassicAtLeast(LE_EXPANSION_MISTS_OF_PANDARIA)
end

function WhoaUF:IsWrathTypedRuneLayout()
	return self:IsClassicClient()
		and LE_EXPANSION_WRATH_OF_THE_LICH_KING
		and ClassicAtMost(LE_EXPANSION_WRATH_OF_THE_LICH_KING)
end

-- Display name + toast tint key. Keep in sync with docs/expansion-colors.md.
function WhoaUF:GetClientFlavor()
	if self:IsMainline() then
		return "Retail"
	end
	if self:IsCamelot() then
		return "Forever"
	end
	local _, _, _, interfaceVersion = GetBuildInfo()
	interfaceVersion = tonumber(interfaceVersion) or 0
	-- Live Classic clients only (Era / TBC Anniversary / Mists).
	if interfaceVersion >= 50500 then
		return "Mists Classic"
	end
	if interfaceVersion >= 20500 then
		return "TBC Classic"
	end
	-- Classic Era seasons share the same project / TOC band.
	if C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() then
		return "Hardcore"
	end
	local season = C_Seasons and C_Seasons.GetActiveSeason and C_Seasons.GetActiveSeason()
	local sod = Enum and Enum.SeasonID and Enum.SeasonID.SeasonOfDiscovery
	if season and ((sod and season == sod) or season == 2) then
		return "Season of Discovery"
	end
	return "Classic Era"
end

function WhoaUF:IsClassicEraClient()
	-- Forever is Classic Era content (no focus unit) on a restricted binary.
	if self:IsCamelot() then
		return true
	end
	if self:IsMainline() then
		return false
	end
	if WOW_PROJECT_CLASSIC and WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
		return true
	end
	local _, _, _, interfaceVersion = GetBuildInfo()
	interfaceVersion = tonumber(interfaceVersion) or 0
	return interfaceVersion > 0 and interfaceVersion < 20000
end

-- Focus unit/frame exists from TBC Classic onward, not on vanilla Classic Era / Forever.
-- Mainline always has focus.
function WhoaUF:HasFocusUnit()
	return self:IsMainline() or not self:IsClassicEraClient()
end

function WhoaUF:HasEditModeFocusSupport()
	return self:HasFocusUnit()
end

-- RGB 0–1. Source of truth: docs/expansion-colors.md.
local CLIENT_FLAVOR_COLORS = {
	["Classic Era"] = { r = 0x00 / 255, g = 0x70 / 255, b = 0xDD / 255 }, -- rare blue
	["Hardcore"] = { r = 0xC4 / 255, g = 0x1E / 255, b = 0x3A / 255 },
	["Season of Discovery"] = { r = 0xE8 / 255, g = 0xA8 / 255, b = 0x38 / 255 },
	["TBC Classic"] = { r = 0x4A / 255, g = 0xE3 / 255, b = 0x4A / 255 },
	["Mists Classic"] = { r = 0x2E / 255, g = 0xBD / 255, b = 0x85 / 255 },
	["Retail"] = { r = 0x5B / 255, g = 0x4B / 255, b = 0xDB / 255 }, -- Midnight
	["Forever"] = { r = 0x3D / 255, g = 0xB8 / 255, b = 0xD1 / 255 },
}

function WhoaUF:GetClientFlavorColor()
	local color = CLIENT_FLAVOR_COLORS[self:GetClientFlavor()]
	if color then
		return color.r, color.g, color.b
	end
end

---------------------------------------------------------------------------
-- Toast text colors (game globals / stock UI only)
---------------------------------------------------------------------------

function WhoaUF:ColorEscape(r, g, b, text)
	if r == nil or g == nil or b == nil then
		return text or ""
	end
	return string.format(
		"|cff%02x%02x%02x%s|r",
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5),
		text or ""
	)
end

function WhoaUF:GetColorFromColorCode(code)
	if type(code) ~= "string" then
		return
	end
	local hex = code:match("|cff(%x%x%x%x%x%x)")
	if not hex then
		return
	end
	return tonumber(hex:sub(1, 2), 16) / 255,
		tonumber(hex:sub(3, 4), 16) / 255,
		tonumber(hex:sub(5, 6), 16) / 255
end

function WhoaUF:ResolveColor(...)
	for i = 1, select("#", ...) do
		local src = select(i, ...)
		local r, g, b
		if type(src) == "function" then
			r, g, b = src()
		elseif type(src) == "table" then
			if src.r ~= nil then
				r, g, b = src.r, src.g, src.b
			elseif src.GetRGB then
				r, g, b = src:GetRGB()
			elseif src.GetRGBA then
				r, g, b = src:GetRGBA()
			end
		elseif type(src) == "userdata" then
			if src.GetTextColor then
				r, g, b = src:GetTextColor()
			elseif src.GetVertexColor then
				r, g, b = src:GetVertexColor()
			end
		end
		if r ~= nil and g ~= nil and b ~= nil then
			return r, g, b
		end
	end
end

function WhoaUF:GetToastBodyColor()
	return self:ResolveColor(
		FRIENDS_GRAY_COLOR,
		function()
			local stock = BNToastFrame and BNToastFrame.BottomLine
			if stock then
				return stock:GetTextColor()
			end
		end,
		GRAY_FONT_COLOR
	)
end

function WhoaUF:GetToastBNetNameColor()
	return self:ResolveColor(FRIENDS_BNET_NAME_COLOR, function()
		return self:GetToastBodyColor()
	end)
end

function WhoaUF:GetToastWhiteColor()
	return self:ResolveColor(WHITE_FONT_COLOR, HIGHLIGHT_FONT_COLOR, function()
		return self:GetToastBodyColor()
	end)
end

function WhoaUF:GetToastVersionColor()
	return self:ResolveColor(FRIENDS_WOW_NAME_COLOR, function()
		return self:GetToastBodyColor()
	end)
end

function WhoaUF:GetToastBroadcastTimeColor()
	return self:ResolveColor(function()
		return self:GetColorFromColorCode(FRIENDS_BROADCAST_TIME_COLOR_CODE)
	end, function()
		return self:GetToastBodyColor()
	end)
end

function WhoaUF:GetToastClientColor()
	return self:ResolveColor(function()
		return self:GetClientFlavorColor()
	end, function()
		return self:GetToastBodyColor()
	end)
end
