--[[
	Shared unit-frame module state. All Frames/* modules read/write via WhoaUF._UF.
]]

WhoaUF._UF = WhoaUF._UF or {}

local UF = WhoaUF._UF

UF.frames = UF.frames or {}

-- Deferred work flushed on PLAYER_REGEN_ENABLED (combat lockdown).
UF.pendingUnitFramesApply = nil
UF.pendingBossFramesInit = nil
UF.pendingVehicleArtApply = nil
UF.pendingPowerVisibility = nil
UF.pendingPetVisibility = nil
UF.pendingFrameScale = nil
-- vehicleTransitionGen: retry vehicle art when HasVehiclePlayerFrameUI lags exit.
UF.vehicleTransitionGen = nil
-- playerOptionsRefreshGen: defer Options refresh until secure player art can swap back.
UF.playerOptionsRefreshGen = nil

function WhoaUF:GetUnitFrameRegistry()
	return UF.frames
end
