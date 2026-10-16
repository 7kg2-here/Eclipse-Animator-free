--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Data = require("ChunkStore")
local Cache = {}
local EMPTY = table.freeze({})
local sessions = setmetatable({}, { __mode = "k" })
local owners = setmetatable({}, { __mode = "k" })
local suspended = 0
local previews = setmetatable({}, { __mode = "k" })

function Cache.preview(state, enabled)
	previews[state] = enabled
end

function Cache.withPreview(state, callback)
	local previous = previews[state]
	previews[state] = true
	local result = table.pack(xpcall(callback, debug.traceback))
	previews[state] = previous
	assert(result[1], result[2])
	return table.unpack(result, 2, result.n)
end

function Cache.without(callback)
	suspended += 1
	local result = table.pack(xpcall(callback, debug.traceback))
	suspended -= 1
	assert(result[1], result[2])
	return table.unpack(result, 2, result.n)
end

function Cache.list(state)
	local session = sessions[state.Keyframes]
	return session and session.clips or EMPTY
end

function Cache.set(state, clips)
	local previous = sessions[state.Keyframes]
	if previous then
		for bucket, owner in owners do
			if owner.session == previous then
				owners[bucket] = nil
			end
		end
	end

	local session = { state = state, clips = table.clone(clips), fps = state.FPS }
	sessions[state.Keyframes] = session
	for _, clip in clips do
		for motor in clip.tracks do
			state.Keyframes[motor] = state.Keyframes[motor] or {}
			local bucket = state.Keyframes[motor]
			local owner = owners[bucket]
			if not owner or owner.session ~= session then
				owner = { session = session, motor = motor, clips = {} }
				owners[bucket] = owner
			end

			table.insert(owner.clips, clip)
		end
	end
end

function Cache.invalidate(bucket)
	if bucket then
		local owner = owners[bucket]
		if owner then
			owner.merged = nil
		end
	else
		for _, owner in owners do
			owner.merged = nil
		end
	end
end

function Cache.active(bucket)
	if suspended > 0 then
		return bucket
	end

	local owner = bucket and owners[bucket]
	if not owner or previews[owner.session.state] == false then
		return bucket
	end

	local fps = owner.session.state.FPS
	if owner.merged and owner.fps == fps then
		return owner.merged
	end

	local merged = {}
	for frame, source in bucket do
		local key = table.clone(source)
		if source.Channels then
			key.Channels = {}
			for id, point in source.Channels do
				key.Channels[id] = table.clone(point)
			end
		end

		merged[frame] = key
	end

	for _, clip in owner.clips do
		local keys = clip.tracks[owner.motor]
		if keys then
			for frame in merged do
				if frame >= clip.first and frame <= clip.last then
					merged[frame] = nil
				end
			end

			for frame, source in keys do
				local key = table.clone(source)
				key.Frame, key.Time = frame, frame / fps
				merged[frame] = key
			end
		end
	end

	owner.merged, owner.fps = merged, fps
	return merged
end

function Cache.contains(bucket, time)
	if suspended > 0 then
		return false
	end

	local owner = bucket and owners[bucket]
	if not owner or previews[owner.session.state] == false then
		return false
	end

	local frame = time * owner.session.state.FPS
	for _, clip in owner.clips do
		if clip.tracks[owner.motor] and frame >= clip.first and frame <= clip.last then
			return true
		end
	end

	return false
end

function Cache.has(bucket)
	local owner = bucket and owners[bucket]
	return suspended == 0 and owner ~= nil and previews[owner.session.state] ~= false
end

function Cache.clearRig(state, rig)
	local remaining = {}
	for _, clip in Cache.list(state) do
		local copy = table.clone(clip)
		copy.tracks = table.clone(clip.tracks)
		copy.owners = table.clone(clip.owners or {})
		copy.ragdolls = table.clone(clip.ragdolls or {})
		for motor in copy.tracks do
			if (copy.owners[motor] or clip.rig) == rig then
				copy.tracks[motor] = nil
				copy.owners[motor] = nil
				copy.ragdolls[motor] = nil
			end
		end

		if next(copy.tracks) then
			copy.rig = copy.owners[next(copy.tracks)] or clip.rig
			table.insert(remaining, copy)
		end
	end

	Cache.set(state, remaining)
end

function Cache.write(sequence, rig, state, encode, pathOf)
	local clips = {}
	local references = Instance.new("Folder")

	references["Name"] = "EclipsePhysicsReferences"
	local referenceCount = 0
	for _, clip in Cache.list(state) do
		local tracks = {}
		for motor, keys in clip.tracks do
			if (clip.owners and clip.owners[motor] or clip.rig) ~= rig then
				continue
			end

			local property = typeof(motor) == "table"
				and motor.IsEclipseProperty
				and motor.PropertyId
			local path = not property and pathOf(motor.Part1, rig)
			local reference
			if not path and not property then
				referenceCount += 1
				reference = tostring(referenceCount)
				local value = Instance.new("ObjectValue")

				value.Name, value.Value, value.Parent =
					reference, require("rig").original(motor.Part1), references
			end

			local guideIndex
			for index, target in clip.guideMotors or {} do
				if target == motor then
					guideIndex = index
					break
				end
			end

			table.insert(tracks, {
				property = property,
				guideIndex = guideIndex,
				path = path,
				reference = reference,
				keys = encode(keys),
				original = encode(state.Keyframes[motor] or {}),
				ragdoll = clip.ragdolls and clip.ragdolls[motor],
				guide = clip.guideMotor == motor,
			})
		end

		if #tracks > 0 then
			table.insert(clips, {
				id = clip.id,
				name = clip.name,
				first = clip.first,
				last = clip.last,
				settings = encode(clip.settings),
				tracks = tracks,
			})
		end
	end

	if #clips > 0 then
		Data.write(
			sequence,
			"EclipsePhysicsData",
			Http:JSONEncode({ version = 1, clips = clips, origin = encode(rig:GetPivot()) })
		)
	end

	if referenceCount > 0 then
		references.Parent = sequence
	else
		references:Destroy()
	end
end

function Cache.prepareRead(sequence, rig, resolve, budget)
	local source = sequence:FindFirstChild("EclipsePhysicsData")
	if not source then
		return nil, {}
	end

	local data = Data.decodeJson(Data.read(source), budget)
	assert(data.version == 1, "this physics clip needs a newer Eclipse version")
	local references = sequence:FindFirstChild("EclipsePhysicsReferences")
	local parts = {}
	for _, clip in data.clips do
		for _, track in clip.tracks do
			local reference = track.reference
				and references
				and references:FindFirstChild(track.reference)
			local part = track.path and resolve(rig, track.path) or reference and reference.Value
			if part and track.original then
				parts[part] = true
			end
		end
	end

	return data, parts
end

function Cache.read(
	sequence,
	rig,
	timeline,
	decode,
	resolve,
	sanitize,
	prepared,
	budget,
	targetPivot
)
	local state = timeline:GetState()
	Cache.clearRig(state, rig)
	local source = sequence:FindFirstChild("EclipsePhysicsData")
	if not source then
		return
	end

	Cache.preview(state, false)
	local data = prepared or Data.decodeJson(Data.read(source), budget)
	assert(data.version == 1, "this physics clip needs a newer Eclipse version")
	local clips = table.clone(Cache.list(state))
	local references = sequence:FindFirstChild("EclipsePhysicsReferences")
	local target = targetPivot or require("PoseSpace").getImportPivot(rig, sequence)
	local origin = data.origin and decode(data.origin) or target
	local Space = require("PoseSpace")
	local ratio = Space.savedRatio(rig, sequence)

	local function retarget(keys, motor, part)
		for frame, key in keys do
			if budget then
				budget()
			end

			key.Motor, key.Part, key.SanitizeName = motor, part, sanitize
			key.Frame, key.Time = frame, frame / state.FPS
			Space.retargetKey(key, ratio, origin, target)
		end
	end

	for _, saved in data.clips do
		local clip
		for _, existing in clips do
			if existing.id == saved.id then
				clip = existing
				break
			end
		end

		local existing = clip ~= nil
		clip = clip
			or {
				id = saved.id,
				name = saved.name,
				first = saved.first,
				last = saved.last,
				settings = decode(saved.settings),
				rig = rig,
				tracks = {},
				owners = {},
			}
		clip.owners = clip.owners or {}
		clip.ragdolls = clip.ragdolls or {}
		for _, track in saved.tracks do
			local reference = track.reference
				and references
				and references:FindFirstChild(track.reference)
			local part = track.path and resolve(rig, track.path) or reference and reference.Value
			local motor = part and state.MotorByPart[part]
			if track.property then
				for _, candidate in require("Properties").list(rig, true) do
					if candidate.PropertyId == track.property then
						motor = candidate
						part = candidate.Part1
						break
					end
				end
			end

			if not motor then
				for candidate in state.DefaultPose do
					if candidate.Part1 == part then
						motor = candidate
						break
					end
				end
			end

			assert(motor, "a physics track is missing from " .. rig.Name)
			local keys = decode(track.keys)
			retarget(keys, motor, part)
			clip.tracks[motor] = keys
			clip.owners[motor] = rig
			clip.ragdolls[motor] = track.ragdoll
			if track.guide then
				clip.guideMotor = motor
			end

			if track.guideIndex then
				clip.guideMotors = clip.guideMotors or {}
				clip.guideMotors[track.guideIndex] = motor
			end

			if track.original then
				local original = decode(track.original)
				retarget(original, motor, part)
				timeline:_restoreMotorBucket(motor, original, state._ImportingKeyframes, budget)
			end
		end

		if not existing then
			table.insert(clips, clip)
		end

		timeline:EnsureTimelineEnd(clip.last)
	end

	Cache.set(state, clips)
end

return Cache
