--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local makeLegacy = require("makeLegacy")
local VFX = { Version = 1 }

local function finite(value, fallback, limit)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return fallback
	end

	return math.clamp(value, 0, limit or 3600)
end

function VFX.classify(item)
	if item:GetAttribute("Transformed") == true then
		return true, true
	end

	if item:HasTag("BezierParticle") then
		return true, true
	end

	if item:IsA("Model") then
		if item:FindFirstChild("Start") and item:FindFirstChild("End") then
			return true, true
		end

		if
			item:GetAttribute("SpinRotation")
			or item:GetAttribute("Scale_Start")
			or item:GetAttribute("Scale_End")
		then
			return true, false
		end
	end

	if item:IsA("BasePart") then
		local ancestor = item.Parent
		while ancestor and ancestor ~= game do
			if ancestor:IsA("Attachment") and ancestor:HasTag("Shockwave") then
				return true, true
			end

			ancestor = ancestor.Parent
		end
	end

	if item:IsA("RayValue") then
		return true, true
	end

	if item:IsA("ParticleEmitter") then
		local start = tonumber(item:GetAttribute("TimeScale_Start")) or item.TimeScale
		local finish = tonumber(item:GetAttribute("TimeScale_End")) or start
		if start ~= finish then
			return true, true
		end
	end

	if item:IsA("Beam") then
		for _, name in
			{
				"EffectDuration",
				"Width0_Start",
				"Width0_End",
				"StartWidth0",
				"EndTransparencyScale",
			}
		do
			if item:GetAttribute(name) ~= nil then
				return true, true
			end
		end
	end

	return false, false
end

function VFX.new(previewServices)
	local env = previewServices or {
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
	local task, Instance, typeof = env.task, env.Instance, env.typeof
	local engine = { runs = {}, closed = false, enabled = {} }

	local function attribute(object, name, fallback, limit)
		local value = object:GetAttribute(name)
		if typeof(value) == "NumberRange" then
			value = env.math.random() * (value.Max - value.Min) + value.Min
		elseif typeof(value) == "string" then
			local a, b = value:match("^%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*$")
			if a and b then
				a, b = tonumber(a), tonumber(b)
				if a and b then
					value = a + env.math.random() * (b - a)
				end
			else
				value = tonumber(value)
			end
		end

		return finite(value, fallback, limit)
	end

	function engine:SetEnabled(root, value, options)
		assert(not self.closed, "EclipseVFX is closed")
		assert(typeof(root) == "Instance", "SetEnabled expects an instance")
		assert(type(value) == "boolean", "SetEnabled expects a boolean")
		options = options or {}

		local function apply(item)
			if
				not (
					item:IsA("ParticleEmitter")
					or item:IsA("Beam")
					or item:IsA("Trail")
					or item:IsA("Light")
				)
			then
				return
			end

			local saved = self.enabled[item]
			if not saved then
				saved = { original = item.Enabled }
				self.enabled[item] = saved
			end

			item.Enabled = value
			saved.last = value
		end

		apply(root)
		if not options.SelfOnly then
			for _, item in
				(options.Descendants == false and root:GetChildren() or root:GetDescendants())
			do
				apply(item)
			end
		end
	end

	function engine:Apply(root, row)
		local options = { Descendants = row.Mode == "All", SelfOnly = row.Mode == "Exact" }
		if row.Action == "Enable" or row.Action == "Disable" then
			return self:SetEnabled(root, row.Action == "Enable", options)
		elseif row.Action == nil or row.Action == "Emit" then
			return self:Emit(root, options)
		end
	end

	function engine:Emit(root, options)
		assert(not self.closed, "EclipseVFX is closed")
		assert(typeof(root) == "Instance", "Emit expects an instance")
		options = options or {}
		local run = {
			cancelled = false,
			outputs = {},
			threads = {},
			pending = 0,
			errors = {},
			children = {},
		}

		function run:IsFinished()
			return self.cancelled
				or self.pending == 0 and next(self.outputs) == nil and not self.legacy
		end

		self.runs[run] = true

		local function finished()
			if run.pending == 0 and next(run.outputs) == nil and not run.legacy then
				self.runs[run] = nil
			end
		end

		local function schedule(delay, fn)
			run.pending += 1
			local token = {}
			run.threads[token] = true
			local thread = task.delay(delay, function()
				if not run.cancelled and not self.closed then
					local ok, err = pcall(fn)
					if not ok then
						table.insert(run.errors, tostring(err))
						env.warn("EclipseVFX: " .. tostring(err))
					end
				end

				run.pending -= 1
				run.threads[token] = nil
				finished()
			end)
			if run.threads[token] then
				run.threads[token] = thread
			end
		end

		function run:Cancel()
			if self.cancelled then
				return
			end

			self.cancelled = true
			for _, child in self.children do
				child:Cancel()
			end

			table.clear(self.children)
			if self.legacy then
				self.legacy:Destroy()
				self.legacy = nil
			end

			for _, thread in self.threads do
				if type(thread) == "thread" and thread ~= coroutine.running() then
					pcall(task.cancel, thread)
				end
			end

			for output in self.outputs do
				output:Destroy()
			end

			table.clear(self.outputs)
			table.clear(self.threads)
			engine.runs[self] = nil
		end

		run.Destroy = run.Cancel

		local function native(source)
			local delay = attribute(source, "EmitDelay", 0)
			schedule(delay, function()
				if not source.Parent then
					return
				end

				local output = Instance.fromExisting(source)
				output.Name = "EclipseVFX Output"
				output.Archivable = false
				output:SetAttribute("EclipseVFXOutput", true)
				output.Enabled = false
				run.outputs[output] = true
				local parent = source.Parent
				if
					parent
					and parent:IsA("Attachment")
					and not parent:FindFirstAncestorWhichIsA("BasePart")
				then
					local anchor = Instance.new("Attachment")
					anchor.Name = "EclipseVFX Anchor"
					anchor.Archivable = false
					anchor.CFrame = parent.WorldCFrame
					anchor.Parent = env.workspace.Terrain
					run.outputs[anchor] = true
					parent = anchor
					local follow
					follow = function()
						if not output.Parent or not source.Parent then
							return
						end

						anchor.CFrame = source.Parent.WorldCFrame
						schedule(1 / 60, follow)
					end

					schedule(1 / 60, follow)
					output.Destroying:Once(function()
						anchor:Destroy()
						run.outputs[anchor] = nil
					end)
				end

				output.Parent = parent
				local duration = attribute(source, "EmitDuration", 0)
				local life = 0
				if source:IsA("ParticleEmitter") then
					local count = options.Count ~= nil and finite(options.Count, 0, 100000)
						or attribute(source, "EmitCount", 1, 100000)
					output.TimeScale = attribute(source, "TimeScale_Start", source.TimeScale, 1)
					output:Emit(math.floor(count))
					if duration > 0 then
						output.Enabled = true
					end

					local speed = math.max(0.001, output.TimeScale)
					life = source.Lifetime.Max / speed
				else
					output.Enabled = true
					duration = attribute(
						source,
						"EmitDuration",
						attribute(source, "EffectDuration", attribute(source, "Duration", 0.25))
					)
					if source:IsA("Trail") then
						life = source.Lifetime
					end
				end

				schedule(duration, function()
					if output.Parent then
						output.Enabled = false
					end

					schedule(life, function()
						output:Destroy()
						run.outputs[output] = nil
					end)
				end)
			end)
		end

		local visited = {}

		local function visit(item, descend)
			if visited[item] or item:GetAttribute("EclipseVFXOutput") == true then
				return
			end

			visited[item] = true
			local special, prune = VFX.classify(item)
			if special then
				schedule(0, function()
					if not item.Parent then
						return
					end

					if not run.legacy then
						run.legacy = makeLegacy(env, function(object)
							local child = self:Emit(object)
							table.insert(run.children, child)
							return child
						end)
						local poll
						poll = function()
							if not run.legacy then
								return
							end

							if run.legacy:active() then
								schedule(0.1, poll)
							else
								run.legacy:Destroy()
								run.legacy = nil
							end
						end

						schedule(0.1, poll)
					end

					run.legacy:emit(item)
				end)
				if prune then
					return
				end
			elseif
				item:IsA("ParticleEmitter")
				or item:IsA("Beam")
				or item:IsA("Trail")
				or item:IsA("Light")
			then
				native(item)
			end

			for _, child in item:GetChildren() do
				if descend then
					visit(child, true)
				elseif
					not options.SelfOnly
					and (
						child:IsA("ParticleEmitter")
						or child:IsA("Beam")
						or child:IsA("Trail")
						or child:IsA("Light")
					)
				then
					visit(child, false)
				end
			end
		end

		visit(root, options.Descendants ~= false)
		finished()
		return run
	end

	function engine:EmitAll(root, options)
		options = table.clone(options or {})
		options.Descendants = true
		return self:Emit(root, options)
	end

	function engine:EmitSelected(root, options)
		options = table.clone(options or {})
		options.Descendants = false
		return self:Emit(root, options)
	end

	function engine:Destroy()
		if self.closed then
			return
		end

		self.closed = true
		for run in self.runs do
			run:Cancel()
		end

		for item, saved in self.enabled do
			pcall(function()
				if item.Enabled == saved.last then
					item.Enabled = saved.original
				end
			end)
		end

		table.clear(self.enabled)
	end

	return engine
end

local default

function VFX.Emit(root, options)
	if not default or default.closed then
		default = VFX.new()
	end

	return default:Emit(root, options)
end

function VFX.EmitAll(root, options)
	options = table.clone(options or {})
	options.Descendants = true
	return VFX.Emit(root, options)
end

function VFX.EmitSelected(root, options)
	options = table.clone(options or {})
	options.Descendants = false
	return VFX.Emit(root, options)
end

function VFX.Destroy()
	if default then
		default:Destroy()
		default = nil
	end
end

function VFX.Bind(animationTrack, root)
	local engine = VFX.new()
	local connection = animationTrack:GetMarkerReachedSignal("EclipseVFX"):Connect(function(payload)
		local ok, data = pcall(
			game:GetService("HttpService").JSONDecode,
			game:GetService("HttpService"),
			payload
		)
		if not ok or type(data) ~= "table" or data.Version ~= 1 or type(data.Emits) ~= "table" then
			return
		end

		for _, row in data.Emits do
			if
				type(row) ~= "table"
				or type(row.Path) ~= "table"
				or #row.Path > 128
				or (row.Mode ~= "All" and row.Mode ~= "Selected" and row.Mode ~= "Exact")
			then
				continue
			end

			local target = root
			for _, step in row.Path do
				if not target or type(step) ~= "table" then
					target = nil
					break
				end

				local found, index = nil, 0
				for _, child in target:GetChildren() do
					if child.Name == step.Name and child.ClassName == step.Class then
						index += 1
						if index == step.Index then
							found = child
							break
						end
					end
				end

				target = found
			end

			if target and target.Parent then
				engine:Apply(target, row)
			end
		end
	end)
	local stopped = animationTrack.Stopped:Connect(function()
		engine:Destroy()
		engine = VFX.new()
	end)
	local binding = {}

	function binding:Disconnect()
		connection:Disconnect()
		stopped:Disconnect()
		engine:Destroy()
	end

	binding.Destroy = binding.Disconnect
	return binding
end

return VFX
