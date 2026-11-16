--[[
	Appearance: bar textures/fonts, aura size, name background, health tint.
	Colors: Util.lua. Chrome packs: Theme.lua.
]]

local ADDON_NAME = ...
local ADDON_MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
-- Always pin .blp — extensionless SetTexture can hit a neighboring .png / other addon.
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

function WhoaUF:ApplyBarTextFonts(bar)
	if not bar then
		return
	end
	self:ApplyStatusBarTextFont(bar.TextString)
	self:ApplyStatusBarTextFont(bar.LeftText)
	self:ApplyStatusBarTextFont(bar.RightText)
	self:ApplyStatusBarTextFont(bar.StockText)
	self:ApplyStatusBarTextFont(bar.StackedCenter)
	self:ApplyStatusBarTextFont(bar.StackedLeft)
	self:ApplyStatusBarTextFont(bar.StackedRight)
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
			self:ApplyBarTextFonts(frame.Health)
			self:ApplyBarTextFonts(frame.Power)
			RestoreLifeStatusLabelFont(frame.DeadText)
			RestoreLifeStatusLabelFont(frame.UnconsciousText)
			self:ApplyBarTextFonts(frame.AlternateManaBar)
			self:ApplyBarTextFonts(frame.MonkStaggerBar)
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
	-- nil = no tint option (Classic green). Do not truth-test r — custom blue is r=0.
	if r ~= nil then
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

local function ApplyPowerBarTextureOrAtlas(self, bar, manaTexture)
	if not bar then
		return
	end
	-- Special powers (insanity / maelstrom / …) keep Blizzard atlas art.
	if self.ApplyPowerBarTypeVisual and (bar.powerToken or bar.powerType) then
		if self:PowerBarUsesNaturalAtlas(bar.powerToken, bar.powerType) then
			self:ApplyPowerBarTypeVisual(bar, bar.powerToken, bar.powerType)
			return
		end
	end
	if bar.whoaPowerUsesAtlas then
		-- Type no longer atlas-backed; clear so ApplyBarTexture rebinds.
		bar.whoaPowerUsesAtlas = false
		bar.whoaTexture = nil
	end
	ApplyBarTexture(bar, manaTexture)
end

-- Apply current texture (+ optional health color) to one Whoa frame's bars.
function WhoaUF:ApplyFrameStatusBars(frame, applyColor)
	if not frame then
		return
	end
	local hp, mana = self:GetStatusBarTexturePaths()
	ApplyBarTexture(frame.Health, hp)
	ApplyPowerBarTextureOrAtlas(self, frame.Power, mana)
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
			ApplyPowerBarTextureOrAtlas(self, frame.Power, mana)
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
	-- Clear party tint caches before the shared refresh (UpdatePartyMemberFrame skips hidden).
	if self.RefreshPartyHealthBarColors then
		self:RefreshPartyHealthBarColors()
	end
	-- RefreshAllUnitFrames already routes party/pet via UpdateUnitFrame.
	if self.RefreshAllUnitFrames then
		self:RefreshAllUnitFrames()
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
	elseif WhoaUF.UnitIsPlayerOrSecret and WhoaUF:UnitIsPlayerOrSecret(unit) then
		-- Other players (or secret identity) keep class / custom; never NPC cycle.
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

-- Frame chrome / ApplyFrameStyle: Core/Theme.lua
