--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Properties = require("Properties")
local PoseSpace = {}

local SPACE_ATTRIBUTE = "EclipsePoseSpace"
local CANONICAL_SPACE = "Canonical"

function PoseSpace.getRigScale(rig: Instance?): number
	if rig and rig:IsA("Model") then
		for _, property in Properties.list(rig, true) do
			if property.PropertyId == "Scale" then
				return property.DefaultValue
			end
		end

		return rig:GetScale()
	end

	return 1
end

function PoseSpace.getImportScale(
	rig: Instance?,
	sequence: KeyframeSequence,
	preview: boolean?
): number
	if
		sequence:GetAttribute(SPACE_ATTRIBUTE) == nil
		and sequence:GetAttribute("EclipseHadArmature") ~= nil
	then
		return 1
	end

	if preview and rig and rig:IsA("Model") then
		return rig:GetScale()
	end

	return PoseSpace.getRigScale(rig)
end

function PoseSpace.scaleTranslation(transform: CFrame, scale: number): CFrame
	if scale == 1 then
		return transform
	end

	return CFrame.new(transform.Position * scale) * transform.Rotation
end

local function placementRoot(rig)
	local Master = require("MasterControl")
	local root = Master.root(rig)
	if not root then
		return nil
	end

	local master = Master.get(rig, true)
	return master and master.Part0.CFrame or root.CFrame
end

function PoseSpace.markCanonical(sequence: KeyframeSequence, rig: Instance?)
	sequence:SetAttribute(SPACE_ATTRIBUTE, CANONICAL_SPACE)
	sequence:SetAttribute("EclipseAuthoredScale", PoseSpace.getRigScale(rig))
	if rig and rig:IsA("Model") then
		sequence:SetAttribute("EclipseAuthoredPivot", rig:GetPivot())
	end

	sequence:SetAttribute("EclipseAuthoredRoot", placementRoot(rig))
end

function PoseSpace.savedRatio(rig, sequence)
	local authored = sequence:GetAttribute("EclipseAuthoredScale")
	if typeof(authored) ~= "number" or authored <= 0 then
		return 1
	end

	return PoseSpace.getRigScale(rig) / authored
end

function PoseSpace.getImportPivot(rig, sequence)
	if not rig or not rig:IsA("Model") then
		return nil
	end

	local origin = sequence:GetAttribute("EclipseAuthoredPivot")
	local savedRoot = sequence:GetAttribute("EclipseAuthoredRoot")
	local currentRoot = typeof(savedRoot) == "CFrame" and placementRoot(rig)
	if typeof(origin) == "CFrame" and currentRoot then
		return currentRoot
			* PoseSpace.scaleTranslation(
				savedRoot:ToObjectSpace(origin),
				PoseSpace.savedRatio(rig, sequence)
			)
	end

	return rig:GetPivot()
end

function PoseSpace.retargetWorld(value, ratio, origin, target)
	if typeof(value) == "CFrame" and typeof(origin) == "CFrame" and typeof(target) == "CFrame" then
		return target * PoseSpace.scaleTranslation(origin:ToObjectSpace(value), ratio)
	end

	return value
end

function PoseSpace.retargetKey(key, ratio, origin, target)
	if
		typeof(key.MasterWorld) == "CFrame"
		and typeof(origin) == "CFrame"
		and typeof(target) == "CFrame"
	then
		key.MasterWorld = target
			* PoseSpace.scaleTranslation(origin:Inverse() * key.MasterWorld * origin, ratio)
			* target:Inverse()
	end

	if key.PhysicsLead then
		PoseSpace.retargetKey(key.PhysicsLead, ratio, origin, target)
	end

	if ratio ~= 1 then
		for _, field in { "C0", "ChannelPoseC0", "IKBaseC0" } do
			if typeof(key[field]) == "CFrame" then
				key[field] = PoseSpace.scaleTranslation(key[field], ratio)
			end
		end

		if key.C0 then
			key.Position = key.C0.Position
			key.Rotation = key.C0.Rotation
		end

		for _, field in { "PathTangentIn", "PathTangentOut" } do
			if typeof(key[field]) == "Vector3" then
				key[field] *= ratio
			end
		end

		local seen = {}
		for _, collection in { key.Channels or {}, key.GraphCurves or {} } do
			for id, point in collection do
				if id:sub(1, 4) == "loc_" and typeof(point) == "table" and not seen[point] then
					seen[point] = true
					if typeof(point.Value) == "number" then
						point.Value *= ratio
					end

					for _, side in { "In", "Out" } do
						if point[side] then
							point[side][2] *= ratio
						end
					end

					point.BlenderHandles = nil
				end
			end
		end
	end

	if typeof(origin) == "CFrame" and typeof(target) == "CFrame" then
		if
			key.CamTargetParent
			and not key.CamTargetParent.world
			and typeof(key.CamTargetAnchor) == "CFrame"
		then
			key.CamTargetAnchor =
				PoseSpace.retargetWorld(key.CamTargetAnchor, ratio, origin, target)
		end

		for _, field in { "WorldCFrame", "IKBaseWorld", "IKAnchor", "IKRigWorld", "IKRoot" } do
			if typeof(key[field]) == "CFrame" then
				key[field] = target
					* PoseSpace.scaleTranslation(origin:ToObjectSpace(key[field]), ratio)
			end
		end

		for _, field in { "IKTarget", "IKPole" } do
			local value = key[field]
			if typeof(value) == "CFrame" then
				key[field] = target * PoseSpace.scaleTranslation(origin:ToObjectSpace(value), ratio)
			elseif typeof(value) == "Vector3" then
				key[field] = target:PointToWorldSpace(origin:PointToObjectSpace(value) * ratio)
			end
		end

		if typeof(key.HSRotation) == "CFrame" then
			key.HSRotation = (target * origin:Inverse()).Rotation * key.HSRotation
		end
	end
end

return PoseSpace
