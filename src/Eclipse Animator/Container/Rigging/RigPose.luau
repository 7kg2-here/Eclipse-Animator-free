--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")

local Pose = {}

function Pose.rememberRest(joint, rest)
	if typeof(rest) == "CFrame" then
		joint:SetAttribute("EclipseRigRestC0", rest)
	end
end

local function classicRest(rig, motor)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return nil
	end

	local a, b = motor.Part0, motor.Part1
	if not a or not b then
		return nil
	end

	local flip = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	local right = CFrame.Angles(0, math.pi / 2, 0)
	local left = CFrame.Angles(0, -math.pi / 2, 0)
	local rest, expected
	if motor.Name == "RootJoint" and a.Name == "HumanoidRootPart" and b.Name == "Torso" then
		rest = flip
		expected = flip
	elseif motor.Name == "Neck" and a.Name == "Torso" and b.Name == "Head" then
		rest = CFrame.new(0, a.Size.Y / 2, 0) * flip
		expected = CFrame.new(0, -b.Size.Y / 2, 0) * flip
	else
		local side, kind = motor.Name:match("^(Left) (.+)$")
		if not side then
			side, kind = motor.Name:match("^(Right) (.+)$")
		end

		if a.Name ~= "Torso" or not side then
			return nil
		end

		local sign = side == "Right" and 1 or -1
		local rotation = sign == 1 and right or left
		if kind == "Shoulder" and b.Name == side .. " Arm" then
			rest = CFrame.new(sign * a.Size.X / 2, a.Size.Y / 4, 0) * rotation
			expected = CFrame.new(-sign * b.Size.X / 2, b.Size.Y / 4, 0) * rotation
		elseif kind == "Hip" and b.Name == side .. " Leg" then
			rest = CFrame.new(sign * a.Size.X / 2, -a.Size.Y / 2, 0) * rotation
			expected = CFrame.new(sign * b.Size.X / 2, b.Size.Y / 2, 0) * rotation
		end
	end

	return expected and motor.C1:FuzzyEq(expected, 1e-5) and rest or nil
end

local layouts = setmetatable({}, { __mode = "k" })

local function layout(rig)
	local entry = layouts[rig]
	if entry and entry.valid then
		return entry
	end

	if entry then
		for _, connection in entry.connections do
			connection:Disconnect()
		end
	end

	entry = {
		valid = true,
		accessories = {},
		objects = {},
		connections = {},
		passive = RigTraversal.passiveMotors(rig),
	}

	local function dirty()
		entry.valid = false
	end

	for _, object in RigTraversal.rigDescendants(rig) do
		if object:IsA("Motor6D") then
			for _, property in { "Part0", "Part1", "Enabled" } do
				table.insert(
					entry.connections,
					object:GetPropertyChangedSignal(property):Connect(dirty)
				)
			end
		elseif object:IsA("BasePart") then
			table.insert(entry.connections, object:GetPropertyChangedSignal("Name"):Connect(dirty))
		end

		if object:IsA("BasePart") and object:FindFirstAncestorOfClass("Accessory") then
			entry.accessories[object] = true
		end

		if object:IsA("JointInstance") or object:IsA("RigidConstraint") then
			table.insert(entry.objects, object)
		end

		if object:GetAttribute("EclipseAccessoryLink") and object:IsA("Weld") and object.Part1 then
			entry.accessories[object.Part1] = true
		end
	end

	if rig:IsA("Model") then
		table.insert(entry.connections, rig:GetPropertyChangedSignal("PrimaryPart"):Connect(dirty))
	end

	table.insert(entry.connections, rig.DescendantAdded:Connect(dirty))
	table.insert(entry.connections, rig.DescendantRemoving:Connect(dirty))
	layouts[rig] = entry
	return entry
end

function Pose.syncAccessories(rig)
	local cached = layout(rig)
	local passive = cached.passive
	if not next(cached.accessories) and not next(passive) then
		return
	end

	local objects = cached.objects
	local accessories, links, worlds, visiting = {}, {}, {}, {}
	for part in cached.accessories do
		if part.Parent then
			accessories[part] = true
		end
	end

	for motor in passive do
		accessories[motor.Part0] = true
	end

	if not next(accessories) then
		return
	end

	for _, joint in objects do
		if joint:IsA("JointInstance") and joint.Enabled and joint.Part0 and joint.Part1 then
			local a, b = joint.Part0, joint.Part1
			if not a:IsDescendantOf(rig) or not b:IsDescendantOf(rig) then
				continue
			end

			local offset = joint.C0
				* (joint:IsA("Motor6D") and joint.Transform or CFrame.identity)
				* joint.C1:Inverse()
			if passive[joint] or accessories[a] and not accessories[b] then
				links[a] = { part = b, offset = offset:Inverse() }
			elseif accessories[b] then
				links[b] = { part = a, offset = offset }
			end
		elseif
			joint:IsA("RigidConstraint")
			and joint.Enabled
			and joint.Attachment0
			and joint.Attachment1
		then
			local a, b = joint.Attachment0, joint.Attachment1
			if
				not a.Parent
				or not b.Parent
				or not a.Parent:IsA("BasePart")
				or not b.Parent:IsA("BasePart")
				or not a:IsDescendantOf(rig)
				or not b:IsDescendantOf(rig)
			then
				continue
			end

			if accessories[a.Parent] and not accessories[b.Parent] then
				links[a.Parent] = { part = b.Parent, offset = b.CFrame * a.CFrame:Inverse() }
			elseif accessories[b.Parent] then
				links[b.Parent] = { part = a.Parent, offset = a.CFrame * b.CFrame:Inverse() }
			end
		end
	end

	local function world(part)
		if worlds[part] then
			return worlds[part]
		end

		if visiting[part] then
			return part.CFrame
		end

		visiting[part] = true
		local link = links[part]
		local frame = link and world(link.part) * link.offset or part.CFrame
		visiting[part] = nil
		worlds[part] = frame
		return frame
	end

	local parts, frames = {}, {}
	for part in accessories do
		if links[part] then
			local cf = world(part)
			if not part.CFrame:FuzzyEq(cf, 1e-6) then
				table.insert(parts, part)
				table.insert(frames, cf)
			end
		end
	end

	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Pose.resolve(selected, items)
	local rigs = {}

	local function add(object)
		while typeof(object) == "Instance" and object ~= workspace do
			local reference = object:FindFirstChild("EclipseSourceRig")
			if reference and reference:IsA("ObjectValue") and reference.Value then
				object = reference.Value
			end

			if
				object:IsA("Model")
				and (
					object:FindFirstChildOfClass("Humanoid")
					or object:FindFirstChildWhichIsA("Motor6D", true)
					or object:FindFirstChildWhichIsA("Bone", true)
					or object:FindFirstChildWhichIsA("AnimationConstraint", true)
				)
			then
				rigs[object] = true
				return
			end

			object = object.Parent
		end
	end

	for _, object in selected do
		add(object)
	end

	if not next(rigs) then
		for item, enabled in items or {} do
			if enabled then
				add((item.grandpa or item).linkedRigInstance or item.linkedRigInstance)
			end
		end
	end

	local result
	for rig in rigs do
		if result then
			return nil, true
		end

		result = rig
	end

	return result, false
end

function Pose.assemble(rig)
	local passive = RigTraversal.passiveMotors(rig)
	local links, worlds, visiting = {}, {}, {}
	for _, joint in RigTraversal.rigDescendants(rig) do
		if
			joint:IsA("JointInstance")
			and joint.Enabled
			and joint.Part0
			and joint.Part1
			and not (joint:GetAttribute("EclipseAccessorySource") and not joint.Enabled)
		then
			if joint.Part0:IsDescendantOf(rig) and joint.Part1:IsDescendantOf(rig) then
				local accessory = joint.Part0:FindFirstAncestorOfClass("Accessory")
				if passive[joint] or accessory and not joint.Part1:IsDescendantOf(accessory) then
					if
						not links[joint.Part0]
						or joint:IsA("Motor6D") and not links[joint.Part0].motor
					then
						links[joint.Part0] = {
							part = joint.Part1,
							offset = joint.C1
								* (joint:IsA("Motor6D") and joint.Transform:Inverse() or CFrame.identity)
								* joint.C0:Inverse(),
							motor = joint:IsA("Motor6D"),
						}
					end
				elseif
					not links[joint.Part1]
					or joint:IsA("Motor6D") and not links[joint.Part1].motor
				then
					links[joint.Part1] = {
						motor = joint:IsA("Motor6D"),
						part = joint.Part0,
						offset = joint.C0
							* (joint:IsA("Motor6D") and joint.Transform or CFrame.identity)
							* joint.C1:Inverse(),
					}
				end
			end
		end
	end

	for _, joint in RigTraversal.rigDescendants(rig) do
		if
			joint:IsA("WeldConstraint")
			and joint.Part0
			and joint.Part1
			and not (joint:GetAttribute("EclipseAccessorySource") and not joint.Enabled)
			and joint.Enabled
			and joint.Part0:IsDescendantOf(rig)
			and joint.Part1:IsDescendantOf(rig)
		then
			local a, b = joint.Part0, joint.Part1
			local accessory = a:FindFirstAncestorOfClass("Accessory")
			if accessory and not b:IsDescendantOf(accessory) then
				a, b = b, a
			end

			if not links[b] then
				links[b] = { part = a, offset = a.CFrame:ToObjectSpace(b.CFrame) }
			end
		end
	end

	for _, joint in RigTraversal.rigDescendants(rig) do
		if
			joint:IsA("RigidConstraint")
			and joint.Enabled
			and joint.Attachment0
			and joint.Attachment1
		then
			local a, b = joint.Attachment0, joint.Attachment1
			if
				a.Parent
				and b.Parent
				and a.Parent:IsA("BasePart")
				and b.Parent:IsA("BasePart")
				and a:IsDescendantOf(rig)
				and b:IsDescendantOf(rig)
			then
				local accessory = a.Parent:FindFirstAncestorOfClass("Accessory")
				if accessory and not b:IsDescendantOf(accessory) then
					a, b = b, a
				end

				if not links[b.Parent] then
					links[b.Parent] = { part = a.Parent, offset = a.CFrame * b.CFrame:Inverse() }
				end
			end
		elseif
			joint:IsA("AnimationConstraint")
			and joint.Enabled
			and joint.Attachment0
			and joint.Attachment1
		then
			local a, b = joint.Attachment0, joint.Attachment1
			if
				a.Parent:IsA("BasePart")
				and b.Parent:IsA("BasePart")
				and a:IsDescendantOf(rig)
				and b:IsDescendantOf(rig)
				and not links[b.Parent]
			then
				links[b.Parent] = {
					part = a.Parent,
					offset = a.CFrame * joint.Transform * b.CFrame:Inverse(),
				}
			end
		end
	end

	local function world(part)
		if worlds[part] then
			return worlds[part]
		end

		if visiting[part] then
			return part.CFrame
		end

		visiting[part] = true
		local link = links[part]
		local cf = link and world(link.part) * link.offset or part.CFrame
		visiting[part], worlds[part] = nil, cf
		return cf
	end

	local parts, frames = {}, {}
	for _, part in RigTraversal.rigDescendants(rig) do
		if part:IsA("BasePart") then
			table.insert(parts, part)
			table.insert(frames, world(part))
		end
	end

	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	return #parts
end

function Pose.capture(rig)
	local snapshot = {}
	for _, item in RigTraversal.rigDescendants(rig) do
		if item:IsA("Motor6D") then
			snapshot[item] = { C0 = item.C0, Transform = item.Transform }
		elseif item:IsA("JointInstance") then
			snapshot[item] = { C0 = item.C0 }
		elseif item:IsA("Bone") or item:IsA("AnimationConstraint") then
			snapshot[item] = { Transform = item.Transform }
		elseif item:IsA("Attachment") then
			snapshot[item] = { CFrame = item.CFrame }
		elseif item:IsA("BasePart") then
			snapshot[item] = { CFrame = item.CFrame }
		end
	end

	return snapshot
end

function Pose.restore(rig, snapshot)
	local parts, frames = {}, {}
	for item, properties in snapshot do
		if not item.Parent then
			continue
		end

		if item:IsA("BasePart") then
			table.insert(parts, item)
			table.insert(frames, properties.CFrame)
		else
			for property, value in properties do
				item[property] = value
			end
		end
	end

	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

function Pose.recoverStamps(scope, state)
	local models = {}

	local function owner(item)
		local model = item:FindFirstAncestorOfClass("Model")
		if model then
			models[model] = true
		end
	end

	local objects = RigTraversal.descendants(scope)
	if scope then
		table.insert(objects, 1, scope)
	end

	for _, item in objects do
		if item:GetAttribute("EclipseArmatureSkinningHelper") then
			continue
		end

		local saved = item:GetAttribute("EclipseAnimatorDefaultC0")
		if
			item:IsA("Motor6D")
			and typeof(saved) == "CFrame"
			and not (state and state.DefaultPose[item])
		then
			item.C0, item.Transform = saved, CFrame.identity
			Pose.rememberRest(item, saved)
			owner(item)
		elseif item:IsA("Bone") and typeof(saved) == "CFrame" then
			local adapter = require("BoneMotor").get(item)
			if not (state and state.DefaultPose[adapter]) then
				item.Transform = item.CFrame:Inverse() * saved
				Pose.rememberRest(item, saved)
			end
		elseif item:IsA("BasePart") and not (state and state.DefaultSize[item]) then
			local size = item:GetAttribute("EclipseAnimatorDefaultSize")
			if typeof(size) == "Vector3" then
				item.Size = size
				owner(item)
			end
		end
	end

	for model in models do
		Pose.assemble(model)
	end
end

function Pose.reset(rig, defaults, boneMotor)
	for _, item in RigTraversal.rigDescendants(rig) do
		if item:GetAttribute("EclipseArmatureSkinningHelper") then
			continue
		end

		if item:IsA("Motor6D") then
			local rest = defaults and defaults[item]
				or item:GetAttribute("EclipseAnimatorDefaultC0")
				or item:GetAttribute("EclipseRigRestC0")

			if not rest and item.Part0 and item.Part1 then
				local a = item.Part0:FindFirstChild(item.Name .. "RigAttachment")
				local b = item.Part1:FindFirstChild(item.Name .. "RigAttachment")
				if a and b and a:IsA("Attachment") and b:IsA("Attachment") then
					rest = a.CFrame
				end
			end

			rest = rest or classicRest(rig, item)
			if rest then
				item.C0 = rest
				Pose.rememberRest(item, rest)
			end

			item.Transform = CFrame.identity
		elseif item:IsA("JointInstance") then
			local rest = defaults and defaults[item] or item:GetAttribute("EclipseRigRestC0")
			if typeof(rest) == "CFrame" then
				item.C0 = rest
				Pose.rememberRest(item, rest)
			end
		elseif item:IsA("Bone") then
			local rest = defaults and boneMotor and defaults[boneMotor.get(item)]
				or item:GetAttribute("EclipseAnimatorDefaultC0")
				or item:GetAttribute("EclipseRigRestC0")
			item.Transform = rest and item.CFrame:Inverse() * rest or CFrame.identity
		elseif item:IsA("AnimationConstraint") then
			local rest = item:GetAttribute("EclipseConstraintRestC0")
			if typeof(rest) == "CFrame" and item.Attachment0 then
				local savedScale = rig:GetAttribute("EclipseNativeJointScale") or rig:GetScale()
				item.Attachment0.CFrame = CFrame.new(rest.Position * (rig:GetScale() / savedScale))
					* rest.Rotation
			end

			item.Transform = CFrame.identity
		end
	end

	Pose.assemble(rig)
end

return Pose
