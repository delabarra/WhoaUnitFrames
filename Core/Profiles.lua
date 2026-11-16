--[[
	Named settings profiles + per-character selection.

	Active options stay on WhoaUFDB root (Settings binds to that stable table).
	Named snapshots live in WhoaUFDB.profiles; WhoaUFDB.charProfiles picks which
	profile each character loads. New characters start on "Default".

	DK specialty lock: named profiles saved with Alpha / BlizzCon player art are
	locked (profileLock = "dk") and renamed with a " (DK)" suffix. Only Death
	Knights — and Forever warriors — may load them.
]]

local DEFAULT_PROFILE_NAME = "Default"
local PROFILES_VERSION = 1
-- Room for Forever "First Last" plus optional " (DK)".
local MAX_PROFILE_NAME_LEN = 48
local DK_LOCK = "dk"
local DK_NAME_SUFFIX = " (DK)"

-- Root keys that are account/meta — never copied into profile snapshots.
local META_KEYS = {
	profiles = true,
	charProfiles = true,
	activeProfile = true,
	profilesVersion = true,
	testingNoticeAccepted = true,
	numberAbbreviationMainline = true,
	numberAbbreviationFullDefault = true,
}

-- Keys stored on the profile snapshot only (never applied onto WhoaUFDB root).
local PROFILE_ONLY_KEYS = {
	profileLock = true,
}

-- Retired options (profiles superseded per-character colors).
local RETIRED_KEYS = {
	colorsLocal = true,
	charColors = true,
}

local function DeepCopy(src)
	if type(src) ~= "table" then
		return src
	end
	local dest = {}
	for key, value in pairs(src) do
		if type(value) == "table" then
			dest[key] = DeepCopy(value)
		else
			dest[key] = value
		end
	end
	return dest
end

local function WipeProfileKeys(db)
	local remove = {}
	for key in pairs(db) do
		if not META_KEYS[key] then
			remove[#remove + 1] = key
		end
	end
	for i = 1, #remove do
		db[remove[i]] = nil
	end
end

local function HasDkSpecialtyArt(options)
	local art = options and options.dkPlayerArt
	return art == "alpha" or art == "blizzcon" or art == true
end

local function ProfileNameHasDkSuffix(name)
	return type(name) == "string" and name:sub(-#DK_NAME_SUFFIX) == DK_NAME_SUFFIX
end

local function EnsureDkProfileName(name)
	if ProfileNameHasDkSuffix(name) then
		return name
	end
	local maxBase = MAX_PROFILE_NAME_LEN - #DK_NAME_SUFFIX
	if #name > maxBase then
		name = name:sub(1, maxBase)
		name = name:match("^(.-)%s*$") or name
	end
	return name .. DK_NAME_SUFFIX
end

local function SnapshotTableAsProfile(src)
	local snap = {}
	if type(src) ~= "table" then
		return snap
	end
	for key, value in pairs(src) do
		if not META_KEYS[key] and not PROFILE_ONLY_KEYS[key] and not RETIRED_KEYS[key] then
			if type(value) == "table" then
				snap[key] = DeepCopy(value)
			else
				snap[key] = value
			end
		end
	end
	return snap
end

local function SnapshotActiveOptions(db)
	return SnapshotTableAsProfile(db)
end

local function ApplySnapshotToActive(db, snap)
	WipeProfileKeys(db)
	if type(snap) ~= "table" then
		return
	end
	for key, value in pairs(snap) do
		if not PROFILE_ONLY_KEYS[key] and not RETIRED_KEYS[key] then
			if type(value) == "table" then
				db[key] = DeepCopy(value)
			else
				db[key] = value
			end
		end
	end
	db.colorsLocal = nil
	db.charColors = nil
end

local function TrimProfileName(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:match("^%s*(.-)%s*$")
	if not name or name == "" then
		return nil
	end
	if #name > MAX_PROFILE_NAME_LEN then
		name = name:sub(1, MAX_PROFILE_NAME_LEN)
	end
	return name
end

local function GetPlayerProfileKey()
	local name, realm = UnitFullName("player")
	realm = realm or GetRealmName()
	if not name or name == "" then
		return nil
	end
	return name .. "-" .. (realm or "")
end

--- Finalize lock + optional (DK) rename. Default is never class-locked.
local function StoreProfileSnapshot(db, name, snap)
	db.profiles = db.profiles or {}
	snap = snap or {}
	if name ~= DEFAULT_PROFILE_NAME and HasDkSpecialtyArt(snap) then
		snap.profileLock = DK_LOCK
		local renamed = EnsureDkProfileName(name)
		if renamed ~= name then
			-- Move char / active pointers off the unsuffixed key.
			if db.activeProfile == name then
				db.activeProfile = renamed
			end
			if type(db.charProfiles) == "table" then
				for charKey, profileName in pairs(db.charProfiles) do
					if profileName == name then
						db.charProfiles[charKey] = renamed
					end
				end
			end
			db.profiles[name] = nil
			name = renamed
		end
	else
		snap.profileLock = nil
	end
	db.profiles[name] = snap
	return name
end

local function IsDkLockedSnap(snap)
	if type(snap) ~= "table" then
		return false
	end
	if snap.profileLock == DK_LOCK then
		return true
	end
	-- Treat specialty art as locked even before profileLock was stamped.
	return HasDkSpecialtyArt(snap)
end

function WhoaUF:GetDefaultProfileName()
	return DEFAULT_PROFILE_NAME
end

function WhoaUF:IsDefaultProfileName(name)
	return TrimProfileName(name) == DEFAULT_PROFILE_NAME
end

--- Suggested save name: character name; Forever includes surname ("First Last").
function WhoaUF:GetSuggestedProfileName()
	local suggested
	if self.IsCamelot and self:IsCamelot() and self.GetUnitDisplayName then
		-- Forever: GetUnitDisplayName joins first + surname (not realm).
		suggested = self:GetUnitDisplayName("player", true)
	else
		suggested = UnitName("player")
	end
	if self.CanAccessValue and not self:CanAccessValue(suggested) then
		suggested = nil
	end
	suggested = TrimProfileName(suggested)
	if not suggested then
		return "Character"
	end
	return suggested
end

function WhoaUF:CanLoadProfile(name)
	name = TrimProfileName(name) or DEFAULT_PROFILE_NAME
	if name == DEFAULT_PROFILE_NAME then
		return true
	end
	local db = self.db
	local snap = db and db.profiles and db.profiles[name]
	if not snap then
		return false
	end
	if not IsDkLockedSnap(snap) then
		return true
	end
	return self.IsDkSpecialtyPlayerArtEligible and self:IsDkSpecialtyPlayerArtEligible() and true or false
end

function WhoaUF:GetActiveProfileName()
	local db = self.db
	if not db then
		return DEFAULT_PROFILE_NAME
	end
	local name = TrimProfileName(db.activeProfile)
	if not name or not db.profiles or not db.profiles[name] then
		return DEFAULT_PROFILE_NAME
	end
	return name
end

--- Names this character may select (DK-locked profiles hidden for other classes).
function WhoaUF:GetProfileNames()
	local db = self.db
	local names = { DEFAULT_PROFILE_NAME }
	if not db or type(db.profiles) ~= "table" then
		return names
	end
	local extras = {}
	for name in pairs(db.profiles) do
		if name ~= DEFAULT_PROFILE_NAME and self:CanLoadProfile(name) then
			extras[#extras + 1] = name
		end
	end
	table.sort(extras)
	for i = 1, #extras do
		names[#names + 1] = extras[i]
	end
	return names
end

function WhoaUF:ProfileExists(name)
	name = TrimProfileName(name)
	local db = self.db
	return name and db and type(db.profiles) == "table" and db.profiles[name] ~= nil
end

local function ValuesEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in pairs(a) do
		if PROFILE_ONLY_KEYS[key] or RETIRED_KEYS[key] then
			-- skip
		elseif not ValuesEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if not PROFILE_ONLY_KEYS[key] and not RETIRED_KEYS[key] and a[key] == nil then
			return false
		end
	end
	return true
end

function WhoaUF:IsProfileDirty()
	local db = self.db
	if not db or type(db.profiles) ~= "table" then
		return false
	end
	local active = self:GetActiveProfileName()
	local stored = db.profiles[active]
	if type(stored) ~= "table" then
		return active ~= DEFAULT_PROFILE_NAME
	end
	return not ValuesEqual(SnapshotActiveOptions(db), stored)
end

--- Persist live options into the current profile (or character name when on Default).
function WhoaUF:SaveCurrentProfileChanges()
	local active = self:GetActiveProfileName()
	if active == DEFAULT_PROFILE_NAME then
		local suggested = self:GetSuggestedProfileName()
		local panel = self._profilesPanel
		local typed = panel and panel.NameBox and panel.NameBox:GetText()
		typed = TrimProfileName(typed)
		local name = typed or suggested
		if not name or name == DEFAULT_PROFILE_NAME then
			name = suggested
		end
		return self:SaveProfileAs(name)
	end
	return self:SyncActiveToProfile(active), nil
end

local function LiveOptionsMatchProfile(db, name)
	if not db or type(db.profiles) ~= "table" or type(name) ~= "string" then
		return false
	end
	local stored = db.profiles[name]
	if type(stored) ~= "table" then
		return false
	end
	return ValuesEqual(SnapshotActiveOptions(db), stored)
end

local function LiveOptionsMatchAnyProfile(db)
	if not db or type(db.profiles) ~= "table" then
		return false
	end
	local live = SnapshotActiveOptions(db)
	for _, stored in pairs(db.profiles) do
		if type(stored) == "table" and ValuesEqual(live, stored) then
			return true
		end
	end
	return false
end

local function RefreshProfilesPanelIfShown()
	local panel = WhoaUF._profilesPanel
	if panel and panel.Refresh then
		panel:Refresh()
	end
end

local function ClearPendingProfileSwitch()
	WhoaUF._pendingSwitchProfile = nil
end

local function UnsavedPopup_SaveAndSwitch()
	local target = WhoaUF._pendingSwitchProfile
	ClearPendingProfileSwitch()
	if not target then
		return
	end
	if WhoaUF:SaveCurrentProfileChanges() then
		WhoaUF:SetActiveProfile(target, { discard = true })
	end
	RefreshProfilesPanelIfShown()
end

local function UnsavedPopup_DiscardAndSwitch()
	local target = WhoaUF._pendingSwitchProfile
	ClearPendingProfileSwitch()
	if target then
		WhoaUF:SetActiveProfile(target, { discard = true })
	end
	RefreshProfilesPanelIfShown()
end

local function UnsavedPopup_CancelSwitch()
	ClearPendingProfileSwitch()
	RefreshProfilesPanelIfShown()
end

local function UnsavedPopup_OnHide()
	-- Escape / close without a choice cancels the pending switch.
	if WhoaUF._pendingSwitchProfile then
		UnsavedPopup_CancelSwitch()
	end
end

--- Two fixed dialogs so button3 is never toggled away (avoids missing Cancel).
local function EnsureUnsavedPopups()
	if not StaticPopupDialogs["WHOAUF_PROFILE_UNSAVED"] then
		-- Save | Discard | Cancel (Cancel was previously middle via button2/button3 swap).
		StaticPopupDialogs["WHOAUF_PROFILE_UNSAVED"] = {
			text = "You have unsaved changes to \"%s\".\n\nSave them, discard them, or cancel switching profiles?",
			button1 = SAVE,
			button2 = "Discard",
			button3 = CANCEL,
			OnAccept = UnsavedPopup_SaveAndSwitch,
			OnCancel = UnsavedPopup_DiscardAndSwitch,
			OnAlt = UnsavedPopup_CancelSwitch,
			OnHide = UnsavedPopup_OnHide,
			-- Discard is button2; Escape must not discard — OnHide cancels instead.
			noCancelOnEscape = 1,
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
			preferredIndex = 3,
		}
	end
	if not StaticPopupDialogs["WHOAUF_PROFILE_UNSAVED_NOSAVE"] then
		-- Discard | Cancel — used when live options already match some profile.
		StaticPopupDialogs["WHOAUF_PROFILE_UNSAVED_NOSAVE"] = {
			text = "You have unsaved changes to \"%s\".\n\nDiscard them, or cancel switching profiles?",
			button1 = "Discard",
			button2 = CANCEL,
			OnAccept = UnsavedPopup_DiscardAndSwitch,
			OnCancel = UnsavedPopup_CancelSwitch,
			OnHide = UnsavedPopup_OnHide,
			timeout = 0,
			whileDead = 1,
			hideOnEscape = 1,
			preferredIndex = 3,
		}
	end
end

--- Switch profile, prompting when the current one is dirty.
function WhoaUF:RequestActiveProfile(name)
	name = TrimProfileName(name)
	if not name then
		return false
	end
	if name == self:GetActiveProfileName() then
		return true
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
		return false
	end
	if not self:ProfileExists(name) then
		return false
	end
	if not self:CanLoadProfile(name) then
		UIErrorsFrame:AddMessage(
			"That profile is locked to Death Knights (Forever warriors allowed).",
			1.0,
			0.1,
			0.1
		)
		return false
	end
	if self:IsProfileDirty() then
		-- Already matches the profile being clicked — just switch (nothing to save/discard).
		if LiveOptionsMatchProfile(self.db, name) then
			return self:SetActiveProfile(name, { discard = true })
		end
		EnsureUnsavedPopups()
		self._pendingSwitchProfile = name
		-- Save only when live options are not already identical to some stored profile.
		local which = LiveOptionsMatchAnyProfile(self.db) and "WHOAUF_PROFILE_UNSAVED_NOSAVE"
			or "WHOAUF_PROFILE_UNSAVED"
		StaticPopup_Show(which, self:GetActiveProfileName())
		return false
	end
	return self:SetActiveProfile(name, { discard = true })
end

--- Replace the read-only Default template from the current root (Reset only).
function WhoaUF:ReplaceDefaultProfileTemplate()
	local db = self.db
	if not db then
		return false
	end
	db.profiles = db.profiles or {}
	local snap = SnapshotActiveOptions(db)
	snap.profileLock = nil
	db.profiles[DEFAULT_PROFILE_NAME] = snap
	db.activeProfile = DEFAULT_PROFILE_NAME
	return true
end

--- Write current root options into profiles[name] (create if missing).
--- Default is read-only — never overwritten by sync.
function WhoaUF:SyncActiveToProfile(name)
	local db = self.db
	if not db then
		return false
	end
	name = TrimProfileName(name) or self:GetActiveProfileName()
	if name == DEFAULT_PROFILE_NAME then
		db.activeProfile = DEFAULT_PROFILE_NAME
		return true
	end
	db.profiles = db.profiles or {}
	local snap = SnapshotActiveOptions(db)
	name = StoreProfileSnapshot(db, name, snap)
	db.activeProfile = name
	return true
end

local function RefreshSettingsFromDb(self)
	local vars = self._optionSettingVariables
	if not vars or not Settings or not Settings.NotifyUpdate then
		return
	end
	for i = 1, #vars do
		Settings.NotifyUpdate(vars[i])
	end
end

--- Copy a named profile into the active root table and re-apply visuals.
function WhoaUF:LoadProfile(name, opts)
	local db = self.db
	if not db then
		return false
	end
	opts = opts or {}
	name = TrimProfileName(name) or DEFAULT_PROFILE_NAME
	db.profiles = db.profiles or {}
	if not db.profiles[name] then
		if name ~= DEFAULT_PROFILE_NAME then
			return false
		end
		-- Seed Default from shipping defaults (option keys only).
		local defaults = self.GetOptionDefaults and self:GetOptionDefaults() or {}
		db.profiles[name] = SnapshotTableAsProfile(defaults)
	end

	if not opts.skipLockCheck and not self:CanLoadProfile(name) then
		return false
	end

	local previousLock = db.profiles[name] and db.profiles[name].profileLock
	ApplySnapshotToActive(db, db.profiles[name])
	db.activeProfile = name

	if self.MigrateFrameStyleOptions then
		self:MigrateFrameStyleOptions(db)
	end
	-- Keep the profile snapshot aligned after migrations / CopyDefaults fill-ins.
	if self.GetOptionDefaults then
		local defaults = self:GetOptionDefaults()
		for key, value in pairs(defaults) do
			if not META_KEYS[key] and not PROFILE_ONLY_KEYS[key] and db[key] == nil then
				if type(value) == "table" then
					db[key] = DeepCopy(value)
				else
					db[key] = value
				end
			end
		end
	end
	-- Default is read-only: never write live options back into the Default snapshot.
	if name ~= DEFAULT_PROFILE_NAME then
		local snap = SnapshotActiveOptions(db)
		if previousLock == DK_LOCK and HasDkSpecialtyArt(snap) then
			snap.profileLock = DK_LOCK
		end
		name = StoreProfileSnapshot(db, name, snap)
		db.activeProfile = name
	end

	local charKey = GetPlayerProfileKey()
	if charKey then
		db.charProfiles = db.charProfiles or {}
		db.charProfiles[charKey] = name
	end

	if not opts.skipApply then
		if self.ApplyAllOptions then
			self:ApplyAllOptions()
		end
		RefreshSettingsFromDb(self)
	end
	return true
end

--- opts.discard: load without writing the profile being left (unsaved discard).
function WhoaUF:SetActiveProfile(name, opts)
	local db = self.db
	if not db then
		return false
	end
	opts = opts or {}
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
		return false
	end
	name = TrimProfileName(name)
	if not name then
		return false
	end
	if name == self:GetActiveProfileName() then
		return true
	end
	if not self:ProfileExists(name) then
		return false
	end
	if not self:CanLoadProfile(name) then
		UIErrorsFrame:AddMessage(
			"That profile is locked to Death Knights (Forever warriors allowed).",
			1.0,
			0.1,
			0.1
		)
		return false
	end
	if not opts.discard then
		self:SyncActiveToProfile(self:GetActiveProfileName())
	end
	return self:LoadProfile(name)
end

--- Create or overwrite a named profile from the current active options and switch to it.
--- Default is read-only. Profiles with Alpha / BlizzCon art are saved as "Name (DK)".
function WhoaUF:SaveProfileAs(name)
	local db = self.db
	if not db then
		return false, "no_db"
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
		return false, "combat"
	end
	name = TrimProfileName(name)
	if not name then
		return false, "empty"
	end
	if name == DEFAULT_PROFILE_NAME then
		return false, "reserved"
	end

	local needsDkLock = HasDkSpecialtyArt(db)
	if needsDkLock then
		name = EnsureDkProfileName(name)
	end

	db.profiles = db.profiles or {}
	-- Leaving Default does not sync into it (read-only). Other actives sync first.
	local previous = self:GetActiveProfileName()
	if previous ~= DEFAULT_PROFILE_NAME and previous ~= name then
		self:SyncActiveToProfile(previous)
	end
	local snap = SnapshotActiveOptions(db)
	name = StoreProfileSnapshot(db, name, snap)
	return self:LoadProfile(name) and true or false, nil
end

--- Rename a named profile. Default cannot be renamed. DK-locked profiles keep the " (DK)" suffix.
function WhoaUF:RenameProfile(oldName, newName)
	local db = self.db
	if not db then
		return false, "no_db"
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
		return false, "combat"
	end
	oldName = TrimProfileName(oldName)
	newName = TrimProfileName(newName)
	if not oldName or not newName then
		return false, "empty"
	end
	if oldName == DEFAULT_PROFILE_NAME or newName == DEFAULT_PROFILE_NAME then
		return false, "reserved"
	end
	db.profiles = db.profiles or {}
	local snap = db.profiles[oldName]
	if type(snap) ~= "table" then
		return false, "missing"
	end

	-- Preserve DK lock naming when the snapshot (or live art) requires it.
	if IsDkLockedSnap(snap) or HasDkSpecialtyArt(snap) then
		newName = EnsureDkProfileName(newName)
	end

	if newName == oldName then
		return true, nil
	end
	if db.profiles[newName] then
		return false, "exists"
	end

	db.profiles[oldName] = nil
	newName = StoreProfileSnapshot(db, newName, snap)

	if db.activeProfile == oldName then
		db.activeProfile = newName
	end
	if type(db.charProfiles) == "table" then
		for charKey, profileName in pairs(db.charProfiles) do
			if profileName == oldName then
				db.charProfiles[charKey] = newName
			end
		end
	end

	return true, nil
end

function WhoaUF:DeleteProfile(name)
	local db = self.db
	if not db then
		return false, "no_db"
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1)
		return false, "combat"
	end
	name = TrimProfileName(name)
	if not name then
		return false, "empty"
	end
	if name == DEFAULT_PROFILE_NAME then
		return false, "reserved"
	end
	db.profiles = db.profiles or {}
	if not db.profiles[name] then
		return false, "missing"
	end

	local wasActive = self:GetActiveProfileName() == name
	db.profiles[name] = nil

	-- Point any characters still on this profile back to Default.
	if type(db.charProfiles) == "table" then
		for charKey, profileName in pairs(db.charProfiles) do
			if profileName == name then
				db.charProfiles[charKey] = DEFAULT_PROFILE_NAME
			end
		end
	end

	if wasActive then
		return self:LoadProfile(DEFAULT_PROFILE_NAME) and true or false, nil
	end
	return true, nil
end

function WhoaUF:GetCharProfileName()
	local db = self.db
	if not db then
		return DEFAULT_PROFILE_NAME
	end
	local charKey = GetPlayerProfileKey()
	local name = charKey and db.charProfiles and db.charProfiles[charKey]
	name = TrimProfileName(name)
	if name and db.profiles and db.profiles[name] and self:CanLoadProfile(name) then
		return name
	end
	return DEFAULT_PROFILE_NAME
end

--- One-time migrate flat WhoaUFDB → profiles + per-character selection.
function WhoaUF:InitProfiles()
	local db = self.db
	if not db then
		return
	end

	db.profiles = type(db.profiles) == "table" and db.profiles or {}
	db.charProfiles = type(db.charProfiles) == "table" and db.charProfiles or {}

	if db.profilesVersion ~= PROFILES_VERSION then
		-- Existing installs: current root options become Default.
		if not db.profiles[DEFAULT_PROFILE_NAME] then
			db.profiles[DEFAULT_PROFILE_NAME] = SnapshotActiveOptions(db)
		end
		db.profilesVersion = PROFILES_VERSION
	end

	if not db.profiles[DEFAULT_PROFILE_NAME] then
		local defaults = self.GetOptionDefaults and self:GetOptionDefaults() or {}
		db.profiles[DEFAULT_PROFILE_NAME] = SnapshotTableAsProfile(defaults)
	end

	-- Stamp locks / (DK) suffixes on any named profiles that already have specialty art.
	local renamePass = {}
	for name, snap in pairs(db.profiles) do
		if name ~= DEFAULT_PROFILE_NAME and type(snap) == "table" and IsDkLockedSnap(snap) then
			renamePass[#renamePass + 1] = name
		end
	end
	for i = 1, #renamePass do
		local name = renamePass[i]
		local snap = db.profiles[name]
		if snap then
			StoreProfileSnapshot(db, name, snap)
		end
	end

	local lastActive = TrimProfileName(db.activeProfile) or DEFAULT_PROFILE_NAME
	if not db.profiles[lastActive] then
		lastActive = DEFAULT_PROFILE_NAME
	end
	-- Fold last session's root into the active named profile. Default stays read-only.
	if lastActive == DEFAULT_PROFILE_NAME then
		db.activeProfile = DEFAULT_PROFILE_NAME
	else
		lastActive = StoreProfileSnapshot(db, lastActive, SnapshotActiveOptions(db))
		db.activeProfile = lastActive
	end

	local want = self:GetCharProfileName()
	if want ~= lastActive then
		self:LoadProfile(want, { skipApply = true })
	else
		if not self:CanLoadProfile(want) then
			want = DEFAULT_PROFILE_NAME
			self:LoadProfile(want, { skipApply = true })
		else
			local charKey = GetPlayerProfileKey()
			if charKey then
				db.charProfiles[charKey] = want
			end
		end
	end

	if not self._profileLogoutFrame then
		local frame = CreateFrame("Frame")
		frame:RegisterEvent("PLAYER_LOGOUT")
		frame:SetScript("OnEvent", function()
			if not (WhoaUF and WhoaUF.db) then
				return
			end
			local active = WhoaUF:GetActiveProfileName()
			if active == DEFAULT_PROFILE_NAME then
				-- Keep Default pristine; persist working options under the character name.
				local suggested = WhoaUF:GetSuggestedProfileName()
				if suggested and suggested ~= DEFAULT_PROFILE_NAME then
					local snap = SnapshotActiveOptions(WhoaUF.db)
					suggested = StoreProfileSnapshot(WhoaUF.db, suggested, snap)
					WhoaUF.db.activeProfile = suggested
					local charKey = GetPlayerProfileKey()
					if charKey then
						WhoaUF.db.charProfiles = WhoaUF.db.charProfiles or {}
						WhoaUF.db.charProfiles[charKey] = suggested
					end
				end
			elseif WhoaUF.SyncActiveToProfile then
				WhoaUF:SyncActiveToProfile(active)
			end
		end)
		self._profileLogoutFrame = frame
	end
end
