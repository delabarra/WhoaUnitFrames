--[[
	Death Knight optional player frame chrome.

	dkPlayerArt off / alpha / blizzcon:
	  alpha    — WotLK DK sword art; HP only (mana/power bar hidden); portrait
	             runic fill (early bloom pulse) + blade glow at 80+ power
	             (soft→strong intensity 55→100). Mainline: vertical StatusBar
	             SetValue (secret-safe); Classic: Texture crop.
	  blizzcon — texture swap only (UI-Deathknight-Blizzcon).

	Forever warrior exception (no DK class): same Alpha / BlizzCon chrome as DK.
	  Alpha: portrait fill driven by Rage (red tint); blade glow stays stock
	  white/yellow (not Rage red); no rune bar. Layout matches DK Alpha.

	Frame chrome: Media\dk\{light|dark}\ (shared across whoa/thick/classic).
	Alpha overlays shared by light/dark: Media\shared\dk\
	  GoldBorder, Sword-Glow, RunicPower, UI-Player-DK-Status.
	Rune / classbar sheets stay on client Interface\PlayerFrame\ paths.

	Reference: reference/Classic_DK_1, 3.3.5 FrameXML/PlayerFrame.lua;
	           reference/Blizzard_UnitFrame/Mainline (StatusBar SetValue / secret power).
]]

if not WhoaUF:CanUseDkSpecialtyPlayerArt() then
	return
end

local function DkTex(key, clientFallback)
	if WhoaUF.GetDkFrameTexture then
		local path = WhoaUF:GetDkFrameTexture(key)
		if path then
			return path
		end
	end
	return clientFallback
end

local function DK_FRAME_ALPHA()
	return DkTex("alpha", "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight")
end
local function DK_FRAME_BLIZZCON()
	return DkTex("blizzcon", "Interface\\CHARACTERFRAME\\UI-DeathKnightFrame")
end
local function DK_FRAME_ALPHA_BG()
	return DkTex("background", "Interface\\PlayerFrame\\UI-PlayerFrame-DeathKnight-Background")
end
local function DK_FRAME_ALPHA_BORDER()
	return DkTex("goldBorder", "Interface\\PlayerFrame\\UI-PlayerFrame-Deathknight-GoldBorder")
end
local function DK_FRAME_ALPHA_GLOW()
	return DkTex("swordGlow", "Interface\\PlayerFrame\\UI-PlayerFrame-DeathKnight-Sword-Glow")
end
local function DK_FRAME_ALPHA_RUNIC()
	return DkTex("runicPower", "Interface\\PlayerFrame\\UI-PlayerFrame-DeathKnight-RunicPower")
end
local PLAYER_STATUS_TEXTURE = "Interface\\CharacterFrame\\UI-Player-Status"
local PLAYER_STATUS_TEXCOORD = { 0, 0.74609375, 0, 0.53125 }
local PLAYER_STATUS_W, PLAYER_STATUS_H = 190, 66
local PLAYER_STATUS_MEDIA_W, PLAYER_STATUS_MEDIA_H = 256, 128
local PLAYER_BORDER_W, PLAYER_BORDER_H = 193, 77
local PLAYER_BORDER_TEXCOORD = { 0.85546875, 0.1015625, 0.0625, 0.6640625 }
local PLAYER_HEALTH_TEXT = { centerX = 34, centerY = -1, leftX = 98, rightX = -26 }

local PLAYER_FRAME_W = 232
local DK_CHROME_W, DK_CHROME_H = 256, 128
local DK_CHROME_TOP_Y = 15

-- Alpha chrome offsets from GetDkAlphaChromeOrigin (centered TOPLEFT on overlay).
local DK_ALPHA_CHROME_BG_X, DK_ALPHA_CHROME_BG_Y = 9, -4
local DK_ALPHA_CHROME_GLOW_X, DK_ALPHA_CHROME_GLOW_Y = 8, -5
local DK_ALPHA_CHROME_SWORD_X, DK_ALPHA_CHROME_SWORD_Y = 9, -4
local DK_ALPHA_CHROME_STATUS_X, DK_ALPHA_CHROME_STATUS_Y = 30, -26
local DK_ALPHA_RUNIC_POWER_X, DK_ALPHA_RUNIC_POWER_Y = 64, 20

local DK_ALPHA_PLAYER_BARS = {
	health = { width = 110, height = 12, point = "TOPLEFT", x = 97, y = -45 },
	power = { width = 119, height = 12, point = "TOPLEFT", x = 90, y = -56 },
	name = { point = "CENTER", x = 34, y = 13 },
	background = { width = 119, height = 41, point = "TOPLEFT", x = 89.5, y = -26 },
}

local DK_ALPHA_RUNE_X, DK_ALPHA_RUNE_Y = 90, -21
local DK_ALPHA_RUNE_SCALE, DK_ALPHA_RUNE_SPACING = 1, 2

local DK_BLIZZCON_ART = { x = -7, y = 3, w = 256, h = 256 }
local DK_BLIZZCON_NAME_X, DK_BLIZZCON_NAME_Y = 34, 32
-- Mixed layout: whoa HP slot + classic power slot (Core/Appearance.lua FRAME_STYLE_BARS).
local DK_BLIZZCON_HEALTH_X, DK_BLIZZCON_HEALTH_Y = 90, -28
local DK_BLIZZCON_HEALTH_W, DK_BLIZZCON_HEALTH_H = 119, 18
local DK_BLIZZCON_POWER_X, DK_BLIZZCON_POWER_Y = 90, -45
local DK_BLIZZCON_POWER_W, DK_BLIZZCON_POWER_H = 119, 12
local DK_BLIZZCON_RUNE_X, DK_BLIZZCON_RUNE_Y = 90, -20
local DK_BLIZZCON_RUNE_SCALE, DK_BLIZZCON_RUNE_SPACING = 1, 2

local RUNICPOWERBAR_HEIGHT = 63
local RUNICPOWERBAR_WIDTH = 64
local RUNICGLOW_FADEALPHA = 0.050
local RUNICGLOW_MINALPHA = 0.40
local RUNICGLOW_MAXALPHA = 0.80
-- Soft end of blade intensity (at STRENGTH_MIN); hard end uses MIN/MAX above.
local RUNICGLOW_SOFT_MINALPHA = 0.18
local RUNICGLOW_SOFT_MAXALPHA = 0.42
local RUNICGLOW_THROBINTERVAL = 0.8
-- Blade arms at 80 (Classic Lua compare). Mainline: StatusBar min/max snaps
-- empty→full across one point so SetValue(power) gates without secret compares.
local RUNICGLOW_ARM_POWER = 80
local RUNICGLOW_BAR_MIN = RUNICGLOW_ARM_POWER - 1
local RUNICGLOW_BAR_MAX = RUNICGLOW_ARM_POWER
-- Blade throb intensity: softer at 55 → stronger at 100 (DK + Forever warrior).
local RUNICGLOW_STRENGTH_MIN = 55
local RUNICGLOW_STRENGTH_MAX = 100
-- Stock ADD glow (combat-status yellow-white); never Rage/runic cyan→red.
local RUNICGLOW_TINT_R, RUNICGLOW_TINT_G, RUNICGLOW_TINT_B = 1.0, 0.88, 0.25
-- Portrait runic fill brightness (ADD alpha) — independent of blade glow.
-- Front-loaded so the small fill is readable before the sword throbs.
local RUNICFILL_MINALPHA = 0.35
local RUNICFILL_MAXALPHA = 1.0
local RUNICFILL_BRIGHT_AT = 55
-- Soft bloom + pulse on the fill itself (not the sword glow texture).
-- Same size/anchor as the fill; ADD layer on top for the glow read.
local RUNICFILL_GLOW_MIN = 0.12
local RUNICFILL_GLOW_MAX = 0.70
local RUNICFILL_GLOW_THROB = 1.1
local RUNIC_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.RunicPower) or 6
local RAGE_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Rage) or 1
local TWO_PI = math.pi * 2

local function IsDeathKnight()
	local _, class = UnitClass("player")
	return class == "DEATHKNIGHT"
end

local function IsDkSpecialtyEligible()
	if WhoaUF.IsDkSpecialtyPlayerArtEligible then
		return WhoaUF:IsDkSpecialtyPlayerArtEligible()
	end
	return IsDeathKnight()
end

-- Power that drives Alpha sword fill: Runic Power for DKs, Rage for Forever warriors.
local function GetDkAlphaFillPowerType()
	if IsDeathKnight() then
		return RUNIC_POWER_TYPE, "RUNIC_POWER"
	end
	return RAGE_POWER_TYPE, "RAGE"
end

-- Portrait fill only: DK keeps baked cyan (white multiply). Warrior Rage:
-- desaturate the cyan sheet then tint Rage red so blue→red without crushing ADD.
local function GetDkAlphaFillTint()
	local _, token = GetDkAlphaFillPowerType()
	if token == "RAGE" then
		-- Prefer PowerBarColor.RAGE directly — GetPowerBarColor falls back to MANA.
		local info = PowerBarColor and PowerBarColor.RAGE
		if info then
			return true, info.r or 1, info.g or 0, info.b or 0
		end
		return true, 1, 0, 0
	end
	return false, 1, 1, 1
end

local function ApplyDkRegionTint(region, desaturate, r, g, b)
	if not region then
		return
	end
	local isStatusBar = region.GetObjectType and region:GetObjectType() == "StatusBar"
	if isStatusBar then
		local tex = region.GetStatusBarTexture and region:GetStatusBarTexture()
		if region.SetStatusBarDesaturated then
			region:SetStatusBarDesaturated(desaturate)
		elseif tex and tex.SetDesaturated then
			tex:SetDesaturated(desaturate)
		end
		if region.SetStatusBarColor then
			region:SetStatusBarColor(r, g, b)
		elseif tex and tex.SetVertexColor then
			tex:SetVertexColor(r, g, b)
		end
		return
	end
	if region.SetDesaturated then
		region:SetDesaturated(desaturate)
	end
	if region.SetVertexColor then
		region:SetVertexColor(r, g, b)
	end
end

local function ApplyDkAlphaFillTint(region)
	local rageTint, r, g, b = GetDkAlphaFillTint()
	ApplyDkRegionTint(region, rageTint, r, g, b)
end

-- Blade Sword-Glow: stock yellow-white ADD (DK + warrior). Never Rage red.
local function ApplyDkSwordGlowTint(region)
	ApplyDkRegionTint(region, true, RUNICGLOW_TINT_R, RUNICGLOW_TINT_G, RUNICGLOW_TINT_B)
end

-- Soft→strong blade intensity across STRENGTH_MIN…STRENGTH_MAX (power or fill ratio).
-- Never Lua-math secret UnitPower — Forever/Mainline pass fillRatio (texture height) instead.
local function GetDkSwordGlowStrengthT(runicPower, fillRatio)
	local power
	if runicPower ~= nil and WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(runicPower) then
		power = runicPower
	elseif fillRatio ~= nil and type(fillRatio) == "number"
		and (not WhoaUF.CanAccessValue or WhoaUF:CanAccessValue(fillRatio)) then
		power = fillRatio * 100
	else
		-- Secret power / no fill yet — mid soft→strong until OnUpdate can read fill ratio.
		return 0.55
	end
	local span = RUNICGLOW_STRENGTH_MAX - RUNICGLOW_STRENGTH_MIN
	if span <= 0 then
		return 1
	end
	return math.min(1, math.max(0, (power - RUNICGLOW_STRENGTH_MIN) / span))
end

local function GetDkSwordGlowAlphaRange(strengthT)
	local t = strengthT or 1
	local minA = RUNICGLOW_SOFT_MINALPHA + (RUNICGLOW_MINALPHA - RUNICGLOW_SOFT_MINALPHA) * t
	local maxA = RUNICGLOW_SOFT_MAXALPHA + (RUNICGLOW_MAXALPHA - RUNICGLOW_SOFT_MAXALPHA) * t
	return minA, maxA
end

local function SyncDkAlphaFillTint(frame)
	if not frame then
		return
	end
	ApplyDkAlphaFillTint(frame.dkRunicPowerBar)
	ApplyDkAlphaFillTint(frame.dkRunicFillGlow)
	ApplyDkSwordGlowTint(frame.dkRunicGlow)
end

-- UnitHasVehiclePlayerFrameUI is authoritative only while the vehicle unit still
-- exists. Quest seats (e.g. Lou's House) can clear the vehicle token while the
-- HasUI flag lags — treat that as not-in-vehicle so exit can restore player art.
-- frame.state can stay "vehicle" until REGEN — secure unit swap deferred in combat.
local function IsPlayerVehicleFrameActive(frame)
	frame = frame or (WhoaUF.unitFrames and WhoaUF.unitFrames.player)
	if not frame or frame.kind ~= "player" then
		return false
	end
	if UnitHasVehiclePlayerFrameUI then
		if not UnitHasVehiclePlayerFrameUI("player") then
			return false
		end
		return UnitExists("vehicle")
	end
	return frame.state == "vehicle" and UnitExists("vehicle")
end

function WhoaUF:IsPlayerVehicleFrameActive(frame)
	return IsPlayerVehicleFrameActive(frame)
end

-- True for real vehicle seat OR DevTools force-show vehicle preview (chrome only).
function WhoaUF:IsVehiclePlayerArtActive(frame)
	if self.GetForceShowVehicleType and self:GetForceShowVehicleType() then
		return true
	end
	return IsPlayerVehicleFrameActive(frame)
end

function WhoaUF:ShouldUseClassicVehicleStatusBars(frame)
	return self:IsVehiclePlayerArtActive(frame)
end

local function IsVehicleArtActive(frame)
	if WhoaUF.IsVehiclePlayerArtActive then
		return WhoaUF:IsVehiclePlayerArtActive(frame)
	end
	return IsPlayerVehicleFrameActive(frame)
end

local function RestorePlayerBackgroundForVehicle(frame)
	if not frame or not frame.Background then
		return
	end
	frame.Background:SetDrawLayer("BACKGROUND")
	frame.Background:SetSize(114, 41)
	frame.Background:ClearAllPoints()
	frame.Background:SetPoint("TOPLEFT", 89.5, -26)
end

local function GetDkAlphaChromeOrigin(frame)
	local width = (frame and frame:GetWidth()) or PLAYER_FRAME_W
	return (width - DK_CHROME_W) * 0.5, DK_CHROME_TOP_Y
end

local function LayoutDkAlphaPlayerStatus(frame)
	local status = frame and frame.StatusTexture
	local overlay = frame and frame.Overlay
	if not status or not overlay then
		return
	end
	local plateX, plateY = GetDkAlphaChromeOrigin(frame)
	local x = plateX + DK_ALPHA_CHROME_STATUS_X
	local y = plateY + DK_ALPHA_CHROME_STATUS_Y
	if status:GetParent() ~= overlay then
		status:SetParent(overlay)
	end
	-- Portrait rest/combat flash only — not the full 256×128 chrome sheet (that duplicates the gold ring).
	local path = WhoaUF.GetPlayerStatusTexture and WhoaUF:GetPlayerStatusTexture(frame) or PLAYER_STATUS_TEXTURE
	status:SetTexture(path)
	if WhoaUF.GetPlayerStatusTexCoord then
		status:SetTexCoord(WhoaUF:GetPlayerStatusTexCoord(frame))
	else
		status:SetTexCoord(PLAYER_STATUS_TEXCOORD[1], PLAYER_STATUS_TEXCOORD[2], PLAYER_STATUS_TEXCOORD[3], PLAYER_STATUS_TEXCOORD[4])
	end
	status.whoaPlayerStatusPath = path
	status:SetSize(PLAYER_STATUS_MEDIA_W, PLAYER_STATUS_MEDIA_H)
	status:SetDrawLayer("OVERLAY", 0)
	status:ClearAllPoints()
	status:SetPoint("TOPLEFT", overlay, "TOPLEFT", x, y)
end

local function RestorePlayerStatusTexture(frame)
	if WhoaUF.ApplyPlayerStatusTexture then
		WhoaUF:ApplyPlayerStatusTexture(frame)
		return
	end
	local status = frame and frame.StatusTexture
	if not status then
		return
	end
	status:SetTexture(PLAYER_STATUS_TEXTURE)
	status:SetTexCoord(PLAYER_STATUS_TEXCOORD[1], PLAYER_STATUS_TEXCOORD[2], PLAYER_STATUS_TEXCOORD[3], PLAYER_STATUS_TEXCOORD[4])
	status:SetSize(PLAYER_STATUS_W, PLAYER_STATUS_H)
	status.whoaPlayerStatusPath = PLAYER_STATUS_TEXTURE
end

local function ApplyDkRunicGoldBorderLayer(border)
	if not border or not border.SetDrawLayer then
		return
	end
	-- Above runic fill (StatusBar host under Overlay / Texture ARTWORK), below sword glow.
	border:SetDrawLayer("OVERLAY", -2)
end

local function SyncDkRunicFillHostLevel(frame)
	local host = frame and frame.dkRunicFillHost
	if not host then
		return
	end
	-- Overlay sits at unit+3; keep fill under Overlay so GoldBorder paints over RP.
	local want = (frame:GetFrameLevel() or 0) + 1
	if host:GetFrameLevel() ~= want then
		host:SetFrameLevel(want)
	end
end

local function ApplyDkAlphaChromePositions(frame)
	local overlay = frame.Overlay or frame
	local plateX, plateY = GetDkAlphaChromeOrigin(frame)

	local function anchorTopLeftChrome(tex, offsetX, offsetY)
		if not tex then
			return
		end
		tex:ClearAllPoints()
		tex:SetSize(DK_CHROME_W, DK_CHROME_H)
		tex:SetPoint("TOPLEFT", overlay, "TOPLEFT", plateX + offsetX, plateY + offsetY)
	end

	anchorTopLeftChrome(frame.dkArtBackground, DK_ALPHA_CHROME_BG_X, DK_ALPHA_CHROME_BG_Y)
	anchorTopLeftChrome(frame.dkRunicGlow, DK_ALPHA_CHROME_GLOW_X, DK_ALPHA_CHROME_GLOW_Y)
	anchorTopLeftChrome(frame.dkGoldBorder, DK_ALPHA_CHROME_BG_X, DK_ALPHA_CHROME_BG_Y)
	if frame.dkGoldBorder then
		ApplyDkRunicGoldBorderLayer(frame.dkGoldBorder)
	end

	if frame.FrameTexture then
		frame.FrameTexture:ClearAllPoints()
		frame.FrameTexture:SetSize(DK_CHROME_W, DK_CHROME_H)
		frame.FrameTexture:SetPoint("TOPLEFT", overlay, "TOPLEFT", plateX + DK_ALPHA_CHROME_SWORD_X, plateY + DK_ALPHA_CHROME_SWORD_Y)
	end

	SyncDkRunicFillHostLevel(frame)
	if frame.dkRunicPowerBar then
		frame.dkRunicPowerBar:ClearAllPoints()
		frame.dkRunicPowerBar:SetSize(RUNICPOWERBAR_WIDTH, RUNICPOWERBAR_HEIGHT)
		-- Anchor to player frame coords (same as Classic Texture path).
		frame.dkRunicPowerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", plateX + DK_ALPHA_RUNIC_POWER_X, DK_ALPHA_RUNIC_POWER_Y)
	end
	if frame.dkRunicFillGlow and frame.dkRunicPowerBar then
		frame.dkRunicFillGlow:ClearAllPoints()
		frame.dkRunicFillGlow:SetAllPoints(frame.dkRunicPowerBar)
	end
end

-- Mainline: UnitPower is secret — drive fill via StatusBar SetValue (Blizzard path).
-- Classic: Texture height/texcoord + Lua thresholds (WotLK PlayerFrame_SetRunicPower).
local function UsesSecretRunicFill()
	return WhoaUF.UsesSecretValues and WhoaUF:UsesSecretValues()
end

local function IsDkRunicStatusBar(region)
	return region and region.GetObjectType and region:GetObjectType() == "StatusBar"
end

local function ApplyDkRunicStatusBarTexture(bar, sublevel)
	if not bar or not bar.SetStatusBarTexture then
		return
	end
	bar:SetStatusBarTexture(DK_FRAME_ALPHA_RUNIC())
	bar:SetOrientation("VERTICAL")
	if bar.SetRotatesTexture then
		-- Runic sheet is already vertical (bottom→top crop like Classic texcoords).
		bar:SetRotatesTexture(false)
	end
	if bar.SetReverseFill then
		bar:SetReverseFill(false)
	end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if tex then
		if tex.SetBlendMode then
			tex:SetBlendMode("ADD")
		end
		if tex.SetDrawLayer then
			tex:SetDrawLayer("ARTWORK", sublevel or -1)
		end
	end
	ApplyDkAlphaFillTint(bar)
end

local function CreateDkRunicStatusBar(parent, sublevel)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:EnableMouse(false)
	bar:SetSize(RUNICPOWERBAR_WIDTH, RUNICPOWERBAR_HEIGHT)
	ApplyDkRunicStatusBarTexture(bar, sublevel)
	bar:SetMinMaxValues(0, 100)
	bar:SetValue(0)
	bar:SetAlpha(RUNICFILL_MAXALPHA)
	bar:Hide()
	return bar
end

local function ApplyDkSwordGlowStatusBarTexture(bar)
	if not bar or not bar.SetStatusBarTexture then
		return
	end
	bar:SetStatusBarTexture(DK_FRAME_ALPHA_GLOW())
	bar:SetOrientation("VERTICAL")
	if bar.SetRotatesTexture then
		bar:SetRotatesTexture(false)
	end
	if bar.SetReverseFill then
		bar:SetReverseFill(false)
	end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if tex then
		if tex.SetBlendMode then
			tex:SetBlendMode("ADD")
		end
		if tex.SetDrawLayer then
			tex:SetDrawLayer("ARTWORK", 0)
		end
	end
	ApplyDkSwordGlowTint(bar)
end

-- Full chrome Sword-Glow; value gate empty (<ARM) vs full art (>=ARM).
local function CreateDkSwordGlowStatusBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:EnableMouse(false)
	bar:SetSize(DK_CHROME_W, DK_CHROME_H)
	ApplyDkSwordGlowStatusBarTexture(bar)
	bar:SetMinMaxValues(RUNICGLOW_BAR_MIN, RUNICGLOW_BAR_MAX)
	bar:SetValue(0)
	bar:SetAlpha(RUNICGLOW_FADEALPHA)
	bar:Hide()
	return bar
end

-- Infer fill fraction for throb timing / strength (not the StatusBar arm gate).
local function GetDkRunicFillRatio(bar)
	if not IsDkRunicStatusBar(bar) then
		return nil
	end
	local fullH = RUNICPOWERBAR_HEIGHT
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not tex then
		return nil
	end

	local fillH = tex:GetHeight()
	if WhoaUF.CanAccessValue and not WhoaUF:CanAccessValue(fillH) then
		return nil
	end
	if type(fillH) ~= "number" then
		return nil
	end

	-- Prefer height when the fill texture is resized with value.
	-- Height ~0 is ambiguous (empty vs non-resizing StatusBar) — do not treat as 0%.
	if fillH > 0.5 and fillH < fullH - 0.5 then
		return fillH / fullH
	end

	-- Some clients keep full height and crop via texcoords — visible span ≈ fill %.
	if tex.GetTexCoord then
		local _, ULy, _, LLy = tex:GetTexCoord()
		if WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(ULy) and WhoaUF:CanAccessValue(LLy) then
			if type(ULy) == "number" and type(LLy) == "number" then
				local span = math.abs(LLy - ULy)
				if span <= 0.001 then
					return 0
				end
				if span >= 0.999 then
					return 1
				end
				return span
			end
		end
	end

	return nil
end

-- Mainline: StatusBar SetValue(power) with min=ARM-1 max=ARM — empty below ARM, full art at ARM+.
-- No Lua compare / SetShown(secret); Classic keeps Texture Show/Hide at RUNICGLOW_ARM_POWER.
local function SyncDkSwordGlowFromPower(glow, host, power)
	if not glow or not host then
		return
	end
	host.throbFinishAndHide = false
	if not IsDkRunicStatusBar(glow) then
		return
	end
	if power == nil then
		glow:SetValue(0)
		return
	end
	glow:SetMinMaxValues(RUNICGLOW_BAR_MIN, RUNICGLOW_BAR_MAX)
	glow:SetValue(power)
	if not glow:IsShown() then
		glow:Show()
	end
	-- Alpha from accessible power or fill-bar height — never secret arithmetic.
	local fillRatio = nil
	local frame = host.dkFrame
	if frame and frame.dkRunicPowerBar then
		fillRatio = GetDkRunicFillRatio(frame.dkRunicPowerBar)
	end
	local accessiblePower = (WhoaUF.CanAccessValue and WhoaUF:CanAccessValue(power)) and power or nil
	local _, maxA = GetDkSwordGlowAlphaRange(GetDkSwordGlowStrengthT(accessiblePower, fillRatio))
	glow:SetAlpha(maxA)
end

local function ApplyDkRunicFillGeometry(frame, pct)
	local bar = frame and frame.dkRunicPowerBar
	if not bar or IsDkRunicStatusBar(bar) then
		return
	end
	local plateX = GetDkAlphaChromeOrigin(frame)
	local fill = RUNICPOWERBAR_HEIGHT * pct
	bar:ClearAllPoints()
	bar:SetSize(RUNICPOWERBAR_WIDTH, math.max(0.01, fill))
	bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", plateX + DK_ALPHA_RUNIC_POWER_X, DK_ALPHA_RUNIC_POWER_Y)
	bar:SetTexCoord(0, 1, 1 - pct, 1)

	local fillGlow = frame.dkRunicFillGlow
	if not fillGlow or IsDkRunicStatusBar(fillGlow) then
		return
	end
	-- Match fill exactly (same rect + crop); glow is ADD on the same ARTWORK strata.
	fillGlow:ClearAllPoints()
	fillGlow:SetAllPoints(bar)
	fillGlow:SetTexCoord(0, 1, 1 - pct, 1)
end

local function RunicFillBrightEase(runicPower)
	local brightT = math.min(1, runicPower / RUNICFILL_BRIGHT_AT)
	return 1 - (1 - brightT) * (1 - brightT)
end

local SyncDkAlphaGlowDriver

-- Classic only: accessible fill power for Lua fill/threshold. Nil on Mainline secrets.
local function GetPlayerRunicPower()
	local powerType = GetDkAlphaFillPowerType()
	local power = UnitPower("player", powerType)
	if power == nil then
		power = UnitPower("player")
	end
	if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(power) then
		return nil
	end
	return power or 0
end

local function GetPlayerRunicPowerPair()
	local powerType = GetDkAlphaFillPowerType()
	local power = UnitPower("player", powerType)
	if power == nil then
		power = UnitPower("player")
	end
	local max = UnitPowerMax and UnitPowerMax("player", powerType)
	if max == nil and UnitPowerMax then
		max = UnitPowerMax("player")
	end
	return power, max
end

local function StopDkAlphaGlow(frame)
	local host = frame and frame.dkRunicGlowHost
	if not host then
		return
	end
	host:SetScript("OnUpdate", nil)
	host.throbFinishAndHide = nil
	host.throbStart = 0
	host.throbFirstFadeIn = true
	host.fillThrobT = 0
	if frame.dkRunicGlow then
		frame.dkRunicGlow:Hide()
	end
	if frame.dkRunicFillGlow then
		frame.dkRunicFillGlow:Hide()
	end
end

local function PulseDkFillGlowAlpha(fillGlow, host, elapsed, brightEase)
	host.fillThrobT = (host.fillThrobT or 0) + elapsed
	local pulse = 0.5 + 0.5 * math.sin(host.fillThrobT * (TWO_PI / RUNICFILL_GLOW_THROB))
	local base = RUNICFILL_GLOW_MIN + (RUNICFILL_GLOW_MAX - RUNICFILL_GLOW_MIN) * brightEase
	fillGlow:SetAlpha(base * (0.55 + 0.45 * pulse))
end

local function DkAlphaGlowOnUpdate(host, elapsed)
	local frame = host.dkFrame
	if not frame or frame.dkPlayerArt ~= "alpha" then
		host:SetScript("OnUpdate", nil)
		return
	end

	local secretFill = UsesSecretRunicFill()
	-- Visibility gated on power events via SetShown; do not re-Show every tick.

	local fillGlow = frame.dkRunicFillGlow
	if fillGlow and fillGlow:IsShown() then
		if secretFill then
			local fillRatio = GetDkRunicFillRatio(frame.dkRunicPowerBar)
			local bright = (fillRatio ~= nil) and fillRatio or 0.65
			PulseDkFillGlowAlpha(fillGlow, host, elapsed, bright)
		else
			local runicPower = GetPlayerRunicPower()
			if runicPower == nil then
				fillGlow:Hide()
				host.fillThrobT = 0
				SyncDkAlphaGlowDriver(frame)
			else
				PulseDkFillGlowAlpha(fillGlow, host, elapsed, RunicFillBrightEase(runicPower))
			end
		end
	end

	local glow = frame.dkRunicGlow
	if not glow then
		return
	end
	-- Mainline: IsShown() may be secret after SetShown(secretBool) — never Lua-test it.
	-- StatusBar glow stays Shown; value (ARM-1…ARM) gates the art. Throb alpha always.
	if not secretFill then
		if not glow:IsShown() and not host.throbFinishAndHide then
			return
		end
	elseif not IsDkRunicStatusBar(glow) then
		return
	end

	local runicPower = (not secretFill) and GetPlayerRunicPower() or nil
	local fillRatio = secretFill and GetDkRunicFillRatio(frame.dkRunicPowerBar) or nil
	local strengthT = GetDkSwordGlowStrengthT(runicPower, fillRatio)
	local glowMinA, glowMaxA = GetDkSwordGlowAlphaRange(strengthT)
	-- Peak throb toward full power (100), not the old 90% stock target.
	local peakRatio = RUNICGLOW_STRENGTH_MAX / 100
	if host.throbStart == 0 then
		host.throbStart = GetTime()
	elseif not host.throbFinishAndHide then
		local interval = RUNICGLOW_THROBINTERVAL
		if runicPower ~= nil then
			interval = RUNICGLOW_THROBINTERVAL - math.abs(peakRatio - (runicPower / 100))
		elseif fillRatio ~= nil then
			interval = RUNICGLOW_THROBINTERVAL - math.abs(peakRatio - fillRatio)
		end
		local animTime = GetTime() - host.throbStart
		if animTime >= interval then
			glow:SetAlpha(math.max(glowMinA, math.min(glowMaxA, glowMaxA * interval / animTime)))
			if animTime >= interval * 2 then
				host.throbStart = GetTime()
			end
			host.throbFirstFadeIn = false
		else
			if host.throbFirstFadeIn then
				glow:SetAlpha(math.max(RUNICGLOW_FADEALPHA, math.min(glowMaxA, glowMaxA * animTime / interval)))
			else
				glow:SetAlpha(math.max(glowMinA, math.min(glowMaxA, glowMaxA * animTime / interval)))
			end
		end
	elseif host.throbFinishAndHide then
		local animTime = GetTime() - host.throbStart
		local interval = RUNICGLOW_THROBINTERVAL
		host.throbFirstFadeIn = true
		if animTime >= interval then
			local alpha = math.min(glow:GetAlpha(), glowMaxA * (interval / (animTime * (animTime / 2))))
			glow:SetAlpha(alpha)
			if alpha <= RUNICGLOW_FADEALPHA then
				host.throbStart = 0
				glow:Hide()
				host.throbFinishAndHide = nil
				SyncDkAlphaGlowDriver(frame)
			end
		else
			host.throbStart = GetTime() - interval
		end
	end
end

SyncDkAlphaGlowDriver = function(frame)
	local host = frame and frame.dkRunicGlowHost
	if not host then
		return
	end
	local fillOn = frame.dkRunicFillGlow and frame.dkRunicFillGlow:IsShown()
	local bladeOn = false
	if UsesSecretRunicFill() then
		-- Blade visibility is SetShown(secret) — never read IsShown; keep driver with fill.
		bladeOn = fillOn and true or false
	elseif frame.dkRunicGlow and frame.dkRunicGlow:IsShown() then
		bladeOn = true
	end
	if bladeOn or fillOn or host.throbFinishAndHide then
		if not host:GetScript("OnUpdate") then
			host:SetScript("OnUpdate", DkAlphaGlowOnUpdate)
		end
	elseif host:GetScript("OnUpdate") then
		host:SetScript("OnUpdate", nil)
		host.fillThrobT = 0
	end
end

-- Mainline: StatusBar SetMinMaxValues/SetValue accept secrets (no Lua math).
local function UpdateDkAlphaRunicPowerSecret(frame, bar, fillGlow, glow, host)
	local power, max = GetPlayerRunicPowerPair()
	-- Constant 100 only when max is missing — never coalesce a secret max.
	if max == nil then
		bar:SetMinMaxValues(0, 100)
	else
		bar:SetMinMaxValues(0, max)
	end
	bar:SetValue(power)
	bar:SetAlpha(RUNICFILL_MAXALPHA)
	if not bar:IsShown() then
		bar:Show()
	end

	if fillGlow then
		if max == nil then
			fillGlow:SetMinMaxValues(0, 100)
		else
			fillGlow:SetMinMaxValues(0, max)
		end
		fillGlow:SetValue(power)
		if not fillGlow:IsShown() then
			fillGlow:Show()
		end
		fillGlow:SetAlpha((RUNICFILL_GLOW_MIN + RUNICFILL_GLOW_MAX) * 0.5)
	end

	-- ARM gate: StatusBar SetValue with min=ARM-1 max=ARM (no Lua power compare).
	SyncDkSwordGlowFromPower(glow, host, power)
	SyncDkAlphaGlowDriver(frame)
end

local function UpdateDkAlphaRunicPower(frame)
	local bar = frame and frame.dkRunicPowerBar
	local fillGlow = frame and frame.dkRunicFillGlow
	local glow = frame and frame.dkRunicGlow
	local host = frame and frame.dkRunicGlowHost
	if not bar or not glow or not host then
		return
	end

	if UsesSecretRunicFill() and IsDkRunicStatusBar(bar) then
		UpdateDkAlphaRunicPowerSecret(frame, bar, fillGlow, glow, host)
		return
	end

	local runicPower = GetPlayerRunicPower()
	if runicPower == nil then
		-- Unexpected on Classic; keep chrome quiet if secrets appear.
		ApplyDkRunicFillGeometry(frame, 0)
		bar:SetAlpha(RUNICFILL_MINALPHA)
		if fillGlow then
			fillGlow:Hide()
			host.fillThrobT = 0
		end
		if glow:IsShown() or host.throbFinishAndHide then
			host.throbFinishAndHide = true
		end
		SyncDkAlphaGlowDriver(frame)
		return
	end

	local pct = math.min(1, math.max(0, runicPower / 100))
	ApplyDkRunicFillGeometry(frame, pct)
	local brightEase = RunicFillBrightEase(runicPower)
	bar:SetAlpha(RUNICFILL_MINALPHA + (RUNICFILL_MAXALPHA - RUNICFILL_MINALPHA) * brightEase)

	if fillGlow then
		if runicPower > 0 then
			if not fillGlow:IsShown() then
				fillGlow:Show()
			end
			local base = RUNICFILL_GLOW_MIN + (RUNICFILL_GLOW_MAX - RUNICFILL_GLOW_MIN) * brightEase
			fillGlow:SetAlpha(base)
		else
			fillGlow:Hide()
			host.fillThrobT = 0
		end
	end

	-- Blade / sword glow only — separate from fill bloom above.
	if runicPower >= RUNICGLOW_ARM_POWER then
		host.throbFinishAndHide = false
		if not glow:IsShown() then
			glow:Show()
		end
	elseif glow:IsShown() or host.throbFinishAndHide then
		host.throbFinishAndHide = true
	end
	SyncDkAlphaGlowDriver(frame)
end

local function ReleaseDkAlphaChrome(frame)
	if not frame then
		return
	end
	StopDkAlphaGlow(frame)
	if frame.dkArtBackground then
		frame.dkArtBackground:Hide()
	end
	if frame.dkGoldBorder then
		frame.dkGoldBorder:Hide()
	end
	if frame.dkRunicGlow then
		frame.dkRunicGlow:Hide()
	end
	if frame.dkRunicPowerBar then
		frame.dkRunicPowerBar:Hide()
	end
	if frame.dkRunicFillGlow then
		frame.dkRunicFillGlow:Hide()
	end
	frame.dkAlphaChromeReady = false
	frame.dkArtBackground = nil
	frame.dkGoldBorder = nil
	frame.dkRunicGlow = nil
	frame.dkRunicGlowHost = nil
	frame.dkRunicPowerBar = nil
	frame.dkRunicFillGlow = nil
	if frame.dkRunicFillHost then
		frame.dkRunicFillHost:Hide()
		frame.dkRunicFillHost:SetParent(nil)
	end
	frame.dkRunicFillHost = nil
	-- Keep dkRunicEventHost — reused by SetDkAlphaRunicEvents.
end

local function SetDkAlphaRunicEvents(frame, enabled)
	local host = frame.dkRunicEventHost
	if not host then
		return
	end
	host:UnregisterAllEvents()
	if not enabled then
		return
	end
	host.dkFrame = frame
	local _, fillPowerToken = GetDkAlphaFillPowerType()
	host:SetScript("OnEvent", function(_, event, unit, powerToken)
		if frame.dkPlayerArt ~= "alpha" or IsVehicleArtActive(frame) then
			return
		end
		if event == "UNIT_RUNIC_POWER" then
			if unit == "player" then
				UpdateDkAlphaRunicPower(frame)
			end
		elseif event == "UNIT_POWER_UPDATE" then
			if unit == "player" then
				-- powerToken may be secret on Mainline — refresh rather than Lua-compare.
				if WhoaUF.NeedsSecretSafeNumberOps and WhoaUF:NeedsSecretSafeNumberOps(powerToken) then
					UpdateDkAlphaRunicPower(frame)
				elseif powerToken == nil or powerToken == fillPowerToken then
					UpdateDkAlphaRunicPower(frame)
				end
			end
		elseif event == "PLAYER_ENTERING_WORLD" or event == "RUNE_POWER_UPDATE" then
			UpdateDkAlphaRunicPower(frame)
		end
	end)
	if fillPowerToken == "RUNIC_POWER" then
		pcall(function()
			host:RegisterUnitEvent("UNIT_RUNIC_POWER", "player")
		end)
		pcall(function()
			host:RegisterEvent("RUNE_POWER_UPDATE")
		end)
	end
	host:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	host:RegisterEvent("PLAYER_ENTERING_WORLD")
end

local function EnsureDkAlphaChrome(frame)
	local overlay = frame.Overlay or frame
	local secretFill = UsesSecretRunicFill()

	if frame.dkAlphaChromeReady then
		local barKindMismatch = frame.dkRunicPowerBar
			and (secretFill ~= IsDkRunicStatusBar(frame.dkRunicPowerBar))
		local glowKindMismatch = frame.dkRunicGlow
			and (secretFill ~= IsDkRunicStatusBar(frame.dkRunicGlow))
		local wantFillParent = secretFill and frame.dkRunicFillHost or overlay
		local missingFillHost = secretFill and not frame.dkRunicFillHost
		local parentMismatch = (frame.dkRunicGlow and frame.dkRunicGlow:GetParent() ~= overlay)
			or (frame.dkGoldBorder and frame.dkGoldBorder:GetParent() ~= overlay)
			or (frame.dkRunicPowerBar and wantFillParent and frame.dkRunicPowerBar:GetParent() ~= wantFillParent)
			or (frame.dkRunicFillGlow and wantFillParent and frame.dkRunicFillGlow:GetParent() ~= wantFillParent)
			or missingFillHost
			or (not secretFill and frame.dkRunicFillHost)
		if parentMismatch or barKindMismatch or glowKindMismatch then
			ReleaseDkAlphaChrome(frame)
		else
			if frame.dkRunicGlowHost and not frame.dkRunicGlowHost.dkFrame then
				frame.dkRunicGlowHost.dkFrame = frame
			end
			if frame.dkRunicGlow and frame.dkRunicGlow.SetDrawLayer then
				frame.dkRunicGlow:SetDrawLayer("OVERLAY", -1)
			end
			if frame.dkGoldBorder then
				ApplyDkRunicGoldBorderLayer(frame.dkGoldBorder)
			end
			SyncDkRunicFillHostLevel(frame)
			return
		end
	end
	frame.dkAlphaChromeReady = true

	local plateX, plateY = GetDkAlphaChromeOrigin(frame)

	local plate = frame:CreateTexture(nil, "BACKGROUND")
	plate:SetTexture(DK_FRAME_ALPHA_BG())
	plate:SetSize(DK_CHROME_W, DK_CHROME_H)
	plate:SetPoint("TOPLEFT", overlay, "TOPLEFT", plateX + DK_ALPHA_CHROME_BG_X, plateY + DK_ALPHA_CHROME_BG_Y)
	plate:SetDrawLayer("BORDER")
	plate:Hide()
	frame.dkArtBackground = plate

	local glowDriver = CreateFrame("Frame", nil, frame)
	glowDriver:SetSize(1, 1)
	glowDriver:SetPoint("CENTER", frame, "CENTER")
	glowDriver:EnableMouse(false)
	glowDriver.dkFrame = frame
	glowDriver.throbStart = 0
	glowDriver.throbFirstFadeIn = true
	frame.dkRunicGlowHost = glowDriver

	local glow
	if secretFill then
		-- StatusBar on Overlay paints above Overlay textures (GoldBorder) — desired for blade.
		glow = CreateDkSwordGlowStatusBar(overlay)
		glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", plateX + DK_ALPHA_CHROME_GLOW_X, plateY + DK_ALPHA_CHROME_GLOW_Y)
	else
		glow = overlay:CreateTexture(nil, "OVERLAY")
		glow:SetTexture(DK_FRAME_ALPHA_GLOW())
		glow:SetSize(DK_CHROME_W, DK_CHROME_H)
		glow:SetPoint("TOPLEFT", overlay, "TOPLEFT", plateX + DK_ALPHA_CHROME_GLOW_X, plateY + DK_ALPHA_CHROME_GLOW_Y)
		if glow.SetDrawLayer then
			glow:SetDrawLayer("OVERLAY", -1)
		end
		if glow.SetBlendMode then
			glow:SetBlendMode("ADD")
		end
		glow:SetAlpha(RUNICGLOW_FADEALPHA)
		glow:Hide()
		ApplyDkSwordGlowTint(glow)
	end
	frame.dkRunicGlow = glow

	local runicBar
	local fillGlow
	if secretFill then
		-- StatusBar children of Overlay paint above Overlay textures. Host under
		-- Overlay (unit+1 vs Overlay unit+3) so GoldBorder sits over runic fill.
		local fillHost = CreateFrame("Frame", nil, frame)
		fillHost:EnableMouse(false)
		fillHost:SetAllPoints(frame)
		frame.dkRunicFillHost = fillHost
		SyncDkRunicFillHostLevel(frame)

		runicBar = CreateDkRunicStatusBar(fillHost, -1)
		runicBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", plateX + DK_ALPHA_RUNIC_POWER_X, DK_ALPHA_RUNIC_POWER_Y)
		frame.dkRunicPowerBar = runicBar

		fillGlow = CreateDkRunicStatusBar(fillHost, 0)
		fillGlow:SetAllPoints(runicBar)
		fillGlow:SetFrameLevel((runicBar:GetFrameLevel() or 0) + 1)
		fillGlow:SetAlpha(RUNICFILL_GLOW_MIN)
		frame.dkRunicFillGlow = fillGlow
	else
		runicBar = overlay:CreateTexture(nil, "ARTWORK")
		runicBar:SetTexture(DK_FRAME_ALPHA_RUNIC())
		runicBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", plateX + DK_ALPHA_RUNIC_POWER_X, DK_ALPHA_RUNIC_POWER_Y)
		runicBar:SetSize(RUNICPOWERBAR_WIDTH, RUNICPOWERBAR_HEIGHT)
		if runicBar.SetDrawLayer then
			runicBar:SetDrawLayer("ARTWORK", -1)
		end
		if runicBar.SetBlendMode then
			runicBar:SetBlendMode("ADD")
		end
		runicBar:SetAlpha(RUNICFILL_MINALPHA)
		runicBar:Hide()
		ApplyDkAlphaFillTint(runicBar)
		frame.dkRunicPowerBar = runicBar

		-- Same parent/strata/size as fill; sublevel +1 so ADD bloom sits on top of the fill.
		fillGlow = overlay:CreateTexture(nil, "ARTWORK")
		fillGlow:SetTexture(DK_FRAME_ALPHA_RUNIC())
		fillGlow:SetAllPoints(runicBar)
		if fillGlow.SetDrawLayer then
			fillGlow:SetDrawLayer("ARTWORK", 0)
		end
		if fillGlow.SetBlendMode then
			fillGlow:SetBlendMode("ADD")
		end
		fillGlow:SetAlpha(RUNICFILL_GLOW_MIN)
		fillGlow:Hide()
		ApplyDkAlphaFillTint(fillGlow)
		frame.dkRunicFillGlow = fillGlow
	end
	SyncDkAlphaFillTint(frame)

	local border = overlay:CreateTexture(nil, "OVERLAY")
	border:SetTexture(DK_FRAME_ALPHA_BORDER())
	border:SetSize(DK_CHROME_W, DK_CHROME_H)
	border:SetPoint("TOPLEFT", overlay, "TOPLEFT", plateX + DK_ALPHA_CHROME_BG_X, plateY + DK_ALPHA_CHROME_BG_Y)
	ApplyDkRunicGoldBorderLayer(border)
	border:Hide()
	frame.dkGoldBorder = border

	if not frame.dkRunicEventHost then
		frame.dkRunicEventHost = CreateFrame("Frame")
	end
end

local function RestorePlayerHealthText(frame)
	local overlay = frame.Overlay
	local health = frame.Health
	if not overlay or not health then
		return
	end
	if health.TextString then
		health.TextString:ClearAllPoints()
		health.TextString:SetPoint("CENTER", overlay, "CENTER", PLAYER_HEALTH_TEXT.centerX, PLAYER_HEALTH_TEXT.centerY)
	end
	if health.LeftText then
		health.LeftText:ClearAllPoints()
		health.LeftText:SetPoint("LEFT", overlay, "LEFT", PLAYER_HEALTH_TEXT.leftX, PLAYER_HEALTH_TEXT.centerY)
	end
	if health.RightText then
		health.RightText:ClearAllPoints()
		health.RightText:SetPoint("RIGHT", overlay, "RIGHT", PLAYER_HEALTH_TEXT.rightX, PLAYER_HEALTH_TEXT.centerY)
	end
end

local function ApplyDkAlphaPlayerLayout(frame)
	local layout = DK_ALPHA_PLAYER_BARS
	if layout.health and frame.Health then
		local health = layout.health
		frame.Health:ClearAllPoints()
		frame.Health:SetSize(health.width or 12, health.height or frame.Health:GetHeight() or 12)
		frame.Health:SetPoint(health.point, health.x, health.y)
	end
	if layout.name and frame.Name then
		local name = layout.name
		frame.Name:ClearAllPoints()
		frame.Name:SetPoint(name.point, name.x, name.y)
	end
	if WhoaUF.SyncPlayerNumericThreatAnchor then
		WhoaUF:SyncPlayerNumericThreatAnchor(frame)
	end
	RestorePlayerHealthText(frame)
	if frame.Background then
		frame.Background:SetDrawLayer("ARTWORK")
		frame.Background:SetSize(4, 4)
		frame.Background:ClearAllPoints()
		local anchor = layout.power or layout.background
		if anchor then
			frame.Background:SetPoint(anchor.point, anchor.x, anchor.y)
		end
	end
end

local function RestoreDkAlphaArt(frame)
	if not frame or frame.dkPlayerArt ~= "alpha" then
		return
	end

	StopDkAlphaGlow(frame)
	SetDkAlphaRunicEvents(frame, false)

	if frame.dkArtBackground then
		frame.dkArtBackground:Hide()
	end
	if frame.dkGoldBorder then
		frame.dkGoldBorder:Hide()
	end
	if frame.dkRunicPowerBar then
		frame.dkRunicPowerBar:Hide()
	end
	if frame.dkRunicFillGlow then
		frame.dkRunicFillGlow:Hide()
	end

	local inVehicle = IsVehicleArtActive(frame)

	local tex = frame.FrameTexture
	if tex then
		if WhoaUF.ApplyPlayerFrameBorderArt then
			WhoaUF:ApplyPlayerFrameBorderArt(frame)
		else
			local path = WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("player")
			tex:SetTexture(path or "Interface\\TargetingFrame\\UI-TargetingFrame")
			tex:SetSize(PLAYER_BORDER_W, PLAYER_BORDER_H)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER")
			tex:SetTexCoord(PLAYER_BORDER_TEXCOORD[1], PLAYER_BORDER_TEXCOORD[2], PLAYER_BORDER_TEXCOORD[3], PLAYER_BORDER_TEXCOORD[4])
		end
		if inVehicle then
			tex:Hide()
		else
			tex:Show()
		end
	end

	if frame.Portrait then
		frame.Portrait:SetDrawLayer("ARTWORK")
	end
	if frame.Power then
		frame.Power.pauseUpdates = false
		frame.Power:Show()
	end

	RestorePlayerHealthText(frame)
	RestorePlayerStatusTexture(frame)
	frame.dkPlayerArt = nil

	if inVehicle then
		RestorePlayerBackgroundForVehicle(frame)
	elseif WhoaUF.ApplyFrameBarLayout then
		WhoaUF:ApplyFrameBarLayout(frame)
	end
	if not inVehicle and WhoaUF.AnchorRuneFrame then
		WhoaUF:AnchorRuneFrame()
	end
	if WhoaUF.LayoutPlayerCombatGlow then
		WhoaUF:LayoutPlayerCombatGlow(frame)
	end
	if WhoaUF.UpdateFrameThreat then
		WhoaUF:UpdateFrameThreat(frame)
	end
end

local function RestorePlayerFrameTexture(frame)
	if frame.dkPlayerArt == "alpha" then
		RestoreDkAlphaArt(frame)
		return
	end
	local tex = frame and frame.FrameTexture
	if not tex then
		if frame then
			frame.dkPlayerArt = nil
		end
		return
	end
	local inVehicle = IsVehicleArtActive(frame)
	if WhoaUF.ApplyPlayerFrameBorderArt then
		WhoaUF:ApplyPlayerFrameBorderArt(frame)
	else
		local path = WhoaUF.GetFrameTexture and WhoaUF:GetFrameTexture("player")
		tex:SetTexture(path or "Interface\\TargetingFrame\\UI-TargetingFrame")
		tex:SetSize(PLAYER_BORDER_W, PLAYER_BORDER_H)
		tex:ClearAllPoints()
		tex:SetPoint("CENTER")
		tex:SetTexCoord(PLAYER_BORDER_TEXCOORD[1], PLAYER_BORDER_TEXCOORD[2], PLAYER_BORDER_TEXCOORD[3], PLAYER_BORDER_TEXCOORD[4])
	end
	if inVehicle then
		tex:Hide()
	else
		tex:Show()
	end
	if frame.Portrait then
		frame.Portrait:SetDrawLayer("ARTWORK")
	end
	local wasBlizzcon = frame.dkPlayerArt == "blizzcon"
	frame.dkPlayerArt = nil
	if wasBlizzcon then
		if inVehicle then
			RestorePlayerBackgroundForVehicle(frame)
		elseif WhoaUF.ApplyFrameBarLayout then
			WhoaUF:ApplyFrameBarLayout(frame)
		end
	end
	if WhoaUF.AnchorRuneFrame then
		WhoaUF:AnchorRuneFrame()
	end
	if WhoaUF.UpdateFrameThreat then
		WhoaUF:UpdateFrameThreat(frame)
	end
end

local function ApplyBlizzconBarText(bar, textShiftX, textShiftY)
	if not bar then
		return
	end
	local inset = 5
	local y = WhoaUF.GetStatusBarFontTextOffset and WhoaUF:GetStatusBarFontTextOffset() or 0
	local tx = textShiftX or 0
	local ty = textShiftY or 0
	if bar.TextString then
		bar.TextString:ClearAllPoints()
		bar.TextString:SetPoint("CENTER", bar, "CENTER", tx, y + ty)
	end
	if bar.LeftText then
		bar.LeftText:ClearAllPoints()
		bar.LeftText:SetPoint("LEFT", bar, "LEFT", inset + tx, y + ty)
	end
	if bar.RightText then
		bar.RightText:ClearAllPoints()
		bar.RightText:SetPoint("RIGHT", bar, "RIGHT", -inset + tx, y + ty)
	end
end

local function LayoutDkBlizzconHealth(frame)
	local health = frame and frame.Health
	if not health then
		return
	end
	health:ClearAllPoints()
	health:SetSize(DK_BLIZZCON_HEALTH_W, DK_BLIZZCON_HEALTH_H)
	health:SetPoint("TOPLEFT", DK_BLIZZCON_HEALTH_X, DK_BLIZZCON_HEALTH_Y)
	ApplyBlizzconBarText(health)
end

local function LayoutDkBlizzconPower(frame)
	local power = frame and frame.Power
	if not power then
		return
	end
	power.pauseUpdates = false
	power:Show()
	power:ClearAllPoints()
	power:SetSize(DK_BLIZZCON_POWER_W, DK_BLIZZCON_POWER_H)
	power:SetPoint("TOPLEFT", DK_BLIZZCON_POWER_X, DK_BLIZZCON_POWER_Y)
	ApplyBlizzconBarText(power)
	if WhoaUF.SyncFullPowerFrameLayout then
		WhoaUF:SyncFullPowerFrameLayout(power)
	end
end

local function ApplyDkBlizzconPlayerLayout(frame)
	if not frame or frame.dkPlayerArt ~= "blizzcon" then
		return
	end
	if frame.Name then
		frame.Name:ClearAllPoints()
		frame.Name:SetPoint("CENTER", DK_BLIZZCON_NAME_X, DK_BLIZZCON_NAME_Y)
	end
	if WhoaUF.SyncPlayerNumericThreatAnchor then
		WhoaUF:SyncPlayerNumericThreatAnchor(frame)
	end
	LayoutDkBlizzconHealth(frame)
	LayoutDkBlizzconPower(frame)
end

local function ApplyDkBlizzconArt(frame)
	local tex = frame.FrameTexture
	if not tex then
		return
	end
	local layout = DK_BLIZZCON_ART
	tex:ClearAllPoints()
	tex:SetTexCoord(0, 1, 0, 1)
	tex:Show()
	tex:SetTexture(DK_FRAME_BLIZZCON())
	tex:SetSize(layout.w, layout.h)
	local anchor = frame.Overlay or frame
	tex:SetPoint("TOPLEFT", anchor, "TOPLEFT", layout.x, layout.y)
	if frame.Portrait then
		frame.Portrait:SetDrawLayer("BACKGROUND")
	end
	frame.dkPlayerArt = "blizzcon"
	ApplyDkBlizzconPlayerLayout(frame)
	if WhoaUF.ApplyPlayerStatusTexture then
		WhoaUF:ApplyPlayerStatusTexture(frame)
	end
	if WhoaUF.LayoutPlayerCombatGlow then
		WhoaUF:LayoutPlayerCombatGlow(frame)
	end
	if WhoaUF.AnchorRuneFrame then
		WhoaUF:AnchorRuneFrame()
	end
end

local function ApplyDkAlphaArt(frame)
	local overlay = frame.Overlay or frame
	local secretFill = UsesSecretRunicFill()
	local needsChromeReset = false
	local wantFillParent = secretFill and frame.dkRunicFillHost or overlay
	if secretFill and not frame.dkRunicFillHost then
		needsChromeReset = true
	end
	if not secretFill and frame.dkRunicFillHost then
		needsChromeReset = true
	end
	if frame.dkRunicPowerBar and wantFillParent and frame.dkRunicPowerBar:GetParent() ~= wantFillParent then
		needsChromeReset = true
	end
	if frame.dkRunicFillGlow and wantFillParent and frame.dkRunicFillGlow:GetParent() ~= wantFillParent then
		needsChromeReset = true
	end
	if frame.dkAlphaChromeReady and not frame.dkRunicFillGlow then
		needsChromeReset = true
	end
	if frame.dkRunicPowerBar and (secretFill ~= IsDkRunicStatusBar(frame.dkRunicPowerBar)) then
		needsChromeReset = true
	end
	if frame.dkRunicGlow and (secretFill ~= IsDkRunicStatusBar(frame.dkRunicGlow)) then
		needsChromeReset = true
	end
	if frame.dkRunicGlow and frame.dkRunicGlow:GetParent() ~= overlay then
		needsChromeReset = true
	end
	if frame.dkGoldBorder and frame.dkGoldBorder:GetParent() ~= overlay then
		needsChromeReset = true
	end
	if frame.dkRunicGlowHost and frame.dkRunicGlowHost:GetWidth() > 1 then
		needsChromeReset = true
	end
	if frame.dkRunicGlowHost and not frame.dkRunicGlowHost.dkFrame then
		needsChromeReset = true
	end
	if needsChromeReset then
		ReleaseDkAlphaChrome(frame)
	end
	EnsureDkAlphaChrome(frame)

	local tex = frame.FrameTexture
	if not tex then
		return
	end

	if frame.Portrait then
		frame.Portrait:SetDrawLayer("BACKGROUND")
	end

	tex:SetTexture(DK_FRAME_ALPHA())
	tex:SetTexCoord(0, 1, 0, 1)
	tex:Show()

	if frame.dkArtBackground then
		frame.dkArtBackground:Show()
	end
	if frame.dkGoldBorder then
		frame.dkGoldBorder:Show()
		ApplyDkRunicGoldBorderLayer(frame.dkGoldBorder)
	end
	if frame.dkRunicPowerBar then
		frame.dkRunicPowerBar:Show()
		if IsDkRunicStatusBar(frame.dkRunicPowerBar) then
			ApplyDkRunicStatusBarTexture(frame.dkRunicPowerBar, -1)
		else
			if frame.dkRunicPowerBar.SetDrawLayer then
				frame.dkRunicPowerBar:SetDrawLayer("ARTWORK", -1)
			end
			if frame.dkRunicPowerBar.SetBlendMode then
				frame.dkRunicPowerBar:SetBlendMode("ADD")
			end
		end
	end
	if frame.dkRunicFillGlow then
		if IsDkRunicStatusBar(frame.dkRunicFillGlow) then
			ApplyDkRunicStatusBarTexture(frame.dkRunicFillGlow, 0)
		else
			if frame.dkRunicFillGlow.SetDrawLayer then
				frame.dkRunicFillGlow:SetDrawLayer("ARTWORK", 0)
			end
			if frame.dkRunicFillGlow.SetBlendMode then
				frame.dkRunicFillGlow:SetBlendMode("ADD")
			end
		end
	end
	ApplyDkAlphaChromePositions(frame)
	ApplyDkAlphaPlayerLayout(frame)
	LayoutDkAlphaPlayerStatus(frame)

	if frame.Power then
		frame.Power.pauseUpdates = true
		frame.Power:Hide()
	end

	frame.dkPlayerArt = "alpha"
	if frame.FrameTexture and frame.FrameTexture.SetDrawLayer then
		frame.FrameTexture:SetDrawLayer("BORDER", 0)
	end
	if frame.dkRunicGlow then
		if IsDkRunicStatusBar(frame.dkRunicGlow) then
			ApplyDkSwordGlowStatusBarTexture(frame.dkRunicGlow)
			frame.dkRunicGlow:SetMinMaxValues(RUNICGLOW_BAR_MIN, RUNICGLOW_BAR_MAX)
		else
			if frame.dkRunicGlow.SetDrawLayer then
				frame.dkRunicGlow:SetDrawLayer("OVERLAY", -1)
			end
			if frame.dkRunicGlow.SetBlendMode then
				frame.dkRunicGlow:SetBlendMode("ADD")
			end
		end
	end
	SyncDkAlphaFillTint(frame)
	if frame.dkRunicGlowHost then
		frame.dkRunicGlowHost.dkFrame = frame
	end
	SetDkAlphaRunicEvents(frame, true)
	UpdateDkAlphaRunicPower(frame)
	if WhoaUF.LayoutPlayerCombatGlow then
		WhoaUF:LayoutPlayerCombatGlow(frame)
	end
	SyncDkRunicFillHostLevel(frame)
	if WhoaUF.AnchorRuneFrame then
		WhoaUF:AnchorRuneFrame()
	end
end

function WhoaUF:GetDkAlphaRuneLayout()
	return DK_ALPHA_RUNE_X, DK_ALPHA_RUNE_Y, DK_ALPHA_RUNE_SCALE, DK_ALPHA_RUNE_SPACING, 0, 0
end

function WhoaUF:GetDkBlizzconRuneLayout()
	return DK_BLIZZCON_RUNE_X, DK_BLIZZCON_RUNE_Y, DK_BLIZZCON_RUNE_SCALE, DK_BLIZZCON_RUNE_SPACING, 0, 0
end

function WhoaUF:LayoutDkBlizzconPower(frame)
	if not self:IsDkBlizzconPlayerArtActive(frame) then
		return
	end
	LayoutDkBlizzconPower(frame)
end

function WhoaUF:IsDkBlizzconPlayerArtActive(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	return frame and frame.dkPlayerArt == "blizzcon" and not IsVehicleArtActive(frame)
end

function WhoaUF:ApplyDkBlizzconPlayerLayout(frame)
	if not self:IsDkBlizzconPlayerArtActive(frame) then
		return
	end
	ApplyDkBlizzconPlayerLayout(frame)
end

function WhoaUF:UpdateDkAlphaRunicPower(player)
	player = player or (self.unitFrames and self.unitFrames.player)
	if player and self:IsDkAlphaPlayerArtActive(player) then
		UpdateDkAlphaRunicPower(player)
	end
end

function WhoaUF:GetDeathKnightPlayerArt()
	if not IsDkSpecialtyEligible() then
		return "off"
	end
	local value = self.db and self.db.dkPlayerArt
	if value == true or value == "alpha" then
		return "alpha"
	end
	if value == "blizzcon" then
		return "blizzcon"
	end
	return "off"
end

function WhoaUF:ShouldUseWhoaPlayerForDKLayout()
	if not IsDkSpecialtyEligible() then
		return false
	end
	return self:GetDeathKnightPlayerArt() ~= "off"
end

function WhoaUF:ApplyDeathKnightPlayerArt(player)
	if not player or player.kind ~= "player" then
		return false
	end
	if IsVehicleArtActive(player) or not IsDkSpecialtyEligible() then
		if player.dkPlayerArt then
			RestorePlayerFrameTexture(player)
		end
		return false
	end
	local art = self:GetDeathKnightPlayerArt()
	if art == "off" then
		RestorePlayerFrameTexture(player)
		return false
	end
	if art == "alpha" then
		if player.dkPlayerArt == "blizzcon" then
			RestorePlayerFrameTexture(player)
		end
		ApplyDkAlphaArt(player)
	elseif art == "blizzcon" then
		if player.dkPlayerArt == "alpha" then
			RestoreDkAlphaArt(player)
		end
		ApplyDkBlizzconArt(player)
	end
	if self.UpdateFrameThreat then
		self:UpdateFrameThreat(player)
	end
	return true
end

function WhoaUF:IsDkAlphaPlayerArtActive(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	return frame and frame.dkPlayerArt == "alpha" and not IsVehicleArtActive(frame)
end

function WhoaUF:LayoutDkAlphaPlayerStatus(frame)
	if not self:IsDkAlphaPlayerArtActive(frame) then
		return
	end
	LayoutDkAlphaPlayerStatus(frame)
	SyncDkRunicFillHostLevel(frame)
end

function WhoaUF:IsDkSpecialPlayerArtActive(frame)
	frame = frame or (self.unitFrames and self.unitFrames.player)
	return frame and not IsVehicleArtActive(frame)
		and (frame.dkPlayerArt == "alpha" or frame.dkPlayerArt == "blizzcon")
end
