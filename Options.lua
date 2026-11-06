function WhoaUF:RegisterOptions()
	if self.settingsCategory then
		return
	end
	-- Classic Settings lacks SETTINGS_SUBCATEGORY_FMT; GetQualifiedName needs it for subcategory titles.
	if not SETTINGS_SUBCATEGORY_FMT then
		SETTINGS_SUBCATEGORY_FMT = "%s (%s)"
	end
	local db = self.db
	if self.MigrateFrameStyleOptions then
		self:MigrateFrameStyleOptions(db)
	end
	-- Canvas category so Settings search never walks our controls. Addon vertical layouts
	-- taint FindInitializersMatchingSearchText; stock Social Discord Init then hits
	-- forbidden C_Discord.IsUserOAuthed() (e.g. search "con" matches DISCONNECT).
	local layout = CreateVerticalLayout()
	local canvas = CreateFrame("Frame", "WhoaUFSettingsCanvas", nil, "SettingsListTemplate")
	canvas.Header.Title:SetText("Whoa Unit Frames")
	canvas.Header.DefaultsButton:Hide()
	canvas.Header.TutorialButton:Hide()
	function canvas:OnRefresh()
		self:Display(layout:GetInitializers())
	end
	local category, canvasLayout = Settings.RegisterCanvasLayoutCategory(canvas, "Whoa Unit Frames")
	-- SetParentInitializer → IsParentInitializerInLayout calls currentLayout:EnumerateInitializers().
	-- Canvas layouts lack that; keep layoutType=Canvas (search skip) but forward the list.
	function canvasLayout:EnumerateInitializers()
		return layout:EnumerateInitializers()
	end

	-- Track Settings variables so ResetOptionsToDefaults can refresh the panel UI.
	-- WHOAUF_STATUS_TEXT is a Blizzard CVar — intentionally not tracked.
	local trackedVars = {}
	self._optionSettingVariables = trackedVars

	-- SettingMixin:SetValueChangedCallback registers without an owner, which draws
	-- from CallbackRegistry's shared owner-ID counter under Whoa taint and poisons
	-- later stock registrations (nameplate TextStatusBar OnLoad → CUF secret compares).
	local function SetOwnedValueChangedCallback(setting, callback)
		local function OnValueChanged(_, changedSetting, value)
			callback(changedSetting, value)
		end
		Settings.SetOnValueChangedCallback(setting:GetVariable(), OnValueChanged, OnValueChanged)
	end
	local function WithOwnedCallbacks(setting)
		if setting then
			setting.SetValueChangedCallback = SetOwnedValueChangedCallback
		end
		return setting
	end

	local function RegisterTrackedAddOnSetting(cat, variable, ...)
		trackedVars[#trackedVars + 1] = variable
		return WithOwnedCallbacks(Settings.RegisterAddOnSetting(cat, variable, ...))
	end
	local function RegisterTrackedProxySetting(cat, variable, ...)
		if variable ~= "WHOAUF_STATUS_TEXT" then
			trackedVars[#trackedVars + 1] = variable
		end
		return WithOwnedCallbacks(Settings.RegisterProxySetting(cat, variable, ...))
	end

	-- Settings.Create* appends via GetLayout(category); canvas layouts have no AddInitializer.
	local function CreateCheckbox(cat, setting, tooltip)
		local initializer = Settings.CreateCheckboxInitializer(setting, nil, tooltip)
		layout:AddInitializer(initializer)
		return initializer
	end
	local function CreateSlider(cat, setting, options, tooltip)
		local initializer = Settings.CreateSliderInitializer(setting, options, tooltip)
		layout:AddInitializer(initializer)
		return initializer
	end
	local function CreateDropdown(cat, setting, options, tooltip)
		local initializer = Settings.CreateDropdownInitializer(setting, options, tooltip)
		layout:AddInitializer(initializer)
		return initializer
	end

	local function IsPlayerClass(classToken)
		local _, class = UnitClass("player")
		return class == classToken
	end

	-- Settings dropdown steppers normally disable at the ends; ours wrap first↔last on click.
	local loopingDropdownVars = self._loopingDropdownVars
	if not loopingDropdownVars then
		loopingDropdownVars = {}
		self._loopingDropdownVars = loopingDropdownVars
	end

	local function CollectSelectableRadios(dropdown)
		local radios = {}
		if not dropdown or not dropdown.GetMenuDescription or not MenuUtil or not MenuUtil.TraverseMenu then
			return radios
		end
		local root = dropdown:GetMenuDescription()
		if not root then
			return radios
		end
		MenuUtil.TraverseMenu(root, function(description)
			if description.IsSelectionIgnored and description:IsSelectionIgnored() then
				return
			end
			if description.IsRadio and description:IsRadio()
				and description.CanSelect and description:CanSelect() then
				radios[#radios + 1] = description
			end
		end)
		return radios
	end

	local function EnableLoopingDropdown(setting)
		if setting and setting.GetVariable then
			loopingDropdownVars[setting:GetVariable()] = true
		end
	end

	local function CreateLoopingDropdown(cat, setting, optionsFn, tooltip)
		local initializer = CreateDropdown(cat, setting, optionsFn, tooltip)
		EnableLoopingDropdown(setting)
		return initializer
	end

	if SettingsDropdownControlMixin and not self._loopingDropdownHooked then
		self._loopingDropdownHooked = true
		hooksecurefunc(SettingsDropdownControlMixin, "Init", function(control, initializer)
			local setting = initializer and initializer.GetSetting and initializer:GetSetting()
			local variable = setting and setting.GetVariable and setting:GetVariable()
			if not variable or not WhoaUF._loopingDropdownVars or not WhoaUF._loopingDropdownVars[variable] then
				return
			end
			local stepper = control.Control
			if not stepper or stepper.whoaLoopSteppers then
				return
			end
			stepper.whoaLoopSteppers = true
			local inputContext = MenuInputContext and MenuInputContext.MouseWheel or nil

			stepper.Increment = function(self)
				local dropdown = self.Dropdown
				if not dropdown or not dropdown.CollectSelectionData then
					return
				end
				local _, nextRadio = dropdown:CollectSelectionData()
				if nextRadio then
					dropdown:Pick(nextRadio, inputContext)
					return
				end
				local radios = CollectSelectableRadios(dropdown)
				if radios[1] then
					dropdown:Pick(radios[1], inputContext)
				end
			end

			stepper.Decrement = function(self)
				local dropdown = self.Dropdown
				if not dropdown or not dropdown.CollectSelectionData then
					return
				end
				local previousRadio = dropdown:CollectSelectionData()
				if previousRadio then
					dropdown:Pick(previousRadio, inputContext)
					return
				end
				local radios = CollectSelectableRadios(dropdown)
				local last = radios[#radios]
				if last then
					dropdown:Pick(last, inputContext)
				end
			end

			local baseSetSteppersEnabled = stepper.SetSteppersEnabled
			stepper.SetSteppersEnabled = function(self, canDecrement, canIncrement)
				if self.Dropdown and self.Dropdown:IsEnabled() then
					local radios = CollectSelectableRadios(self.Dropdown)
					if #radios > 1 then
						canDecrement, canIncrement = true, true
					end
				end
				if baseSetSteppersEnabled then
					baseSetSteppersEnabled(self, canDecrement, canIncrement)
				elseif DropdownWithSteppersMixin and DropdownWithSteppersMixin.SetSteppersEnabled then
					DropdownWithSteppersMixin.SetSteppersEnabled(self, canDecrement, canIncrement)
				end
			end

			if stepper.UpdateSteppers then
				stepper:UpdateSteppers()
			end
		end)
	end

	---------------------------------------------------------------------------
	-- Frame Style (Whoa / Thick / Classic + class specialty styles)
	---------------------------------------------------------------------------
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Frame Style"))

	local function NormalizeDkPlayerArt(value)
		if value == true or value == "alpha" then
			return "alpha"
		end
		if value == "blizzcon" then
			return "blizzcon"
		end
		return "off"
	end
	db.dkPlayerArt = NormalizeDkPlayerArt(db.dkPlayerArt)

	-- Class specialty chrome (DK Alpha / BlizzCon; Forever warriors share it).
	-- Listed in the frame Style dropdown for eligible classes — not under Player rarity.
	local canUseDkSpecialtyArt = self.IsDkSpecialtyPlayerArtEligible
		and self:IsDkSpecialtyPlayerArtEligible()
	local DK_STYLE_BY_ART = { alpha = "dk_alpha", blizzcon = "dk_blizzcon" }
	local DK_ART_BY_STYLE = { dk_alpha = "alpha", dk_blizzcon = "blizzcon" }

	local function GetCurrentDkPlayerArt()
		if not canUseDkSpecialtyArt then
			return "off"
		end
		return NormalizeDkPlayerArt(db.dkPlayerArt)
	end

	local function NormalizeBaseFrameStyle(value)
		if value == "thick" or value == "classic" then
			return value
		end
		return "whoa"
	end

	local function ApplyDkPlayerArt(art)
		db.dkPlayerArt = art
		-- BlizzCon uses the player name slot; move threat % to target (Alpha keeps both).
		if art == "blizzcon" and db.numericThreatFrame == "player" then
			db.numericThreatFrame = "target"
			local nt = Settings.GetSetting("WHOAUF_NUMERIC_THREAT")
			if nt and nt.SetValue then
				nt:SetValue("target")
			end
		end
		local player = self.unitFrames and self.unitFrames.player
		if self.ApplyDeathKnightPlayerArt then
			self:ApplyDeathKnightPlayerArt(player)
		end
		if self.ApplyUnitFrames then
			self:ApplyUnitFrames()
		end
		if art == "off" and self.ApplyFrameStyle then
			self:ApplyFrameStyle()
		end
		if self.LayoutPlayerBottomFrames then
			self:LayoutPlayerBottomFrames()
		end
		if self.ApplyNumericThreatFrame then
			self:ApplyNumericThreatFrame()
		end
	end

	local function ApplyBaseFrameStyle(style)
		style = NormalizeBaseFrameStyle(style)
		db.frameStyle = style
		local prevArt = GetCurrentDkPlayerArt()
		local player = self.unitFrames and self.unitFrames.player
		if prevArt ~= "off" or (player and player.dkPlayerArt) then
			ApplyDkPlayerArt("off")
		elseif self.ApplyFrameStyle then
			self:ApplyFrameStyle()
		end
	end

	local function GetFrameStyleOptions()
		local container = Settings.CreateControlTextContainer()
		local keys, labels = self:GetFrameStyleOptions()
		for _, key in ipairs(keys) do
			container:Add(key, labels[key] or key)
		end
		if canUseDkSpecialtyArt then
			container:Add("dk_alpha", "Alpha Frame")
			container:Add("dk_blizzcon", "BlizzCon '07 Frame")
		end
		return container:GetData()
	end

	-- Style → Rarity → Appearance → Player name → Name background → Portraits → Scale
	local frameStyleSetting = RegisterTrackedProxySetting(
		category,
		"WHOAUF_FRAME_STYLE",
		Settings.VarType.String,
		"Style",
		"whoa",
		function()
			local art = GetCurrentDkPlayerArt()
			if art ~= "off" then
				return DK_STYLE_BY_ART[art]
			end
			return NormalizeBaseFrameStyle(db.frameStyle)
		end,
		function(value)
			if type(value) ~= "string" then
				value = "whoa"
			end
			local art = canUseDkSpecialtyArt and DK_ART_BY_STYLE[value]
			if art then
				if GetCurrentDkPlayerArt() ~= art then
					ApplyDkPlayerArt(art)
				end
				return
			end
			ApplyBaseFrameStyle(value)
		end
	)
	local frameStyleTooltip =
		"Choose how your unit frames look. Whoa Frames, Thick Frames, and Classic Frames are all included — the three styles that used to ship as separate addons."
	if canUseDkSpecialtyArt then
		if IsPlayerClass("WARRIOR") then
			frameStyleTooltip =
				"Choose how your unit frames look. Alpha matches the WotLK DK sword frame with Rage in the portrait fill (red glow, no rune bar). BlizzCon '07 swaps the player border only."
		else
			frameStyleTooltip =
				"Choose how your unit frames look. Alpha adds the WotLK sword look with runic fill. BlizzCon '07 swaps the player border only."
		end
	end
	CreateLoopingDropdown(category, frameStyleSetting, GetFrameStyleOptions, frameStyleTooltip)

	local function NormalizePlayerFrameBorder(value)
		if value == "elite" or value == "rareelite" then
			return value
		end
		return "normal"
	end
	db.playerFrameBorder = NormalizePlayerFrameBorder(db.playerFrameBorder)

	local function GetPlayerFrameOptions()
		local container = Settings.CreateControlTextContainer()
		local keys, labels = self:GetPlayerFrameBorderOptions()
		for _, key in ipairs(keys) do
			container:Add(key, labels[key] or key)
		end
		return container:GetData()
	end

	local playerFrameSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_PLAYER_FRAME_BORDER",
		"playerFrameBorder",
		db,
		Settings.VarType.String,
		"Rarity",
		"normal"
	)
	playerFrameSetting:SetValueChangedCallback(function(setting, value)
		if type(value) ~= "string" then
			value = setting and setting.GetValue and setting:GetValue()
		end
		value = NormalizePlayerFrameBorder(value)
		if self.SetPlayerFrameBorder then
			self:SetPlayerFrameBorder(value)
		else
			db.playerFrameBorder = value
			if self.ApplyFrameStyle then
				self:ApplyFrameStyle()
			end
		end
	end)
	local playerFrameTooltip = "Player border rarity: Default, Elite, or Rare Elite."
	if IsPlayerClass("DRUID") then
		playerFrameTooltip =
			"Player border rarity: Default, Elite, or Rare Elite. In cat and bear form the Druid frame adds a matching alternate mana bar on this border."
	end
	CreateLoopingDropdown(category, playerFrameSetting, GetPlayerFrameOptions, playerFrameTooltip)

	local function GetFrameThemeOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("light", "Light")
		container:Add("dark", "Dark")
		return container:GetData()
	end
	local frameThemeSetting = RegisterTrackedProxySetting(
		category,
		"WHOAUF_FRAME_DARK",
		Settings.VarType.String,
		"Appearance",
		"light",
		function()
			return db.frameDark and "dark" or "light"
		end,
		function(value)
			local dark = value == "dark"
			if self.SetFrameDark then
				self:SetFrameDark(dark)
			else
				db.frameDark = dark
				if self.ApplyFrameStyle then
					self:ApplyFrameStyle()
				end
			end
		end
	)
	CreateLoopingDropdown(
		category,
		frameThemeSetting,
		GetFrameThemeOptions,
		"Light or dark frame art. Bar layout still follows Whoa, Thick, or Classic."
	)

	local function NormalizeHideName(value)
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
	db.hideName = NormalizeHideName(db.hideName)

	local function GetHideNameOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("auto", "Auto")
		container:Add("always", "Always")
		container:Add("never", "Never")
		return container:GetData()
	end
	local hideNameSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_HIDE_NAME",
		"hideName",
		db,
		Settings.VarType.String,
		"Player name",
		"auto"
	)
	hideNameSetting:SetValueChangedCallback(function(setting, value)
		if type(value) ~= "string" then
			value = setting and setting.GetValue and setting:GetValue()
		end
		db.hideName = NormalizeHideName(value)
		if self.ApplyPlayerNameVisibility then
			self:ApplyPlayerNameVisibility()
		end
		if self.ApplyNameBackgrounds then
			self:ApplyNameBackgrounds()
		end
		if self.RefreshAllUnitFrames then
			self:RefreshAllUnitFrames()
		end
	end)
	CreateLoopingDropdown(
		category,
		hideNameSetting,
		GetHideNameOptions,
		"Player name visibility. Auto hides the name on Whoa/Thick while threat percent occupies that slot. Always hides your name. Never keeps the name visible."
	)

	local function NormalizeNameBackground(value)
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
	db.nameBackground = NormalizeNameBackground(db.nameBackground)

	local function GetNameBackgroundOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("player", "Player")
		container:Add("target", "Target")
		container:Add("both", "Both")
		container:Add("none", "None")
		return container:GetData()
	end
	-- Blizzard name: NameBackground (UI-TargetingFrame-LevelBackground) — colored strip behind the unit name.
	local nameBgSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_NAME_BACKGROUND",
		"nameBackground",
		db,
		Settings.VarType.String,
		"Name background",
		"none"
	)
	nameBgSetting:SetValueChangedCallback(function(setting, value)
		if type(value) ~= "string" then
			value = setting and setting.GetValue and setting:GetValue()
		end
		db.nameBackground = NormalizeNameBackground(value)
		if self.ApplyNameBackgrounds then
			self:ApplyNameBackgrounds()
		end
	end)
	CreateLoopingDropdown(
		category,
		nameBgSetting,
		GetNameBackgroundOptions,
		"Show the colored name strip behind unit names. Classic Frames only; Whoa and Thick hide it by design. Player, Target (includes focus), Both, or None."
	)

	local function RefreshPortraits()
		if self.RefreshAllPortraits then
			self:RefreshAllPortraits()
		elseif self.RefreshAllUnitFrames then
			self:RefreshAllUnitFrames()
		end
		if self.UpdateAllPartyFrames then
			self:UpdateAllPartyFrames()
		end
		if self.UpdatePetFrame then
			self:UpdatePetFrame()
		end
	end

	local function GetPortraitModeOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("normal", "Normal")
		container:Add("class", "Class icon")
		return container:GetData()
	end
	if db.portraitMode ~= "normal" and db.portraitMode ~= "class" then
		db.portraitMode = "normal"
	end
	local portraitModeSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_PORTRAIT_MODE",
		"portraitMode",
		db,
		Settings.VarType.String,
		"Portraits",
		"normal"
	)
	portraitModeSetting:SetValueChangedCallback(function(setting, value)
		if type(value) ~= "string" then
			value = setting and setting.GetValue and setting:GetValue()
		end
		if value ~= "normal" and value ~= "class" then
			value = "normal"
		end
		db.portraitMode = value
		RefreshPortraits()
	end)
	CreateLoopingDropdown(
		category,
		portraitModeSetting,
		GetPortraitModeOptions,
		"Portrait on every unit frame. Normal shows the unit; Class icon shows the class circle for players (pets and NPCs stay Normal)."
	)

	local scaleMin, scaleMax, scaleStep, scaleDefault = 50, 200, 5, 100
	if self.GetFrameScaleRange then
		scaleMin, scaleMax, scaleStep, scaleDefault = self:GetFrameScaleRange()
	end
	db.frameScale = (self.ClampFrameScalePercent and self:ClampFrameScalePercent(db.frameScale))
		or scaleDefault
	local frameScaleSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_FRAME_SCALE",
		"frameScale",
		db,
		Settings.VarType.Number,
		"Scale",
		scaleDefault
	)
	frameScaleSetting:SetValueChangedCallback(function(setting, value)
		if type(value) ~= "number" then
			value = setting and setting.GetValue and setting:GetValue()
		end
		value = (self.ClampFrameScalePercent and self:ClampFrameScalePercent(value)) or scaleDefault
		db.frameScale = value
		if self.ApplyFrameScale then
			self:ApplyFrameScale()
		end
	end)
	local frameScaleOptions = Settings.CreateSliderOptions(scaleMin, scaleMax, scaleStep)
	frameScaleOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return string.format("%d%%", value)
	end)
	CreateSlider(
		category,
		frameScaleSetting,
		frameScaleOptions,
		"Scale player, target, focus, party, and boss frames. Drag the slider or use the steppers."
	)

	---------------------------------------------------------------------------
	-- Colors (class / NPC / custom health bars)
	---------------------------------------------------------------------------
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Colors"))

	local function OnHealthColorSettingChanged()
		if self.RefreshHealthBarColors then
			self:RefreshHealthBarColors()
		end
	end

	local function RegisterColorProxy(variable, key, name, defaultValue, tooltip, onChanged)
		local setting = RegisterTrackedProxySetting(
			category,
			variable,
			Settings.VarType.Boolean,
			name,
			defaultValue,
			function()
				return self:GetColorOption(key, defaultValue) and true or false
			end,
			function(value)
				self:SetColorOption(key, value and true or false)
				if onChanged then
					onChanged(value and true or false)
				end
			end
		)
		return setting
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

	local function NormalizeNpcColorMode(value)
		if value == "hostility" or value == "blizzard" or value == "chromatic" then
			return value
		end
		return "hostility"
	end

	local function GetClassColorOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("all", "All")
		container:Add("player", "Player")
		container:Add("target", "Target")
		container:Add("none", "None")
		container:Add("chromatic", "Chromatic")
		return container:GetData()
	end

	local classSetting = RegisterTrackedProxySetting(
		category,
		"WHOAUF_CLASS_COLOR",
		Settings.VarType.String,
		"Players class colors",
		"all",
		function()
			return NormalizeClassColorMode(self:GetColorOption("classColor", "all"))
		end,
		function(value)
			value = NormalizeClassColorMode(value)
			self:SetColorOption("classColor", value)
			-- Start/stop cycle before refresh so GetHealthBarColor sees the new mode.
			if self.UpdateHealthColorCycleDriver then
				self:UpdateHealthColorCycleDriver()
			else
				OnHealthColorSettingChanged()
			end
		end
	)
	CreateLoopingDropdown(
		category,
		classSetting,
		GetClassColorOptions,
		"Color player health bars by class. All: you, party, and player targets. Player: only your frame. Target: player targets and focus. None: Classic green. Chromatic: rainbow cycle on your player frame only."
	)

	local function GetNpcColorOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("hostility", "Hostility")
		container:Add("blizzard", "Blizzard")
		container:Add("chromatic", "Chromatic")
		return container:GetData()
	end

	local npcColorSetting = RegisterTrackedProxySetting(
		category,
		"WHOAUF_NPC_COLOR",
		Settings.VarType.String,
		"NPC color",
		"hostility",
		function()
			return NormalizeNpcColorMode(self:GetColorOption("npcColor", "hostility"))
		end,
		function(value)
			value = NormalizeNpcColorMode(value)
			self:SetColorOption("npcColor", value)
			-- Start/stop cycle before refresh so GetHealthBarColor sees the new mode.
			if self.UpdateHealthColorCycleDriver then
				self:UpdateHealthColorCycleDriver()
			else
				OnHealthColorSettingChanged()
			end
		end
	)
	local npcColorInitializer = CreateLoopingDropdown(
		category,
		npcColorSetting,
		GetNpcColorOptions,
		"How NPC health bars are tinted. Hostility uses Whoa's reaction palette. Blizzard uses the default reaction colors. Chromatic cycles around the color wheel on NPC frames (independent of the Players Chromatic option)."
	)

	local customHealthSetting = RegisterColorProxy(
		"WHOAUF_CUSTOM_HEALTH_COLOR",
		"customHealthColor",
		"Custom health bar color",
		false,
		nil,
		function()
			OnHealthColorSettingChanged()
		end
	)
	local customHealthTooltip =
		"Paint health bars with a fixed color from the swatch. Overrides class and Hostility/Blizzard NPC color on the frames it applies to. Ignored on your player frame while Players is Chromatic, and on NPCs while NPC color is Chromatic. Never party or boss. Disconnect still shows grey."

	-- Stock ColorSwatch is square; reshape ours into a short horizontal bar.
	local function StyleHealthColorSwatch(swatch)
		if not swatch or swatch.whoaRectSwatch then
			return
		end
		swatch.whoaRectSwatch = true
		local outerW, outerH = 42, 16
		local bgW, bgH = 40, 14
		local borderW, borderH = 38, 12
		local colorW, colorH = 36, 10
		local function SizeRect()
			swatch:SetSize(outerW, outerH)
			if PixelUtil then
				PixelUtil.SetSize(swatch.SwatchBg, bgW, bgH)
				PixelUtil.SetSize(swatch.InnerBorder, borderW, borderH)
				PixelUtil.SetSize(swatch.Color, colorW, colorH)
			else
				swatch.SwatchBg:SetSize(bgW, bgH)
				swatch.InnerBorder:SetSize(borderW, borderH)
				swatch.Color:SetSize(colorW, colorH)
			end
		end
		swatch:HookScript("OnShow", SizeRect)
		SizeRect()
	end

	local customHealthInitializer
	if CreateSettingsCheckboxWithColorSwatchInitializer and CreateColor then
		customHealthInitializer = CreateSettingsCheckboxWithColorSwatchInitializer(
			customHealthSetting,
			customHealthTooltip,
			function(swatch)
				StyleHealthColorSwatch(swatch)
				if self.OpenHealthBarColorPicker then
					self:OpenHealthBarColorPicker(swatch)
				end
			end,
			true, -- swatch only clickable while checkbox is on
			false,
			function()
				local c = self:GetHealthBarCustomColor()
				return CreateColor(c.r, c.g, c.b)
			end,
			"Health bar color",
			"Choose the fixed health bar color."
		)
		layout:AddInitializer(customHealthInitializer)
		if SettingsCheckboxWithColorSwatchControlMixin then
			hooksecurefunc(SettingsCheckboxWithColorSwatchControlMixin, "Init", function(control, initializer)
				local setting = initializer and initializer.GetSetting and initializer:GetSetting()
				if setting == customHealthSetting then
					StyleHealthColorSwatch(control.ColorSwatch)
				end
			end)
		end
	else
		customHealthInitializer = CreateCheckbox(category, customHealthSetting, customHealthTooltip)
		layout:AddInitializer(CreateSettingsButtonInitializer(
			"Health bar color",
			"Pick…",
			function()
				if self.OpenHealthBarColorPicker then
					self:OpenHealthBarColorPicker()
				end
			end,
			"Open the color picker for the custom health bar tint.",
			true
		))
	end

	local customPlayerOnlySetting = RegisterColorProxy(
		"WHOAUF_CUSTOM_HEALTH_COLOR_PLAYER_ONLY",
		"customHealthColorPlayerOnly",
		"Only player frame",
		false,
		nil,
		function()
			OnHealthColorSettingChanged()
		end
	)
	local customPlayerOnlyInitializer = CreateCheckbox(
		category,
		customPlayerOnlySetting,
		"On: custom color applies only to your player frame. Off: also target, focus, ToT, and pet. Never party or boss."
	)
	customPlayerOnlyInitializer:SetParentInitializer(customHealthInitializer, function()
		return customHealthSetting:GetValue()
	end)

	db.healthColorCycleSpeed = tonumber(db.healthColorCycleSpeed) or 4
	if db.healthColorCycleSpeed < 1 then
		db.healthColorCycleSpeed = 1
	elseif db.healthColorCycleSpeed > 20 then
		db.healthColorCycleSpeed = 20
	end
	local cycleSpeedSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_HEALTH_COLOR_CYCLE_SPEED",
		"healthColorCycleSpeed",
		db,
		Settings.VarType.Number,
		"Cycle speed",
		4
	)
	cycleSpeedSetting:SetValueChangedCallback(function(setting, value)
		if type(value) ~= "number" then
			value = setting and setting.GetValue and setting:GetValue()
		end
		value = tonumber(value) or 4
		if value < 1 then
			value = 1
		elseif value > 20 then
			value = 20
		end
		db.healthColorCycleSpeed = value
		if self.IsHealthColorCycleActive and self:IsHealthColorCycleActive() and self.SetHealthColorCycleRuntime then
			self:SetHealthColorCycleRuntime(
				true,
				value * 0.05,
				self.IsHealthColorCycleTintPlayer and self:IsHealthColorCycleTintPlayer(),
				self.IsHealthColorCycleTintNpc and self:IsHealthColorCycleTintNpc()
			)
		end
	end)
	local cycleSpeedOptions = Settings.CreateSliderOptions(1, 20, 1)
	cycleSpeedOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		local seconds = 1 / (value * 0.05)
		if seconds >= 10 then
			return string.format("%.0fs", seconds)
		end
		return string.format("%.1fs", seconds)
	end)
	local cycleSpeedInitializer = CreateSlider(
		category,
		cycleSpeedSetting,
		cycleSpeedOptions,
		"How fast the chromatic cycle runs. Higher = faster (label shows seconds per full loop)."
	)
	cycleSpeedInitializer:SetParentInitializer(npcColorInitializer, function()
		return classSetting:GetValue() == "chromatic" or npcColorSetting:GetValue() == "chromatic"
	end)

	-- Checked = per-character color overrides; unchecked = account-wide WhoaUFDB.
	db.colorsLocal = db.colorsLocal and true or false
	local colorsLocalSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_COLORS_LOCAL",
		"colorsLocal",
		db,
		Settings.VarType.Boolean,
		"Per-character colors",
		false
	)
	colorsLocalSetting:SetValueChangedCallback(function(setting, value)
		if type(value) ~= "boolean" then
			value = setting and setting.GetValue and setting:GetValue()
		end
		if self.SetColorsLocal then
			self:SetColorsLocal(value and true or false)
		else
			db.colorsLocal = value and true or false
			OnHealthColorSettingChanged()
		end
		-- Resync color dropdowns/checkboxes to the active account or character store.
		local classS = Settings.GetSetting("WHOAUF_CLASS_COLOR")
		local npcS = Settings.GetSetting("WHOAUF_NPC_COLOR")
		local customS = Settings.GetSetting("WHOAUF_CUSTOM_HEALTH_COLOR")
		local customPlayerS = Settings.GetSetting("WHOAUF_CUSTOM_HEALTH_COLOR_PLAYER_ONLY")
		if classS and classS.SetValue then
			classS:SetValue(NormalizeClassColorMode(self:GetColorOption("classColor", "all")))
		end
		if npcS and npcS.SetValue then
			npcS:SetValue(NormalizeNpcColorMode(self:GetColorOption("npcColor", "hostility")))
		end
		if customS and customS.SetValue then
			customS:SetValue(self:GetColorOption("customHealthColor", false) and true or false)
		end
		if customPlayerS and customPlayerS.SetValue then
			customPlayerS:SetValue(self:GetColorOption("customHealthColorPlayerOnly", false) and true or false)
		end
	end)
	CreateCheckbox(
		category,
		colorsLocalSetting,
		"Off (default): color options apply to every character. On: this character keeps its own color choices."
	)

	---------------------------------------------------------------------------
	-- Bars & numbers
	---------------------------------------------------------------------------
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Bars & Numbers"))

	local function GetStatusBarTextureOptions()
		local container = Settings.CreateControlTextContainer()
		local keys, labels = self:GetStatusBarTextureOptions()
		for _, key in ipairs(keys) do
			container:Add(key, labels[key] or key)
		end
		return container:GetData()
	end

	local statusBarSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_STATUSBAR_TEXTURE",
		"statusBarTexture",
		db,
		Settings.VarType.String,
		"Bar texture",
		"blizzard"
	)
	statusBarSetting:SetValueChangedCallback(function()
		if self.ApplyStatusBarTextures then
			self:ApplyStatusBarTextures()
		end
	end)
	CreateLoopingDropdown(category, statusBarSetting, GetStatusBarTextureOptions, "Texture used for health and power bars.")

	do
		local CVAR_VALUE_NUMERIC = "NUMERIC"
		local CVAR_VALUE_PERCENT = "PERCENT"
		local CVAR_VALUE_BOTH = "BOTH"
		local CVAR_VALUE_NONE = "NONE"
		-- All flavors: value / percent / both / none.
		-- Mainline formats via Unit*Percent + AbbreviateNumbers (secret-safe).

		local function GetStatusTextValue()
			local statusTextDisplay = C_CVar and C_CVar.GetCVar("statusTextDisplay") or GetCVar("statusTextDisplay")
			if statusTextDisplay == CVAR_VALUE_NUMERIC then
				return 1
			elseif statusTextDisplay == CVAR_VALUE_PERCENT then
				return 2
			elseif statusTextDisplay == CVAR_VALUE_BOTH then
				return 3
			elseif statusTextDisplay == CVAR_VALUE_NONE then
				return 4
			end
			-- Mainline default before first choice: percent.
			if WhoaUF.IsMainline and WhoaUF:IsMainline() then
				return 2
			end
		end

		local function SetStatusTextValue(value)
			if value == 1 then
				SetCVar("statusTextDisplay", CVAR_VALUE_NUMERIC)
				SetCVar("statusText", "1")
			elseif value == 2 then
				SetCVar("statusTextDisplay", CVAR_VALUE_PERCENT)
				SetCVar("statusText", "1")
			elseif value == 3 then
				SetCVar("statusTextDisplay", CVAR_VALUE_BOTH)
				SetCVar("statusText", "1")
			elseif value == 4 then
				SetCVar("statusTextDisplay", CVAR_VALUE_NONE)
				SetCVar("statusText", "0")
			end
			if self.RefreshAllUnitFrames then
				self:RefreshAllUnitFrames()
			end
		end

		local function GetStatusTextOptions()
			local container = Settings.CreateControlTextContainer()
			container:Add(1, STATUS_TEXT_VALUE)
			container:Add(2, STATUS_TEXT_PERCENT)
			container:Add(3, STATUS_TEXT_BOTH)
			container:Add(4, NONE)
			return container:GetData()
		end

		local statusTextSetting = RegisterTrackedProxySetting(
			category,
			"WHOAUF_STATUS_TEXT",
			Settings.VarType.Number,
			"Health and mana text",
			(WhoaUF.IsMainline and WhoaUF:IsMainline()) and 2 or 4,
			GetStatusTextValue,
			SetStatusTextValue
		)
		CreateLoopingDropdown(
			category,
			statusTextSetting,
			GetStatusTextOptions,
			"How health and mana numbers appear on the bars. Retail uses Blizzard secret-safe formatters (percent via Unit*Percent; values follow Number abbreviation)."
		)
	end

	local function GetStatusBarFontOptions()
		local container = Settings.CreateControlTextContainer()
		local keys, labels = self:GetStatusBarFontOptions()
		for _, key in ipairs(keys) do
			container:Add(key, labels[key] or key)
		end
		return container:GetData()
	end

	if self.MigrateStatusBarFontOptions then
		self:MigrateStatusBarFontOptions(db)
	end

	local statusBarFontSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_STATUSBAR_FONT",
		"statusBarFont",
		db,
		Settings.VarType.String,
		"Number font",
		"retail"
	)
	statusBarFontSetting:SetValueChangedCallback(function()
		if self.ApplyStatusBarFonts then
			self:ApplyStatusBarFonts()
		end
	end)
	CreateLoopingDropdown(
		category,
		statusBarFontSetting,
		GetStatusBarFontOptions,
		"Font for health and power numbers. Retail uses Friz Quadrata; Classic and Mono use Arial Narrow. Mono is thick-outlined with no antialiasing."
	)

	do
		local defaultNumberAbbreviation = self:GetDefaultNumberAbbreviationMode()
		local function NormalizeNumberAbbreviation(value)
			if value == "whoa" or value == "large" or value == "numbers" then
				return value
			end
			return defaultNumberAbbreviation
		end
		db.numberAbbreviation = NormalizeNumberAbbreviation(db.numberAbbreviation)

		local function GetNumberAbbreviationOptions()
			local container = Settings.CreateControlTextContainer()
			container:Add("whoa", "Whoa")
			container:Add("numbers", "Compact (1.2K)")
			container:Add("large", "Large (Blizzard)")
			return container:GetData()
		end

		local numberAbbrevSetting = RegisterTrackedAddOnSetting(
			category,
			"WHOAUF_NUMBER_ABBREVIATION",
			"numberAbbreviation",
			db,
			Settings.VarType.String,
			"Number abbreviation",
			defaultNumberAbbreviation
		)
		numberAbbrevSetting:SetValueChangedCallback(function(setting, value)
			if type(value) ~= "string" then
				value = setting and setting.GetValue and setting:GetValue()
			end
			db.numberAbbreviation = NormalizeNumberAbbreviation(value)
			if self.RefreshAllUnitFrames then
				self:RefreshAllUnitFrames()
			end
			if self.UpdateAllPartyFrames then
				self:UpdateAllPartyFrames()
			end
			if self.UpdatePetFrame then
				self:UpdatePetFrame()
			end
		end)
		local tooltip = "How large health and power values are shortened. Whoa is the Classic Whoa style (e.g. 12.345, 100 K, 1.25 M). Compact and Large use Blizzard abbreviators."
		if self:IsMainline() then
			tooltip = tooltip .. " On Retail, Whoa falls back to Compact when the game hides exact values (e.g. in combat)."
		end
		CreateLoopingDropdown(
			category,
			numberAbbrevSetting,
			GetNumberAbbreviationOptions,
			tooltip
		)
	end

	---------------------------------------------------------------------------
	-- Buffs & Debuffs
	---------------------------------------------------------------------------
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Buffs & Debuffs"))

	local auraMinSize, auraMaxSize, auraDefaultSize = 12, 73, 27
	if self.GetAuraIconSizeRange then
		auraMinSize, auraMaxSize, auraDefaultSize = self:GetAuraIconSizeRange()
	end
	-- Cap aura size from older profiles that allowed larger icons than auraMaxSize.
	if type(db.auraIconSize) == "number" and db.auraIconSize > auraMaxSize then
		db.auraIconSize = auraMaxSize
	end
	local auraSizeSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_AURA_SIZE",
		"auraIconSize",
		db,
		Settings.VarType.Number,
		"Buff icon size",
		auraDefaultSize
	)
	auraSizeSetting:SetValueChangedCallback(function()
		if self.RefreshAuraIconSizes then
			self:RefreshAuraIconSizes()
		end
	end)
	local auraSizeOptions = Settings.CreateSliderOptions(auraMinSize, auraMaxSize, 1)
	auraSizeOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, tostring)
	CreateSlider(
		category,
		auraSizeSetting,
		auraSizeOptions,
		"Size of the large buff icons on target and focus. Debuffs scale with them."
	)

	layout:AddInitializer(CreateSettingsButtonInitializer("Classic buff size", "21", function()
		auraSizeSetting:SetValue(21)
	end, "Set buff icons to Classic Blizzard size (21).", true))
	layout:AddInitializer(CreateSettingsButtonInitializer("Whoa buff size", "27", function()
		auraSizeSetting:SetValueToDefault()
	end, "Set buff icons to the Whoa default size (27).", true))

	---------------------------------------------------------------------------
	-- Combat
	---------------------------------------------------------------------------
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Combat"))

	local function NormalizeCombatFeedbackColors(value)
		if value == "school" then
			return "school"
		end
		return "default"
	end
	db.combatFeedbackColors = NormalizeCombatFeedbackColors(db.combatFeedbackColors)

	local function GetCombatFeedbackColorsOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("default", "Default")
		container:Add("school", "School")
		return container:GetData()
	end
	local combatFeedbackColorsSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_COMBAT_FEEDBACK_COLORS",
		"combatFeedbackColors",
		db,
		Settings.VarType.String,
		"Combat text colors",
		"default"
	)
	combatFeedbackColorsSetting:SetValueChangedCallback(function(setting, value)
		if type(value) ~= "string" then
			value = setting and setting.GetValue and setting:GetValue()
		end
		db.combatFeedbackColors = NormalizeCombatFeedbackColors(value)
	end)
	CreateLoopingDropdown(
		category,
		combatFeedbackColorsSetting,
		GetCombatFeedbackColorsOptions,
		"Colors for damage numbers on unit-frame portraits. Default matches floating combat text: white auto-attacks, yellow specials, orange pet, green heals. School colors by spell school (fire, frost, shadow, arcane, etc.)."
	)

	local function NormalizeNumericThreatFrame(value)
		if value == "target" then
			return "target"
		end
		if value == "off" or value == false then
			return "off"
		end
		return "player"
	end
	db.numericThreatFrame = NormalizeNumericThreatFrame(db.numericThreatFrame)

	local function GetNumericThreatFrameOptions()
		local container = Settings.CreateControlTextContainer()
		container:Add("off", "Off")
		local dkArt = self.GetDeathKnightPlayerArt and self:GetDeathKnightPlayerArt()
		-- BlizzCon uses the name slot — omit "On player"; Alpha can show threat % with the name.
		if dkArt ~= "blizzcon" then
			container:Add("player", "On player frame")
		end
		container:Add("target", "On target frame")
		return container:GetData()
	end
	local numericThreatSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_NUMERIC_THREAT",
		"numericThreatFrame",
		db,
		Settings.VarType.String,
		"Threat percent",
		"player"
	)
	numericThreatSetting:SetValueChangedCallback(function(_, value)
		db.numericThreatFrame = NormalizeNumericThreatFrame(value)
		-- Reject "player" threat placement while BlizzCon art is active.
		if db.numericThreatFrame == "player"
			and self.GetDeathKnightPlayerArt
			and self:GetDeathKnightPlayerArt() == "blizzcon" then
			db.numericThreatFrame = "target"
		end
		if self.ApplyNumericThreatFrame then
			self:ApplyNumericThreatFrame()
		end
	end)
	CreateLoopingDropdown(
		category,
		numericThreatSetting,
		GetNumericThreatFrameOptions,
		"Show your threat percent on the player frame or above the target. On Whoa and Thick, the unit name hides while the percent is shown (except DK Alpha, which keeps both). Classic keeps both. BlizzCon specialty frames only support On target (or Off)."
	)

	-- Timing sparks are independent modules (separate db keys). See docs/timing/README.md.
	-- ModeToBool maps legacy combat-gated values ("combat" / "only in combat") to on/off.
	local Timing = self.Timing
	db.manaTickGlow = Timing.ModeToBool(db.manaTickGlow)
	if db.swingTickGlow == nil then
		db.swingTickGlow = db.manaTickGlow
	end
	db.swingTickGlow = Timing.ModeToBool(db.swingTickGlow)
	db.powerTickGlow = Timing.ModeToBool(db.powerTickGlow)
	db.manaTickLatency = db.manaTickLatency and true or false

	-- Skip checkboxes the running client cannot drive (Mainline/Forever, Wrath+ energy, etc.).
	-- Saved keys still migrate above so values survive moving between clients.
	local function AddTickGlowCheckbox(varName, settingId, label, tooltip, onChanged)
		local setting = RegisterTrackedAddOnSetting(
			category,
			settingId,
			varName,
			db,
			Settings.VarType.Boolean,
			label,
			false
		)
		setting:SetValueChangedCallback(function(s, value)
			if type(value) ~= "boolean" and s and s.GetValue then
				value = s:GetValue()
			end
			db[varName] = value and true or false
			onChanged()
		end)
		CreateCheckbox(category, setting, tooltip)
		return setting
	end

	do
		-- Mana checkbox label/tooltip follow what this client supports.
		local manaLabel, manaTip
		local manaSupported = Timing.hasRegenTick or Timing.hasFiveSecondRule or Timing.hasCombatManaPulse
		if Timing.hasRegenTick then
			manaLabel = "Mana tick"
			manaTip = "Shows when your next mana tick lands. Mana color = 2s regen tick, white = five-second rule. "
				.. "Casters and moonkin: primary mana bar. Druid cat/bear: alternate mana bar (Wrath+), or the power bar on Era/TBC (hidden mana pool)."
		elseif Timing.hasFiveSecondRule then
			manaLabel = "Five-second rule"
			manaTip = "White spark on the mana bar for the five-second rule. Wrath has no 2s tick — only the rule. Removed in Cataclysm."
		elseif Timing.hasCombatManaPulse then
			manaLabel = "Combat mana pulse"
			manaTip = "Mana-colored spark while in combat with missing mana. Cataclysm: ~5s cycle; Mists: ~1s. Hidden at full mana until the next spend."
		end
		if manaSupported then
			AddTickGlowCheckbox(
				"manaTickGlow",
				"WHOAUF_MANA_TICK_GLOW",
				manaLabel,
				manaTip,
				function()
					if self.InitManaTickGlowModule then
						self:InitManaTickGlowModule()
					end
					if self.RefreshManaTickGlow then
						self:RefreshManaTickGlow()
					end
				end
			)
		end
		if Timing.hasRegenTick then
			AddTickGlowCheckbox(
				"manaTickLatency",
				"WHOAUF_MANA_TICK_LATENCY",
				"Mana tick latency",
				"Lead the mana tick spark by your world latency so it estimates the server tick (cast-weave). Off by default — then the spark matches when your mana bar moves.",
				function()
					if self.RefreshManaTickGlow then
						self:RefreshManaTickGlow()
					end
				end
			)
		end
	end

	if Timing.hasRegenTick then
		AddTickGlowCheckbox(
			"powerTickGlow",
			"WHOAUF_POWER_TICK_GLOW",
			"Energy tick",
			"Energy-colored spark on the power bar when the next energy tick lands (rogues, druid cat). Only on Classic Era and TBC — later clients regen energy continuously.",
			function()
				if self.InitPowerTickGlowModule then
					self:InitPowerTickGlowModule()
				end
				if self.RefreshPowerTickGlow then
					self:RefreshPowerTickGlow()
				end
			end
		)
	end

	if Timing.cleuAllowed then
		AddTickGlowCheckbox(
			"swingTickGlow",
			"WHOAUF_SWING_TICK_GLOW",
			"Swing timer",
			"Auto-attack timers on the power bar (untinted stock spark; off hand is dimmer). Always a little late by your latency.",
			function()
				if self.InitSwingTickGlowModule then
					self:InitSwingTickGlowModule()
				end
				if self.RefreshSwingTickGlow then
					self:RefreshSwingTickGlow()
				end
			end
		)
	end

	---------------------------------------------------------------------------
	-- General
	---------------------------------------------------------------------------
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("General"))

	local welcomeSetting = RegisterTrackedAddOnSetting(
		category,
		"WHOAUF_WELCOME_TOAST",
		"hideWelcome",
		db,
		Settings.VarType.Boolean,
		"Skip welcome message",
		false
	)
	welcomeSetting:SetValueChangedCallback(function(_, value)
		db.hideWelcome = value and true or false
	end)
	CreateCheckbox(
		category,
		welcomeSetting,
		"Don't show the Whoa welcome toast after you log in."
	)

	if not StaticPopupDialogs["WHOAUF_RESET_OPTIONS"] then
		StaticPopupDialogs["WHOAUF_RESET_OPTIONS"] = {
			text = "Reset all Whoa Unit Frames options to their defaults?\n\nThis restores Whoa settings and Dev force-show flags. Edit Mode layout positions and Blizzard health/mana text are unchanged.",
			button1 = YES,
			button2 = CANCEL,
			OnAccept = function()
				if WhoaUF.ResetOptionsToDefaults then
					WhoaUF:ResetOptionsToDefaults()
				end
			end,
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
			preferredIndex = 3,
		}
	end
	layout:AddInitializer(CreateSettingsButtonInitializer(
		"Reset options",
		"Reset",
		function()
			if InCombatLockdown() then
				UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
				return
			end
			StaticPopup_Show("WHOAUF_RESET_OPTIONS")
		end,
		"Restore every Whoa Unit Frames option to its default. Does not move Edit Mode frames or change Blizzard status text.",
		true
	))

	-- Enable / force-show live in DevTools (/whoadev via RegisterDevToolsProvider), not Settings.

	Settings.RegisterAddOnCategory(category)
	self.settingsCategory = category
end
