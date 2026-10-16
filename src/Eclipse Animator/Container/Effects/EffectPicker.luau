--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Data = require("ClipboardRows")
local VFX = require("NativeVFX")
local Theme = require("Theme")
local Picker = {}

local function native(item)
	return item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") or item:IsA("Light")
end

function Picker.selection(root, entries, action)
	local model = { root = root, nodes = {}, selected = {}, actions = {} }
	local continuous = action == "Enable" or action == "Disable"
	for _, row in Data.copy(entries) do
		if row.Action == "Enable" or row.Action == "Disable" then
			continuous = true
		end
	end

	local function walk(item, parent, depth)
		if item:GetAttribute("EclipseVFXOutput") == true then
			return
		end

		local special, atomic = VFX.classify(item)
		local node = {
			instance = item,
			parent = parent,
			depth = depth,
			children = {},
			effect = (action == nil or action == "Emit") and special or native(item),
			compound = atomic and not native(item),
			expanded = true,
		}
		if
			item ~= root
			and not node.effect
			and not (
				item:IsA("Model")
				or item:IsA("Folder")
				or item:IsA("BasePart")
				or item:IsA("Attachment")
			)
		then
			return
		end

		table.insert(model.nodes, node)
		if parent then
			table.insert(parent.children, node)
		end

		if not atomic or continuous then
			for _, child in item:GetChildren() do
				walk(child, node, depth + 1)
			end
		end

		return node
	end

	model.tree = walk(root, nil, 0)

	function model:contains(node)
		return node.instance == root or node.instance:IsDescendantOf(root)
	end

	function model:status(node)
		local total, chosen = 0, 0

		local function count(n)
			if not self:contains(n) then
				return
			end

			if n.effect then
				total += 1
				if self.selected[n.instance] then
					chosen += 1
				end
			end

			for _, child in n.children do
				count(child)
			end
		end

		count(node)
		return chosen, total
	end

	function model:set(node, value)
		if not self:contains(node) then
			return
		end

		if node.effect then
			self.selected[node.instance] = value or nil
		end

		for _, child in node.children do
			self:set(child, value)
		end
	end

	function model:toggle(node)
		local chosen, total = self:status(node)
		self:set(node, chosen < total)
	end

	function model:export()
		local rows = {}
		for _, node in self.nodes do
			if node.effect and self.selected[node.instance] and self:contains(node) then
				local path = Data.path(root, node.instance)
				if path then
					table.insert(rows, {
						Mode = "Exact",
						Path = path,
						Action = action or self.actions[node.instance],
					})
				end
			end
		end

		return rows
	end

	for _, entry in Data.copy(entries) do
		local target = Data.resolve(root, entry.Path)
		if target then
			for _, node in model.nodes do
				local item = node.instance
				if
					node.effect
					and (
						item == target
						or entry.Mode == "All" and item:IsDescendantOf(target)
						or (action == "Enable" or action == "Disable") and not native(target) and item:IsDescendantOf(
							target
						)
						or entry.Mode == "Selected" and item.Parent == target and native(item)
					)
				then
					model.selected[item] = true
					model.actions[item] = entry.Action
				end
			end
		end
	end

	return model
end

function Picker.open(options)
	local Chrome = require("Chrome")
	local Motion = require("Motion")
	local FX = require("WindowFX")
	local Surface = require("Surface")
	local owner = options.window
	local model = Picker.selection(options.root, options.entries, options.action)
	if #Data.copy(options.entries) == 0 then
		model:set(model.tree, true)
	end

	local frame = Instance.new("Frame")
	frame.Name = "EmitPicker"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(440, 460)
	frame.Position = owner.Position
	frame.Active = true
	frame.ZIndex = 200
	frame.Visible = false
	frame.Parent = owner.Parent
	Surface.fill(frame)
	local outline = Instance.new("UIStroke")
	outline.Color = Theme.panelOutlineDefault()
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline:SetAttribute("ThemeStrk", "Strk")
	outline.Parent = frame
	local header, _, drag = Chrome.header(frame, "VFX TARGETS", 201)
	local view = { frame = frame, model = model, closed = false, connections = {} }
	local previousVisible = owner.Visible
	owner.Visible = false

	local function fit()
		if not frame.Parent or view.closed then
			return
		end

		local parent = Motion.coordinateParent(frame)
		if not parent then
			return
		end

		local viewport = parent.AbsoluteSize / Motion.scale(frame)
		local height = math.clamp(viewport.Y - 16, 160, 460)
		local width = math.clamp(viewport.X - 16, 240, 440)
		frame.Size = UDim2.fromOffset(width, height)
		frame.Position =
			Motion.inside(frame.Position, Vector2.new(width, height), viewport, frame.AnchorPoint)
	end

	local function dispose()
		for _, connection in view.connections do
			connection:Disconnect()
		end

		table.clear(view.connections)
		FX.clear(frame)
		frame:Destroy()
		if owner.Parent then
			owner.Visible = previousVisible
		end

		if options.closed then
			options.closed()
		end
	end

	local function close(immediate)
		if view.closed then
			if immediate and frame.Parent then
				dispose()
			end

			return
		end

		view.closed = true
		if immediate then
			dispose()
		else
			FX.shrink(frame, dispose)
		end
	end

	view.close = close
	frame.Destroying:Once(function()
		FX.clear(frame)
		for _, connection in view.connections do
			connection:Disconnect()
		end

		table.clear(view.connections)
		if not view.closed then
			view.closed = true
			if owner.Parent then
				owner.Visible = previousVisible
			end

			if options.closed then
				options.closed()
			end
		end
	end)
	table.insert(
		view.connections,
		owner.Destroying:Once(function()
			close(true)
		end)
	)
	local parent = Motion.coordinateParent(frame)
	if parent then
		table.insert(view.connections, parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
	end

	Chrome.close(header, function()
		close()
	end, 205)
	Chrome.bindDrag(frame, drag, {
		inside = true,
		threshold = 3,
		disabled = function()
			return view.closed
		end,
	})
	local list = Instance.new("ScrollingFrame")
	list.Name = "Hierarchy"
	list.Position = UDim2.fromOffset(10, 38)
	list.Size = UDim2.new(1, -20, 1, -88)
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 4
	list.BorderSizePixel = 0
	list.BackgroundColor3 = Theme.get("Pnl", Color3.fromRGB(20, 16, 26))
	list:SetAttribute("ThemeBg", "Pnl")
	list.ZIndex = 202
	list.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = list

	local function button(parent, name, text, pos, size, fn)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Position = pos
		b.Size = size
		b.Text = ""
		b.BorderSizePixel = 0
		b.AutoButtonColor = true
		b.ZIndex = 205
		b.BackgroundColor3 = Theme.get("TopBtn", Color3.fromRGB(49, 43, 62))
		b.Parent = parent
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 5)
		corner.Parent = b
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(6, 0)
		label.Size = UDim2.new(1, -12, 1, 0)
		label.Text = text
		label.FontFace = Chrome.FONT
		label.TextSize = 12
		label.TextColor3 = Theme.get("Txt", Color3.fromRGB(234, 229, 245))
		label.ZIndex = 206
		label.Parent = b
		b.Activated:Connect(fn)
		return b, label
	end

	local function line(x, y, width, height)
		local l = Instance.new("Frame")
		l.Name = "Branch"
		l.Position = UDim2.fromOffset(x, y)
		l.Size = UDim2.fromOffset(width, height)
		l.BorderSizePixel = 0
		l.BackgroundColor3 = Theme.get("Txt", Color3.fromRGB(180, 168, 199))
		l.BackgroundTransparency = 0.65
		l.ZIndex = 203
		l.Parent = list
	end

	local paint

	function view:toggle(node)
		if not self.closed then
			model:toggle(node)
			paint()
		end
	end

	paint = function()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		local visible, indices = {}, {}
		for _, node in model.nodes do
			local show = true
			local ancestor = node.parent
			while ancestor do
				if not ancestor.expanded then
					show = false
					break
				end

				ancestor = ancestor.parent
			end

			if show then
				table.insert(visible, node)
				indices[node] = #visible
			end
		end

		for index, node in visible do
			local y = (index - 1) * 34 + 8
			local indent = math.min(node.depth, 10) * 20
			if node.parent and indices[node.parent] then
				local x = 18 + math.min(node.parent.depth, 10) * 20
				local py = (indices[node.parent] - 1) * 34 + 25
				line(x, py, 1, y + 17 - py)
				line(x, y + 17, math.max(1, indent + 10 - x), 1)
			end

			local chosen, total = model:status(node)
			local row, title = button(
				list,
				"Target" .. index,
				node.instance.Name,
				UDim2.fromOffset(48 + indent, y),
				UDim2.new(1, -60 - indent, 0, 32),

				function()
					view:toggle(node)
				end
			)
			row.BackgroundTransparency = chosen > 0 and 0.7 or 1
			row.Interactable = total > 0
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.TextTransparency = total > 0 and 0 or 0.5
			title.Position = UDim2.fromOffset(8, 0)
			title.Size = UDim2.new(1, -72, 1, 0)
			local kind = Instance.new("TextLabel")
			kind.Name = "Kind"
			kind.BackgroundTransparency = 1
			kind.Position = UDim2.new(1, -64, 0, 0)
			kind.Size = UDim2.fromOffset(56, 32)
			kind.Text = node.compound and "effect"
				or node.instance:IsA("Attachment") and "attach"
				or node.instance:IsA("ParticleEmitter") and "particles"
				or #node.children > 0 and "group"
				or node.instance.ClassName:lower()
			kind.TextSize = 9
			kind.FontFace = Chrome.FONT
			kind.TextXAlignment = Enum.TextXAlignment.Right
			kind.TextColor3 = title.TextColor3
			kind.TextTransparency = 0.45
			kind.ZIndex = 206
			kind.Parent = row
			if #node.children > 0 then
				local expand, label = button(
					list,
					"Expand" .. index,
					node.expanded and "⌄" or "›",
					UDim2.fromOffset(10 + indent, y + 6),
					UDim2.fromOffset(16, 20),

					function()
						node.expanded = not node.expanded
						paint()
					end
				)
				expand.BackgroundTransparency = 1
				label.Position = UDim2.new()
				label.Size = UDim2.fromScale(1, 1)
				label.TextSize = 18
			end

			local check, label = button(
				list,
				"Check" .. index,
				chosen == 0 and "" or chosen == total and "✓" or "−",
				UDim2.fromOffset(29 + indent, y + 8),
				UDim2.fromOffset(17, 17),

				function()
					view:toggle(node)
				end
			)
			label.Position = UDim2.new()
			label.Size = UDim2.fromScale(1, 1)
			label.TextSize = 13
			check.Interactable = total > 0
			check.BackgroundTransparency = chosen > 0 and 0.15 or 1
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Color = title.TextColor3
			stroke.Transparency = total > 0 and 0.5 or 0.85
			stroke.Parent = check
		end

		local depth = 0
		for _, node in visible do
			depth = math.max(depth, math.min(node.depth, 10))
		end

		list.CanvasSize = UDim2.fromOffset(math.max(0, depth * 20 + 310), #visible * 34 + 16)
		Theme.applyTree(frame)
	end

	view.apply = function()
		if view.closed then
			return
		end

		options.apply(model:export())
		close()
	end

	local footerSize = UDim2.new(0.25, -9.5, 0, 28)
	button(frame, "All", "All", UDim2.new(0, 10, 1, -38), footerSize, function()
		model:set(model.tree, true)
		paint()
	end)
	button(frame, "None", "None", UDim2.new(0.25, 6.5, 1, -38), footerSize, function()
		model:set(model.tree, false)
		paint()
	end)
	button(frame, "Cancel", "Cancel", UDim2.new(0.5, 3, 1, -38), footerSize, function()
		close()
	end)
	button(frame, "Apply", "Done", UDim2.new(0.75, -0.5, 1, -38), footerSize, view.apply)
	paint()
	fit()
	task.defer(function()
		if not view.closed then
			fit()
			frame.Visible = true
			FX.pop(frame)
		end
	end)
	return view
end

return Picker
