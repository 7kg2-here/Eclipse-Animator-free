--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local RigTraversal = require("RigTraversal")

local Paths = require("Paths")
local PartRig = {}

function PartRig.supports(model)
	if not model or not model:IsA("Model") then
		return false
	end

	for _, child in model:GetChildren() do
		if child:GetAttribute("EclipsePartRigRoot") then
			return true
		end
	end

	return false
end

function PartRig.enabled(model, raw)
	local value = model:GetAttribute("EclipseIndividualParts")
	if value ~= nil then
		return value == true
	end

	if raw then
		for motor, keys in raw.Keyframes do
			if
				typeof(motor) == "Instance"
				and motor:GetAttribute("EclipsePartRigJoint")
				and motor:IsDescendantOf(model)
				and next(keys)
			then
				return true
			end
		end
	end

	return false
end

function PartRig.flush(model)
	if not model then
		return
	end

	for _, root in model:GetChildren() do
		if not root:GetAttribute("EclipsePartRigRoot") then
			continue
		end

		for _, joint in root:GetChildren() do
			if
				joint:IsA("Motor6D")
				and joint:GetAttribute("EclipsePartRigJoint")
				and joint.Part0
				and joint.Part1
				and joint.Part1.Parent
			then
				local world = joint.Part0.CFrame * joint.C0 * joint.Transform * joint.C1:Inverse()
				if joint.Part1.CFrame ~= world then
					require("Recovery").captureJoint(joint)
					joint.Part1.CFrame = world
				end
			end
		end
	end
end

function PartRig.inspect(model)
	assert(typeof(model) == "Instance" and model:IsA("Model"), "Select a model first")
	assert(not model:FindFirstChildOfClass("Humanoid"), "This character already has a rig")
	local root
	local parts, occupied = {}, {}
	for _, object in RigTraversal.descendants(model) do
		if object:IsA("Motor6D") then
			assert(
				object:GetAttribute("EclipsePartRigJoint"),
				"This model already has joints. Add its existing rig to Eclipse"
			)
			if object.Part1 then
				occupied[object.Part1] = true
			end
		elseif
			object:IsA("JointInstance")
			or object:IsA("WeldConstraint")
			or object:IsA("Constraint")
			or object:IsA("Bone")
		then
			error("This model has joints or constraints. Use an unrigged model", 0)
		elseif object:IsA("BasePart") and object:GetAttribute("EclipsePartRigRoot") then
			root = object
		end
	end

	for _, object in RigTraversal.descendants(model) do
		if
			object:IsA("BasePart")
			and object ~= root
			and not occupied[object]
			and not Paths.excluded(object, model)
		then
			table.insert(parts, object)
		end
	end

	table.sort(parts, function(a, b)
		return Paths.of(a, model) < Paths.of(b, model)
	end)
	return parts, root
end

function PartRig.catalog(model)
	local parts, root = PartRig.inspect(model)
	local joints = {}
	if root then
		for _, joint in root:GetChildren() do
			if
				joint:IsA("Motor6D")
				and joint:GetAttribute("EclipsePartRigJoint")
				and joint.Part1
			then
				joints[joint.Part1] = joint
				table.insert(parts, joint.Part1)
			end
		end
	end

	table.sort(parts, function(a, b)
		return Paths.of(a, model) < Paths.of(b, model)
	end)
	return parts, joints
end

function PartRig.choice(model)
	local choices = {}
	for _, root in model:GetChildren() do
		if root:GetAttribute("EclipsePartRigRoot") then
			for _, joint in root:GetChildren() do
				if
					joint:IsA("Motor6D")
					and joint:GetAttribute("EclipsePartRigJoint")
					and joint.Part1
				then
					local path = Paths.of(joint.Part1, model)
					if path then
						choices[path] = joint:GetAttribute("EclipsePartTrackEnabled") ~= false
					end
				end
			end
		end
	end

	return choices
end

function PartRig.restoreChoice(model, choices)
	for _, root in model:GetChildren() do
		if root:GetAttribute("EclipsePartRigRoot") then
			for _, joint in root:GetChildren() do
				if
					joint:IsA("Motor6D")
					and joint:GetAttribute("EclipsePartRigJoint")
					and joint.Part1
				then
					local path = Paths.of(joint.Part1, model)
					if path then
						joint:SetAttribute("EclipsePartTrackEnabled", choices and choices[path])
					end
				end
			end
		end
	end
end

function PartRig.create(model, selected)
	local parts, existing = PartRig.inspect(model)
	if selected then
		local filtered = {}
		for _, part in parts do
			if selected[part] then
				table.insert(filtered, part)
			end
		end

		parts = filtered
	end

	assert(#parts > 0 or existing and selected, "Choose at least one part")
	local originalPrimary = model.PrimaryPart
	local originalPivot = model:GetPivot()
	local root = existing
	if not root then
		root = Instance.new("Part")
		root.Name = "EclipseRigRoot"
		root.Size = Vector3.one * 0.2
		root.CFrame = originalPivot
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
		root.CastShadow = false
		root.Locked = true
		root:SetAttribute("EclipsePartRigRoot", true)
	end

	local joints, poses = {}, {}
	for _, part in parts do
		poses[part] = part.CFrame
		local joint = Instance.new("Motor6D")
		joint.Name = part.Name
		joint.Part0 = root
		joint.Part1 = part
		joint.C0 = root.CFrame:ToObjectSpace(part.CFrame)
		joint.C1 = CFrame.identity
		joint:SetAttribute("EclipsePartRigJoint", true)
		joint:SetAttribute("EclipseAnimatorDefaultC0", joint.C0)
		table.insert(joints, joint)
	end

	local transaction = {
		model = model,
		root = root,
		parts = parts,
		joints = joints,
		createdRoot = not existing,
	}

	function transaction.apply(enabled)
		if enabled then
			root.Parent = model
			model.PrimaryPart = root
			for _, joint in joints do
				joint.Parent = root
			end
		else
			for _, joint in joints do
				joint.Parent = nil
			end

			if not existing then
				model.PrimaryPart = originalPrimary
				root.Parent = nil
				if not originalPrimary then
					model.WorldPivot = originalPivot
				end
			end
		end

		for part, pose in poses do
			if part.Parent then
				part.CFrame = pose
			end
		end
	end

	transaction.apply(true)
	return transaction
end

return PartRig
