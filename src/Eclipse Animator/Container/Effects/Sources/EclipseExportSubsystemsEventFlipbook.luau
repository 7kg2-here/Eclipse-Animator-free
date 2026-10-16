--!nocheck
-- riftkuro

return function(require)
	local Orientation = require("./EventOrientation")
	local Flipbook = {}
	local textures = {}

	function Flipbook.ready(source)
		local texture = source.Texture
		if texture == "" then
			return true
		end
		if textures[texture] == nil then
			textures[texture] = false
			task.spawn(function()
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ texture })
				end)
				textures[texture] = true
			end)
		end
		return textures[texture]
	end

	function Flipbook.layout(source)
		local layout = source.FlipbookLayout
		if layout == Enum.ParticleFlipbookLayout.None then
			return 1, 1
		end
		if layout == Enum.ParticleFlipbookLayout.Grid2x2 then
			return 2, 2
		end
		if layout == Enum.ParticleFlipbookLayout.Grid4x4 then
			return 4, 4
		end
		if layout == Enum.ParticleFlipbookLayout.Grid8x8 then
			return 8, 8
		end
		return math.max(1, source.FlipbookSizeX), math.max(1, source.FlipbookSizeY)
	end

	function Flipbook.birth(source, noise)
		local x, y = Flipbook.layout(source)
		local rate = source.FlipbookFramerate
		return {
			rate = rate.Min + (rate.Max - rate.Min) * (noise[2] + 1) * 0.5,
			start = source.FlipbookStartRandom
					and math.min(x * y - 1, math.floor((noise[3] + 1) * 0.5 * x * y))
				or 0,
			seed = math.floor((noise[1] + 1) * 0.5 * 2147483646) + 1,
		}
	end

	function Flipbook.frames(source, particle)
		local x, y = Flipbook.layout(source)
		local count = x * y
		if count <= 1 then
			return 0, 0, 0, x, y
		end
		local data = particle.flipbook
		local mode = source.FlipbookMode
		local position = math.max(0, particle.age) * data.rate + data.start
		if mode == Enum.ParticleFlipbookMode.OneShot then
			position = math.clamp(particle.age / particle.life, 0, 1) * count + data.start
		end
		local index = math.floor(position + 1e-8)
		local function frame(step)
			if mode == Enum.ParticleFlipbookMode.OneShot then
				return math.min(step, count - 1)
			end
			if mode == Enum.ParticleFlipbookMode.PingPong then
				local phase = step % (2 * (count - 1))
				return phase < count and phase or 2 * (count - 1) - phase
			end
			if mode == Enum.ParticleFlipbookMode.Random then
				local seed = (data.seed + (step % 2147483647) * 48271) % 2147483647
				return Random.new(seed):NextInteger(0, count - 1)
			end
			return step % count
		end
		local first, last = frame(index), frame(index + 1)
		local blend = source.FlipbookBlendFrames and math.clamp(position - index, 0, 1) or 0
		return first, last, first ~= last and blend or 0, x, y
	end

	local function object(clock, class, parent)
		local result = Instance.new(class)

		result.Archivable = false
		clock.internal[result] = true
		result.Parent = parent
		return result
	end

	local function image(clock, parent)
		local label = object(clock, "ImageLabel", parent)
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		return label
	end

	function Flipbook.create(visual, clock)
		local part = object(clock, "Part", visual.attachment)
		part.Name = "EclipseEventFlipbook"
		part.Anchored = true
		part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
		part.Transparency, part.CastShadow = 1, false
		local gui = object(clock, "SurfaceGui", part)
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(256, 256)
		gui.Enabled = false
		gui.AlwaysOnTop = false
		gui.Adornee = part
		local group = object(clock, "Frame", gui)
		group.BackgroundTransparency = 1
		group.Size = UDim2.fromScale(1, 1)
		group.ClipsDescendants = true
		local first = image(clock, group)
		local second = image(clock, group)
		second.ZIndex = 2
		visual.sprite = { part = part, gui = gui, group = group, first = first, second = second }
		return visual.sprite
	end

	local function placeTile(label, state, mirrored)
		if
			state.mirrored == mirrored
			and state.placedIndex == state.index
			and state.placedX == state.x
			and state.placedY == state.y
		then
			return
		end
		local x, y, index = state.x, state.y, state.index
		if state.mirrored ~= mirrored or state.placedX ~= x or state.placedY ~= y then
			label.Size = UDim2.fromScale(mirrored and -x or x, y)
		end
		label.Position =
			UDim2.fromScale(mirrored and index % x + 1 or -(index % x), -math.floor(index / x))
		state.mirrored, state.placedIndex, state.placedX, state.placedY = mirrored, index, x, y
	end

	local function tile(label, texture, index, x, y, state, mirrored)
		state = state or {}
		if state.texture ~= texture then
			label.ImageContent = texture
			state.texture = texture
		end
		state.index, state.x, state.y = index, x, y
		placeTile(label, state, mirrored)
		return state
	end

	function Flipbook.orient(sprite, camera)
		if not sprite.gui.Enabled or not camera then
			return
		end
		local position = sprite.position
		local toward = camera.Position - position
		if toward.Magnitude < 1e-6 then
			toward = -camera.LookVector
		else
			toward = toward.Unit
		end
		local orientation = sprite.orientation
		local normal, up = -camera.LookVector, camera.UpVector
		local rotation = sprite.rotation
		local mirrored = false
		if orientation == Enum.ParticleOrientation.FacingCameraWorldUp then
			up = Vector3.yAxis
			normal = Vector3.new(toward.X, 0, toward.Z)
			if normal.Magnitude < 1e-6 then
				normal = Vector3.zAxis
			else
				normal = normal.Unit
			end
		elseif orientation == Enum.ParticleOrientation.VelocityParallel then
			mirrored = true
			local right = sprite.direction
			normal = normal - right * normal:Dot(right)
			if normal.Magnitude < 1e-6 then
				normal = camera.UpVector - right * camera.UpVector:Dot(right)
			end
			normal = normal.Unit
			up = right:Cross(normal)
		elseif orientation == Enum.ParticleOrientation.VelocityPerpendicular then
			normal = sprite.direction
			mirrored = normal:Dot(toward) >= 0
			if not mirrored then
				normal = -normal
				rotation = -rotation
			end
			up = sprite.up
		end
		if math.abs(normal:Dot(up)) > 0.999 then
			up = math.abs(normal.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
		end
		if sprite.mirrored ~= mirrored then
			sprite.mirrored = mirrored
			if sprite.firstTile then
				placeTile(sprite.first, sprite.firstTile, mirrored)
				placeTile(sprite.second, sprite.secondTile, mirrored)
			end
		end
		local depth = (position - camera.Position):Dot(camera.LookVector)
		local scale = depth > 1e-6 and math.max(0.001, depth - sprite.zOffset) / depth or 1
		position = camera.Position + (position - camera.Position) * scale
		if sprite.dimensions then
			local size = sprite.dimensions * scale
			sprite.part.Size = Vector3.new(math.max(0.001, size.X), math.max(0.001, size.Y), 0.001)
		end
		sprite.part.CFrame = CFrame.new(position)
			* CFrame.lookAt(Vector3.zero, normal, up)
			* CFrame.Angles(0, 0, math.rad(rotation))
	end

	function Flipbook.render(
		visual,
		clock,
		source,
		particle,
		position,
		cf,
		size,
		squash,
		color,
		transparency
	)
		local sprite = visual.sprite or Flipbook.create(visual, clock)
		local first, second, blend, x, y = Flipbook.frames(source, particle)
		sprite.frame, sprite.nextFrame, sprite.blend = first, second, blend
		local texture = source.TextureContent
		sprite.firstTile =
			tile(sprite.first, texture, first, x, y, sprite.firstTile, sprite.mirrored == true)
		sprite.secondTile =
			tile(sprite.second, texture, second, x, y, sprite.secondTile, sprite.mirrored == true)
		sprite.first.ImageColor3, sprite.second.ImageColor3 = color, color
		local opacity = (1 - transparency) * (1 - source.LocalTransparencyModifier)
		local overlay = opacity * blend
		sprite.first.ImageTransparency = 1 - opacity * (1 - blend) / math.max(1 - overlay, 1e-8)
		sprite.second.ImageTransparency = 1 - overlay
		sprite.second.Visible = blend > 0
		sprite.gui.LightInfluence = source.LightInfluence
		sprite.gui.Brightness = source.Brightness
		sprite.position, sprite.orientation = position, source.Orientation
		sprite.direction = Orientation.direction(particle)
		sprite.up = source.Orientation == Enum.ParticleOrientation.VelocityPerpendicular
				and Orientation.frame(particle.origin or cf, sprite.direction, Vector3.zero).UpVector
			or cf.UpVector
		sprite.rotation = particle.rotation + particle.spin * particle.age
		sprite.zOffset = source.ZOffset
		local stretch = 1 + math.abs(squash)
		local width, height = size * 2, size * 2
		if squash >= 0 then
			width /= stretch
			height *= stretch
		else
			width *= stretch
			height /= stretch
		end
		sprite.dimensions = Vector3.new(width, height, 0)
		sprite.gui.Enabled = size > 0 and opacity > 0
		local camera = workspace.CurrentCamera
		if camera then
			Flipbook.orient(sprite, camera.CFrame)
		else
			sprite.part.Size = Vector3.new(math.max(0.001, width), math.max(0.001, height), 0.001)
		end
	end

	function Flipbook.hide(visual)
		if visual.sprite then
			visual.sprite.gui.Enabled = false
		end
	end

	return Flipbook
end
