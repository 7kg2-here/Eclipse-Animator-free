--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Data = require("ProjectData")
local UI = require("UI")
local Tool = require("Tool")
local Notification = require("Notification")
local Provider = game:GetService("KeyframeSequenceProvider")
local Marketplace = game:GetService("MarketplaceService")
local Selection = game:GetService("Selection")
local Import = {}
local busy = false
local prompt

function Import.assetId(value)
	local text = tostring(value or ""):match("^%s*(.-)%s*$")
	local id = tonumber(text)
		or tonumber(text:match("rbxassetid://(%d+)"))
		or tonumber(text:match("/catalog/(%d+)"))
		or tonumber(text:match("/library/(%d+)"))
		or tonumber(text:match("/store/asset/(%d+)"))
		or tonumber(text:match("/animations/(%d+)"))
		or tonumber(text:match("[?&]id=(%d+)"))
	assert(id and id > 0 and id % 1 == 0 and id < 2 ^ 53, "Enter a valid Roblox asset ID or link.")
	return id
end

function Import.sortSequences(animations)
	local insertion = {}
	for i, animation in animations do
		insertion[animation] = i
	end

	local function modified(animation)
		local value = animation:GetAttribute("EclipseAnimationModified")
		return typeof(value) == "number" and value == value and value < math.huge and value or 0
	end

	table.sort(animations, function(a, b)
		local am, bm = modified(a), modified(b)
		return am > bm or am == bm and insertion[a] > insertion[b]
	end)
	return animations
end

function Import.selectedSequences(selected)
	local result, seen, visited = {}, {}, {}
	local slice = os.clock()

	local function visit(object)
		if visited[object] then
			return
		end

		visited[object] = true
		if os.clock() - slice >= 0.012 then
			task.wait()
			slice = os.clock()
		end

		if object:IsA("KeyframeSequence") then
			if not seen[object] then
				seen[object] = true
				table.insert(result, object)
			end

			return
		end

		for _, child in object:GetChildren() do
			visit(child)
		end

		if object:IsA("ObjectValue") and object.Name == "AnimSaves" and object.Value then
			visit(object.Value)
		end
	end

	for _, object in selected or Selection:Get() do
		visit(object)
	end

	Import.sortSequences(result)
	return result
end

function Import.load(id, emote)
	id = Import.assetId(id)
	local sequence
	local ok, err = pcall(function()
		local fetched, result =
			pcall(Provider.GetKeyframeSequenceAsync, Provider, "rbxassetid://" .. id)
		assert(
			fetched,
			"Could not read this animation ID. Use the underlying animation ID or insert the animation in Studio and import the selected KeyframeSequence. "
				.. tostring(result)
		)
		sequence = result

		assert(
			sequence and sequence:IsA("KeyframeSequence"),
			"Roblox did not return an editable keyframe sequence."
		)
		assert(#sequence:GetKeyframes() > 0, "This animation has no keyframes.")
		local found, info = pcall(Marketplace.GetProductInfoAsync, Marketplace, id)
		sequence.Name = found and info.Name or "Imported Animation " .. id
	end)

	if not ok then
		if sequence then
			sequence:Destroy()
		end

		error(err, 0)
	end

	return sequence
end

function Import.store(rig, sequence)
	assert(rig and rig.Parent, "The selected rig was removed while importing.")
	assert(sequence and sequence:IsA("KeyframeSequence"), "No keyframe sequence was returned.")
	local saves = Data.ensureAnimSaves(rig)
	local target = saves:IsA("ObjectValue") and saves.Value or saves
	assert(target, "This rig's animation folder is unavailable.")
	sequence.Name = Data.getUniqueExportName(saves, sequence.Name)

	sequence:SetAttribute("EclipseAnimationModified", DateTime.now().UnixTimestampMillis)
	sequence.Parent = target
	return sequence
end

function Import.run(rig, kind, id, done)
	if busy then
		return
	end

	if not rig or not rig.Parent then
		Notification.show("Import animation", "Select a rig first.")
		return
	end

	busy = true
	task.spawn(function()
		local sequence
		local ok, err = pcall(function()
			local plugin = assert(Data.getPlugin(), "Eclipse is not ready.")
			if kind == "Roblox" then
				local asset = plugin:PromptForExistingAssetIdAsync("Animation")
				if not asset or asset <= 0 then
					return
				end

				sequence = Import.load(asset, false)
			elseif kind == "FBX" then
				local humanoid = rig:FindFirstChildOfClass("Humanoid")
				sequence = plugin:ImportFbxAnimationAsync(
					rig,
					humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
				)
				if not sequence then
					return
				end
			else
				sequence = Import.load(id, true)
			end

			Import.store(rig, sequence)
		end)
		busy = false
		if not ok then
			if sequence then
				sequence:Destroy()
			end

			Notification.show("Couldn't import animation", (tostring(err):gsub("^.-:%d+: ", "")))
		elseif sequence then
			Notification.show(
				"Animation imported",
				sequence.Name .. " is in this rig's animation list."
			)
			if done then
				done(sequence)
			end
		end
	end)
end

function Import.open(rig, kind, done)
	if kind ~= "Avatar Shop" then
		Import.run(rig, kind, nil, done)
		return
	end

	if not rig then
		Notification.show("Import animation", "Select a rig first.")
		return
	end

	if prompt then
		prompt:close(true)
	end

	local window = Tool.new(
		{ ScreenGui = UI.EclipseGUI, Plugin = Data.getPlugin() },
		"EclipseEmoteImport",
		"AVATAR SHOP",
		Vector2.new(360, 134),
		false,

		function()
			prompt = nil
		end
	)
	prompt = window
	Tool.label(
		window.frame,
		"Label",
		"Emote ID or Avatar Shop link",
		UDim2.fromOffset(12, 38),
		UDim2.fromOffset(336, 18)
	)
	local field =
		Tool.field(window.frame, "Emote", "", UDim2.fromOffset(12, 60), UDim2.fromOffset(336, 26))

	local function submit()
		local ok, id = pcall(Import.assetId, field.Text)
		if not ok then
			field.PlaceholderText = "Enter an emote ID or link"
			field.Text = ""
			return
		end

		window:close()
		Import.run(rig, kind, id, done)
	end

	Tool.button(
		window.frame,
		"Import",
		"IMPORT",
		UDim2.fromOffset(236, 98),
		UDim2.fromOffset(112, 26),
		submit
	)
	field.FocusLost:Connect(function(enter)
		if enter then
			submit()
		end
	end)
end

return Import
