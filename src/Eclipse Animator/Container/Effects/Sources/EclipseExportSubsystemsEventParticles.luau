--!nocheck
-- riftkuro

return function(require)
	local Flipbook = require("./EventFlipbook")
	local Orientation = require("./EventOrientation")
	local Cleanup = require("./EventCleanup")
	local Particles = {}
	Particles.__index = Particles

	local LIMIT = 512
	local LOG_TWO = math.log(2)
	local nativeProperties = {
		"TextureContent",
		"Color",
		"Size",
		"Transparency",
		"Squash",
		"Rotation",
		"RotSpeed",
		"Lifetime",
		"Speed",
		"SpreadAngle",
		"Acceleration",
		"Drag",
		"EmissionDirection",
		"Shape",
		"ShapeStyle",
		"ShapeInOut",
		"ShapePartial",
		"LockedToPart",
		"VelocityInheritance",
		"WindAffectsDrag",
		"Orientation",
		"FlipbookLayout",
		"FlipbookSizeX",
		"FlipbookSizeY",
		"FlipbookMode",
		"FlipbookFramerate",
		"FlipbookStartRandom",
		"FlipbookBlendFrames",
		"LightEmission",
		"LightInfluence",
		"Brightness",
		"ZOffset",
		"LocalTransparencyModifier",
	}
	local nativePropertySet = {}
	for _, key in nativeProperties do
		nativePropertySet[key] = true
	end
	local function nativeSource(key)
		return type(key) == "table" and key.source or key
	end
	local function nativeRate(key)
		return type(key) == "table" and key.rate or 1
	end

	local function sample(keys, age, noise)
		local left = keys[1]
		for index = 2, #keys do
			local right = keys[index]
			if age <= right.Time then
				local alpha =
					math.clamp((age - left.Time) / math.max(right.Time - left.Time, 1e-8), 0, 1)
				if typeof(left.Value) == "Color3" then
					return left.Value:Lerp(right.Value, alpha)
				end
				local a = left.Value + left.Envelope * (noise[index - 1] or 0)
				local b = right.Value + right.Envelope * (noise[index] or 0)
				return a + (b - a) * alpha
			end
			left = right
		end
		return typeof(left.Value) == "Color3" and left.Value
			or left.Value + left.Envelope * (noise[#keys] or 0)
	end

	local function transform(emitter)
		local parent = emitter.Parent
		if parent and parent:IsA("Attachment") then
			return parent.WorldCFrame, Vector3.zero
		end
		if parent and parent:IsA("BasePart") then
			return parent.CFrame, parent.Size
		end
		return CFrame.identity, Vector3.zero
	end

	function Particles.new(clock, pool)
		for _, visual in pool or {} do
			clock.internal[visual.attachment] = true
			for _, child in visual.attachment:GetDescendants() do
				clock.internal[child] = true
			end
		end
		return setmetatable({
			clock = clock,
			emitters = {},
			emitterOrder = {},
			live = {},
			pool = table.clone(pool or {}),
			created = pool or {},
			dropped = 0,
			nativeOutputs = {},
			nativeDirty = {},
			nativeKeys = {},
			nativeRevision = {},
			nativeApplied = {},
			native = false,
		}, Particles)
	end

	function Particles:setNative(enabled, hold)
		local mode = enabled and "play" or hold and "hold" or "seek"
		if self.mode == mode then
			return
		end
		self.mode, self.native = mode, enabled
		for key, output in self.nativeOutputs do
			local source = nativeSource(key)
			if not output.Parent then
				continue
			end
			output.Enabled = false
			output.TimeScale = enabled
					and self:track(source).TimeScale * math.min(1, nativeRate(key))
				or 0
			if mode == "seek" then
				output:Clear()
			end
		end
		if mode == "seek" then
			for _, p in self.live do
				p.native = false
			end
		end
	end

	function Particles:markNativeDirty(source, key)
		if not self.emitters[source] then
			return
		end
		if key == "Texture" then
			key = "TextureContent"
		end
		if key ~= "Parent" and key ~= "TimeScale" and not nativePropertySet[key] then
			return
		end
		self.nativeRevision[source] = (self.nativeRevision[source] or 0) + 1
	end

	function Particles:nativeOutput(source, rate)
		rate = rate or 1
		local keys = self.nativeKeys[source]
		if not keys then
			keys = {}
			self.nativeKeys[source] = keys
		end
		local key = keys[rate]
		if not key then
			key = rate == 1 and source or { source = source, rate = rate }
			keys[rate] = key
		end
		local output = self.nativeOutputs[key]
		if not output or output.Parent ~= source.Parent then
			if output then
				output:Destroy()
				self.nativeApplied[output] = nil
			end
			local archivable = source.Archivable
			local dependencies = self.clock.dependencies
			if dependencies then
				dependencies:before(source, "Archivable")
			end
			source.Archivable = true
			if dependencies then
				dependencies:after(source, "Archivable")
			end
			local ok, clone = pcall(function()
				return source:Clone()
			end)
			if dependencies then
				dependencies:before(source, "Archivable")
			end
			source.Archivable = archivable
			if dependencies then
				dependencies:after(source, "Archivable")
			end
			assert(ok and clone, clone)
			output = clone
			output.Name, output.Archivable, output.Enabled = "EclipseEventPlayback", false, false
			self.clock.internal[output] = true
			for _, child in output:GetDescendants() do
				self.clock.internal[child] = true
			end
			Cleanup.visual(output)
			output.Parent = source.Parent
			self.nativeOutputs[key] = output
		end
		local revision = self.nativeRevision[source] or 0
		if self.nativeApplied[output] ~= revision then
			local stretch = math.max(1, rate)
			for _, property in nativeProperties do
				local value = source[property]
				if property == "Lifetime" then
					value = NumberRange.new(value.Min / stretch, value.Max / stretch)
				elseif
					property == "Speed"
					or property == "RotSpeed"
					or property == "FlipbookFramerate"
				then
					value = NumberRange.new(value.Min * stretch, value.Max * stretch)
				elseif property == "Acceleration" then
					value *= stretch * stretch
				elseif property == "Drag" or property == "VelocityInheritance" then
					value *= stretch
				end
				if output[property] ~= value then
					output[property] = value
				end
			end
			self.nativeApplied[output] = revision
		end
		output.TimeScale = self.native and self:track(source).TimeScale * math.min(1, rate) or 0
		return output
	end

	function Particles:active()
		if #self.live > 0 then
			return true
		end
		for emitter, state in self.emitters do
			if emitter.Parent and state.Enabled then
				return true
			end
		end
		return false
	end

	function Particles:retainDisplay()
		local display, retained = {}, {}
		for _, particle in self.live do
			local visual = particle.visual
			if visual and not retained[visual] then
				retained[visual] = true
				table.insert(display, visual)
			end
			particle.visual = nil
		end
		local created = {}
		for _, visual in self.created do
			if not retained[visual] then
				table.insert(created, visual)
			end
		end
		self.created = created
		for key, output in self.nativeOutputs do
			local source = nativeSource(key)
			if not output.Parent then
				continue
			end
			output.Enabled, output.TimeScale = false, 0
			table.insert(display, { root = output, emitter = output })
		end
		table.clear(self.nativeOutputs)
		table.clear(self.nativeApplied)
		return display
	end

	function Particles:track(emitter)
		local state = self.emitters[emitter]
		if state then
			return state
		end
		local tilesX, tilesY = Flipbook.layout(emitter)
		if tilesX * tilesY > 1 then
			Flipbook.ready(emitter)
		end
		local dependencies = self.clock.dependencies
		if dependencies then
			dependencies:watch(emitter, true)
		end
		state = {
			source = emitter,
			Enabled = emitter.Enabled,
			TimeScale = emitter.TimeScale,
			rate = self.clock:rate(),
			fraction = 0,
			previousCFrame = transform(emitter),
		}
		self.emitters[emitter] = state
		table.insert(self.emitterOrder, state)
		if state.Enabled then
			self.clock:remember(emitter, "Enabled")
		end
		self.clock:remember(emitter, "TimeScale")
		if state.Enabled then
			if dependencies then
				dependencies:before(emitter, "Enabled")
			end
			emitter.Enabled = false
			if dependencies then
				dependencies:after(emitter, "Enabled")
			end
		end
		if dependencies then
			dependencies:before(emitter, "TimeScale")
		end
		emitter.TimeScale = 0
		if dependencies then
			dependencies:after(emitter, "TimeScale")
		end
		table.insert(
			self.clock.connections,
			emitter.Changed:Connect(function(key)
				self:markNativeDirty(emitter, key)
			end)
		)
		return state
	end

	function Particles:clear(emitter)
		for key, output in self.nativeOutputs do
			if nativeSource(key) == emitter then
				output:Clear()
			end
		end
		for index = #self.live, 1, -1 do
			if self.live[index].source == emitter then
				self:release(index)
			end
		end
	end

	function Particles:release(index)
		local particle = self.live[index]
		if particle.visual then
			particle.visual.emitter:Clear()
			Flipbook.hide(particle.visual)
			table.insert(self.pool, particle.visual)
		end
		self.live[index] = self.live[#self.live]
		self.live[#self.live] = nil
	end

	function Particles:emit(emitter, count, emission, rate)
		local state = self:track(emitter)
		rate = rate or self.clock:rate()
		local random = self.clock.particleRandom or self.clock.random
		local requested = math.max(0, math.floor(tonumber(count) or 16))
		if self.native and requested > 0 then
			self:nativeOutput(emitter, rate):Emit(requested)
		end
		if self.native and self.clock.options.nativeOnly then
			return
		end
		count = math.min(requested, LIMIT - #self.live)
		self.dropped += requested - count
		local currentCF, size = transform(emitter)
		if not emission then
			state.previousCFrame = currentCF
		end
		local basis = Orientation.emissionFrame(emitter.EmissionDirection)
		for index = 1, count do
			local age = emission
					and math.max(0, (emission.count - index) * emission.interval + emission.tail)
				or 0
			local cf = emission
					and emission.from:Lerp(
						currentCF,
						math.clamp(1 - age / math.max(emission.delta, 1e-8), 0, 1)
					)
				or currentCF
			local life = random:NextNumber(
				math.min(20, emitter.Lifetime.Min),
				math.min(20, emitter.Lifetime.Max)
			)
			if life <= 0 then
				continue
			end
			local noise = {}
			for index = 1, 20 do
				noise[index] = random:NextNumber(-1, 1)
			end
			local offset = Vector3.new(
				random:NextNumber(-0.5, 0.5),
				random:NextNumber(-0.5, 0.5),
				random:NextNumber(-0.5, 0.5)
			) * size
			local normal
			if emitter.Shape == Enum.ParticleEmitterShape.Sphere then
				local y = random:NextNumber(-1, 1)
				local angle = random:NextNumber(0, math.pi * 2)
				normal = Vector3.new(
					math.sqrt(1 - y * y) * math.cos(angle),
					y,
					math.sqrt(1 - y * y) * math.sin(angle)
				)
				local radius = emitter.ShapeStyle == Enum.ParticleEmitterShapeStyle.Surface and 1
					or random:NextNumber() ^ (1 / 3)
				offset = normal * size * 0.5 * radius
			elseif
				emitter.Shape == Enum.ParticleEmitterShape.Cylinder
				or emitter.Shape == Enum.ParticleEmitterShape.Disc
			then
				local angle = random:NextNumber(0, math.pi * 2)
				normal = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local radius = emitter.ShapeStyle == Enum.ParticleEmitterShapeStyle.Surface and 1
					or math.sqrt(random:NextNumber())
				offset = normal * size * 0.5 * radius
					+ Vector3.new(
						0,
						emitter.Shape == Enum.ParticleEmitterShape.Disc and 0
							or random:NextNumber(-0.5, 0.5) * size.Y,
						0
					)
			elseif
				size.Magnitude > 0
				and emitter.ShapeStyle == Enum.ParticleEmitterShapeStyle.Surface
			then
				local face = random:NextInteger(1, 3)
				local sign = random:NextInteger(0, 1) * 2 - 1
				if face == 1 then
					offset = Vector3.new(size.X * 0.5 * sign, offset.Y, offset.Z)
					normal = Vector3.xAxis * sign
				end
				if face == 2 then
					offset = Vector3.new(offset.X, size.Y * 0.5 * sign, offset.Z)
					normal = Vector3.yAxis * sign
				end
				if face == 3 then
					offset = Vector3.new(offset.X, offset.Y, size.Z * 0.5 * sign)
					normal = Vector3.zAxis * sign
				end
			end
			local spread = emitter.SpreadAngle
			local ray = (basis * CFrame.Angles(
				math.rad(random:NextNumber(-spread.X, spread.X)),
				math.rad(random:NextNumber(-spread.Y, spread.Y)),
				0
			)).LookVector
			if normal then
				if emitter.ShapeInOut == Enum.ParticleEmitterShapeInOut.Inward then
					ray = -normal
				elseif emitter.ShapeInOut == Enum.ParticleEmitterShapeInOut.Outward then
					ray = normal
				end
			end
			local parent = emitter.Parent
			local velocityPart = parent
				and (
					parent:IsA("BasePart") and parent
					or parent:FindFirstAncestorWhichIsA("BasePart")
				)
			local inherited = velocityPart
					and velocityPart.AssemblyLinearVelocity * emitter.VelocityInheritance
				or Vector3.zero
			local particle = {
				source = emitter,
				state = state,
				rate = rate,
				age = 0,
				life = life,
				origin = cf,
				position = offset,
				native = self.native,
				direction = cf:VectorToWorldSpace(ray),
				flipbook = Flipbook.birth(emitter, noise),
				velocity = cf:VectorToWorldSpace(ray)
						* random:NextNumber(emitter.Speed.Min, emitter.Speed.Max)
					+ inherited,
				rotation = random:NextNumber(emitter.Rotation.Min, emitter.Rotation.Max),
				spin = random:NextNumber(emitter.RotSpeed.Min, emitter.RotSpeed.Max),
				noise = noise,
			}
			if age > 0 then
				self:age(particle, age)
			end
			if particle.age < particle.life - 1e-8 then
				table.insert(self.live, particle)
			end
		end
	end

	function Particles:age(p, delta)
		p.age += delta
		local drag = math.max(0, p.source.Drag) * LOG_TWO
		local acceleration = p.source.Acceleration
		local displacement
		if drag > 1e-5 then
			local decay = math.exp(-drag * delta)
			displacement = p.velocity * (1 - decay) / drag
				+ acceleration * (delta / drag - (1 - decay) / (drag * drag))
			p.velocity = p.velocity * decay + acceleration * (1 - decay) / drag
		else
			displacement = p.velocity * delta + acceleration * (0.5 * delta * delta)
			p.velocity += acceleration * delta
		end
		p.position += p.origin:VectorToObjectSpace(displacement)
	end

	function Particles:step(dt)
		for index = #self.live, 1, -1 do
			local p = self.live[index]
			if not p.source.Parent then
				self:release(index)
				continue
			end
			self:age(p, dt * p.state.TimeScale * (p.rate or 1))
			if p.age >= p.life - 1e-8 then
				self:release(index)
			end
		end
		local write = 1
		for _, state in self.emitterOrder do
			local emitter = state.source
			if self.emitters[emitter] ~= state then
				continue
			end
			if not emitter.Parent then
				self.emitters[emitter] = nil
				continue
			end
			self.emitterOrder[write] = state
			write += 1
			local from = state.previousCFrame
			local nativeOnly = self.native and self.clock.options.nativeOnly
			if not nativeOnly then
				state.previousCFrame = transform(emitter)
			end
			if not state.Enabled or emitter.Rate <= 0 then
				continue
			end
			local delta = dt * state.TimeScale * (state.rate or 1)
			state.fraction += emitter.Rate * delta
			local count = math.floor(state.fraction + 1e-8)
			state.fraction = math.max(0, state.fraction - count)
			if count > 0 then
				if nativeOnly then
					self:emit(emitter, count, nil, state.rate)
				else
					self:emit(emitter, count, {
						count = count,
						interval = 1 / emitter.Rate,
						tail = state.fraction / emitter.Rate,
						delta = delta,
						from = from,
					}, state.rate)
				end
			end
		end
		for index = #self.emitterOrder, write, -1 do
			self.emitterOrder[index] = nil
		end
	end

	function Particles:visual()
		local item = table.remove(self.pool)
		if item then
			return item
		end
		local attachment = Instance.new("Attachment")

		attachment.Name, attachment.Archivable = "EclipseEventParticle", false
		self.clock.internal[attachment] = true
		Cleanup.visual(attachment)
		attachment.Parent = workspace.Terrain
		local emitter = Instance.new("ParticleEmitter")

		self.clock.internal[emitter] = true
		emitter.Enabled, emitter.TimeScale = false, 0
		emitter.Speed, emitter.Lifetime = NumberRange.new(0), NumberRange.new(100)
		emitter.LockedToPart = true
		emitter.Parent = attachment
		item = { attachment = attachment, emitter = emitter }
		table.insert(self.created, item)
		return item
	end

	function Particles:captureFrame()
		local result = table.create(#self.live)
		for index, p in self.live do
			result[index] = { p, p.age, p.position, p.velocity }
		end
		return result
	end

	function Particles:releaseFrame()
		for _, p in self.live do
			if p.visual then
				p.visual.emitter:Clear()
				Flipbook.hide(p.visual)
				table.insert(self.pool, p.visual)
				p.visual = nil
			end
		end
	end

	function Particles:showFrame(frame)
		if not self.savedLive then
			self:setNative(false, false)
			for _, output in self.nativeOutputs do
				output:Destroy()
			end
			table.clear(self.nativeOutputs)
			table.clear(self.nativeApplied)
			self.savedLive = self.live
		end
		local visuals = {}
		for _, p in self.live do
			if p.visual then
				visuals[p.frameIdentity or p] = p.visual
				p.visual = nil
			end
		end
		self.live = table.create(#frame)
		for index, sample in frame do
			local identity = sample[1]
			local p = table.clone(identity)
			p.age, p.position, p.velocity = sample[2], sample[3], sample[4]
			p.frameIdentity = identity
			p.visual, p.native = visuals[identity], false
			visuals[identity] = nil
			self.live[index] = p
		end
		for _, visual in visuals do
			visual.emitter:Clear()
			Flipbook.hide(visual)
			table.insert(self.pool, visual)
		end
	end

	function Particles:restoreFrame()
		if not self.savedLive then
			return
		end
		self:releaseFrame()
		self.live, self.savedLive = self.savedLive, nil
	end

	function Particles:prepare(deadline)
		local ready = true
		self.pendingTextures = false
		for _, p in self.live do
			if p.native then
				continue
			end
			local x, y = Flipbook.layout(p.source)
			if x * y > 1 and not Flipbook.ready(p.source) then
				self.pendingTextures = true
			end
			if not p.visual or x * y > 1 and not p.visual.sprite then
				if os.clock() >= deadline then
					return false
				end
				p.visual = p.visual or self:visual()
				if x * y > 1 and not p.visual.sprite then
					Flipbook.create(p.visual, self.clock)
				end
			end
		end
		return ready
	end

	function Particles:render(preparedOnly)
		if self.native then
			for key, output in self.nativeOutputs do
				local source = nativeSource(key)
				if not source.Parent then
					output:Destroy()
					self.nativeOutputs[key] = nil
					self.nativeApplied[output] = nil
					self.nativeKeys[source] = nil
				else
					self:nativeOutput(source, nativeRate(key))
				end
			end
		end
		if #self.live == 0 then
			return
		end
		local renderSequences = {}
		for _, p in self.live do
			if p.native then
				continue
			end
			local source = p.source
			if preparedOnly then
				local x, y = Flipbook.layout(source)
				if
					not p.visual
					or x * y > 1 and (not p.visual.sprite or not Flipbook.ready(source))
				then
					continue
				end
			end
			local sequences = renderSequences[source]
			if not sequences then
				local state = p.state
				sequences = state.sequences or {}
				state.sequences = sequences
				for _, key in { "Color", "Size", "Transparency", "Squash" } do
					local value = source[key]
					if sequences[key] ~= value then
						sequences[key] = value
						sequences[key .. "Keys"] = value.Keypoints
					end
				end
				renderSequences[source] = sequences
			end
			local age = math.clamp(p.age / p.life, 0, 1)
			local visual = p.visual or self:visual()
			p.visual = visual
			local cf = source.LockedToPart and transform(source) or p.origin
			local worldPosition = cf:PointToWorldSpace(p.position)
			local output = visual.emitter
			output.Orientation = source.Orientation
			local x, y = Flipbook.layout(source)
			if x * y > 1 then
				output:Clear()
				Flipbook.render(
					visual,
					self.clock,
					source,
					p,
					worldPosition,
					cf,
					math.max(0, sample(sequences.SizeKeys, age, p.noise)),
					sample(sequences.SquashKeys, age, p.noise),
					sample(sequences.ColorKeys, age, p.noise),
					math.clamp(sample(sequences.TransparencyKeys, age, p.noise), 0, 1)
				)
				continue
			end
			local orientation = source.Orientation
			if
				orientation == Enum.ParticleOrientation.VelocityParallel
				or orientation == Enum.ParticleOrientation.VelocityPerpendicular
			then
				local direction = Orientation.direction(p)
				local basis = Orientation.frame(p.origin or cf, direction, worldPosition)
				visual.attachment.CFrame = basis
			else
				visual.attachment.CFrame = cf * CFrame.new(p.position)
			end
			Flipbook.hide(visual)
			output.TextureContent = source.TextureContent
			output.FlipbookLayout = Enum.ParticleFlipbookLayout.None
			output.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
			output.FlipbookStartRandom = false
			output.Color = ColorSequence.new(sample(sequences.ColorKeys, age, p.noise))
			output.Size = NumberSequence.new(math.max(0, sample(sequences.SizeKeys, age, p.noise)))
			output.Transparency = NumberSequence.new(
				math.clamp(sample(sequences.TransparencyKeys, age, p.noise), 0, 1)
			)
			output.Squash = NumberSequence.new(sample(sequences.SquashKeys, age, p.noise))
			output.Rotation = NumberRange.new(p.rotation + p.spin * p.age)
			output.LightEmission, output.LightInfluence =
				source.LightEmission, source.LightInfluence
			output.Brightness, output.ZOffset = source.Brightness, source.ZOffset
			output.LocalTransparencyModifier = source.LocalTransparencyModifier
			output.Orientation = source.Orientation
			output.EmissionDirection = Enum.NormalId.Front
			output.Speed = NumberRange.new(1)
			output:Clear()
			output:Emit(1)
		end
	end

	function Particles:updateCamera()
		if self.pendingTextures then
			self:prepare(os.clock() + 0.003)
			self:render(true)
		end
		local camera = workspace.CurrentCamera
		if not camera or self.cameraCFrame == camera.CFrame then
			return
		end
		self.cameraCFrame = camera.CFrame
		for _, p in self.live do
			if p.visual and p.visual.sprite then
				Flipbook.orient(p.visual.sprite, camera.CFrame)
			end
		end
	end

	function Particles:recycleDisplay(visual)
		visual.emitter:Clear()
		Flipbook.hide(visual)
		self.clock.internal[visual.attachment] = true
		for _, child in visual.attachment:GetDescendants() do
			self.clock.internal[child] = true
		end
		table.insert(self.created, visual)
		table.insert(self.pool, visual)
	end

	function Particles:destroy(keep)
		for _, output in self.nativeOutputs do
			output:Destroy()
		end
		table.clear(self.nativeOutputs)
		table.clear(self.nativeApplied)
		table.clear(self.nativeDirty)
		local result = keep and self.created or nil
		for _, item in self.created do
			if keep then
				item.emitter:Clear()
				Flipbook.hide(item)
			else
				item.attachment:Destroy()
			end
		end
		self.created = {}
		table.clear(self.live)
		table.clear(self.pool)
		table.clear(self.emitters)
		table.clear(self.emitterOrder)
		self.savedLive = nil
		return result
	end

	return Particles
end
