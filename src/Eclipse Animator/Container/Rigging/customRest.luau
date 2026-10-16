--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Auto = {}

function Auto.limbKind(owner)
	local name = owner.Part1.Name:lower():gsub("[^%a]", "")
	if name:find("foot", 1, true) or name:find("ankle", 1, true) then
		return "Leg"
	end

	return "Arm"
end

function Auto.rest(owner)
	local result = {}
	for i = 1, 3 do
		local cf = owner:GetAttribute("EclipseAutoIKRest" .. i)
		if typeof(cf) ~= "CFrame" then
			return {}
		end

		result[i] = cf
	end

	return result
end

function Auto.restoreRest(owner, values)
	values = values or {}
	for i = 1, 3 do
		local cf = values[i]
		assert(cf == nil or typeof(cf) == "CFrame", "Invalid custom IK calibration")
		if cf then
			for _, v in { cf:GetComponents() } do
				assert(v == v and math.abs(v) < 1e9, "Invalid custom IK calibration")
			end
		end
	end

	for i = 1, 3 do
		owner:SetAttribute("EclipseAutoIKRest" .. i, values[i])
	end
end

function Auto.isJoint(motor)
	return typeof(motor) == "Instance"
			and motor:IsA("Motor6D")
			and motor.Part0 ~= nil
			and motor.Part1 ~= nil
		or typeof(motor) == "table"
			and rawget(motor, "_bone") ~= nil
			and motor.Parent ~= nil
			and not require("ArmatureRuntime").isDriven(motor.Bone)
end

function Auto.index(motors)
	local parents = {}
	for _, motor in motors do
		if Auto.isJoint(motor) then
			if parents[motor.Part1] ~= nil then
				parents[motor.Part1] = false
			else
				parents[motor.Part1] = motor
			end
		end
	end

	return parents
end

function Auto.chain(rig, endpoint, motors, parents)
	if not Auto.isJoint(endpoint) then
		return nil, "Select a Motor6D joint or a bone at the end of a limb"
	end

	parents = parents or Auto.index(motors)

	local function parentOf(motor)
		return typeof(motor) == "table" and motor.RealPart0 or motor.Part0
	end

	local lower = parents[parentOf(endpoint)]
	local upper = lower and parents[parentOf(lower)]
	if not upper or upper == lower or upper == endpoint or lower == endpoint then
		return nil, "The selected end joint needs two connected parent joints"
	end

	local boneChain = typeof(endpoint) == "table"
	for _, motor in { upper, lower, endpoint } do
		if (typeof(motor) == "table") ~= boneChain then
			return nil, "Choose three joints of the same type"
		end

		if
			not motor.Part1:IsDescendantOf(rig)
			or (typeof(motor) == "Instance" and not motor:IsDescendantOf(rig))
		then
			return nil, "All joints must belong to the selected rig"
		end
	end

	local a = upper.Part0.CFrame * upper.C0
	local b = lower.Part0.CFrame * lower.C0
	local c = endpoint.Part0.CFrame * endpoint.C0
	if
		(b.Position - a.Position).Magnitude < 0.0001
		or (c.Position - b.Position).Magnitude < 0.0001
	then
		return nil, "The chain has a zero-length segment"
	end

	return { upper, lower, endpoint }
end

function Auto.setup(selectedMotor, selectedRig)
	local State = require("State")
	local timeline = State.Timeline
	if
		not timeline
		or require("BlenderEdit").blocked()
		or timeline:IsExportLocked()
		or State.PhysicsSimulating
	then
		return
	end

	local motor, rig = selectedMotor, selectedRig
	if not motor then
		motor, rig = require("IKPanel").selection()
	end

	local Notice = require("Notification")
	if not motor or not rig then
		Notice.show("AUTO IK", "Select the end joint of the limb in the timeline")
		return
	end

	if State.getAllRigs and not table.find(State.getAllRigs(), rig) then
		Notice.show("AUTO IK", "This rig is no longer in the active animation.", 4)
		return
	end

	local IK = require("LimbIK")
	local entry = IK.getRig(rig)
	if entry.owners[motor] then
		Notice.show("AUTO IK", "This joint already has IK controls. Use its FK / IK toggle.")
		return
	end

	local chain, message = Auto.chain(rig, motor, entry.motors)
	if not chain then
		Notice.show("AUTO IK", message)
		return
	end

	for _, member in chain do
		if entry.members[member] then
			Notice.show("AUTO IK", "This chain overlaps another IK limb")
			return
		end
	end

	local previous = motor:GetAttribute("EclipseAutoIK")
	local Controls = require("R6Controls")
	local created = {}
	local previousRest, setupRest = {}, {}
	for i, member in chain do
		previousRest[i] = motor:GetAttribute("EclipseAutoIKRest" .. i)
		setupRest[i] = member.C0
	end

	local function refresh()
		IK.invalidate(rig)
		require("Project").refreshTimelineAfterStructureChange()
		State.currentProjectSaved = false
	end

	local function apply()
		motor:SetAttribute("EclipseAutoIK", true)
		for i, cf in setupRest do
			motor:SetAttribute("EclipseAutoIKRest" .. i, cf)
		end

		IK.invalidate(rig)
		local found = assert(IK.chain(rig, motor), "Custom IK chain could not be registered")
		local before = {}
		for _, child in motor.Part1:GetChildren() do
			before[child] = true
		end

		local ok, why = pcall(IK.prepare, found)
		created = {}
		for _, child in motor.Part1:GetChildren() do
			if not before[child] and Controls.isControl(child) then
				table.insert(created, child)
			end
		end

		assert(ok, why)
		refresh()
	end

	local function undo()
		motor:SetAttribute("EclipseAutoIK", previous)
		for i = 1, 3 do
			motor:SetAttribute("EclipseAutoIKRest" .. i, previousRest[i])
		end

		for _, child in created do
			child:Destroy()
		end

		refresh()
	end

	local ok, why = pcall(apply)
	if not ok then
		undo()
		Notice.show("AUTO IK", tostring(why))
		return
	end

	require("History").record(undo, apply, "Set up custom IK")
	return motor, rig
end

function Auto.candidates(rig, motors, entry)
	local result, parents = {}, Auto.index(motors)
	for _, motor in motors do
		local registered = entry.owners[motor]
		local chain
		if registered then
			if registered.kind ~= "Torso" then
				chain = registered.motors
			end
		else
			chain = Auto.chain(rig, motor, motors, parents)
		end

		if chain then
			local overlap = false
			for _, member in chain do
				if entry.members[member] and entry.members[member] ~= entry.owners[motor] then
					overlap = true
				end
			end

			if not overlap then
				local names = {}
				for _, member in chain do
					table.insert(names, member.Part1.Name)
				end

				local path = motor:GetFullName()
				local prefix = rig:GetFullName() .. "."
				if path:sub(1, #prefix) == prefix then
					path = path:sub(#prefix + 1)
				end

				table.insert(result, {
					motor = motor,
					chain = chain,
					name = motor.Part1.Name,
					path = path,
					search = (path .. " " .. table.concat(names, " ")):lower(),
				})
			end
		end
	end

	table.sort(result, function(a, b)
		if a.name == b.name then
			return a.path < b.path
		end

		return a.name:lower() < b.name:lower()
	end)
	return result
end

function Auto.pick(candidates, selected)
	local exact, related = {}, {}

	local function matches(motor, object)
		return object == motor
			or object == motor.Part1
			or typeof(motor) == "table" and object == motor.Bone
	end

	for _, item in candidates do
		for _, object in selected do
			if matches(item.motor, object) then
				exact[item.motor] = item
			end

			for _, member in item.chain do
				if matches(member, object) then
					related[item.motor] = item
				end
			end
		end
	end

	local pool = next(exact) and exact or related
	local choice, count = nil, 0
	for _, item in pool do
		choice = item
		count += 1
	end

	return count == 1 and choice or nil, count
end

local refs, host
local connections = {}

function Auto.close()
	if host then
		local old = host
		host = nil
		old:close(true)
	end
end

function Auto.destroy()
	Auto.close()
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)
end

function Auto.open()
	if host or not refs or not refs.Active() then
		return
	end

	local State = refs.State
	local timeline = State.Timeline
	local rig = require("SelectedRig").resolve(State)
	local Notice = require("Notification")
	if not rig or not timeline then
		Notice.show("AUTO IK", "Add a rig first.", 4)
		return
	end

	local Tool = require("Tool")
	local IK = require("LimbIK")
	local session
	session = Tool.new(
		refs,
		"EclipseAutoIK",
		"AUTO IK · " .. rig.Name,
		Vector2.new(360, 152),
		false,

		function()
			if host == session then
				host = nil
			end
		end
	)
	host = session
	local frame = session.frame
	local guide = Tool.label(
		frame,
		"Guide",
		"Choose a limb",
		UDim2.fromOffset(14, 34),
		UDim2.fromOffset(232, 22)
	)
	guide.TextSize = 14
	local search =
		Tool.field(frame, "Search", "", UDim2.fromOffset(14, 62), UDim2.fromOffset(332, 28))
	search.PlaceholderText = "Find a limb..."
	local list = Tool.make("ScrollingFrame", frame, "Endpoints", {
		Position = UDim2.fromOffset(14, 62),
		Size = UDim2.fromOffset(332, 32),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
	})
	local selected, candidates, rows = nil, {}, {}
	local createButton, createLabel
	local refresh, draw, choose
	local lastMotor, lastRig, lastObjects = nil, nil, {}

	local function alive()
		return host == session
			and not session.closed
			and State.Timeline == timeline
			and refs.Active()
			and table.find(State.getAllRigs(), rig) ~= nil
	end

	local function show()
		local item
		for _, v in candidates do
			if v.motor == selected then
				item = v
				break
			end
		end

		if item then
			for _, member in item.chain do
				if not Auto.isJoint(member) or not member.Part1:IsDescendantOf(rig) then
					selected = nil
					item = nil
					break
				end
			end
		end

		for motor, row in rows do
			row.outline.Enabled = motor == selected
			row.label:SetAttribute("AutoIKSelected", motor == selected)
		end

		local configured = item and IK.chain(rig, selected)
		local enabled = configured and IK.isEnabled(selected, timeline:GetState().CurrentTime or 0)
		local ready = item ~= nil
			and not enabled
			and not State.PhysicsSimulating
			and not timeline:IsExportLocked()
			and not require("BlenderEdit").blocked()
		createButton.Active = ready
		createButton:SetAttribute("Ready", ready)
		createLabel.Text = not item and "SELECT A LIMB"
			or enabled and "IK ENABLED"
			or configured and "ENABLE IK"
			or "CREATE IK"
	end

	draw = function()
		if not alive() then
			return
		end

		for _, child in list:GetChildren() do
			child:Destroy()
		end

		table.clear(rows)
		local query = search.Text:lower():match("^%s*(.-)%s*$")
		local visible, names = {}, {}
		for _, item in candidates do
			names[item.name] = (names[item.name] or 0) + 1
			if query == "" or item.search:find(query, 1, true) then
				table.insert(visible, item)
			end
		end

		local selectedVisible = false
		for _, item in visible do
			if item.motor == selected then
				selectedVisible = true
			end
		end

		if not selectedVisible then
			selected = nil
		end

		for i, item in visible do
			local title = names[item.name] > 1 and item.path or item.name
			local button, text = Tool.button(
				list,
				"Endpoint" .. i,
				title,
				UDim2.fromOffset(0, (i - 1) * 32),
				UDim2.new(1, -6, 0, 28),

				function()
					if not alive() then
						return
					end

					selected = item.motor
					show()
				end
			)
			text.Position = UDim2.fromOffset(8, 0)
			text.Size = UDim2.new(1, -16, 1, 0)
			text.TextXAlignment = Enum.TextXAlignment.Left
			text.TextWrapped = false
			text.TextTruncate = Enum.TextTruncate.AtEnd
			local outline = Tool.make(
				"UIStroke",
				button,
				"Selection",
				{ Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
			)
			outline:SetAttribute("ThemeStrk", "Strk")
			rows[item.motor] = { label = text, outline = outline }
		end

		search.Parent.Visible = #candidates > 6
		local top = #candidates > 6 and 98 or 62
		local height = math.clamp(#visible * 32, 32, 192)
		list.Position = UDim2.fromOffset(14, top)
		list.Size = UDim2.fromOffset(332, height)
		list.CanvasSize = UDim2.fromOffset(0, #visible * 32)
		createButton.Position = UDim2.fromOffset(14, top + height + 10)
		createButton.Visible = #visible > 0
		frame.Size =
			UDim2.fromOffset(360, math.max(152, top + height + (#visible > 0 and 52 or 14)))
		if #visible == 0 then
			Tool.label(
				list,
				"Empty",
				#candidates == 0 and "No supported limbs in this rig." or "No matching limbs.",
				UDim2.fromOffset(4, 2),
				UDim2.new(1, -10, 0, 28)
			)
		end

		show()
		require("Theme").applyTree(frame)
	end

	local function selection()
		local motor, owner = require("IKPanel").selection()
		return motor, owner, game:GetService("Selection"):Get()
	end

	choose = function(motor, owner, objects, preferTimeline)
		lastMotor, lastRig, lastObjects = motor, owner, table.clone(objects)
		local picked
		if preferTimeline then
			picked = Auto.pick(candidates, owner == rig and motor and { motor } or {})
		else
			local count
			picked, count = Auto.pick(candidates, objects)
			if count == 0 then
				picked = Auto.pick(candidates, owner == rig and motor and { motor } or {})
			end
		end

		selected = picked and picked.motor or nil
		search.Text = ""
		draw()
		if selected then
			for i, item in candidates do
				if item.motor == selected then
					list.CanvasPosition = Vector2.new(0, math.max(0, (i - 2) * 32))
					break
				end
			end
		end
	end

	refresh = function()
		if not alive() then
			Auto.close()
			return
		end

		local motors = require("Parenting").collectMotors(rig)
		candidates = Auto.candidates(rig, motors, IK.getRig(rig))
		if #candidates <= 6 then
			search.Text = ""
		end

		local found = false
		for _, v in candidates do
			if v.motor == selected then
				found = true
			end
		end

		if not found then
			selected = nil
		end

		draw()
	end

	Tool.button(
		frame,
		"Refresh",
		"REFRESH",
		UDim2.fromOffset(264, 34),
		UDim2.fromOffset(82, 22),
		refresh
	)
	createButton, createLabel = Tool.button(
		frame,
		"Create",
		"SELECT A LIMB",
		UDim2.fromOffset(14, 104),
		UDim2.fromOffset(332, 30),

		function()
			if not alive() then
				Auto.close()
				return
			end

			if
				not selected
				or State.PhysicsSimulating
				or timeline:IsExportLocked()
				or require("BlenderEdit").blocked()
			then
				return
			end

			local previous
			for _, v in candidates do
				if v.motor == selected then
					previous = v
					break
				end
			end

			local owner = selected
			refresh()
			local current
			for _, v in candidates do
				if v.motor == owner then
					current = v
					break
				end
			end

			local same = current and previous and #current.chain == #previous.chain
			if same then
				for i, member in previous.chain do
					if current.chain[i] ~= member then
						same = false
						break
					end
				end
			end

			if not same then
				selected = nil
				show()
				Notice.show("AUTO IK", "The rig changed. Select the limb again.", 3)
				return
			end

			if not IK.chain(rig, owner) then
				local created = Auto.setup(owner, rig)
				if not created then
					return
				end
			end

			if not IK.isEnabled(owner, timeline:GetState().CurrentTime or 0) then
				timeline:SwitchIKAtCurrentTime(owner, rig)
			end

			refresh()
		end
	)
	createButton:SetAttribute("Primary", true)
	table.insert(session.connections, search:GetPropertyChangedSignal("Text"):Connect(draw))
	local elapsed = 0
	table.insert(
		session.connections,
		game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.2 then
				return
			end

			elapsed = 0
			if not alive() then
				Auto.close()
				return
			end

			local motor, owner, objects = selection()
			local changed = #objects ~= #lastObjects
			if not changed then
				for i, object in objects do
					if object ~= lastObjects[i] then
						changed = true
						break
					end
				end
			end

			if changed or motor ~= lastMotor or owner ~= lastRig then
				choose(motor, owner, objects, not changed)
			else
				show()
			end
		end)
	)
	refresh()
	local motor, owner, objects = selection()
	choose(motor, owner, objects, false)
end

function Auto.toggle()
	if host then
		Auto.close()
	else
		Auto.open()
	end
end

function Auto.init(options)
	Auto.destroy()
	refs = options
	table.insert(
		connections,
		options.ScreenGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not options.ScreenGui.Enabled then
				Auto.close()
			end
		end)
	)
	table.insert(connections, options.ScreenGui.Destroying:Connect(Auto.destroy))
	table.insert(connections, options.Plugin.Unloading:Connect(Auto.destroy))
end

return Auto
