local ADDON_NAME = ...

--[[
	Bootstrap: defaults/migrations, enable swap, DevTools setters, load + slashes.
	Profiles: Core/Profiles.lua.
]]

WhoaUF = WhoaUF or {}

local IS_MAINLINE = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local defaults = {
	enabled = true,
	hideWelcome = false,
	testingNoticeAccepted = false, -- one-time StaticPopup; set on Accept
	-- Dev force-show (HUD only). Class power ≠ Classic target ComboFrame; DK runes never force-toggled.
	forceShowClassPowerBars = false,
	forceShowTargetFrame = false,
	forceShowFocusFrame = false,
	forceShowToTFrame = false,
	forceShowFocusToTFrame = false,
	forceShowPetFrame = false,
	forceShowPartyFrames = false,
	forceShowBossFrames = false,
	forceShowRaidGroup = false,
	forceShowThreatIndicator = false,
	forceShowGroupIndicator = false,
	forceShowComboPoints = false,
	forceShowVehicleArt = "off", -- "off" | "Mechanical" | "Natural"
	frameStyle = "whoa",
	frameDark = false,
	playerFrameBorder = "normal", -- normal / elite / rareelite; DK art ignores
	dkPlayerArt = "off",
	altManaBarStyle = "stacked", -- MigrateFrameStyleOptions enforces stacked rim
	classColor = "all", -- all | player | target | none | chromatic
	npcColor = "hostility", -- hostility | blizzard | chromatic
	customHealthColor = false,
	customHealthColorPlayerOnly = false,
	healthBarColor = { r = 0, g = 1, b = 0 },
	healthColorCycleSpeed = 4, -- 1≈20s/cycle … 20≈1s; *0.05 → rev/sec
	statusBarTexture = "blizzard",
	statusBarFont = "retail",
	numberAbbreviation = "full", -- full | whoa | numbers | large
	numberAbbreviationMainline = IS_MAINLINE or nil,
	numberAbbreviationFullDefault = true,
	nameBackground = "none", -- none | player | target | both
	portraitMode = "normal", -- normal | class
	hideName = "auto", -- auto | always | never
	numericThreatFrame = "player", -- player | target | off
	combatFeedbackColors = "default", -- default | school
	auraIconSize = 27,
	-- Timing sparks (client-gated; docs/timing/README.md).
	manaTickGlow = false,
	manaTickLatency = false, -- lead blue spark by world latency (weave); default off
	powerTickGlow = false,
	swingTickGlow = false,
	-- Fallback when Edit Mode / stock layout has nothing to mirror.
	frames = {
		player = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = -1, y = 0 },
		target = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 232, y = 0 },
		focus = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 174, y = -178 },
		party = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 10, y = -160 },
	},
}

local function CopyDefaults(src, dest)
	dest = dest or {}
	for key, value in pairs(src) do
		if type(value) == "table" then
			dest[key] = CopyDefaults(value, dest[key])
		elseif dest[key] == nil then
			dest[key] = value
		end
	end
	return dest
end

function WhoaUF:GetOptionDefaults()
	return defaults
end

function WhoaUF:ApplyAllOptions()
	if self.MigrateFrameStyleOptions and self.db then
		self:MigrateFrameStyleOptions(self.db)
	end
	if self.ApplyFrameStyle then
		pcall(self.ApplyFrameStyle, self)
	end
	if self.ApplyFrameScale then
		pcall(self.ApplyFrameScale, self)
	end
	if self.ApplyStatusBarTextures then
		pcall(self.ApplyStatusBarTextures, self)
	end
	if self.ApplyStatusBarFonts then
		pcall(self.ApplyStatusBarFonts, self)
	end
	if self.ApplyNameBackgrounds then
		pcall(self.ApplyNameBackgrounds, self)
	end
	if self.ApplyPlayerNameVisibility then
		pcall(self.ApplyPlayerNameVisibility, self)
	end
	if self.ApplyNumericThreatFrame then
		pcall(self.ApplyNumericThreatFrame, self)
	end
	if self.RefreshAuraIconSizes then
		pcall(self.RefreshAuraIconSizes, self)
	end
	if self.RefreshHealthBarColors then
		pcall(self.RefreshHealthBarColors, self)
	end
	if self.UpdateHealthColorCycleDriver then
		pcall(self.UpdateHealthColorCycleDriver, self)
	end
	if self.RefreshAllPortraits then
		pcall(self.RefreshAllPortraits, self)
	end
	if self.InitManaTickGlowModule then
		pcall(self.InitManaTickGlowModule, self)
	end
	if self.RefreshManaTickGlow then
		pcall(self.RefreshManaTickGlow, self)
	end
	if self.InitPowerTickGlowModule then
		pcall(self.InitPowerTickGlowModule, self)
	end
	if self.RefreshPowerTickGlow then
		pcall(self.RefreshPowerTickGlow, self)
	end
	if self.InitSwingTickGlowModule then
		pcall(self.InitSwingTickGlowModule, self)
	end
	if self.RefreshSwingTickGlow then
		pcall(self.RefreshSwingTickGlow, self)
	end
	if self.ApplyEnabledState then
		pcall(self.ApplyEnabledState, self)
	end
	if self.ApplyClassPowerBarPreview then
		pcall(self.ApplyClassPowerBarPreview, self)
	end
	if self.ApplyForceShowThreatIndicators then
		pcall(self.ApplyForceShowThreatIndicators, self)
	end
	if self.ApplyForceShowGroupIndicator then
		pcall(self.ApplyForceShowGroupIndicator, self)
	end
	if self.ApplyForceShowVehicleArt then
		pcall(self.ApplyForceShowVehicleArt, self)
	end
	if self.UpdateComboFrame then
		pcall(self.UpdateComboFrame, self)
	end
	if self.RefreshAllUnitFrames then
		pcall(self.RefreshAllUnitFrames, self)
	end
	if self.SyncUnitFramePositions then
		pcall(self.SyncUnitFramePositions, self)
	end
end

--- Reset the active profile to shipping defaults (same table identity for Settings bindings).
--- Keeps named profiles, per-character selection, and account meta (notice / migrations).
--- Does not touch Blizzard CVars (e.g. status text) or Edit Mode layout saves.
function WhoaUF:ResetOptionsToDefaults()
	local db = self.db
	if not db then
		return
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
		return
	end

	-- Preserve account/profile meta while wiping active option keys.
	local testingNoticeAccepted = db.testingNoticeAccepted
	local profiles = db.profiles
	local charProfiles = db.charProfiles
	local activeProfile = db.activeProfile
	local profilesVersion = db.profilesVersion
	local numberAbbreviationMainline = db.numberAbbreviationMainline
	local numberAbbreviationFullDefault = db.numberAbbreviationFullDefault

	wipe(db)
	CopyDefaults(defaults, db)

	db.profiles = profiles
	db.charProfiles = charProfiles
	db.activeProfile = activeProfile
	db.profilesVersion = profilesVersion
	db.numberAbbreviationMainline = numberAbbreviationMainline
	db.numberAbbreviationFullDefault = numberAbbreviationFullDefault
	if testingNoticeAccepted then
		db.testingNoticeAccepted = true
	end

	-- Refresh Settings controls when the category has been built.
	local vars = self._optionSettingVariables
	if vars and Settings and Settings.GetSetting then
		for i = 1, #vars do
			local setting = Settings.GetSetting(vars[i])
			if setting and setting.SetValueToDefault then
				setting:SetValueToDefault()
			end
		end
	end

	self:ApplyAllOptions()

	-- Default is read-only during normal sync; Reset may refresh the template itself.
	if self.IsDefaultProfileName and self:IsDefaultProfileName(self:GetActiveProfileName()) then
		if self.ReplaceDefaultProfileTemplate then
			self:ReplaceDefaultProfileTemplate()
		end
	elseif self.SyncActiveToProfile then
		self:SyncActiveToProfile(self:GetActiveProfileName())
	end
	local profilesPanel = self._profilesPanel
	if profilesPanel and profilesPanel.Refresh then
		profilesPanel:Refresh()
	end

	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cff69ccf0Whoa Unit Frames:|r options reset to defaults.")
	end
end

local COLOR_OPTION_STRING_KEYS = {
	classColor = true,
	npcColor = true,
}
local DEFAULT_HEALTH_BAR_COLOR = { r = 0, g = 1, b = 0 }

local function CopyHealthBarColor(src)
	src = type(src) == "table" and src or DEFAULT_HEALTH_BAR_COLOR
	local r = tonumber(src.r) or DEFAULT_HEALTH_BAR_COLOR.r
	local g = tonumber(src.g) or DEFAULT_HEALTH_BAR_COLOR.g
	local b = tonumber(src.b) or DEFAULT_HEALTH_BAR_COLOR.b
	return { r = r, g = g, b = b }
end

--- One-time: fold retired per-character color overrides into the active profile, then drop them.
function WhoaUF:MigrateRetiredColorsLocal()
	local db = self.db
	if not db then
		return
	end
	if db.colorsLocal and type(db.charColors) == "table" then
		local name, realm = UnitFullName("player")
		realm = realm or GetRealmName()
		local key = name and name ~= "" and (name .. "-" .. (realm or "")) or nil
		local store = key and db.charColors[key]
		if type(store) == "table" then
			if store.classColor ~= nil then
				db.classColor = store.classColor
			end
			if store.npcColor ~= nil then
				db.npcColor = store.npcColor
			end
			if store.customHealthColor ~= nil then
				db.customHealthColor = store.customHealthColor and true or false
			end
			if store.customHealthColorPlayerOnly ~= nil then
				db.customHealthColorPlayerOnly = store.customHealthColorPlayerOnly and true or false
			end
			if type(store.healthBarColor) == "table" then
				db.healthBarColor = CopyHealthBarColor(store.healthBarColor)
			end
		end
	end
	db.colorsLocal = nil
	db.charColors = nil
end

function WhoaUF:GetColorOption(key, default)
	local db = self.db
	if not db or db[key] == nil then
		return default
	end
	return db[key]
end

function WhoaUF:SetColorOption(key, value)
	local db = self.db
	if not db then
		return
	end
	if not COLOR_OPTION_STRING_KEYS[key] then
		value = value and true or false
	end
	db[key] = value
	if key == "npcColor" and self.UpdateHealthColorCycleDriver then
		self:UpdateHealthColorCycleDriver()
	end
end

function WhoaUF:GetHealthBarCustomColor()
	local db = self.db
	if not db then
		return CopyHealthBarColor(DEFAULT_HEALTH_BAR_COLOR)
	end
	return CopyHealthBarColor(db.healthBarColor)
end

function WhoaUF:SetHealthBarCustomColor(r, g, b)
	local db = self.db
	if not db then
		return
	end
	db.healthBarColor = CopyHealthBarColor({ r = r, g = g, b = b })
end

--- Optional `swatch` (ColorSwatch button) is updated live while picking.
function WhoaUF:OpenHealthBarColorPicker(swatch)
	if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
		return
	end
	local current = self:GetHealthBarCustomColor()
	local function ApplyColor(r, g, b)
		self:SetHealthBarCustomColor(r, g, b)
		if swatch and swatch.SetColorRGB then
			swatch:SetColorRGB(r, g, b)
		end
		if self.RefreshHealthBarColors then
			self:RefreshHealthBarColors()
		end
	end
	ColorPickerFrame:SetupColorPickerAndShow({
		r = current.r,
		g = current.g,
		b = current.b,
		hasOpacity = false,
		swatchFunc = function()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			ApplyColor(r, g, b)
		end,
		cancelFunc = function(restore)
			local r, g, b
			if type(restore) == "table" then
				r, g, b = restore.r, restore.g, restore.b
			else
				r, g, b = ColorPickerFrame:GetPreviousValues()
			end
			if r and g and b then
				ApplyColor(r, g, b)
			end
		end,
	})
end

-- Enable toggle = exclusive runtime swap (apply immediately).
-- On:  mute Blizzard unit frames, then show + register Whoa listeners.
-- Off: unregister/hide Whoa first, then restore Blizzard events/scripts.
function WhoaUF:ApplyEnabledState()
	local enabled = self.db and self.db.enabled
	if enabled then
		if self.ApplyBlizzardFrames then
			self:ApplyBlizzardFrames()
		end
		-- Unit frames may not exist yet during options registration / early load.
		if self.unitFrames and self.ApplyUnitFrames then
			self:ApplyUnitFrames()
		end
		if self.AttachWhoaEditModeSystems then
			self:AttachWhoaEditModeSystems()
		end
	else
		if self.DetachWhoaEditModeSystems then
			self:DetachWhoaEditModeSystems()
		end
		if self.unitFrames and self.ApplyUnitFrames then
			self:ApplyUnitFrames()
		end
		if self.ApplyBlizzardFrames then
			self:ApplyBlizzardFrames()
		end
	end
	if self.UpdateHealthColorCycleDriver then
		self:UpdateHealthColorCycleDriver()
	end
	if self.ApplyPersonalResourceDisplayTint then
		self:ApplyPersonalResourceDisplayTint()
	end
end

-- Replaces EventUtil.ContinueOnAddOnLoaded: ownerless EventRegistry registration
-- from Whoa can object-taint shared CallbackRegistry paths that stock code later
-- uses (historically: nameplate TextStatusBar OnLoad → CUF secret compares).
-- Prefer a Whoa-owned ADDON_LOADED watcher; never touch SettingsCallbackRegistry
-- for PROXY_STATUS_TEXT from frame create (see UnitFrameShared CreateTextStatusBar).
local addonLoadedWaiters = {}
local addonLoadedWatcher

local function OnWatchedAddonLoaded(self, _, loadedName)
	local waiting = addonLoadedWaiters[loadedName]
	if not waiting then
		return
	end
	addonLoadedWaiters[loadedName] = nil
	if not next(addonLoadedWaiters) then
		self:UnregisterEvent("ADDON_LOADED")
	end
	for i = 1, #waiting do
		waiting[i](loadedName)
	end
end

function WhoaUF:ContinueOnAddOnLoaded(addonName, callback)
	local _, isLoaded = C_AddOns.IsAddOnLoaded(addonName)
	if isLoaded then
		callback(addonName)
		return
	end
	local waiting = addonLoadedWaiters[addonName]
	if not waiting then
		waiting = {}
		addonLoadedWaiters[addonName] = waiting
	end
	waiting[#waiting + 1] = callback
	if not addonLoadedWatcher then
		addonLoadedWatcher = CreateFrame("Frame")
		addonLoadedWatcher:SetScript("OnEvent", OnWatchedAddonLoaded)
	end
	addonLoadedWatcher:RegisterEvent("ADDON_LOADED")
end

local TESTING_NOTICE_POPUP = "WHOAUF_TESTING_NOTICE"

local function EnsureTestingNoticePopup()
	if StaticPopupDialogs[TESTING_NOTICE_POPUP] then
		return
	end
	StaticPopupDialogs[TESTING_NOTICE_POPUP] = {
		text = "Whoa Unit Frames is currently in testing.\n\nYour feedback is needed to help improve the addon. Please report bugs and suggestions.\n\nThank you for trying it!",
		button1 = ACCEPT,
		OnAccept = function()
			local db = WhoaUF and WhoaUF.db
			if db then
				db.testingNoticeAccepted = true
			end
		end,
		timeout = 0,
		whileDead = 1,
		hideOnEscape = 0,
		preferredIndex = 3,
	}
end

function WhoaUF:ShowTestingNoticeIfNeeded()
	-- Testing notice is Mainline-only (Classic flavors skip entirely).
	if not IS_MAINLINE then
		return
	end
	local db = self.db
	if not db or db.testingNoticeAccepted then
		return
	end
	EnsureTestingNoticePopup()
	if StaticPopup_Visible(TESTING_NOTICE_POPUP) then
		return
	end
	StaticPopup_Show(TESTING_NOTICE_POPUP)
end

local function BootWhoaRuntime()
	if WhoaUF._booted then
		return
	end
	WhoaUF._booted = true
	-- Settings category is built on first /whoaui (OpenOptions) to keep reload Lua peak down.
	WhoaUF:ApplyBlizzardFrames()
	if WhoaUF.InitStatusText then
		WhoaUF:InitStatusText()
	end
	WhoaUF:InitUnitFrames()
	if WhoaUF.InitEditMode then
		WhoaUF:InitEditMode()
	end
	if WhoaUF.InitVehicleXpBarHide then
		WhoaUF:InitVehicleXpBarHide()
	end
	if WhoaUF.InitPersonalResourceDisplayTint then
		WhoaUF:InitPersonalResourceDisplayTint()
	end
	if WhoaUF.StartWelcomeToast then
		WhoaUF:StartWelcomeToast()
	end
	-- Defer one frame so login UI settles; center StaticPopup, once per install.
	C_Timer.After(0, function()
		if WhoaUF.ShowTestingNoticeIfNeeded then
			WhoaUF:ShowTestingNoticeIfNeeded()
		end
	end)
	if WhoaUF.RegisterDevToolsProvider then
		WhoaUF:RegisterDevToolsProvider()
	end
	if WhoaUF.UpdateHealthColorCycleDriver then
		WhoaUF:UpdateHealthColorCycleDriver()
	end
end

local function OnAddonLoaded()
	-- Mainline profiles saved "whoa" before the abbreviation dropdown existed there.
	if IS_MAINLINE and WhoaUFDB and not WhoaUFDB.numberAbbreviationMainline then
		WhoaUFDB.numberAbbreviation = nil
	end
	-- Prefer Full (regional) as the new default once; CopyDefaults fills "full".
	if WhoaUFDB and not WhoaUFDB.numberAbbreviationFullDefault then
		WhoaUFDB.numberAbbreviation = nil
	end
	-- Retired absorb overlay options (shields now use the stock Shield-Fill look).
	if WhoaUFDB then
		WhoaUFDB.absorbBarCommonShield = nil
		WhoaUFDB.absorbBarBorderGlow = nil
		WhoaUFDB.absorbBarTargetColor = nil
		-- Drop retired personalResourceDisplay SavedVariables key.
		WhoaUFDB.personalResourceDisplay = nil
	end
	WhoaUFDB = CopyDefaults(defaults, WhoaUFDB)
	WhoaUF.db = WhoaUFDB
	if WhoaUF.MigrateFrameStyleOptions then
		WhoaUF:MigrateFrameStyleOptions(WhoaUFDB)
	end
	-- Retired: scale is Edit Mode Frame Size only (ignore orphaned SavedVariables).
	if WhoaUFDB then
		WhoaUFDB.frameScale = nil
	end
	-- Fold retired per-character colors into the active options, then drop them.
	if WhoaUF.MigrateRetiredColorsLocal then
		WhoaUF:MigrateRetiredColorsLocal()
	end
	-- Named profiles + per-character selection (after migrations so Default is clean).
	if WhoaUF.InitProfiles then
		WhoaUF:InitProfiles()
	end

	-- Mainline / Forever: boot after VARIABLES_LOADED (+ 1 frame) so CUFProfiles
	-- ApplyCurrentSettings → CompactParty RefreshMembers runs untainted first.
	-- Booting on ADDON_LOADED poisoned CompactUnitFrame_UpdateHealthColor (secret oldR).
	local deferBoot = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
		or (WhoaUF.IsCamelot and WhoaUF:IsCamelot())
	if deferBoot then
		local boot = CreateFrame("Frame")
		boot:RegisterEvent("VARIABLES_LOADED")
		boot:RegisterEvent("PLAYER_LOGIN")
		boot:SetScript("OnEvent", function(self)
			self:UnregisterAllEvents()
			C_Timer.After(0, BootWhoaRuntime)
		end)
	else
		BootWhoaRuntime()
	end
end

-- Dev controls live in sibling DevTools (/whoadev HUD). DevTools is UI only;
-- setters / Apply* below stay here; registerHud just wires checkboxes to them.
function WhoaUF:SetEnabled(enabled)
	if not self.db then
		return
	end
	self.db.enabled = enabled and true or false
	if self.ApplyEnabledState then
		pcall(self.ApplyEnabledState, self)
	end
end

function WhoaUF:SetFrameDark(enabled)
	if not self.db then
		return
	end
	self.db.frameDark = enabled and true or false
	if self.ApplyFrameStyle then
		pcall(self.ApplyFrameStyle, self)
	end
end

function WhoaUF:SetForceShowClassPowerBars(enabled)
	if not self.db then
		return
	end
	self.db.forceShowClassPowerBars = enabled and true or false
	if self.ApplyClassPowerBarPreview then
		self:ApplyClassPowerBarPreview()
	end
end

function WhoaUF:SetForceShowFrameOption(dbKey, enabled)
	if not self.db or type(dbKey) ~= "string" then
		return
	end
	self.db[dbKey] = enabled and true or false
	if self.ApplyUnitFrames then
		pcall(self.ApplyUnitFrames, self)
	end
	-- ApplyUnitFrames may skip boss/raid layout; call Layout* explicitly for those.
	if dbKey == "forceShowBossFrames" and self.LayoutBossFrames then
		pcall(self.LayoutBossFrames, self)
	elseif dbKey == "forceShowRaidGroup" and self.LayoutRaidGroupFrames then
		pcall(self.LayoutRaidGroupFrames, self)
	end
end

function WhoaUF:SetForceShowThreatIndicator(enabled)
	if not self.db then
		return
	end
	self.db.forceShowThreatIndicator = enabled and true or false
	if self.ApplyForceShowThreatIndicators then
		pcall(self.ApplyForceShowThreatIndicators, self)
	end
end

function WhoaUF:IsForceShowThreatIndicator()
	return self.db and self.db.forceShowThreatIndicator and true or false
end

function WhoaUF:SetForceShowGroupIndicator(enabled)
	if not self.db then
		return
	end
	self.db.forceShowGroupIndicator = enabled and true or false
	if self.ApplyForceShowGroupIndicator then
		pcall(self.ApplyForceShowGroupIndicator, self)
	end
end

function WhoaUF:IsForceShowGroupIndicator()
	return self.db and self.db.forceShowGroupIndicator and true or false
end

function WhoaUF:ApplyForceShowGroupIndicator()
	local uf = self._UF
	local frame = uf and uf.frames and uf.frames.player
	if frame and uf.UpdateGroupIndicator then
		uf.UpdateGroupIndicator(frame)
	end
end

function WhoaUF:SetForceShowComboPoints(enabled)
	if not self.db then
		return
	end
	self.db.forceShowComboPoints = enabled and true or false
	if self.UpdateComboFrame then
		pcall(self.UpdateComboFrame, self)
	end
	-- Turning off: restore normal target UnitWatch if we forced it visible.
	if not self.db.forceShowComboPoints and self.ApplyUnitFrames then
		pcall(self.ApplyUnitFrames, self)
	end
end

function WhoaUF:GetForceShowVehicleType()
	local v = self.db and self.db.forceShowVehicleArt
	if v == "Natural" or v == "Mechanical" then
		return v
	end
	return nil
end

function WhoaUF:SetForceShowVehicleArt(vehicleType)
	if not self.db then
		return
	end
	if vehicleType == "Natural" or vehicleType == "Mechanical" then
		self.db.forceShowVehicleArt = vehicleType
	else
		self.db.forceShowVehicleArt = "off"
	end
	if self.ApplyForceShowVehicleArt then
		pcall(self.ApplyForceShowVehicleArt, self)
	elseif self.ApplyUnitFrames then
		pcall(self.ApplyUnitFrames, self)
	end
end

function WhoaUF:RegisterDevToolsProvider()
	local function register()
		if not WhoaDev or not WhoaDev.RegisterProvider then
			return
		end
		WhoaDev:RegisterProvider({
			id = "WhoaUnitFrames",
			name = "Whoa Unit Frames",
			registerHud = function(hud)
				local function db()
					return WhoaUF.db
				end
				local function dbBool(key)
					local d = db()
					return d and d[key] and true or false
				end

				hud:AddCheckbox(
					"Enable Whoa Unit Frames",
					function()
						return dbBool("enabled")
					end,
					function(value)
						WhoaUF:SetEnabled(value)
					end,
					"Applies immediately. On: mute Blizzard unit frames and run Whoa. Off: unregister Whoa and restore Blizzard."
				)
				hud:AddCheckbox(
					"Dark theme",
					function()
						return dbBool("frameDark")
					end,
					function(value)
						WhoaUF:SetFrameDark(value)
					end,
					"Use Media\\{style}\\dark (and Media\\shared\\dark) instead of light/client art. Same as Settings → Appearance."
				)

				hud:AddTab("Force Show", function(tab)
					tab:AddCheckbox(
						"Force show class power bars",
						function()
							return dbBool("forceShowClassPowerBars")
						end,
						function(value)
							WhoaUF:SetForceShowClassPowerBars(value)
						end,
						"Off: normal class gating. On: force-show and fill your current class resource under the player. Classic target ComboFrame is separate. DK runes unchanged."
					)
					tab:AddCheckbox(
						"Force show target frame",
						function()
							return dbBool("forceShowTargetFrame")
						end,
						function(value)
							WhoaUF:SetForceShowFrameOption("forceShowTargetFrame", value)
						end,
						"Show Whoa target chrome without a target (labeled Target)."
					)
					tab:AddCheckbox(
						"Force show focus frame",
						function()
							return dbBool("forceShowFocusFrame")
						end,
						function(value)
							WhoaUF:SetForceShowFrameOption("forceShowFocusFrame", value)
						end,
						"Show Whoa focus chrome without a focus (labeled Focus)."
					)
					tab:AddCheckbox(
						"Force show target of target",
						function()
							return dbBool("forceShowToTFrame")
						end,
						function(value)
							WhoaUF:SetForceShowFrameOption("forceShowToTFrame", value)
						end,
						"Show Whoa ToT chrome without a unit / even if showTargetOfTarget is off."
					)
					tab:AddCheckbox(
						"Force show target of focus",
						function()
							return dbBool("forceShowFocusToTFrame")
						end,
						function(value)
							WhoaUF:SetForceShowFrameOption("forceShowFocusToTFrame", value)
						end,
						"Show Whoa ToF chrome without a unit (labeled ToF)."
					)
					tab:AddCheckbox(
						"Force show pet frame",
						function()
							return dbBool("forceShowPetFrame")
						end,
						function(value)
							WhoaUF:SetForceShowFrameOption("forceShowPetFrame", value)
						end,
						"Show Whoa pet chrome without a pet (labeled Pet)."
					)
					tab:AddCheckbox(
						"Force show party frames",
						function()
							return dbBool("forceShowPartyFrames")
						end,
						function(value)
							WhoaUF:SetForceShowFrameOption("forceShowPartyFrames", value)
						end,
						"Show Whoa party chrome (and party pets under each slot) without a group. Ignores showPartyPets / missing pets when party frames are enabled."
					)
					if WhoaUF.HasBossFrames and WhoaUF:HasBossFrames() then
						tab:AddCheckbox(
							"Force show boss frames",
							function()
								return dbBool("forceShowBossFrames")
							end,
							function(value)
								WhoaUF:SetForceShowFrameOption("forceShowBossFrames", value)
							end,
							"Show Whoa boss1–5 chrome without an encounter (labeled Boss 1–5)."
						)
					end
					tab:AddCheckbox(
						"Force show raid group",
						function()
							return dbBool("forceShowRaidGroup")
						end,
						function(value)
							WhoaUF:SetForceShowFrameOption("forceShowRaidGroup", value)
						end,
						"Show Whoa CompactRaid-style Group 1 (5 member slots) for layout preview. Live raid CUF still Blizzard until Whoa raid ships."
					)
					tab:AddCheckbox(
						"Force show threat indicator",
						function()
							return dbBool("forceShowThreatIndicator")
						end,
						function(value)
							WhoaUF:SetForceShowThreatIndicator(value)
						end,
						"Paint threat flash (and numeric when enabled) at tanking / 100% on visible frames that have threat chrome."
					)
					tab:AddCheckbox(
						"Force show group indicator",
						function()
							return dbBool("forceShowGroupIndicator")
						end,
						function(value)
							WhoaUF:SetForceShowGroupIndicator(value)
						end,
						"Show/hide preview of the player raid subgroup indicator (Media\\shared\\{light|dark}\\UI-GroupIndicator + G#) without being in a raid. Uses real subgroup when already raiding."
					)
					tab:AddCheckbox(
						"Force show combo points",
						function()
							return dbBool("forceShowComboPoints")
						end,
						function(value)
							WhoaUF:SetForceShowComboPoints(value)
						end,
						"Off: Classic gems on target only while you have combo points. On: force-show 5 filled gems for layout preview."
					)
					tab:AddCheckbox(
						"Force show vehicle (Mechanical)",
						function()
							return WhoaUF:GetForceShowVehicleType() == "Mechanical"
						end,
						function(value)
							WhoaUF:SetForceShowVehicleArt(value and "Mechanical" or "off")
						end,
						"Preview mechanical vehicle player chrome without entering a vehicle. Real vehicle seats override this."
					)
					tab:AddCheckbox(
						"Force show vehicle (Natural)",
						function()
							return WhoaUF:GetForceShowVehicleType() == "Natural"
						end,
						function(value)
							WhoaUF:SetForceShowVehicleArt(value and "Natural" or "off")
						end,
						"Preview natural/organic vehicle player chrome without entering a vehicle. Real vehicle seats override this."
					)
				end)
			end,
		})
	end
	if WhoaDev and WhoaDev.RegisterProvider then
		register()
	else
		WhoaUF:ContinueOnAddOnLoaded("DevTools", register)
	end
end

function WhoaUF:IsForceShowClassPowerBars()
	return self.db and self.db.forceShowClassPowerBars
end

local FORCE_SHOW_DB_KEYS = {
	target = "forceShowTargetFrame",
	focus = "forceShowFocusFrame",
	tot = "forceShowToTFrame",
	focustot = "forceShowFocusToTFrame",
	pet = "forceShowPetFrame",
	party = "forceShowPartyFrames",
	-- Party pets share the party force-show toggle (shown under each forced party slot).
	partypet = "forceShowPartyFrames",
	boss = "forceShowBossFrames",
	raidgroup = "forceShowRaidGroup",
}

local FORCE_SHOW_PLACEHOLDERS = {
	target = "Target",
	focus = "Focus",
	tot = "ToT",
	focustot = "ToF",
	pet = "Pet",
	partypet = "Pet",
	boss = "Boss",
}

function WhoaUF:IsForceShowFrame(kind)
	local key = kind and FORCE_SHOW_DB_KEYS[kind]
	return key and self.db and self.db[key] and true or false
end

-- Empty-slot chrome when a force-show option is on but the unit is missing.
function WhoaUF:ApplyForceShowPlaceholder(frame)
	if not frame or not frame.kind then
		return
	end
	local previewOk
	if frame.kind == "boss" then
		previewOk = self.WantBossFramePreview and self:WantBossFramePreview()
	else
		previewOk = self:IsForceShowFrame(frame.kind)
	end
	if not previewOk then
		return
	end
	if UnitExists(frame.unit) then
		return
	end
	local label = FORCE_SHOW_PLACEHOLDERS[frame.kind]
	if frame.kind == "boss" and frame.bossIndex then
		label = "Boss " .. frame.bossIndex
	end
	if label and frame.Name then
		frame.Name:SetText(label)
	end
	if frame.Portrait then
		frame.Portrait:SetTexture("Interface\\CharacterFrame\\TempPortrait")
		frame.Portrait:Show()
	end
end

function WhoaUF:IsForceShowClassPowerFor(classToken)
	if not self:IsForceShowClassPowerBars() then
		return false
	end
	local _, class = UnitClass("player")
	return class == classToken
end

-- Dev preview: refresh registered class bars for this character only.
function WhoaUF:ApplyClassPowerBarPreview()
	if not (self.unitFrames and self.unitFrames.player) then
		return
	end
	if self.RefreshPlayerClassBars then
		self:RefreshPlayerClassBars()
	end
	if self.LayoutPlayerBottomFrames then
		self:LayoutPlayerBottomFrames()
	end
end

-- Lua GC is global (not per-frame). Request a full collect only on quiet
-- clear/hide moments (no target/focus, leave combat). Throttled + deferred
-- so rapid tabbing and same-frame hide updates do not hitch.
local lastIdleGC = 0
local idleGCPending = false
local idleGCForce = false
local IDLE_GC_MIN_INTERVAL = 5

function WhoaUF:RequestIdleCollect(force)
	if InCombatLockdown() then
		return
	end
	if force then
		idleGCForce = true
	end
	if idleGCPending then
		return
	end
	local now = GetTime()
	if not idleGCForce and (now - lastIdleGC) < IDLE_GC_MIN_INTERVAL then
		return
	end
	idleGCPending = true
	C_Timer.After(0, function()
		idleGCPending = false
		local doForce = idleGCForce
		idleGCForce = false
		if InCombatLockdown() then
			return
		end
		local t = GetTime()
		if not doForce and (t - lastIdleGC) < IDLE_GC_MIN_INTERVAL then
			return
		end
		lastIdleGC = t
		collectgarbage("collect")
	end)
end

function WhoaUF:OpenOptions()
	-- Never touch Settings while locked down — opening the panel from a macro/slash in combat taints.
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
		self.pendingOptionsOpen = true
		return
	end
	self.pendingOptionsOpen = nil
	if not self.settingsCategory and self.RegisterOptions then
		self:RegisterOptions()
	end
	if not self.settingsCategory then
		return
	end
	Settings.OpenToCategory(self.settingsCategory:GetID())
end

-- Register then flush into hash_SlashCmdList immediately. Leaving entries pending in
-- SlashCmdList lets macro UseAction → ImportAllListsToHash read tainted SLASH_* globals
-- (see Logs/taint.log / WoWUIBugs#447).
SLASH_WHOAUI1 = "/whoaui"
SlashCmdList.WHOAUI = function()
	WhoaUF:OpenOptions()
end
SLASH_RL1 = "/rl"
SlashCmdList.RL = function()
	ReloadUI()
end
if ChatFrameUtil and ChatFrameUtil.ImportAllListsToHash then
	ChatFrameUtil.ImportAllListsToHash()
end

WhoaUF:ContinueOnAddOnLoaded(ADDON_NAME, OnAddonLoaded)
