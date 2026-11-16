local ADDON_NAME = ... or "WhoaUnitFrames"

--[[
	First-session welcome toast: preload SocialToast templates, wait for UI idle, show version.
]]

-- Load Blizzard_SocialToast before XML instantiates WhoaToastFrame templates.
local function EnsureToastTemplates()
	if C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_SocialToast")
		pcall(C_AddOns.LoadAddOn, "Blizzard_ChatFrame")
	elseif LoadAddOn then
		pcall(LoadAddOn, "Blizzard_SocialToast")
		pcall(LoadAddOn, "Blizzard_ChatFrame")
	end
end
EnsureToastTemplates()

local SETTLE_SECONDS = 1.5
local MAX_WAIT_SECONDS = 8

local TEXT_LEFT = 44
local TEXT_RIGHT = 20
local LINE_GAP = 4
local TOP_PAD = 10
local BOTTOM_PAD = 10
local MIN_TOAST_WIDTH = 200
local MAX_TOAST_WIDTH = 400
local MIN_TOAST_HEIGHT = 50

local shownWelcomeThisSession = false
local welcomeWatcher
local lastBusyTime = 0
local waitStartedTime = 0

WhoaToastMixin = {}

local function GetAddonMetadataField(field)
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		return C_AddOns.GetAddOnMetadata(ADDON_NAME, field) or ""
	end
	if GetAddOnMetadata then
		return GetAddOnMetadata(ADDON_NAME, field) or ""
	end
	return ""
end

local function ColorEscape(r, g, b, text)
	if WhoaUF and WhoaUF.ColorEscape then
		return WhoaUF:ColorEscape(r, g, b, text)
	end
	if r == nil or g == nil or b == nil then
		return text or ""
	end
	return string.format(
		"|cff%02x%02x%02x%s|r",
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5),
		text or ""
	)
end

local function Colored(text, r, g, b)
	return ColorEscape(r, g, b, text)
end

local function StripColorCodes(text)
	if not text then
		return ""
	end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
	text = text:gsub("|r", "")
	return text
end

local function PrintMsg(text)
	(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff66ccffWhoa Toast|r: " .. text)
end

local function MarkBusy()
	lastBusyTime = GetTime()
end

local function HasQueuedBNetToasts()
	local stock = BNToastFrame
	local queue = stock and stock.BNToasts
	if not queue then
		return false
	end
	for i = 1, #queue do
		return true
	end
	return false
end

local function BNetToastsAreIdle()
	local stock = BNToastFrame
	if stock and stock:IsShown() then
		return false
	end
	return not HasQueuedBNetToasts()
end

function WhoaToastMixin:OnLoad()
	self.toastQueue = self.toastQueue or {}
	if ChatAlertFrame and ChatAlertFrame.AddAutoAnchoredSubSystem then
		local alertSystem = ChatAlertFrame:AddAutoAnchoredSubSystem(self)
		if ChatAlertFrame.SetSubSystemAnchorPriority then
			ChatAlertFrame:SetSubSystemAnchorPriority(alertSystem, 2)
		end
	end
end

function WhoaToastMixin:OnHide()
	if self._whoaToastPumpPending then
		return
	end
	if not self.toastQueue or #self.toastQueue == 0 then
		return
	end
	self._whoaToastPumpPending = true
	C_Timer.After(0.1, function()
		self._whoaToastPumpPending = false
		self:PumpQueue()
	end)
end

function WhoaToastMixin:PumpQueue()
	if self:IsShown() or not self.toastQueue or #self.toastQueue == 0 then
		return
	end
	local data = table.remove(self.toastQueue, 1)
	self:ShowToastData(data)
end

function WhoaToastMixin:ApplyToastSize(line1, line2, line3, line4)
	local topLine = self.TopLine
	local middleLine = self.MiddleLine
	local bottomLine = self.BottomLine
	local pathLine = self.DoubleLine
	if not topLine or not bottomLine then
		self:SetWidth(MIN_TOAST_WIDTH)
		self:SetHeight(MIN_TOAST_HEIGHT)
		return
	end

	line1 = line1 or ""
	line2 = line2 or ""
	line3 = line3 or ""
	line4 = line4 or ""

	local function MeasurePlainWidth(fontString, text)
		fontString:SetText(StripColorCodes(text))
		return fontString:GetStringWidth()
	end

	local contentWidth = MeasurePlainWidth(topLine, line1)
	if line2 ~= "" and middleLine then
		contentWidth = math.max(contentWidth, MeasurePlainWidth(middleLine, line2))
	end
	if line3 ~= "" then
		contentWidth = math.max(contentWidth, MeasurePlainWidth(bottomLine, line3))
	end
	if line4 ~= "" and pathLine then
		contentWidth = math.max(contentWidth, MeasurePlainWidth(pathLine, line4))
	end
	contentWidth = math.max(contentWidth, 1)

	local frameWidth = contentWidth + TEXT_LEFT + TEXT_RIGHT
	if frameWidth < MIN_TOAST_WIDTH then
		frameWidth = MIN_TOAST_WIDTH
	elseif frameWidth > MAX_TOAST_WIDTH then
		frameWidth = MAX_TOAST_WIDTH
	end

	self:SetWidth(frameWidth)

	topLine:SetText(line1)
	local frameHeight = TOP_PAD + topLine:GetHeight()

	if line2 ~= "" and middleLine then
		middleLine:SetText(line2)
		frameHeight = frameHeight + LINE_GAP + middleLine:GetHeight()
	end

	if line3 ~= "" then
		bottomLine:SetText(line3)
		frameHeight = frameHeight + LINE_GAP + bottomLine:GetHeight()
	end

	if line4 ~= "" and pathLine then
		pathLine:SetText(line4)
		frameHeight = frameHeight + LINE_GAP + pathLine:GetHeight()
	end

	frameHeight = frameHeight + BOTTOM_PAD
	if frameHeight < MIN_TOAST_HEIGHT then
		frameHeight = MIN_TOAST_HEIGHT
	end
	self:SetHeight(frameHeight)
end

function WhoaToastMixin:ShowToastData(data)
	data = data or {}
	local line1 = data.line1 or data.title or ""
	local line2 = data.line2 or ""
	local line3 = data.line3 or data.text or ""
	local line4 = data.line4 or ""

	local bodyR, bodyG, bodyB = WhoaUF:GetToastBodyColor()

	self.TopLine:Show()
	self.TopLine:SetTextColor(bodyR, bodyG, bodyB)
	self.TopLine:SetText(line1)

	if line2 ~= "" then
		self.MiddleLine:Show()
		self.MiddleLine:SetTextColor(bodyR, bodyG, bodyB)
		self.MiddleLine:SetText(line2)
		self.BottomLine:SetPoint("TOPLEFT", self.MiddleLine, "BOTTOMLEFT", 0, -LINE_GAP)
	else
		self.MiddleLine:Hide()
		self.BottomLine:SetPoint("TOPLEFT", self.TopLine, "BOTTOMLEFT", 0, -LINE_GAP)
	end

	if line3 ~= "" then
		self.BottomLine:Show()
		self.BottomLine:SetTextColor(bodyR, bodyG, bodyB)
		self.BottomLine:SetText(line3)
	else
		self.BottomLine:Hide()
		self.BottomLine:SetText("")
	end

	if line4 ~= "" then
		self.DoubleLine:Show()
		self.DoubleLine:SetTextColor(bodyR, bodyG, bodyB)
		self.DoubleLine:SetText(line4)
		if line3 ~= "" then
			self.DoubleLine:SetPoint("TOPLEFT", self.BottomLine, "BOTTOMLEFT", 0, -LINE_GAP)
		elseif line2 ~= "" then
			self.DoubleLine:SetPoint("TOPLEFT", self.MiddleLine, "BOTTOMLEFT", 0, -LINE_GAP)
		else
			self.DoubleLine:SetPoint("TOPLEFT", self.TopLine, "BOTTOMLEFT", 0, -LINE_GAP)
		end
	else
		self.DoubleLine:Hide()
		self.DoubleLine:SetText("")
	end

	if self.IconTexture then
		self.IconTexture:SetTexCoord(0, 0.25, 0, 0.5)
	end
	self:ApplyToastSize(line1, line2, line3, line4)

	if SOUNDKIT and SOUNDKIT.UI_BNET_TOAST then
		PlaySound(SOUNDKIT.UI_BNET_TOAST)
	end

	if AlertFrame_ShowNewAlert then
		AlertFrame_ShowNewAlert(self)
	else
		self:Show()
	end
end

function WhoaToastMixin:EnqueueToast(line1, line2, line3, line4)
	self.toastQueue = self.toastQueue or {}
	self.toastQueue[#self.toastQueue + 1] = { line1 = line1, line2 = line2, line3 = line3, line4 = line4 }
	self:PumpQueue()
end

function WhoaUF:ShowToast(title, text)
	if not WhoaToastFrame then
		PrintMsg("toast frame missing (SocialToast templates did not load).")
		return
	end
	local ok, err = pcall(WhoaToastFrame.EnqueueToast, WhoaToastFrame, title, nil, text, nil)
	if not ok then
		PrintMsg("toast error: " .. tostring(err))
	end
end

local function StopWelcomeWatcher()
	if welcomeWatcher then
		welcomeWatcher:Cancel()
		welcomeWatcher = nil
	end
end

local function BuildWelcomeToast()
	local version = GetAddonMetadataField("Version")
	local flavor = WhoaUF:GetClientFlavor()

	local nameR, nameG, nameB = WhoaUF:GetToastBNetNameColor()
	local versionR, versionG, versionB = WhoaUF:GetToastVersionColor()
	local whiteR, whiteG, whiteB = WhoaUF:GetToastWhiteColor()
	local clientR, clientG, clientB = WhoaUF:GetToastClientColor()
	local commandR, commandG, commandB = WhoaUF:GetToastBroadcastTimeColor()

	local line1 = Colored(ADDON_NAME, nameR, nameG, nameB)
	if version ~= "" then
		line1 = line1 .. " - " .. Colored(version, versionR, versionG, versionB)
	end

	local line2 = Colored("Addon loaded - ", whiteR, whiteG, whiteB)
		.. Colored(flavor, clientR, clientG, clientB)

	local line3 = "To view the settings type "
		.. Colored("/whoaui", commandR, commandG, commandB)
		.. " or go to"

	local line4 = "Options > AddOns > " .. ADDON_NAME .. "."
	return line1, line2, line3, line4
end

local function ShowWelcomeToast()
	if shownWelcomeThisSession then
		return
	end
	local db = WhoaUF and WhoaUF.db
	if db and db.hideWelcome then
		return
	end
	shownWelcomeThisSession = true
	StopWelcomeWatcher()
	if not WhoaToastFrame then
		PrintMsg("loaded, but toast frame is missing.")
		return
	end
	local line1, line2, line3, line4 = BuildWelcomeToast()
	local ok, err = pcall(WhoaToastFrame.EnqueueToast, WhoaToastFrame, line1, line2, line3, line4)
	if not ok then
		PrintMsg("welcome toast error: " .. tostring(err))
	end
end

local function TickWelcomeWatcher()
	if shownWelcomeThisSession then
		StopWelcomeWatcher()
		return
	end

	local now = GetTime()
	if now - waitStartedTime >= MAX_WAIT_SECONDS then
		ShowWelcomeToast()
		return
	end

	if not BNetToastsAreIdle() then
		MarkBusy()
		return
	end

	if now - lastBusyTime < SETTLE_SECONDS then
		return
	end

	ShowWelcomeToast()
end

local function StartWelcomeWatcher()
	if shownWelcomeThisSession or welcomeWatcher then
		return
	end
	local db = WhoaUF and WhoaUF.db
	if db and db.hideWelcome then
		return
	end
	waitStartedTime = GetTime()
	MarkBusy()
	welcomeWatcher = C_Timer.NewTicker(0.25, TickWelcomeWatcher)
end

function WhoaUF:StartWelcomeToast()
	StartWelcomeWatcher()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		StartWelcomeWatcher()
	end
end)
