--[[
	Spellbar / mirror-timer chrome for Classic clients.
	CastingBarMixin SetLook + Whoa dark/light castingbar files.
	Mainline secret-safe cast branches live in SpellbarArt_Mainline.lua.
]]

-- Never touch nameplate cast bars.
local BLIZZARD_CASTINGBAR = "Interface\\CastingBar\\"
local CASTINGBAR_BORDER_CLASSIC = "UI-CastingBar-Border"
local CASTINGBAR_BORDER_SMALL = "UI-CastingBar-Border-Small"
local CASTINGBAR_BORDER_SHIELD = "UI-CastingBar-Small-Shield"
local CASTINGBAR_FLASH = "UI-CastingBar-Flash"
local CASTINGBAR_FLASH_SMALL = "UI-CastingBar-Flash-Small"
local CASTINGBAR_SPARK = "UI-CastingBar-Spark"
local CAST_FILL_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

function WhoaUF:GetCastingBarMediaRoot()
	WhoaUF:RefreshFrameMediaCache(self:GetFrameStyle())
	return WhoaUF:GetSharedMediaRoot() .. "castingbar\\"
end

-- Player / unit / pet / mirror: Media\shared\{dark|light}\castingbar\<file>.
-- Border / Border-Small / Shield always follow frameDark. Flash/Spark stay client
-- (no dark pack files). Light full Border falls back to Classic client.
function WhoaUF:GetCastingBarTexture(file)
	if not file then
		return nil
	end
	WhoaUF:RefreshFrameMediaCache(self:GetFrameStyle())
	local root = WhoaUF:GetSharedMediaRoot() .. "castingbar\\"
	if file == CASTINGBAR_BORDER_SMALL or file == CASTINGBAR_BORDER_SHIELD then
		return WhoaUF:AddonBlp(root .. file)
	end
	if file == CASTINGBAR_BORDER_CLASSIC then
		if WhoaUF:IsFrameDarkVariant() then
			return WhoaUF:AddonBlp(root .. file)
		end
		-- Light pack has Border-Small/Shield only; full Border uses Classic client sheet.
		return BLIZZARD_CASTINGBAR .. file
	end
	return BLIZZARD_CASTINGBAR .. file
end

-- Only Whoa-owned spellbars + intentional Blizzard player/pet castbars.
local function IsWhoaManagedCastingBar(bar)
	if not bar then
		return false
	end
	if bar.whoaCastArtHooked then
		return true
	end
	return bar == PlayerCastingBarFrame
		or bar == OverlayPlayerCastingBarFrame
		or bar == PetCastingBarFrame
end

local function IsNamePlateCastingBar(bar)
	if not bar then
		return false
	end
	if bar.IsNamePlateComponent then
		return true
	end
	local name = bar.GetName and bar:GetName()
	if name and name:find("NamePlate", 1, true) then
		return true
	end
	return false
end

local function IsPlayerStyleCastingBar(bar)
	if not bar then
		return false
	end
	if bar == PlayerCastingBarFrame
		or bar == OverlayPlayerCastingBarFrame
		or bar == PetCastingBarFrame then
		return true
	end
	local look = bar.look
	return look == "CLASSIC" or look == "OVERLAY"
end

local function HideModernCastChrome(bar)
	if bar.TextBorder then
		bar.TextBorder:Hide()
	end
	if bar.DropShadow then
		bar.DropShadow:Hide()
	end
end

-- Classic CastingBarFrameTemplate: BACKGROUND black at 50% alpha under the fill.
local function ApplyClassicCastBackground(bar)
	if not bar then
		return
	end
	local bg = bar.Background or bar.whoaCastBackground
	if not bg then
		bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
		bar.whoaCastBackground = bg
	end
	if bg.SetAtlas then
		bg:SetAtlas(nil)
	end
	if bg.SetTexture then
		bg:SetTexture(nil)
	end
	if bg.SetColorTexture then
		bg:SetColorTexture(0, 0, 0, 0.5)
	else
		bg:SetVertexColor(0, 0, 0)
		bg:SetAlpha(0.5)
	end
	bg:ClearAllPoints()
	bg:SetAllPoints(bar)
	bg:Show()
	bar.Background = bar.Background or bg
end

local function SetCastingBarRegionTexture(tex, path)
	if not tex or not tex.SetTexture or not path then
		return
	end
	-- SetAtlas(nil) can error under secret/instance cast chrome — never abort the file rebind.
	if tex.SetAtlas then
		pcall(tex.SetAtlas, tex, nil)
	end
	pcall(tex.SetTexture, tex, path)
end

-- After SetLook: keep Blizzard Classic anchors (width 0 + dual points). Do not SetSize
-- the border to barW+46 — that distorts the BLP.
local function ApplyClassicUnitSpellbarLayout(bar)
	if not bar then
		return
	end
	HideModernCastChrome(bar)
	ApplyClassicCastBackground(bar)

	local border = bar.Border
	if border then
		border:ClearAllPoints()
		border:SetWidth(0)
		border:SetHeight(56)
		border:SetPoint("TOPLEFT", -23, 23)
		border:SetPoint("TOPRIGHT", 23, 23)
	end

	local shield = bar.BorderShield
	if shield then
		shield:ClearAllPoints()
		shield:SetWidth(0)
		shield:SetHeight(56)
		shield:SetPoint("TOPLEFT", -28, 23)
		shield:SetPoint("TOPRIGHT", 18, 23)
	end

	local icon = bar.Icon
	if icon then
		icon:ClearAllPoints()
		icon:SetSize(16, 17)
		icon:SetPoint("RIGHT", bar, "LEFT", -5, 1)
	end

	local text = bar.Text
	if text then
		text:ClearAllPoints()
		text:SetWidth(0)
		text:SetHeight(16)
		text:SetPoint("TOPLEFT", 0, 4)
		text:SetPoint("TOPRIGHT", 0, 4)
		if text.SetFontObject then
			text:SetFontObject("SystemFont_Shadow_Small")
		end
	end

	local spark = bar.Spark
	if spark then
		spark:ClearAllPoints()
		spark:SetSize(36, 36)
		spark:SetPoint("CENTER", 0, 0)
	end

	local flash = bar.Flash
	if flash then
		flash:ClearAllPoints()
		flash:SetWidth(0)
		flash:SetHeight(56)
		flash:SetPoint("TOPLEFT", -23, 23)
		flash:SetPoint("TOPRIGHT", 23, 23)
	end
end

local function ApplyClassicPlayerSpellbarLayout(bar)
	if not bar then
		return
	end
	HideModernCastChrome(bar)
	ApplyClassicCastBackground(bar)

	local border = bar.Border
	if border then
		border:ClearAllPoints()
		border:SetWidth(256)
		border:SetHeight(64)
		border:SetPoint("TOP", 0, 28)
	end

	local shield = bar.BorderShield
	if shield then
		shield:ClearAllPoints()
		shield:SetWidth(256)
		shield:SetHeight(64)
		shield:SetPoint("TOP", 0, 28)
	end

	local icon = bar.Icon
	if icon then
		icon:ClearAllPoints()
		icon:SetSize(16, 16)
		icon:SetPoint("RIGHT", bar, "LEFT", -5, 0)
		if bar == PlayerCastingBarFrame or bar == OverlayPlayerCastingBarFrame then
			icon:Hide()
		end
	end

	local text = bar.Text
	if text then
		text:Show()
		text:ClearAllPoints()
		text:SetWidth(185)
		text:SetHeight(16)
		text:SetPoint("TOP", 0, 5)
		if text.SetFontObject then
			text:SetFontObject("GameFontHighlight")
		end
	end

	local spark = bar.Spark
	if spark then
		spark:ClearAllPoints()
		spark:SetSize(32, 32)
		spark:SetPoint("CENTER", 0, 2)
		spark.offsetY = 2
	end

	local flash = bar.Flash
	if flash then
		flash:ClearAllPoints()
		flash:SetWidth(256)
		flash:SetHeight(64)
		flash:SetPoint("TOP", 0, 28)
	end
end

function WhoaUF:ApplySpellbarClassicLayout(spellbar)
	if not spellbar or IsNamePlateCastingBar(spellbar) then
		return
	end
	if not IsPlayerStyleCastingBar(spellbar) then
		ApplyClassicUnitSpellbarLayout(spellbar)
	else
		ApplyClassicPlayerSpellbarLayout(spellbar)
	end
end

-- Guards SetLook recursion only. Theme rebind must still run (SetLook paints light).
local applyingSpellbarLook

local function ApplySpellbarThemeTextures(bar)
	if not bar then
		return
	end
	local playerStyle = IsPlayerStyleCastingBar(bar)
	local borderFile = playerStyle and CASTINGBAR_BORDER_CLASSIC or CASTINGBAR_BORDER_SMALL
	-- Each region independently — one failure must not leave stock light chrome.
	SetCastingBarRegionTexture(bar.Border, WhoaUF:GetCastingBarTexture(borderFile))
	SetCastingBarRegionTexture(bar.BorderShield, WhoaUF:GetCastingBarTexture(CASTINGBAR_BORDER_SHIELD))
	if bar.Flash and bar.Flash.SetTexture then
		local flashFile = playerStyle and CASTINGBAR_FLASH or CASTINGBAR_FLASH_SMALL
		SetCastingBarRegionTexture(bar.Flash, WhoaUF:GetCastingBarTexture(flashFile))
	end
	if bar.Spark and bar.Spark.SetTexture then
		SetCastingBarRegionTexture(bar.Spark, WhoaUF:GetCastingBarTexture(CASTINGBAR_SPARK))
		if bar.Spark.SetBlendMode then
			pcall(bar.Spark.SetBlendMode, bar.Spark, "ADD")
		end
	end
	if bar.SetStatusBarTexture then
		pcall(bar.SetStatusBarTexture, bar, CAST_FILL_TEXTURE)
	end
	pcall(ApplyClassicCastBackground, bar)
end

function WhoaUF:ApplySpellbarArt(spellbar)
	if not spellbar or IsNamePlateCastingBar(spellbar) then
		return
	end
	if not IsWhoaManagedCastingBar(spellbar) then
		return
	end

	local playerStyle = IsPlayerStyleCastingBar(spellbar)
	local look = playerStyle and "CLASSIC" or "UNITFRAME"

	-- SetLook always paints Interface\CastingBar\ (stock light). Call at most once
	-- per look; theme textures always rebind last so instance/uninterruptible shield
	-- chrome cannot stick on the client light sheet.
	spellbar.classicStyleCastBar = true
	if not applyingSpellbarLook then
		applyingSpellbarLook = true
		if spellbar.SetLook and spellbar.whoaClassicLookApplied ~= look then
			pcall(function()
				spellbar:SetLook(look)
			end)
			spellbar.whoaClassicLookApplied = look
		else
			spellbar.look = look
		end
		pcall(function()
			self:ApplySpellbarClassicLayout(spellbar)
		end)
		applyingSpellbarLook = nil
	end

	ApplySpellbarThemeTextures(spellbar)
end

-- SetLook hard-resets Border to Interface\CastingBar\… — rebind theme after.
local function RebindSpellbarArtAfterSetLook(bar)
	if not IsWhoaManagedCastingBar(bar) or IsNamePlateCastingBar(bar) then
		return
	end
	-- Texture-only while SetLook is in flight (avoid re-entering SetLook).
	ApplySpellbarThemeTextures(bar)
	if applyingSpellbarLook then
		return
	end
	pcall(function()
		if WhoaUF.ApplySpellbarClassicLayout then
			WhoaUF:ApplySpellbarClassicLayout(bar)
		end
	end)
	ApplySpellbarThemeTextures(bar)
end

-- Per-bar hooks only — never hooksecurefunc(CastingBarMixin, "SetLook") globally.
-- Classic stock player/pet bars are hooked individually via ApplyAllSpellbarArt.
-- CastingBarFrame_SetLook (global) is wrapped only when a managed bar lacks a
-- method-style SetLook (older Classic templates).
local castingBarFrameSetLookHooked
local function EnsureClassicCastingBarFrameSetLookHook()
	if castingBarFrameSetLookHooked or not CastingBarFrame_SetLook then
		return
	end
	castingBarFrameSetLookHooked = true
	hooksecurefunc("CastingBarFrame_SetLook", RebindSpellbarArtAfterSetLook)
end

local function HookSpellbarArt(spellbar)
	if not spellbar then
		return
	end
	spellbar.whoaCastArtHooked = true
	if spellbar.SetLook and not spellbar.whoaCastArtSetLookHooked then
		spellbar.whoaCastArtSetLookHooked = true
		hooksecurefunc(spellbar, "SetLook", RebindSpellbarArtAfterSetLook)
	elseif not spellbar.SetLook then
		EnsureClassicCastingBarFrameSetLookHook()
	end
	if spellbar.HookScript and not spellbar.whoaCastArtOnShowHooked then
		spellbar.whoaCastArtOnShowHooked = true
		spellbar:HookScript("OnShow", RebindSpellbarArtAfterSetLook)
	end
end

function WhoaUF:ApplyAllSpellbarArt()
	local function apply(bar)
		if not bar then
			return
		end
		-- Force SetLook + theme on style/dark swaps (instance loads, options).
		bar.whoaClassicLookApplied = nil
		HookSpellbarArt(bar)
		self:ApplySpellbarArt(bar)
	end
	-- Main player castbar + overlay + pet: Classic geometry + dark/light chrome.
	apply(PlayerCastingBarFrame)
	apply(OverlayPlayerCastingBarFrame)
	apply(PetCastingBarFrame)
	local uf = self.unitFrames
	if uf then
		apply(uf.target and uf.target.spellbar)
		apply(uf.focus and uf.focus.spellbar)
		for i = 1, 5 do
			local boss = uf["boss" .. i]
			apply(boss and boss.spellbar)
		end
	end
	if self.ApplyAllMirrorTimerArt then
		self:ApplyAllMirrorTimerArt()
	end
end

-- Breath / fatigue / feign mirror bars (MirrorTimer1–3 / MirrorTimerContainer).
-- Classic: Border file UI-CastingBar-Border. Mainline: Border atlas → same dark/light file.
function WhoaUF:ApplyMirrorTimerArt(timerFrame)
	if not timerFrame then
		return
	end
	local border = timerFrame.Border
	if not border then
		local name = timerFrame.GetName and timerFrame:GetName()
		if name then
			border = _G[name .. "Border"]
		end
	end
	SetCastingBarRegionTexture(border, self:GetCastingBarTexture(CASTINGBAR_BORDER_CLASSIC))
end

function WhoaUF:ApplyAllMirrorTimerArt()
	local function apply(frame)
		if not frame then
			return
		end
		if not frame.whoaMirrorArtHooked and frame.HookScript then
			frame.whoaMirrorArtHooked = true
			frame:HookScript("OnShow", function(f)
				if WhoaUF.ApplyMirrorTimerArt then
					WhoaUF:ApplyMirrorTimerArt(f)
				end
			end)
		end
		self:ApplyMirrorTimerArt(frame)
	end

	local n = (type(MIRRORTIMER_NUMTIMERS) == "number" and MIRRORTIMER_NUMTIMERS) or 3
	for i = 1, n do
		apply(_G["MirrorTimer" .. i])
	end

	local container = MirrorTimerContainer
	if container and container.mirrorTimers then
		for i = 1, #container.mirrorTimers do
			apply(container.mirrorTimers[i])
		end
	end
end
