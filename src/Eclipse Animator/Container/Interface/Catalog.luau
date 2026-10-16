--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local Changes = game:GetService("ChangeHistoryService")
local Tool = require("Tool")
local Theme = require("Theme")
local History = require("History")
local Appearance = require("Appearance")
local RigPose = require("RigPose")
local Layout = require("Layout")
local Catalog = {}

local function clean(model)
	for _, item in model:GetDescendants() do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide = false
			item.Massless = true
		end
	end
end

function Catalog.fetchOutfits(userId, page, current)
	local url = string.format(
		"https://avatar.roproxy.com/v1/users/%d/outfits?page=%d&itemsPerPage=50",
		userId,
		page
	)
	local response
	for attempt = 1, 3 do
		if current and not current() then
			error("Outfit request cancelled", 0)
		end

		response = Http:RequestAsync({ Url = url, Method = "GET" })
		if response.Success then
			break
		end

		if response.StatusCode ~= 429 and response.StatusCode < 500 then
			error("Couldn't load outfits", 0)
		end

		if attempt == 3 then
			error(
				response.StatusCode == 429 and "Outfits are rate limited. Try again shortly."
					or "Outfits are unavailable. Try again shortly.",
				0
			)
		end

		task.wait(
			math.clamp(
				tonumber(response.Headers["Retry-After"] or response.Headers["retry-after"])
					or attempt * 2,
				1,
				10
			)
		)
	end

	response = Http:JSONDecode(response.Body)
	assert(type(response) == "table" and type(response.data) == "table", "Invalid outfit response")
	local outfits = {}
	for _, entry in response.data do
		if
			type(entry) == "table"
			and type(entry.id) == "number"
			and entry.id > 0
			and entry.isEditable == true
		then
			table.insert(outfits, { id = entry.id, name = tostring(entry.name or "Outfit") })
		end
	end

	return outfits,
		#response.data == 50 and (not tonumber(response.total) or page * 50 < response.total)
end

function Catalog.outfit(id, kind)
	local description = Players:GetHumanoidDescriptionFromOutfitIdAsync(id)
	local ok, model =
		pcall(Players.CreateHumanoidModelFromDescriptionAsync, Players, description, kind)
	description:Destroy()
	if not ok then
		error(model, 0)
	end

	clean(model)
	return model
end

function Catalog.attach(rig, asset)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "Select one rig")
	if asset:IsA("Accessory") then
		local handle = asset:FindFirstChild("Handle")
		assert(handle and handle:IsA("BasePart"), "This accessory has no handle")
		for _, part in asset:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = false
			end
		end

		humanoid:AddAccessory(asset)
		if not handle:FindFirstChild("AccessoryWeld") then
			local mount = handle:FindFirstChildOfClass("Attachment")
			local socket
			if mount then
				for _, item in rig:GetDescendants() do
					if
						item:IsA("Attachment")
						and item.Name == mount.Name
						and item.Parent:IsA("BasePart")
						and not item:FindFirstAncestorWhichIsA("Accessory")
					then
						socket = item
						break
					end
				end

				assert(socket, "This accessory does not fit the selected rig")
			end

			local body = socket and socket.Parent or rig:FindFirstChild("Head")
			assert(body and body:IsA("BasePart"), "This rig has no accessory mount")
			local weld = Instance.new("Weld")
			weld.Name = "AccessoryWeld"
			weld.Part0 = handle
			weld.Part1 = body
			weld.C0 = mount and mount.CFrame or asset.AttachmentPoint
			weld.C1 = socket and socket.CFrame or CFrame.new(0, 0.5, 0)
			handle.CFrame = body.CFrame * weld.C1 * weld.C0:Inverse()
			weld.Parent = handle
		end
	else
		local head = rig:FindFirstChild("Head")
		assert(head and head:IsA("BasePart"), "This rig has no head")
		asset.Name = "face"
		asset.Face = Enum.NormalId.Front
		asset.Parent = head
	end
end

function Catalog.init(options)
	local gui, frame, state = options.Gui, options.Frame, options.State
	local connections = {}
	local destroyed, busy, generation = false, false, 0
	local asset, preview, target, popup
	local tab = Tool.make("Frame", frame, "AccessoriesTab", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 78),
		Size = UDim2.fromOffset(464, 204),
		Visible = false,
	})
	local viewport = Tool.make("ViewportFrame", tab, "Preview", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(128, 166),
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
	})
	viewport:SetAttribute("ThemeBg", "Pnl")
	Tool.make("UICorner", viewport, "Corner", { CornerRadius = UDim.new(0, 3) })
	local world = Instance.new("WorldModel", viewport)
	local rigLabel = Tool.label(
		tab,
		"RigName",
		"Select a rig",
		UDim2.fromOffset(0, 174),
		UDim2.fromOffset(128, 30)
	)
	rigLabel.TextXAlignment = Enum.TextXAlignment.Center
	rigLabel.TextTruncate = Enum.TextTruncate.AtEnd
	Tool.label(
		tab,
		"Header",
		"ACCESSORY / FACE",
		UDim2.fromOffset(144, 0),
		UDim2.fromOffset(320, 18)
	)
	local input =
		Tool.field(tab, "AssetId", "", UDim2.fromOffset(144, 26), UDim2.fromOffset(230, 28))
	input.PlaceholderText = "Asset ID / URL"
	local loadButton, loadLabel =
		Tool.button(tab, "Load", "LOAD", UDim2.fromOffset(382, 26), UDim2.fromOffset(82, 28))
	local name =
		Tool.label(tab, "AssetName", "", UDim2.fromOffset(144, 64), UDim2.fromOffset(320, 40))
	local kind =
		Tool.label(tab, "AssetType", "", UDim2.fromOffset(144, 108), UDim2.fromOffset(320, 20))
	local status =
		Tool.label(tab, "Status", "", UDim2.fromOffset(144, 134), UDim2.fromOffset(320, 34))
	name.TextWrapped = true
	name.TextTruncate = Enum.TextTruncate.AtEnd
	status.TextWrapped = true
	local insert =
		Tool.button(tab, "Insert", "INSERT", UDim2.fromOffset(144, 174), UDim2.fromOffset(320, 30))

	local function connect(signal, callback)
		table.insert(connections, signal:Connect(callback))
	end

	local function resolve()
		return Appearance.resolve(Selection:Get(), state.Rig and state.Rig._selectedItems)
	end

	local function active()
		return not destroyed and gui.Enabled and tab.Visible
	end

	local function paint()
		loadLabel.Text = busy and "LOADING..." or "LOAD"
		Layout.enabled(loadButton, not busy)
		Layout.enabled(insert, not busy and target ~= nil and asset ~= nil and preview ~= nil)
	end

	local function show()
		world:ClearAllChildren()
		preview = nil
		local rig, multiple = resolve()
		target = not multiple and rig or nil
		rigLabel.Text = target and target.Name or "Select one rig"
		if target then
			local model
			local ok, err = pcall(function()
				model = Appearance.clone(target)
				clean(model)
				RigPose.assemble(model)
				model:PivotTo(CFrame.identity)
				model.Parent = world
				if asset then
					if asset:IsA("Decal") then
						for _, d in model.Head:GetChildren() do
							if d:IsA("Decal") and d.Face == Enum.NormalId.Front then
								d:Destroy()
							end
						end
					end

					Catalog.attach(model, asset:Clone())
				end

				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
					end
				end

				options.FitCamera(viewport, model)
			end)
			if ok then
				preview = model
			else
				if model then
					model:Destroy()
				end

				status.Text = "Couldn't preview this item on this rig."
				warn("Eclipse accessory preview: " .. tostring(err))
			end
		end

		paint()
	end

	local controller = {}

	function controller.load()
		if not active() then
			return
		end
		status.Text = "Accessory and face loading is temporarily down."
		require("Notification").show("TEMPORARILY DOWN", status.Text, 5)
	end

	function controller.insert()
		if not active() or busy or not asset or not preview or resolve() ~= target then
			return
		end

		local rig = target
		local item = asset:Clone()
		local previous = {}
		if item:IsA("Decal") then
			for _, d in rig.Head:GetChildren() do
				if d:IsA("Decal") and d.Face == Enum.NormalId.Front then
					table.insert(previous, d)
				end
			end
		end

		local inFile = false
		for _, r in state.getAllRigs() do
			if r == rig then
				inFile = true
				break
			end
		end

		local recording
		if not inFile then
			recording = Changes:TryBeginRecording("EclipseAccessory", "Insert accessory")
			if not recording then
				item:Destroy()
				return
			end
		end

		local function undo()
			item.Parent = nil
			for _, d in previous do
				d.Parent = rig.Head
			end

			state.currentProjectSaved = false
		end

		local function redo()
			for _, d in previous do
				d.Parent = nil
			end

			Catalog.attach(rig, item)
			state.currentProjectSaved = false
		end

		local ok, err = pcall(redo)
		if not ok then
			undo()
			item:Destroy()
			status.Text = "This item doesn't fit the selected rig."
			warn(tostring(err))
		end

		if recording then
			Changes:FinishRecording(
				recording,
				ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel
			)
		elseif ok then
			History.record(undo, redo, "Insert " .. item.Name)
		end

		if ok then
			status.Text = "Inserted " .. item.Name
			show()
		end
	end

	function controller.outfits()
		if popup then
			popup:close(true)
		end

		local window =
			Tool.new({ ScreenGui = gui }, "EclipseOutfits", "OUTFITS", Vector2.new(422, 488), false)
		popup = window
		local body = window.frame
		local user =
			Tool.field(body, "User", "", UDim2.fromOffset(16, 40), UDim2.fromOffset(282, 28))
		user.PlaceholderText = "Username / User ID"
		user.Text = frame.RigsTab.AvatarPanel.UserInput.Text
		if user.Text == "" then
			local id = game:GetService("StudioService"):GetUserId()
			if id > 0 then
				user.Text = tostring(id)
			end
		end

		local fetch, fetchText =
			Tool.button(body, "Load", "LOAD", UDim2.fromOffset(306, 40), UDim2.fromOffset(100, 28))
		local scroll = Tool.make("ScrollingFrame", body, "Outfits", {
			Position = UDim2.fromOffset(16, 80),
			Size = UDim2.fromOffset(390, 286),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
		})
		Tool.make("UIGridLayout", scroll, "Grid", {
			CellSize = UDim2.fromOffset(120, 138),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local more = Tool.button(
			body,
			"More",
			"LOAD MORE",
			UDim2.fromOffset(16, 374),
			UDim2.fromOffset(120, 26)
		)
		more.Visible = false
		local message =
			Tool.label(body, "Status", "", UDim2.fromOffset(146, 374), UDim2.fromOffset(260, 26))
		local r6 =
			Tool.button(body, "R6", "R6", UDim2.fromOffset(16, 408), UDim2.fromOffset(62, 28))
		local r15 =
			Tool.button(body, "R15", "R15", UDim2.fromOffset(86, 408), UDim2.fromOffset(62, 28))
		local chosen =
			Tool.label(body, "Selected", "", UDim2.fromOffset(158, 408), UDim2.fromOffset(248, 28))
		chosen.TextTruncate = Enum.TextTruncate.AtEnd
		local add, addText = Tool.button(
			body,
			"Insert",
			"INSERT OUTFIT",
			UDim2.fromOffset(16, 448),
			UDim2.fromOffset(390, 28)
		)
		local mode, selected, page, uid, token, loading, adding =
			"R15", nil, 0, nil, 0, false, false
		local seen, buttons = {}, {}

		local function refresh()
			options.SetButtonSelected(r6, mode == "R6")
			options.SetButtonSelected(r15, mode == "R15")
			Layout.enabled(add, selected ~= nil and not loading and not adding)
			Layout.enabled(fetch, not loading and not adding)
			Layout.enabled(more, not loading and not adding)
			Layout.enabled(r6, not adding)
			Layout.enabled(r15, not adding)
			fetchText.Text = loading and "LOADING..." or "LOAD"
			addText.Text = adding and "LOADING..." or "INSERT OUTFIT"
		end

		local function fetchOutfitsPage(nextPage)
			if loading or adding then
				return
			end

			token += 1
			local request = token
			loading = true
			message.Text = ""
			refresh()
			task.spawn(function()
				local ok, err = pcall(function()
					local id = uid
					if not nextPage then
						local text = user.Text:match("^%s*(.-)%s*$"):gsub("^@", "")
						assert(text ~= "", "Enter a username or user ID")
						id = tonumber(text) or Players:GetUserIdFromNameAsync(text)
						assert(id > 0 and id % 1 == 0, "Invalid user ID")
					end

					local nextIndex = nextPage and page + 1 or 1
					local entries, hasMore = (options.FetchOutfits or Catalog.fetchOutfits)(
						id,
						nextIndex,

						function()
							return not window.closed and token == request
						end
					)
					if window.closed or token ~= request then
						return
					end

					if not nextPage then
						for _, button in buttons do
							button:Destroy()
						end

						buttons = {}
						seen = {}
						selected = nil
						chosen.Text = ""
						scroll.CanvasPosition = Vector2.zero
					end

					uid, page = id, nextIndex
					for _, entry in entries do
						if not seen[entry.id] then
							seen[entry.id] = true
							local button, label = Tool.button(
								scroll,
								"Outfit_" .. string.format("%.0f", entry.id),
								entry.name,
								UDim2.new(),
								UDim2.fromOffset(120, 138)
							)
							button.LayoutOrder = #buttons + 1
							label.Position = UDim2.fromOffset(4, 110)
							label.Size = UDim2.fromOffset(112, 24)
							label.TextSize = 11
							label.TextTruncate = Enum.TextTruncate.AtEnd
							Tool.make("ImageLabel", button, "Thumbnail", {
								BackgroundTransparency = 1,
								Position = UDim2.fromOffset(7, 4),
								Size = UDim2.fromOffset(106, 106),
								Image = "rbxthumb://type=Outfit&id="
									.. string.format("%.0f", entry.id)
									.. "&w=150&h=150",
							})
							button.Activated:Connect(function()
								if adding then
									return
								end

								selected = entry
								chosen.Text = entry.name
								for _, b in buttons do
									options.SetButtonSelected(b, b == button)
								end

								refresh()
							end)
							table.insert(buttons, button)
						end
					end

					more.Visible = hasMore
					if #buttons == 0 then
						message.Text = hasMore and "No saved outfits on this page."
							or "No saved outfits found."
					end

					Theme.applyTree(body)
				end)
				if not window.closed and token == request then
					loading = false
					if not ok then
						message.Text = tostring(err):find("rate limited", 1, true)
								and "Rate limited. Try again shortly."
							or "Couldn't load outfits. Try again."
						warn(tostring(err))
					end

					refresh()
				end
			end)
		end

		fetch.Activated:Connect(function()
			fetchOutfitsPage(false)
		end)
		user:GetPropertyChangedSignal("Text"):Connect(function()
			if adding then
				return
			end

			token += 1
			loading = false
			uid = nil
			page = 0
			selected = nil
			chosen.Text = ""
			more.Visible = false
			for _, button in buttons do
				button:Destroy()
			end

			buttons = {}
			seen = {}
			refresh()
		end)
		user.FocusLost:Connect(function(enter)
			if enter then
				fetchOutfitsPage(false)
			end
		end)
		more.Activated:Connect(function()
			fetchOutfitsPage(true)
		end)
		r6.Activated:Connect(function()
			if not adding then
				mode = "R6"
				refresh()
			end
		end)
		r15.Activated:Connect(function()
			if not adding then
				mode = "R15"
				refresh()
			end
		end)
		add.Activated:Connect(function()
			if adding or loading or not selected then
				return
			end

			adding = true
			refresh()
			local entry, kind = selected, Enum.HumanoidRigType[mode]
			task.spawn(function()
				local ok, model = pcall(options.BuildOutfit or Catalog.outfit, entry.id, kind)
				if window.closed or destroyed then
					if ok then
						model:Destroy()
					end

					return
				end

				adding = false
				if ok then
					model.Name = entry.name
					options.PlaceModel(model, "Eclipse Insert Outfit")
					window:close()
				else
					message.Text = "Couldn't insert this outfit. Try again."
					warn(tostring(model))
					refresh()
				end
			end)
		end)
		refresh()
		Theme.applyTree(body)
		if user.Text ~= "" then
			fetchOutfitsPage(false)
		end
	end

	function controller.destroy()
		if destroyed then
			return
		end

		destroyed = true
		generation += 1
		for _, connection in connections do
			connection:Disconnect()
		end

		if popup then
			popup:close(true)
		end

		if asset then
			asset:Destroy()
		end

		world:ClearAllChildren()
	end

	connect(loadButton.Activated, controller.load)
	connect(input.FocusLost, function(enter)
		if enter then
			controller.load()
		end
	end)
	connect(input:GetPropertyChangedSignal("Text"), function()
		generation += 1
		busy = false
		if asset then
			asset:Destroy()
			asset = nil
		end

		name.Text = ""
		kind.Text = ""
		status.Text = ""
		paint()
	end)
	connect(insert.Activated, controller.insert)
	connect(frame.RigsTab.AvatarPanel.Outfits.Activated, controller.outfits)
	connect(Selection.SelectionChanged, function()
		if active() then
			generation += 1
			busy = false
			status.Text = ""
			show()
		end
	end)
	local elapsed = 0
	connect(game:GetService("RunService").Heartbeat, function(dt)
		if not active() then
			return
		end

		elapsed += dt
		if elapsed < 0.2 then
			return
		end

		elapsed = 0
		if resolve() ~= target then
			generation += 1
			busy = false
			status.Text = ""
			show()
		end
	end)

	local function visibility()
		generation += 1
		busy = false
		if active() then
			show()
		end

		if not gui.Enabled and popup then
			popup:close(true)
		end
	end

	connect(tab:GetPropertyChangedSignal("Visible"), visibility)
	connect(gui:GetPropertyChangedSignal("Enabled"), visibility)
	connect(options.Owner.Destroying, controller.destroy)
	connect(tab.Destroying, controller.destroy)
	Theme.applyTree(tab)
	paint()
	return controller
end

return Catalog
