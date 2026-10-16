--!nocheck
-- riftkuro

--[[
-- the in game copy of the preview clock, same idea as Clock in the plugin
-- cutscene events run on a clock the cutscene owns so pausing, seeking and speed changes stay in sync
-- it tracks what events create so stopping the cutscene can clean up after them
-- http, datastores, messaging, teleports and remotes are REFUSED inside events, a cutscene has NO business doing those!!!

please stop taking this down roblox it's not anythign stupidddd pelaseee devrellll ohmygoddd -riftkuro
]]

local require = require(script:FindFirstAncestor("Container").Require)

local Particles = require("Particles")
local Cleanup = require("DumpStorage")
local EclipseStorage = require("root")
local NativeVFX = require("NativeVFX")
local NativeEmitData = require("ClipboardRows")
local Dependencies = require("EventDependencies")
local NativeTween = game:GetService("TweenService")
local Clock = {}
Clock.__index = Clock
local previewHttp = { JSONEncode = true, JSONDecode = true, GenerateGUID = true, UrlEncode = true }
local WAIT = {}
local SLEEP = {}
local NIL = {}
local EMPTY_ARGS = table.freeze({ n = 0 })
local STEP = 1 / 60
local PREVIEW_EPOCH = DateTime.now().UnixTimestampMillis / 1000
local getChildren, getDescendants = game.GetChildren, game.GetDescendants
local getAttribute, getAttributes, isA = game.GetAttribute, game.GetAttributes, game.IsA

local function propertyKey(object, key)
	if key == "BrickColor" and object:IsA("BasePart") then
		return "Color"
	end

	if key == "Position" or key == "Orientation" or key == "Rotation" then
		if object:IsA("BasePart") or object:IsA("Attachment") then
			return "CFrame"
		end
	elseif key == "Axis" or key == "SecondaryAxis" then
		if object:IsA("Attachment") then
			return "CFrame"
		end
	elseif key == "Texture" and (object:IsA("ParticleEmitter") or object:IsA("Decal")) then
		return "TextureContent"
	end

	return key
end

local function stored(value)
	if value == NIL then
		return nil
	end

	return value
end

local function signal(clock, frameSignal)
	local value = { listeners = {}, order = {} }
	table.insert(clock.virtualSignals, value)
	clock.virtualTypes[value] = "RBXScriptSignal"

	function value:Connect(callback)
		local connection = { Connected = true, domain = clock.domain }
		clock.virtualTypes[connection] = "RBXScriptConnection"

		function connection:Disconnect()
			self.Connected = false
			value.listeners[self] = nil
		end

		connection.disconnect = connection.Disconnect
		self.listeners[connection] = callback
		table.insert(self.order, connection)
		return connection
	end

	value.connect = value.Connect
	value.ConnectParallel = value.Connect

	function value:Once(callback)
		local connection
		local fired = false
		connection = self:Connect(function(...)
			if fired then
				return
			end

			fired = true
			connection:Disconnect()
			callback(...)
		end)
		return connection
	end

	function value:Wait()
		local thread = coroutine.running()
		self:Once(function(...)
			clock:queue(thread, clock.now, table.pack(...))
		end)
		return coroutine.yield(WAIT)
	end

	value.wait = value.Wait

	function value:Fire(...)
		if clock.closed or #self.order == 0 then
			return
		end

		local shared = table.pack(...)
		local write = 1
		for _, connection in self.order do
			local callback = self.listeners[connection]
			if connection.Connected and callback then
				self.order[write] = connection
				write += 1
				local args = shared
				if frameSignal then
					local rate = connection.domain and connection.domain.rate or 1
					if rate ~= 1 then
						args = table.clone(shared)
						args[args.n] *= rate
						if args.n == 2 then
							args[1] = clock:localTime(connection.domain)
						end
					end
				end

				clock:spawnPacked(connection.domain, callback, args)
			end
		end

		for index = #self.order, write, -1 do
			self.order[index] = nil
		end
	end

	return value
end

function Clock.new(options)
	local self = setmetatable({
		now = 0,
		jobs = {},
		freeJobs = {},
		serial = 0,
		closed = false,
		owned = {},
		originals = {},
		attributes = {},
		proxies = {},
		raw = {},
		internal = {},
		hidden = {},
		staging = options.staging == true,
		modules = {},
		loading = {},
		sourceCache = options.sourceCache or {},
		services = {},
		signals = {},
		connections = {},
		virtualSignals = {},
		tweens = {},
		animationTracks = {},
		bindings = {},
		random = Random.new(81739),
		tags = {},
		scales = {},
		classNames = {},
		threads = {},
		threadDomains = setmetatable({}, { __mode = "k" }),
		virtualTypes = setmetatable({}, { __mode = "k" }),
		epoch = options.epoch or PREVIEW_EPOCH,
		warnings = {},
		callbacks = 0,
		options = options,
		step = STEP,
		unitDomain = { rate = 1, origin = 0 },
		retired = {},
		ownedCount = 0,
		frameEpoch = 0,
		frameProperties = options.cacheFrames and {} or nil,
		frameAttributes = options.cacheFrames and {} or nil,
		particleRandom = options.nativeOnly and Random.new(81739) or nil,
	}, Clock)
	self.cleanup = Cleanup.new()
	self.dependencies = Dependencies.new(self, NIL)
	self.particles = Particles.new(self, options.visualPool)
	self.render, self.heartbeat, self.stepped =
		signal(self, true), signal(self, true), signal(self, true)
	self.preSimulation, self.preAnimation = signal(self, true), signal(self, true)
	self.instanceMethods = {
		GetAttribute = function(proxy, name)
			local object = self.raw[proxy]
			local value = getAttribute(object, name)
			if self.dependencies and self.dependencies.read then
				self.dependencies:read(object, name, value, "Attribute")
			end

			return value
		end,
		GetAttributes = function(proxy)
			local object = self.raw[proxy]
			local values = getAttributes(object)
			if self.dependencies and self.dependencies.readAttributes then
				self.dependencies:readAttributes(object, values)
			end

			return values
		end,
		IsA = function(proxy, name)
			return isA(self.raw[proxy], name)
		end,
	}
	for _, key in { "GetChildren", "GetDescendants" } do
		local query = key == "GetChildren" and getChildren or getDescendants
		self.instanceMethods[key] = function(proxy)
			local items = query(self.raw[proxy])
			local count = #items
			if count == 0 then
				return items
			end

			local write = 1
			local internal, proxies, raw, mt =
				self.internal, self.proxies, self.raw, self.proxyMetatable
			for index = 1, count do
				local child = items[index]
				if not internal[child] then
					local wrapped = proxies[child]
					if not wrapped then
						wrapped = setmetatable({}, mt)
						proxies[child], raw[wrapped] = wrapped, child
					end

					items[write] = wrapped
					write += 1
				end
			end

			for index = count, write, -1 do
				items[index] = nil
			end

			return items
		end
	end

	self.proxyMetatable = {
		__index = function(proxy, key)
			local method = self.instanceMethods[key]
			if method then
				return method
			end

			local result = self:read(self.raw[proxy], key)
			if type(result) == "function" then
				rawset(proxy, key, result)
			end

			return result
		end,
		__newindex = function(proxy, key, value)
			self:write(self.raw[proxy], key, value)
		end,
		__tostring = function(proxy)
			return tostring(self.raw[proxy])
		end,
	}
	return self
end

function Clock:report(message)
	message = tostring(message)
	if self.warnings[message] then
		return
	end

	self.warnings[message] = true
	if self.options.onError then
		self.options.onError(message)
	else
		warn("Eclipse event preview: " .. message)
	end
end

function Clock:rate()
	return self.domain and self.domain.rate or 1
end

function Clock:localTime(domain)
	domain = domain or self.domain
	return domain and domain.origin + (self.now - domain.origin) * domain.rate or self.now
end

function Clock:spawnPacked(domain, fn, args)
	local thread = coroutine.create(fn)
	self.threadDomains[thread] = domain or self.unitDomain
	return self:queue(thread, self.now, args)
end

function Clock:spawnIn(domain, fn, ...)
	return self:spawnPacked(domain, fn, table.pack(...))
end

function Clock:queue(thread, due, args)
	if self.closed then
		return thread
	end

	self.threads[thread] = true
	self.threadDomains[thread] = self.threadDomains[thread] or self.domain or self.unitDomain
	self.serial += 1
	local job = table.remove(self.freeJobs) or {}
	job.thread, job.due, job.args, job.id = thread, due, args or EMPTY_ARGS, self.serial
	local index = #self.jobs + 1
	while index > 1 do
		local parent = math.floor(index / 2)
		local prior = self.jobs[parent]
		if prior.due < due or prior.due == due and prior.id < job.id then
			break
		end

		self.jobs[index] = prior
		index = parent
	end

	self.jobs[index] = job
	return thread
end

function Clock:pop()
	local first, last = self.jobs[1], table.remove(self.jobs)
	if #self.jobs > 0 then
		local index = 1
		while index * 2 <= #self.jobs do
			local child = index * 2
			local left, right = self.jobs[child], self.jobs[child + 1]
			if right and (right.due < left.due or right.due == left.due and right.id < left.id) then
				child += 1
			end

			local nextJob = self.jobs[child]
			if last.due < nextJob.due or last.due == nextJob.due and last.id < nextJob.id then
				break
			end

			self.jobs[index] = nextJob
			index = child
		end

		self.jobs[index] = last
	end

	return first
end

function Clock:resume(thread, args, reportError)
	if self.closed or coroutine.status(thread) == "dead" then
		return false, "Cannot resume an ended event coroutine"
	end

	self.threads[thread] = true
	self.threadDomains[thread] = self.threadDomains[thread] or self.domain or self.unitDomain
	self.callbacks += 1
	local previousDomain = self.domain
	self.domain = self.threadDomains[thread]
	local rate = self:rate()
	local result = table.pack(coroutine.resume(thread, table.unpack(args, 1, args.n)))
	self.domain = previousDomain
	if coroutine.status(thread) == "dead" then
		self.threads[thread] = nil
	end

	if not result[1] then
		if reportError ~= false then
			self:report(debug.traceback(thread, tostring(result[2])))
		end
	elseif result[2] == SLEEP then
		local duration = math.max(self.step, result[3])
		self:queue(thread, self.now + duration / rate, table.pack(duration))
		return true
	elseif result[2] == WAIT then
		return true
	end

	return table.unpack(result, 1, result.n)
end

function Clock:spawn(fn, ...)
	local thread = type(fn) == "thread" and fn or coroutine.create(fn)
	self:queue(thread, self.now, table.pack(...))
	return thread
end

function Clock:drain()
	local count = 0
	while self.jobs[1] and self.jobs[1].due <= self.now + 1e-8 and count < 1000 do
		local job = self:pop()
		self:resume(job.thread, job.args)

		table.clear(job)
		if not self.closed and #self.freeJobs < 512 then
			table.insert(self.freeJobs, job)
		end

		count += 1
	end

	if count == 1000 then
		self:report("Too many callbacks at one frame; the remaining callbacks are deferred.")
	end
end

function Clock:stopFrameCapture()
	if not self.frameProperties then
		return
	end

	self.frameProperties, self.frameAttributes = nil, nil
	for object in self.retired do
		self.owned[object] = nil
		object:Destroy()
	end

	table.clear(self.retired)
	self.frameEpoch += 1
end

function Clock:rememberFrame(object, key)
	if not self.frameProperties or key == "Parent" then
		return
	end

	key = propertyKey(object, key)
	if object:IsA("ParticleEmitter") and (key == "Enabled" or key == "TimeScale") then
		return
	end

	local properties = self.frameProperties[object]
	if not properties then
		properties = {}
		self.frameProperties[object] = properties
	end

	if properties[key] == nil then
		local value = object[key]
		if self.hidden[object] and self.hidden[object][key] ~= nil then
			value = self.hidden[object][key]
		end

		properties[key] = value == nil and NIL or value
	end
end

function Clock:captureFrame()
	local frame = {
		time = self.now,
		properties = {},
		attributes = {},
		particles = self.particles:captureFrame(),
		parents = {},
		weight = 1,
	}
	frame.weight += #frame.particles * 4
	for object in self.owned do
		frame.parents[object] = object.Parent or NIL
		frame.weight += 1
	end

	for object, keys in self.frameProperties or {} do
		local values = {}
		for key in keys do
			local value = object[key]
			if self.hidden[object] and self.hidden[object][key] ~= nil then
				value = self.hidden[object][key]
			end

			values[key] = value == nil and NIL or value
			frame.weight += 1
		end

		frame.properties[object] = values
	end

	for object, keys in self.frameAttributes or {} do
		local values = {}
		for key in keys do
			local value = object:GetAttribute(key)
			values[key] = value == nil and NIL or value
			frame.weight += 1
		end

		frame.attributes[object] = values
	end

	return frame
end

function Clock:applyFrame(frame)
	self.staging = false
	table.clear(self.hidden)
	for object in self.owned do
		local parent = stored(frame.parents and frame.parents[object])
		if object.Parent ~= parent then
			object.Parent = parent
		end
	end

	for object, keys in self.frameProperties or {} do
		local values = frame.properties[object] or {}
		for key, original in keys do
			local value = values[key]
			if value == nil then
				value = original
			end

			value = stored(value)
			if object[key] ~= value then
				if self.dependencies then
					self.dependencies:before(object, key)
				end

				object[key] = value
				if self.dependencies then
					self.dependencies:after(object, key)
				end
			end
		end
	end

	for object, keys in self.frameAttributes or {} do
		local values = frame.attributes[object] or {}
		for key, original in keys do
			local value = values[key]
			if value == nil then
				value = original
			end

			value = stored(value)
			if object:GetAttribute(key) ~= value then
				if self.dependencies then
					self.dependencies:before(object, key, "Attribute")
				end

				object:SetAttribute(key, value)
				if self.dependencies then
					self.dependencies:after(object, key, "Attribute")
				end
			end
		end
	end
end

function Clock:remember(object, key, frameRemembered)
	key = propertyKey(object, key)
	if not frameRemembered then
		self:rememberFrame(object, key)
	end

	if self.owned[object] then
		return
	end

	local properties = self.originals[object]
	if not properties then
		properties = {}
		self.originals[object] = properties
	end

	if properties[key] == nil then
		local value = object[key]
		properties[key] = value == nil and NIL or value
		self.cleanup:remember(object, key, value)
	end
end

function Clock:changed(object, key)
	self.particles:markNativeDirty(object, key)
	local signals = self.signals[object]
	if signals then
		if signals[key] then
			signals[key]:Fire()
		end

		if key:sub(1, 1) == "@" then
			if signals.AttributeChanged then
				signals.AttributeChanged:Fire(key:sub(2))
			end
		elseif signals.Changed then
			if object:IsA("ValueBase") then
				if key == "Value" then
					signals.Changed:Fire(self:wrap(object.Value))
				end
			else
				signals.Changed:Fire(key)
			end
		end
	end
end

function Clock:write(object, key, value)
	assert(not self.closed, "Event preview has ended")
	value = self:unwrap(value)
	local observed = self.signals[object] ~= nil
	local previous = observed and self:read(object, key)
	if self.dependencies then
		self.dependencies:before(object, key)
	end

	self:rememberFrame(object, key)
	if key == "Parent" and object.Parent ~= value then
		if not self.owned[object] or not self.frameProperties then
			self.frameEpoch += 1
		end

		if self.owned[object] and not self.owned[value] then
			self.cleanup:own(object)
		end
	end

	if self.hidden[object] and self.hidden[object][key] ~= nil then
		self.hidden[object][key] = value
	elseif self.animationTracks[object] and key == "TimePosition" then
		self.animationTracks[object].time = value
		object.TimePosition = value
	elseif object:IsA("ParticleEmitter") and (key == "Enabled" or key == "TimeScale") then
		local state = self.particles:track(object)
		state[key] = value
		if key == "Enabled" and value then
			state.rate = self:rate()
		end
	else
		self:remember(object, key, true)
		object[key] = value
	end

	if self.dependencies then
		self.dependencies:after(object, key)
	end

	if not observed or previous ~= self:read(object, key) then
		self:changed(object, key)
	end
end

function Clock:adopt(object)
	self.cleanup:own(object)
	if not self.frameProperties then
		self.frameEpoch += 1
	end

	local list = object:GetDescendants()
	table.insert(list, object)
	for _, child in list do
		if not self.owned[child] then
			self.ownedCount += 1
		end

		self.owned[child] = true
		if self.ownedCount > 4096 then
			self:stopFrameCapture()
		end

		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
		end

		if child:IsA("ParticleEmitter") then
			self.particles:track(child)
		end

		if self.staging then
			local key, value
			if child:IsA("BasePart") then
				key, value = "LocalTransparencyModifier", 1
			elseif child:IsA("Decal") then
				key, value = "Transparency", 1
			elseif
				child:IsA("Beam")
				or child:IsA("Trail")
				or child:IsA("Light")
				or child:IsA("Fire")
				or child:IsA("Smoke")
				or child:IsA("Sparkles")
				or child:IsA("Highlight")
			then
				key, value = "Enabled", false
			elseif child:IsA("GuiObject") then
				key, value = "Visible", false
			end

			if key and not self.hidden[child] then
				self:rememberFrame(child, key)
				self.hidden[child] = { [key] = child[key] }
				child[key] = value
			end
		end
	end

	object.Archivable = false
	return object
end

function Clock:remove(object)
	if self.retired[object] then
		return
	end

	local owned = self.owned[object]
	local children = object:GetDescendants()
	if owned then
		self.retired[object] = true
		for _, child in children do
			if not self.retired[child] then
				self.retired[child] = true
				local signals = self.signals[child]
				if signals and signals.Destroying then
					signals.Destroying:Fire()
				end
			end
		end
	end

	local signals = self.signals[object]
	if signals and signals.Destroying then
		signals.Destroying:Fire()
	end

	for _, child in children do
		if child:IsA("ParticleEmitter") then
			self.particles:clear(child)
			self.particles.emitters[child] = nil
		end
	end

	if object:IsA("ParticleEmitter") then
		self.particles:clear(object)
	end

	if owned and self.frameProperties then
		object.Parent = nil
	elseif owned then
		self.frameEpoch += 1
		object:Destroy()
		self.owned[object] = nil
		for _, child in children do
			self.owned[child] = nil
		end
	else
		self:write(object, "Parent", nil)
	end
end

function Clock:unwrap(value, seen)
	if type(value) ~= "table" then
		return value
	end

	if self.raw[value] then
		return self.raw[value]
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local result = {}
	seen[value] = result
	for key, entry in value do
		result[self:unwrap(key, seen)] = self:unwrap(entry, seen)
	end

	return result
end

function Clock:wrap(value, seen)
	if typeof(value) == "Instance" then
		if self.internal[value] then
			return nil
		end

		if self.proxies[value] then
			return self.proxies[value]
		end

		local proxy = {}
		self.proxies[value], self.raw[proxy] = proxy, value
		setmetatable(proxy, self.proxyMetatable)
		return proxy
	elseif typeof(value) == "RaycastResult" then
		if self.proxies[value] then
			return self.proxies[value]
		end

		local proxy = setmetatable({}, {
			__index = function(_, key)
				return self:wrap(value[key])
			end,
			__newindex = function()
				error("RaycastResult properties are read-only", 2)
			end,
			__tostring = function()
				return tostring(value)
			end,
		})
		self.proxies[value], self.raw[proxy] = proxy, value
		return proxy
	elseif typeof(value) == "RBXScriptSignal" then
		if self.proxies[value] then
			return self.proxies[value]
		end

		local output = signal(self)
		local connection = value:Connect(function(...)
			if self.closed then
				return
			end

			local args = table.pack(...)
			for index = 1, args.n do
				if typeof(args[index]) == "Instance" and self.internal[args[index]] then
					return
				end
			end

			for index = 1, args.n do
				args[index] = self:wrap(args[index])
			end

			output:Fire(table.unpack(args, 1, args.n))
		end)
		table.insert(self.connections, connection)
		self.proxies[value] = output
		return output
	elseif type(value) == "table" then
		seen = seen or {}
		if seen[value] then
			return seen[value]
		end

		local result = {}
		seen[value] = result
		if #value > 0 and typeof(value[1]) == "Instance" then
			for _, entry in ipairs(value) do
				local wrapped = self:wrap(entry, seen)
				if wrapped then
					table.insert(result, wrapped)
				end
			end

			return result
		end

		for key, entry in value do
			result[self:wrap(key, seen)] = self:wrap(entry, seen)
		end

		return result
	end

	return value
end

local function lerp(a, b, alpha)
	if typeof(a) == "number" then
		return a + (b - a) * alpha
	end

	if typeof(a) == "boolean" or typeof(a) == "string" or typeof(a) == "EnumItem" then
		return alpha < 1 and a or b
	end

	return a:Lerp(b, alpha)
end

function Clock:tween(object, info, goals)
	local clock = self
	local tween = {
		Instance = self:wrap(object),
		TweenInfo = info,
		PlaybackState = Enum.PlaybackState.Begin,
		Completed = signal(self),
	}
	self.virtualTypes[tween] = "Instance"
	tween.ClassName, tween.Name = "Tween", "Tween"

	function tween:IsA(name)
		return name == "Tween" or name == "TweenBase" or name == "Instance"
	end

	local entry = {
		object = object,
		info = info,
		goals = self:unwrap(goals),
		tween = tween,
		elapsed = 0,
		origins = {},
		domain = self.domain,
	}

	function tween:Play()
		if
			self.PlaybackState == Enum.PlaybackState.Playing
			or self.PlaybackState == Enum.PlaybackState.Delayed
		then
			return
		end

		for other in clock.tweens do
			if other ~= entry and other.object == object then
				for key in entry.goals do
					if other.goals[key] ~= nil then
						other.tween:Cancel()
						break
					end
				end
			end
		end

		if self.PlaybackState ~= Enum.PlaybackState.Paused then
			entry.elapsed = 0
			for key in entry.goals do
				entry.origins[key] = clock:read(object, key)
			end
		end

		self.PlaybackState = info.DelayTime > entry.elapsed and Enum.PlaybackState.Delayed
			or Enum.PlaybackState.Playing
		clock.tweens[entry] = true
	end

	function tween:Pause()
		self.PlaybackState = Enum.PlaybackState.Paused
	end

	function tween:Cancel()
		clock.tweens[entry] = nil
		entry.elapsed = 0
		self.PlaybackState = Enum.PlaybackState.Cancelled
		self.Completed:Fire(self.PlaybackState)
	end

	function tween:Destroy()
		clock.tweens[entry] = nil
	end

	return tween
end

function Clock:updateTweens(dt)
	for entry in self.tweens do
		local tween, info = entry.tween, entry.info
		if tween.PlaybackState == Enum.PlaybackState.Paused then
			continue
		end

		entry.elapsed += dt * (entry.domain and entry.domain.rate or 1)
		local previousDomain = self.domain
		self.domain = entry.domain
		local duration = math.max(info.Time, 1e-8)
		local cycle = info.DelayTime + duration * (info.Reverses and 2 or 1)
		local ended = info.RepeatCount >= 0
			and entry.elapsed >= cycle * (info.RepeatCount + 1) - 1e-8
		local within = ended and cycle or entry.elapsed % cycle
		local progress = math.max(0, within - info.DelayTime) / duration
		if info.Reverses and progress > 1 then
			progress = 2 - progress
		end

		if ended then
			progress = info.Reverses and 0 or 1
		end

		local alpha =
			NativeTween:GetValue(math.clamp(progress, 0, 1), info.EasingStyle, info.EasingDirection)
		for key, target in entry.goals do
			self:write(entry.object, key, lerp(entry.origins[key], target, alpha))
		end

		tween.PlaybackState = within < info.DelayTime and Enum.PlaybackState.Delayed
			or Enum.PlaybackState.Playing
		if ended then
			self.tweens[entry] = nil
			tween.PlaybackState = Enum.PlaybackState.Completed
			tween.Completed:Fire(tween.PlaybackState)
		end

		self.domain = previousDomain
	end
end

function Clock:read(object, key)
	if self.hidden[object] and self.hidden[object][key] ~= nil then
		return self.hidden[object][key]
	end

	if key == "GetAttribute" then
		return function(_, name)
			local value = object:GetAttribute(name)
			if self.dependencies and self.dependencies.read then
				self.dependencies:read(object, name, value, "Attribute")
			end

			return value
		end
	end

	if key == "GetAttributes" then
		return function()
			local values = object:GetAttributes()
			if self.dependencies and self.dependencies.readAttributes then
				self.dependencies:readAttributes(object, values)
			end

			return values
		end
	end

	if key == "IsA" then
		return function(_, name)
			return object:IsA(name)
		end
	end

	if key == "GetChildren" or key == "GetDescendants" then
		return function()
			local result = {}
			for _, child in object[key](object) do
				if not self.internal[child] then
					table.insert(result, self:wrap(child))
				end
			end

			return result
		end
	end

	local service = self.classNames[object]
	if not service then
		service = object.ClassName
		self.classNames[object] = service
	end

	if service == "Workspace" then
		if key == "DistributedGameTime" then
			return self:localTime()
		end

		if key == "GetServerTimeNow" then
			return function()
				return self.epoch + self:localTime()
			end
		end
	elseif service == "RunService" then
		if key == "RenderStepped" or key == "PreRender" then
			return self.render
		end

		if key == "Heartbeat" or key == "PostSimulation" then
			return self.heartbeat
		end

		if key == "Stepped" then
			return self.stepped
		end

		if key == "PreSimulation" then
			return self.preSimulation
		end

		if key == "PreAnimation" then
			return self.preAnimation
		end

		if key == "BindToRenderStep" then
			return function(_, name, priority, callback)
				self.bindings[name] =
					{ priority = priority, callback = callback, domain = self.domain }
				self.bindingOrder = nil
			end
		end

		if key == "UnbindFromRenderStep" then
			return function(_, name)
				self.bindings[name] = nil
				self.bindingOrder = nil
			end
		end
	elseif service == "TweenService" and key == "Create" then
		return function(_, target, info, goals)
			return self:tween(self:unwrap(target), info, goals)
		end
	elseif service == "Debris" and key == "AddItem" then
		return function(_, target, duration)
			self:queue(
				coroutine.create(function()
					self:remove(self:unwrap(target))
				end),
				self.now + (duration or 10) / self:rate()
			)
		end
	elseif service == "CollectionService" and (key == "AddTag" or key == "RemoveTag") then
		return function(_, target, tag)
			return self:read(self:unwrap(target), key)(nil, tag)
		end
	elseif service == "CollectionService" and key == "GetTagged" then
		return function(_, tag)
			local objects = object:GetTagged(tag)
			if self.dependencies and self.dependencies.readTags then
				self.dependencies:readTags(tag, objects)
			end

			return self:wrap(objects)
		end
	elseif service == "CollectionService" and (key == "HasTag" or key == "GetTags") then
		return function(_, target, ...)
			return self:read(self:unwrap(target), key)(nil, ...)
		end
	end

	if key == "AddTag" or key == "RemoveTag" then
		return function(_, tag)
			if self.dependencies then
				self.dependencies:before(object, tag, "Tag")
			end

			self.tags[object] = self.tags[object] or {}
			if self.tags[object][tag] == nil then
				self.tags[object][tag] = object:HasTag(tag)
				if not self.owned[object] then
					self.cleanup:remember(object, tag, self.tags[object][tag], "Tag")
				end
			end

			if key == "AddTag" then
				object:AddTag(tag)
			else
				object:RemoveTag(tag)
			end

			if self.dependencies then
				self.dependencies:after(object, tag, "Tag")
			end
		end
	end

	if key == "HasTag" then
		return function(_, tag)
			local value = object:HasTag(tag)
			if self.dependencies and self.dependencies.read then
				self.dependencies:read(object, tag, value, "Tag")
			end

			return value
		end
	end

	if key == "GetTags" then
		return function()
			local tags = object:GetTags()
			if self.dependencies and self.dependencies.readObjectTags then
				self.dependencies:readObjectTags(object, tags)
			end

			return tags
		end
	end

	if service == "ParticleEmitter" then
		if key == "Emit" then
			return function(_, count)
				self.particles:emit(object, count)
			end
		end

		if key == "Clear" then
			return function()
				self.particles:clear(object)
			end
		end

		if key == "Enabled" or key == "TimeScale" then
			return self.particles:track(object)[key]
		end
	end

	if service == "BindableEvent" then
		self.signals[object] = self.signals[object] or {}
		self.signals[object].Event = self.signals[object].Event or signal(self)
		if key == "Event" then
			return self.signals[object].Event
		end

		if key == "Fire" then
			return function(_, ...)
				self.signals[object].Event:Fire(...)
			end
		end
	end

	if key == "Clone" then
		return function()
			if self.dependencies then
				self.dependencies:watch(object, true)
			end

			local originals = {}
			local items = object:GetDescendants()
			table.insert(items, object)
			for _, item in items do
				if item == object or self.owned[item] then
					originals[item] = item.Archivable
					if self.dependencies then
						self.dependencies:before(item, "Archivable")
					end

					item.Archivable = true
					if self.dependencies then
						self.dependencies:after(item, "Archivable")
					end
				end
			end

			local ok, result = pcall(function()
				return object:Clone()
			end)
			for item, archivable in originals do
				if self.dependencies then
					self.dependencies:before(item, "Archivable")
				end

				item.Archivable = archivable
				if self.dependencies then
					self.dependencies:after(item, "Archivable")
				end
			end

			if not ok then
				error(result)
			end

			if result then
				local function copy(source, clone)
					local state = self.particles.emitters[source]
					if state then
						clone.Enabled = state.Enabled
						clone.TimeScale = state.TimeScale
					end

					for key, value in self.hidden[source] or {} do
						clone[key] = value
					end

					local children = clone:GetChildren()
					for _, child in source:GetChildren() do
						for index, candidate in children do
							if
								candidate.Name == child.Name
								and candidate.ClassName == child.ClassName
							then
								copy(child, candidate)
								table.remove(children, index)
								break
							end
						end
					end
				end

				copy(object, result)
				self:adopt(result)
			end

			return self:wrap(result)
		end
	end

	if key == "Destroy" or key == "Remove" then
		return function()
			self:remove(object)
		end
	end

	if key == "ClearAllChildren" then
		return function()
			for _, child in object:GetChildren() do
				self:remove(child)
			end
		end
	end

	if key == "Destroying" and self.owned[object] then
		self.signals[object] = self.signals[object] or {}
		self.signals[object].Destroying = self.signals[object].Destroying or signal(self)
		return self.signals[object].Destroying
	end

	if
		key == "Changed"
		or key == "AttributeChanged"
		or key == "GetPropertyChangedSignal"
		or key == "GetAttributeChangedSignal"
	then
		self.signals[object] = self.signals[object] or {}

		local function get(name)
			self.signals[object][name] = self.signals[object][name] or signal(self)
			return self.signals[object][name]
		end

		if key == "Changed" or key == "AttributeChanged" then
			return get(key)
		end

		return function(_, name)
			return get(key == "GetAttributeChangedSignal" and "@" .. name or name)
		end
	end

	if key == "SetAttribute" then
		return function(_, name, value)
			local previous = object:GetAttribute(name)
			if self.dependencies then
				self.dependencies:before(object, name, "Attribute")
			end

			if self.frameAttributes then
				local keys = self.frameAttributes[object]
				if not keys then
					keys = {}
					self.frameAttributes[object] = keys
				end

				if keys[name] == nil then
					local old = object:GetAttribute(name)
					keys[name] = old == nil and NIL or old
				end
			end

			if not self.owned[object] then
				self.attributes[object] = self.attributes[object] or {}
				if self.attributes[object][name] == nil then
					local old = object:GetAttribute(name)
					self.attributes[object][name] = old == nil and NIL or old
					self.cleanup:remember(object, name, old, "Attribute")
				end
			end

			object:SetAttribute(name, value)
			if self.dependencies then
				self.dependencies:after(object, name, "Attribute")
			end

			if previous ~= value then
				self:changed(object, "@" .. name)
			end
		end
	end

	if key == "GetPivot" and object:IsA("PVInstance") then
		return function()
			if self.dependencies and self.dependencies.readPivot then
				self.dependencies:readPivot(object)
			end

			return object:GetPivot()
		end
	end

	if (key == "PivotTo" or key == "SetPrimaryPartCFrame") and object:IsA("PVInstance") then
		return function(_, cf)
			if self.dependencies then
				self.dependencies:beforeTree(object, "pivot")
			end

			if object:IsA("BasePart") then
				self:remember(object, "CFrame")
			end

			for _, child in object:GetDescendants() do
				if child:IsA("BasePart") then
					self:remember(child, "CFrame")
				end
			end

			object:PivotTo(cf)
			if self.dependencies then
				self.dependencies:afterTree(object, "pivot")
			end
		end
	end

	if key == "ScaleTo" and object:IsA("Model") then
		return function(_, scale)
			if self.dependencies then
				self.dependencies:before(object, "Scale", "Scale")
				self.dependencies:beforeTree(object, "scale")
			end

			if self.frameProperties then
				for _, child in object:GetDescendants() do
					if child:IsA("BasePart") then
						self:rememberFrame(child, "CFrame")
						self:rememberFrame(child, "Size")
					end

					if child:IsA("Attachment") then
						self:rememberFrame(child, "CFrame")
					end

					if child:IsA("DataModelMesh") then
						self:rememberFrame(child, "Scale")
						self:rememberFrame(child, "Offset")
					end

					if child:IsA("JointInstance") then
						self:rememberFrame(child, "C0")
						self:rememberFrame(child, "C1")
					end
				end
			end

			if not self.owned[object] and not self.scales[object] then
				self.scales[object] = object:GetScale()
				self.cleanup:remember(object, "Scale", self.scales[object], "Scale")
				for _, child in object:GetDescendants() do
					if child:IsA("BasePart") then
						self:remember(child, "CFrame")
						self:remember(child, "Size")
					end

					if child:IsA("Attachment") then
						self:remember(child, "CFrame")
					end

					if child:IsA("DataModelMesh") then
						self:remember(child, "Scale")
						self:remember(child, "Offset")
					end

					if child:IsA("JointInstance") then
						self:remember(child, "C0")
						self:remember(child, "C1")
					end
				end
			end

			object:ScaleTo(scale)
			if self.dependencies then
				self.dependencies:afterTree(object, "scale")
				self.dependencies:after(object, "Scale", "Scale")
			end
		end
	end

	if key == "BulkMoveTo" and object:IsA("WorldRoot") then
		return function(_, parts, frames, mode)
			parts = self:unwrap(parts)
			for _, part in parts do
				if self.dependencies then
					self.dependencies:before(part, "CFrame")
				end

				self:remember(part, "CFrame")
			end

			object:BulkMoveTo(parts, frames, mode)
			if self.dependencies then
				for _, part in parts do
					self.dependencies:after(part, "CFrame")
				end
			end
		end
	end

	if key == "WaitForChild" then
		return function(_, name, timeout)
			local start = self:localTime()
			repeat
				local found = object:FindFirstChild(name)
				if found then
					return self:wrap(found)
				end

				coroutine.yield(SLEEP, self.step)
			until timeout and self:localTime() - start >= timeout
			return nil
		end
	end

	if
		key == "LoadAnimation"
		and (object:IsA("Animator") or object:IsA("AnimationController") or object:IsA("Humanoid"))
	then
		return function(_, animation)
			animation = self:unwrap(animation)
			if self.dependencies then
				self.dependencies:watch(animation, true)
			end

			local animator = object
			if not object:IsA("Animator") then
				animator = object:FindFirstChildOfClass("Animator")
				if not animator then
					animator = Instance.new("Animator")
					self:adopt(animator)
					animator.Parent = object
				end
			end

			local track = animator:LoadAnimation(animation)
			self.owned[track] = true
			self.cleanup:own(track)
			self.animationTracks[track] = {
				animator = animator,
				time = 0,
				speed = 1,
				playing = false,
				domain = self.domain,
			}
			local root = animator.Parent and animator.Parent.Parent
			if root then
				for _, joint in root:GetDescendants() do
					if joint:IsA("Motor6D") or joint:IsA("Bone") then
						self:remember(joint, "Transform")
					end
				end
			end

			return self:wrap(track)
		end
	end

	local animation = self.animationTracks[object]
	if animation then
		if key == "Play" then
			return function(_, fade, weight, speed)
				animation.playing = true
				animation.time = 0
				animation.speed = speed or 1
				object:Play(0, weight or 1, 0)
			end
		end

		if key == "AdjustSpeed" then
			return function(_, speed)
				animation.speed = speed
			end
		end

		if key == "Stop" then
			return function()
				animation.playing = false
				object:Stop(0)
			end
		end

		if key == "TimePosition" then
			return animation.time
		end

		if key == "Speed" then
			return animation.speed
		end
	end

	if key == "Value" and self.dependencies and object:IsA("ValueBase") then
		self.dependencies:watch(object)
	end

	local value = object[key]
	if type(value) ~= "function" and self.dependencies and self.dependencies.read then
		self.dependencies:read(object, key, value)
	end

	if type(value) == "function" then
		return function(_, ...)
			if
				key == "FireServer"
				or key == "FireClient"
				or key == "FireAllClients"
				or key == "InvokeServer"
				or key == "InvokeClient"
				or service == "HttpService" and not previewHttp[key]
				or service == "DataStoreService"
				or service == "MessagingService"
				or service == "TeleportService"
			then
				error(
					"This operation is unavailable during event preview: " .. service .. ":" .. key
				)
			end

			local args = table.pack(...)
			for index = 1, args.n do
				args[index] = self:unwrap(args[index])
			end

			local results = table.pack(value(object, table.unpack(args, 1, args.n)))
			for index = 1, results.n do
				results[index] = self:wrap(results[index])
			end

			return table.unpack(results, 1, results.n)
		end
	end

	return self:wrap(value)
end

function Clock:previewServices()
	local clock = self
	local env = {
		task = task,
		game = game,
		workspace = workspace,
		Instance = Instance,
		typeof = typeof,
		type = type,
		os = os,
		math = math,
		Random = Random,
		coroutine = coroutine,
		warn = warn,
		shared = shared,
	}
	local virtualCoroutine = table.clone(coroutine)

	function virtualCoroutine.create(fn)
		local thread = coroutine.create(fn)
		clock.threads[thread] = true
		return thread
	end

	function virtualCoroutine.resume(thread, ...)
		return clock:resume(thread, table.pack(...), false)
	end

	function virtualCoroutine.wrap(fn)
		local thread = virtualCoroutine.create(fn)
		return function(...)
			local result = table.pack(virtualCoroutine.resume(thread, ...))
			if not result[1] then
				error(result[2], 2)
			end

			return table.unpack(result, 2, result.n)
		end
	end

	function virtualCoroutine.close(thread)
		local result = table.pack(coroutine.close(thread))
		if result[1] then
			clock.threads[thread] = nil
		end

		return table.unpack(result, 1, result.n)
	end

	env.coroutine = virtualCoroutine
	local virtualTask = {}

	function virtualTask.spawn(fn, ...)
		local thread = type(fn) == "thread" and fn or coroutine.create(fn)
		clock:resume(thread, table.pack(...))
		return thread
	end

	function virtualTask.defer(fn, ...)
		return clock:queue(
			type(fn) == "thread" and fn or coroutine.create(fn),
			clock.now,
			table.pack(...)
		)
	end

	function virtualTask.delay(duration, fn, ...)
		return clock:queue(
			type(fn) == "thread" and fn or coroutine.create(fn),
			clock.now + math.max(0, duration) / clock:rate(),
			table.pack(...)
		)
	end

	function virtualTask.wait(duration)
		return coroutine.yield(SLEEP, math.max(clock.step, duration or 0))
	end

	function virtualTask.cancel(thread)
		local ok = pcall(coroutine.close, thread)
		if ok then
			clock.threads[thread] = nil
		end
	end

	virtualTask.synchronize = function() end
	virtualTask.desynchronize = function() end
	env.task, env.wait, env.spawn, env.delay =
		virtualTask, virtualTask.wait, virtualTask.spawn, virtualTask.delay
	env.game, env.workspace = clock:wrap(game), clock:wrap(workspace)
	env.Game, env.Workspace = env.game, env.workspace
	env.Instance = {
		new = function(class, parent)
			local object = Instance.new(class)
			clock:adopt(object)
			if parent then
				object.Parent = clock:unwrap(parent)
			end

			return clock:wrap(object)
		end,
		fromExisting = function(source)
			source = clock:unwrap(source)
			if clock.dependencies then
				clock.dependencies:watch(source)
			end

			local object = Instance.fromExisting(source)
			local state = clock.particles.emitters[source]
			if state then
				object.Enabled, object.TimeScale = state.Enabled, state.TimeScale
			end

			for key, value in clock.hidden[source] or {} do
				object[key] = value
			end

			clock:adopt(object)
			return clock:wrap(object)
		end,
	}

	local function parameterProxy(constructor)
		return {
			new = function()
				local object = constructor.new()
				local proxy = {}
				clock.raw[proxy] = object
				return setmetatable(proxy, {
					__index = function(_, key)
						local value = object[key]
						if type(value) ~= "function" then
							return clock:wrap(value)
						end

						return function(_, ...)
							local args = table.pack(...)
							for index = 1, args.n do
								args[index] = clock:unwrap(args[index])
							end

							local result = table.pack(value(object, table.unpack(args, 1, args.n)))
							for index = 1, result.n do
								result[index] = clock:wrap(result[index])
							end

							return table.unpack(result, 1, result.n)
						end
					end,
					__newindex = function(_, key, value)
						object[key] = clock:unwrap(value)
					end,
				})
			end,
		}
	end

	env.RaycastParams = parameterProxy(RaycastParams)
	env.OverlapParams = parameterProxy(OverlapParams)
	env.typeof = function(value)
		return clock.virtualTypes[value]
			or clock.raw[value] and typeof(clock.raw[value])
			or typeof(value)
	end

	env.type = function(value)
		return clock.virtualTypes[value] and "userdata"
			or clock.raw[value] and type(clock.raw[value])
			or type(value)
	end

	env.time = function()
		return clock:localTime()
	end

	env.tick = function()
		return clock.epoch + clock:localTime()
	end

	env.os = table.clone(os)
	env.os.clock = env.time
	env.os.time = function(date)
		if date ~= nil then
			return os.time(date)
		end

		return math.floor(clock.epoch + clock:localTime())
	end

	env.DateTime = table.clone(DateTime)
	env.DateTime.now = function()
		return DateTime.fromUnixTimestampMillis(
			math.floor((clock.epoch + clock:localTime()) * 1000)
		)
	end

	env.math = table.clone(math)
	env.math.random = function(a, b)
		if not a then
			return clock.random:NextNumber()
		end

		return clock.random:NextInteger(b and a or 1, b or a)
	end

	env.math.randomseed = function(seed)
		clock.random = Random.new(seed)
	end

	env.Random = {
		new = function(seed)
			return Random.new(seed or clock.random:NextInteger(1, 2147483646))
		end,
	}
	env.shared = clock.shared or {}
	clock.shared = env.shared
	return env
end

function Clock:emitNative(rig, event, speed)
	local rows = NativeEmitData.copy(event.Emits)
	if #rows == 0 then
		return
	end

	if not self.vfx then
		local env = self:previewServices()
		env.EclipsePreview = true
		env.warn = function(message)
			self:report(message)
		end

		self.vfx = NativeVFX.new(env)
	end

	self:spawnIn({ rate = speed or 1, origin = self.now }, function()
		for _, row in rows do
			local target = NativeEmitData.resolve(rig, row.Path)
			if target and target.Parent then
				self.vfx:Apply(self:wrap(target), row)
			end
		end
	end)
end

function Clock:execute(code, values, name, speed)
	if type(code) == "string" and code:match("%S") then
		self:report(
			"Custom event code is saved and exported, but does not run in Studio preview. Native VFX, sounds and subtitles still preview."
		)
	end
end

function Clock:stepTo(time, frame)
	local dt = time - self.now
	self.now = time
	self:updateTweens(dt)
	self.particles:step(dt)
	self:drain()
	if dt > 0 and frame ~= false then
		local frameDelta = type(frame) == "number" and frame or frame == true and self.step or dt
		self.preSimulation:Fire(frameDelta)
		self.preAnimation:Fire(frameDelta)
		self.stepped:Fire(time, frameDelta)
		self.heartbeat:Fire(frameDelta)
		local bindings = self.bindingOrder
		if not bindings then
			bindings = {}
			for _, binding in self.bindings do
				table.insert(bindings, binding)
			end

			table.sort(bindings, function(a, b)
				return a.priority < b.priority
			end)
			self.bindingOrder = bindings
		end

		for _, binding in bindings do
			self:spawnIn(
				binding.domain,
				binding.callback,
				frameDelta * (binding.domain and binding.domain.rate or 1)
			)
		end

		self.render:Fire(frameDelta)
		self:drain()
	end

	for track, entry in self.animationTracks do
		if not entry.playing then
			continue
		end

		entry.time += dt * entry.speed * (entry.domain and entry.domain.rate or 1)
		local length = track.Length
		track.TimePosition = length > 0
				and (track.Looped and entry.time % length or math.min(entry.time, length))
			or entry.time
		entry.animator:StepAnimations(0)
	end
end

function Clock:renderGeometry()
	self.staging = false
	for object, properties in self.hidden do
		for key, value in properties do
			pcall(function()
				object[key] = value
			end)
		end
	end

	table.clear(self.hidden)
end

function Clock:renderFrame()
	self:renderGeometry()
	self.particles:render()
end

function Clock:retainDisplay()
	local display = self.particles:retainDisplay()
	local roots = {}
	for object in self.owned do
		if object.Parent and object:IsDescendantOf(workspace) and not self.owned[object.Parent] then
			table.insert(roots, object)
		end
	end

	local holder
	for _, root in roots do
		Cleanup.visual(root)
		self.owned[root] = nil
		for _, child in root:GetDescendants() do
			self.owned[child] = nil
		end

		if root:IsA("PVInstance") or root:IsA("Folder") then
			if not holder then
				holder = Instance.new("Folder")
				holder.Name = "EclipseEventHold"
				holder.Archivable = false
				Cleanup.visual(holder)
				holder.Parent = workspace
				table.insert(display, { root = holder })
			end

			root.Parent = holder
		else
			table.insert(display, { root = root })
		end
	end

	return display
end

function Clock:destroy(keepVisuals)
	if self.closed then
		return
	end

	if self.vfx then
		self.vfx:Destroy()
		self.vfx = nil
	end

	if self.dependencies then
		self.dependencies:poll()
		self.dependencies:disconnect()
	end

	self.closed = true
	for _, connection in self.connections do
		connection:Disconnect()
	end

	for track in self.animationTracks do
		pcall(function()
			track:Stop(0)
		end)
	end

	local visualPool = self.particles:destroy(keepVisuals)
	local scales = {}
	for object, scale in self.scales do
		local depth, parent = 0, object.Parent
		while parent do
			depth += 1
			parent = parent.Parent
		end

		table.insert(scales, { object = object, value = scale, depth = depth })
	end

	table.sort(scales, function(a, b)
		return a.depth < b.depth
	end)
	for _, entry in scales do
		pcall(function()
			entry.object:ScaleTo(entry.value)
		end)
	end

	for object, properties in self.originals do
		for key, value in properties do
			if key ~= "Parent" then
				pcall(function()
					object[key] = stored(value)
				end)
			end
		end
	end

	for object, properties in self.originals do
		if properties.Parent ~= nil then
			pcall(function()
				object.Parent = stored(properties.Parent)
			end)
		end
	end

	for object, attributes in self.attributes do
		for key, value in attributes do
			pcall(function()
				object:SetAttribute(key, stored(value))
			end)
		end
	end

	for object, tags in self.tags do
		for tag, present in tags do
			pcall(function()
				if present then
					object:AddTag(tag)
				else
					object:RemoveTag(tag)
				end
			end)
		end
	end

	for object in self.owned do
		pcall(function()
			object:Destroy()
		end)
	end

	for thread in self.threads do
		pcall(coroutine.close, thread)
	end

	table.clear(self.threads)
	table.clear(self.loading)
	table.clear(self.jobs)
	table.clear(self.freeJobs)
	self.cleanup:finish()
	for _, event in self.virtualSignals do
		for connection in event.listeners do
			connection:Disconnect()
		end

		table.clear(event.listeners)
		table.clear(event.order)
	end

	for _, key in
		{
			"virtualSignals",
			"connections",
			"bindings",
			"tweens",
			"animationTracks",
			"signals",
			"modules",
			"originals",
			"attributes",
			"tags",
			"scales",
			"hidden",
			"proxies",
			"raw",
			"internal",
			"retired",
			"owned",
		}
	do
		table.clear(self[key])
	end

	if self.frameProperties then
		table.clear(self.frameProperties)
	end

	if self.frameAttributes then
		table.clear(self.frameAttributes)
	end

	return visualPool
end

return Clock
