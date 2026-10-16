-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Paths = require("Paths")
local Codec = require("ArmatureAnimation")
local ValueCodec = require("ValueCodec")
local Armature = require("ArmatureRuntime")
local Parenting = require("Parenting")
local Master = require("MasterControl")
local Events = require("Events")
local History = require("History")
local LimbIK = require("LimbIK")
local Animation = {}

local r15Parents = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	RightHand = "RightLowerArm",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
	LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	RightFoot = "RightLowerLeg",
}

local function r15Motors(rig)
	local result = {}
	for _, motor in Parenting.collectMotors(rig) do
		if typeof(motor) == "Instance" and motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local name = motor.Part1.Name
			if r15Parents[name] then
				if result[name] or motor.Part0.Name ~= r15Parents[name] then
					return nil
				end

				result[name] = motor
			end
		end
	end

	for name in r15Parents do
		if not result[name] then
			return nil
		end
	end

	return result
end

local function r15Name(path)
	if type(path) ~= "string" or path:sub(1, 1) ~= "[" then
		return nil
	end

	local ok, steps =
		pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), path)
	local last = ok and type(steps) == "table" and steps[#steps]
	return type(last) == "table" and last[2] ~= "Bone" and r15Parents[last[1]] and last[1] or nil
end

local function r15Source(data)
	local names = {}
	for path in data.native or {} do
		local name = r15Name(path)
		if name then
			if names[name] then
				return false
			end

			names[name] = true
		end
	end

	for name in r15Parents do
		if not names[name] then
			return false
		end
	end

	return true
end

local function r15ScaleRatio(data, rig, motors)
	if type(data.scale) == "number" and data.scale > 0 and data.scale < math.huge then
		return require("PoseSpace").getRigScale(rig) / data.scale
	end

	local ratio
	for path, values in data.native or {} do
		local name = r15Name(path)
		local motor = name and motors and motors[name]
		if motor and typeof(values.size) == "Vector3" then
			for _, axis in { "X", "Y", "Z" } do
				if values.size[axis] <= 0 then
					return 1
				end

				local value = motor.Part1.Size[axis] / values.size[axis]
				if ratio and math.abs(value - ratio) > 1e-4 then
					return 1
				end

				ratio = value
			end
		end
	end

	return ratio or 1
end

local function rebaseKey(key, source, target, timeline, ratio)
	if key.Parented == false or not key.C0 or ratio == 1 and source:FuzzyEq(target, 1e-6) then
		return
	end

	local delta = target * source:Inverse()
	local before = timeline:DecomposeC0(key.C0)
	for _, field in { "C0", "ChannelPoseC0", "IKBaseC0" } do
		if typeof(key[field]) == "CFrame" then
			key[field] = target
				* require("PoseSpace").scaleTranslation(source:ToObjectSpace(key[field]), ratio)
		end
	end

	local after = timeline:DecomposeC0(key.C0)
	local seen = {}
	for _, collection in { key.Channels or {}, key.GraphCurves or {} } do
		for id, point in collection do
			if before[id] and after[id] and type(point) == "table" and not seen[point] then
				seen[point] = true
				local factor = id:sub(1, 4) == "loc_" and ratio or 1
				local shift = after[id] - before[id] * factor
				if type(point.Value) == "number" then
					point.Value = point.Value * factor + shift
				end

				for _, side in { "In", "Out" } do
					if point[side] then
						point[side][2] = point[side][2] * factor + shift
					end
				end

				if factor ~= 1 or math.abs(shift) > 1e-6 then
					point.BlenderHandles = nil
				end
			end
		end
	end

	for _, field in { "PathTangentIn", "PathTangentOut" } do
		if typeof(key[field]) == "Vector3" then
			key[field] = delta:VectorToWorldSpace(key[field]) * ratio
		end
	end

	key.Position, key.Rotation = key.C0.Position, key.C0.Rotation
end

local function copy(value)
	return ValueCodec.decode(ValueCodec.encode(value))
end

local function native(rig)
	local values = {}
	local origin = rig:GetPivot()
	for _, object in rig:GetDescendants() do
		if Paths.excluded(object, rig) then
			continue
		end

		if object:IsA("BasePart") and not object:GetAttribute("EclipseArmatureBone") then
			values[Paths.of(object, rig)] =
				{ frame = origin:ToObjectSpace(object.CFrame), size = object.Size }
		elseif object:IsA("Bone") then
			values[Paths.of(object, rig)] = { transform = object.Transform }
		end
	end

	return values
end

local function appearance(rig)
	local values = {}
	for _, object in rig:GetDescendants() do
		if Paths.excluded(object, rig) then
			continue
		end

		if object:IsA("Decal") or object:IsA("Texture") then
			values[Paths.of(object, rig)] = {
				Texture = object.Texture,
				Color3 = object.Color3,
				Transparency = object.Transparency,
				Face = object.Face,
			}
		elseif object:IsA("Shirt") then
			values[Paths.of(object, rig)] = { ShirtTemplate = object.ShirtTemplate }
		elseif object:IsA("Pants") then
			values[Paths.of(object, rig)] = { PantsTemplate = object.PantsTemplate }
		end
	end

	return values
end

function Animation.capture(rig, timeline, kind, buildPreview, selectedMotors)
	local state = timeline:GetState()
	local data = {
		version = 1,
		kind = kind,
		fps = state.FPS,
		sourceFrame = timeline:TimeToFrame(state.CurrentTime),
		scale = require("PoseSpace").getRigScale(rig),
		origin = rig:GetPivot(),
		tracks = {},
		native = native(rig),
		appearance = appearance(rig),
		preview = {},
	}
	local master = Master.get(rig, true)
	data.master = (not selectedMotors or selectedMotors[master])
			and master
			and Master.enabled(rig)
			and {
				enabled = true,
				rest = master.DefaultC0,
				radius = rig:GetAttribute("EclipseMasterRadius"),
			}
		or nil
	local last = 0
	for _, motor in Parenting.collectMotors(rig) do
		if selectedMotors and not selectedMotors[motor] then
			continue
		end

		local id = Paths.motor(motor, rig)
		if not id then
			continue
		end

		local track = { id = id, default = state.DefaultPose[motor] or motor.C0, keys = {} }
		if typeof(motor) == "table" and motor.IsEclipseR6Control then
			track.control = {
				customRest = require("customRest").rest(motor.Owner),
				customIK = motor.Owner:GetAttribute("EclipseAutoIK") == true or nil,
				owner = Paths.motor(motor.Owner, rig),
				kind = motor:GetAttribute("EclipseR6Control"),
				rest = motor.Bone.CFrame,
			}
		end

		if kind == "Poses" then
			local key = {
				C0 = motor.C0,
				Time = 0,
				Frame = 0,
				Parented = Parenting.isParentedAt(
					motor,
					state.Keyframes[motor],
					state.CurrentTime,
					state.ParentingDefaults[motor]
				),
				EasingStyle = "Linear",
			}
			if not key.Parented then
				key.WorldCFrame = Parenting.worldOf(motor, state.MotorByPart)
				key.MasterWorld = Master.worldDelta(motor)
			end

			local previous = Parenting.bounds(state.Keyframes[motor], state.CurrentTime)
			if previous then
				for _, field in
					{
						"CamTargetAnchor",
						"HS",
						"HSRotation",
						"HSLocalRotation",
						"HSRestoreParented",
					}
				do
					key[field] = previous[field]
				end
			end

			local chain = LimbIK.chain(rig, motor)
			if chain then
				key.IK = LimbIK.isEnabled(motor, state.CurrentTime)
				if key.IK then
					LimbIK.state(chain, state.CurrentTime)
				end
			end

			key.Time = state.CurrentTime
			LimbIK.captureKey(motor, key)
			key.Time = 0
			local part = motor.Part1
			local size = state.DefaultSize and state.DefaultSize[part]
			local scale
			if typeof(motor) == "table" and motor.IsEclipseArmatureControl then
				scale = motor.InputScale
			elseif size and part:IsA("BasePart") then
				scale = part.Size / size
			end

			if scale then
				key.Channels = {}
				for id, value in timeline:DecomposeC0(key.C0) do
					key.Channels[id] = { Value = value }
				end

				key.WholePoseScale = { scale_x = scale.X, scale_y = scale.Y, scale_z = scale.Z }
				for id, value in key.WholePoseScale do
					key.Channels[id] = { Value = value }
				end
			end

			track.keys[1] = copy(key)
		else
			for frame, key in state.Keyframes[motor] or {} do
				local value = copy(key)
				value.Frame = frame
				value.Time = frame / state.FPS
				table.insert(track.keys, value)
				last = math.max(last, frame)
			end

			table.sort(track.keys, function(a, b)
				return a.Frame < b.Frame
			end)
		end

		if #track.keys > 0 then
			table.insert(data.tracks, track)
		end
	end

	data.properties = kind == "Poses" and Armature.properties(rig) or Codec.propertySnapshot(rig)
	if selectedMotors then
		assert(#data.tracks > 0, "Select at least one bone to save a partial pose.")
		data.partial = true

		data.appearance = {}
		data.properties = {}
	end

	if kind == "Animations" then
		data.events = Events.snapshot(Events.get(rig))
		data.subtitles = Events.snapshot(Events.subtitleTrack())
		for _, event in data.subtitles.Events do
			last = math.max(last, event.Frame + event.Subtitle.Duration)
		end

		for _, event in data.events.Events do
			last = math.max(last, event.Frame + (event.Duration or 0))
		end

		for _, track in data.properties.tracks do
			for _, key in track.keys do
				last = math.max(last, key.frame)
			end
		end

		data.duration = last / state.FPS
		assert(buildPreview, "Animation preview isn't ready.")
		local sequence = buildPreview(rig, function(motor, key, frame, c0, baked)
			local path = Paths.of(motor.Part1, rig)
			if not path then
				return
			end

			local track = data.preview[path]
			if not track then
				track = {}
				data.preview[path] = track
			end

			local sample = copy(key)
			sample.C0 = c0
			sample.Time = frame / state.FPS
			sample.Frame = frame
			if baked then
				sample.EasingStyle = "Linear"
				sample.HandleType = "Vector"
			end

			table.insert(track, sample)
		end)
		if sequence then
			sequence:Destroy()
		end

		for _, track in data.preview do
			table.sort(track, function(a, b)
				return a.Time < b.Time
			end)
		end
	end

	return data
end

local worldFrames = {
	WorldCFrame = true,
	CamTargetAnchor = true,
	IKAnchor = true,
	IKRigWorld = true,
	IKRoot = true,
	IKBaseWorld = true,
}
local worldPoints = { IKTarget = true, IKPole = true }

local function resolveTracks(data, rig, motors)
	local plans = {}
	local kinds = {
		root = "IK",
		spine = "Spine",
		upper = "UpperTorso",
		target = "IKTarget",
		pole = "IKPole",
		roll = "FootRoll",
	}
	local Http = game:GetService("HttpService")
	for _, track in data.tracks do
		if (motors[track.id] and not track.control) or track.id == "master" and data.master then
			continue
		end

		local control = track.control
		if not control then
			local ok, path = pcall(Http.JSONDecode, Http, track.id)
			if ok and type(path) == "table" and #path > 1 then
				local last = path[#path]
				if type(last) == "table" and last[2] == "Bone" and last[3] == 1 then
					for kind, name in kinds do
						if last[1] == name then
							local parent = table.clone(path)
							table.remove(parent)
							control = {
								owner = Http:JSONEncode(parent),
								kind = kind,
								rest = track.default,
							}
							break
						end
					end
				end
			end
		end

		local owner = control and motors[control.owner]
		assert(
			control
				and kinds[control.kind]
				and typeof(control.rest) == "CFrame"
				and require("customRest").isJoint(owner),
			"This save uses different bones. Insert its rig from the card menu, or select a matching rig."
		)

		local existing = owner.Part1:FindFirstChild(kinds[control.kind])
		assert(
			not existing
				or existing:IsA("Bone")
					and existing:GetAttribute("EclipseR6Control") == control.kind,
			"This save's IK control conflicts with an existing bone."
		)
		if control.customIK then
			assert(
				require("customRest").chain(rig, owner, Parenting.collectMotors(rig)),
				"Saved custom IK chain is no longer connected"
			)
		end

		table.insert(plans, {
			track = track,
			owner = owner,
			kind = control.kind,
			rest = control.rest,
			customIK = control.customIK,
			customRest = control.customRest,
		})
	end

	return plans
end

function Animation.apply(data, rig, timeline, sanitize, refreshStructure)
	local state = timeline:GetState()
	local at = timeline:TimeToFrame(state.CurrentTime)
	local targetOrigin = rig:GetPivot()
	local worldDelta = targetOrigin * data.origin:Inverse()
	local motors = {}
	for _, motor in Parenting.collectMotors(rig) do
		local id = Paths.motor(motor, rig)
		if id then
			motors[id] = motor
		end
	end

	local r15 = r15Source(data) and r15Motors(rig)
	local poseRatio = r15 and r15ScaleRatio(data, rig, r15) or 1
	if r15 then
		for _, track in data.tracks do
			local name = r15Name(track.id)
			if name and not track.control and not motors[track.id] then
				motors[track.id] = r15[name]
			end

			if track.control then
				local ownerName = r15Name(track.control.owner)
				if ownerName and not motors[track.control.owner] then
					motors[track.control.owner] = r15[ownerName]
				end
			end
		end
	end

	local controlPlans = resolveTracks(data, rig, motors)
	local customOwners = {}
	for _, plan in controlPlans do
		if plan.customIK and not customOwners[plan.owner] then
			customOwners[plan.owner] = {
				before = plan.owner:GetAttribute("EclipseAutoIK"),
				beforeRest = require("customRest").rest(plan.owner),
				afterRest = plan.customRest,
			}
		end
	end

	local oldMaster = Master.get(rig, true)
	local beforeMaster = oldMaster and { enabled = Master.enabled(rig), c0 = oldMaster.C0 }
	if data.master and data.master.enabled and not motors.master then
		motors.master = Master.setEnabled(rig, true)
		if motors.master then
			timeline:CaptureDefaultPoseAdditive(rig)
			timeline:InvalidateMotorListCache()
			if refreshStructure then
				refreshStructure(rig)
			end
		end
	end

	local before, after = {}, {}
	local beforeProperties = Codec.propertySnapshot(rig)
	local propertyValues = Armature.isRig(rig) and Armature.snapshot(rig)
	local eventTrack = Events.get(rig)
	local beforeEvents = Events.snapshot(eventTrack)
	local beforeSubtitles = Events.snapshot(Events.subtitleTrack())
	local afterSubtitles
	local changes = {}
	for path, values in data.appearance or {} do
		local object = Paths.resolve(rig, path)
		if object then
			local old = {}
			for key in values do
				old[key] = object[key]
			end

			table.insert(changes, { object = object, before = old, after = values })
		end
	end

	local function restore(buckets, properties, events, which)
		for owner, values in customOwners do
			if which == "before" then
				owner:SetAttribute("EclipseAutoIK", values.before)
				require("customRest").restoreRest(owner, values.beforeRest)
			else
				owner:SetAttribute("EclipseAutoIK", true)
				require("customRest").restoreRest(owner, values.afterRest)
			end
		end

		if next(customOwners) then
			LimbIK.invalidate(rig)
		end

		for motor, bucket in buckets do
			timeline:_restoreMotorBucket(motor, bucket)
		end

		Codec.restoreProperties(rig, properties)
		Events.restore(eventTrack, events)
		Events.restore(
			Events.subtitleTrack(),
			which == "before" and beforeSubtitles or afterSubtitles
		)
		for _, change in changes do
			if change.object.Parent then
				for key, value in change[which] do
					change.object[key] = value
				end
			end
		end

		if which == "before" then
			if beforeMaster then
				Master.setEnabled(rig, beforeMaster.enabled)
				Master.get(rig, true).C0 = beforeMaster.c0
			elseif motors.master then
				Master.setEnabled(rig, false)
			end

			if propertyValues then
				Armature.restore(rig, propertyValues)
			end
		elseif data.master then
			Master.setEnabled(rig, data.master.enabled)
		end

		timeline:InvalidateMotorListCache()
		if refreshStructure and (data.master or next(customOwners)) then
			refreshStructure(rig)
		end

		timeline:ApplyPoseAtTime(rig, state.CurrentTime, { OnlyRig = true })
	end

	local createdControls = {}
	local ok, err = xpcall(function()
		local Controls = require("R6Controls")
		for owner, values in customOwners do
			owner:SetAttribute("EclipseAutoIK", true)
			require("customRest").restoreRest(owner, values.afterRest)
		end

		if next(customOwners) then
			LimbIK.invalidate(rig)
		end

		for _, plan in controlPlans do
			local existing = Controls.find(plan.owner, plan.kind)
			local bone = Controls.ensure(plan.owner, plan.kind, plan.rest)
			if not existing then
				table.insert(createdControls, bone)
			end

			motors[plan.track.id] = assert(Controls.get(bone), "Could not create saved IK control")
		end

		if #controlPlans > 0 then
			timeline:CaptureDefaultPoseAdditive(rig)
			timeline:InvalidateMotorListCache()
			if refreshStructure then
				refreshStructure(rig)
			end
		end

		for _, track in data.tracks do
			local motor = assert(motors[track.id], "This rig doesn't have a master control.")
			before[motor] = timeline:_snapshotMotorBucket(motor)
			local combined = table.clone(before[motor])
			for _, saved in track.keys do
				local key = copy(saved)
				if r15 and r15[motor.Part1.Name] == motor and typeof(track.default) == "CFrame" then
					rebaseKey(
						key,
						track.default,
						state.DefaultPose[motor] or motor.C0,
						timeline,
						poseRatio
					)
				end

				if key.MasterWorld then
					key.MasterWorld = worldDelta * key.MasterWorld * worldDelta:Inverse()
				end

				local frame = at
					+ (data.kind == "Poses" and 0 or math.round(saved.Time * state.FPS))
				for field in worldFrames do
					if typeof(key[field]) == "CFrame" then
						key[field] = worldDelta * key[field]
					end
				end

				for field in worldPoints do
					local value = key[field]
					if typeof(value) == "CFrame" then
						key[field] = worldDelta * value
					elseif typeof(value) == "Vector3" then
						key[field] = worldDelta:PointToWorldSpace(value)
					end
				end

				if typeof(key.HSRotation) == "CFrame" then
					key.HSRotation = worldDelta.Rotation * key.HSRotation
				end

				if key.Parented == false then
					for _, field in { "PathTangentIn", "PathTangentOut" } do
						if key[field] then
							key[field] = worldDelta:VectorToWorldSpace(key[field])
						end
					end
				end

				key.Frame, key.Time, key.Motor, key.Part, key.SanitizeName =
					frame, frame / state.FPS, motor, motor.Part1, sanitize
				if key.C0 then
					key.Position, key.Rotation = key.C0.Position, key.C0.Rotation
				end

				for _, curve in key.GraphCurves or {} do
					if curve.In then
						curve.In[1] *= state.FPS / data.fps
					end

					if curve.Out then
						curve.Out[1] *= state.FPS / data.fps
					end
				end

				combined[frame] = key
				timeline:EnsureTimelineEnd(frame)
			end

			timeline:_restoreMotorBucket(motor, combined)
			after[motor] = timeline:_snapshotMotorBucket(motor)
		end

		local properties = copy(beforeProperties)
		local byId = {}
		for _, track in properties.tracks do
			byId[track.id] = track
		end

		local incoming = {}
		if data.kind == "Poses" then
			for _, property in data.properties do
				local id = game:GetService("HttpService")
					:JSONEncode({ property.object, property.bone or "", property.key })
				table.insert(incoming, {
					id = id,
					object = property.object,
					bone = property.bone,
					key = property.key,
					default = property.default,
					keys = { { frame = 0, value = property.value } },
				})
			end
		else
			incoming = data.properties.tracks
		end

		for _, saved in incoming do
			local track = byId[saved.id]
			if not track then
				track = copy(saved)
				track.keys = {}
				table.insert(properties.tracks, track)
				byId[track.id] = track
			end

			for _, key in saved.keys do
				local frame = at + math.round(key.frame / data.fps * state.FPS)
				for i = #track.keys, 1, -1 do
					if track.keys[i].frame == frame then
						table.remove(track.keys, i)
					end
				end

				table.insert(track.keys, { frame = frame, value = key.value })
				timeline:EnsureTimelineEnd(frame)
			end

			table.sort(track.keys, function(a, b)
				return a.frame < b.frame
			end)
		end

		Codec.restoreProperties(rig, properties)
		if data.events then
			for _, event in data.events.Events do
				local item = copy(event)
				item.Id = game:GetService("HttpService"):GenerateGUID(false)
				item.Frame =
					Events.nextFrame(eventTrack, at + math.round(item.Frame / data.fps * state.FPS))
				item.Duration = math.round((item.Duration or 0) / data.fps * state.FPS)
				item.Subtitle = require("SubtitleData").rescale(item.Subtitle, state.FPS / data.fps)
				eventTrack.Events[item.Id] = item
				timeline:EnsureTimelineEnd(item.Frame + item.Duration)
			end

			Events.migrateSubtitles(eventTrack)
			Events.changed(eventTrack)
		end

		local subtitleTrack = Events.subtitleTrack()
		for _, event in data.subtitles and data.subtitles.Events or {} do
			local item = copy(event)
			item.Id = game:GetService("HttpService"):GenerateGUID(false)
			item.Frame = at + math.round(item.Frame / data.fps * state.FPS)
			item.Subtitle = require("SubtitleData").rescale(item.Subtitle, state.FPS / data.fps)
			subtitleTrack.Events[item.Id] = item
			timeline:EnsureTimelineEnd(item.Frame + item.Subtitle.Duration)
		end

		if data.events or data.subtitles then
			Events.changed(subtitleTrack)
		end

		afterSubtitles = Events.snapshot(subtitleTrack)
		for _, change in changes do
			for key, value in change.after do
				change.object[key] = value
			end
		end

		timeline:ApplyPoseAtTime(rig, state.CurrentTime, { OnlyRig = true })
		local afterProperties, afterEvents =
			Codec.propertySnapshot(rig), Events.snapshot(eventTrack)
		History.record(function()
			restore(before, beforeProperties, beforeEvents, "before")
		end, function()
			restore(after, afterProperties, afterEvents, "after")
		end, "Insert " .. (data.kind == "Poses" and "pose" or "animation"), at)
	end, debug.traceback)
	if not ok then
		restore(before, beforeProperties, beforeEvents, "before")
		for _, bone in createdControls do
			bone:Destroy()
		end

		timeline:InvalidateMotorListCache()
		if #createdControls > 0 and refreshStructure then
			refreshStructure(rig)
		end

		error(err, 0)
	end

	return true
end

return Animation
