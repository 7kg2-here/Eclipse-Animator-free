--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Http = game:GetService("HttpService")
local Paths = require("Paths")
local Storage = require("Storage")
local Rig = {}
local templates = {}
local generation = 0

local function stamp(object, root)
	if object:IsA("BasePart") or object:IsA("Bone") then
		object:SetAttribute("EclipseLibraryPath", Paths.of(object, root))
	end
end

local function clean(model)
	for _, object in model:GetDescendants() do
		if not object.Parent then
			continue
		end

		if
			Paths.excluded(object, model)
			or object.Name == "EclipseArmatureAnimation"
			or object.Name == "EclipseArmaturePropertyKeys"
		then
			object:Destroy()
		elseif object:IsA("BasePart") then
			object.LocalTransparencyModifier = 0
			object.Anchored = true
			object.CanCollide = false
			object.CanTouch = false
		elseif object:IsA("Decal") or object:IsA("Texture") then
			object.LocalTransparencyModifier = 0
		end
	end
end

function Rig.save(source, state)
	local signature = {}
	for _, object in source:GetDescendants() do
		if
			not Paths.excluded(object, source)
			and (object:IsA("BasePart") or object:IsA("JointInstance") or object:IsA("Bone"))
		then
			local content = object:IsA("MeshPart") and object.MeshId or ""
			table.insert(signature, Paths.of(object, source) .. content)
		end
	end

	table.sort(signature)
	signature = table.concat(signature, "|")
	local id = source:GetAttribute("EclipseLibraryRigId")
	local saved = typeof(id) == "string" and Storage.rig(id)
	if saved and saved.signature == signature then
		return id
	end

	id = Http:GenerateGUID(false):gsub("%-", "")
	local model = source:Clone()
	assert(model, "Turn on Archivable for this rig before saving it.")
	local ok, result = xpcall(function()
		for _, object in model:GetDescendants() do
			stamp(object, model)
		end

		for motor, default in state.DefaultPose do
			if
				typeof(motor) == "Instance"
				and motor:IsA("Motor6D")
				and motor:IsDescendantOf(source)
			then
				local target = Paths.resolve(model, Paths.of(motor, source))
				if target then
					target:SetAttribute("EclipseLibraryRestC0", default)
					target.C0 = default
					target.Transform = CFrame.identity
				end
			end
		end

		for part, size in state.DefaultSize or {} do
			if part:IsDescendantOf(source) then
				local target = Paths.resolve(model, Paths.of(part, source))
				if target then
					target.Size = size
				end
			end
		end

		for motor, frame in state.DefaultWorldPose or {} do
			local part = motor.Part1
			if
				typeof(part) == "Instance"
				and part:IsDescendantOf(source)
				and part:IsA("BasePart")
			then
				local target = Paths.resolve(model, Paths.of(part, source))
				if target then
					target.CFrame = frame
				end
			end
		end

		for _, object in model:GetDescendants() do
			if object:IsA("Bone") then
				object.Transform = CFrame.identity
			end

			if object:GetAttribute("EclipseArmatureInputC0") then
				object:SetAttribute("EclipseArmatureInputC0", nil)
				object:SetAttribute("EclipseArmatureInputScale", nil)
			end
		end

		local rest = model:GetAttribute("EclipseMasterRest")
		if rest then
			model:SetAttribute("EclipseMasterInput", rest)
			model:SetAttribute("EclipseMasterMovement", CFrame.identity)
		end

		clean(model)
		model:SetAttribute("EclipseLibraryRigId", id)
		Storage.saveRig(id, model, source.Name, signature)
		return id
	end, debug.traceback)
	model:Destroy()
	if not ok then
		error(result, 0)
	end

	source:SetAttribute("EclipseLibraryRigId", id)
	return result
end

function Rig.preview(id)
	local entry = templates[id]
	if not entry then
		local started = generation
		local model = Storage.loadRig(id)
		if generation ~= started then
			model:Destroy()
			error("Preview was closed.")
		end

		if templates[id] then
			model:Destroy()
			return templates[id].model:Clone()
		end

		local ok, err = pcall(function()
			for _, object in model:GetDescendants() do
				if object:IsA("Model") and object:FindFirstChild("EclipseArmatureGraph") then
					object:Destroy()
				end
			end

			clean(model)
		end)
		if not ok then
			model:Destroy()
			error(err, 0)
		end

		entry = { model = model, used = os.clock() }
		templates[id] = entry
		local count = 0
		for _ in templates do
			count += 1
		end

		if count > 4 then
			local oldest, key
			for k, v in templates do
				if k ~= id and (not oldest or v.used < oldest.used) then
					oldest, key = v, k
				end
			end

			if oldest then
				oldest.model:Destroy()
				templates[key] = nil
			end
		end
	end

	entry.used = os.clock()
	return entry.model:Clone()
end

function Rig.clear()
	generation += 1
	for _, entry in templates do
		entry.model:Destroy()
	end

	table.clear(templates)
end

return Rig
