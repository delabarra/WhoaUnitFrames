--[[
	Theme: frame chrome packs (whoa/thick/classic x light/dark), media roots,
	GetFrameTexture, vehicle/DK/party chrome, ApplyFrameStyle / bar geometry.
	Status-bar textures, fonts, health tint, and aura size stay in Appearance.lua.
]]

local ADDON_NAME = ...
local ADDON_MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local CLASS_POWER_MEDIA = ADDON_MEDIA .. "shared\\dark\\classpower\\"

local function AddonBlp(path)
	if type(path) ~= "string" or path == "" then
		return path
	end
	if path:sub(-4):lower() == ".blp" then
		return path
	end
	return path .. ".blp"
end

local function GetOption(key, default)
	local db = WhoaUF.db
	if not db or db[key] == nil then
		return default
	end
	return db[key]
end

---------------------------------------------------------------------------
-- Frame styles: whoa / thick / classic × light / dark + bar geometry
---------------------------------------------------------------------------

local BLIZZARD_TARGETING = "Interface\\TargetingFrame\\"
local BLIZZARD_PLAYER_STATUS = "Interface\\CharacterFrame\\UI-Player-Status"
-- DK chrome: Media\dk\{light|dark}\ + Media\shared\dk\ (not rune/classbar).
local DK_FRAME_MEDIA = ADDON_MEDIA .. "dk\\"
local DK_SHARED_MEDIA = ADDON_MEDIA .. "shared\\dk\\"
local PLAYER_FLASH_TEX_COORD = { 0.9453125, 0, 0, 0.181640625 }
local PLAYER_FLASH_W, PLAYER_FLASH_H = 242, 93
local BLIZZARD_PLAYER_FLASH = BLIZZARD_TARGETING .. "UI-TargetingFrame-Flash"
local PLAYER_STATUS_TEXCOORD_CLASSIC = { 0, 0.74609375, 0, 0.53125 }
local PLAYER_STATUS_TEXCOORD_MEDIA = { 0, 1, 0, 1 }
local PLAYER_STATUS_W, PLAYER_STATUS_H = 190, 66
local PLAYER_STATUS_MEDIA_W, PLAYER_STATUS_MEDIA_H = 256, 128
-- Stock UI-Player-Status crop; thick + DK alpha use full 256×128 sheets.
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

-- ClassResource rim sheets; geometry in FRAME_STYLE_BARS; border remaps like player chrome.
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
	partyPet = "UI-PartyFrame", -- path chosen in GetFrameTexture
	pet = "UI-SmallTargetingFrame",
	petNoMana = "UI-SmallTargetingFrame-NoMana",
	boss = "UI-UnitFrame-Boss",
	bossFlash = "UI-UnitFrame-Boss-Flash",
	pvpFFA = "UI-PVP-FFA",
	pvpAlliance = "UI-PVP-Alliance",
	pvpHorde = "UI-PVP-Horde",
}

-- Classic: client TargetingFrame sheets. Mainline: Media packs (no UI-UnitFrame-Boss).
local CLIENT_ONLY_FRAME_TEXTURES = {
	bossFlash = true,
}

local ADDON_ONLY_FRAME_TEXTURES = {
	playerDruid = true,
	playerDruidElite = true,
	playerDruidRareElite = true,
	playerDruidFlash = true,
}

-- Shared keys: light → client; dark → Media\shared\dark\. Party/pet resolved in GetFrameTexture.
local SHARED_FRAME_TEXTURE_KEYS = {
	minus = true,
	pvpFFA = true,
	pvpAlliance = true,
	pvpHorde = true,
}

local STYLE_USES_ADDON_LIGHT = {
	whoa = true,
	thick = true,
	classic = false,
}

-- Vehicle chrome: one table for UnitFrame + combat-safe paths. Flashes always client.
local BLIZZARD_VEHICLES = "Interface\\Vehicles\\"local VEHICLE_DARK_MEDIA = ADDON_MEDIA .. "shared\\dark\\vehicles\\"
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

-- Player border sheets (DK specialty art ignores this).
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
	db.altManaBarStyle = "stacked"

	-- Legacy portrait flags → portraitMode (old "3d" → normal).
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

	-- Legacy boolean → nameBackground enum.
	if db.nameBackground == nil and db.showTargetNameBackground ~= nil then
		db.nameBackground = db.showTargetNameBackground and "target" or "none"
	end
	db.nameBackground = NormalizeNameBackground(db.nameBackground)
	db.showTargetNameBackground = nil

	-- Legacy boolean → hideName enum.
	if db.hideName == nil and db.hidePlayerName ~= nil then
		db.hideName = db.hidePlayerName and "always" or "auto"
	end
	db.hideName = NormalizeHideName(db.hideName)
	db.hidePlayerName = nil

	-- Legacy boolean → classColor mode.
	db.classColor = NormalizeClassColor(db.classColor)

	-- Legacy react/blizz/cycle → npcColor mode.
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
end

function WhoaUF:IsFrameDarkVariant()
	return IsFrameDarkEnabled()
end

function WhoaUF:AddonBlp(path)
	return AddonBlp(path)
end

function WhoaUF:GetSharedMediaRoot()
	return GetSharedMediaRoot()
end

function WhoaUF:RefreshFrameMediaCache(style)
	return RefreshFrameMediaCache(style)
end

-- Class power sheets: light → client; dark → Media\shared\dark\classpower\.
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
	-- FlipBook atlases must keep SetAtlas. Dark remapping via SetTexture + one-cell
	-- UVs freezes FlipBook (frameWidth/Height 0 reads atlas grid metadata).
	if atlasName:find("[Ff]lip[Bb]ook") or atlasName == "UF-DruidCP-Slash" then
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

-- ClassResource rim chrome: same border remap as GetPlayerFrameTextureKey.
-- Pack keys stay playerDruid* (Blizzard UI-TARGETINGFRAME-DRUID* asset names).
function WhoaUF:GetClassResourceRimTextureKey()
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

-- Texture path + size / texcoords / anchor for the ClassResource rim player border.
-- While the rim is active, FrameTexture is the DRUID sheet (elite remap included).
function WhoaUF:ApplyClassResourceRimArt(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	local tex = frame and frame.FrameTexture
	if not tex then
		return
	end
	local path = self:GetClassResourceRimTexture()
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
	-- ClassResource rim owns the border; keep elite/style on the DRUID sheets.
	if self.IsClassResourceRimActive and self:IsClassResourceRimActive(frame) then
		self:ApplyClassResourceRimArt(frame)
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

--- Player threat flash. Style-pack UI-TARGETINGFRAME-FLASH is for the ClassResource
--- rim only; all player-side flashes use mirrored PlayerFrame.xml texcoords.
function WhoaUF:ApplyPlayerThreatFlashArt(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	local flash = frame and frame.threatIndicator
	if not flash then
		return
	end
	local path
	local classResourceRim = self.IsClassResourceRimActive and self:IsClassResourceRimActive(frame)
	if classResourceRim then
		path = self:GetClassResourceRimFlashTexture()
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
	-- ClassResource rim: remaps "playerDruid" → elite / rareelite DRUID sheets.
	if key == "playerDruid" then
		key = self:GetClassResourceRimTextureKey()
	end
	local file = FRAME_TEXTURE_FILES[key]
	if not file then
		return nil
	end
	if key == "playerDruid" or key == "playerDruidElite" or key == "playerDruidRareElite" then
		return self:GetClassResourceRimTexture()
	end
	if key == "playerDruidFlash" then
		return self:GetClassResourceRimFlashTexture()
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

function WhoaUF:GetClassResourceRimTexture()
	local key = self:GetClassResourceRimTextureKey()
	local file = FRAME_TEXTURE_FILES[key] or FRAME_TEXTURE_FILES.playerDruid
	return AddonBlp(GetFrameMediaRoot(self:GetFrameStyle()) .. file)
end

function WhoaUF:GetClassResourceRimFlashTexture()
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
	local classResourceRim = self.IsClassResourceRimActive and self:IsClassResourceRimActive(frame)

	if not dkSpecial then
		-- Force whoa/thick/classic HP+mana geom even if vehicle HasUI lags one frame.
		self:ApplyFrameBarLayout(frame, true)
		if not classResourceRim and frame.FrameTexture then
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
	if self.ApplyBarTextFonts then
		self:ApplyBarTextFonts(frame.Health)
		self:ApplyBarTextFonts(frame.Power)
	end

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

-- Whole-frame scale from Blizzard Edit Mode Frame Size (per system).
-- Ref: EditModeUnitFrameSystemMixin:UpdateSystemSettingFrameSize / FocusFrameMixin:SetSmallSize
local FRAME_SIZE_DEFAULT = 100
local SMALL_UNIT_FRAME_SCALE = 0.75

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

local function ResolveScaleKind(frameOrKind)
	if type(frameOrKind) == "string" then
		return frameOrKind
	end
	if not frameOrKind then
		return nil
	end
	if frameOrKind.kind == "boss" or frameOrKind.isBossFrame then
		return "boss"
	end
	return frameOrKind.kind
end

-- Percent from Edit Mode layout / Mixined system (EditMode_*.lua). Default 100.
function WhoaUF:GetFrameSizePercent(kind)
	kind = ResolveScaleKind(kind)
	if not kind then
		return FRAME_SIZE_DEFAULT
	end
	if self.GetEditModeFrameSizePercent then
		local percent = self:GetEditModeFrameSizePercent(kind)
		if type(percent) == "number" and percent > 0 then
			return percent
		end
	end
	return FRAME_SIZE_DEFAULT
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
	-- Mainline/Forever: Whoa is not registered — read layout fields only.
	if self.IsEditModeFocusUseLargerFrame then
		local larger = self:IsEditModeFocusUseLargerFrame()
		if larger ~= nil then
			return not larger
		end
	end
	return false
end

function WhoaUF:IsBossUsingSmallScale()
	if self.IsEditModeBossUseLargerFrame then
		local larger = self:IsEditModeBossUseLargerFrame()
		if larger ~= nil then
			return not larger
		end
	end
	-- Blizzard default boss size is small (0.75) when UseLargerFrame is unset.
	return true
end

-- Blizzard-equivalent effective scale for a Whoa root (FrameSize ± UseLargerFrame).
function WhoaUF:GetEffectiveFrameScale(frameOrKind)
	local kind = ResolveScaleKind(frameOrKind)
	if not kind then
		return 1
	end
	if kind == "focus" then
		if self:IsFocusUsingSmallScale(frameOrKind) then
			return SMALL_UNIT_FRAME_SCALE
		end
		return self:GetFrameSizePercent("focus") / 100
	end
	if kind == "boss" then
		if self:IsBossUsingSmallScale() then
			return SMALL_UNIT_FRAME_SCALE
		end
		return self:GetFrameSizePercent("boss") / 100
	end
	if kind == "party" then
		local raidStyle = self.IsRaidStylePartyFramesEnabled and self:IsRaidStylePartyFramesEnabled()
		if raidStyle then
			return 1
		end
	end
	return self:GetFrameSizePercent(kind) / 100
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

	-- Scale only top-level roots. Children (ToT, pet, party members) inherit.
	SetFrameScaleSafe(uf.player, self:GetEffectiveFrameScale("player"))
	SetFrameScaleSafe(uf.target, self:GetEffectiveFrameScale("target"))
	if uf.focus then
		-- Reanchor so focus stays put when scale / large-small size changes.
		self:SetFocusFrameScale(self:GetEffectiveFrameScale(uf.focus))
	end
	if uf.party then
		SetFrameScaleSafe(uf.party, self:GetEffectiveFrameScale("party"))
	end
	local bossScale = self:GetEffectiveFrameScale("boss")
	for i = 1, 5 do
		local boss = uf["boss" .. i]
		if boss then
			SetFrameScaleSafe(boss, bossScale)
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
				-- ClassResource rim replaces the player border; RefreshAlternateManaBar restores it.
				local classResourceRim = self.IsClassResourceRimActive and self:IsClassResourceRimActive(frame)
				if not dkSpecial
					and frame.state ~= "vehicle"
					and not classResourceRim
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
	if self.ApplyPersonalResourceDisplayTint then
		self:ApplyPersonalResourceDisplayTint()
	end
	if self.ApplyAllNumericThreatArt then
		self:ApplyAllNumericThreatArt()
	end
	if self.RefreshAllUnitFrames then
		self:RefreshAllUnitFrames()
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
			-- After DK/status/flash: keep ClassResource rim on the active style + elite border.
			if self.IsClassResourceRimActive
				and self:IsClassResourceRimActive(player)
				and self.ApplyClassResourceRimArt then
				self:ApplyClassResourceRimArt(player)
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
