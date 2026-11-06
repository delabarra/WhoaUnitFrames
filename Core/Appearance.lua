--[[
	Appearance: status-bar textures, aura size, frame scale, name background, apply health colors.
	Color DB lives in Util.lua (ClassColors / PowerBarColor / …).
	Health tint applies to Whoa unit frames only (no Blizzard/nameplate hooks).
]]

local ADDON_NAME = ...
local ADDON_MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
-- Layout: Media\{classic|whoa|thick}\{light|dark}\ + Media\dk\{light|dark}\
--          + Media\shared\{light|dark|statusbar} + Media\shared\{light|dark}\castingbar
--            (Border / Border-Small / Small-Shield; light full Border uses client sheet;
--             SpellbarArt_Classic also skins MirrorTimer1–3 breath/fatigue chrome)
-- Pin addon art to this pack's .blp. Extensionless SetTexture can resolve a
-- neighboring .png (editor export) or another addon's same-named sheet.
local function AddonBlp(path)
	if type(path) ~= "string" or path == "" then
		return path
	end
	if path:sub(-4):lower() == ".blp" then
		return path
	end
	return path .. ".blp"
end
local STATUSBAR_MEDIA = ADDON_MEDIA .. "shared\\statusbar\\"
local CLASS_POWER_MEDIA = ADDON_MEDIA .. "shared\\dark\\classpower\\"

local STATUSBAR_TEXTURES = {
	"65",
	"Aluminium",
	"Armory",
	"BantoBar",
	"Bars",
	"blizzard",
	"Bumps",
	"Charcoal",
	"Cilo",
	"Cloud",
	"Comet",
	"Dabs",
	"DarkBottom",
	"Diagonal",
	"Falumn",
	"Fifths",
	"Flat",
	"Fourths",
	"Frost",
	"Glass",
	"Glaze",
	"Glaze2",
	"Gloss",
	"Graphite",
	"Grid",
	"Hatched",
	"Healbot",
	"LiteStep",
	"LiteStepLite",
	"Lyfe",
	"Melli",
	"MelliDark",
	"Minimalist",
	"Otravi",
	"Outline",
	"Perl",
	"Perl2",
	"Pill",
	"Rain",
	"Rocks",
	"Round",
	"Ruben",
	"Runes",
	"shiny",
	"Skewed",
	"Smooth",
	"Smoothv2",
	"Smudge",
	"Steel",
	"Striped",
	"Tube",
	"Water",
	"whoa",
	"Wisps",
	"Xeon",
}

local STATUSBAR_LABELS = {
	["65"] = "65",
	Aluminium = "Aluminium",
	Armory = "Armory",
	BantoBar = "Banto Bar",
	Bars = "Bars",
	blizzard = "Blizzard",
	Bumps = "Bumps",
	Charcoal = "Charcoal",
	Cilo = "Cilo",
	Cloud = "Cloud",
	Comet = "Comet",
	Dabs = "Dabs",
	DarkBottom = "Dark Bottom",
	Diagonal = "Diagonal",
	Falumn = "Falumn",
	Fifths = "Fifths",
	Flat = "Flat",
	Fourths = "Fourths",
	Frost = "Frost",
	Glass = "Glass",
	Glaze = "Glaze",
	Glaze2 = "Glaze 2",
	Gloss = "Gloss",
	Graphite = "Graphite",
	Grid = "Grid",
	Hatched = "Hatched",
	Healbot = "Healbot",
	LiteStep = "Lite Step",
	LiteStepLite = "Lite Step Lite",
	Lyfe = "Lyfe",
	Melli = "Melli",
	MelliDark = "Melli Dark",
	Minimalist = "Minimalist",
	Otravi = "Otravi",
	Outline = "Outline",
	Perl = "Perl",
	Perl2 = "Perl 2",
	Pill = "Pill",
	Rain = "Rain",
	Rocks = "Rocks",
	Round = "Round",
	Ruben = "Ruben",
	Runes = "Runes",
	shiny = "Shiny",
	Skewed = "Skewed",
	Smooth = "Smooth",
	Smoothv2 = "Smooth v2",
	Smudge = "Smudge",
	Steel = "Steel",
	Striped = "Striped",
	Tube = "Tube",
	Water = "Water",
	whoa = "Whoa",
	Wisps = "Wisps",
	Xeon = "Xeon",
}

local AURA_BUFF_SIZE = 21
local AURA_DEBUFF_SIZE = 17
local AURA_TOT_SIZE = 12
local AURA_MIN_SIZE = 12
local AURA_MAX_SIZE = 73
local AURA_SPACING = 3
local AURA_MAX_PER_ROW = 1
local AURA_ROW_WIDTH = 122
local AURA_START_Y = 28
local AURA_OFFSET_Y = 1
local TOT_BOTTOM_Y = -14
local DEFAULT_NUM_TOT_AURA_ROWS = 2

-- Prebuilt paths — avoid `..` when applying textures / reading options.
local STATUSBAR_PATHS = {}
for i = 1, #STATUSBAR_TEXTURES do
	local key = STATUSBAR_TEXTURES[i]
	STATUSBAR_PATHS[key] = AddonBlp(STATUSBAR_MEDIA .. key)
end

local NAME_BG_FRAMES = { "player", "target", "focus" }

-- Cached appearance values (invalidated when the matching option changes).
local cachedStatusBarKey
local cachedStatusBarPath
local cachedAuraLarge
local cachedAuraSmall
local cachedAuraTot
local cachedAuraOptSize
local cachedTotAuraRows

local function GetOption(key, default)
	local db = WhoaUF.db
	if not db or db[key] == nil then
		return default
	end
	return db[key]
end

local function NormalizeStatusBarKey(key)
	if not key or key == "" then
		return "blizzard"
	end
	return key
end

local function InvalidateStatusBarPathCache()
	cachedStatusBarKey = nil
	cachedStatusBarPath = nil
end

local function InvalidateAuraSizeCache()
	cachedAuraLarge = nil
	cachedAuraSmall = nil
	cachedAuraTot = nil
	cachedAuraOptSize = nil
	cachedTotAuraRows = nil
end

function WhoaUF:GetStatusBarTextureOptions()
	return STATUSBAR_TEXTURES, STATUSBAR_LABELS
end

---------------------------------------------------------------------------
-- Status-bar text: one preset (ThickFrames retail + classic sizes / mono).
---------------------------------------------------------------------------

local STATUSBAR_FONTS = {
	"retail",
	"retailBig",
	"retailHuge",
	"classicSmall",
	"classic",
	"classicBig",
	"mono",
}
local STATUSBAR_FONT_LABELS = {
	retail = "Retail",
	retailBig = "Retail Big",
	retailHuge = "Retail Huge",
	classicSmall = "Classic Small",
	classic = "Classic",
	classicBig = "Classic Big",
	mono = "Mono",
}

local STATUSBAR_FONT_FILES = {
	friz = {
		ruRU = "Fonts\\FRIZQT___CYR.TTF",
		koKR = "Fonts\\2002.TTF",
		zhCN = "Fonts\\ARKai_T.ttf",
		zhTW = "Fonts\\bKAI00M.TTF",
		default = "Fonts\\FRIZQT__.TTF",
	},
	arialn = {
		koKR = "Fonts\\2002.TTF",
		zhCN = "Fonts\\ARHei.ttf",
		zhTW = "Fonts\\bHEI01B.TTF",
		default = "Fonts\\ARIALN.TTF",
	},
}

-- SystemFont_Outline_Small / Outline / Game15Font_o1 / Number12 / TextStatusBarText / Outline_Large / Mono.
local STATUSBAR_FONT_PRESETS = {
	retail = { face = "friz", height = 10, flags = "OUTLINE" },
	retailBig = { face = "friz", height = 13, flags = "OUTLINE" },
	retailHuge = { face = "friz", height = 15, flags = "OUTLINE" },
	classicSmall = { face = "arialn", height = 12, flags = "OUTLINE" },
	classic = { face = "arialn", height = 14, flags = "OUTLINE" },
	classicBig = { face = "arialn", height = 16, flags = "OUTLINE" },
	mono = { face = "arialn", height = 12, flags = "THICKOUTLINE,MONOCHROME" },
}

local cachedStatusBarFontKey
local cachedStatusBarFontPath
local cachedStatusBarFontLocale
local cachedStatusBarFontFace

local function NormalizeStatusBarFontKey(key)
	if STATUSBAR_FONT_PRESETS[key] then
		return key
	end
	return "retail"
end

local function InvalidateStatusBarFontCache()
	cachedStatusBarFontKey = nil
	cachedStatusBarFontPath = nil
	cachedStatusBarFontLocale = nil
	cachedStatusBarFontFace = nil
end

function WhoaUF:MigrateStatusBarFontOptions(db)
	if not db then
		return
	end
	local font = db.statusBarFont
	local style = db.statusBarFontStyle
	if STATUSBAR_FONT_PRESETS[font] then
		db.statusBarFontStyle = nil
		return
	end
	if font == "friz" then
		if style == "small" then
			db.statusBarFont = "retail"
		elseif style == "large" then
			db.statusBarFont = "retailHuge"
		elseif style == "mono" then
			db.statusBarFont = "mono"
		else
			db.statusBarFont = "retailBig"
		end
	elseif style == "small" then
		db.statusBarFont = "classicSmall"
	elseif style == "large" then
		db.statusBarFont = "classicBig"
	elseif style == "mono" then
		db.statusBarFont = "mono"
	else
		db.statusBarFont = "classic"
	end
	db.statusBarFontStyle = nil
end

function WhoaUF:GetStatusBarFontOptions()
	return STATUSBAR_FONTS, STATUSBAR_FONT_LABELS
end

function WhoaUF:GetStatusBarFontTextOffset()
	if NormalizeStatusBarFontKey(GetOption("statusBarFont", "retail")) == "mono" then
		return -1
	end
	return 0
end

local function GetStatusBarFontPath(face)
	local locale = GetLocale and GetLocale() or "enUS"
	if cachedStatusBarFontFace == face and cachedStatusBarFontLocale == locale and cachedStatusBarFontPath then
		return cachedStatusBarFontPath
	end
	local files = STATUSBAR_FONT_FILES[face] or STATUSBAR_FONT_FILES.arialn
	local path = files[locale] or files.default
	cachedStatusBarFontFace = face
	cachedStatusBarFontLocale = locale
	cachedStatusBarFontPath = path
	return path
end

local function GetStatusBarFontPreset()
	local key = NormalizeStatusBarFontKey(GetOption("statusBarFont", "retail"))
	local preset = STATUSBAR_FONT_PRESETS[key]
	if cachedStatusBarFontKey == key and cachedStatusBarFontPath then
		return key, cachedStatusBarFontPath, preset
	end
	cachedStatusBarFontKey = key
	return key, GetStatusBarFontPath(preset.face), preset
end

function WhoaUF:ApplyStatusBarTextFont(fs)
	if not fs or not fs.SetFont then
		return
	end
	local key, path, preset = GetStatusBarFontPreset()
	if fs.whoaBarFont == key then
		return
	end
	if path and preset then
		fs:SetFont(path, preset.height, preset.flags)
	end
	fs.whoaBarFont = key
end

local function ApplyBarTextFonts(bar)
	if not bar then
		return
	end
	WhoaUF:ApplyStatusBarTextFont(bar.TextString)
	WhoaUF:ApplyStatusBarTextFont(bar.LeftText)
	WhoaUF:ApplyStatusBarTextFont(bar.RightText)
	WhoaUF:ApplyStatusBarTextFont(bar.StockText)
	WhoaUF:ApplyStatusBarTextFont(bar.StackedCenter)
	WhoaUF:ApplyStatusBarTextFont(bar.StackedLeft)
	WhoaUF:ApplyStatusBarTextFont(bar.StackedRight)
end

-- Dead / Ghost / Unconscious / Offline labels stay on stock GameFontNormalSmall.
local function RestoreLifeStatusLabelFont(fs)
	if not fs or not fs.SetFontObject then
		return
	end
	if GameFontNormalSmall then
		fs:SetFontObject(GameFontNormalSmall)
	end
	fs.whoaBarFont = nil
end

function WhoaUF:ApplyStatusBarFonts()
	InvalidateStatusBarFontCache()
	local uf = self.unitFrames
	if not uf then
		return
	end
	for _, frame in pairs(uf) do
		if type(frame) == "table" then
			ApplyBarTextFonts(frame.Health)
			ApplyBarTextFonts(frame.Power)
			RestoreLifeStatusLabelFont(frame.DeadText)
			RestoreLifeStatusLabelFont(frame.UnconsciousText)
			ApplyBarTextFonts(frame.AlternateManaBar)
			ApplyBarTextFonts(frame.MonkStaggerBar)
			if frame.GroupIndicator and frame.GroupIndicator.Text then
				self:ApplyStatusBarTextFont(frame.GroupIndicator.Text)
				local gt = frame.GroupIndicator.Text
				if NORMAL_FONT_COLOR then
					gt:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
				else
					gt:SetTextColor(1, 0.82, 0)
				end
			end
			if frame.EclipseBar then
				self:ApplyStatusBarTextFont(frame.EclipseBar.powerText)
			end
			if frame.DemonicFuryBar then
				self:ApplyStatusBarTextFont(frame.DemonicFuryBar.powerText)
			end
			if frame.kind == "target" or frame.kind == "focus" then
				if frame.unit and UnitExists(frame.unit) and self.ApplyTargetClassificationChrome then
					self:ApplyTargetClassificationChrome(frame)
				elseif self.ApplyFrameBarLayout then
					self:ApplyFrameBarLayout(frame)
				end
			elseif self.ApplyFrameBarLayout then
				self:ApplyFrameBarLayout(frame)
			end
			if frame.kind == "pet" and self.ApplyPetPowerTextStock then
				self:ApplyPetPowerTextStock(frame)
			end
		end
	end
	if self.RefreshAlternateManaBar then
		self:RefreshAlternateManaBar()
	end
	if self.ApplyStockTargetStatusText then
		self:ApplyStockTargetStatusText()
	end
end

function WhoaUF:GetStatusBarTexturePaths()
	-- Same sheet for health and power bars.
	local key = NormalizeStatusBarKey(GetOption("statusBarTexture", "blizzard"))
	if cachedStatusBarKey == key and cachedStatusBarPath then
		return cachedStatusBarPath, cachedStatusBarPath
	end
	local path = STATUSBAR_PATHS[key] or AddonBlp(STATUSBAR_MEDIA .. key)
	cachedStatusBarKey = key
	cachedStatusBarPath = path
	return path, path
end

local function GetAuraIconMaxSize()
	local rowMax = math.floor((AURA_ROW_WIDTH - ((AURA_MAX_PER_ROW - 1) * AURA_SPACING)) / AURA_MAX_PER_ROW)
	return math.min(AURA_MAX_SIZE, rowMax)
end

local function ScaleAuraSize(canonicalSize, baseSize)
	return math.max(1, math.floor((canonicalSize * (baseSize / AURA_BUFF_SIZE)) + 0.5))
end

function WhoaUF:GetAuraIconSizeRange()
	-- Option default is 27 (Whoa); 21 is Classic Blizzard buff size.
	return AURA_MIN_SIZE, GetAuraIconMaxSize(), 27
end

function WhoaUF:GetAuraIconSize()
	local minSize, maxSize, defaultSize = self:GetAuraIconSizeRange()
	local size = GetOption("auraIconSize", defaultSize)
	if type(size) ~= "number" then
		return defaultSize
	end
	return math.min(maxSize, math.max(minSize, math.floor(size + 0.5)))
end

function WhoaUF:GetAuraIconSizes()
	local large = self:GetAuraIconSize()
	if cachedAuraOptSize == large and cachedAuraLarge then
		return cachedAuraLarge, cachedAuraSmall, cachedAuraTot
	end
	local small = ScaleAuraSize(AURA_DEBUFF_SIZE, large)
	local tot = ScaleAuraSize(AURA_TOT_SIZE, large)
	cachedAuraOptSize = large
	cachedAuraLarge = large
	cachedAuraSmall = small
	cachedAuraTot = tot
	cachedTotAuraRows = nil
	return large, small, tot
end

-- ToT row count from vertical clearance (Classic pins debuffs above the ToT frame).
function WhoaUF:GetNumTotAuraRows()
	local large = self:GetAuraIconSizes()
	if cachedTotAuraRows then
		return cachedTotAuraRows
	end
	local rowPitch = large + AURA_OFFSET_Y
	if rowPitch <= 0 then
		cachedTotAuraRows = DEFAULT_NUM_TOT_AURA_ROWS
		return cachedTotAuraRows
	end
	local clearance = AURA_START_Y - TOT_BOTTOM_Y
	cachedTotAuraRows = math.max(1, math.ceil(clearance / rowPitch))
	return cachedTotAuraRows
end

function WhoaUF:GetNameBackgroundMode()
	local value = GetOption("nameBackground", "none")
	if value == true then
		return "target"
	end
	if value == false then
		return "none"
	end
	if value == "player" or value == "target" or value == "both" or value == "none" then
		return value
	end
	return "none"
end

function WhoaUF:ShouldShowNameBackground(frame)
	-- Whoa/Thick art has no name strip; Classic respects the option.
	if self:GetFrameStyle() ~= "classic" then
		return false
	end
	local mode = self:GetNameBackgroundMode()
	if mode == "none" then
		return false
	end
	if not frame then
		return true
	end
	local kind = frame.kind
	if mode == "both" then
		return kind == "player" or kind == "target" or kind == "focus"
	end
	if mode == "player" then
		return kind == "player"
	end
	-- target
	return kind == "target" or kind == "focus"
end

function WhoaUF:GetHideNameMode()
	local value = GetOption("hideName", "auto")
	if value == true then
		return "always"
	end
	if value == false then
		return "auto"
	end
	if value == "auto" or value == "always" or value == "never" then
		return value
	end
	return "auto"
end

function WhoaUF:ShouldShowPlayerName()
	return self:GetHideNameMode() ~= "always"
end

function WhoaUF:GetNumericThreatFrame()
	local value = GetOption("numericThreatFrame", "player")
	if value ~= "target" and value ~= "player" then
		return nil
	end
	-- BlizzCon: player name slot is chrome-owned; numeric only on target.
	-- Alpha relocates the name so it can share the player slot.
	if value == "player"
		and self.GetDeathKnightPlayerArt
		and self:GetDeathKnightPlayerArt() == "blizzcon" then
		return "target"
	end
	return value
end

function WhoaUF:ShouldDisplayUnitName(frame)
	if not frame or not frame.Name then
		return true
	end
	if frame.kind == "player" and not self:ShouldShowPlayerName() then
		return false
	end
	-- never: keep the name visible even when numeric threat shares the slot.
	if self:GetHideNameMode() == "never" then
		return true
	end
	-- Whoa/Thick hide the name while numeric threat occupies that slot.
	-- Classic keeps the name (Blizzard TargetFrame parity: numeric sits above).
	-- DK Alpha: name is laid out above the threat slot — keep both visible.
	if self:GetFrameStyle() ~= "classic"
		and frame.threatNumericIndicator
		and frame.threatNumericIndicator:IsShown() then
		if frame.kind == "player"
			and self.IsDkAlphaPlayerArtActive
			and self:IsDkAlphaPlayerArtActive(frame) then
			return true
		end
		return false
	end
	return true
end

function WhoaUF:ShouldDisplayPlayerName(frame)
	return self:ShouldDisplayUnitName(frame)
end

function WhoaUF:SyncNameBackgroundForFrame(frame)
	if not frame or not frame.NameBackground then
		return
	end
	if frame.kind ~= "player" and frame.kind ~= "target" and frame.kind ~= "focus" then
		return
	end
	local show = not frame.isMinus
		and self:ShouldShowNameBackground(frame)
		and self:ShouldDisplayUnitName(frame)
	if show then
		frame.NameBackground:Show()
	else
		frame.NameBackground:Hide()
	end
end

function WhoaUF:ApplyNumericThreatFrame()
	local uf = self.unitFrames
	if not uf then
		return
	end
	local frames = { uf.player, uf.target, uf.focus }
	for i = 1, #frames do
		local frame = frames[i]
		if frame and self.UpdateFrameThreat then
			self:UpdateFrameThreat(frame)
		end
	end
	if uf.target and self.UpdateUnitAuras then
		self:UpdateUnitAuras(uf.target)
	end
	if uf.focus and self.UpdateUnitAuras then
		self:UpdateUnitAuras(uf.focus)
	end
end

function WhoaUF:ApplyPlayerNameVisibility()
	local player = self.unitFrames and self.unitFrames.player
	if player and self.UpdateUnitFrame then
		self:UpdateUnitFrame(player)
	end
end

local function SetBarColor(bar, r, g, b)
	-- Secret RGB (C_ClassColor on restricted units) cannot be cache-compared.
	if WhoaUF:NeedsSecretSafeNumberOps(r, g, b) then
		bar.whoaHR, bar.whoaHG, bar.whoaHB = nil, nil, nil
		bar:SetStatusBarColor(r, g, b)
		return
	end
	if bar.whoaHR == r and bar.whoaHG == g and bar.whoaHB == b then
		return
	end
	bar.whoaHR, bar.whoaHG, bar.whoaHB = r, g, b
	bar:SetStatusBarColor(r, g, b)
end

function WhoaUF:ApplyHealthBarColor(bar, unit)
	if not bar or not bar.SetStatusBarColor then
		return
	end
	unit = unit or bar.unit
	if not unit then
		return
	end

	if not UnitIsConnected(unit) then
		local c = WhoaUF.ReactionColors.disconnected
		SetBarColor(bar, c.r, c.g, c.b)
		return
	end

	local r, g, b = self:GetHealthBarColor(unit)
	if not self:CanAccessValue(r) or r then
		SetBarColor(bar, r, g, b)
	else
		local c = WhoaUF.ReactionColors.default
		SetBarColor(bar, c.r, c.g, c.b)
	end
end

local function ApplyBarTexture(statusBar, texture)
	if not statusBar or not texture then
		return
	end
	if statusBar.whoaTexture == texture then
		return
	end
	statusBar.whoaTexture = texture
	if not statusBar.SetStatusBarTexture then
		return
	end
	statusBar:SetStatusBarTexture(texture)
	-- Texture rebind often resets the fill to full; snap without poking to max.
	local cur = statusBar.currValue
	-- Never `cur == nil` before secret check — comparing secrets errors.
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(cur) then
		statusBar:SetValue(cur)
		return
	end
	if cur == nil then
		return
	end
	local snap = WhoaUF._UF and WhoaUF._UF.SnapStatusBarValue
	if snap then
		snap(statusBar, cur)
		return
	end
	-- Fallback when shared snap is not loaded yet.
	if WhoaUF.UsesClassicStatusBarSnap and not WhoaUF:UsesClassicStatusBarSnap() then
		statusBar:SetValue(cur)
		return
	end
	local minV, maxV = statusBar:GetMinMaxValues()
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(minV, maxV) then
		statusBar:SetValue(cur)
		return
	end
	if not maxV or not minV or maxV <= minV then
		statusBar:SetMinMaxValues(0, 1)
		minV, maxV = 0, 1
	end
	if cur == minV and maxV > minV then
		local span = maxV - minV
		local poke = minV + ((span > 100) and 1 or (span * 0.01))
		if poke > minV and poke < maxV then
			statusBar:SetValue(poke)
		else
			statusBar:SetMinMaxValues(minV, maxV)
		end
	elseif cur ~= minV then
		statusBar:SetValue(minV)
	end
	statusBar:SetValue(cur)
end

-- Apply current texture (+ optional health color) to one Whoa frame's bars.
function WhoaUF:ApplyFrameStatusBars(frame, applyColor)
	if not frame then
		return
	end
	local hp, mana = self:GetStatusBarTexturePaths()
	ApplyBarTexture(frame.Health, hp)
	ApplyBarTexture(frame.Power, mana)
	local loss = frame.AnimatedLossBar or (frame.Health and frame.Health.AnimatedLossBar)
	if loss then
		ApplyBarTexture(loss, hp)
	end
	if applyColor ~= false and frame.Health and frame.unit then
		self:ApplyHealthBarColor(frame.Health, frame.unit)
	end
end

function WhoaUF:ApplyStatusBarTextures()
	InvalidateStatusBarPathCache()
	local hp, mana = self:GetStatusBarTexturePaths()
	local uf = self.unitFrames
	if not uf then
		return
	end

	for _, frame in pairs(uf) do
		if type(frame) == "table" and frame.Health then
			ApplyBarTexture(frame.Health, hp)
			ApplyBarTexture(frame.Power, mana)
			if frame.unit and UnitExists(frame.unit) then
				self:ApplyHealthBarColor(frame.Health, frame.unit)
			end
		end
	end

	local player = uf.player
	if player and player.AlternateManaBar then
		ApplyBarTexture(player.AlternateManaBar, mana)
	end
	if player and player.MonkStaggerBar then
		ApplyBarTexture(player.MonkStaggerBar, mana)
	end

	if self.ApplyHealPredictionTextures then
		self:ApplyHealPredictionTextures()
	end
	if self.ApplyPowerFeedbackTextures then
		self:ApplyPowerFeedbackTextures()
	end

	if self.RefreshAllUnitFrames then
		self:RefreshAllUnitFrames()
	end
	if self.UpdateAllPartyFrames then
		self:UpdateAllPartyFrames()
	end
	if self.UpdatePetFrame then
		self:UpdatePetFrame()
	end
end

--- Drop whoaH* cache and re-tint one Whoa health bar (option toggles / force-show recovery).
function WhoaUF:RefreshFrameHealthBarColor(frame)
	if not frame or not frame.Health then
		return
	end
	local health = frame.Health
	health.whoaHR, health.whoaHG, health.whoaHB = nil, nil, nil
	local unit = frame.unit or health.unit
	if unit then
		health.unit = unit
	end
	if unit and UnitExists(unit) and self.ApplyHealthBarColor then
		self:ApplyHealthBarColor(health, unit)
	end
end

function WhoaUF:RefreshPartyHealthBarColors()
	local frames = self.partyFrames
	if not frames then
		return
	end
	for i = 1, #frames do
		local frame = frames[i]
		if frame then
			self:RefreshFrameHealthBarColor(frame)
			if frame.PetFrame then
				self:RefreshFrameHealthBarColor(frame.PetFrame)
			end
		end
	end
end

function WhoaUF:RefreshHealthBarColors()
	if self.RefreshAllUnitFrames then
		self:RefreshAllUnitFrames()
	end
	-- Party: clear tint cache then full update (UpdatePartyMemberFrame skips hidden slots).
	if self.RefreshPartyHealthBarColors then
		self:RefreshPartyHealthBarColors()
	end
	if self.UpdateAllPartyFrames then
		self:UpdateAllPartyFrames()
	end
	if self.UpdatePetFrame then
		self:UpdatePetFrame()
	end
end

--- Lightweight re-tint for chromatic cycle (no pairs / DB / string / full refresh).
--- Player and/or NPC surfaces depending on which chromatic options are on.
local CYCLE_NPC_UNIT_KEYS = { "player", "target", "focus", "tot", "focustot", "pet" }

local function TintCycleFrame(frame, r, g, b)
	if not frame then
		return
	end
	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		return
	end
	local isLocalPlayer = frame.kind == "player" or unit == "player" or unit == "vehicle"
	if isLocalPlayer then
		if not WhoaUF.IsHealthColorCycleTintPlayer or not WhoaUF:IsHealthColorCycleTintPlayer() then
			return
		end
	elseif UnitIsPlayer(unit) then
		-- Other players keep class / custom colors; never cycle.
		return
	elseif not WhoaUF.IsHealthColorCycleTintNpc or not WhoaUF:IsHealthColorCycleTintNpc() then
		return
	end
	local health = frame.Health
	if health and health.SetStatusBarColor then
		if UnitIsConnected(unit) then
			-- Drop cache so a same-frame class/custom paint cannot block the first cycle tick.
			health.whoaHR, health.whoaHG, health.whoaHB = nil, nil, nil
			SetBarColor(health, r, g, b)
		else
			local c = WhoaUF.ReactionColors.disconnected
			SetBarColor(health, c.r, c.g, c.b)
		end
	end
	local nameBg = frame.NameBackground
	if nameBg and nameBg.SetVertexColor then
		-- Tap grey stays a status cue (same as UpdateNameBackground).
		if not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) then
			nameBg:SetVertexColor(0.5, 0.5, 0.5)
		else
			nameBg:SetVertexColor(r, g, b)
		end
	end
end

function WhoaUF:ApplyCycleHealthBarColors()
	-- No work when chromatic is off (OnUpdate must not be attached either).
	if not self.IsHealthColorCycleActive or not self:IsHealthColorCycleActive() then
		return
	end
	local r, g, b = self:AdvanceHealthColorCycle()
	local frames = self.unitFrames
	if not frames then
		return
	end
	for i = 1, #CYCLE_NPC_UNIT_KEYS do
		TintCycleFrame(frames[CYCLE_NPC_UNIT_KEYS[i]], r, g, b)
	end
end

local healthColorCycleFrame
local healthColorCycleAccum = 0
local HEALTH_COLOR_CYCLE_TICK = 0.05

local function StopHealthColorCycleOnUpdate()
	healthColorCycleAccum = 0
	if not healthColorCycleFrame then
		return
	end
	healthColorCycleFrame:SetScript("OnUpdate", nil)
	healthColorCycleFrame:Hide()
end

local function HealthColorCycle_OnUpdate(self, elapsed)
	-- Option may flip mid-tick; detach OnUpdate immediately if chromatic is off.
	if not WhoaUF.IsHealthColorCycleActive or not WhoaUF:IsHealthColorCycleActive() then
		StopHealthColorCycleOnUpdate()
		return
	end
	healthColorCycleAccum = healthColorCycleAccum + elapsed
	if healthColorCycleAccum < HEALTH_COLOR_CYCLE_TICK then
		return
	end
	healthColorCycleAccum = healthColorCycleAccum - HEALTH_COLOR_CYCLE_TICK
	WhoaUF:ApplyCycleHealthBarColors()
end

--- Start/stop chromatic health tint driver when option / addon enable changes.
--- OnUpdate is attached only while chromatic is on; otherwise it must not run at all.
function WhoaUF:UpdateHealthColorCycleDriver()
	local tintPlayer = self.GetColorOption
		and self:GetColorOption("classColor", "all") == "chromatic"
		or false
	local tintNpc = self.GetColorOption
		and self:GetColorOption("npcColor", "hostility") == "chromatic"
		or false
	local want = self.db and self.db.enabled and (tintPlayer or tintNpc) and true or false
	if self.SetHealthColorCycleRuntime then
		self:SetHealthColorCycleRuntime(
			want,
			want and self:GetHealthColorCycleRate() or nil,
			want and tintPlayer,
			want and tintNpc
		)
	end
	if want then
		if not healthColorCycleFrame then
			healthColorCycleFrame = CreateFrame("Frame")
		end
		healthColorCycleAccum = HEALTH_COLOR_CYCLE_TICK
		healthColorCycleFrame:SetScript("OnUpdate", HealthColorCycle_OnUpdate)
		healthColorCycleFrame:Show()
		self:ApplyCycleHealthBarColors()
		-- Full paint path so player/NPCs swap off class/custom immediately on option change.
		if self.RefreshHealthBarColors then
			self:RefreshHealthBarColors()
		end
	else
		local wasRunning = healthColorCycleFrame and healthColorCycleFrame:GetScript("OnUpdate")
		StopHealthColorCycleOnUpdate()
		if wasRunning and self.RefreshHealthBarColors then
			self:RefreshHealthBarColors()
		end
	end
end

function WhoaUF:ApplyNameBackgrounds()
	local uf = self.unitFrames
	if not uf then
		return
	end
	for i = 1, #NAME_BG_FRAMES do
		local frame = uf[NAME_BG_FRAMES[i]]
		if frame and self.UpdateUnitFrame then
			self:UpdateUnitFrame(frame)
		end
	end
end

function WhoaUF:RefreshAuraIconSizes()
	InvalidateAuraSizeCache()
	local uf = self.unitFrames
	if not uf then
		return
	end
	if uf.target and self.UpdateUnitAuras then
		self:UpdateUnitAuras(uf.target)
	end
	if uf.focus and self.UpdateUnitAuras then
		self:UpdateUnitAuras(uf.focus)
	end
	if uf.tot and self.UpdateToTDebuffs then
		self:UpdateToTDebuffs(uf.tot)
	end
	if uf.focustot and self.UpdateToTDebuffs then
		self:UpdateToTDebuffs(uf.focustot)
	end
end

function WhoaUF:ApplyToTAuraSizes(frame)
	if not frame or not frame.whoaToTDebuffs then
		return
	end
	local _, _, totSize = self:GetAuraIconSizes()
	local borderSize = totSize + 2
	for i = 1, #frame.whoaToTDebuffs do
		local button = frame.whoaToTDebuffs[i]
		if button and button.whoaSize ~= totSize then
			button.whoaSize = totSize
			button:SetSize(totSize, totSize)
			local border = button.Border
			if border and button.whoaBorderSize ~= borderSize then
				button.whoaBorderSize = borderSize
				border:SetSize(borderSize, borderSize)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Frame styles: whoa / thick / classic × light / dark Media packs + bar geometry.
---------------------------------------------------------------------------

local BLIZZARD_TARGETING = "Interface\\TargetingFrame\\"
local BLIZZARD_PLAYER_STATUS = "Interface\\CharacterFrame\\UI-Player-Status"
-- DK player frame chrome: Media\dk\{light|dark}\ + Media\shared\dk\ for alpha-shared sheets.
-- (Not rune/classbar; those stay client.)
local DK_FRAME_MEDIA = ADDON_MEDIA .. "dk\\"
local DK_SHARED_MEDIA = ADDON_MEDIA .. "shared\\dk\\"
-- Mirrored player threat flash (PlayerFrameFlash in PlayerFrame.xml).
local PLAYER_FLASH_TEX_COORD = { 0.9453125, 0, 0, 0.181640625 }
local PLAYER_FLASH_W, PLAYER_FLASH_H = 242, 93
local BLIZZARD_PLAYER_FLASH = BLIZZARD_TARGETING .. "UI-TargetingFrame-Flash"
local PLAYER_STATUS_TEXCOORD_CLASSIC = { 0, 0.74609375, 0, 0.53125 }
local PLAYER_STATUS_TEXCOORD_MEDIA = { 0, 1, 0, 1 }
local PLAYER_STATUS_W, PLAYER_STATUS_H = 190, 66
local PLAYER_STATUS_MEDIA_W, PLAYER_STATUS_MEDIA_H = 256, 128
-- Stock UI-Player-Status crop (PlayerFrame.xml). Thick + DK alpha use full 256×128 sheets.
local PLAYER_STATUS_LAYOUTS = {
	stock = { point = "TOPLEFT", x = 19, y = -12, width = PLAYER_STATUS_W, height = PLAYER_STATUS_H, fullSheet = false },
	thick = { point = "TOPLEFT", x = 19, y = -12, width = PLAYER_STATUS_MEDIA_W, height = PLAYER_STATUS_MEDIA_H, fullSheet = true },
}
local FRAME_STYLE_KEYS = { "whoa", "thick", "classic" }
local FRAME_STYLE_LABELS = {
	whoa = "Whoa Frames",
	thick = "Thick Frames",
	classic = "Classic Frames",
}

-- Druid stacked frame: UI-TARGETINGFRAME-DRUID(+Elite) + flash from the active style pack.
-- Bar geometry stays on FRAME_STYLE_BARS[style]; stacked mode swaps chrome + alt mana.
-- Player border option remaps to DRUID / DRUID-ELITE / DRUID-RARE-ELITE like normal player chrome.
local FRAME_TEXTURE_FILES = {
	player = "UI-TargetingFrame",
	playerDruid = "UI-TARGETINGFRAME-DRUID",
	playerDruidElite = "UI-TARGETINGFRAME-DRUID-ELITE",
	playerDruidRareElite = "UI-TARGETINGFRAME-DRUID-RARE-ELITE",
	playerDruidFlash = "UI-TARGETINGFRAME-FLASH",
	normal = "UI-TargetingFrame",
	minus = "UI-TargetingFrame-Minus",
	elite = "UI-TargetingFrame-Elite",
	rareelite = "UI-TargetingFrame-Rare-Elite",
	rare = "UI-TargetingFrame-Rare",
	tot = "UI-TargetofTargetFrame",
	party = "UI-PartyFrame",
	-- Party-pet sheet name matches members; path is chosen in GetFrameTexture (not whoa chrome).
	partyPet = "UI-PartyFrame",
	pet = "UI-SmallTargetingFrame",
	petNoMana = "UI-SmallTargetingFrame-NoMana",
	boss = "UI-UnitFrame-Boss",
	bossFlash = "UI-UnitFrame-Boss-Flash",
	pvpFFA = "UI-PVP-FFA",
	pvpAlliance = "UI-PVP-Alliance",
	pvpHorde = "UI-PVP-Horde",
}

-- Boss chrome: Classic client TargetingFrame sheets; Mainline uses Media packs
-- (retail has no UI-UnitFrame-Boss). bossFlash stays client (sheet not shipped).
local CLIENT_ONLY_FRAME_TEXTURES = {
	bossFlash = true,
}

-- Always from the style pack (no Blizzard Classic equivalent under the same name).
local ADDON_ONLY_FRAME_TEXTURES = {
	playerDruid = true,
	playerDruidElite = true,
	playerDruidRareElite = true,
	playerDruidFlash = true,
}

-- Shared across every frame style (light → client; dark → Media\shared\dark\).
-- Party / party-pet / player-pet are resolved separately in GetFrameTexture.
local SHARED_FRAME_TEXTURE_KEYS = {
	minus = true,
	pvpFFA = true,
	pvpAlliance = true,
	pvpHorde = true,
}

-- Whoa/Thick ship custom chrome; Classic light uses client art unless darkened.
local STYLE_USES_ADDON_LIGHT = {
	whoa = true,
	thick = true,
	classic = false,
}

-- Classic: WhoaUF / Blizzard XML geometry.
-- Whoa/Thick: taller HP/power slots; name Y 32 (classic 15). Player +X TOPLEFT; target/focus −X TOPRIGHT.
-- Druid stacked alt-mana uses each style's alternateMana slot in FRAME_STYLE_BARS.
-- Vehicle seat chrome (PlayerFrame.xml + PlayerFrame_ToVehicleArt). One table — do not
-- duplicate in UnitFrame vehicle handlers or combat-safe visual paths.
-- Frame sheets: light → client; dark → Media\shared\dark\vehicles\. Flashes always client.
local BLIZZARD_VEHICLES = "Interface\\Vehicles\\"
local VEHICLE_DARK_MEDIA = ADDON_MEDIA .. "shared\\dark\\vehicles\\"
local VEHICLE_PLAYER_CHROME = {
	Natural = {
		vehicleFile = "UI-Vehicle-Frame-Organic",
		threatTexture = BLIZZARD_VEHICLES .. "UI-Vehicle-Frame-Organic-Flash",
		health = { width = 103, height = 12, point = "TOPLEFT", x = 100, y = -45 },
		power = { width = 103, height = 12, point = "TOPLEFT", x = 100, y = -56 },
		name = { point = "CENTER", x = 34, y = 19 },
		backgroundWidth = 114,
	},
	Mechanical = {
		vehicleFile = "UI-Vehicle-Frame",
		threatTexture = BLIZZARD_VEHICLES .. "UI-Vehicle-Frame-Flash",
		health = { width = 100, height = 12, point = "TOPLEFT", x = 103, y = -45 },
		power = { width = 100, height = 12, point = "TOPLEFT", x = 103, y = -56 },
		name = { point = "CENTER", x = 34, y = 19 },
		backgroundWidth = 114,
	},
}
local VEHICLE_PARTY_FILES = {
	Natural = "UI-Vehicles-PartyFrame-Organic",
	Mechanical = "UI-Vehicles-PartyFrame",
}
local VEHICLE_THREAT_TEX_COORD = { -0.02, 1, 0.07, 0.86 }

local FRAME_STYLE_BARS = {
	classic = {
		player = {
			health = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -45 },
			power = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -56 },
			alternateMana = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -68 },
			name = { point = "CENTER", x = 34, y = 15 },
			background = { width = 119, height = 41, point = "TOPLEFT", x = 89.5, y = -26 },
		},
		target = {
			health = { width = 119, height = 12, point = "TOPRIGHT", x = -90, y = -45 },
			power = { width = 119, height = 12, point = "TOPRIGHT", x = -90, y = -56 },
			name = { point = "CENTER", x = -34, y = 15 },
			background = { width = 119, height = 41, point = "TOPRIGHT", x = -89.5, y = -26 },
		},
		focus = {
			health = { width = 119, height = 12, point = "TOPRIGHT", x = -90, y = -45 },
			power = { width = 119, height = 12, point = "TOPRIGHT", x = -90, y = -56 },
			name = { point = "CENTER", x = -34, y = 15 },
			background = { width = 119, height = 41, point = "TOPRIGHT", x = -89.5, y = -26 },
		},
		tot = {
			health = { width = 46, height = 7, point = "TOPRIGHT", x = -2, y = -15 },
			power = { width = 46, height = 7, point = "TOPRIGHT", x = -2, y = -23 },
		},
		focustot = {
			health = { width = 46, height = 7, point = "TOPRIGHT", x = -2, y = -15 },
			power = { width = 46, height = 7, point = "TOPRIGHT", x = -2, y = -23 },
		},
		pet = {
			health = { width = 69, height = 8, point = "TOPLEFT", x = 47, y = -22 },
			power = { width = 69, height = 8, point = "TOPLEFT", x = 47, y = -29 },
			background = { width = 69, height = 15, point = "TOPLEFT", x = 47, y = -22 },
			-- PetFrame.xml PetName: BOTTOMLEFT 52, 33 in the small-frame nameplate.
			name = { point = "BOTTOMLEFT", x = 52, y = 33, width = 64, height = 12, justify = "LEFT" },
		},
		party = {
			health = { width = 70, height = 8, point = "TOPLEFT", x = 47, y = -12 },
			power = { width = 70, height = 8, point = "TOPLEFT", x = 47, y = -21 },
			background = { width = 72, height = 20, point = "TOPLEFT", x = 45, y = -11 },
		},
	},
	whoa = {
		player = {
			health = { width = 119, height = 18, point = "TOPLEFT", x = 90, y = -28 },
			power = { width = 119, height = 18, point = "TOPLEFT", x = 90, y = -49 },
			-- Stacked alt-mana sits under power (y = power.y − power.height).
			alternateMana = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -67 },
			name = { point = "CENTER", x = 34, y = 32 },
			background = { width = 119, height = 42, point = "TOPLEFT", x = 89.5, y = -26 },
		},
		target = {
			health = { width = 119, height = 18, point = "TOPRIGHT", x = -90, y = -28 },
			power = { width = 119, height = 18, point = "TOPRIGHT", x = -90, y = -49 },
			name = { point = "CENTER", x = -34, y = 32 },
			background = { width = 119, height = 42, point = "TOPRIGHT", x = -89.5, y = -26 },
			hideNameBackground = true,
		},
		focus = {
			health = { width = 119, height = 18, point = "TOPRIGHT", x = -90, y = -28 },
			power = { width = 119, height = 18, point = "TOPRIGHT", x = -90, y = -49 },
			name = { point = "CENTER", x = -34, y = 32 },
			background = { width = 119, height = 42, point = "TOPRIGHT", x = -89.5, y = -26 },
			hideNameBackground = true,
		},
		tot = {
			health = { width = 46, height = 10, point = "TOPRIGHT", x = -2, y = -15 },
			power = { width = 46, height = 5, point = "TOPRIGHT", x = -2, y = -25 },
		},
		focustot = {
			health = { width = 46, height = 10, point = "TOPRIGHT", x = -2, y = -15 },
			power = { width = 46, height = 5, point = "TOPRIGHT", x = -2, y = -25 },
		},
		pet = {
			health = { width = 69, height = 8, point = "TOPLEFT", x = 47, y = -22 },
			power = { width = 69, height = 8, point = "TOPLEFT", x = 47, y = -29 },
			background = { width = 69, height = 15, point = "TOPLEFT", x = 47, y = -22 },
		},
		party = {
			-- Taller HP / thin power — matches Media\shared\{light|dark}\UI-PartyFrame slots.
			health = { width = 70, height = 12, point = "TOPLEFT", x = 47, y = -12 },
			power = { width = 70, height = 5, point = "TOPLEFT", x = 47, y = -26 },
			background = { width = 72, height = 22, point = "TOPLEFT", x = 45, y = -11 },
		},
	},
	thick = {
		player = {
			health = { width = 119, height = 28, point = "TOPLEFT", x = 90, y = -27 },
			power = { width = 119, height = 8, point = "TOPLEFT", x = 90, y = -58 },
			alternateMana = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -68 },
			name = { point = "CENTER", x = 34, y = 32 },
			background = { width = 119, height = 42, point = "TOPLEFT", x = 89.5, y = -26 },
		},
		target = {
			health = { width = 119, height = 28, point = "TOPRIGHT", x = -90, y = -27 },
			power = { width = 119, height = 8, point = "TOPRIGHT", x = -90, y = -58 },
			name = { point = "CENTER", x = -34, y = 32 },
			background = { width = 119, height = 42, point = "TOPRIGHT", x = -89.5, y = -26 },
			hideNameBackground = true,
		},
		focus = {
			health = { width = 119, height = 28, point = "TOPRIGHT", x = -90, y = -27 },
			power = { width = 119, height = 8, point = "TOPRIGHT", x = -90, y = -58 },
			name = { point = "CENTER", x = -34, y = 32 },
			background = { width = 119, height = 42, point = "TOPRIGHT", x = -89.5, y = -26 },
			hideNameBackground = true,
		},
		tot = {
			health = { width = 46, height = 10, point = "TOPRIGHT", x = -2, y = -15 },
			power = { width = 46, height = 5, point = "TOPRIGHT", x = -2, y = -25 },
		},
		focustot = {
			health = { width = 46, height = 10, point = "TOPRIGHT", x = -2, y = -15 },
			power = { width = 46, height = 5, point = "TOPRIGHT", x = -2, y = -25 },
		},
		pet = {
			health = { width = 69, height = 8, point = "TOPLEFT", x = 47, y = -22 },
			power = { width = 69, height = 8, point = "TOPLEFT", x = 47, y = -29 },
			background = { width = 69, height = 15, point = "TOPLEFT", x = 47, y = -22 },
		},
		party = {
			-- Same taller slots as whoa (shared party chrome).
			health = { width = 70, height = 12, point = "TOPLEFT", x = 47, y = -12 },
			power = { width = 70, height = 5, point = "TOPLEFT", x = 47, y = -26 },
			background = { width = 72, height = 22, point = "TOPLEFT", x = 45, y = -11 },
		},
	},
	dark = {
		player = {
			health = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -45 },
			power = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -56 },
			alternateMana = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -68 },
			name = { point = "CENTER", x = 34, y = 15 },
			background = { width = 119, height = 41, point = "TOPLEFT", x = 89.5, y = -26 },
		},
		target = {
			health = { width = 119, height = 12, point = "TOPRIGHT", x = -90, y = -45 },
			power = { width = 119, height = 12, point = "TOPRIGHT", x = -90, y = -56 },
			name = { point = "CENTER", x = -34, y = 15 },
			background = { width = 119, height = 41, point = "TOPRIGHT", x = -89.5, y = -26 },
		},
		focus = {
			health = { width = 119, height = 12, point = "TOPRIGHT", x = -90, y = -45 },
			power = { width = 119, height = 12, point = "TOPRIGHT", x = -90, y = -56 },
			name = { point = "CENTER", x = -34, y = 15 },
			background = { width = 119, height = 41, point = "TOPRIGHT", x = -89.5, y = -26 },
		},
		tot = {
			health = { width = 46, height = 7, point = "TOPRIGHT", x = -2, y = -15 },
			power = { width = 46, height = 7, point = "TOPRIGHT", x = -2, y = -23 },
		},
		focustot = {
			health = { width = 46, height = 7, point = "TOPRIGHT", x = -2, y = -15 },
			power = { width = 46, height = 7, point = "TOPRIGHT", x = -2, y = -23 },
		},
		pet = {
			health = { width = 69, height = 8, point = "TOPLEFT", x = 47, y = -22 },
			power = { width = 69, height = 8, point = "TOPLEFT", x = 47, y = -29 },
			background = { width = 69, height = 15, point = "TOPLEFT", x = 47, y = -22 },
			name = { point = "BOTTOMLEFT", x = 52, y = 33, width = 64, height = 12, justify = "LEFT" },
		},
		party = {
			health = { width = 70, height = 8, point = "TOPLEFT", x = 47, y = -12 },
			power = { width = 70, height = 8, point = "TOPLEFT", x = 47, y = -21 },
			background = { width = 72, height = 20, point = "TOPLEFT", x = 45, y = -11 },
		},
	},
}

local cachedFrameStyle
local cachedFrameDark
local cachedFrameMediaRoot
local cachedSharedMediaRoot

local function IsFrameDarkEnabled()
	return GetOption("frameDark", false) == true
end

local function NormalizeFrameStyle(key)
	if key == "dark" then
		return "classic"
	end
	if key == "whoa" or key == "thick" or key == "classic" then
		return key
	end
	return "whoa"
end

local function GetThemeVariant()
	if IsFrameDarkEnabled() then
		return "dark"
	end
	return "light"
end

local function GetFrameMediaRoot(baseStyle)
	baseStyle = NormalizeFrameStyle(baseStyle)
	return ADDON_MEDIA .. baseStyle .. "\\" .. GetThemeVariant() .. "\\"
end

local function GetSharedMediaRoot()
	return ADDON_MEDIA .. "shared\\" .. GetThemeVariant() .. "\\"
end

local function RefreshFrameMediaCache(style)
	style = NormalizeFrameStyle(style)
	local dark = IsFrameDarkEnabled()
	if cachedFrameStyle ~= style or cachedFrameDark ~= dark or not cachedFrameMediaRoot then
		cachedFrameStyle = style
		cachedFrameDark = dark
		cachedFrameMediaRoot = GetFrameMediaRoot(style)
		cachedSharedMediaRoot = GetSharedMediaRoot()
	end
	return cachedFrameMediaRoot
end

local function ShouldUseAddonStylePack(style, key)
	if ADDON_ONLY_FRAME_TEXTURES[key] then
		return true
	end
	if IsFrameDarkEnabled() then
		return true
	end
	return STYLE_USES_ADDON_LIGHT[NormalizeFrameStyle(style)] == true
end

-- Player chrome border: Default / Elite / Rare Elite (same sheets as target classification).
-- DK alpha/blizzcon art owns the player border and ignores this option.
local PLAYER_FRAME_BORDER_KEYS = { "normal", "elite", "rareelite" }
local PLAYER_FRAME_BORDER_LABELS = {
	normal = "Default",
	elite = "Elite",
	rareelite = "Rare Elite",
}

local function NormalizePlayerFrameBorder(key)
	if key == "elite" or key == "rareelite" then
		return key
	end
	return "normal"
end

local function NormalizeNameBackground(value)
	if value == true then
		return "target"
	end
	if value == false or value == nil then
		return "none"
	end
	if value == "player" or value == "target" or value == "both" or value == "none" then
		return value
	end
	return "none"
end

local function NormalizeHideName(value)
	if value == true then
		return "always"
	end
	if value == false or value == nil then
		return "auto"
	end
	if value == "auto" or value == "always" or value == "never" then
		return value
	end
	return "auto"
end

local function NormalizeClassColor(value)
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

local function NormalizeNpcColor(value)
	if value == "hostility" or value == "blizzard" or value == "chromatic" then
		return value
	end
	return "hostility"
end

local function MigrateCharColorStore(store)
	if type(store) ~= "table" then
		return
	end
	if store.classColor ~= nil then
		store.classColor = NormalizeClassColor(store.classColor)
	end
	if store.npcColor == nil then
		if store.cycleHealthColor then
			store.npcColor = "chromatic"
		elseif store.blizzColors then
			store.npcColor = "blizzard"
		elseif store.reactColor then
			store.npcColor = "hostility"
		end
	elseif store.npcColor ~= nil then
		store.npcColor = NormalizeNpcColor(store.npcColor)
	end
	store.reactColor = nil
	store.blizzColors = nil
	store.cycleHealthColor = nil
	store.cycleHealthColorPlayerOnly = nil
end

function WhoaUF:MigrateFrameStyleOptions(db)
	if not db then
		return
	end
	if db.frameStyle == "dark" then
		db.frameStyle = "classic"
		db.frameDark = true
	end
	if db.frameDark == nil then
		db.frameDark = false
	end
	db.frameStyle = NormalizeFrameStyle(db.frameStyle)
	db.playerFrameBorder = NormalizePlayerFrameBorder(db.playerFrameBorder)
	-- Druid stacked frame is always on (Settings no longer offers the stock strip).
	db.altManaBarStyle = "stacked"

	-- Collapse legacy portrait flags into portraitMode (normal | class).
	-- Former "3d" / portrait3D values fall back to normal.
	if db.portraitMode == "3d" or db.portrait3D then
		db.portraitMode = "normal"
	elseif db.portraitMode ~= "normal" and db.portraitMode ~= "class" then
		if db.targetClassIcon then
			db.portraitMode = "class"
		else
			db.portraitMode = "normal"
		end
	end
	db.targetClassIcon = nil
	db.portrait3D = nil

	-- Name background: boolean showTargetNameBackground → nameBackground enum.
	if db.nameBackground == nil and db.showTargetNameBackground ~= nil then
		db.nameBackground = db.showTargetNameBackground and "target" or "none"
	end
	db.nameBackground = NormalizeNameBackground(db.nameBackground)
	db.showTargetNameBackground = nil

	-- Hide name: boolean hidePlayerName → hideName enum.
	if db.hideName == nil and db.hidePlayerName ~= nil then
		db.hideName = db.hidePlayerName and "always" or "auto"
	end
	db.hideName = NormalizeHideName(db.hideName)
	db.hidePlayerName = nil

	-- Class colors: boolean → all/none string mode.
	db.classColor = NormalizeClassColor(db.classColor)

	-- NPC color: fold react / blizz / chromatic cycle into one mode.
	if db.npcColor == nil then
		if db.cycleHealthColor then
			db.npcColor = "chromatic"
		elseif db.blizzColors then
			db.npcColor = "blizzard"
		elseif db.reactColor then
			db.npcColor = "hostility"
		else
			db.npcColor = "hostility"
		end
	end
	db.npcColor = NormalizeNpcColor(db.npcColor)
	db.reactColor = nil
	db.blizzColors = nil
	db.cycleHealthColor = nil
	db.cycleHealthColorPlayerOnly = nil

	if type(db.charColors) == "table" then
		for _, store in pairs(db.charColors) do
			MigrateCharColorStore(store)
		end
	end
end

function WhoaUF:IsFrameDarkVariant()
	return IsFrameDarkEnabled()
end

-- Thin media accessors for SpellbarArt_*.lua (and other flavor modules).
function WhoaUF:AddonBlp(path)
	return AddonBlp(path)
end

function WhoaUF:GetSharedMediaRoot()
	return GetSharedMediaRoot()
end

function WhoaUF:RefreshFrameMediaCache(style)
	return RefreshFrameMediaCache(style)
end

-- Class power sheets (Paladin / shards / eclipse / monk / priest / DK runes / …).
-- Light → client Interface\… path; dark → Media\shared\dark\classpower\<basename>.
function WhoaUF:GetClassPowerMediaRoot()
	return CLASS_POWER_MEDIA
end

function WhoaUF:GetClassPowerTexture(clientPath)
	if type(clientPath) ~= "string" or clientPath == "" then
		return clientPath
	end
	if not IsFrameDarkEnabled() then
		return clientPath
	end
	local file = clientPath:match("([^\\/]+)$")
	if not file then
		return clientPath
	end
	return AddonBlp(CLASS_POWER_MEDIA .. file)
end

-- Resolve atlas source sheet basename from a path string, or by matching fileID
-- against known client sheets (retail often returns fileID instead of a path).
-- ComboPoints-* (Whoa ComboPointPlayerBar / Legion tray): always ClassOverlayComboPoints
-- on Classic and Mainline — never UIRogueComboPoints2x (different layout; dark gems break).
local CLASS_POWER_ATLAS_CLIENT_SHEETS = {
	-- Legion ComboPointPlayerFrame (same sheet Classic + Mainline Whoa bar).
	["^ComboPoints%-"] = {
		"Interface\\PlayerFrame\\ClassOverlayComboPoints",
	},
	-- Mainline druid combo.
	["^UF%-DruidCP%-"] = {
		"Interface\\HUD\\UIDruidComboPoints2x",
		"Interface\\HUD\\UIDruidComboPoints",
		"Interface\\PlayerFrame\\UIDruidComboPoints2x",
		"Interface\\PlayerFrame\\UIDruidComboPoints",
	},
}

local function BasenameFromTexturePath(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	if path:match("^%d+$") then
		return nil
	end
	local basename = path:match("([^\\/]+)$")
	if not basename then
		return nil
	end
	basename = basename:gsub("%.blp$", ""):gsub("%.BLP$", ""):gsub("%.png$", ""):gsub("%.PNG$", "")
	if basename == "" then
		return nil
	end
	return basename
end

local function GetFileIDForPath(path)
	if type(path) ~= "string" or path == "" or not GetFileIDFromPath then
		return nil
	end
	local id = GetFileIDFromPath(path)
	if id and id ~= 0 then
		return id
	end
	if not path:lower():find("%.blp$") then
		id = GetFileIDFromPath(path .. ".blp")
		if id and id ~= 0 then
			return id
		end
	end
	return nil
end

local function GetAtlasFileID(file)
	if type(file) == "number" then
		return file
	end
	if type(file) == "string" and file:match("^%d+$") then
		return tonumber(file)
	end
	return nil
end

local function GetClassPowerAtlasSheetBasename(atlasName, file)
	-- Whoa ComboPointPlayerBar = Classic Legion tray on every flavor.
	-- Always dark-remap onto ClassOverlayComboPoints (same as Classic).
	if type(atlasName) == "string" and atlasName:find("^ComboPoints%-") then
		return "ClassOverlayComboPoints"
	end
	local fromPath = BasenameFromTexturePath(file)
	if fromPath then
		return fromPath
	end
	local fileID = GetAtlasFileID(file)
	if fileID and type(atlasName) == "string" then
		for pattern, paths in pairs(CLASS_POWER_ATLAS_CLIENT_SHEETS) do
			if atlasName:find(pattern) then
				for i = 1, #paths do
					local clientPath = paths[i]
					if GetFileIDForPath(clientPath) == fileID then
						return BasenameFromTexturePath(clientPath)
					end
				end
			end
		end
		-- fileID present but unmatched — do not guess a sheet.
		return nil
	end
	-- No file field at all: one sheet per era (never cross-pack).
	if file == nil and type(atlasName) == "string" then
		if atlasName:find("^UF%-DruidCP%-") then
			if WhoaUF.IsMainline and WhoaUF:IsMainline() then
				return "UIDruidComboPoints2x"
			end
			return "UIDruidComboPoints"
		end
	end
	return nil
end

local function ClearTextureAtlas(texture)
	if not texture or not texture.SetAtlas then
		return
	end
	-- Avoid SetAtlas(nil) on plain SetTexture regions (can blank Classic ComboPoint gems).
	if texture.GetAtlas then
		local atlas = texture:GetAtlas()
		if not atlas or atlas == "" then
			return
		end
	end
	pcall(function()
		texture:SetAtlas(nil)
	end)
end

local function ResetTextureCoords(texture)
	if texture and texture.SetTexCoord then
		pcall(function()
			texture:SetTexCoord(0, 1, 0, 1)
		end)
	end
end

-- Classic / MoP ClassOverlayComboPoints is 128x64 (same as Media\shared\dark\classpower\).
-- Mainline rebuilt that sheet to 128x128 with different packing — client GetAtlasInfo
-- UVs for ComboPoints-* are wrong on the dark pack and paint white garbage.
-- Pixel L,R,T,B + display W,H from Classic atlas 728 (build 5.5.0).
local CLASSIC_COMBO_POINTS_ATLAS = {
	["ComboPoints-AllPointsBG"] = { 1, 127, 1, 19, 126, 18 },
	["ComboPoints-PointBg"] = { 78, 98, 21, 42, 20, 21 },
	["ComboPoints-ComboPoint"] = { 56, 76, 21, 42, 20, 21 },
	["ComboPoints-FX-Circle"] = { 1, 27, 21, 48, 26, 27 },
	["ComboPoints-FX-Star"] = { 29, 54, 21, 46, 25, 25 },
	["ComboPoints-ComboPointDash"] = { 29, 38, 48, 58, 9, 10 },
	["ComboPoints-ComboPointDash-Bg"] = { 40, 49, 48, 58, 9, 10 },
	["ComboPoints-FX-Dash"] = { 1, 26, 50, 58, 25, 8 },
}
local CLASSIC_COMBO_SHEET_W = 128
local CLASSIC_COMBO_SHEET_H = 64

local function ApplyClassicComboPointsDarkAtlas(texture, atlasName, useAtlasSize)
	local region = CLASSIC_COMBO_POINTS_ATLAS[atlasName]
	if not region then
		return false
	end
	local leftPx, rightPx, topPx, bottomPx, width, height = region[1], region[2], region[3], region[4], region[5], region[6]
	local mediaPath = AddonBlp(CLASS_POWER_MEDIA .. "ClassOverlayComboPoints")
	local ok = pcall(function()
		ClearTextureAtlas(texture)
		texture:SetTexture(mediaPath)
		texture:SetTexCoord(
			leftPx / CLASSIC_COMBO_SHEET_W,
			rightPx / CLASSIC_COMBO_SHEET_W,
			topPx / CLASSIC_COMBO_SHEET_H,
			bottomPx / CLASSIC_COMBO_SHEET_H
		)
		if useAtlasSize then
			texture:SetSize(width, height)
		end
	end)
	return ok
end

-- Dark theme: if the atlas source sheet exists under classpower, rebind to that BLP
-- (keeps atlas UV). Light / missing / unknown sheet → SetAtlas as usual.
-- Must clear atlas before SetTexture or the prior SetAtlas wins on many clients
-- (same pitfall as casting-bar chrome).
function WhoaUF:ApplyClassPowerAtlas(texture, atlasName, useAtlasSize)
	if not texture or type(atlasName) ~= "string" or atlasName == "" then
		return false
	end
	local function setAtlas()
		-- After a dark SetTexture+SetTexCoord pass, reset coords so SetAtlas
		-- is not stuck on the previous sheet's UVs.
		ResetTextureCoords(texture)
		texture:SetAtlas(atlasName, useAtlasSize and true or false)
	end
	if not IsFrameDarkEnabled() then
		return pcall(setAtlas)
	end
	-- ComboPointPlayerBar: always Classic 128x64 UVs + ClassOverlayComboPoints dark.
	-- Do not reuse Mainline GetAtlasInfo (128x128 packing) — that overrides Classic look.
	if atlasName:find("^ComboPoints%-") then
		if ApplyClassicComboPointsDarkAtlas(texture, atlasName, useAtlasSize) then
			return true
		end
		return pcall(setAtlas)
	end
	local info
	if C_Texture and C_Texture.GetAtlasInfo then
		info = C_Texture.GetAtlasInfo(atlasName)
	elseif GetAtlasInfo then
		local filename, width, height, left, right, top, bottom = GetAtlasInfo(atlasName)
		if filename then
			info = {
				filename = filename,
				width = width,
				height = height,
				leftTexCoord = left,
				rightTexCoord = right,
				topTexCoord = top,
				bottomTexCoord = bottom,
			}
		end
	end
	if not info then
		return pcall(setAtlas)
	end
	local file = info.filename or info.fileName or info.file
	local basename = GetClassPowerAtlasSheetBasename(atlasName, file)
	if not basename then
		-- Unknown source: keep client atlas (do not paint a wrong sheet).
		return pcall(setAtlas)
	end
	local mediaPath = AddonBlp(CLASS_POWER_MEDIA .. basename)
	local left = info.leftTexCoord or info.left or 0
	local right = info.rightTexCoord or info.right or 1
	local top = info.topTexCoord or info.top or 0
	local bottom = info.bottomTexCoord or info.bottom or 1
	local ok = pcall(function()
		ClearTextureAtlas(texture)
		texture:SetTexture(mediaPath)
		texture:SetTexCoord(left, right, top, bottom)
		if useAtlasSize and info.width and info.height then
			texture:SetSize(info.width, info.height)
		end
	end)
	if ok then
		return true
	end
	return pcall(setAtlas)
end

-- Re-apply a client sheet path onto every Texture region under a frame (XML templates).
function WhoaUF:ApplyClassPowerSheetToRegions(frame, clientPath)
	if not frame or not clientPath then
		return
	end
	local path = self:GetClassPowerTexture(clientPath)
	local regions = { frame:GetRegions() }
	for i = 1, #regions do
		local region = regions[i]
		if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.SetTexture then
			ClearTextureAtlas(region)
			region:SetTexture(path)
		end
	end
end

-- Same as above, including nested child frames (holy runes, shards, chi orbs, …).
function WhoaUF:ApplyClassPowerSheetRecursive(frame, clientPath)
	if not frame or not clientPath then
		return
	end
	self:ApplyClassPowerSheetToRegions(frame, clientPath)
	local children = { frame:GetChildren() }
	for i = 1, #children do
		self:ApplyClassPowerSheetRecursive(children[i], clientPath)
	end
end

-- DK player-frame chrome only. Theme-variant sheets live in Media\dk\{light|dark}.
-- Alpha overlays shared by light/dark live in Media\shared\dk\. Rune buttons use classpower dark pack.
local DK_FRAME_TEXTURE_FILES = {
	alpha = "UI-Deathknight-Alpha",
	blizzcon = "UI-Deathknight-Blizzcon",
	background = "UI-PlayerFrame-Deathknight-Background",
}
local DK_SHARED_TEXTURE_FILES = {
	goldBorder = "UI-PlayerFrame-Deathknight-GoldBorder",
	swordGlow = "UI-PlayerFrame-Deathknight-Sword-Glow",
	runicPower = "UI-PlayerFrame-Deathknight-RunicPower",
	status = "UI-Player-DK-Status",
}

function WhoaUF:GetDkFrameMediaRoot()
	RefreshFrameMediaCache(self:GetFrameStyle())
	return DK_FRAME_MEDIA .. GetThemeVariant() .. "\\"
end

function WhoaUF:GetDkSharedMediaRoot()
	return DK_SHARED_MEDIA
end

function WhoaUF:GetDkFrameTexture(key)
	local shared = DK_SHARED_TEXTURE_FILES[key]
	if shared then
		return AddonBlp(DK_SHARED_MEDIA .. shared)
	end
	local file = DK_FRAME_TEXTURE_FILES[key]
	if not file then
		return nil
	end
	return AddonBlp(self:GetDkFrameMediaRoot() .. file)
end

function WhoaUF:GetFrameStyleOptions()
	return FRAME_STYLE_KEYS, FRAME_STYLE_LABELS
end

function WhoaUF:GetFrameStyle()
	local style = NormalizeFrameStyle(GetOption("frameStyle", "whoa"))
	RefreshFrameMediaCache(style)
	return style
end

function WhoaUF:GetPlayerFrameBorderOptions()
	return PLAYER_FRAME_BORDER_KEYS, PLAYER_FRAME_BORDER_LABELS
end

function WhoaUF:GetPlayerFrameBorder()
	return NormalizePlayerFrameBorder(GetOption("playerFrameBorder", "normal"))
end

function WhoaUF:GetPlayerFrameTextureKey()
	local border = self:GetPlayerFrameBorder()
	if border == "elite" then
		return "elite"
	end
	if border == "rareelite" then
		return "rareelite"
	end
	return "player"
end

-- Stacked cat/bear chrome: same border remap as GetPlayerFrameTextureKey.
function WhoaUF:GetDruidPlayerFrameTextureKey()
	local border = self:GetPlayerFrameBorder()
	if border == "elite" then
		return "playerDruidElite"
	end
	if border == "rareelite" then
		return "playerDruidRareElite"
	end
	return "playerDruid"
end

-- Stock player chrome is a tight crop (193×77). Elite / Rare Elite need the larger
-- TargetFrame sheet window, mirrored for the player side (TargetFrame.xml note).
local PLAYER_BORDER_LAYOUT_NORMAL = {
	width = 193,
	height = 77,
	x = 0,
	y = 0,
	coords = { 0.85546875, 0.1015625, 0.0625, 0.6640625 },
}
local PLAYER_BORDER_LAYOUT_ELITE = {
	width = 230,
	height = 99,
	x = -18.5,
	y = -4,
	coords = { 1.0, 0.1015625, 0.0078125, 0.78125 },
}

function WhoaUF:GetPlayerFrameBorderLayout()
	local border = self:GetPlayerFrameBorder()
	if border == "elite" or border == "rareelite" then
		return PLAYER_BORDER_LAYOUT_ELITE
	end
	return PLAYER_BORDER_LAYOUT_NORMAL
end

-- Texture path + size / texcoords / anchor for the standard (non-DK) player border.
-- While stacked druid chrome is active, FrameTexture is the DRUID sheet (elite remap included).
function WhoaUF:ApplyDruidStackedPlayerFrameArt(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	local tex = frame and frame.FrameTexture
	if not tex then
		return
	end
	local path = self:GetDruidPlayerFrameTexture()
	if path then
		tex:SetTexture(path)
	end
	local layout = self:GetPlayerFrameBorderLayout()
	local c = layout.coords
	tex:SetSize(layout.width, layout.height)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", layout.x, layout.y)
	tex:SetTexCoord(c[1], c[2], c[3], c[4])
	tex:SetAlpha(1)
	tex:Show()
end

function WhoaUF:ApplyPlayerFrameBorderArt(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	local tex = frame and frame.FrameTexture
	if not tex then
		return
	end
	-- Stacked cat/bear rim owns the border; keep elite/style on the DRUID sheets.
	if self.IsDruidStackedPlayerFrameActive and self:IsDruidStackedPlayerFrameActive(frame) then
		self:ApplyDruidStackedPlayerFrameArt(frame)
		return
	end
	local path = self:GetFrameTexture("player")
	if path then
		tex:SetTexture(path)
	end
	local layout = self:GetPlayerFrameBorderLayout()
	local c = layout.coords
	tex:SetSize(layout.width, layout.height)
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", layout.x, layout.y)
	tex:SetTexCoord(c[1], c[2], c[3], c[4])
	tex:SetAlpha(1)
	tex:Show()
end

function WhoaUF:SetPlayerFrameBorder(border)
	if not self.db then
		return
	end
	self.db.playerFrameBorder = NormalizePlayerFrameBorder(border)
	if self.ApplyFrameStyle then
		pcall(self.ApplyFrameStyle, self)
	end
end

function WhoaUF:ShouldUseThickPlayerStatusTexture(frame)
	if self:GetFrameStyle() ~= "thick" then
		return false
	end
	frame = frame or (self.unitFrames and self.unitFrames.player)
	if self.IsDkAlphaPlayerArtActive and self:IsDkAlphaPlayerArtActive(frame) then
		return false
	end
	if frame and frame.kind == "player" and self.GetDeathKnightPlayerArt then
		if self:GetDeathKnightPlayerArt() == "alpha" then
			return false
		end
	end
	return true
end

-- Back-compat alias.
WhoaUF.ShouldUseAddonPlayerStatusTexture = WhoaUF.ShouldUseThickPlayerStatusTexture

function WhoaUF:GetPlayerStatusTexture(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	if self.IsDkAlphaPlayerArtActive and self:IsDkAlphaPlayerArtActive(frame) then
		return self:GetDkFrameTexture("status")
	end
	if frame and frame.kind == "player" and self.GetDeathKnightPlayerArt then
		if self:GetDeathKnightPlayerArt() == "alpha" then
			return self:GetDkFrameTexture("status")
		end
	end
	if self:ShouldUseThickPlayerStatusTexture(frame) then
		-- Thick status sheet is modified addon art (full 256×128).
		return AddonBlp(GetFrameMediaRoot("thick") .. "UI-Player-Status")
	end
	return BLIZZARD_PLAYER_STATUS
end

function WhoaUF:UsesFullPlayerStatusMediaSheet(frame)
	if self:ShouldUseThickPlayerStatusTexture(frame) then
		return true
	end
	frame = frame or (self.unitFrames and self.unitFrames.player)
	if self.IsDkAlphaPlayerArtActive and self:IsDkAlphaPlayerArtActive(frame) then
		return true
	end
	if frame and frame.kind == "player" and self.GetDeathKnightPlayerArt then
		return self:GetDeathKnightPlayerArt() == "alpha"
	end
	return false
end

function WhoaUF:GetPlayerStatusTexCoord(frame)
	if self:UsesFullPlayerStatusMediaSheet(frame) then
		local t = PLAYER_STATUS_TEXCOORD_MEDIA
		return t[1], t[2], t[3], t[4]
	end
	local t = PLAYER_STATUS_TEXCOORD_CLASSIC
	return t[1], t[2], t[3], t[4]
end

function WhoaUF:GetPlayerStatusLayout(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	local layout = self:UsesFullPlayerStatusMediaSheet(frame)
		and PLAYER_STATUS_LAYOUTS.thick
		or PLAYER_STATUS_LAYOUTS.stock
	local y = layout.y
	if self.IsAlternateManaBarShown and self:IsAlternateManaBarShown()
		and not (self.IsAlternateManaBarStackedStyle and self:IsAlternateManaBarStackedStyle()) then
		y = y + 2
	end
	return layout.point, layout.x, y, layout.width, layout.height
end

function WhoaUF:ApplyPlayerStatusTexture(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	local status = frame and frame.StatusTexture
	if not status then
		return
	end
	if self.IsDkAlphaPlayerArtActive and self:IsDkAlphaPlayerArtActive(frame) then
		if self.LayoutDkAlphaPlayerStatus then
			self:LayoutDkAlphaPlayerStatus(frame)
		end
		return
	end
	local path = self:GetPlayerStatusTexture(frame)
	if status.whoaPlayerStatusPath ~= path then
		status.whoaPlayerStatusPath = path
		status:SetTexture(path)
	end
	local l, r, t, b = self:GetPlayerStatusTexCoord(frame)
	status:SetTexCoord(l, r, t, b)
	local point, x, y, w, h = self:GetPlayerStatusLayout(frame)
	status:SetSize(w, h)
	local overlay = frame.Overlay or frame
	if status:GetParent() ~= overlay then
		status:SetParent(overlay)
	end
	status:SetDrawLayer("OVERLAY", 0)
	status:ClearAllPoints()
	status:SetPoint(point, frame, point, x, y)
end

--- Player threat flash. Style-pack UI-TARGETINGFRAME-FLASH is for the custom stacked
--- druid frame only; all player-side flashes use mirrored PlayerFrame.xml texcoords.
function WhoaUF:ApplyPlayerThreatFlashArt(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	local flash = frame and frame.threatIndicator
	if not flash then
		return
	end
	local path
	local druidStacked = self.IsDruidStackedPlayerFrameActive and self:IsDruidStackedPlayerFrameActive(frame)
	if druidStacked then
		path = self:GetDruidPlayerFlashTexture()
	else
		path = BLIZZARD_PLAYER_FLASH
	end
	-- Always re-apply texture: vehicle chrome may leave a vehicle sheet while the
	-- cached path still says player flash.
	flash.whoaThreatFlashPath = path
	flash:SetTexture(path)
	flash:SetTexCoord(PLAYER_FLASH_TEX_COORD[1], PLAYER_FLASH_TEX_COORD[2], PLAYER_FLASH_TEX_COORD[3], PLAYER_FLASH_TEX_COORD[4])
	flash:SetSize(PLAYER_FLASH_W, PLAYER_FLASH_H)
	flash:SetBlendMode("BLEND")
	if self.ApplyThreatFlashStrata then
		self:ApplyThreatFlashStrata(frame)
	end
end

function WhoaUF:GetToTFrameTexture()
	return self:GetFrameTexture("tot")
end

-- Party members:
--   classic → light client / Media\classic\dark\UI-PartyFrame (stock-sized slots + classic bars)
--   whoa/thick → Media\shared\{light|dark}\UI-PartyFrame (taller slots + whoa/thick bars)
-- Party flash: classic → client; whoa/thick → Media\shared\light\UI-PARTYFRAME-FLASH
-- Party-pet: light → client PartyFrame; dark → classic\dark\UI-PartyFrame
-- Player pet (all styles): light → client SmallTargeting*; dark → classic\dark\UI-SmallTargetingFrame*
local BLIZZARD_PARTY_FLASH = BLIZZARD_TARGETING .. "UI-PartyFrame-Flash"
local SHARED_PARTY_FLASH_LIGHT = ADDON_MEDIA .. "shared\\light\\UI-PARTYFRAME-FLASH"
local SHARED_PARTY_FRAME = ADDON_MEDIA .. "shared\\%s\\UI-PartyFrame"
local CLASSIC_DARK_PARTY_FRAME = ADDON_MEDIA .. "classic\\dark\\UI-PartyFrame"
local CLASSIC_DARK_PET_ROOT = ADDON_MEDIA .. "classic\\dark\\"

function WhoaUF:GetPartyFlashTexture()
	local style = NormalizeFrameStyle(self:GetFrameStyle())
	if style == "whoa" or style == "thick" then
		return AddonBlp(SHARED_PARTY_FLASH_LIGHT)
	end
	return BLIZZARD_PARTY_FLASH
end

function WhoaUF:GetPartyPetFlashTexture()
	return BLIZZARD_PARTY_FLASH
end

function WhoaUF:GetClassicPartyFrameTexture()
	if IsFrameDarkEnabled() then
		return AddonBlp(CLASSIC_DARK_PARTY_FRAME)
	end
	return BLIZZARD_TARGETING .. FRAME_TEXTURE_FILES.party
end

function WhoaUF:GetWhoaPartyFrameTexture()
	return AddonBlp(string.format(SHARED_PARTY_FRAME, GetThemeVariant()))
end

-- Player pet only (pet / petNoMana). Dark sheets live in classic\dark (seeded from whoa dark).
function WhoaUF:GetClassicPetFrameTexture(key)
	local file = FRAME_TEXTURE_FILES[key]
	if not file then
		return nil
	end
	if IsFrameDarkEnabled() then
		return AddonBlp(CLASSIC_DARK_PET_ROOT .. file)
	end
	return BLIZZARD_TARGETING .. file
end

function WhoaUF:ApplyPartyFlashArt(frame)
	if not frame or not frame.Flash or not frame.Flash.SetTexture then
		return
	end
	local path = (frame.kind == "partypet") and self:GetPartyPetFlashTexture() or self:GetPartyFlashTexture()
	frame.Flash:SetTexture(path)
end

-- Party chrome on Overlay (+3) above StatusBars (+1). Sheets use alpha holes for
-- bar slots (PartyFrameTemplates.xml / Media shared+classic party art).
function WhoaUF:ApplyPartyChromeLayering(frame)
	if not frame or frame.kind ~= "party" then
		return
	end
	local tex = frame.FrameTexture
	local overlay = frame.Overlay
	if not tex or not overlay then
		return
	end
	if tex:GetParent() ~= overlay then
		tex:SetParent(overlay)
	end
	tex:SetDrawLayer("BORDER", 0)
	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", 0, -2)
	-- Name lives on NameHost (+8); keep OVERLAY so it stays above bars/chrome.
	if frame.Name and frame.Name.SetDrawLayer then
		frame.Name:SetDrawLayer("OVERLAY", 0)
	end
	local nameHost = frame.NameHost
	if nameHost then
		local want = (frame:GetFrameLevel() or 0) + 8
		if nameHost:GetFrameLevel() ~= want then
			nameHost:SetFrameLevel(want)
		end
	end
end

-- Kept for callers; ToT threat no longer uses UI-TOT-FLASH (party Flash + pulse).
function WhoaUF:GetToTThreatFlashTexture()
	return self:GetPartyFlashTexture()
end

-- Numeric threat % border: light → client; dark → Media\shared\dark\NumericThreatBorder.
function WhoaUF:GetNumericThreatBorderTexture()
	RefreshFrameMediaCache(self:GetFrameStyle())
	if self:IsFrameDarkVariant() then
		return AddonBlp(cachedSharedMediaRoot .. "NumericThreatBorder")
	end
	return BLIZZARD_TARGETING .. "NumericThreatBorder"
end

-- Player raid subgroup badge: Media\shared\{light|dark}\UI-GroupIndicator.
function WhoaUF:GetGroupIndicatorTexture()
	RefreshFrameMediaCache(self:GetFrameStyle())
	return AddonBlp(cachedSharedMediaRoot .. "UI-GroupIndicator")
end

-- Leader / master looter / LFG portrait roles: Media\shared\{light|dark}\.
function WhoaUF:GetLeaderIconTexture()
	RefreshFrameMediaCache(self:GetFrameStyle())
	return AddonBlp(cachedSharedMediaRoot .. "UI-Group-LeaderIcon")
end

function WhoaUF:GetMasterLooterIconTexture()
	RefreshFrameMediaCache(self:GetFrameStyle())
	return AddonBlp(cachedSharedMediaRoot .. "UI-Group-MasterLooter")
end

function WhoaUF:GetPortraitRoleIconTexture()
	RefreshFrameMediaCache(self:GetFrameStyle())
	return AddonBlp(cachedSharedMediaRoot .. "UI-LFG-ICON-PORTRAITROLES")
end

function WhoaUF:ApplyNumericThreatArt(numeric)
	if not numeric or not numeric.border or not numeric.border.SetTexture then
		return
	end
	numeric.border:SetTexture(self:GetNumericThreatBorderTexture())
end

function WhoaUF:ApplyAllNumericThreatArt()
	local uf = self.unitFrames
	if not uf then
		return
	end
	for _, frame in pairs(uf) do
		if type(frame) == "table" and frame.threatNumericIndicator then
			self:ApplyNumericThreatArt(frame.threatNumericIndicator)
		end
	end
end

function WhoaUF:GetFrameTexture(key)
	-- Player border option remaps "player" → elite / rareelite sheets.
	if key == "player" then
		key = self:GetPlayerFrameTextureKey()
	end
	-- Stacked druid: remaps "playerDruid" → elite / rareelite DRUID sheets.
	if key == "playerDruid" then
		key = self:GetDruidPlayerFrameTextureKey()
	end
	local file = FRAME_TEXTURE_FILES[key]
	if not file then
		return nil
	end
	if key == "playerDruid" or key == "playerDruidElite" or key == "playerDruidRareElite" then
		return self:GetDruidPlayerFrameTexture()
	end
	if key == "playerDruidFlash" then
		return self:GetDruidPlayerFlashTexture()
	end
	if CLIENT_ONLY_FRAME_TEXTURES[key] then
		return BLIZZARD_TARGETING .. file
	end

	local style = self:GetFrameStyle()
	RefreshFrameMediaCache(style)

	-- Boss: Classic client sheet when present; Mainline / missing → style Media pack.
	if key == "boss" then
		if not self:IsMainline() then
			return BLIZZARD_TARGETING .. file
		end
		return AddonBlp(cachedFrameMediaRoot .. file)
	end

	-- Shared (minus + PVP): light → client; dark → Media\shared\dark\
	if SHARED_FRAME_TEXTURE_KEYS[key] then
		if self:IsFrameDarkVariant() then
			return AddonBlp(cachedSharedMediaRoot .. file)
		end
		return BLIZZARD_TARGETING .. file
	end

	-- Party-pet: light → client PartyFrame; dark → classic\dark\UI-PartyFrame.
	if key == "partyPet" then
		return self:GetClassicPartyFrameTexture()
	end

	-- Party members: classic → client / classic\dark; whoa+thick → shared\{light|dark}.
	if key == "party" then
		if NormalizeFrameStyle(style) == "classic" then
			return self:GetClassicPartyFrameTexture()
		end
		return self:GetWhoaPartyFrameTexture()
	end

	-- Player pet: light → client SmallTargeting*; dark → classic\dark\UI-SmallTargetingFrame*.
	if key == "pet" or key == "petNoMana" then
		return self:GetClassicPetFrameTexture(key)
	end

	-- Light: client art unless this style ships modified chrome. Dark: always addon pack.
	if ShouldUseAddonStylePack(style, key) then
		return AddonBlp(cachedFrameMediaRoot .. file)
	end
	return BLIZZARD_TARGETING .. file
end

function WhoaUF:GetDruidPlayerFrameTexture()
	local key = self:GetDruidPlayerFrameTextureKey()
	local file = FRAME_TEXTURE_FILES[key] or FRAME_TEXTURE_FILES.playerDruid
	return AddonBlp(GetFrameMediaRoot(self:GetFrameStyle()) .. file)
end

function WhoaUF:GetDruidPlayerFlashTexture()
	return AddonBlp(GetFrameMediaRoot(self:GetFrameStyle()) .. FRAME_TEXTURE_FILES.playerDruidFlash)
end

function WhoaUF:GetFrameBarLayout(kind)
	local style = self:GetFrameStyle()
	local bars = FRAME_STYLE_BARS[style] or FRAME_STYLE_BARS.classic
	if kind == "party1" or kind == "party2" or kind == "party3" or kind == "party4" then
		kind = "party"
	end
	if kind == "boss" then
		kind = "target"
	end
	return bars[kind]
end

local function ApplyBarGeom(bar, geom)
	if not bar or not geom then
		return
	end
	bar:SetSize(geom.width, geom.height or bar:GetHeight())
	bar:ClearAllPoints()
	bar:SetPoint(geom.point, geom.x, geom.y)
end

local function NormalizeVehicleType(vehicleType)
	if vehicleType == "Natural" then
		return "Natural"
	end
	return "Mechanical"
end

-- Vehicle frame chrome only: light → client; dark → Media\shared\dark\vehicles\. Flashes stay client.
function WhoaUF:GetVehicleFrameTexture(file)
	if not file then
		return nil
	end
	if IsFrameDarkEnabled() then
		return AddonBlp(VEHICLE_DARK_MEDIA .. file)
	end
	return BLIZZARD_VEHICLES .. file
end

function WhoaUF:GetPlayerVehicleChrome(vehicleType)
	local key = NormalizeVehicleType(vehicleType)
	local base = VEHICLE_PLAYER_CHROME[key]
	if not base then
		return nil
	end
	return {
		vehicleTexture = self:GetVehicleFrameTexture(base.vehicleFile),
		threatTexture = base.threatTexture,
		health = base.health,
		power = base.power,
		name = base.name,
		backgroundWidth = base.backgroundWidth,
	}
end

function WhoaUF:GetPartyVehicleTexture(vehicleType)
	local file = VEHICLE_PARTY_FILES[NormalizeVehicleType(vehicleType)]
	return self:GetVehicleFrameTexture(file)
end

-- Shared vehicle chrome: bars, name, bg width, vehicle/threat textures (combat-safe).
function WhoaUF:ApplyPlayerVehicleChrome(frame, vehicleType)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	if not frame then
		return
	end
	local chrome = self:GetPlayerVehicleChrome(vehicleType)
	if not chrome then
		return
	end

	if frame.FrameTexture then
		frame.FrameTexture:Hide()
	end
	local vtex = frame.VehicleTexture
	if vtex then
		vtex:SetTexture(chrome.vehicleTexture)
		vtex:Show()
	end

	ApplyBarGeom(frame.Health, chrome.health)
	ApplyBarGeom(frame.Power, chrome.power)
	self:ApplyBarTextToBar(frame.Health)
	self:ApplyBarTextToBar(frame.Power)

	if frame.Name and chrome.name then
		frame.Name:ClearAllPoints()
		frame.Name:SetPoint(chrome.name.point, chrome.name.x, chrome.name.y)
	end
	if frame.Background and chrome.backgroundWidth then
		frame.Background:SetWidth(chrome.backgroundWidth)
	end
	if frame.Level then
		frame.Level:Hide()
	end

	local flash = frame.threatIndicator
	if flash and chrome.threatTexture then
		-- Invalidate cache so exit restore always re-applies player flash art.
		flash.whoaThreatFlashPath = nil
		flash:SetTexture(chrome.threatTexture)
		local t = VEHICLE_THREAT_TEX_COORD
		flash:SetTexCoord(t[1], t[2], t[3], t[4])
		-- PlayerFrameFlash keeps 242×93 when swapping to vehicle sheets (PlayerFrame.xml).
		flash:SetSize(PLAYER_FLASH_W, PLAYER_FLASH_H)
	end
	if self.SyncPlayerNumericThreatAnchor then
		self:SyncPlayerNumericThreatAnchor(frame)
	end
	if WhoaUF._UF and WhoaUF._UF.LayoutGroupIndicator then
		WhoaUF._UF.LayoutGroupIndicator(frame)
	end
end

-- Restore non-vehicle player chrome from the active frame style (PlayerFrame_ToPlayerArt).
function WhoaUF:RestorePlayerFrameChrome(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	if not frame then
		return
	end
	if self.RefreshPlayerFrameFromOptions then
		self:RefreshPlayerFrameFromOptions(frame)
		return
	end
	if frame.VehicleTexture then
		frame.VehicleTexture:Hide()
	end
	if frame.FrameTexture then
		frame.FrameTexture:Show()
		if self.ApplyPlayerFrameBorderArt then
			self:ApplyPlayerFrameBorderArt(frame)
		else
			local path = self:GetFrameTexture("player")
			if path then
				frame.FrameTexture:SetTexture(path)
			end
		end
	end
	frame.state = "player"
	self:ApplyFrameBarLayout(frame, true)
	if frame.threatIndicator then
		frame.threatIndicator.whoaThreatFlashPath = nil
	end
	if self.ApplyPlayerThreatFlashArt then
		self:ApplyPlayerThreatFlashArt(frame)
	elseif frame.threatIndicator then
		frame.threatIndicator:SetTexture(BLIZZARD_PLAYER_FLASH)
		local t = PLAYER_FLASH_TEX_COORD
		frame.threatIndicator:SetTexCoord(t[1], t[2], t[3], t[4])
		frame.threatIndicator:SetSize(PLAYER_FLASH_W, PLAYER_FLASH_H)
	end
	if frame.Level then
		frame.Level:Show()
	end
	if self.LayoutPlayerCombatGlow then
		self:LayoutPlayerCombatGlow(frame)
	end
	if self.ApplyDeathKnightPlayerArt then
		self:ApplyDeathKnightPlayerArt(frame)
	end
	if self.SyncPlayerNumericThreatAnchor then
		self:SyncPlayerNumericThreatAnchor(frame)
	end
	if WhoaUF._UF and WhoaUF._UF.LayoutGroupIndicator then
		WhoaUF._UF.LayoutGroupIndicator(frame)
	end
end

-- Full player-frame re-apply from saved options after vehicle exit (style bars,
-- textures, fonts, DK art, alt mana, class power, threat/status chrome).
function WhoaUF:RefreshPlayerFrameFromOptions(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	if not frame or frame.kind ~= "player" then
		return
	end
	if self.PlayerVehicleSeatActive and self:PlayerVehicleSeatActive() then
		return
	end

	frame.state = "player"
	if frame.VehicleTexture then
		frame.VehicleTexture:Hide()
	end
	if frame.Level then
		frame.Level:Show()
	end
	if frame.Power then
		frame.Power.pauseUpdates = false
	end

	-- Re-establish DK special art first so layout branching matches ApplyFrameStyle.
	if self.ApplyDeathKnightPlayerArt then
		self:ApplyDeathKnightPlayerArt(frame)
	end

	local dkSpecial = self.IsDkSpecialPlayerArtActive and self:IsDkSpecialPlayerArtActive(frame)
	local druidStacked = self.IsDruidStackedPlayerFrameActive and self:IsDruidStackedPlayerFrameActive(frame)

	if not dkSpecial then
		-- Force whoa/thick/classic HP+mana geom even if vehicle HasUI lags one frame.
		self:ApplyFrameBarLayout(frame, true)
		if not druidStacked and frame.FrameTexture then
			frame.FrameTexture:Show()
			if self.ApplyPlayerFrameBorderArt then
				self:ApplyPlayerFrameBorderArt(frame)
			else
				local path = self:GetFrameTexture("player")
				if path then
					frame.FrameTexture:SetTexture(path)
				end
			end
		end
	elseif self.IsDkBlizzconPlayerArtActive and self:IsDkBlizzconPlayerArtActive(frame) then
		if self.ApplyDkBlizzconPlayerLayout then
			self:ApplyDkBlizzconPlayerLayout(frame)
		end
	end

	if self.ApplyFrameStatusBars then
		self:ApplyFrameStatusBars(frame)
	end
	ApplyBarTextFonts(frame.Health)
	ApplyBarTextFonts(frame.Power)

	if frame.threatIndicator then
		frame.threatIndicator.whoaThreatFlashPath = nil
	end
	if self.ApplyPlayerThreatFlashArt then
		self:ApplyPlayerThreatFlashArt(frame)
	end
	if self.ApplyPlayerStatusTexture then
		self:ApplyPlayerStatusTexture(frame)
	end
	if self.LayoutPlayerCombatGlow then
		self:LayoutPlayerCombatGlow(frame)
	end
	if self.RefreshAlternateManaBar then
		self:RefreshAlternateManaBar()
	end
	if self.RestorePlayerClassPowerBars then
		self:RestorePlayerClassPowerBars()
	elseif self.RefreshPlayerClassBars then
		self:RefreshPlayerClassBars()
	end
	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end
	if self.SyncPlayerNumericThreatAnchor then
		self:SyncPlayerNumericThreatAnchor(frame)
	end
	if self.ApplyPowerFeedbackTextures then
		self:ApplyPowerFeedbackTextures()
	end
	self:UpdateUnitFrame(frame)
end

-- Defer retry after vehicle exit — HasUI / seat token can lag the event.
function WhoaUF:SchedulePlayerFrameOptionsRefresh()
	local state = WhoaUF._UF
	if not state then
		return
	end
	state.playerOptionsRefreshGen = (state.playerOptionsRefreshGen or 0) + 1
	local gen = state.playerOptionsRefreshGen
	local function tryRefresh(attempt)
		C_Timer.After(0, function()
			if not WhoaUF._UF or gen ~= WhoaUF._UF.playerOptionsRefreshGen then
				return
			end
			if WhoaUF.PlayerVehicleSeatActive and WhoaUF:PlayerVehicleSeatActive() then
				if attempt < 5 then
					tryRefresh(attempt + 1)
				end
				return
			end
			if WhoaUF.RefreshPlayerFrameFromOptions then
				WhoaUF:RefreshPlayerFrameFromOptions()
			end
		end)
	end
	tryRefresh(1)
end

-- Keep percent/value text inside the bar slots (old whoa packs anchored to the bars).
-- Pet BOTH-mode strings sit closer to the fill (narrow 69px slot).
-- Party BOTH-mode left/right sit 4px closer to the bar edges than the default inset.
local BAR_TEXT_INSET = 5
local PET_BAR_TEXT_INSET = 1
local PARTY_BAR_TEXT_INSET = 1

local function BarTextInsetForKind(kind)
	if kind == "pet" then
		return PET_BAR_TEXT_INSET
	end
	if kind == "party" then
		return PARTY_BAR_TEXT_INSET
	end
	return nil
end

local function ApplyBarTextToBar(bar, inset)
	if not bar then
		return
	end
	if inset == nil then
		inset = BAR_TEXT_INSET
	end
	local y = WhoaUF:GetStatusBarFontTextOffset()
	if bar.TextString then
		bar.TextString:ClearAllPoints()
		bar.TextString:SetPoint("CENTER", bar, "CENTER", 0, y)
	end
	if bar.LeftText then
		bar.LeftText:ClearAllPoints()
		bar.LeftText:SetPoint("LEFT", bar, "LEFT", inset, y)
	end
	if bar.RightText then
		bar.RightText:ClearAllPoints()
		bar.RightText:SetPoint("RIGHT", bar, "RIGHT", -inset, y)
	end
end

function WhoaUF:ApplyBarTextToBar(bar, inset)
	ApplyBarTextToBar(bar, inset)
end

-- Dead / Ghost / Unconscious / Offline labels stay centered in the HP slot across styles.
local function ApplyDeadTextToHealth(frame)
	local health = frame and frame.Health
	if not health then
		return
	end
	local deadText = frame.DeadText
	if deadText then
		deadText:ClearAllPoints()
		deadText:SetPoint("CENTER", health, "CENTER")
	end
	local unconsciousText = frame.UnconsciousText
	if unconsciousText then
		unconsciousText:ClearAllPoints()
		unconsciousText:SetPoint("CENTER", health, "CENTER")
	end
end

local function ApplyLayoutExtras(frame, layout)
	if frame.Name and layout.name then
		local name = layout.name
		frame.Name:ClearAllPoints()
		frame.Name:SetPoint(name.point, name.x, name.y)
		if name.width then
			frame.Name:SetSize(name.width, name.height or 12)
		end
		if name.justify then
			frame.Name:SetJustifyH(name.justify)
		end
		if frame.Name.SetWordWrap then
			frame.Name:SetWordWrap(false)
		end
	end
	if frame.Background and layout.background and not frame.isMinus then
		local bg = layout.background
		local width, height = bg.width, bg.height
		-- Pet no-mana: alpha fill only the HP slot (mana chrome is gone).
		if frame.kind == "pet" then
			local hasMana = true
			local unit = frame.unit or "pet"
			if UnitExists(unit) then
				local powerType = UnitPowerType(unit)
				local pmax = UnitPowerMax(unit, powerType)
				if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(pmax) then
					hasMana = pmax > 0
				else
					hasMana = true
				end
			elseif frame.Power and frame.Power.IsShown then
				hasMana = frame.Power:IsShown()
			end
			if not hasMana and layout.health then
				width, height = layout.health.width, layout.health.height
			end
		end
		frame.Background:ClearAllPoints()
		frame.Background:SetSize(width, height)
		frame.Background:SetPoint(bg.point, bg.x, bg.y)
	end
	if frame.NameBackground then
		if layout.hideNameBackground then
			frame.NameBackground:Hide()
		elseif WhoaUF.ShouldShowNameBackground and WhoaUF:ShouldShowNameBackground(frame) then
			-- Classification may still hide for minus units.
			if not frame.isMinus then
				frame.NameBackground:Show()
			end
		end
	end
end

-- Minus / critter chrome: shared art + classic one-bar geometry (TargetFrame CheckClassification).
-- Style packs never apply to minus border, bars, bg, or threat flash.
local MINUS_TARGET_BG = { width = 119, height = 12, point = "TOPRIGHT", x = -89.5, y = -44 }

local function HidePowerBarTextLocal(bar)
	if not bar then
		return
	end
	if bar.TextString then
		bar.TextString:Hide()
	end
	if bar.LeftText then
		bar.LeftText:Hide()
	end
	if bar.RightText then
		bar.RightText:Hide()
	end
end

local function ApplyMinusTargetName(frame)
	local classicLayout = FRAME_STYLE_BARS.classic[frame.kind]
	if frame.Name and classicLayout and classicLayout.name then
		local name = classicLayout.name
		frame.Name:ClearAllPoints()
		frame.Name:SetPoint(name.point, name.x, name.y)
	end
end

local function ApplyMinusTargetChrome(frame)
	if not frame then
		return
	end
	local classicLayout = FRAME_STYLE_BARS.classic[frame.kind]
	local healthGeom = classicLayout and classicLayout.health
	ApplyBarGeom(frame.Health, healthGeom or {
		width = 119,
		height = 12,
		point = "TOPRIGHT",
		x = -90,
		y = -45,
	})
	ApplyBarTextToBar(frame.Health)
	ApplyDeadTextToHealth(frame)
	ApplyMinusTargetName(frame)
	if frame.Background then
		frame.Background:ClearAllPoints()
		frame.Background:SetSize(MINUS_TARGET_BG.width, MINUS_TARGET_BG.height)
		frame.Background:SetPoint(MINUS_TARGET_BG.point, frame, MINUS_TARGET_BG.point, MINUS_TARGET_BG.x, MINUS_TARGET_BG.y)
	end
	if frame.NameBackground then
		frame.NameBackground:Hide()
	end
	if frame.Power then
		frame.Power.pauseUpdates = true
		HidePowerBarTextLocal(frame.Power)
		frame.Power:Hide()
	end
	if WhoaUF.SyncHealPredictionLayout then
		WhoaUF:SyncHealPredictionLayout(frame)
	end
end

function WhoaUF:GetTargetChromeKey(unit)
	if not unit or not UnitExists(unit) then
		return nil
	end
	if self.IsMinusUnit and self:IsMinusUnit(unit) then
		return "minus"
	end
	local classification = UnitClassification(unit)
	-- Mainline: classification may be secret — fall back to normal chrome.
	if not self:CanAccessValue(classification) then
		return "normal"
	end
	if classification == "worldboss" or classification == "elite" then
		return "elite"
	end
	if classification == "rareelite" then
		return "rareelite"
	end
	if classification == "rare" then
		return "rare"
	end
	return "normal"
end

-- Target/focus classification chrome (border, bg, bars, threat flash, hit rect).
function WhoaUF:ApplyTargetClassificationChrome(frame)
	if not frame or (frame.kind ~= "target" and frame.kind ~= "focus") then
		return
	end
	local unit = frame.unit
	if not unit or not UnitExists(unit) then
		return
	end

	local key = self:GetTargetChromeKey(unit)
	frame.whoaChromeKey = key
	frame.isMinus = (key == "minus") or nil
	frame.haveElite = (key == "elite" or key == "rareelite" or key == "rare") or nil

	-- Bind the border sheet before bar layout. Frame alpha hold (target/focus)
	-- keeps bars invisible until the sheet has loaded (see HoldTargetFrameReveal).
	if frame.FrameTexture then
		local path = self:GetFrameTexture(key)
		if path then
			frame.FrameTexture:SetTexture(path)
			frame.FrameTexture:SetAlpha(1)
			frame.whoaChromePainted = true
		end
	end

	if frame.isMinus then
		ApplyMinusTargetChrome(frame)
	else
		if frame.Power then
			frame.Power.pauseUpdates = false
		end
		self:ApplyFrameBarLayout(frame)
	end

	if self.UpdateThreatFlashLayout then
		self:UpdateThreatFlashLayout(frame)
	end
	if self.AdjustSpellBar then
		self:AdjustSpellBar(frame)
	end

	if frame.NameBackground then
		if frame.isMinus or not self:ShouldShowNameBackground(frame) or not self:ShouldDisplayUnitName(frame) then
			frame.NameBackground:Hide()
		else
			frame.NameBackground:Show()
		end
	end
end

function WhoaUF:RestoreTargetFrameChrome(frame)
	self:ApplyTargetClassificationChrome(frame)
end

function WhoaUF:ApplyFrameBarLayout(frame, force)
	if not frame or not frame.Health then
		return
	end
	-- Vehicle art owns player bar geometry only while frame.state is still "vehicle".
	-- Exit restore sets state to "player" first so style bars re-apply even if
	-- UnitHasVehiclePlayerFrameUI lags for a frame. force=true skips this gate.
	-- DevTools force-show vehicle also owns bar geometry without flipping state.
	if not force
		and frame.kind == "player"
		and (
			(frame.state == "vehicle"
				and WhoaUF.IsPlayerVehicleFrameActive
				and WhoaUF:IsPlayerVehicleFrameActive(frame))
			or (WhoaUF.GetForceShowVehicleType and WhoaUF:GetForceShowVehicleType())
		)
	then
		return
	end
	if not force and frame.kind == "player" and self.IsDkBlizzconPlayerArtActive and self:IsDkBlizzconPlayerArtActive(frame) then
		if self.ApplyDkBlizzconPlayerLayout then
			self:ApplyDkBlizzconPlayerLayout(frame)
		end
		return
	end
	if not force and frame.kind == "player" and self.IsDkAlphaPlayerArtActive and self:IsDkAlphaPlayerArtActive(frame) then
		return
	end
	-- Target/focus: derive minus from the live unit so stale frame.isMinus cannot apply whoa bars.
	if frame.kind == "target" or frame.kind == "focus" then
		local unit = frame.unit
		if unit and UnitExists(unit) and self.IsMinusUnit then
			frame.isMinus = self:IsMinusUnit(unit) or nil
		end
	end
	-- Minus / critter: Classic one-bar slot (CheckClassification), not Whoa/thick HP+MP/name.
	if frame.isMinus then
		ApplyMinusTargetChrome(frame)
		return
	end
	local layout = self:GetFrameBarLayout(frame.kind)
	if not layout then
		return
	end
	ApplyBarGeom(frame.Health, layout.health)
	ApplyBarTextToBar(frame.Health, BarTextInsetForKind(frame.kind))
	ApplyDeadTextToHealth(frame)
	if frame.Power and layout.power then
		ApplyBarGeom(frame.Power, layout.power)
		-- Pet mana text stays on stock PetFrame.xml TOPLEFT anchors (y=-38), not bar-center.
		if frame.kind ~= "pet" then
			ApplyBarTextToBar(frame.Power, BarTextInsetForKind(frame.kind))
		end
		if WhoaUF.SyncFullPowerFrameLayout then
			WhoaUF:SyncFullPowerFrameLayout(frame.Power)
		end
		if frame.kind == "player" and WhoaUF.SyncTickGlowLayout then
			WhoaUF:SyncTickGlowLayout(frame)
		end
	end
	ApplyLayoutExtras(frame, layout)
	if self.SyncHealPredictionLayout then
		self:SyncHealPredictionLayout(frame)
	end
	if frame.kind == "player" and self.SyncAlternateManaBarLayout then
		self:SyncAlternateManaBarLayout(frame)
	end
end

local function ApplyStaticBorder(frame, textureKey)
	if frame and frame.FrameTexture and textureKey then
		if frame.kind == "player" and WhoaUF.ApplyPlayerFrameBorderArt then
			WhoaUF:ApplyPlayerFrameBorderArt(frame)
		else
			local path = WhoaUF:GetFrameTexture(textureKey)
			if path then
				frame.FrameTexture:SetTexture(path)
			end
			-- Never leave non-target borders cloaked from a prior chrome hold mistake.
			if frame.kind ~= "target" and frame.kind ~= "focus" then
				frame.FrameTexture:SetAlpha(1)
			end
		end
	end
	if frame and frame.kind == "player" and WhoaUF.ApplyDeathKnightPlayerArt then
		WhoaUF:ApplyDeathKnightPlayerArt(frame)
	end
end

-- Whole-frame scale (Settings "Frame scale" slider). Percent → SetScale on roots.
local FRAME_SCALE_MIN, FRAME_SCALE_MAX, FRAME_SCALE_STEP = 50, 200, 5
local FRAME_SCALE_DEFAULT = 100
local BOSS_FRAME_SCALE = 0.75
local SMALL_FOCUS_SCALE = 0.75

function WhoaUF:GetFrameScaleRange()
	return FRAME_SCALE_MIN, FRAME_SCALE_MAX, FRAME_SCALE_STEP, FRAME_SCALE_DEFAULT
end

function WhoaUF:ClampFrameScalePercent(value)
	value = tonumber(value) or FRAME_SCALE_DEFAULT
	if value < FRAME_SCALE_MIN then
		value = FRAME_SCALE_MIN
	elseif value > FRAME_SCALE_MAX then
		value = FRAME_SCALE_MAX
	end
	-- Snap to step so Edit Mode / slider stay aligned.
	local step = FRAME_SCALE_STEP
	return math.floor((value / step) + 0.5) * step
end

function WhoaUF:GetFrameScalePercent()
	return self:ClampFrameScalePercent(self.db and self.db.frameScale)
end

function WhoaUF:GetFrameScale()
	return self:GetFrameScalePercent() / 100
end

local function SetFrameScaleSafe(frame, scale)
	if not frame or not frame.SetScale or type(scale) ~= "number" or scale <= 0 then
		return
	end
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
		return false
	end
	frame:SetScale(scale)
	return true
end

-- Keep the frame's visual position when scale changes (Edit Mode SetScaleOverride math).
local function ReanchorFrameForScaleChange(frame, oldScale, newScale)
	if not frame or not oldScale or not newScale or oldScale <= 0 or newScale <= 0 then
		return
	end
	if oldScale == newScale then
		return
	end
	if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
		return
	end
	local setPoint = frame.SetPointBase or frame.SetPoint
	if not setPoint then
		return
	end
	local numPoints = frame:GetNumPoints()
	if numPoints < 1 then
		return
	end
	local factor = oldScale / newScale
	for i = 1, numPoints do
		local point, relativeTo, relativePoint, offsetX, offsetY = frame:GetPoint(i)
		setPoint(
			frame,
			point,
			relativeTo,
			relativePoint,
			(offsetX or 0) * factor,
			(offsetY or 0) * factor
		)
	end
end

local function PersistFrameAnchorToDb(frame)
	if not frame or not frame.kind or not WhoaUF.db or type(WhoaUF.db.frames) ~= "table" then
		return
	end
	local cfg = WhoaUF.db.frames[frame.kind]
	if type(cfg) ~= "table" or not frame.GetPoint or frame:GetNumPoints() < 1 then
		return
	end
	local point, relativeTo, relativePoint, offsetX, offsetY = frame:GetPoint(1)
	cfg.point = point
	cfg.relativePoint = relativePoint or point
	cfg.x = offsetX or 0
	cfg.y = offsetY or 0
	if relativeTo and relativeTo.GetName then
		cfg.relativeTo = relativeTo:GetName() or "UIParent"
	else
		cfg.relativeTo = "UIParent"
	end
end

local function SetFrameScaleWithReanchor(frame, scale)
	if not frame or type(scale) ~= "number" or scale <= 0 then
		return
	end
	local oldScale = frame.GetScale and frame:GetScale() or 1
	-- Edit Mode installs SetScaleOverride, which already compensates offsets.
	local scaleOverride = EditModeSystemMixin and EditModeSystemMixin.SetScaleOverride
	local alreadyReanchors = WhoaUF.editModePreviewActive
		or (scaleOverride and frame.SetScale == scaleOverride)
	if not SetFrameScaleSafe(frame, scale) then
		return false
	end
	if not alreadyReanchors then
		ReanchorFrameForScaleChange(frame, oldScale, scale)
		PersistFrameAnchorToDb(frame)
	end
	return true
end

function WhoaUF:SetFocusFrameScale(scale)
	local focus = self.unitFrames and self.unitFrames.focus
	if not focus then
		return
	end
	if type(scale) ~= "number" or scale <= 0 then
		scale = self:GetEffectiveFrameScale(focus)
	end
	return SetFrameScaleWithReanchor(focus, scale)
end

function WhoaUF:IsFocusUsingSmallScale(frame)
	frame = frame or (self.unitFrames and self.unitFrames.focus)
	if not frame then
		return false
	end
	if frame.HasSetting
		and frame.GetSettingValueBool
		and Enum
		and Enum.EditModeUnitFrameSetting
		and frame:HasSetting(Enum.EditModeUnitFrameSetting.UseLargerFrame)
	then
		return not frame:GetSettingValueBool(Enum.EditModeUnitFrameSetting.UseLargerFrame)
	end
	return false
end

function WhoaUF:GetEffectiveFrameScale(frame)
	local scale = self:GetFrameScale()
	if not frame then
		return scale
	end
	if frame.kind == "boss" or frame.isBossFrame then
		return scale * BOSS_FRAME_SCALE
	end
	if frame.kind == "focus" and self:IsFocusUsingSmallScale(frame) then
		return scale * SMALL_FOCUS_SCALE
	end
	return scale
end

function WhoaUF:ApplyFrameScale()
	local uf = self.unitFrames
	if not uf then
		return
	end
	if InCombatLockdown() then
		if WhoaUF._UF then
			WhoaUF._UF.pendingFrameScale = true
		end
		return
	end
	if WhoaUF._UF then
		WhoaUF._UF.pendingFrameScale = nil
	end

	local scale = self:GetFrameScale()
	-- Scale only top-level roots. Children (ToT, pet, party members) inherit.
	SetFrameScaleSafe(uf.player, scale)
	SetFrameScaleSafe(uf.target, scale)
	if uf.focus then
		-- Reanchor so focus stays put when scale / large-small size changes.
		self:SetFocusFrameScale(self:GetEffectiveFrameScale(uf.focus))
	end
	if uf.party then
		-- Raid-style party uses Compact frames; keep Whoa container at 1 like Blizzard.
		-- Mainline: never HasSetting on PartyFrame / Mixined systems (CUF taint).
		local raidStyle = self.IsRaidStylePartyFramesEnabled and self:IsRaidStylePartyFramesEnabled()
		SetFrameScaleSafe(uf.party, raidStyle and 1 or scale)
	end
	for i = 1, 5 do
		local boss = uf["boss" .. i]
		if boss then
			SetFrameScaleSafe(boss, scale * BOSS_FRAME_SCALE)
		end
	end
end

function WhoaUF:ApplyFrameStyle()
	cachedFrameStyle = nil
	cachedFrameDark = nil
	cachedFrameMediaRoot = nil
	cachedSharedMediaRoot = nil

	-- Force-load classification sheets so the first target paint does not wait on disk.
	local preload = self._frameChromePreload
	if not preload then
		preload = UIParent:CreateTexture(nil, "BACKGROUND")
		preload:SetSize(1, 1)
		preload:Hide()
		self._frameChromePreload = preload
	end
	local chromeKeys = { "normal", "elite", "rare", "rareelite", "minus" }
	for i = 1, #chromeKeys do
		local path = self:GetFrameTexture(chromeKeys[i])
		if path then
			preload:SetTexture(path)
		end
	end

	local uf = self.unitFrames
	if not uf then
		return
	end

	local canLayout = not InCombatLockdown()

	for _, frame in pairs(uf) do
		if type(frame) == "table" and frame.kind then
			local kind = frame.kind
			-- Drop cached texture paths so light↔dark swaps rebind immediately.
			frame.whoaChromeKey = nil
			if frame.kind == "target" or frame.kind == "focus" then
				frame.whoaChromePainted = nil
			end
			if frame.threatIndicator then
				frame.threatIndicator.whoaThreatFlashPath = nil
			end
			if frame.StatusTexture then
				frame.StatusTexture.whoaPlayerStatusPath = nil
			end
			local dkSpecial = kind == "player"
				and self.IsDkSpecialPlayerArtActive
				and self:IsDkSpecialPlayerArtActive(frame)
			local classificationChrome = kind == "target" or kind == "focus"
			if canLayout and not dkSpecial and not classificationChrome then
				self:ApplyFrameBarLayout(frame)
			end
			if kind == "player" then
				-- Stacked druid chrome replaces the player border; RefreshAlternateManaBar restores it.
				local druidStacked = self.IsDruidStackedPlayerFrameActive and self:IsDruidStackedPlayerFrameActive(frame)
				if not dkSpecial
					and frame.state ~= "vehicle"
					and not druidStacked
					and not (WhoaUF.GetForceShowVehicleType and WhoaUF:GetForceShowVehicleType())
					and not (WhoaUF.IsPlayerVehicleFrameActive and WhoaUF:IsPlayerVehicleFrameActive(frame)) then
					ApplyStaticBorder(frame, "player")
				end
			elseif kind == "target" or kind == "focus" then
				if canLayout then
					if frame.unit and UnitExists(frame.unit) then
						self:ApplyTargetClassificationChrome(frame)
					else
						self:ApplyFrameBarLayout(frame)
						ApplyStaticBorder(frame, "normal")
					end
				end
			elseif kind == "tot" or kind == "focustot" then
				ApplyStaticBorder(frame, "tot")
			elseif kind == "boss" then
				if canLayout then
					self:ApplyFrameBarLayout(frame)
				end
				ApplyStaticBorder(frame, "boss")
			elseif kind == "party" then
				if canLayout then
					self:ApplyFrameBarLayout(frame)
				end
				ApplyStaticBorder(frame, "party")
				self:ApplyPartyChromeLayering(frame)
				self:ApplyPartyFlashArt(frame)
				if self.ApplyFrameStatusBars then
					self:ApplyFrameStatusBars(frame)
				end
				if frame.PetFrame then
					self:ApplyPartyFlashArt(frame.PetFrame)
					ApplyStaticBorder(frame.PetFrame, "partyPet")
					if self.ApplyFrameStatusBars then
						self:ApplyFrameStatusBars(frame.PetFrame)
					end
				end
			elseif kind == "pet" then
				-- Pet mana/no-mana border is chosen in UpdatePetFrame / UpdatePetPower.
				if self.ApplyPetFrameArt then
					self:ApplyPetFrameArt(frame)
				end
			end
			-- target/focus classification textures applied via UpdateUnitFrame.
		end
	end

	if self.RefreshAlternateManaBar then
		self:RefreshAlternateManaBar()
	end
	if self.ApplyPlayerClassPowerArt then
		self:ApplyPlayerClassPowerArt()
	end
	if self.ApplyComboFrameArt then
		self:ApplyComboFrameArt()
	end
	if self.ApplyAllSpellbarArt then
		self:ApplyAllSpellbarArt()
	end
	if self.ApplyAllNumericThreatArt then
		self:ApplyAllNumericThreatArt()
	end
	if self.RefreshAllUnitFrames then
		self:RefreshAllUnitFrames()
	end
	if self.UpdateAllPartyFrames then
		self:UpdateAllPartyFrames()
	end
	if self.UpdatePetFrame then
		self:UpdatePetFrame()
	end
	-- Last: DK art first, then status glow (thick + DK alpha use custom status sheets).
	-- Live / force-show vehicle chrome must rebind after frameDark so light↔dark
	-- swaps Media\shared\dark\vehicles (ApplyForceShowVehicleArt alone early-outs on a seat).
	local player = uf.player
	if player then
		local vehicleArtActive = self.IsVehiclePlayerArtActive and self:IsVehiclePlayerArtActive(player)
		if self.ApplyDeathKnightPlayerArt and not vehicleArtActive then
			self:ApplyDeathKnightPlayerArt(player)
		end
		if self.IsPlayerVehicleFrameActive and self:IsPlayerVehicleFrameActive(player) then
			if self.ApplyPlayerVehicleVisuals then
				self:ApplyPlayerVehicleVisuals()
			end
		elseif self.ApplyForceShowVehicleArt then
			self:ApplyForceShowVehicleArt()
		end
		if not vehicleArtActive then
			self:ApplyPlayerStatusTexture(player)
			if self.ApplyPlayerThreatFlashArt then
				self:ApplyPlayerThreatFlashArt(player)
			end
			-- After DK/status/flash: keep stacked DRUID rim on the active style + elite border.
			if self.IsDruidStackedPlayerFrameActive
				and self:IsDruidStackedPlayerFrameActive(player)
				and self.ApplyDruidStackedPlayerFrameArt then
				self:ApplyDruidStackedPlayerFrameArt(player)
			end
		elseif self.ApplyPlayerStatusTexture then
			-- Vehicle owns border + threat flash; status glow can still follow theme.
			self:ApplyPlayerStatusTexture(player)
		end
	end

	if self.ApplyFrameScale then
		self:ApplyFrameScale()
	end
end
