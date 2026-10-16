--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Orientation = {}

local emissionFrames = {
	[Enum.NormalId.Front] = CFrame.identity,
	[Enum.NormalId.Back] = CFrame.Angles(0, -math.pi, 0),
	[Enum.NormalId.Left] = CFrame.Angles(0, math.pi / 2, 0),
	[Enum.NormalId.Right] = CFrame.Angles(0, -math.pi / 2, 0),
	[Enum.NormalId.Top] = CFrame.Angles(math.pi / 2, 0, 0),
	[Enum.NormalId.Bottom] = CFrame.Angles(-math.pi / 2, 0, 0),
}

function Orientation.emissionFrame(direction)
	return emissionFrames[direction] or emissionFrames[Enum.NormalId.Top]
end

function Orientation.direction(particle)
	local direction = particle.velocity.Magnitude > 0 and particle.velocity.Unit
		or particle.direction
	return direction
end

function Orientation.frame(cf, direction, position)
	local normal = direction.Magnitude > 0 and direction.Unit or cf.UpVector.Unit
	local right = normal:Cross(Vector3.yAxis)
	if right.Magnitude == 0 then
		right = normal:Cross(cf.ZVector)
		if right.Magnitude == 0 then
			right = normal:Cross(cf.UpVector)
		end

		if right.Magnitude == 0 then
			right = normal:Cross(Vector3.xAxis)
		end
	end

	right = right.Unit
	return CFrame.fromMatrix(position, right, right:Cross(normal).Unit, -normal)
end

return Orientation
