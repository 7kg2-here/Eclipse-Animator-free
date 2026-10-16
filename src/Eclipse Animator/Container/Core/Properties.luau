-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)
local RigTraversal = require("RigTraversal")

local Document = require("Document")
local Chunks = require("ChunkStore")
local Interp = require("Interp")
local Camera = require("CameraRig")
local Paths = require("Paths")
local Tracks = {}
local EventDependencies = require("EventDependencies")

local function write(object, key, value)
	if EventDependencies.isPosing() then
		EventDependencies.poseWrite(object, key, value)
	else
		object[key] = value
	end
end

local EffectObjects = require("Objects")
local nodes = setmetatable({}, { __mode = "k" })
local folders = setmetatable({}, { __mode = "k" })
local owners = setmetatable({}, { __mode = "k" })
local meshes = setmetatable({}, { __mode = "k" })
local schemas = {
	{ "Model", { "CFrame", "Scale", "Transparency", "Color", "Reflectance" } },
	{
		"BasePart",
		{
			"CFrame",
			"Size",
			"Color",
			"Transparency",
			"Reflectance",
			"Material",
			"Anchored",
			"CastShadow",
		},
	},
	{ "MeshPart", { "ApplyTexture", "ApplyMesh" } },
	{ "SpecialMesh", { "Scale", "Offset", "VertexColor", "MeshType", "MeshId", "TextureId" } },
	{ "Camera", { "CFrame", "FieldOfView", "Focus", "HeadScale" } },
	{ "BlockMesh", { "Scale", "Offset", "VertexColor" } },
	{
		"SurfaceAppearance",
		{ "Color", "ColorMap", "MetalnessMap", "NormalMap", "RoughnessMap", "AlphaMode" },
	},
	{ "Shirt", { "Color3", "ShirtTemplate" } },
	{ "Pants", { "Color3", "PantsTemplate" } },
	{ "ShirtGraphic", { "Color3", "Graphic" } },
	{
		"Lighting",
		{
			"ClockTime",
			"Brightness",
			"Ambient",
			"OutdoorAmbient",
			"ExposureCompensation",
			"FogEnd",
			"FogStart",
			"FogColor",
			"GeographicLatitude",
			"ColorShift_Bottom",
			"ColorShift_Top",
			"EnvironmentDiffuseScale",
			"EnvironmentSpecularScale",
			"ShadowSoftness",
			"GlobalShadows",
		},
	},
	{ "Atmosphere", { "Color", "Density", "Offset", "Haze", "Decay", "Glare" } },
	{ "Clouds", { "Cover", "Density", "Color", "Enabled" } },
	{ "Fire", { "Enabled", "Color", "SecondaryColor", "Size", "Heat" } },
	{ "Sparkles", { "Enabled", "SparkleColor" } },
	{ "Smoke", { "Enabled", "Color", "Size", "Opacity", "RiseVelocity" } },
	{ "ForceField", { "Visible" } },
	{ "SoundGroup", { "Volume" } },
	{ "Attachment", { "CFrame" } },
	{ "Light", { "Brightness", "Color", "Enabled", "Shadows" } },
	{ "PointLight", { "Range" } },
	{ "SpotLight", { "Range", "Angle", "Face" } },
	{ "SurfaceLight", { "Range", "Angle", "Face" } },
	{ "Decal", { "Texture", "Color3", "Transparency", "Face" } },
	{ "Texture", { "OffsetStudsU", "OffsetStudsV", "StudsPerTileU", "StudsPerTileV" } },
	{
		"Sound",
		{
			"Volume",
			"PlaybackSpeed",
			"SoundId",
			"Looped",
			"RollOffMaxDistance",
			"RollOffMinDistance",
			"RollOffMode",
		},
	},
	{
		"ParticleEmitter",
		{
			"Enabled",
			"Rate",
			"Lifetime",
			"Speed",
			"Acceleration",
			"Drag",
			"Rotation",
			"RotSpeed",
			"SpreadAngle",
			"VelocityInheritance",
			"LightEmission",
			"LightInfluence",
			"ZOffset",
			"TimeScale",
			"Texture",
		},
	},
	{
		"Beam",
		{
			"Enabled",
			"Width0",
			"Width1",
			"CurveSize0",
			"CurveSize1",
			"Texture",
			"TextureLength",
			"TextureSpeed",
			"LightEmission",
			"LightInfluence",
			"FaceCamera",
		},
	},
	{
		"Trail",
		{
			"Enabled",
			"Lifetime",
			"MinLength",
			"MaxLength",
			"Texture",
			"TextureLength",
			"LightEmission",
			"LightInfluence",
			"FaceCamera",
		},
	},
	{
		"Highlight",
		{
			"Enabled",
			"FillColor",
			"OutlineColor",
			"FillTransparency",
			"OutlineTransparency",
			"DepthMode",
		},
	},
	{ "ColorCorrectionEffect", { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" } },
	{ "BloomEffect", { "Enabled", "Intensity", "Size", "Threshold" } },
	{ "BlurEffect", { "Enabled", "Size" } },
	{
		"DepthOfFieldEffect",
		{ "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
	},
	{ "SunRaysEffect", { "Enabled", "Intensity", "Spread" } },
	{ "NumberValue", { "Value" } },
	{ "IntValue", { "Value" } },
	{ "BoolValue", { "Value" } },
	{ "StringValue", { "Value" } },
	{ "Color3Value", { "Value" } },
	{ "Vector3Value", { "Value" } },
	{ "CFrameValue", { "Value" } },
}
local members = setmetatable({}, { __mode = "k" })

local function aggregate(rig, id)
	return not EffectObjects.is(rig)
		and (rig:IsA("Model") and rig.Parent ~= game)
		and (id == "Color" or id == "Transparency" or id == "Reflectance")
end

local function captures(rig, id)
	local rows = {}
	for _, object in RigTraversal.rigDescendants(rig) do
		if
			(object:IsA("BasePart") or id == "Transparency" and object:IsA("Decal"))
			and not Paths.excluded(object, rig)
		then
			table.insert(rows, { path = Paths.of(object, rig), value = object[id] })
		end
	end

	return rows
end

local function modelMembers(motor)
	local node = motor.Part1
	local source = node:GetAttribute("Members")
	local cache = members[node]
	if not cache or cache.source ~= source then
		local rows = source and Document.unpack(source) or captures(motor.Rig, motor.PropertyId)
		cache = { source = source, rows = {} }
		members[node] = cache
		for _, row in rows do
			local object = Paths.resolve(motor.Rig, row.path)
			if object then
				table.insert(cache.rows, { object = object, value = row.value })
			end
		end
	end

	return cache.rows
end

function Tracks.restoreValue(motor)
	if aggregate(motor.Rig, motor.PropertyId) then
		for _, row in modelMembers(motor) do
			if row.object:IsDescendantOf(motor.Rig) then
				write(row.object, motor.PropertyId, row.value)
			end
		end

		motor.Part1:SetAttribute("Current", nil)
	else
		Tracks.setValue(motor, motor.DefaultValue)
	end
end

local function finite(value)
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isClock(rig, id)
	return rig:IsA("Lighting") and (id == "ClockTime" or id == "TimeOfDay")
end

local function clockValue(value)
	if typeof(value) == "number" then
		return value
	end

	if typeof(value) ~= "string" then
		return nil
	end

	local number = tonumber(value)
	if number then
		return number
	end

	local h, m, s = value:match("^%s*(%d+):(%d+):?([%d%.]*)%s*$")
	if not h then
		return nil
	end

	h, m, s = tonumber(h), tonumber(m), tonumber(s) or 0
	if m >= 60 or s >= 60 then
		return nil
	end

	return h + m / 60 + s / 3600
end

function Tracks.readValue(rig, id)
	if EffectObjects.is(rig) then
		return EffectObjects.read(rig, id)
	end

	if isClock(rig, id) then
		return rig.ClockTime
	end

	if aggregate(rig, id) then
		local folder = Tracks.folder(rig, false)
		local node = folder and folder:FindFirstChild(id)
		local current = node and node:GetAttribute("Current")
		if current ~= nil then
			return current
		end

		if id ~= "Color" then
			return 0
		end

		for _, object in RigTraversal.rigDescendants(rig) do
			if object:IsA("BasePart") and not Paths.excluded(object, rig) then
				return object.Color
			end
		end

		return Color3.new(1, 1, 1)
	end

	if id == "ApplyMesh" then
		return rig.MeshId
	end

	if (rig:IsA("Model") and rig.Parent ~= game) and id == "Scale" then
		return rig:GetScale()
	end

	if (rig:IsA("Model") and rig.Parent ~= game) and id == "CFrame" then
		return rig:GetPivot()
	end

	return rig[id == "ApplyTexture" and "TextureID" or id]
end

function Tracks.prepare(motor, value)
	if motor.PropertyId ~= "ApplyMesh" then
		return
	end

	local rig = motor.Rig
	local cache = meshes[rig]
	if not cache then
		cache = {}
		meshes[rig] = cache
		local original = Instance.new("MeshPart")
		original:ApplyMesh(rig)
		cache[rig.MeshId] = original
		rig.Destroying:Once(function()
			for _, part in cache do
				part:Destroy()
			end

			meshes[rig] = nil
		end)
	end

	if cache[value] then
		return
	end

	assert(value:match("^rbxassetid://%d+$") or value:match("^https?://"), "Enter a mesh asset URL")
	cache[value] = game:GetService("AssetService"):CreateMeshPartAsync(
		Content.fromUri(value),
		{ CollisionFidelity = rig.CollisionFidelity, RenderFidelity = rig.RenderFidelity }
	)
end

local reflected = {}
local supported = {
	number = true,
	boolean = true,
	string = true,
	EnumItem = true,
	Vector2 = true,
	Vector3 = true,
	Color3 = true,
	CFrame = true,
	NumberRange = true,
	UDim = true,
	UDim2 = true,
	Rect = true,
	BrickColor = true,
	NumberSequence = true,
	ColorSequence = true,
}
local excluded = {
	Name = true,
	Parent = true,
	Archivable = true,
	Source = true,
	Capabilities = true,
	Sandboxed = true,
	UniqueId = true,
	HistoryId = true,
	Tags = true,
	Attributes = true,
}

local function reflectedNames(class)
	if reflected[class] then
		return reflected[class]
	end

	local names = {}
	local ok, properties = pcall(function()
		return game:GetService("ReflectionService"):GetPropertiesOfClass(class)
	end)
	if ok then
		for _, property in properties do
			if
				property.Permits.Write ~= nil
				and property.Permits.Read ~= nil
				and property.Display
				and not property.Display.DeprecationMessage
				and not excluded[property.Name]
				and property.Owner ~= "Instance"
				and property.Owner ~= "Object"
			then
				table.insert(names, property.Name)
			end
		end
	end

	table.sort(names)
	reflected[class] = names
	return names
end

function Tracks.propertyOnly(object)
	return object.Parent == game
		or object:IsA("Terrain")
		or not (object:IsA("Model") or object:IsA("BasePart"))
end

function Tracks.catalog(rig)
	if EffectObjects.is(rig) then
		return EffectObjects.catalog(rig)
	end

	if
		not rig
		or rig:IsA("LuaSourceContainer")
		or rig:IsA("Folder")
		or rig:IsA("DataModel")
		or rig.Parent == game and not rig:IsA("Lighting")
	then
		return {}
	end

	if Camera.isRig(rig) then
		return {
			{ id = "CFrame", label = "CFrame", kind = "CFrame", builtin = true },
			{ id = "FieldOfView", label = "FOV", kind = "number", builtin = true },
		}
	end

	local list, seen = {}, {}

	local function add(id)
		if seen[id] then
			return
		end

		seen[id] = true
		if rig:IsA("Lighting") and id == "TimeOfDay" then
			local folder = Tracks.folder(rig, false)
			if not folder or not folder:FindFirstChild(id) then
				return
			end
		end

		if
			rig:IsA("Terrain")
				and ({
					CFrame = true,
					Position = true,
					Orientation = true,
					PivotOffset = true,
					Size = true,
				})[id]
			or rig:IsA("Workspace") and id == "WorldPivot"
		then
			return
		end

		local ok, value = pcall(Tracks.readValue, rig, id)
		if ok and supported[typeof(value)] then
			table.insert(list, {
				id = id,
				label = id,
				kind = typeof(value),
				enum = typeof(value) == "EnumItem" and value.EnumType or nil,
			})
		end
	end

	for _, schema in schemas do
		if
			rig:IsA(schema[1]) and not (rig.Parent == game or rig:IsA("Terrain"))
			or rig.ClassName == schema[1]
		then
			for _, id in schema[2] do
				add(id)
			end
		end
	end

	for _, id in reflectedNames(rig.ClassName) do
		if id ~= "TextureID" or not rig:IsA("MeshPart") then
			add(id)
		end
	end

	return list
end

function Tracks.definition(rig, id)
	if rig:IsA("Lighting") and id == "TimeOfDay" then
		return { id = id, label = id, kind = "number" }
	end

	for _, def in Tracks.catalog(rig) do
		if def.id == id then
			return def
		end
	end
end

function Tracks.inheritedTransform(rig)
	if not rig or not (rig:IsA("BasePart") or rig:IsA("Model")) then
		return false
	end

	local State = require("State")
	for _, owner in State.getAllRigs and State.getAllRigs() or {} do
		if owner ~= rig and owner:IsA("Model") and rig:IsDescendantOf(owner) then
			return true
		end
	end

	return false
end

function Tracks.required(rig, id)
	if EffectObjects.is(rig) then
		return false
	end

	if id ~= "CFrame" or Camera.isRig(rig) or rig.Parent == game or rig:IsA("Terrain") then
		return false
	end

	if Tracks.inheritedTransform(rig) then
		return false
	end

	if rig:IsA("Model") and rig.Parent ~= game then
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		if
			humanoid
			and (
				humanoid.RigType == Enum.HumanoidRigType.R6 and rig:FindFirstChild("Torso")
				or humanoid.RigType == Enum.HumanoidRigType.R15
					and rig:FindFirstChild("UpperTorso")
					and rig:FindFirstChild("LowerTorso")
			)
		then
			return false
		end

		return true
	end

	return rig:IsA("BasePart") or rig:IsA("Attachment")
end

function Tracks.owner(node)
	return owners[node] or node.Parent and owners[node.Parent]
end

function Tracks.folder(rig, create)
	local folder = folders[rig]
	if folder then
		return folder
	end

	for _, child in rig:GetChildren() do
		if child:IsA("Folder") and child:GetAttribute("EclipsePropertyTracks") == 1 then
			folder = child
			break
		end
	end

	if not folder and create then
		folder = Instance.new("Folder")
		folder.Name = "Properties"
		folder:SetAttribute("EclipsePropertyTracks", 1)
	end

	if folder then
		folder.Parent = nil
		folder.Archivable = false
		folders[rig] = folder
		owners[folder] = rig
		rig.Destroying:Once(function()
			folders[rig] = nil
			owners[folder] = nil
			folder:Destroy()
		end)
	end

	return folder
end

function Tracks.is(motor)
	return typeof(motor) == "table" and motor.IsEclipseProperty == true
end

function Tracks.isNode(node)
	return typeof(node) == "Instance"
		and node:GetAttribute("EclipseProperty") ~= nil
		and node.Parent
		and node.Parent:GetAttribute("EclipsePropertyTracks") == 1
end

function Tracks.encode(value)
	local kind = typeof(value)
	if kind == "CFrame" then
		return value
	end

	if kind == "number" then
		return CFrame.new(value, 0, 0)
	end

	if kind == "Vector3" then
		return CFrame.new(value)
	end

	if kind == "Vector2" then
		return CFrame.new(value.X, value.Y, 0)
	end

	if kind == "Color3" then
		return CFrame.new(value.R, value.G, value.B)
	end

	if kind == "NumberRange" then
		return CFrame.new(value.Min, value.Max, 0)
	end

	return CFrame.identity
end

function Tracks.decode(motor, cf, explicit)
	local kind = motor.Definition.kind
	if isClock(motor.Rig, motor.PropertyId) and explicit ~= nil then
		return assert(clockValue(explicit), "Enter a time from 0 to 24 hours")
	end

	if explicit ~= nil and typeof(explicit) == kind then
		return explicit
	end

	if kind == "CFrame" then
		return cf
	end

	if kind == "number" then
		return cf.X
	end

	if kind == "Vector3" then
		return cf.Position
	end

	if kind == "Vector2" then
		return Vector2.new(cf.X, cf.Y)
	end

	if kind == "Color3" then
		return Color3.new(math.clamp(cf.X, 0, 1), math.clamp(cf.Y, 0, 1), math.clamp(cf.Z, 0, 1))
	end

	if kind == "NumberRange" then
		return NumberRange.new(math.min(cf.X, cf.Y), math.max(cf.X, cf.Y))
	end

	return motor.DefaultValue
end

function Tracks.validate(motor, value)
	if typeof(value) ~= motor.Definition.kind then
		return false
	end

	local ok = pcall(Document.pack, value)
	if not ok then
		return false
	end

	local id = motor.PropertyId
	if motor.Definition.enum and value.EnumType ~= motor.Definition.enum then
		return false
	end

	if typeof(value) == "number" and not finite(value) then
		return false
	end

	if id == "ZIndex" and EffectObjects.is(motor.Rig) then
		return value >= -100 and value <= 100
	end

	if id == "Scale" and typeof(value) == "number" then
		return value >= 0.001 and value <= 10000
	end

	if id == "Size" and typeof(value) == "Vector3" then
		return value.X >= 0.001 and value.Y >= 0.001 and value.Z >= 0.001
	end

	if (id:find("Transparency") or id == "Reflectance") and typeof(value) == "number" then
		return value >= 0 and value <= 1
	end

	if isClock(motor.Rig, id) then
		return finite(value) and value >= 0 and value <= 24
	end

	if id == "FieldOfView" then
		return value >= 1 and value <= 120
	end

	return true
end

function Tracks.setValue(motor, value)
	assert(Tracks.validate(motor, value), "Invalid " .. motor.PropertyId .. " value")
	local rig, id = motor.Rig, motor.PropertyId
	if EffectObjects.is(rig) then
		EffectObjects.write(rig, id, value)
		return
	end

	if isClock(rig, id) then
		if rig.ClockTime ~= value % 24 then
			rig.ClockTime = value % 24
		end

		return
	end

	if aggregate(rig, id) then
		motor.Part1:SetAttribute("Current", value)
		for _, row in modelMembers(motor) do
			if row.object:IsDescendantOf(rig) then
				local changed = id == "Color" and value or row.value + (1 - row.value) * value
				if row.object[id] ~= changed then
					write(row.object, id, changed)
				end
			end
		end
	elseif id == "ApplyMesh" then
		if rig.MeshId == value then
			return
		end

		local mesh = meshes[rig] and meshes[rig][value]
		assert(mesh, "Mesh asset has not loaded")
		local size, texture = rig.Size, rig.TextureID
		rig:ApplyMesh(mesh)
		rig.Size = size
		rig.TextureID = texture
	elseif (rig:IsA("Model") and rig.Parent ~= game) and id == "Scale" then
		if math.abs(rig:GetScale() - value) > 1e-7 then
			if EventDependencies.isPosing() then
				EventDependencies.poseModel(rig, "scale", value)
			else
				rig:ScaleTo(value)
			end
		end
	elseif (rig:IsA("Model") and rig.Parent ~= game) and id == "CFrame" then
		if rig:GetPivot() ~= value then
			if EventDependencies.isPosing() then
				EventDependencies.poseModel(rig, "pivot", value)
			else
				rig:PivotTo(value)
			end
		end
	else
		local property = id == "ApplyTexture" and "TextureID" or id
		if rig[property] ~= value then
			write(rig, property, value)
		end
	end
end

local defaultCache = setmetatable({}, { __mode = "k" })

function Tracks.fromNode(node)
	if not Tracks.isNode(node) then
		return nil
	end

	if nodes[node] then
		return nodes[node]
	end

	local rig = Tracks.owner(node) or node.Parent.Parent
	local id = node:GetAttribute("EclipseProperty")
	local def = Tracks.definition(rig, id)
	if not def then
		return nil
	end

	local motor = {
		Rig = rig,
		PropertyId = id,
		Definition = def,
		IsEclipseProperty = true,
		Part1 = node,
		Part0 = { CFrame = CFrame.identity },
		C1 = CFrame.identity,
	}
	setmetatable(motor, {
		__index = function(_, key)
			if key == "Parent" then
				return node.Parent and rig.Parent and rig
			end

			if key == "Name" then
				return node.Name
			end

			if key == "DefaultValue" then
				local raw = node:GetAttribute("Default")
				local cached = defaultCache[node]
				if not cached or cached.raw ~= raw then
					cached = { raw = raw, value = Document.unpack(raw) }
					defaultCache[node] = cached
				end

				local value = cached.value
				return isClock(rig, id) and assert(clockValue(value), "Invalid saved time of day")
					or value
			end

			if key == "C0" then
				return Tracks.encode(Tracks.readValue(rig, id))
			end

			if key == "GetAttribute" then
				return function(_, name)
					return node:GetAttribute(name)
				end
			end

			if key == "SetAttribute" then
				return function(_, name, value)
					node:SetAttribute(name, value)
				end
			end

			if key == "GetAttributes" then
				return function()
					return node:GetAttributes()
				end
			end

			if key == "IsA" then
				return function(_, class)
					return class == "Motor6D"
				end
			end
		end,
		__newindex = function(_, key, value)
			if key == "C0" then
				Tracks.setValue(motor, Tracks.decode(motor, value))
			else
				rawset(motor, key, value)
			end
		end,
	})
	nodes[node] = motor
	return motor
end

function Tracks.list(rig, includeDisabled, skipRequired)
	if not skipRequired and Tracks.required(rig, "CFrame") then
		local storage = Tracks.folder(rig, false)
		local node = storage and storage:FindFirstChild("CFrame")
		if not node or node:GetAttribute("Enabled") == false then
			Tracks.enable(rig, "CFrame", true)
		end
	end

	local folder = Tracks.folder(rig, false)
	local out = {}
	if folder then
		for _, node in folder:GetChildren() do
			local motor = Tracks.fromNode(node)
			if motor and (includeDisabled or node:GetAttribute("Enabled") ~= false) then
				table.insert(out, motor)
			end
		end
	end

	table.sort(out, function(a, b)
		return a.PropertyId < b.PropertyId
	end)
	return out
end

function Tracks.enable(rig, id, enabled, raw)
	if Tracks.required(rig, id) then
		enabled = true
	end

	assert(Tracks.definition(rig, id), "This item does not support " .. id)
	if Camera.isRig(rig) then
		rig:SetAttribute("EclipsePropertyEnabled_" .. id, nil)
		local motor = Camera.motor(rig, id == "CFrame" and "CamPart" or "FovPart")
		return motor
	end

	local motor
	for _, candidate in Tracks.list(rig, true, true) do
		if candidate.PropertyId == id then
			motor = candidate
			break
		end
	end

	if not motor then
		local node = Instance.new("Folder")
		node.Name = id
		node:SetAttribute("EclipseProperty", id)
		node:SetAttribute("Default", Document.pack(Tracks.readValue(rig, id)))
		if aggregate(rig, id) then
			node:SetAttribute("Members", Document.pack(captures(rig, id)))
		end

		node.Parent = Tracks.folder(rig, true)
		motor = Tracks.fromNode(node)
	end

	motor.Part1:SetAttribute("Enabled", enabled)
	Tracks.prepare(motor, motor.DefaultValue)
	if raw then
		raw.DefaultPose[motor] = Tracks.encode(motor.DefaultValue)
		raw.MotorByPart[motor.Part1] = motor
		raw.ParentingDefaults[motor] = true
	end

	if not enabled then
		Tracks.restoreValue(motor)
	end

	return motor
end

function Tracks.enabled(rig, id)
	if Camera.isRig(rig) then
		return id == "CFrame" or id == "FieldOfView"
	end

	for _, motor in Tracks.list(rig, true) do
		if motor.PropertyId == id then
			return motor.Part1:GetAttribute("Enabled") ~= false
		end
	end

	return false
end

function Tracks.scaleFactor(motor)
	if Tracks.is(motor) or typeof(motor) == "table" and motor.IsEclipseMasterControl then
		return 1
	end

	local part = motor.Part1
	while typeof(part) == "Instance" do
		if part:IsA("Model") then
			for _, property in Tracks.list(part, true) do
				if property.PropertyId == "Scale" then
					return part:GetScale() / property.DefaultValue
				end
			end
		end

		part = part.Parent
	end

	return 1
end

function Tracks.basePose(motor, cf)
	if not cf then
		return nil
	end

	local factor = Tracks.scaleFactor(motor)
	return factor == 1 and cf or CFrame.new(cf.Position / factor) * cf.Rotation
end

local complex = {
	UDim = true,
	UDim2 = true,
	Rect = true,
	BrickColor = true,
	NumberSequence = true,
	ColorSequence = true,
}

local function blendProperty(a, b, sample)
	local kind = typeof(a)

	local function color(get)
		return Color3.new(
			math.clamp(
				sample(function(v)
					return get(v).R
				end),
				0,
				1
			),
			math.clamp(
				sample(function(v)
					return get(v).G
				end),
				0,
				1
			),
			math.clamp(
				sample(function(v)
					return get(v).B
				end),
				0,
				1
			)
		)
	end

	if kind == "UDim" then
		return UDim.new(
			sample(function(v)
				return v.Scale
			end),
			sample(function(v)
				return v.Offset
			end)
		)
	end

	if kind == "UDim2" then
		return UDim2.new(
			sample(function(v)
				return v.X.Scale
			end),
			sample(function(v)
				return v.X.Offset
			end),
			sample(function(v)
				return v.Y.Scale
			end),
			sample(function(v)
				return v.Y.Offset
			end)
		)
	end

	if kind == "Rect" then
		return Rect.new(
			sample(function(v)
				return v.Min.X
			end),
			sample(function(v)
				return v.Min.Y
			end),
			sample(function(v)
				return v.Max.X
			end),
			sample(function(v)
				return v.Max.Y
			end)
		)
	end

	if kind == "BrickColor" then
		return BrickColor.new(color(function(v)
			return v.Color
		end))
	end

	local times, seen = {}, {}
	for _, sequence in { a, b } do
		for _, key in sequence.Keypoints do
			if not seen[key.Time] then
				seen[key.Time] = true
				table.insert(times, key.Time)
			end
		end
	end

	table.sort(times)

	local function at(sequence, time)
		local keys = sequence.Keypoints
		for i = 2, #keys do
			if keys[i].Time >= time then
				local l, r = keys[i - 1], keys[i]
				local t = (time - l.Time) / (r.Time - l.Time)
				if kind == "ColorSequence" then
					return l.Value:Lerp(r.Value, t), 0
				end

				return l.Value + (r.Value - l.Value) * t, l.Envelope + (r.Envelope - l.Envelope) * t
			end
		end
	end

	local keys = {}
	for _, time in times do
		if kind == "ColorSequence" then
			table.insert(
				keys,
				ColorSequenceKeypoint.new(
					time,
					color(function(v)
						return at(v, time)
					end)
				)
			)
		else
			local value = sample(function(v)
				return at(v, time)
			end)
			local envelope = sample(function(v)
				local _, e = at(v, time)
				return e
			end)
			table.insert(keys, NumberSequenceKeypoint.new(time, value, math.max(0, envelope)))
		end
	end

	while #keys > 20 do
		local best, errorAt = 2, math.huge
		for i = 2, #keys - 1 do
			local l, k, r = keys[i - 1], keys[i], keys[i + 1]
			local t = (k.Time - l.Time) / (r.Time - l.Time)
			local error
			if kind == "ColorSequence" then
				local c = l.Value:Lerp(r.Value, t)
				error = (Vector3.new(k.Value.R, k.Value.G, k.Value.B) - Vector3.new(c.R, c.G, c.B)).Magnitude
			else
				error = math.abs(k.Value - (l.Value + (r.Value - l.Value) * t))
					+ math.abs(k.Envelope - (l.Envelope + (r.Envelope - l.Envelope) * t))
			end

			if error < errorAt then
				best, errorAt = i, error
			end
		end

		table.remove(keys, best)
	end

	return kind == "ColorSequence" and ColorSequence.new(keys) or NumberSequence.new(keys)
end

local function activePropertyBucket(motor, bucket)
	local cache = bucket and require("cache").poseCache()
	local views
	if cache and cache.persistent then
		cache.propertyBuckets = cache.propertyBuckets or setmetatable({}, { __mode = "k" })
		views = cache.propertyBuckets[bucket]
		if not views then
			views = setmetatable({}, { __mode = "k" })
			cache.propertyBuckets[bucket] = views
		end

		if views[motor] ~= nil then
			return views[motor] == true and bucket or views[motor]
		end
	end

	local active
	if isClock(motor.Rig, motor.PropertyId) then
		active = {}
		for frame, key in bucket or {} do
			if not key.Disabled then
				local value = Tracks.decode(motor, key.C0, key.PropertyValue)
				local copy = table.clone(key)
				copy.C0 = Tracks.encode(value)
				copy.Position = copy.C0.Position
				copy.PropertyValue = value
				active[frame] = copy
			end
		end
	else
		local hasDisabled = false
		for _, key in bucket or {} do
			if key.Disabled then
				hasDisabled = true
				break
			end
		end

		if hasDisabled then
			active = {}
			for frame, key in bucket do
				if not key.Disabled then
					active[frame] = key
				end
			end
		else
			active = bucket or {}
		end
	end

	if views then
		views[motor] = active == bucket and true or active
	end

	return active
end

function Tracks.evaluate(motor, bucket, time, loopEnd)
	bucket = activePropertyBucket(motor, require("Cache").active(bucket))
	local previous, following
	local index = Interp.index(bucket)
	if index then
		local p = Interp.search(index, time)
		previous = index[p] and index[p].key
		following = index[p + 1] and index[p + 1].key
	else
		for _, key in bucket or {} do
			if not key.Disabled then
				if key.Time <= time and (not previous or key.Time > previous.Time) then
					previous = key
				end

				if key.Time > time and (not following or key.Time < following.Time) then
					following = key
				end
			end
		end
	end

	if not previous and not following then
		return motor.DefaultValue
	end

	if not previous then
		return Tracks.decode(motor, following.C0, following.PropertyValue)
	end

	if not following or previous.Time == time then
		return Tracks.decode(motor, previous.C0, previous.PropertyValue)
	end

	if table.find({ "string", "boolean", "EnumItem" }, motor.Definition.kind) then
		return Tracks.decode(motor, previous.C0, previous.PropertyValue)
	end

	local alpha = (time - previous.Time) / (following.Time - previous.Time)
	if complex[motor.Definition.kind] then
		local source = bucket
		if index then
			source = {}
			local p = Interp.search(index, time)
			for _, i in { 1, 2, #index - 1, #index, p - 1, p, p + 1, p + 2 } do
				local row = index[i]
				if row then
					source[row.frame] = row.key
				end
			end
		end

		local function sample(extract)
			local projected = {}
			local left, right
			for frame, key in source do
				local point = table.clone(key)
				point.C0 =
					CFrame.new(extract(Tracks.decode(motor, key.C0, key.PropertyValue)), 0, 0)
				projected[frame] = point
				if key == previous then
					left = point
				elseif key == following then
					right = point
				end
			end

			return Interp.cframe(projected, left, right, alpha, "C0", loopEnd).X
		end

		return blendProperty(
			Tracks.decode(motor, previous.C0, previous.PropertyValue),
			Tracks.decode(motor, following.C0, following.PropertyValue),
			sample
		)
	end

	local value =
		Tracks.decode(motor, Interp.cframe(bucket, previous, following, alpha, "C0", loopEnd))
	local id = motor.PropertyId
	if typeof(value) == "number" then
		if isClock(motor.Rig, id) then
			value = math.clamp(value, 0, 24)
		elseif id == "Scale" then
			value = math.clamp(value, 0.001, 10000)
		elseif id:find("Transparency") or id == "Reflectance" then
			value = math.clamp(value, 0, 1)
		elseif id == "FieldOfView" then
			value = math.clamp(value, 1, 120)
		end
	elseif id == "Size" and typeof(value) == "Vector3" then
		value = Vector3.new(
			math.max(0.001, value.X),
			math.max(0.001, value.Y),
			math.max(0.001, value.Z)
		)
	end

	return value
end

function Tracks.beginPose(rig)
	for _, motor in Tracks.list(rig) do
		if
			(rig:IsA("Model") and rig.Parent ~= game)
			and (
				motor.PropertyId == "Scale"
				or motor.PropertyId == "CFrame" and not Tracks.inheritedTransform(rig)
			)
		then
			Tracks.setValue(motor, motor.DefaultValue)
		end
	end
end

function Tracks.apply(rig, raw, time, loopEnd, propertySamples)
	local Target = require("Target")
	Target.invalidatePropertySamples(propertySamples, rig)
	local list = Tracks.list(rig)
	local clockMotor, clockRank
	for _, motor in list do
		if isClock(rig, motor.PropertyId) then
			local keyed = false
			for _, key in raw.Keyframes[motor] or {} do
				if not key.Disabled then
					keyed = true
					break
				end
			end

			local rank = motor:GetAttribute("EclipseDisabled") and -1
				or (keyed and 4 or 0) + (motor.PropertyId == "ClockTime" and 1 or 0)
			if not clockRank or rank > clockRank then
				clockMotor, clockRank = motor, rank
			end
		end
	end

	for _, motor in list do
		if motor.PropertyId ~= "CFrame" then
			if isClock(rig, motor.PropertyId) and motor ~= clockMotor then
				continue
			end

			local value
			if motor:GetAttribute("EclipseDisabled") then
				value = motor.DefaultValue
			else
				value = Tracks.evaluate(motor, raw.Keyframes[motor], time, loopEnd)
			end

			if
				aggregate(rig, motor.PropertyId)
				and (motor:GetAttribute("EclipseDisabled") or not next(raw.Keyframes[motor] or {}))
			then
				Tracks.restoreValue(motor)
			else
				Tracks.setValue(motor, value)
			end
		end
	end

	for _, motor in list do
		if motor.PropertyId == "CFrame" then
			if Tracks.inheritedTransform(rig) and not next(raw.Keyframes[motor] or {}) then
				continue
			end

			local value
			if motor:GetAttribute("EclipseDisabled") then
				value = motor.DefaultValue
			else
				local Target = require("Target")
				local bucket = raw.Keyframes[motor]
				if Target.hasChild(bucket) then
					value = Target.childWorld(time, bucket, function(key)
						return Tracks.decode(motor, key.C0, key.PropertyValue)
					end, propertySamples)
				end

				value = value or Tracks.evaluate(motor, bucket, time, loopEnd)
			end

			Tracks.setValue(motor, value)
			require("Target").watchProperty(motor, time)
		end
	end

	Target.invalidatePropertySamples(propertySamples, rig)
end

function Tracks.captureDefaults(rig)
	for _, motor in Tracks.list(rig, true) do
		local value = Tracks.readValue(rig, motor.PropertyId)
		if aggregate(rig, motor.PropertyId) and motor.PropertyId ~= "Color" then
			value = 0
		end

		local node = motor.Part1
		node:SetAttribute("Default", Document.pack(value))
		if aggregate(rig, motor.PropertyId) then
			node:SetAttribute("Members", Document.pack(captures(rig, motor.PropertyId)))
		end

		node:SetAttribute("Current", nil)
		Tracks.prepare(motor, value)
	end
end

function Tracks.restoreDefaults(rig)
	for _, motor in Tracks.list(rig, true) do
		if motor.PropertyId == "CFrame" and Tracks.inheritedTransform(rig) then
			continue
		end

		Tracks.prepare(motor, motor.DefaultValue)
		Tracks.restoreValue(motor)
	end
end

function Tracks.snapshot(rig, raw, withKeys)
	local rows = {}
	for _, motor in Tracks.list(rig, true) do
		local keys = {}
		if withKeys then
			for frame, key in raw.Keyframes[motor] or {} do
				keys[frame] = Document.unpack(Document.pack(key))
			end
		end

		table.insert(rows, {
			id = motor.PropertyId,
			default = motor.DefaultValue,
			members = motor.Part1:GetAttribute("Members") and Document.unpack(
				motor.Part1:GetAttribute("Members")
			) or nil,
			enabled = motor.Part1:GetAttribute("Enabled") ~= false,
			disabled = motor:GetAttribute("EclipseDisabled") == true,
			keys = withKeys and keys or nil,
		})
	end

	return {
		version = 1,
		tracks = rows,
		individualParts = rig:GetAttribute("EclipseIndividualParts"),
		partChoices = require("PartRig").choice(rig),
		camera = Camera.isRig(rig) and {
			CFrame = Tracks.enabled(rig, "CFrame"),
			FieldOfView = Tracks.enabled(rig, "FieldOfView"),
		} or nil,
	}
end

function Tracks.restore(rig, data, timeline, sanitize)
	assert(data.version == 1 and type(data.tracks) == "table", "Invalid property tracks")
	rig:SetAttribute("EclipseIndividualParts", data.individualParts)
	require("PartRig").restoreChoice(rig, data.partChoices)
	local raw = timeline:GetState()
	local wanted = {}
	if Camera.isRig(rig) then
		for _, def in Tracks.catalog(rig) do
			Tracks.enable(rig, def.id, not data.camera or data.camera[def.id] ~= false, raw)
		end
	end

	for _, row in data.tracks do
		if isClock(rig, row.id) then
			row = table.clone(row)
			row.default = assert(clockValue(row.default), "Invalid saved time of day")
			if row.keys then
				local keys = {}
				for frame, key in row.keys do
					local copy = table.clone(key)
					local value = copy.PropertyValue ~= nil
							and assert(clockValue(copy.PropertyValue), "Invalid saved time key")
						or copy.C0.X
					copy.PropertyValue = value
					copy.C0 = Tracks.encode(value)
					copy.Position = copy.C0.Position
					copy.Rotation = copy.C0.Rotation
					keys[frame] = copy
				end

				row.keys = keys
			end
		end

		local motor = Tracks.enable(rig, row.id, row.enabled, raw)
		wanted[motor] = true
		if row.members and aggregate(rig, row.id) then
			motor.Part1:SetAttribute("Members", Document.pack(row.members))
		end

		assert(Tracks.validate(motor, row.default), "Invalid property default")
		Tracks.prepare(motor, row.default)
		motor.Part1:SetAttribute("Default", Document.pack(row.default))
		motor:SetAttribute("EclipseDisabled", row.disabled and true or nil)
		if not row.enabled then
			Tracks.restoreValue(motor)
		end

		raw.DefaultPose[motor] = Tracks.encode(row.default)
		if row.keys then
			for frame, key in row.keys do
				local value = Tracks.decode(motor, key.C0, key.PropertyValue)
				assert(Tracks.validate(motor, value), "Invalid saved property value")
				Tracks.prepare(motor, value)
				key.Motor = motor
				key.Part = motor.Part1
				key.Frame = frame
				key.SanitizeName = sanitize
				key.Channels = nil
				key.GraphCurves = nil
			end

			timeline:_restoreMotorBucket(motor, row.keys)
		end
	end

	for _, motor in Tracks.list(rig, true) do
		if not wanted[motor] and not Tracks.required(rig, motor.PropertyId) then
			Tracks.restoreValue(motor)
			motor.Part1:SetAttribute("Enabled", false)
		end
	end
end

function Tracks.write(sequence, rig, raw)
	local old = sequence:FindFirstChild("EclipseProperties")
	if old then
		old:Destroy()
	end

	if Camera.isRig(rig) or #Tracks.list(rig, true) > 0 then
		Chunks.write(sequence, "EclipseProperties", Document.pack(Tracks.snapshot(rig, raw, true)))
	end
end

function Tracks.read(sequence, rig, timeline, sanitize)
	local folder = sequence:FindFirstChild("EclipseProperties")
	local data = folder and Document.unpack(Chunks.read(folder)) or { version = 1, tracks = {} }
	local sourceScale = sequence:GetAttribute("EclipseAuthoredScale")
	if
		(rig:IsA("Model") and rig.Parent ~= game)
		and typeof(sourceScale) == "number"
		and sourceScale > 0
	then
		local ratio = rig:GetScale() / sourceScale
		if ratio ~= 1 then
			for _, row in data.tracks do
				if row.id == "Scale" then
					row.default *= ratio
					for _, key in row.keys or {} do
						if typeof(key.PropertyValue) == "number" then
							key.PropertyValue *= ratio
						end

						if key.C0 then
							key.C0 = CFrame.new(key.C0.Position * ratio) * key.C0.Rotation
							key.Position = key.C0.Position
						end
					end
				end
			end
		end
	end

	Tracks.restore(rig, data, timeline, sanitize)
end

return Tracks
