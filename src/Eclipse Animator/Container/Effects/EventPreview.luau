--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Events = require("Events")
local Clock = require("Clock")
local Frames = require("Frames")
local Cleanup = require("DumpStorage")
local Preview = {}
local current
local lastSignature
local lastTime
local lastPlaying
local suspended = false
local visualPool
local heldDisplay
local emptySignature
local BUDGET = 0.003
local MAX_STEPS = 90
local EDIT_DEBOUNCE = 0.15

local function signature(timeline)
	local state = timeline:GetState()
	local result = { tostring(state.FPS), tostring(state.EventPreviewRevision or 0) }
	for rig, track in Events.all() do
		local content = Events.runtimeSignature(track)
		if content ~= "" and Events.isEnabled(track) and rig.Parent then
			table.insert(result, tostring(track.DocumentId) .. tostring(rig) .. content)
		end
	end

	table.sort(result)
	return table.concat(result, "|")
end

local function enabledCodeSources()
	local sources = {}
	for rig, track in Events.all() do
		if not Events.isEnabled(track) or not rig.Parent then
			continue
		end

		local entries = {}
		for _, event in track.Events do
			if event.Enabled == false then
				continue
			end

			local id = track.DocumentId .. ":" .. event.Id
			if #(event.Emits or {}) > 0 then
				entries[id .. ":emit"] = game:GetService("HttpService"):JSONEncode(event.Emits)
			end

			if event.CodeBegin ~= "" then
				entries[id .. ":begin"] = event.CodeBegin
			end

			if event.CodeEnd ~= "" then
				entries[id .. ":end"] = event.CodeEnd
			end
		end

		sources[rig] = entries
	end

	return sources
end

local function retiredCode(session)
	local latest = enabledCodeSources()
	for rig, entries in session.codeSources do
		for id, source in entries do
			if not latest[rig] or latest[rig][id] ~= source then
				return true
			end
		end
	end

	return false
end

local function releaseDisplay(reuse)
	if heldDisplay then
		for _, item in heldDisplay do
			if reuse and current and item.attachment and item.emitter then
				current.clock.particles:recycleDisplay(item)
			else
				(item.root or item.attachment):Destroy()
			end
		end
	end

	heldDisplay = nil
end

local function dispose(reuse, hold)
	if hold and current and (current.ready or current.presentedFrame) and not heldDisplay then
		heldDisplay = current.clock:retainDisplay()
	end

	if current then
		visualPool = current.clock:destroy(reuse)
		current = nil
	end

	if not reuse and visualPool then
		for _, item in visualPool do
			item.attachment:Destroy()
		end

		visualPool = nil
	end

	if not reuse then
		releaseDisplay()
	end
end

function Preview.clear()
	dispose()
	Cleanup.clearVisuals()
	lastSignature, lastTime = nil, nil
	emptySignature = nil
	lastPlaying = nil
	suspended = false
end

function Preview.suspend()
	Preview.clear()
	suspended = true
end

local exportDepth = 0

function Preview.withCleanScene(timeline, callback)
	local time = timeline:GetState().CurrentTime
	local hadPreview = current ~= nil
	if hadPreview then
		dispose(true, true)
	end

	exportDepth += 1
	local result = table.pack(xpcall(callback, debug.traceback))
	exportDepth -= 1
	if hadPreview then
		Preview.update(timeline, time, false, false)
	end

	assert(result[1], result[2])
	return table.unpack(result, 2, result.n)
end

function Preview.invalidate()
	dispose()
	lastSignature = nil
	emptySignature = nil
end

local function build(timeline, playing)
	local session = {
		clock = Clock.new({
			visualPool = visualPool,
			staging = not playing,
			cacheFrames = not playing,
			nativeOnly = true,
		}),
		due = {},
		index = 1,
		contexts = {},
		rigs = {},
		target = 0,
	}
	visualPool = nil
	for _, item in heldDisplay or {} do
		local root = item.root or item.attachment
		session.clock.internal[root] = true
		for _, child in root:GetDescendants() do
			session.clock.internal[child] = true
		end
	end

	local fps = timeline:GetState().FPS
	session.fps = fps
	session.cache = Frames.new(session.clock, fps)
	session.codeSources = enabledCodeSources()
	for _, track in Events.all() do
		if not Events.isEnabled(track) or not track.Rig.Parent then
			continue
		end

		for _, event in track.Events do
			if
				event.Enabled == false
				or event.CodeBegin == "" and event.CodeEnd == "" and #(event.Emits or {}) == 0
			then
				continue
			end

			session.rigs[track.Rig] = true
			table.insert(
				session.due,
				{ time = event.Frame / fps, phase = "begin", event = event, track = track }
			)
			if event.CodeEnd ~= "" then
				table.insert(session.due, {
					time = (event.Frame + event.Duration) / fps,
					phase = "end",
					event = event,
					track = track,
				})
			end
		end
	end

	table.sort(session.due, function(a, b)
		if a.time ~= b.time then
			return a.time < b.time
		end

		if a.phase ~= b.phase then
			return a.phase == "begin"
		end

		return a.event.Id < b.event.Id
	end)
	local dependencies = session.clock.dependencies
	if dependencies then
		for rig in session.rigs do
			dependencies:addRig(rig)
		end

		session.dependencyRevision = dependencies.revision
	end

	return session
end

local function runDue(session)
	while
		session.due[session.index]
		and session.due[session.index].time <= session.clock.now + 1e-8
	do
		local entry = session.due[session.index]
		local event = entry.event
		local id = entry.track.DocumentId .. ":" .. event.Id
		session.contexts[id] = session.contexts[id] or {}
		if entry.phase == "begin" then
			session.clock:emitNative(entry.track.Rig, event, Events.speed(event, session.fps))
		end

		session.clock:execute(entry.phase == "begin" and event.CodeBegin or event.CodeEnd, {
			rig = session.clock:wrap(entry.track.Rig),
			event = table.clone(event),
			parameter = event.Parameter,
			context = session.contexts[id],
		}, "Event " .. event.Name .. " / " .. entry.phase, Events.speed(event, session.fps))
		session.index += 1
	end

	session.clock:drain()
end

local function advanceNative(session, timeline, time, posedRig, posedTime)
	local clock = session.clock
	local poses = {}
	if posedRig then
		poses[posedRig] = posedTime
		if timeline.refs and timeline.refs.GetAllRigs then
			for _, rig in timeline.refs.GetAllRigs() do
				poses[rig] = posedTime
			end
		end
	end

	local displayTime = math.floor(time * session.cache.fps + 1e-6) / session.cache.fps
	time = displayTime

	local function pose(at)
		at = math.min(displayTime, math.ceil(at * session.fps - 1e-6) / session.fps)
		for rig in session.rigs do
			if rig.Parent and poses[rig] ~= at then
				timeline:ApplyPoseAtTime(rig, at, { OnlyRig = true, SkipControls = true })
				poses[rig] = at
			end
		end
	end

	local start = clock.now
	local due = session.due[session.index]
	local job = clock.jobs[1]
	if due and due.time <= start + 1e-8 or job and job.due <= start + 1e-8 then
		pose(start)
	end

	runDue(session)
	while clock.now < time - 1e-8 do
		local frameTime = (math.floor(clock.now / clock.step + 1e-8) + 1) * clock.step
		local nextTime = math.min(time, frameTime)
		local due = session.due[session.index]
		local job = clock.jobs[1]
		if due and due.time > clock.now + 1e-8 then
			nextTime = math.min(nextTime, due.time)
		end

		if job and job.due > clock.now + 1e-8 then
			nextTime = math.min(nextTime, job.due)
		end

		local onFrame = math.abs(nextTime - frameTime) < 1e-8
		if due and due.time <= nextTime + 1e-8 or job and job.due <= nextTime + 1e-8 or onFrame then
			pose(nextTime)
		end

		clock:stepTo(nextTime, onFrame)
		runDue(session)
	end

	pose(displayTime)
	session.ready = clock.now >= time - 1e-8
	clock:renderFrame()
	releaseDisplay(true)
end

function Preview.update(timeline, time, playing, continuous, posedRig, posedTime)
	if exportDepth > 0 then
		return
	end

	if suspended and lastTime == time and not playing then
		return
	end

	suspended = false
	local key = signature(timeline)
	if emptySignature == key then
		return
	end

	local changed = key ~= lastSignature
	local retired = changed and current and retiredCode(current)
	local explicitSeek = current and lastTime ~= nil and time ~= lastTime and continuous ~= true
	local reconstructing = current and current.reconstruct
	local starting = playing
		and (lastPlaying ~= true or current and current.refreshPending and not reconstructing)
	local dependencies = current and current.clock.dependencies
	if
		dependencies
		and (
			not playing
			or starting
			or reconstructing
			or explicitSeek
			or changed
			or current.displayFrame
			or time < current.clock.now - 1e-8
		)
	then
		dependencies:poll()
	end

	local sceneChanged = dependencies and dependencies.revision ~= current.dependencyRevision
	local refresh = false
	if sceneChanged and (not playing or starting or reconstructing or explicitSeek or changed) then
		local settled = os.clock() - (dependencies.changedAt or 0) >= EDIT_DEBOUNCE
		if
			not retired
			and (
				not (settled or starting or explicitSeek or changed)
				or not dependencies:sourcesReady()
			)
		then
			current.refreshPending = true
			current.clock.particles:setNative(false, true)
			current.clock.particles:updateCamera()
			lastTime, lastPlaying = time, playing
			current.target = time
			return
		end

		refresh = true
	end

	local frame = not changed
		and not sceneChanged
		and current
		and not playing
		and continuous ~= true
		and current.cache:get(time)
	if frame and (current.displayFrame or lastTime ~= time) then
		local clock = current.clock
		if current.displayFrame ~= frame then
			current.liveFrame = current.liveFrame or clock:captureFrame()
			for rig in current.rigs do
				if rig.Parent then
					timeline:ApplyPoseAtTime(rig, time, { OnlyRig = true, SkipControls = true })
				end
			end

			clock:applyFrame(frame)
			clock.particles:showFrame(frame.particles)
			releaseDisplay(true)
			current.displayFrame = frame
			current.presentedFrame = frame
			current.ready = false
		end

		lastTime, lastPlaying = time, false
		current.target = time
		if current.ready then
			clock.particles:updateCamera()
			return
		end

		current.ready = clock.particles:prepare(os.clock() + BUDGET)
		clock.particles:render(true)
		if current.ready then
			releaseDisplay(true)
		end

		return
	end

	local nativeSeek = current
		and not playing
		and continuous ~= true
		and lastTime ~= time
		and (
			not current.clock.frameProperties
			or next(current.clock.particles.nativeOutputs) ~= nil
		)
	local reconstruct = refresh
		or retired
		or playing and current and current.displayFrame and time < current.clock.now - 1e-8
	if changed then
		releaseDisplay()
	end

	if refresh or changed or nativeSeek or current and time < current.clock.now - 1e-8 then
		dispose(not changed, not changed)
	end

	if current and current.displayFrame then
		current.clock:applyFrame(current.liveFrame)
		current.clock.particles:restoreFrame()
		current.liveFrame, current.displayFrame = nil, nil
		current.ready = false
	end

	if not current then
		current = build(timeline, playing and not reconstruct)
		current.reconstruct = reconstruct and true or nil
		lastSignature = key
		if current.due[1] then
			current.clock.now = math.min(time, current.due[1].time)
		end
	end

	local session = current
	if lastTime == time and lastPlaying == playing and not changed and session.ready then
		session.clock.particles:updateCamera()
		return
	end

	local ending = not playing and (continuous == true or session.ending and session.target == time)
	session.ending = ending
	local hold = not playing and not changed and lastTime == time
	local native = (playing or ending) and not session.reconstruct
	if native then
		session.clock:stopFrameCapture()
		session.cache:sync()
	end

	session.clock.particles:setNative(native, hold)
	lastTime = time
	lastPlaying = playing
	session.target = time
	if #session.due == 0 then
		dispose()
		emptySignature = key
		return
	end

	if native then
		advanceNative(session, timeline, time, posedRig, posedTime)
		if ending then
			session.clock.particles:setNative(false, true)
		end

		return
	end

	local clock = session.clock
	local started = os.clock()
	local steps = 0
	local posedTime
	local due = session.due[session.index]
	local job = clock.jobs[1]
	if
		not native
		or due and due.time <= clock.now + 1e-8
		or job and job.due <= clock.now + 1e-8
	then
		for rig in session.rigs do
			if rig.Parent then
				timeline:ApplyPoseAtTime(rig, clock.now, { OnlyRig = true, SkipControls = true })
			end
		end

		posedTime = clock.now
	end

	runDue(session)
	session.cache:capture()
	while
		clock.now < time - 1e-8
		and steps < MAX_STEPS
		and (steps == 0 or os.clock() - started < BUDGET)
	do
		local frameTime = (math.floor(clock.now / clock.step + 1e-8) + 1) * clock.step
		local sampleTime = clock.frameProperties
				and (math.floor(clock.now * session.cache.fps + 1e-8) + 1) / session.cache.fps
			or time
		local nextTime = math.min(time, frameTime, sampleTime)
		local due = session.due[session.index]
		if due and due.time > clock.now then
			nextTime = math.min(nextTime, due.time)
		end

		local job = clock.jobs[1]
		if job and job.due > clock.now + 1e-8 then
			nextTime = math.min(nextTime, job.due)
		end

		if
			not next(clock.tweens)
			and not next(clock.bindings)
			and not clock.particles:active()
			and not next(clock.heartbeat.listeners)
			and not next(clock.render.listeners)
			and not next(clock.stepped.listeners)
			and not next(clock.preSimulation.listeners)
			and not next(clock.preAnimation.listeners)
			and not next(clock.animationTracks)
		then
			nextTime = math.min(
				time,
				due and due.time or time,
				clock.jobs[1] and clock.jobs[1].due or time
			)
			if nextTime <= clock.now + 1e-8 then
				nextTime = math.min(time, clock.now + clock.step)
			end
		end

		for rig in session.rigs do
			if rig.Parent then
				timeline:ApplyPoseAtTime(rig, nextTime, { OnlyRig = true, SkipControls = true })
			end
		end

		posedTime = nextTime
		local onFrame = math.abs(nextTime / clock.step - math.floor(nextTime / clock.step + 0.5))
			< 1e-7
		clock:stepTo(nextTime, onFrame)
		runDue(session)
		session.cache:capture()
		steps += 1
	end

	session.ready = clock.now >= time - 1e-8
	if session.ready then
		session.presentedFrame = clock.frameProperties
				and (session.cache:get(time) or clock:captureFrame())
			or nil
		clock:renderGeometry()
		releaseDisplay(true)
	elseif session.presentedFrame and clock.frameProperties then
		session.liveFrame = clock:captureFrame()
		clock:applyFrame(session.presentedFrame)
		clock.particles:showFrame(session.presentedFrame.particles)
		clock.particles:prepare(os.clock() + BUDGET)
		clock.particles:render(true)
		session.displayFrame = session.presentedFrame
	end

	if session.ready and (not playing and not ending or session.reconstruct) then
		session.ready = clock.particles:prepare(os.clock() + BUDGET)
		if not session.ready then
			clock.particles:render(true)
		end
	end

	if session.ready or (playing or ending) and not session.reconstruct then
		clock:renderGeometry()
		clock.particles:render(true)
		releaseDisplay(true)
	end

	if session.ready then
		session.reconstruct = nil
	end

	if ending then
		clock.particles:setNative(false, true)
	end

	if posedTime ~= time then
		for rig in session.rigs do
			if rig.Parent then
				timeline:ApplyPoseAtTime(rig, time, { OnlyRig = true, SkipControls = true })
			end
		end
	end
end

function Preview.status()
	return current
			and {
				time = current.displayFrame and current.displayFrame.time or current.clock.now,
				simulatedTime = current.clock.now,
				cached = current.displayFrame ~= nil,
				cacheFrames = #current.cache.order,
				cacheValues = current.cache.weight,
				ready = current.ready and not current.refreshPending,
				refreshPending = current.refreshPending == true,
				particles = #current.clock.particles.live,
				dropped = current.clock.particles.dropped,
				callbacks = current.clock.callbacks,
			}
		or nil
end

return Preview
