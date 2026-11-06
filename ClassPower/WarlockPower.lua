--[[
	MoP Warlock Demonic Fury + Burning Embers on Whoa player frame.
	Affliction shards stay in ShardBar.lua. Stock WarlockPowerFrame is muted in Blizzard_*.lua.
	Reference: reference/Blizzard_UnitFrame/Mists/ShardBar.lua|.xml
]]

do
	if not WhoaUF:HasMoPWarlockPower() then
		return
	end
	local _, playerClass = UnitClass("player")
	if playerClass ~= "WARLOCK" then
		return
	end
end

local WARLOCK_METAMORPHOSIS = WARLOCK_METAMORPHOSIS or 103958
local WARLOCK_BURNING_EMBERS = WARLOCK_BURNING_EMBERS or 108647
local WARLOCK_GREEN_FIRE = WARLOCK_GREEN_FIRE or 101508
local MAX_POWER_PER_EMBER = MAX_POWER_PER_EMBER or 10
local MAX_EMBERS_UI = 4

local TEX_DESTRO = "Interface\\PlayerFrame\\Warlock-DestructionUI"
local TEX_DESTRO_GREEN = "Interface\\PlayerFrame\\Warlock-DestructionUI-Green"
local TEX_DEMO = "Interface\\PlayerFrame\\Warlock-DemonologyUI"

local FILL = {
	Demonology = { left = 0.03906250, right = 0.55468750, top = 0.10546875, bottom = 0.19921875, width = 132, fileWidth = 256 },
	DemonologyActivated = { left = 0.03906250, right = 0.55468750, top = 0.00390625, bottom = 0.09765625, width = 132, fileWidth = 256 },
	Destruction = { left = 0.30078125, right = 0.37890625, top = 0.32812500, bottom = 0.67187500, height = 22, fileHeight = 64 },
}

local function HasMoPWarlockPower()
	return WhoaUF:HasMoPWarlockPower()
end

local function GetSpec()
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		return C_SpecializationInfo.GetSpecialization()
	end
	if GetSpecialization then
		return GetSpecialization()
	end
	return nil
end

local function IsWarlock()
	local _, class = UnitClass("player")
	return class == "WARLOCK"
end

local function IsSpellKnownSafe(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		return C_SpellBook.IsSpellKnown(id)
	end
	if IsPlayerSpell then
		return IsPlayerSpell(id)
	end
	if IsSpellKnown then
		return IsSpellKnown(id)
	end
	return true
end

local function HasAura(spellID)
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		return C_UnitAuras.GetPlayerAuraBySpellID(spellID) and true or false
	end
	return false
end

local function ResolveClassPowerTex(clientPath)
	if WhoaUF.GetClassPowerTexture then
		return WhoaUF:GetClassPowerTexture(clientPath)
	end
	return clientPath
end

local function UpdateFill(texture, texData, value, maxValue)
	if value <= 0 or maxValue <= 0 then
		texture:Hide()
		return
	end
	if value >= maxValue then
		texture:SetTexCoord(texData.left, texData.right, texData.top, texData.bottom)
		if texData.width then
			texture:SetWidth(texData.width)
		else
			texture:SetHeight(texData.height)
		end
		texture:Show()
		return
	end
	if texData.width then
		local texWidth = (value / maxValue) * texData.width
		local right = texData.left + texWidth / texData.fileWidth
		texture:SetTexCoord(texData.left, right, texData.top, texData.bottom)
		texture:SetWidth(texWidth)
	else
		local texHeight = (value / maxValue) * texData.height
		local top = texData.bottom - texHeight / texData.fileHeight
		texture:SetTexCoord(texData.left, texData.right, top, texData.bottom)
		texture:SetHeight(texHeight)
	end
	texture:Show()
end

local function SmoothPower(value, displayed, range, elapsed)
	if GetSmoothProgressChange then
		return GetSmoothProgressChange(value, displayed, range, elapsed)
	end
	return value
end

function WhoaUF:GetWarlockPowerAnchor()
	-- Mists ShardBar.xml WarlockPowerFrame: TOP→BOTTOM (32, 30). Demo/Destro child bars
	-- nest inside with TOPLEFT (-28, 15) / (-21, 1).
	return 32, 30
end

local function SetDemonicFuryPower(self, power)
	self.displayedPower = power
	local texData = self.activated and FILL.DemonologyActivated or FILL.Demonology
	if self.activated then
		self.bar:SetTexCoord(0.03906250, 0.69921875, 0.30859375, 0.51171875)
	else
		self.bar:SetTexCoord(0.03906250, 0.69921875, 0.51953125, 0.72265625)
	end
	UpdateFill(self.fill, texData, power, self.maxPower)
	if self.powerText then
		self.powerText:SetText(math.floor(power) .. " / " .. math.floor(self.maxPower))
	end
end

local function UpdateDemonicFury(self, forceUpdate)
	local powerType = (Enum and Enum.PowerType and Enum.PowerType.DemonicFury) or 15
	local power, maxPower
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("WARLOCK") then
		maxPower = 1000
		power = 1000
		self.activated = true
	else
		power = UnitPower("player", powerType) or 0
		maxPower = UnitPowerMax and UnitPowerMax("player", powerType) or 1
		self.activated = HasAura(WARLOCK_METAMORPHOSIS)
	end
	if maxPower < 1 then
		maxPower = 1
	end
	self.power = power
	self.maxPower = maxPower
	if forceUpdate then
		SetDemonicFuryPower(self, power)
	end
end

local function SetEmberActive(ember, active, instant)
	if active then
		if ember.animOut:IsPlaying() then
			ember.animOut:Stop()
		end
		if instant then
			ember.animIn:Stop()
			ember.glow:SetAlpha(0)
			ember.glow2:SetAlpha(0)
			ember.fire:Show()
			ember.active = true
		elseif not ember.active and not ember.animIn:IsPlaying() then
			if ember.animIn.Restart then
				ember.animIn:Restart()
			else
				ember.animIn:Play()
			end
			ember.active = true
			ember.fire:Show()
		end
	else
		if ember.animIn:IsPlaying() then
			ember.animIn:Stop()
		end
		if instant then
			ember.animOut:Stop()
			ember.glow:SetAlpha(0)
			ember.glow2:SetAlpha(0)
			ember.fire:Hide()
			ember.active = false
		elseif ember.active and not ember.animOut:IsPlaying() then
			if ember.animOut.Restart then
				ember.animOut:Restart()
			else
				ember.animOut:Play()
			end
			ember.active = false
			ember.fire:Hide()
		end
	end
end

-- BurningEmbersBarMixin:SetPower — remainder power rolls into the next ember.
local function SetBurningEmbersPower(self, power, instant)
	self.displayedPower = power
	local remaining = power
	local emberCount = self.emberCount or MAX_EMBERS_UI
	for i = 1, MAX_EMBERS_UI do
		local ember = self.embers[i]
		if not ember then
			break
		end
		if i <= emberCount then
			ember:Show()
			UpdateFill(ember.fill, FILL.Destruction, remaining, MAX_POWER_PER_EMBER)
			SetEmberActive(ember, remaining >= MAX_POWER_PER_EMBER, instant)
			remaining = remaining - MAX_POWER_PER_EMBER
		else
			SetEmberActive(ember, false, true)
			ember:Hide()
		end
	end
end

local function UpdateBurningEmbers(self, forceUpdate)
	local powerType = (Enum and Enum.PowerType and Enum.PowerType.BurningEmbers) or 14
	local power, maxPower
	if WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("WARLOCK") then
		maxPower = MAX_POWER_PER_EMBER * MAX_EMBERS_UI
		power = maxPower
	else
		power = UnitPower("player", powerType, true) or 0
		maxPower = UnitPowerMax and UnitPowerMax("player", powerType, true) or (MAX_POWER_PER_EMBER * MAX_EMBERS_UI)
	end
	if maxPower < 1 then
		maxPower = MAX_POWER_PER_EMBER
	end
	self.emberCount = math.floor(maxPower / MAX_POWER_PER_EMBER)
	if self.emberCount < 1 then
		self.emberCount = 1
	elseif self.emberCount > MAX_EMBERS_UI then
		self.emberCount = MAX_EMBERS_UI
	end
	self.power = power
	self.maxPower = maxPower
	if forceUpdate then
		SetBurningEmbersPower(self, power, true)
	end
end

local function GetDestructionClientTex()
	if IsSpellKnownSafe(WARLOCK_GREEN_FIRE) then
		return TEX_DESTRO_GREEN
	end
	return TEX_DESTRO
end

local function ApplyEmberTextures(embers, clientPath)
	local file = ResolveClassPowerTex(clientPath)
	if file == embers.emberFile then
		return
	end
	embers.emberClientPath = clientPath
	embers.emberFile = file
	if embers.background then
		embers.background:SetTexture(file)
	end
	for i = 1, MAX_EMBERS_UI do
		local ember = embers.embers[i]
		if ember then
			ember.border:SetTexture(file)
			ember.fill:SetTexture(file)
			ember.fire:SetTexture(file)
			ember.glow:SetTexture(file)
			ember.glow2:SetTexture(file)
		end
	end
end

local function SyncDestructionTextures(embers)
	ApplyEmberTextures(embers, GetDestructionClientTex())
end

local function OnWarlockPowerUpdate(power, elapsed)
	local fury = power.fury
	local embers = power.embers
	if fury and fury:IsShown() and fury.power and fury.displayedPower ~= fury.power then
		SetDemonicFuryPower(fury, SmoothPower(fury.power, fury.displayedPower, fury.maxPower, elapsed))
	end
	if embers and embers:IsShown() and embers.power and embers.displayedPower ~= embers.power then
		SetBurningEmbersPower(embers, SmoothPower(embers.power, embers.displayedPower, embers.maxPower, elapsed), false)
	end
end

local function RefreshWarlockPowerVisibility(player)
	local power = player.WarlockPowerFrame
	local fury = player.DemonicFuryBar
	local embers = player.BurningEmbersBar
	if not (power or fury or embers) then
		return
	end

	local force = WhoaUF.IsForceShowClassPowerFor and WhoaUF:IsForceShowClassPowerFor("WARLOCK")
	local showFury, showEmbers = false, false
	if HasMoPWarlockPower() and IsWarlock() then
		local spec = GetSpec()
		local aff = SPEC_WARLOCK_AFFLICTION or 1
		local demo = SPEC_WARLOCK_DEMONOLOGY or 2
		local destro = SPEC_WARLOCK_DESTRUCTION or 3
		if force then
			if spec == destro then
				showEmbers = true
			elseif spec == aff then
				-- DevTools force-show on Affliction: ShardBar only (no Fury/Embers here).
			else
				-- DevTools force-show on Demo/Destro: show Demonic Fury bar.
				showFury = true
			end
		elseif spec == demo then
			showFury = true
		elseif spec == destro then
			-- Burning Embers is granted at 42. Blizzard still Shows WarlockPowerFrame
			-- earlier (empty slot); Whoa Hides like ShardBar so pet sits flush until
			-- the spell is known (SPELLS_CHANGED).
			if IsSpellKnownSafe(WARLOCK_BURNING_EMBERS) then
				showEmbers = true
			end
		end
	end

	if fury then
		fury:SetShown(showFury)
		if showFury then
			UpdateDemonicFury(fury, true)
		end
	end
	if embers then
		SyncDestructionTextures(embers)
		embers:SetShown(showEmbers)
		if showEmbers then
			UpdateBurningEmbers(embers, true)
		end
	end
	if power then
		local showPower = showFury or showEmbers
		local wasShown = power:IsShown()
		power:SetShown(showPower)
		if showPower and not wasShown and power.showAnim then
			power:SetAlpha(0)
			power.showAnim:Play()
		elseif not showPower then
			power:SetAlpha(1)
		end
		if showFury or showEmbers then
			power:SetScript("OnUpdate", OnWarlockPowerUpdate)
		else
			power:SetScript("OnUpdate", nil)
		end
	end
	if WhoaUF.RefreshShardBar then
		WhoaUF:RefreshShardBar()
	end
	if WhoaUF.LayoutPlayerBottomFrames then
		WhoaUF:LayoutPlayerBottomFrames()
	end
end

function WhoaUF:RefreshWarlockPowerBars()
	local player = self.unitFrames and self.unitFrames.player
	if player then
		RefreshWarlockPowerVisibility(player)
	end
end

function WhoaUF:InitWarlockPowerBars(playerFrame)
	if not playerFrame or playerFrame.WarlockPowerFrame then
		return
	end
	if not HasMoPWarlockPower() then
		return
	end

	-- Match Blizzard WarlockPowerFrame (110x25); Demo/Destro nest with XML offsets.
	local power = CreateFrame("Frame", "WhoaUFWarlockPowerFrame", playerFrame)
	power:SetSize(110, 25)
	power:SetFrameStrata("LOW")
	power:SetFrameLevel(playerFrame:GetFrameLevel() + 5)
	power:Hide()
	playerFrame.WarlockPowerFrame = power

	local showAnim = power:CreateAnimationGroup()
	local showAlpha = showAnim:CreateAnimation("Alpha")
	showAlpha:SetFromAlpha(0)
	showAlpha:SetToAlpha(1)
	showAlpha:SetDuration(0.5)
	showAlpha:SetOrder(1)
	showAnim:SetScript("OnFinished", function(self)
		self:GetParent():SetAlpha(1)
	end)
	power.showAnim = showAnim

	-- Demonic Fury — TOPLEFT (-28, 15) of WarlockPowerFrame
	local fury = CreateFrame("Frame", "WhoaUFDemonicFuryBar", power)
	fury:SetSize(169, 52)
	fury:SetPoint("TOPLEFT", power, "TOPLEFT", -28, 15)
	fury:EnableMouse(true)
	fury:SetHitRectInsets(14, 17, 12, 12)
	fury:Hide()
	fury.displayedPower = 0
	local furyTex = ResolveClassPowerTex(TEX_DEMO)
	fury.bar = fury:CreateTexture(nil, "ARTWORK")
	fury.bar:SetAllPoints()
	fury.bar:SetTexture(furyTex)
	fury.bar:SetTexCoord(0.03906250, 0.69921875, 0.51953125, 0.72265625)
	fury.fill = fury:CreateTexture(nil, "BORDER")
	fury.fill:SetPoint("LEFT", 17, -1)
	fury.fill:SetSize(132, 24)
	fury.fill:SetTexture(furyTex)
	fury.powerText = fury:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	fury.powerText:SetPoint("CENTER", 0, -2)
	if WhoaUF.ApplyStatusBarTextFont then
		WhoaUF:ApplyStatusBarTextFont(fury.powerText)
	end
	fury:SetScript("OnEnter", function(self)
		if GameTooltip_SetDefaultAnchor then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		GameTooltip:SetText(DEMONIC_FURY or "Demonic Fury", 1, 1, 1)
		if DEMONIC_FURY_TOOLTIP then
			GameTooltip:AddLine(DEMONIC_FURY_TOOLTIP, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	fury:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	playerFrame.DemonicFuryBar = fury
	power.fury = fury

	-- Burning Embers — TOPLEFT (-21, 1), size 148x18 (Mists BurningEmbersBarFrame)
	local embers = CreateFrame("Frame", "WhoaUFBurningEmbersBar", power)
	embers:SetSize(148, 18)
	embers:SetPoint("TOPLEFT", power, "TOPLEFT", -21, 1)
	embers:EnableMouse(true)
	embers:SetHitRectInsets(22, 25, 3, -9)
	embers:Hide()
	embers.embers = {}
	embers.displayedPower = 0
	embers.emberCount = MAX_EMBERS_UI

	local emberClient = GetDestructionClientTex()
	local emberFile = ResolveClassPowerTex(emberClient)
	local bg = embers:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(emberFile)
	bg:SetTexCoord(0.00390625, 0.58203125, 0.01562500, 0.29687500)
	embers.background = bg
	embers.emberClientPath = emberClient
	embers.emberFile = emberFile

	for i = 1, MAX_EMBERS_UI do
		local ember = CreateFrame("Frame", "WhoaUFBurningEmber" .. i, embers, "WhoaUFBurningEmberTemplate")
		ember.active = false
		if i == 1 then
			ember:SetPoint("TOPLEFT", 16, 7)
		else
			ember:SetPoint("LEFT", embers.embers[i - 1], "LEFT", 26, 0)
		end
		embers.embers[i] = ember
	end
	ApplyEmberTextures(embers, emberClient)

	embers:SetScript("OnEnter", function(self)
		if GameTooltip_SetDefaultAnchor then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		end
		GameTooltip:SetText(BURNING_EMBERS or "Burning Embers", 1, 1, 1)
		if BURNING_EMBERS_TOOLTIP then
			GameTooltip:AddLine(BURNING_EMBERS_TOOLTIP, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	embers:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	playerFrame.BurningEmbersBar = embers
	power.embers = embers

	local watcher = CreateFrame("Frame")
	local function RegisterWarlockPowerEvents(w)
		w:RegisterEvent("PLAYER_ENTERING_WORLD")
		w:RegisterEvent("PLAYER_TALENT_UPDATE")
		w:RegisterEvent("SPELLS_CHANGED")
		pcall(function()
			w:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		end)
		w:RegisterEvent("UNIT_DISPLAYPOWER")
		w:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "vehicle")
		w:RegisterUnitEvent("UNIT_MAXPOWER", "player", "vehicle")
		w:RegisterUnitEvent("UNIT_AURA", "player", "vehicle")
	end
	self.RegisterWarlockPowerEvents = RegisterWarlockPowerEvents
	RegisterWarlockPowerEvents(watcher)
	self.warlockPowerWatcher = watcher

	watcher:SetScript("OnEvent", function(_, event, unit, powerToken)
		if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then
			if unit ~= "player" and unit ~= "vehicle" then
				return
			end
			-- Events set power target; OnUpdate lerps displayedPower toward it.
			if powerToken == "DEMONIC_FURY" or not powerToken then
				if fury:IsShown() then
					UpdateDemonicFury(fury, event == "UNIT_MAXPOWER")
				end
			end
			if powerToken == "BURNING_EMBERS" or not powerToken then
				if embers:IsShown() then
					UpdateBurningEmbers(embers, event == "UNIT_MAXPOWER")
				end
			end
			return
		end
		if event == "UNIT_AURA" then
			if fury:IsShown() then
				UpdateDemonicFury(fury, true)
			end
			return
		end
		if event == "SPELLS_CHANGED" and embers:IsShown() then
			SyncDestructionTextures(embers)
		end
		RefreshWarlockPowerVisibility(playerFrame)
	end)

	RefreshWarlockPowerVisibility(playerFrame)
end

function WhoaUF:ApplyWarlockPowerBarArt()
	local player = self.unitFrames and self.unitFrames.player
	if not player then
		return
	end
	local fury = player.DemonicFuryBar
	if fury and fury.bar then
		local path = ResolveClassPowerTex(TEX_DEMO)
		fury.bar:SetTexture(path)
		if fury.fill then
			fury.fill:SetTexture(path)
		end
	end
	local embers = player.BurningEmbersBar
	if embers then
		-- Theme swap: nil emberFile so textures re-resolve.
		embers.emberFile = nil
		SyncDestructionTextures(embers)
	end
end

if WhoaUF.RegisterClassBar then
	WhoaUF:RegisterClassBar({
		classes = "WARLOCK",
		load = function()
			return WhoaUF:HasMoPWarlockPower()
		end,
		init = function(uf, player)
			uf:InitWarlockPowerBars(player)
		end,
		refresh = function(uf)
			uf:RefreshWarlockPowerBars()
		end,
		applyArt = function(uf)
			uf:ApplyWarlockPowerBarArt()
		end,
		watcherKey = "warlockPowerWatcher",
		registerEvents = "RegisterWarlockPowerEvents",
		layout = {
			slot = "bottom",
			order = 70,
			frameKey = "WarlockPowerFrame",
			style = "top",
			getAnchor = "GetWarlockPowerAnchor",
			defaultX = 32,
			defaultY = 30,
		},
	})
end
