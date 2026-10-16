--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Storage = {}
local Layers = require("Layers")
local Document = require("Document")
local Data = require("ChunkStore")
local Http = game:GetService("HttpService")
local NAME = "EclipseAnimationLayers"

local function metadata(data, rows, owners)
	local out = { version = 2, active = data.active, layers = {} }
	for _, layer in rows or data.layers do
		table.insert(out.layers, {
			owner = owners and owners[layer.owner],
			id = layer.id,
			name = layer.name,
			mode = layer.mode,
			weight = layer.weight,
			weightKeys = Layers.clone(layer.weightKeys),
			muted = layer.muted,
			solo = layer.solo,
			locked = layer.locked,
		})
	end

	return out
end

local function validate(value)
	assert(
		type(value) == "table"
			and (value.version == 1 or value.version == 2)
			and type(value.layers) == "table"
			and #value.layers >= 1
			and #value.layers <= 12800,
		"Invalid animation layer stack"
	)
	local ids = {}
	for i, layer in value.layers do
		assert(
			type(layer.id) == "string"
				and #layer.id <= 64
				and not layer.id:find("|", 1, true)
				and not ids[layer.id],
			"Invalid animation layer identity"
		)
		ids[layer.id] = true
		assert(type(layer.name) == "string" and #layer.name <= 192, "Invalid animation layer name")
		assert(
			layer.mode == "Additive" or layer.mode == "Override",
			"Invalid animation layer blend"
		)
		assert(
			type(layer.weight) == "number" and layer.weight >= 0 and layer.weight <= 1,
			"Invalid animation layer weight"
		)
		for frame, w in layer.weightKeys or {} do
			assert(
				type(frame) == "number"
					and frame >= 0
					and frame <= 1000000
					and type(w) == "number"
					and w >= 0
					and w <= 1,
				"Invalid layer weight key"
			)
		end

		for _, flag in { "muted", "solo", "locked" } do
			assert(layer[flag] == nil or type(layer[flag]) == "boolean", "Invalid layer switch")
		end

		if i == 1 then
			assert(layer.id == "base" and layer.mode == "Override", "Missing Base Animation")
		end
	end

	return ids
end

local function decodedKey(text, motor, frame, fps, budget)
	assert(
		type(frame) == "number" and frame == frame and frame >= 0 and frame <= 1000000,
		"Invalid animation layer frame"
	)
	local key = Document.unpackKey(text, budget and Data.decodeJson(text, budget) or nil)
	assert(type(key) == "table" and typeof(key.C0) == "CFrame", "Invalid animation layer key")
	key.Frame, key.Time, key.Motor, key.Part = frame, frame / fps, motor, motor.Part1
	local Properties = require("Properties")
	if Properties.is(motor) then
		assert(
			Properties.validate(motor, Properties.decode(motor, key.C0, key.PropertyValue)),
			"Invalid layered property"
		)
	end

	return key
end

local function availableTracks(rig, raw)
	local motors = require("motors").motors(rig, raw, true)
	if rig == require("State").currentRig then
		for motor in raw.DefaultPose do
			if motor.Part1 and motor.Part1:GetAttribute("EclipseNavigationOrigin") then
				motors["$origin"] = motor
			end
		end
	end

	return motors
end

function Storage.capture(rig, raw)
	if not raw.AnimationLayers then
		return nil
	end

	Layers.ensure(raw)
	Layers.syncProperties(raw)
	local stack = Layers.stack(raw, rig)
	local result = metadata(raw.AnimationLayers, stack)
	result.active = raw.AnimationLayers.activeByRig[rig] or "base"
	local motors = availableTracks(rig, raw)
	for i, layer in stack do
		local row = result.layers[i]
		row.tracks = {}
		row.properties = Layers.clone(layer.properties[rig] or { version = 1, tracks = {} })
		for id, motor in motors do
			local keys = {}
			for frame, key in layer.keys[motor] or {} do
				table.insert(keys, { frame = frame, key = Document.packKey(key) })
				local step = require("State").ProjectWorkStep
				if step then
					step()
				end
			end

			if #keys > 0 then
				table.sort(keys, function(a, b)
					return a.frame < b.frame
				end)
				table.insert(row.tracks, { id = id, keys = keys })
			end
		end

		table.sort(row.tracks, function(a, b)
			return a.id < b.id
		end)
	end

	return result
end

function Storage.write(sequence, rig, raw, archive)
	local value = archive or Storage.capture(rig, raw)
	if not value then
		return
	end

	local old = sequence:FindFirstChild(NAME)
	if old then
		old:Destroy()
	end

	Data.write(sequence, NAME, Document.pack(value))
end

local function legacyDuplicates(rig, sequence, value, available, budget)
	local ignored, wanted = {}, {}
	local project = sequence:GetAttribute("EclipseProjectId")
	if type(project) ~= "string" or project == "" then
		return ignored
	end

	for _, track in value.layers[1].tracks or {} do
		if
			type(track.id) == "string"
			and track.id:sub(1, 9) == "property:"
			and not available[track.id]
		then
			wanted[track.id] = track
		end
	end

	if not next(wanted) then
		return ignored
	end

	local declared = {}
	for _, layer in value.layers do
		for _, row in layer.properties and layer.properties.tracks or {} do
			declared["property:" .. row.id] = true
		end
	end

	local properties = sequence:FindFirstChild("EclipseProperties")
	if properties then
		for _, row in Document.unpackArchive(Data.read(properties), budget).tracks or {} do
			declared["property:" .. row.id] = true
		end
	end

	for id in declared do
		wanted[id] = nil
	end

	if not next(wanted) then
		return ignored
	end

	local function sameTrack(a, b)
		if type(b.keys) ~= "table" or #a.keys == 0 or #a.keys ~= #b.keys then
			return false
		end

		local keys = {}
		for _, entry in a.keys do
			if keys[entry.frame] then
				return false
			end

			keys[entry.frame] = entry.key
		end

		for _, entry in b.keys do
			if keys[entry.frame] ~= entry.key then
				return false
			end

			keys[entry.frame] = nil
		end

		return next(keys) == nil
	end

	local function inspect(owner, saved)
		if
			not saved:IsA("KeyframeSequence")
			or saved:GetAttribute("EclipseProjectId") ~= project
			or saved:GetAttribute("FPS") ~= sequence:GetAttribute("FPS")
		then
			return
		end

		local node = saved:FindFirstChild(NAME)
		local props = saved:FindFirstChild("EclipseProperties")
		if not node or not props then
			return
		end

		local archive = Document.unpackArchive(Data.read(node), budget)
		validate(archive)
		local base = archive.layers[1]
		local source = value.layers[1]
		if
			base.mode ~= source.mode
			or base.weight ~= source.weight
			or (base.muted == true) ~= (source.muted == true)
			or (base.solo == true) ~= (source.solo == true)
		then
			return
		end

		if not Document.equal(base.weightKeys or {}, source.weightKeys or {}) then
			return
		end

		local own = {}
		for _, row in Document.unpackArchive(Data.read(props), budget).tracks or {} do
			own["property:" .. row.id] = row.id
		end

		for _, track in base.tracks or {} do
			local original = wanted[track.id]
			if
				original
				and own[track.id]
				and require("Properties").definition(owner, own[track.id])
				and sameTrack(original, track)
			then
				ignored[original] = true
			end
		end
	end

	local pending = { rig }
	while #pending > 0 do
		local owner = table.remove(pending)
		for _, child in owner:GetChildren() do
			if child.Name == "AnimSaves" then
				if owner ~= rig then
					for _, saved in child:GetChildren() do
						pcall(inspect, owner, saved)
						if budget then
							budget()
						end
					end
				end
			else
				table.insert(pending, child)
			end
		end

		if budget then
			budget()
		end
	end

	return ignored
end

function Storage.restoreRig(rig, raw, value, keepActive, budget, sequence)
	local ids = validate(value)
	for _, layer in value.layers do
		for _, track in layer.tracks or {} do
			if track.id == "$origin" then
				require("Origin").ensure(require("State").Timeline)
			end
		end
	end

	local available = availableTracks(rig, raw)
	local rows = {}
	local ignored = sequence and legacyDuplicates(rig, sequence, value, available, budget) or {}
	for _, source in value.layers do
		local row = {}
		for k, v in source do
			if k ~= "tracks" and k ~= "properties" then
				row[k] = Layers.clone(v)
			end
		end

		row.keys = {}
		row.properties = {}
		for _, track in source.tracks or {} do
			if ignored[track] then
				continue
			end

			if track.id == "$origin" and rig ~= require("State").currentRig then
				continue
			end

			local motor =
				assert(available[track.id], "Layer control is missing: " .. tostring(track.id))
			local bucket = {}
			for _, entry in track.keys do
				bucket[entry.frame] = decodedKey(entry.key, motor, entry.frame, raw.FPS, budget)
				if budget then
					budget()
				end
			end

			row.keys[motor] = bucket
		end

		row.properties[rig] = Layers.clone(source.properties or { version = 1, tracks = {} })
		table.insert(rows, row)
	end

	local data = Layers.ensure(raw)
	local ordered = { data.layers[1] }
	local used = { base = true }

	for _, motor in available do
		data.layers[1].keys[motor] = nil
	end

	for i = 2, #data.layers do
		local layer = data.layers[i]
		if layer.owner ~= rig then
			table.insert(ordered, layer)
			used[layer.id] = true
		end
	end

	local target = "base"
	for _, row in rows do
		local original = row.id
		if row.id == "base" then
			for motor, bucket in row.keys do
				ordered[1].keys[motor] = bucket
			end

			ordered[1].properties[rig] = row.properties[rig]
		else
			row.owner = rig
			if used[row.id] then
				row.id = Http:GenerateGUID(false)
			end

			used[row.id] = true
			table.insert(ordered, row)
			if original == value.active and not row.locked then
				target = row.id
			end
		end
	end

	data.layers = ordered
	if not keepActive then
		data.activeByRig[rig] = target
	end

	Layers.rebuild(raw)
	Layers.restoreActiveProperties()
	return data.activeByRig[rig] or "base"
end

function Storage.prepareRead(sequence, budget)
	local node = sequence:FindFirstChild(NAME)
	if not node then
		return nil
	end

	local value = Document.unpackArchive(Data.read(node), budget)
	validate(value)
	return value
end

function Storage.read(sequence, rig, timeline, budget, prepared, targetPivot)
	local node = sequence:FindFirstChild(NAME)
	if not node then
		return false
	end

	local value = prepared or Storage.prepareRead(sequence, budget)
	local active = Storage.restoreRig(rig, timeline:GetState(), value, nil, budget, sequence)
	local raw = timeline:GetState()
	raw._LayerLoadActive = raw._LayerLoadActive or {}
	raw._LayerLoadActive[rig] = active
	local ratio = require("PoseSpace").savedRatio(rig, sequence)
	if ratio ~= 1 or typeof(sequence:GetAttribute("EclipseAuthoredPivot")) == "CFrame" then
		local available = require("motors").motors(rig, timeline:GetState(), true)
		for _, layer in timeline:GetState().AnimationLayers.layers do
			for _, motor in available do
				if
					typeof(motor) == "table"
					and (motor.IsEclipseProperty or motor.IsEclipseArmatureControl)
				then
					continue
				end

				for _, key in layer.keys[motor] or {} do
					require("PoseSpace").retargetKey(
						key,
						ratio,
						sequence:GetAttribute("EclipseAuthoredPivot"),
						targetPivot or require("PoseSpace").getImportPivot(rig, sequence)
					)
				end
			end
		end
	end

	return true
end

function Storage.withImport(timeline, fn)
	local raw = timeline:GetState()
	local data = raw.AnimationLayers
	local active
	if data then
		Layers.ensure(raw)
		Layers.syncProperties(raw)
		active = table.clone(data.activeByRig)
		data.activeByRig = {}
		Layers.rebuild(raw)
		Layers.restoreActiveProperties()
	end

	local loading = raw._LayerLoading
	raw._LayerLoading = true
	local result = table.pack(xpcall(fn, debug.traceback))
	raw._LayerLoading = loading
	if raw.AnimationLayers then
		Layers.ensure(raw)
		data = raw.AnimationLayers
		for rig, id in active or {} do
			data.activeByRig[rig] = id
		end

		for rig, id in raw._LayerLoadActive or {} do
			data.activeByRig[rig] = id
		end

		raw._LayerLoadActive = nil
		Layers.rebuild(raw)
		Layers.restoreActiveProperties()
	end

	if not result[1] then
		error(result[2], 0)
	end

	return table.unpack(result, 2, result.n)
end

return Storage
