--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Policy = require("Policy")
local Data = require("ChunkStore")
local R6Controls = require("R6Controls")
local MasterControl = require("MasterControl")
local Physics = require("Cache")
local Storage = {}
local MainState = require("State")

local function checkpoint()
	if MainState.ProjectWorkStep then
		MainState.ProjectWorkStep()
	end
end

local NAME = "EclipseKeyframeData"
local omitted = {
	Motor = true,
	Part = true,
	Button = true,
	SanitizeName = true,
	_EclipseRawStored = true,
	_EclipseRawChannels = true,
}

local function encode(value, seen)
	checkpoint()
	local kind = typeof(value)
	if kind == "CFrame" then
		return { C = { value:GetComponents() } }
	elseif kind == "Vector3" then
		return { V = { value.X, value.Y, value.Z } }
	elseif kind == "EnumItem" then
		return { E = { (tostring(value.EnumType):gsub("Enum%.", "")), value.Name } }
	elseif kind == "number" then
		assert(value == value and math.abs(value) < math.huge, "Non-finite keyframe value")
		return value
	elseif kind == "string" or kind == "boolean" then
		return value
	elseif kind == "table" then
		seen = seen or {}
		if seen[value] then
			return nil
		end

		seen[value] = true
		local pose = typeof(value.C0) == "CFrame" and value.C0 or nil
		local derived = false
		local flat = {}
		for key, item in value do
			if not omitted[key] and (typeof(key) == "string" or typeof(key) == "number") then
				if
					pose
					and (
						(key == "Position" and item == pose.Position)
						or (key == "Rotation" and item == pose.Rotation)
					)
				then
					derived = true
					continue
				end

				local encoded = encode(item, seen)
				if encoded ~= nil then
					table.insert(flat, key)
					table.insert(flat, encoded)
				end
			end
		end

		if derived then
			table.insert(flat, "_EclipseDerivedPose")
			table.insert(flat, true)
		end

		seen[value] = nil
		return { T = flat }
	end

	return nil
end

local function decode(value, budget)
	if typeof(value) ~= "table" then
		return value
	end

	if value.T then
		local flat, out = value.T, {}
		for index = 1, #flat, 2 do
			out[flat[index]] = decode(flat[index + 1], budget)
			if budget then
				budget()
			end
		end

		if out._EclipseDerivedPose then
			out._EclipseDerivedPose = nil
			if typeof(out.C0) == "CFrame" then
				if out.Position == nil then
					out.Position = out.C0.Position
				end

				if out.Rotation == nil then
					out.Rotation = out.C0.Rotation
				end
			end
		end

		return out
	elseif value.C then
		return CFrame.new(table.unpack(value.C))
	elseif value.V then
		return Vector3.new(table.unpack(value.V))
	elseif value.E then
		return Enum[value.E[1]][value.E[2]]
	end

	if value.type == "CFrame" then
		return CFrame.new(table.unpack(value.value))
	elseif value.type == "Vector3" then
		return Vector3.new(table.unpack(value.value))
	elseif value.type == "Enum" then
		return Enum[value.enum][value.value]
	elseif value.type == "Table" then
		local out = {}
		for _, entry in value.entries do
			out[entry.key] = decode(entry.value, budget)
			if budget then
				budget()
			end
		end

		return out
	end

	error("Invalid keyframe encoding")
end

local function pathOf(part, rig, bindings)
	local original = part
	local path = {}
	while part and part ~= rig do
		local parent = part.Parent
		if not parent then
			break
		end

		local index = 0
		for _, child in parent:GetChildren() do
			if child.Name == part.Name and child.ClassName == part.ClassName then
				index += 1
			end

			if child == part then
				break
			end
		end

		table.insert(path, 1, { name = part.Name, class = part.ClassName, index = index })
		part = parent
	end

	return part == rig and path
		or require("TrackOrganizationStorage").bindingPath(rig, original, bindings)
end

local function resolve(rig, path)
	local part = rig
	for _, step in path do
		if step.link == "Part1" then
			if not part:IsA("Motor6D") or not part.Part1 then
				return nil
			end

			part = part.Part1
			continue
		end

		local count, found = 0, nil
		for _, child in part:GetChildren() do
			if child.Name == step.name and child.ClassName == step.class then
				count += 1
				if count == step.index then
					found = child
					break
				end
			end
		end

		if not found then
			return nil
		end

		part = found
	end

	return part
end

local function collect(rig, state, fullArchive)
	local tracks, archived = {}, {}
	local incoming = {}
	for _, motor in require("RigTraversal").rigDescendants(rig) do
		if motor:IsA("Motor6D") and motor.Part1 then
			incoming[motor.Part1] = (incoming[motor.Part1] or 0) + 1
		end
	end

	local bindings = {}
	local hasMaster = MasterControl.get(rig, true) ~= nil
	local buckets = state.Keyframes
	if hasMaster or fullArchive then
		buckets = table.clone(buckets)
		for motor in state.DefaultPose do
			if not buckets[motor] then
				buckets[motor] = {}
			end
		end
	end

	for motor, bucket in buckets do
		checkpoint()
		if
			typeof(motor) == "table"
			and (motor.IsEclipseArmatureControl or motor.IsEclipseProperty)
		then
			continue
		end

		local path = pathOf(motor.Part1, rig, bindings)
		if not path then
			continue
		end

		local jointPath = typeof(motor) == "Instance"
				and motor:IsA("Motor6D")
				and (incoming[motor.Part1] or 0) > 1
				and pathOf(motor, rig)
			or nil
		local rest = (fullArchive or not next(bucket)) and state.DefaultPose[motor]
		local control = typeof(motor) == "table" and motor.IsEclipseR6Control
		local needed = jointPath ~= nil
			or fullArchive
			or control
			or rest
			or hasMaster
			or not Policy.channelsEnabled()
		for _, key in bucket do
			if
				key.CamAttachTarget ~= nil
				or key.CamTargetEnabled ~= nil
				or key.CamTrackTo ~= nil
				or key.CamTargetParent ~= nil
				or typeof(key.IK) == "boolean"
				or Policy.isDisabled(key)
				or key.ChannelPoseC0
				or key.BlenderCurve
				or key.BlenderSource
				or next(key.KeyGroups or {})
			then
				needed = true
				break
			end
		end

		if not needed then
			for _, key in bucket do
				for _, channel in key.Channels or {} do
					if channel.Easing then
						needed = true
						break
					end
				end

				if needed then
					break
				end
			end
		end

		if needed and (rest or hasMaster or next(bucket)) then
			local keys = {}
			for frame, key in bucket do
				table.insert(keys, { frame = frame, data = encode(key) })
				checkpoint()
			end

			local descriptor = control
					and {
						kind = motor:GetAttribute("EclipseR6Control"),
						customIK = motor.Owner:GetAttribute("EclipseAutoIK") == true or nil,
						customRest = encode(require("customRest").rest(motor.Owner)),
						owner = pathOf(motor.Owner.Part1, rig),
						rest = encode(state.DefaultPose[motor] or motor.Bone.CFrame),
						attributes = encode(motor:GetAttributes()),
					}
				or nil
			table.insert(tracks, {
				path = path,
				jointPath = jointPath,
				keys = keys,
				rest = rest and encode(rest) or nil,
				world = fullArchive and encode(state.DefaultWorldPose[motor]) or nil,
				parented = if fullArchive then state.ParentingDefaults[motor] else nil,
				size = fullArchive and encode(state.DefaultSize[motor.Part1]) or nil,
				control = descriptor,
			})
			if not control then
				archived[motor] = true
			end
		end
	end

	return tracks, archived
end

function Storage.plan(rig, state, fullArchive)
	return collect(rig, state, fullArchive)
end

local function encodeTracks(tracks)
	local out = { '{"version":2,"quaternionInterpolation":2,"tracks":[' }
	for i, track in tracks do
		if i > 1 then
			table.insert(out, ",")
		end

		local metadata = table.clone(track)
		metadata.keys = nil
		local text = Http:JSONEncode(metadata)
		table.insert(out, text:sub(1, -2))
		table.insert(out, ',"keys":[')
		for first = 1, #track.keys, 64 do
			local batch = table.create(math.min(64, #track.keys - first + 1))
			for index = first, math.min(first + 63, #track.keys) do
				table.insert(batch, track.keys[index])
			end

			if first > 1 then
				table.insert(out, ",")
			end

			local encoded = Http:JSONEncode(batch)
			table.insert(out, encoded:sub(2, -2))
			checkpoint()
		end

		table.insert(out, "]}")
		checkpoint()
	end

	table.insert(out, "]}")
	return table.concat(out)
end

function Storage.write(sequence, rig, state, fullArchive, prepared)
	local planted = rig:GetAttribute("EclipseIKFeetPlanted")
	if planted == nil then
		planted = require("Preferences").get("IKFeetPlanted")
	end

	sequence:SetAttribute("EclipseIKFeetPlanted", planted)
	sequence:SetAttribute("EclipseIKSettingsVersion", 2)
	sequence:SetAttribute(
		"EclipseR6BendPercent",
		rig:GetAttribute("EclipseR6BendPercent") or require("Preferences").get("R6BendPercent")
	)
	local tracks = prepared or collect(rig, state, fullArchive)
	if #tracks > 0 then
		Data.write(sequence, NAME, encodeTracks(tracks))
	end

	local modifierTracks = require("Mods").collect(rig, state, pathOf)
	if #modifierTracks > 0 then
		Data.write(
			sequence,
			"EclipseCurveModifiers",
			Http:JSONEncode({ version = 1, tracks = modifierTracks })
		)
	end

	Physics.write(sequence, rig, state, encode, pathOf)
end

local function restoreControl(rig, track, state, archive)
	local descriptor = track.control
	local last = track.path[#track.path]
	local kind = descriptor and descriptor.kind
		or last
			and last.class == "Bone"
			and ({ IK = "root", Spine = "spine", UpperTorso = "upper" })[last.name]
	if not kind then
		return nil
	end

	local ownerPath = descriptor and descriptor.owner or table.clone(track.path)
	if not descriptor then
		table.remove(ownerPath)
	end

	local ownerPart = resolve(rig, ownerPath)
	local owner = ownerPart and state.MotorByPart[ownerPart]
	if not owner then
		for candidate in state.DefaultPose do
			if candidate.Part1 == ownerPart then
				owner = candidate
				break
			end
		end
	end

	if not require("customRest").isJoint(owner) then
		return nil
	end

	local bone
	if descriptor then
		if descriptor.customIK == true then
			assert(
				require("customRest").chain(rig, owner, require("Parenting").collectMotors(rig)),
				"Saved custom IK chain is no longer connected"
			)
			owner:SetAttribute("EclipseAutoIK", true)
			require("customRest").restoreRest(
				owner,
				descriptor.customRest and decode(descriptor.customRest)
			)
			require("LimbIK").invalidate(rig)
		end

		bone = R6Controls.ensure(owner, kind, decode(descriptor.rest))

		bone:SetAttribute(
			"EclipseIKControlSpace",
			decode(descriptor.attributes).EclipseIKControlSpace
		)
		bone:SetAttribute(
			"EclipseIKAnchorOffset",
			decode(descriptor.attributes).EclipseIKAnchorOffset
		)
		for name, value in decode(descriptor.attributes) do
			bone:SetAttribute(name, value)
		end

		if
			descriptor.customIK
			and R6Controls.rigRoot(rig, owner.Part0)
			and not decode(descriptor.attributes).EclipseIKControlSpace
			and not decode(descriptor.attributes).EclipseIKAnchorOffset
		then
			bone:SetAttribute("EclipseIKControlSpace", nil)
			local first, offset
			for _, saved in archive and archive.tracks or {} do
				if resolve(rig, saved.path) == ownerPart then
					for _, record in saved.keys do
						local key = decode(record.data)
						if
							key.IKAnchor
							and key.IKRigWorld
							and (not first or record.frame < first)
						then
							first = record.frame
							offset = key.IKRigWorld:ToObjectSpace(key.IKAnchor)
						end
					end
				end
			end

			bone:SetAttribute("EclipseIKAnchorOffset", offset)
		end
	else
		local ik = require("LimbIK")
		local chain = ik.chain(rig, owner)
		if not chain or (chain.kind ~= "R6" and chain.kind ~= "Torso") then
			return nil
		end

		ik.prepare(chain)
		bone = R6Controls.find(owner, kind)
	end

	if not bone then
		return nil
	end

	local motor = R6Controls.get(bone)
	if descriptor and descriptor.customIK then
		R6Controls.anchor(owner, kind)
	end

	state.DefaultPose[motor] = descriptor and decode(descriptor.rest) or bone.CFrame
	state.MotorByPart[bone], state.ParentingDefaults[motor] = motor, true
	return bone
end

local function restoreAttachment(rig, data, state)
	if not require("CameraRig").isRig(rig) then
		return
	end

	for _, track in data.tracks do
		local last = track.path and track.path[#track.path]
		if last and last.name == "AttachToPart" then
			for _, record in track.keys or {} do
				if decode(record.data).CamAttachTarget ~= nil then
					local motor = require("Target").ensureAttachment(rig)
					if motor then
						state.DefaultPose[motor] = state.DefaultPose[motor] or CFrame.identity
						state.MotorByPart[motor.Part1] = motor
						state.ParentingDefaults[motor] = true
					end

					return
				end
			end
		end
	end
end

function Storage.prepareRead(sequence, rig, state, budget, layered)
	local source = sequence:FindFirstChild(NAME)
	if not source then
		return nil, {}
	end

	local data = Data.decodeJson(Data.read(source), budget, layered == true)
	assert(data.version == 1 or data.version == 2, "Unsupported keyframe data version")
	restoreAttachment(rig, data, state)
	local motors = {}
	for _, track in data.tracks do
		local part = resolve(rig, track.path)
		local motor = part and state.MotorByPart[part]
		if track.jointPath then
			motor = resolve(rig, track.jointPath)
			if not motor or not motor:IsA("Motor6D") or motor.Part1 ~= part then
				motor = nil
			end
		end

		if not motor and part and not track.jointPath then
			for candidate in state.DefaultPose do
				if candidate.Part1 == part then
					motor = candidate
					break
				end
			end
		end

		if motor then
			motors[motor] = true
		end
	end

	return data, motors
end

local function restoreQuaternionVersion(snapshot, samples)
	local ordered = {}
	for _, key in snapshot do
		table.insert(ordered, key)
	end

	table.sort(ordered, function(a, b)
		return a.Time < b.Time
	end)
	local version = 2
	local oldError, newError, count = 0, 0, 0
	local Interp = require("Interp")

	local function errorSquared(a, b)
		return (a.RightVector - b.RightVector).Magnitude ^ 2
			+ (a.UpVector - b.UpVector).Magnitude ^ 2
			+ (a.LookVector - b.LookVector).Magnitude ^ 2
	end

	for _, sample in samples or {} do
		checkpoint()
		local left, right
		for i = 1, #ordered - 1 do
			if
				sample.time > ordered[i].Time + 1e-5
				and sample.time < ordered[i + 1].Time - 1e-5
			then
				left, right = ordered[i], ordered[i + 1]
				break
			end
		end

		if
			left
			and not left.QuaternionInterpolationVersion
			and Interp.usesAutomaticBezier(left, right)
		then
			local alpha = (sample.time - left.Time) / (right.Time - left.Time)
			local modern = Interp.cframe(snapshot, left, right, alpha, "C0")
			left.QuaternionInterpolationVersion = 1
			local old = Interp.cframe(snapshot, left, right, alpha, "C0")
			left.QuaternionInterpolationVersion = nil
			if modern and old then
				newError += errorSquared(modern, sample.c0)
				oldError += errorSquared(old, sample.c0)
				count += 1
			end
		end
	end

	if count >= 2 and oldError < count * 1e-6 and newError > oldError + count * 1e-5 then
		version = 1
	end

	for _, key in ordered do
		key.QuaternionInterpolationVersion = key.QuaternionInterpolationVersion or version
	end
end

function Storage.read(
	sequence,
	rig,
	timeline,
	sanitize,
	prepared,
	budget,
	targetPivot,
	rotationEvidence
)
	local planted = sequence:GetAttribute("EclipseIKFeetPlanted")
	if type(planted) == "boolean" then
		rig:SetAttribute("EclipseIKFeetPlanted", planted)
	end

	rig:SetAttribute("EclipseIKSettingsVersion", 2)
	local bend = sequence:GetAttribute("EclipseR6BendPercent")
	if sequence:GetAttribute("EclipseIKSettingsVersion") ~= 2 and bend == 74.2 then
		bend = 65
	end

	if typeof(bend) == "number" and bend == bend then
		rig:SetAttribute("EclipseR6BendPercent", math.clamp(bend, 0, 100))
	end

	local function readModifiers()
		local modifierSource = sequence:FindFirstChild("EclipseCurveModifiers")
		if not modifierSource then
			return
		end

		local decoded = Http:JSONDecode(Data.read(modifierSource))
		local modifierState = timeline:GetState()
		require("Mods").load(decoded.tracks, modifierState, function(path)
			local part = resolve(rig, path)
			local motor = part and modifierState.MotorByPart[part]
			if not motor and part then
				for candidate in modifierState.DefaultPose do
					if candidate.Part1 == part then
						motor = candidate
						break
					end
				end
			end

			return motor
		end)
	end

	local source = sequence:FindFirstChild(NAME)
	if not source then
		readModifiers()
		return
	end

	local data = prepared or Data.decodeJson(Data.read(source), budget)
	assert(data.version == 1 or data.version == 2, "Unsupported keyframe data version")
	local state = timeline:GetState()
	restoreAttachment(rig, data, state)
	local legacyWorld = {}
	local hasMaster = MasterControl.get(rig) ~= nil
	for _, track in data.tracks do
		local part = resolve(rig, track.path)
		if track.control or not part then
			part = restoreControl(rig, track, state, data) or part
		end

		local motor = part and state.MotorByPart[part]
		if track.jointPath then
			motor = resolve(rig, track.jointPath)
			if not motor or not motor:IsA("Motor6D") or motor.Part1 ~= part then
				motor = nil
			end
		end

		if not motor and not track.jointPath then
			for candidate in state.DefaultPose do
				if candidate.Part1 == part then
					motor = candidate
					break
				end
			end
		end

		if not motor then
			assert(
				sequence:GetAttribute("EclipseRawRecovery") ~= true or #track.keys == 0,
				"Recovery is missing an attached object or joint. Restore the matching Studio place before reopening this recovery copy."
			)
			continue
		end

		if track.rest then
			state.DefaultPose[motor] = require("PoseSpace").scaleTranslation(
				decode(track.rest),
				require("PoseSpace").savedRatio(rig, sequence)
			)
		end

		if track.world then
			local space = require("PoseSpace")
			state.DefaultWorldPose[motor] = space.retargetWorld(
				decode(track.world),
				space.savedRatio(rig, sequence),
				sequence:GetAttribute("EclipseAuthoredPivot"),
				targetPivot or space.getImportPivot(rig, sequence)
			)
		end

		if track.parented ~= nil then
			state.ParentingDefaults[motor] = track.parented
		end

		if
			track.size
			and (
				state.DefaultSize[part] == nil
				or sequence:GetAttribute("EclipseRawRecovery") == true
			)
		then
			state.DefaultSize[part] = decode(track.size)
				* require("PoseSpace").savedRatio(rig, sequence)
		end

		local snapshot = {}
		for _, record in track.keys do
			if budget then
				budget()
			end

			local key = decode(record.data, budget)
			key._EclipseRawStored = true
			key.Frame, key.Time = record.frame, record.frame / state.FPS
			key.Motor, key.Part, key.SanitizeName = motor, part, sanitize
			snapshot[record.frame] = key
			if hasMaster and key.WorldCFrame and not key.MasterWorld then
				table.insert(legacyWorld, key)
			end

			timeline:EnsureTimelineEnd(record.frame)
		end

		restoreQuaternionVersion(
			snapshot,
			not data.quaternionInterpolation
				and rotationEvidence
				and rotationEvidence[motor]
				and rotationEvidence[motor].samples
		)
		timeline:_restoreMotorBucket(motor, snapshot, state._ImportingKeyframes, budget)
	end

	for _, record in legacyWorld do
		if budget then
			budget()
		end

		local key = state.Keyframes[record.Motor] and state.Keyframes[record.Motor][record.Frame]
		if key then
			local delta = MasterControl.worldDelta(record.Motor, function(motor, time)
				return timeline:EvaluateMotorC0(motor, time)
			end, record.Time)
			if delta and delta ~= CFrame.identity then
				key.MasterWorld = delta
			end
		end
	end

	readModifiers()
	if timeline.CaptureDefaultPoseAdditive then
		timeline:CaptureDefaultPoseAdditive(rig)
	end
end

function Storage.writePhysics(sequence, rig, state)
	Physics.write(sequence, rig, state, encode, pathOf)
end

function Storage.preparePhysics(sequence, rig, budget)
	return Physics.prepareRead(sequence, rig, resolve, budget)
end

function Storage.readPhysics(sequence, rig, timeline, sanitize, prepared, budget, targetPivot)
	Physics.read(sequence, rig, timeline, function(value)
		return decode(value, budget)
	end, resolve, sanitize, prepared, budget, targetPivot)
end

Storage.encode = encode
Storage.decode = decode
return Storage
