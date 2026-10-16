--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Dynamics = {}
local defaults = {
	Damping = 0.2,
	Stiffness = 0.2,
	Elasticity = 3,
	Inertia = 0.15,
	AnchorDepth = 1,
	Gravity = Vector3.new(0, -25, 0),
	Force = Vector3.zero,
	WindStrength = 1,
	WindSpeed = 1,
	WindDirection = Vector3.xAxis,
	WindInfluence = 1,
	Radius = 0.08,
	RotationLimit = 180,
	AnchorsRotate = false,
	ReverseMotion = false,
	Seed = 1,
}

local function unit(v, fallback)
	return v.Magnitude > 1e-7 and v.Unit or fallback
end

local function turn(a, b)
	a = unit(a, Vector3.yAxis)
	b = unit(b, a)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 0.999999 then
		return CFrame.identity
	end

	local axis = a:Cross(b)
	if axis.Magnitude < 1e-6 then
		axis = a:Cross(math.abs(a.X) < 0.8 and Vector3.xAxis or Vector3.yAxis)
	end

	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function collide(position, part, radius)
	if part:IsA("Terrain") then
		return position
	end

	local cf, size = part.CFrame, part.Size * 0.5
	local q = cf:PointToObjectSpace(position)
	if part:IsA("Part") and part.Shape == Enum.PartType.Ball then
		local r = math.max(size.X, size.Y, size.Z) + radius
		if q.Magnitude < r then
			q = unit(q, Vector3.yAxis) * r
		else
			return position
		end
	else
		size += Vector3.one * radius
		if math.abs(q.X) < size.X and math.abs(q.Y) < size.Y and math.abs(q.Z) < size.Z then
			local dx, dy, dz =
				size.X - math.abs(q.X), size.Y - math.abs(q.Y), size.Z - math.abs(q.Z)
			if dx <= dy and dx <= dz then
				q = Vector3.new(q.X < 0 and -size.X or size.X, q.Y, q.Z)
			elseif dy <= dz then
				q = Vector3.new(q.X, q.Y < 0 and -size.Y or size.Y, q.Z)
			else
				q = Vector3.new(q.X, q.Y, q.Z < 0 and -size.Z or size.Z)
			end
		else
			return position
		end
	end

	return cf:PointToWorldSpace(q)
end

function Dynamics.new(mesh, roots, options, colliders)
	options = options or {}
	local settings = table.clone(defaults)
	for key, value in settings do
		local attr = mesh:GetAttribute(key)
		if attr ~= nil and typeof(attr) == typeof(value) then
			settings[key] = attr
		end
	end

	for key, value in options do
		settings[key] = value
	end

	local nodes, seen = {}, {}

	local function append(bone, parent, depth)
		assert(not seen[bone], "Bone Dynamics roots overlap")
		seen[bone] = true
		local cf = bone.WorldCFrame
		local node = {
			bone = bone,
			parent = parent,
			children = {},
			depth = depth,
			position = cf.Position,
			velocity = Vector3.zero,
			animated = cf,
			previousInput = cf.Position,
			output = cf,
			anchored = parent == nil or depth <= settings.AnchorDepth,
		}
		node.length = parent and (cf.Position - parent.position).Magnitude or 0
		table.insert(nodes, node)
		if parent then
			table.insert(parent.children, node)
		end

		local children = {}
		for _, child in bone:GetChildren() do
			if child:IsA("Bone") then
				table.insert(children, child)
			end
		end

		table.sort(children, function(a, b)
			return a.Name < b.Name
		end)
		for _, child in children do
			append(child, node, depth + 1)
		end

		if #children == 0 then
			local length = math.max(node.length, 0.1)
			local direction = parent and unit(node.position - parent.position, cf.UpVector)
				or cf.UpVector
			local offset = cf:VectorToObjectSpace(direction * length)
			local tail = {
				parent = node,
				children = {},
				depth = depth + 1,
				length = length,
				offset = offset,
				anchored = false,
				position = node.position + direction * length,
				velocity = Vector3.zero,
				animated = cf * CFrame.new(offset),
				previousInput = node.position + direction * length,
			}
			table.insert(nodes, tail)
			table.insert(node.children, tail)
		end
	end

	for _, root in roots do
		append(root, nil, 0)
	end

	local parts, terrain = {}, nil
	for _, part in colliders or {} do
		if part:IsA("Terrain") then
			terrain = part
		else
			table.insert(parts, part)
		end
	end

	local terrainParams
	if terrain then
		terrainParams = RaycastParams.new()
		terrainParams.FilterType = Enum.RaycastFilterType.Include
		terrainParams.FilterDescendantsInstances = { terrain }
		terrainParams.IgnoreWater = true
	end

	local function constrain(n)
		local parent = n.parent
		local rest = unit(n.animated.Position - parent.animated.Position, Vector3.yAxis)
		local direction = unit(n.position - parent.position, rest)
		local limit = math.rad(
			math.min(settings.RotationLimit, 180 * (1 - math.clamp(settings.Stiffness, 0, 1)))
		)
		local angle = math.acos(math.clamp(rest:Dot(direction), -1, 1))
		if angle > limit and angle > 1e-7 then
			direction = turn(rest, direction)
				:Lerp(CFrame.identity, 1 - limit / angle)
				:VectorToWorldSpace(rest)
		end

		n.position = parent.position + direction * n.length
	end

	local self = { nodes = nodes, settings = settings, colliders = parts, destroyed = false }

	function self:step(dt, time)
		assert(not self.destroyed and dt > 0 and dt <= 0.1, "Invalid Bone Dynamics step")

		for _, n in nodes do
			n.animated = n.bone and n.bone.WorldCFrame or n.parent.animated * CFrame.new(n.offset)
		end

		local steps = math.max(1, math.ceil(dt * 240 - 1e-6))
		for step = 1, steps do
			local sampleTime = time - dt + step * dt / steps
			local dt = dt / steps
			local damping = math.exp(-math.clamp(settings.Damping, 0, 1) * 60 * dt)
			for index, n in nodes do
				local target = n.animated.Position
				if n.anchored then
					n.position = target
					n.velocity = Vector3.zero
				else
					local inertia = math.clamp(settings.Inertia, 0, 1)
						* (settings.ReverseMotion and -1 or 1)
					local transport = (target - n.previousInput) * (1 - inertia)
					n.position += transport
					local parent = n.parent
					local rest = parent.position + (target - parent.animated.Position)
					local phase = (settings.Seed or 1) * 0.731 + n.depth * 0.27 + index * 0.031
					local breeze = 0.55
						+ 0.3 * math.sin(sampleTime * 1.4 + phase)
						+ 0.15 * math.sin(sampleTime * 0.63 + phase * 2)
					local air = unit(settings.WindDirection, Vector3.zero)
						* settings.WindSpeed
						* breeze
					local wind = (air - n.velocity) * settings.WindStrength * settings.WindInfluence
					if settings.WindDirection.Magnitude < 1e-7 or settings.WindSpeed <= 0 then
						wind = Vector3.zero
					end

					local force = settings.Gravity
						+ settings.Force
						+ wind
						+ (rest - n.position) * (settings.Elasticity * 20)
					n.velocity = (n.velocity + force * dt) * damping
					if n.velocity.Magnitude > 80 then
						n.velocity = n.velocity.Unit * 80
					end

					n.before = n.position
					n.position += n.velocity * dt
				end

				n.previousInput = target
			end

			for _ = 1, 4 do
				for _, n in nodes do
					if not n.anchored then
						constrain(n)
						local constrained = n.position
						for _, part in self.colliders do
							if part.Parent then
								n.position = collide(n.position, part, settings.Radius)
							end
						end

						if terrain and terrain.Parent then
							local travel = n.position - n.before
							if travel.Magnitude > 1e-7 then
								local radius = math.clamp(settings.Radius, 0, 512)
								local hit
								if radius > 0 then
									hit = workspace:Spherecast(
										n.before,
										radius,
										travel,
										terrainParams
									)
								else
									hit = workspace:Raycast(n.before, travel, terrainParams)
								end

								if not hit then
									local origin = n.parent.position
									local span = n.position - origin
									if span.Magnitude > 1e-7 then
										if radius > 0 then
											hit = workspace:Spherecast(
												origin,
												radius,
												span,
												terrainParams
											)
										else
											hit = workspace:Raycast(origin, span, terrainParams)
										end
									end
								end

								if hit then
									local depth = radius
										+ 0.001
										- (n.position - hit.Position):Dot(hit.Normal)
									if depth > 0 then
										n.position += hit.Normal * depth
									end
								end
							end
						end

						if n.position ~= constrained then
							constrain(n)
						end
					end
				end
			end

			for _, n in nodes do
				if not n.anchored then
					n.velocity = (n.position - n.before) / dt
				end
			end
		end

		for _, n in nodes do
			if n.bone then
				local rotation = n.animated.Rotation
				if not n.anchored or settings.AnchorsRotate then
					local original, simulated = Vector3.zero, Vector3.zero
					for _, child in n.children do
						original += unit(
							child.animated.Position - n.animated.Position,
							Vector3.yAxis
						)
						simulated += unit(child.position - n.position, Vector3.yAxis)
					end

					if original.Magnitude > 1e-6 and simulated.Magnitude > 1e-6 then
						rotation = turn(original, simulated) * rotation
					end
				end

				n.output = CFrame.new(n.position) * rotation
				n.bone.WorldCFrame = n.output
			end
		end
	end

	function self:destroy()
		self.destroyed = true
		table.clear(self.nodes)
		table.clear(self.colliders)
	end

	return self
end

return Dynamics
