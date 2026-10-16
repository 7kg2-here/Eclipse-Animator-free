--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Solver = require("Dynamics")
local Cache = require("Cache")
local Pose = require("RigPose")
local Master = require("MasterControl")
local BoneMotor = require("BoneMotor")
local Cleanup = require("KeyframeCleanup")
local Bake = {}

local function dynamicBone(bone)
	return bone:IsA("Bone") and not bone:GetAttribute("EclipseR6Control")
end

function Bake.meshes(rig)
	local found = {}
	for _, object in rig:GetDescendants() do
		if object:IsA("BasePart") then
			for _, bone in object:GetDescendants() do
				if dynamicBone(bone) then
					table.insert(found, object)
					break
				end
			end
		end
	end

	table.sort(found, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return found
end

local function roots(mesh)
	local all, result, names = {}, {}, {}
	for _, bone in mesh:GetDescendants() do
		if dynamicBone(bone) then
			assert(
				not names[bone.Name],
				"Bone Dynamics needs unique bone names within each mesh: " .. bone.Name
			)
			names[bone.Name] = bone
			table.insert(all, bone)
		end
	end

	local configured = mesh:GetAttribute("Roots")
	if type(configured) == "string" and configured:match("%S") then
		for name in configured:gmatch("[^,]+") do
			name = name:match("^%s*(.-)%s*$")
			table.insert(result, assert(names[name], "Missing Bone Dynamics root: " .. name))
		end
	else
		for _, bone in all do
			if not bone.Parent:IsA("Bone") then
				table.insert(result, bone)
			end
		end
	end

	for i, a in result do
		for j, b in result do
			assert(
				i == j or (a ~= b and not a:IsDescendantOf(b)),
				"Bone Dynamics roots must not overlap"
			)
		end
	end

	table.sort(result, function(a, b)
		return a.Name < b.Name
	end)
	return result, all
end

Bake.roots = roots

function Bake.path(rig, object)
	local path = {}
	while object and object ~= rig do
		local parent = object.Parent
		assert(parent, "The selected chain was removed")
		local index = 0
		for _, sibling in parent:GetChildren() do
			if sibling.Name == object.Name and sibling.ClassName == object.ClassName then
				index += 1
			end

			if sibling == object then
				break
			end
		end

		table.insert(path, 1, { object.Name, object.ClassName, index })
		object = parent
	end

	assert(object == rig, "Select a chain belonging to this rig")
	return game.HttpService:JSONEncode(path)
end

local function nativeMotor(m, rig)
	return m:IsA("Motor6D")
		and (m.Enabled or m:GetAttribute("EclipseConstraintProxy") == true)
		and m.Part0
		and m.Part1
		and m.Part0:IsDescendantOf(rig)
		and m.Part1:IsDescendantOf(rig)
end

function Bake.motors(rig)
	local list = {}
	for _, m in rig:GetDescendants() do
		if nativeMotor(m, rig) then
			table.insert(list, m)
		end
	end

	table.sort(list, function(a, b)
		return Bake.path(rig, a) < Bake.path(rig, b)
	end)
	return list
end

function Bake.selection(rig, state)
	local selected = {}

	local function add(m)
		local object = typeof(m) == "table" and rawget(m, "_bone") or m
		if
			typeof(object) == "Instance"
			and object:IsDescendantOf(rig)
			and (dynamicBone(object) or nativeMotor(object, rig))
		then
			selected[Bake.path(rig, object)] = true
		end
	end

	for item in state.Rig and state.Rig._selectedItems or {} do
		local row = item.parentBoneItem or item
		if row.fetchMotor then
			add(row:fetchMotor())
		end
	end

	if state.Axis and state.Rig then
		for _, bone in state.Axis:GetSelectedBones() do
			local part = state.Rig:GetPartFromBone(rig, bone)
			if part then
				add(state.Rig:GetMotorForPart(rig, part))
			end
		end
	end

	for _, object in game:GetService("Selection"):Get() do
		add(object)
		if object:IsA("BasePart") then
			for _, m in Bake.motors(rig) do
				if m.Part1 == object then
					add(m)
				end
			end
		end
	end

	local paths = {}
	for path in selected do
		table.insert(paths, path)
	end

	table.sort(paths)
	assert(#paths > 0, "Select bones or Motor6D joints in the timeline or Explorer first")
	return game.HttpService:JSONEncode(paths), #paths
end

local function selectionMask(rig, encoded)
	if not encoded or encoded == "" then
		return nil
	end

	local paths = game.HttpService:JSONDecode(encoded)
	assert(type(paths) == "table" and #paths > 0, "Select at least one chain")
	local found = {}
	for _, object in rig:GetDescendants() do
		if dynamicBone(object) or nativeMotor(object, rig) then
			found[Bake.path(rig, object)] = object
		end
	end

	local selected = {}
	for _, path in paths do
		selected[assert(found[path], "A selected chain changed. Select the chains again.")] = true
	end

	return selected
end

local function boneRoots(mesh, mask)
	if not mask then
		return roots(mesh)
	end

	local selected, all = {}, {}
	for _, bone in mesh:GetDescendants() do
		if dynamicBone(bone) then
			table.insert(all, bone)
			if mask[bone] then
				local parent = bone.Parent
				local covered = false
				while parent and parent ~= mesh do
					if mask[parent] then
						covered = true
						break
					end

					parent = parent.Parent
				end

				if not covered then
					table.insert(selected, bone)
				end
			end
		end
	end

	local names = {}
	for _, bone in all do
		assert(
			not names[bone.Name],
			"Bone Dynamics needs unique bone names within each mesh: " .. bone.Name
		)
		names[bone.Name] = true
	end

	return selected, all
end

local function motorWorker(rig, motors, mask)
	if mask then
		local selected = false
		for _, m in motors do
			if mask[m] then
				selected = true
				break
			end
		end

		if not selected then
			return nil
		end
	end

	local adjacent, incoming = {}, {}
	for _, m in motors do
		for _, part in { m.Part0, m.Part1 } do
			adjacent[part] = adjacent[part] or {}
			table.insert(adjacent[part], m)
		end

		incoming[m.Part1] = (incoming[m.Part1] or 0) + 1
	end

	local byPart, children, edges, visited = {}, {}, {}, {}
	for _, first in motors do
		if visited[first.Part0] then
			continue
		end

		local parts, seen, component, seenMotor = { first.Part0 }, { [first.Part0] = true }, {}, {}
		local at = 1
		while at <= #parts do
			local part = parts[at]
			at += 1
			for _, m in adjacent[part] do
				if not seenMotor[m] then
					seenMotor[m] = true
					table.insert(component, m)
				end

				local other = m.Part0 == part and m.Part1 or m.Part0
				if not seen[other] then
					seen[other] = true
					table.insert(parts, other)
				end
			end
		end

		for _, part in parts do
			visited[part] = true
		end

		local needed = not mask
		if mask then
			for _, m in component do
				if mask[m] then
					needed = true
					break
				end
			end
		end

		if not needed then
			continue
		end

		assert(
			#component == #parts - 1,
			"Bone Dynamics cannot simulate a cyclic joint chain (including parallel joints between the same parts)"
		)
		local natural = {}
		for _, part in parts do
			if not incoming[part] then
				table.insert(natural, part)
			end
		end

		local root

		if #natural == 1 then
			root = natural[1]
		elseif rig.PrimaryPart and seen[rig.PrimaryPart] then
			root = rig.PrimaryPart
		else
			local hrp = rig:FindFirstChild("HumanoidRootPart", true)
			if hrp and seen[hrp] then
				root = hrp
			end
		end

		if not root then
			table.sort(natural, function(a, b)
				if #adjacent[a] ~= #adjacent[b] then
					return #adjacent[a] > #adjacent[b]
				end

				return Bake.path(rig, a) < Bake.path(rig, b)
			end)
			root = natural[1] or parts[1]
		end

		local pending, covered = { root }, { [root] = true }
		at = 1
		while at <= #pending do
			local parent = pending[at]
			at += 1
			for _, m in adjacent[parent] do
				local child = m.Part0 == parent and m.Part1 or m.Part0
				if covered[child] then
					continue
				end

				covered[child] = true
				table.insert(pending, child)
				local edge =
					{ motor = m, parent = parent, child = child, reversed = m.Part1 == parent }
				edges[m] = edge
				byPart[child] = edge
				children[parent] = children[parent] or {}
				table.insert(children[parent], edge)
			end
		end
	end

	local active = {}

	local function include(edge)
		if active[edge.motor] then
			return
		end

		active[edge.motor] = true
		for _, child in children[edge.child] or {} do
			include(child)
		end
	end

	for _, m in motors do
		if edges[m] and (not mask or mask[m]) then
			include(edges[m])
		end
	end

	if not next(active) then
		return nil
	end

	local clone = Instance.new("Part")
	clone.Name = "EclipseDynamicsMotorProxy"
	clone.Anchored = true
	local worker = { mesh = rig, clone = clone, pairs = {}, motor = true, roots = {} }
	local rows = {}
	local count = 0

	local function append(edge, parent)
		local m = edge.motor
		count += 1
		local bone = Instance.new("Bone")
		bone.Name = string.format("Joint%06d", count)
		bone.Parent = parent
		local row =
			{ motor = m, clone = bone, part0 = m.Part0, part1 = m.Part1, c1 = m.C1, edge = edge }
		rows[m] = row
		table.insert(worker.pairs, row)
		for _, child in children[edge.child] or {} do
			if active[child.motor] then
				append(child, bone)
			end
		end
	end

	local ok, err = pcall(function()
		for _, m in motors do
			local edge = edges[m]
			local parent = edge and byPart[edge.parent]
			if active[m] and (not parent or not active[parent.motor]) then
				local anchor = Instance.new("Bone")
				anchor.Name = "Anchor" .. (#worker.roots + 1)
				anchor.Parent = clone
				table.insert(worker.roots, anchor)
				append(edge, anchor)
				rows[m].anchor = anchor
			end
		end
	end)
	if not ok then
		clone:Destroy()
		error(err, 0)
	end

	function worker:update()
		local worlds, stack = {}, {}

		local function partWorld(part)
			if worlds[part] then
				return worlds[part]
			end

			assert(not stack[part], "Bone Dynamics cannot simulate a cyclic joint chain")
			stack[part] = true
			local edge = byPart[part]
			local world = part.CFrame
			if edge then
				local m = edge.motor
				local offset = edge.reversed and m.C1 * m.C0:Inverse() or m.C0 * m.C1:Inverse()
				world = partWorld(edge.parent) * offset
			end

			stack[part] = nil
			worlds[part] = world
			return world
		end

		self.partWorld = partWorld
		for _, row in self.pairs do
			local m = row.motor
			assert(
				m.Parent and m.Part0 == row.part0 and m.Part1 == row.part1 and m.C1 == row.c1,
				"simulation canceled; a joint changed"
			)
			row.c0 = m.C0
			row.parentWorld = partWorld(row.edge.parent)
			local world = row.parentWorld * (row.edge.reversed and m.C1 or m.C0)
			if row.anchor then
				row.anchor.WorldCFrame = row.parentWorld
			end

			row.clone.CFrame = row.clone.Parent.WorldCFrame:ToObjectSpace(world)
			row.clone.Transform = CFrame.identity
		end
	end

	function worker:pose(row)
		local parentEdge = byPart[row.edge.parent]
		local parent = parentEdge and rows[parentEdge.motor]
		local parentWorld = row.parentWorld
		if parent then
			parentWorld = parent.clone.WorldCFrame
				* (parent.edge.reversed and parent.c0 or parent.motor.C1):Inverse()
		end

		if row.edge.reversed then
			return row.c0 * row.clone.WorldCFrame:ToObjectSpace(parentWorld * row.motor.C1)
		end

		return parentWorld:ToObjectSpace(row.clone.WorldCFrame)
	end

	local success, message = pcall(function()
		worker:update()
	end)
	if not success then
		clone:Destroy()
		error(message, 0)
	end

	return worker
end

function Bake.run(refs, rig, settings, checkpoint, makeKey, previous)
	local state, timeline = refs.State, refs.State.Timeline
	local raw = timeline:GetState()
	assert(
		rig and rig:IsA("Model") and table.find(state.getAllRigs(), rig),
		"Select a rig in the timeline first"
	)
	assert(
		not require("ArmatureRuntime").isRig(rig),
		"Bone Dynamics supports native Bone and Motor6D rigs; convert this armature first"
	)
	local meshes = Bake.meshes(rig)
	local motors = Bake.motors(rig)
	assert(#meshes > 0 or #motors > 0, "This rig has no Bone or Motor6D chains")
	settings = table.clone(settings)
	settings.kind = "BoneDynamics"
	local mask = selectionMask(rig, settings.selectionRoots)
	settings.loop = settings.loop == true
	settings.ReverseMotion = settings.ReverseMotion == true
	settings.first = math.floor(tonumber(settings.first) or 0)
	settings.last = math.floor(tonumber(settings.last) or timeline:GetMaxFrame())
	assert(
		settings.first >= 0 and settings.last > settings.first and settings.last <= 144000,
		"Choose a valid frame range"
	)
	local substeps = math.clamp(math.floor(tonumber(settings.substeps) or 2), 1, 8)
	local warmup = math.clamp(math.floor(tonumber(settings.warmup) or 30), 0, 600)
	local fps = raw.FPS
	local project, keyframes = state.currentAnimations, raw.Keyframes

	local function check(frame)
		assert(
			refs.Active()
				and state.currentAnimations == project
				and raw.Keyframes == keyframes
				and raw.FPS == fps
				and not raw.Playing
				and rig.Parent,
			"simulation canceled; the project changed"
		)
		if checkpoint then
			checkpoint(frame)
		end
	end

	local deadline = os.clock() + 0.006

	local function budget(frame)
		if os.clock() >= deadline then
			game:GetService("RunService").Heartbeat:Wait()
			check(frame)
			deadline = os.clock() + 0.006
		end
	end

	local saved, native, workers, snapshots, tracks, owners = {}, {}, {}, {}, {}, {}
	local clip = {
		id = previous and previous.id or game.HttpService:GenerateGUID(false),
		rig = rig,
		name = rig.Name .. " / Bone Dynamics",
		first = settings.first,
		last = settings.last,
		settings = settings,
		tracks = tracks,
		owners = owners,
	}

	local function sample(time)
		Cache.without(function()
			timeline:ApplyPoseAtTime(rig, time, { SkipControls = true })
		end)
	end

	local ok, err = xpcall(function()
		for _, owner in state.getAllRigs() do
			saved[owner] = { pose = Pose.capture(owner), master = Master.capture(owner) }
			for _, bone in owner:GetDescendants() do
				if dynamicBone(bone) then
					native[bone] = { bone.CFrame, bone.Transform }
				end
			end
		end

		check(settings.first)
		sample(settings.first / fps)
		local colliders = {}
		if settings.collisions then
			for _, part in workspace:GetDescendants() do
				if
					part:IsA("BasePart")
					and not table.find(meshes, part)
					and not part:GetAttribute("EclipseBone")
					and not part:GetAttribute("EclipseBoneLink")
					and not part:GetAttribute("EclipseFullPartWidget")
					and not part:GetAttribute("EclipseHandleStyle")
					and (part.CanCollide or part:IsDescendantOf(rig))
				then
					if part.Transparency < 1 or part.CanCollide then
						table.insert(colliders, part)
					end
				end
			end

			assert(
				#colliders <= 2000,
				"Too many collision parts; disable collisions or simplify the scene"
			)
		end

		for _, mesh in meshes do
			local selected, all = boneRoots(mesh, mask)
			if #selected == 0 then
				continue
			end

			local clone = assert(mesh:Clone(), "The skinned mesh must be archivable")
			local worker = { mesh = mesh, clone = clone, pairs = {} }
			table.insert(workers, worker)
			for _, object in clone:GetDescendants() do
				if
					object:IsA("BaseScript")
					or object:IsA("ModuleScript")
					or (object:IsA("Bone") and object:GetAttribute("EclipseR6Control"))
				then
					object:Destroy()
				end
			end

			local byName = {}
			for _, bone in clone:GetDescendants() do
				if dynamicBone(bone) then
					byName[bone.Name] = bone
				end
			end

			local cloneRoots = {}
			for _, bone in selected do
				table.insert(cloneRoots, byName[bone.Name])
			end

			for _, bone in all do
				local other = byName[bone.Name]
				other.CFrame = bone.CFrame * bone.Transform
				other.Transform = CFrame.identity
				local included = false
				for _, root in selected do
					if bone == root or bone:IsDescendantOf(root) then
						included = true
						break
					end
				end

				local motor = BoneMotor.get(bone)
				local row = { bone = bone, clone = other, motor = included and motor or nil }
				table.insert(worker.pairs, row)
				if row.motor then
					for _, existing in Cache.list(raw) do
						assert(
							existing == previous
								or not existing.tracks[motor]
								or existing.last < settings.first
								or existing.first > settings.last,
							"A cached simulation already overlaps this bone"
						)
					end

					snapshots[motor] = timeline:_snapshotMotorBucket(motor)
					tracks[motor] = {}
					owners[motor] = rig
				end
			end

			local options = {}
			for _, id in
				{
					"Damping",
					"Stiffness",
					"Inertia",
					"Elasticity",
					"AnchorDepth",
					"Gravity",
					"Force",
					"WindStrength",
					"WindSpeed",
					"WindDirection",
					"WindInfluence",
					"AnchorsRotate",
					"ReverseMotion",
					"Seed",
					"Radius",
					"RotationLimit",
				}
			do
				if settings[id] ~= nil and (not settings.meshSettings or id == "Seed") then
					options[id] = settings[id]
				end
			end

			options.UpdateRate = fps * substeps
			worker.solver = Solver.new(clone, cloneRoots, options, colliders)
		end

		local motorState = motorWorker(rig, motors, mask)
		if motorState then
			table.insert(workers, motorState)
			local excluded = {}
			for _, row in motorState.pairs do
				excluded[row.edge.child] = true
			end

			local contacts = {}
			for _, part in colliders do
				if not excluded[part] then
					table.insert(contacts, part)
				end
			end

			local options = { UpdateRate = fps * substeps }
			for _, id in
				{
					"Damping",
					"Stiffness",
					"Inertia",
					"Elasticity",
					"AnchorDepth",
					"Gravity",
					"Force",
					"WindStrength",
					"WindSpeed",
					"WindDirection",
					"WindInfluence",
					"AnchorsRotate",
					"ReverseMotion",
					"Seed",
					"Radius",
					"RotationLimit",
				}
			do
				options[id] = settings[id]
			end

			motorState.solver = Solver.new(motorState.clone, motorState.roots, options, contacts)
			for _, row in motorState.pairs do
				local motor = row.motor
				for _, existing in Cache.list(raw) do
					assert(
						existing == previous
							or not existing.tracks[motor]
							or existing.last < settings.first
							or existing.first > settings.last,
						"A cached simulation already overlaps this joint"
					)
				end

				snapshots[motor] = timeline:_snapshotMotorBucket(motor)
				tracks[motor] = {}
				owners[motor] = rig
			end
		end

		local count = 0
		for _ in tracks do
			count += 1
		end

		assert(count > 0, "No supported chains are selected")
		assert(
			count * (settings.last - settings.first + 1) <= 1000000,
			"Reduce the frame range: Bone Dynamics cache exceeds one million bone frames"
		)

		local function step(time, frame, poseTime)
			sample(poseTime or math.max(settings.first / fps, time))
			if motorState then
				motorState:update()
			end

			for _, worker in workers do
				assert(worker.mesh.Parent, "simulation canceled; a mesh was removed")
				if not worker.motor then
					worker.clone.CFrame = motorState and motorState.partWorld(worker.mesh)
						or worker.mesh.CFrame
					worker.clone.Size = worker.mesh.Size
					for _, row in worker.pairs do
						row.clone.CFrame = row.bone.CFrame * row.bone.Transform
						row.clone.Transform = CFrame.identity
					end
				end

				worker.solver:step(1 / (fps * substeps), time)
			end

			budget(frame)
		end

		for i = 1, warmup * substeps do
			step(settings.first / fps - (warmup * substeps - i) / (fps * substeps), settings.first)
		end

		local function record(frame, blend)
			for _, worker in workers do
				for _, row in worker.pairs do
					if row.motor then
						local cf = worker.motor and worker:pose(row)
							or row.clone.CFrame * row.clone.Transform
						if blend then
							local t = (frame - settings.first) / (settings.last - settings.first)

							cf = cf:Lerp(tracks[row.motor][frame].C0, t * t * (3 - 2 * t))
						end

						for _, value in { cf:GetComponents() } do
							assert(
								value == value and math.abs(value) < 1e9,
								"Bone Dynamics produced an invalid pose"
							)
						end

						local key = makeKey(row.motor, frame, fps, cf, nil, nil)
						key.Parented = true
						key.WorldCFrame = nil
						key.MasterWorld = nil
						tracks[row.motor][frame] = key
					end
				end
			end
		end

		if settings.loop then
			local span = settings.last - settings.first
			for cycle = 1, 2 do
				for frame = settings.first, settings.last do
					local progress = settings.first
						+ ((cycle - 1) * span + frame - settings.first) / 2
					check(progress)

					if frame > settings.first then
						for sub = 1, substeps do
							local poseTime = (frame - 1 + sub / substeps) / fps
							step(poseTime + (cycle - 1) * span / fps, progress, poseTime)
						end
					end

					record(frame, cycle == 2)
					budget(progress)
				end
			end
		else
			for frame = settings.first, settings.last do
				check(frame)
				for sub = 1, substeps do
					step((frame - 1 + sub / substeps) / fps, frame)
				end

				record(frame, false)
			end
		end

		check(settings.last)
		for motor, before in snapshots do
			assert(
				Cleanup.equal(before, timeline:_snapshotMotorBucket(motor)),
				"The animation changed; simulate again"
			)
		end
	end, debug.traceback)

	local cleanupErrors = {}
	for _, worker in workers do
		if worker.solver then
			local good, why = pcall(function()
				worker.solver:destroy()
			end)
			if not good then
				table.insert(cleanupErrors, tostring(why))
			end
		end

		worker.clone:Destroy()
	end

	for owner, record in saved do
		for _, restore in
			{

				function()
					Pose.restore(owner, record.pose)
				end,

				function()
					Master.restore(owner, record.master)
				end,
			}
		do
			local good, why = pcall(restore)
			if not good then
				table.insert(cleanupErrors, tostring(why))
			end
		end
	end

	for bone, value in native do
		if bone.Parent then
			local good, why = pcall(function()
				bone.CFrame = value[1]
				bone.Transform = value[2]
			end)
			if not good then
				table.insert(cleanupErrors, tostring(why))
			end
		end
	end

	assert(#cleanupErrors == 0, table.concat(cleanupErrors, "\n"))
	assert(ok, err)
	return clip
end

return Bake
