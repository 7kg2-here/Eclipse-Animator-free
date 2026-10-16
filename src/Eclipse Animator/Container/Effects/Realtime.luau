--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local RunService = game:GetService("RunService")
local Events = require("Events")
local Clock = require("Clock")
local State = require("State")
local Realtime = {}
local session
local timeline
local position
local positionFired = false
local pending = {}

local function dispose()
	local current = session
	session = nil
	if not current then
		return
	end

	if current.connection then
		current.connection:Disconnect()
	end

	current.clock:destroy()
end

function Realtime.clear()
	dispose()
	timeline, position = nil, nil
	positionFired = false
	table.clear(pending)
end

function Realtime.step(dt, frame)
	local current = session
	if not current or dt <= 0 then
		return
	end

	local ok, err = pcall(function()
		local target = current.clock.now + dt
		current.clock:stepTo(target, if frame == false then false else target - current.frameTime)
		if frame ~= false then
			current.frameTime = target
		end

		current.clock:renderFrame()
	end)
	if not ok then
		Realtime.clear()
		warn("Eclipse event playback: " .. tostring(err))
	end
end

local function sync(current, frame)
	local now = os.clock()
	local dt = math.max(0, now - current.lastWall)
	current.lastWall = now
	if State.PresentationHidden and not (State.CameraPreview and State.CameraPreview.isFull()) then
		return
	end

	Realtime.step(dt, frame)
end

local function ensure()
	if session and session.clock.dependencies then
		local dependencies = session.clock.dependencies
		dependencies:poll()
		if dependencies.revision ~= session.revision then
			dispose()
		end
	end

	if session then
		return session
	end

	local clock = Clock.new({ nativeOnly = true })
	clock.particles:setNative(true)
	local current =
		{ clock = clock, contexts = {}, lastWall = os.clock(), frameTime = 0, revision = 0 }
	session = current
	if clock.dependencies then
		for _, track in Events.all() do
			if Events.isEnabled(track) and track.Rig.Parent then
				clock.dependencies:addRig(track.Rig)
			end
		end

		current.revision = clock.dependencies.revision
	end

	current.connection = RunService.Heartbeat:Connect(function()
		if session ~= current then
			return
		end

		sync(current, true)
	end)
	return current
end

local lastSignature

local function bind(target)
	local parts = { tostring(target:GetState().FPS) }
	for rig, track in Events.all() do
		local content = Events.runtimeSignature(track)
		if content ~= "" and Events.isEnabled(track) and rig.Parent then
			table.insert(parts, tostring(rig) .. ":" .. content)
		end
	end

	table.sort(parts)
	local signature = table.concat(parts, "|")
	if timeline ~= target or signature ~= lastSignature then
		Realtime.clear()
		timeline = target
		lastSignature = signature
	end
end

local function flush()
	local due = pending
	pending = {}
	for _, entry in due do
		local track, event = entry.track, entry.event
		if
			not Events.isEnabled(track)
			or not track.Rig.Parent
			or event.Enabled == false
			or track.Events[event.Id] ~= event
		then
			continue
		end

		local scheduled = (event.Frame + (entry.phase == "end" and event.Duration or 0))
			/ timeline:GetState().FPS
		if scheduled ~= entry.time then
			continue
		end

		local code = entry.phase == "begin" and event.CodeBegin or event.CodeEnd
		if code == "" and not (entry.phase == "begin" and #(event.Emits or {}) > 0) then
			continue
		end

		local current = ensure()
		sync(current, false)
		if session ~= current then
			return
		end

		local id = track.DocumentId .. ":" .. event.Id
		if entry.phase == "begin" or not current.contexts[id] then
			current.contexts[id] = {}
		end

		if entry.phase == "begin" then
			current.clock:emitNative(track.Rig, event, Events.speed(event, timeline:GetState().FPS))
		end

		current.clock:execute(
			code,
			{
				rig = current.clock:wrap(track.Rig),
				event = table.clone(event),
				parameter = event.Parameter,
				context = current.contexts[id],
			},
			"Event " .. event.Name .. " / " .. entry.phase,
			Events.speed(event, timeline:GetState().FPS)
		)
		current.clock:drain()
		current.clock:renderFrame()
	end
end

function Realtime.queue(target, first, last, inclusive)
	bind(target)
	if last < first then
		dispose()
		table.clear(pending)
		position = last
		positionFired = false
		return
	end

	if position == first and positionFired then
		inclusive = false
	end

	local fps = target:GetState().FPS
	local due = {}
	for _, track in Events.all() do
		if not Events.isEnabled(track) or not track.Rig.Parent then
			continue
		end

		for _, entry in Events.range(track, first, last, inclusive, fps, true) do
			table.insert(due, entry)
		end
	end

	table.sort(due, function(a, b)
		if a.time ~= b.time then
			return a.time < b.time
		end

		if a.phase ~= b.phase then
			return a.phase == "begin"
		end

		return a.event.Id < b.event.Id
	end)
	for _, entry in due do
		table.insert(pending, entry)
	end

	position, positionFired = last, true
end

function Realtime.prepare(target, time)
	bind(target)
	if position ~= time then
		table.clear(pending)
		positionFired = false
	end

	Realtime.queue(target, time, time, true)
	flush()
	return true
end

function Realtime.update(target, time)
	bind(target)
	if position and time < position - 1e-8 then
		dispose()
		table.clear(pending)
		position, positionFired = time, false
	elseif #pending > 0 then
		if position and time > position + 1e-8 then
			Realtime.queue(target, position, time, false)
		end

		flush()
		position, positionFired = time, true
	elseif position and time > position then
		Realtime.queue(target, position, time, false)
		flush()
	elseif position ~= time then
		position, positionFired = time, false
	end
end

function Realtime.status()
	return {
		ready = true,
		time = position,
		wallTime = session and session.clock.now or 0,
		active = session ~= nil,
		pending = #pending,
	}
end

return Realtime
