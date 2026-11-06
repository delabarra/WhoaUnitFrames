--[[
	EventBus: batch UpdateUnitFrame calls to one OnUpdate pass.

	QueueFrameUpdate(frame, aspect) coalesces per frame; FlushFrameUpdates always
	runs full UpdateUnitFrame(frame) — aspect keys dedupe only, no partial refresh.
]]

WhoaUF.Event = WhoaUF.Event or {}

local Event = WhoaUF.Event

local queue = {}
local pump

local function EnsurePump()
	if pump then
		return
	end
	pump = CreateFrame("Frame")
	pump:Hide()
end

function Event:QueueFrameUpdate(frame, aspect)
	if not frame then
		return
	end
	local aspects = queue[frame]
	if not aspects then
		aspects = {}
		queue[frame] = aspects
	end
	aspects[aspect or "*"] = true
	EnsurePump()
	if not pump:GetScript("OnUpdate") then
		pump:SetScript("OnUpdate", function()
			pump:SetScript("OnUpdate", nil)
			self:FlushFrameUpdates()
		end)
	end
end

function Event:FlushFrameUpdates()
	local uf = WhoaUF
	if not (uf and uf.UpdateUnitFrame) then
		wipe(queue)
		return
	end
	for frame, aspects in pairs(queue) do
		if aspects["*"] or next(aspects) then
			uf:UpdateUnitFrame(frame)
		end
		queue[frame] = nil
	end
end

-- Optional module hooks: { events = { EVENT = handlerFn }, register = fn(frame) }
local modules = {}

function Event:RegisterModule(name, def)
	if not name or not def then
		return
	end
	modules[name] = def
end

function Event:GetModule(name)
	return modules[name]
end
