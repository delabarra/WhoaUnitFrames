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
	-- Stock Blizzard vertical layout (ImplementationReadme): one category +
	-- Settings.Create*. EnumerateInitializers: Blizzard securecall-wraps next() over
	-- the initializer table; under addon taint that poisons Settings search into
	-- Social Discord (C_Discord.IsUserOAuthed). Plain ipairs keeps search /
	-- RepairDisplay / parent-walk working without that path. Display() still uses
	-- GetInitializers().
	local category, layout = Settings.RegisterVerticalLayoutCategory("Whoa Unit Frames")
	function layout:EnumerateInitializers()
		return ipairs(self:GetInitializers())
	end

	-- Track Settings variables so ResetOptionsToDefaults can refresh the panel UI.
	-- WHOAUF_STATUS_TEXT is a Blizzard CVar — intentionally not tracked.
	local trackedVars = {}
	self._optionSettingVariables = trackedVars

	-- SettingMixin:SetValueChangedCallback registers ownerless. Prefer an explicit
	-- owner. Do not also register PROXY_STATUS_TEXT from Whoa bars (see
	-- UnitFrameShared CreateTextStatusBar): any Whoa touch of SettingsCallbackRegistry
	-- before nameplate OnLoad object-taints that registry into CUF secret compares.
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

	-- Stock Settings.Create* → GetLayout(category):AddInitializer.
	local function CreateCheckbox(cat, setting, tooltip)
		return Settings.CreateCheckbox(cat, setting, tooltip)
	end
	local function CreateSlider(cat, setting, options, tooltip)
		return Settings.CreateSlider(cat, setting, options, tooltip)
	end
	local function CreateDropdown(cat, setting, options, tooltip)
		return Settings.CreateDropdown(cat, setting, options, tooltip)
	end

	local function IsPlayerClass(classToken)
		local _, class = UnitClass("player")
		return class == classToken
	end

	-- Cache static dropdown option tables so scroll recycle does not rebuild them.
	local function MemoizeOptions(buildFn)
		local cached
		return function()
			if cached then
				return cached
			end
			cached = buildFn()
			return cached
		end
	end

	local function CreateLoopingDropdown(cat, setting, optionsFn, tooltip)
		return CreateDropdown(cat, setting, optionsFn, tooltip)
	end

	-- Avoid Init → IsParentInitializerInLayout walking the full list (even with fast
	-- ipairs). Mark indent + short-circuit the layout membership check.
	local function AttachParent(childInitializer, parentInitializer, modifyPredicate)
		childInitializer:SetParentInitializer(parentInitializer, modifyPredicate)
		if childInitializer.Indent then
			childInitializer:Indent()
		end
		childInitializer.IsParentInitializerInLayout = function()
			return true
		end
		return childInitializer
	end

	-- Midnight: stock InitDropdown → SetupMenu → GenerateMenu while the row is shown.
	-- ScrollBox recycle runs that for every dropdown that enters view and hitchs the client.
	-- For WHOAUF_* only: install the menu generator without generating; build on OpenMenu.
	-- Steppers cycle setting values from the options table (no MenuDescription required).
	-- MenuConstants + dropdown mixins are required (Settings dropdown path on Midnight/Classic).
	if SettingsDropdownControlMixin and MenuConstants and MenuConstants.VerticalGridDirection
		and not WhoaUF._whoaLazyDropdownHooked then
		WhoaUF._whoaLazyDropdownHooked = true
		local function IsWhoaSetting(setting)
			local variable = setting and setting.GetVariable and setting:GetVariable()
			return type(variable) == "string" and variable:sub(1, 7) == "WHOAUF_"
		end
		local function OptionsList(options)
			if type(options) == "function" then
				return options()
			end
			return options
		end
		local function LabelForSetting(setting, options)
			local value = setting:GetValue()
			local list = OptionsList(options)
			if list then
				for i = 1, #list do
					local opt = list[i]
					if opt and opt.value == value then
						return opt.label or opt.text or tostring(value)
					end
				end
			end
			if value == nil then
				return ""
			end
			return tostring(value)
		end
		local function CycleSetting(setting, options, delta)
			local list = OptionsList(options)
			if not list or #list == 0 then
				return
			end
			local value = setting:GetValue()
			local idx = 1
			for i = 1, #list do
				if list[i].value == value then
					idx = i
					break
				end
			end
			local n = #list
			local nextIdx = ((idx - 1 + delta) % n) + 1
			setting:SetValue(list[nextIdx].value)
		end

		local baseSetupDropdownMenu = SettingsDropdownControlMixin.SetupDropdownMenu
		local baseInitDropdown = SettingsDropdownControlMixin.InitDropdown

		function SettingsDropdownControlMixin:SetupDropdownMenu(button, setting, options, initTooltip, initializer)
			if not IsWhoaSetting(setting) then
				return baseSetupDropdownMenu(self, button, setting, options, initTooltip, initializer)
			end

			local inserter = Settings.CreateDropdownOptionInserter(setting, options, initializer)
			button:SetDefaultText(CUSTOM or "")
			-- Install generator only; OpenMenu → GenerateMenu builds on click.
			-- Do not call SetupMenu (that GenerateMenu's while the row is shown).
			button.menuGenerator = function(dropdown, rootDescription)
				rootDescription:SetGridMode(MenuConstants.VerticalGridDirection)
				inserter(setting, rootDescription)
			end
			button.menuDescription = nil
			button.whoaOptions = options
			button.whoaSetting = setting
			button:SetTooltipFunc(initTooltip)
			button:SetDefaultTooltipAnchors()
			button:SetScript("OnEnter", function()
				if ButtonStateBehaviorMixin then
					ButtonStateBehaviorMixin.OnEnter(button)
				end
				if DefaultTooltipMixin then
					DefaultTooltipMixin.OnEnter(button)
				end
			end)
			button:SetScript("OnLeave", function()
				if ButtonStateBehaviorMixin then
					ButtonStateBehaviorMixin.OnLeave(button)
				end
				if DefaultTooltipMixin then
					DefaultTooltipMixin.OnLeave(button)
				end
			end)
			if button.SetText then
				button:SetText(LabelForSetting(setting, options))
			end

			local stepper = self.Control
			if stepper then
				stepper.whoaSetting = setting
				stepper.whoaOptions = options
				stepper.whoaDropdown = button
				if not stepper.whoaLazySteppers then
					stepper.whoaLazySteppers = true
					stepper.Increment = function(self)
						CycleSetting(self.whoaSetting, self.whoaOptions, 1)
						local dd = self.whoaDropdown
						if dd and dd.SetText and self.whoaSetting then
							dd:SetText(LabelForSetting(self.whoaSetting, self.whoaOptions))
						end
					end
					stepper.Decrement = function(self)
						CycleSetting(self.whoaSetting, self.whoaOptions, -1)
						local dd = self.whoaDropdown
						if dd and dd.SetText and self.whoaSetting then
							dd:SetText(LabelForSetting(self.whoaSetting, self.whoaOptions))
						end
					end
					local baseSetSteppersEnabled = stepper.SetSteppersEnabled
					stepper.SetSteppersEnabled = function(self, canDecrement, canIncrement)
						if self.whoaDropdown and self.whoaDropdown:IsEnabled() then
							canDecrement, canIncrement = true, true
						end
						if baseSetSteppersEnabled then
							baseSetSteppersEnabled(self, canDecrement, canIncrement)
						elseif DropdownWithSteppersMixin and DropdownWithSteppersMixin.SetSteppersEnabled then
							DropdownWithSteppersMixin.SetSteppersEnabled(self, canDecrement, canIncrement)
						end
					end
				end
			end
		end

		-- Stock InitDropdown calls HasAnyRadioDescriptions() which TraverseMenu's a nil
		-- menuDescription after our lazy SetupDropdownMenu — crash on scroll recycle.
		function SettingsDropdownControlMixin:InitDropdown()
			local setting = self:GetSetting()
			if not IsWhoaSetting(setting) then
				return baseInitDropdown(self)
			end

			local initializer = self:GetElementData()
			local options = initializer:GetOptions()
			local initTooltip = Settings.CreateOptionsInitTooltip(
				setting, initializer:GetName(), initializer:GetTooltip(), options, initializer)
			self:SetupDropdownMenu(self.Control.Dropdown, setting, options, initTooltip, initializer)

			if self.forceSteppersHidden then
				self.Control:HideSteppers()
			else
				self.Control:SetSteppersShown(true)
				if self.Control.UpdateSteppers then
					self.Control:UpdateSteppers()
				end
			end

			local dropdown = self.Control.Dropdown
			if dropdown and dropdown.SetText then
				dropdown:SetText(LabelForSetting(setting, options))
			end
		end

		hooksecurefunc(SettingsDropdownControlMixin, "OnSettingValueChanged", function(self, setting)
			if not IsWhoaSetting(setting) then
				return
			end
			local dropdown = self.Control and self.Control.Dropdown
			if dropdown and dropdown.SetText and dropdown.whoaSetting then
				dropdown:SetText(LabelForSetting(dropdown.whoaSetting, dropdown.whoaOptions))
			end
		end)
	end

	-- Profiles (name box + list; canvas subcategory)
	do
		local function EnsureProfilesPanel()
			if self._profilesPanel then
				return self._profilesPanel
			end

			local panel = CreateFrame("Frame")
			panel:Hide()
			panel:SetSize(480, 420)
			self._profilesPanel = panel

			local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
			title:SetPoint("TOPLEFT", 16, -16)
			title:SetText("Profiles")

			local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
			help:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
			help:SetJustifyH("LEFT")
			help:SetText("Click a profile to load it. Unsaved changes ask Save / Discard / Cancel (no Save if options already match a profile; no prompt if they match the one you click). Default cannot be overwritten, renamed, or deleted — Save copies your changes under your character name (editable). Rename uses the name box for the active profile. DK specialty frames save as \"Name (DK)\" (Death Knights / Forever warriors only).")

			local nameLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			nameLabel:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -16)
			nameLabel:SetText("Profile name")

			local editBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
			editBox:SetAutoFocus(false)
			editBox:SetMaxLetters(48)
			editBox:SetHeight(24)
			editBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -6)
			editBox:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
			editBox:SetFontObject(ChatFontNormal)
			editBox:SetScript("OnEscapePressed", function(box)
				box:ClearFocus()
			end)
			panel.NameBox = editBox

			local listLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
			listLabel:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -4, -14)
			listLabel:SetText("Available profiles")

			local listBorder = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
			listBorder:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -6)
			listBorder:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
			listBorder:SetHeight(220)
			if listBorder.SetBackdrop then
				listBorder:SetBackdrop({
					bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
					edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
					tile = true,
					tileSize = 12,
					edgeSize = 12,
					insets = { left = 2, right = 2, top = 2, bottom = 2 },
				})
				listBorder:SetBackdropColor(0, 0, 0, 0.45)
				listBorder:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
			end

			local scroll = CreateFrame("ScrollFrame", nil, listBorder, "UIPanelScrollFrameTemplate")
			scroll:SetPoint("TOPLEFT", 6, -6)
			scroll:SetPoint("BOTTOMRIGHT", -26, 6)

			local scrollChild = CreateFrame("Frame", nil, scroll)
			scrollChild:SetSize(1, 1)
			scroll:SetScrollChild(scrollChild)
			panel.ListChild = scrollChild
			panel.ListButtons = {}

			local function RefreshProfilesPanel()
				local names = self.GetProfileNames and self:GetProfileNames() or { "Default" }
				local active = self.GetActiveProfileName and self:GetActiveProfileName() or "Default"
				local defaultName = self.GetDefaultProfileName and self:GetDefaultProfileName() or "Default"
				if not editBox:HasFocus() then
					-- Show the active profile name (including Default). Character name is
					-- filled in on Save when leaving Default — not while Default is selected.
					editBox:SetText(active)
					editBox:SetCursorPosition(0)
				end

				local buttons = panel.ListButtons
				local width = math.max(200, (scroll:GetWidth() or 400) - 4)
				local y = 0
				for i = 1, #names do
					local name = names[i]
					local btn = buttons[i]
					if not btn then
						btn = CreateFrame("Button", nil, scrollChild)
						btn:SetHeight(22)
						btn:SetNormalFontObject(GameFontHighlightSmall)
						btn:SetHighlightFontObject(GameFontHighlightSmall)
						btn:SetScript("OnClick", function(b)
							local profileName = b.profileName
							if not profileName then
								return
							end
							editBox:ClearFocus()
							if profileName == (self.GetActiveProfileName and self:GetActiveProfileName()) then
								RefreshProfilesPanel()
								return
							end
							-- Prompts Save / Discard / Cancel when dirty (Save omitted if options match a profile).
							if self.RequestActiveProfile then
								self:RequestActiveProfile(profileName)
							else
								self:SetActiveProfile(profileName)
							end
							RefreshProfilesPanel()
						end)
						local hl = btn:CreateTexture(nil, "HIGHLIGHT")
						hl:SetAllPoints()
						hl:SetColorTexture(1, 1, 1, 0.12)
						btn.Label = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
						btn.Label:SetPoint("LEFT", 6, 0)
						btn.Label:SetPoint("RIGHT", -6, 0)
						btn.Label:SetJustifyH("LEFT")
						buttons[i] = btn
					end
					btn.profileName = name
					btn.Label:SetText(name)
					if name == active then
						btn.Label:SetTextColor(1, 0.82, 0)
					else
						btn.Label:SetTextColor(1, 1, 1)
					end
					btn:ClearAllPoints()
					btn:SetPoint("TOPLEFT", 0, -y)
					btn:SetWidth(width)
					btn:Show()
					y = y + 22
				end
				for i = #names + 1, #buttons do
					buttons[i]:Hide()
					buttons[i].profileName = nil
				end
				scrollChild:SetSize(width, math.max(y, 1))

				local deleteBtn = panel.DeleteButton
				local renameBtn = panel.RenameButton
				local onDefault = active == defaultName
				if deleteBtn then
					if onDefault then
						deleteBtn:Disable()
					else
						deleteBtn:Enable()
					end
				end
				if renameBtn then
					if onDefault then
						renameBtn:Disable()
					else
						renameBtn:Enable()
					end
				end
			end
			panel.Refresh = RefreshProfilesPanel

			local function SaveFromNameBox()
				if InCombatLockdown() then
					UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
					return
				end
				local defaultName = self.GetDefaultProfileName and self:GetDefaultProfileName() or "Default"
				local active = self.GetActiveProfileName and self:GetActiveProfileName() or defaultName
				local name = editBox:GetText() or ""
				name = name:match("^%s*(.-)%s*$") or ""
				-- Leaving Default: prefill character name when the box still says Default/empty.
				if active == defaultName and (name == "" or name == defaultName) then
					name = self.GetSuggestedProfileName and self:GetSuggestedProfileName() or "Character"
					editBox:SetText(name)
					editBox:SetCursorPosition(0)
				end
				local ok, err = self:SaveProfileAs(name)
				if ok then
					RefreshProfilesPanel()
					if DEFAULT_CHAT_FRAME then
						DEFAULT_CHAT_FRAME:AddMessage(
							"|cff69ccf0Whoa Unit Frames:|r saved profile |cffffd200"
								.. self:GetActiveProfileName()
								.. "|r."
						)
					end
				elseif err == "empty" or err == "reserved" then
					UIErrorsFrame:AddMessage("Default cannot be overwritten. Save under a new profile name.", 1.0, 0.1, 0.1)
				end
			end

			local function RenameFromNameBox()
				if InCombatLockdown() then
					UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
					return
				end
				local defaultName = self.GetDefaultProfileName and self:GetDefaultProfileName() or "Default"
				local active = self.GetActiveProfileName and self:GetActiveProfileName() or defaultName
				if active == defaultName then
					UIErrorsFrame:AddMessage("The Default profile cannot be renamed.", 1.0, 0.1, 0.1)
					return
				end
				local newName = editBox:GetText() or ""
				newName = newName:match("^%s*(.-)%s*$") or ""
				if newName == "" or newName == defaultName then
					UIErrorsFrame:AddMessage("Enter a new profile name.", 1.0, 0.1, 0.1)
					return
				end
				local ok, err = self:RenameProfile(active, newName)
				if ok then
					editBox:ClearFocus()
					RefreshProfilesPanel()
					if DEFAULT_CHAT_FRAME then
						DEFAULT_CHAT_FRAME:AddMessage(
							"|cff69ccf0Whoa Unit Frames:|r renamed profile to |cffffd200"
								.. self:GetActiveProfileName()
								.. "|r."
						)
					end
				elseif err == "exists" then
					UIErrorsFrame:AddMessage("A profile with that name already exists.", 1.0, 0.1, 0.1)
				elseif err == "reserved" then
					UIErrorsFrame:AddMessage("The Default profile cannot be renamed.", 1.0, 0.1, 0.1)
				elseif err == "empty" then
					UIErrorsFrame:AddMessage("Enter a new profile name.", 1.0, 0.1, 0.1)
				end
			end

			editBox:SetScript("OnEnterPressed", function()
				SaveFromNameBox()
			end)

			if not StaticPopupDialogs["WHOAUF_PROFILE_DELETE"] then
				StaticPopupDialogs["WHOAUF_PROFILE_DELETE"] = {
					text = "Delete profile \"%s\"?\n\nCharacters using it will switch to Default.",
					button1 = YES,
					button2 = CANCEL,
					OnAccept = function()
						local name = WhoaUF._pendingDeleteProfile
						WhoaUF._pendingDeleteProfile = nil
						if not name then
							return
						end
						local ok, err = WhoaUF:DeleteProfile(name)
						if ok then
							local p = WhoaUF._profilesPanel
							if p and p.Refresh then
								p:Refresh()
							end
							if DEFAULT_CHAT_FRAME then
								DEFAULT_CHAT_FRAME:AddMessage(
									"|cff69ccf0Whoa Unit Frames:|r deleted profile |cffffd200" .. name .. "|r."
								)
							end
						elseif err == "reserved" then
							UIErrorsFrame:AddMessage("The Default profile cannot be deleted.", 1.0, 0.1, 0.1)
						end
					end,
					OnCancel = function()
						WhoaUF._pendingDeleteProfile = nil
					end,
					timeout = 0,
					whileDead = 1,
					hideOnEscape = 1,
					preferredIndex = 3,
				}
			end

			local saveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			saveBtn:SetSize(88, 24)
			saveBtn:SetPoint("TOPLEFT", listBorder, "BOTTOMLEFT", 0, -12)
			saveBtn:SetText("Save")
			saveBtn:SetScript("OnClick", SaveFromNameBox)

			local renameBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			renameBtn:SetSize(88, 24)
			renameBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
			renameBtn:SetText("Rename")
			panel.RenameButton = renameBtn
			renameBtn:SetScript("OnClick", RenameFromNameBox)

			local deleteBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			deleteBtn:SetSize(88, 24)
			deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 8, 0)
			deleteBtn:SetText("Delete")
			panel.DeleteButton = deleteBtn
			deleteBtn:SetScript("OnClick", function()
				if InCombatLockdown() then
					UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
					return
				end
				local defaultName = self.GetDefaultProfileName and self:GetDefaultProfileName() or "Default"
				-- Delete the active profile (not the name box — that may be a Save-As target).
				local name = self.GetActiveProfileName and self:GetActiveProfileName() or ""
				if name == "" or name == defaultName then
					return
				end
				self._pendingDeleteProfile = name
				StaticPopup_Show("WHOAUF_PROFILE_DELETE", name)
			end)

			panel:SetScript("OnShow", function()
				RefreshProfilesPanel()
			end)

			return panel
		end

		local profilesPanel = EnsureProfilesPanel()
		if Settings.RegisterCanvasLayoutSubcategory then
			Settings.RegisterCanvasLayoutSubcategory(category, profilesPanel, "Profiles")
		else
			-- Fallback: keep a section in the main list if canvas subcategories are missing.
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Profiles"))
			layout:AddInitializer(CreateSettingsButtonInitializer(
				"Open profiles",
				"Profiles",
				function()
					EnsureProfilesPanel():Show()
				end,
				"Open the profile name box and list.",
				true
			))
		end
	end

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

	local GetFrameStyleOptions = MemoizeOptions(function()
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
	end)

	-- Style → Rarity → Appearance → Player name → Name background → Portraits
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

	local GetPlayerFrameOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		local keys, labels = self:GetPlayerFrameBorderOptions()
		for _, key in ipairs(keys) do
			container:Add(key, labels[key] or key)
		end
		return container:GetData()
	end)

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
			"Player border rarity: Default, Elite, or Rare Elite. In cat and bear form the ClassResource rim adds a matching alternate mana bar on this border."
	end
	CreateLoopingDropdown(category, playerFrameSetting, GetPlayerFrameOptions, playerFrameTooltip)

	local GetFrameThemeOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		container:Add("light", "Light")
		container:Add("dark", "Dark")
		return container:GetData()
	end)
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

	local GetHideNameOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		container:Add("auto", "Auto")
		container:Add("always", "Always")
		container:Add("never", "Never")
		return container:GetData()
	end)
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

	local GetNameBackgroundOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		container:Add("player", "Player")
		container:Add("target", "Target")
		container:Add("both", "Both")
		container:Add("none", "None")
		return container:GetData()
	end)
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

	local GetPortraitModeOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		container:Add("normal", "Normal")
		container:Add("class", "Class icon")
		return container:GetData()
	end)
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

	local GetClassColorOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		container:Add("all", "All")
		container:Add("player", "Player")
		container:Add("target", "Target")
		container:Add("none", "None")
		container:Add("chromatic", "Chromatic")
		return container:GetData()
	end)

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

	local GetNpcColorOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		container:Add("hostility", "Hostility")
		container:Add("blizzard", "Blizzard")
		container:Add("chromatic", "Chromatic")
		return container:GetData()
	end)

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
					local swatch = control.ColorSwatch
					StyleHealthColorSwatch(swatch)
					-- Stock Color defaults to highlight white; re-apply after reshape so the
					-- swatch shows healthBarColor (not the template / border yellow cue).
					local c = self:GetHealthBarCustomColor()
					if swatch and swatch.SetColorRGB and c then
						swatch:SetColorRGB(c.r, c.g, c.b)
					end
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
	AttachParent(customPlayerOnlyInitializer, customHealthInitializer, function()
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
	AttachParent(cycleSpeedInitializer, npcColorInitializer, function()
		return classSetting:GetValue() == "chromatic" or npcColorSetting:GetValue() == "chromatic"
	end)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Bars & Numbers"))

	local GetStatusBarTextureOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		local keys, labels = self:GetStatusBarTextureOptions()
		for _, key in ipairs(keys) do
			container:Add(key, labels[key] or key)
		end
		return container:GetData()
	end)

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

		local GetStatusTextOptions = MemoizeOptions(function()
			local container = Settings.CreateControlTextContainer()
			container:Add(1, STATUS_TEXT_VALUE)
			container:Add(2, STATUS_TEXT_PERCENT)
			container:Add(3, STATUS_TEXT_BOTH)
			container:Add(4, NONE)
			return container:GetData()
		end)

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
			"How health and mana numbers appear on the bars. Retail uses Blizzard secret-safe formatters (percent via Unit*Percent; values follow Number abbreviation, default Full/regional)."
		)
	end

	local GetStatusBarFontOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		local keys, labels = self:GetStatusBarFontOptions()
		for _, key in ipairs(keys) do
			container:Add(key, labels[key] or key)
		end
		return container:GetData()
	end)

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
			if value == "full" or value == "whoa" or value == "large" or value == "numbers" then
				return value
			end
			return defaultNumberAbbreviation
		end
		db.numberAbbreviation = NormalizeNumberAbbreviation(db.numberAbbreviation)

		local GetNumberAbbreviationOptions = MemoizeOptions(function()
			local container = Settings.CreateControlTextContainer()
			container:Add("full", "Full (regional)")
			container:Add("whoa", "Whoa")
			container:Add("numbers", "Compact (1.2K)")
			container:Add("large", "Large (Blizzard)")
			return container:GetData()
		end)

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
		local tooltip = "How health and power values are shown. Full uses the client formatter (BreakUpLargeNumbers) with locale separators and no K/M. Whoa is the Classic Whoa style (e.g. 12.345, 100 K, 1.25 M). Compact and Large use Blizzard abbreviators."
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

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Combat"))

	local function NormalizeCombatFeedbackColors(value)
		if value == "school" then
			return "school"
		end
		return "default"
	end
	db.combatFeedbackColors = NormalizeCombatFeedbackColors(db.combatFeedbackColors)

	local GetCombatFeedbackColorsOptions = MemoizeOptions(function()
		local container = Settings.CreateControlTextContainer()
		container:Add("default", "Default")
		container:Add("school", "School")
		return container:GetData()
	end)
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
			text = "Reset the active Whoa Unit Frames profile to shipping defaults?\n\nOther named profiles are kept. Edit Mode layout positions and Blizzard health/mana text are unchanged.",
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
		"Restore the active profile to shipping defaults. Other named profiles are unchanged. Does not move Edit Mode frames or change Blizzard status text.",
		true
	))

	-- Enable / force-show live in DevTools (/whoadev via RegisterDevToolsProvider), not Settings.

	Settings.RegisterAddOnCategory(category)
	self.settingsCategory = category
end
