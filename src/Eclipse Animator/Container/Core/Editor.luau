--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local WindowMotion = require("Motion")
local Chrome = require("Chrome")
local Theme = require("Theme")
local Events = require("Events")
local State = require("State")
local SoundEditor = require("SoundEditor")
local SoundData = require("SoundData")
local DELETE_ICON = "rbxassetid://97744685934900"
local WindowFX = require("WindowFX")
local UserInputService = game:GetService("UserInputService")

local function neutralHover(button)
	button.AutoButtonColor = false
	local overlay = Instance.new("Frame")
	overlay.Name = "HoverFill"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BackgroundTransparency = 0.93
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.Visible = false
	overlay.ZIndex = button.ZIndex + 1
	overlay.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = overlay
	button.MouseEnter:Connect(function()
		overlay.Visible = true
	end)
	button.MouseLeave:Connect(function()
		overlay.Visible = false
		overlay.BackgroundTransparency = 0.93
	end)
	button.MouseButton1Down:Connect(function()
		overlay.BackgroundTransparency = 0.87
	end)
	button.MouseButton1Up:Connect(function()
		overlay.BackgroundTransparency = 0.93
	end)
end

local Editor = {}
local WIDTH, HEIGHT = 370, 268
local FIELD_X, FIELD_WIDTH, FIELD_HEIGHT = 56, 54, 26
local FOOTER_Y, SPEED_Y = HEIGHT - 35, 192

local function make(class, parent, name, props)
	local object = Instance.new(class)

	object.Name = name
	for key, value in props do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function tag(object, attr, key)
	object:SetAttribute(attr, key)
	return object
end

local function round(object, radius)
	make("UICorner", object, "Corner", { CornerRadius = UDim.new(0, radius) })
end

local function outline(object, transparency)
	return tag(
		make("UIStroke", object, "Outline", {
			Color = Theme.panelOutlineDefault(),
			Thickness = 1,
			Transparency = transparency or 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		"ThemeStrk",
		"Strk"
	)
end

local function place(session, point)
	local window, parent = session.window, session.window.Parent
	if not parent then
		return
	end

	local animationScale = window:FindFirstChild("EclipseWindowScale")
	local scale = window.AbsoluteSize.X
		/ (window.Size.X.Offset * (animationScale and animationScale.Scale or 1))
	if scale <= 0 then
		scale = 1
	end

	local origin, viewport = parent.AbsolutePosition, parent.AbsoluteSize
	local size = Vector2.new(window.Size.X.Offset, window.Size.Y.Offset)
	local desired = UDim2.fromOffset(
		(point.X - origin.X) / scale + size.X * 0.5,
		(point.Y - origin.Y) / scale + size.Y * 0.5
	)
	window.Position =
		WindowMotion.inside(desired, size, viewport / scale, Vector2.new(0.5, 0.5), scale)
end

local function restingPosition(window)
	local animationScale = window:FindFirstChild("EclipseWindowScale")
	local scale = animationScale and animationScale.Scale or 1
	return window.AbsolutePosition + window.AbsoluteSize * (0.5 - 0.5 / scale)
end

local function bindDrag(session, handle)
	Chrome.bindDrag(session.window, handle, {
		disabled = function()
			return session.closing
		end,
		clamp = true,
		threshold = 3,
	})
	table.insert(
		session.connections,
		session.window.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if not session.closing then
				place(session, restingPosition(session.window))
			end
		end)
	)
end

function Editor.open(timeline, track, id, anchor)
	Editor.close(timeline)
	local event = track.Events[id]
	if not event then
		return
	end

	local template = timeline.refs.RigItemTemplate
	local title = template and template:FindFirstChild("Title", true)
	local fontFace = title and title.FontFace
		or Font.new("rbxasset://fonts/families/RobotoMono.json")
	local parent = timeline.refs.PluginGui
	if not parent then
		return
	end

	local window = tag(
		make("Frame", nil, "EventEditor", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(WIDTH, HEIGHT),
			BackgroundColor3 = Color3.fromRGB(22, 16, 28),
			BorderSizePixel = 0,
			Active = true,
			Visible = false,
			ZIndex = 100,
		}),
		"ThemeBg",
		"Bg"
	)
	round(window, 6)
	outline(window)
	local header, headerTitle, dragHandle = Chrome.header(window, "EVENT", 101, 44)

	local function label(parentObject, name, text, pos, size)
		local object = make("TextLabel", parentObject, name, {
			Text = text,
			Position = pos,
			Size = size,
			BackgroundTransparency = 1,
			FontFace = fontFace,
			TextSize = 11,
			TextColor3 = Color3.fromRGB(230, 223, 238),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 102,
		})
		tag(object, "ThemeTxt", "Txt")
		return object
	end

	local function button(parentObject, name, text, pos, size)
		local object = make("TextButton", parentObject, name, {
			Text = text,
			Position = pos,
			Size = size,
			BackgroundColor3 = Color3.fromRGB(45, 27, 56),
			BorderSizePixel = 0,
			FontFace = fontFace,
			TextSize = 11,
			TextColor3 = Color3.fromRGB(230, 223, 238),
			AutoButtonColor = true,
			ZIndex = 103,
		})
		tag(object, "ThemeBg", "TopBtn")
		tag(object, "ThemeTxt", "Txt")
		round(object, 4)
		return object
	end

	local close = Chrome.close(header, nil, 105)

	local tabs, pages, numericFields = {}, {}, {}
	local speed, durationLabel, duration
	local selectedTab = event.Subtitle and "Subtitle"
		or #(event.Emits or {}) > 0 and "Emit"
		or SoundData.has(event.Sounds) and "Sound"
		or "Event"
	local sessionSound

	local function speedValue()
		return selectedTab == "Sound" and sessionSound and sessionSound.speed()
			or track.Events[id].Speed
			or 1
	end

	local session = {
		window = window,
		track = track,
		id = id,
		before = Events.snapshot(track),
		dirty = false,
		connections = {},
	}
	timeline._eventEditor = session
	window.Destroying:Once(function()
		if timeline._eventEditor == session and not session.closing then
			if session.settle then
				session.settle()
			end

			Editor.commit(timeline)
			if session.sound then
				session.sound.close()
			end

			session.closing = true
			timeline._eventEditor = nil
		end

		for _, connection in session.connections do
			connection:Disconnect()
		end

		table.clear(session.connections)
		WindowFX.clear(window)
	end)
	local pendingChange

	local function settle()
		pendingChange = nil
		if session.closing then
			return
		end

		Events.changed(track)
		require("EventPlayback").disable()
		timeline:RefreshEventRows()
	end

	session.settle = function()
		if pendingChange then
			task.cancel(pendingChange)
			settle()
		end
	end

	local function change(field, value, deferred)
		if session.closing then
			return
		end

		local current = track.Events[id]
		if not current then
			return
		end

		if field == "Frame" then
			value = Events.nextFrame(track, value, id)
		end

		if current[field] == value then
			return
		end

		if field == "Markers" then
			Events.setMarkers(current, value)
		else
			current[field] = value
		end

		session.dirty = true
		if pendingChange then
			task.cancel(pendingChange)
			pendingChange = nil
		end

		if deferred then
			pendingChange = task.delay(0.25, settle)
		else
			settle()
		end
	end

	local function fieldShell(parentObject, name, pos, size)
		local shell = tag(
			make("Frame", parentObject, name .. "Field", {
				Position = pos,
				Size = size,
				BackgroundColor3 = Color3.fromRGB(15, 12, 19),
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 103,
			}),
			"ThemeBg",
			"Pnl"
		)
		round(shell, 4)
		outline(shell)
		return shell
	end

	local function textBox(parentObject, name, text, multiline)
		local object = tag(
			make("TextBox", parentObject, name, {
				Text = text,
				Position = UDim2.fromOffset(7, multiline and 5 or 2),
				Size = UDim2.new(1, -14, 1, multiline and -10 or -4),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				MultiLine = multiline or false,
				FontFace = multiline and Font.new("rbxasset://fonts/families/RobotoMono.json")
					or fontFace,
				TextSize = multiline and 13 or 12,
				TextColor3 = Color3.fromRGB(230, 223, 238),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = multiline and Enum.TextYAlignment.Top
					or Enum.TextYAlignment.Center,
				ZIndex = 104,
			}),
			"ThemeTxt",
			"Txt"
		)
		object.FocusLost:Connect(function()
			task.defer(function()
				if timeline._eventEditor == session then
					Editor.commit(timeline)
				end
			end)
		end)
		return object
	end

	local function box(parentObject, name, text, pos, size)
		return textBox(fieldShell(parentObject, name, pos, size), name, text, false)
	end

	local function numeric(boxObject, field)
		local function flush()
			local current = track.Events[id]
			if not current or session.closing then
				return
			end

			local value = tonumber(boxObject.Text)
			if value and value == value and math.abs(value) < math.huge then
				if field == "Speed" and selectedTab == "Sound" then
					sessionSound.setSpeed(value)
				else
					change(
						field,
						field == "Speed" and Events.normalizeSpeed(value)
							or math.max(0, math.floor(value + 0.5))
					)
				end
			end

			boxObject.Text = tostring(field == "Speed" and speedValue() or current[field] or 0)
		end

		table.insert(numericFields, flush)
		require("NumericInput").connect(
			boxObject,
			{ step = field == "Speed" and 0.1 or 1, min = 0, integer = field ~= "Speed" },
			flush
		)
	end

	session.flush = function()
		for _, flush in numericFields do
			flush()
		end

		if sessionSound then
			sessionSound.flush()
		end

		if session.settle then
			session.settle()
		end
	end

	local tabBar = tag(
		make("Frame", window, "Tabs", {
			Position = UDim2.fromOffset(10, 37),
			Size = UDim2.new(1, -20, 0, 30),
			BackgroundColor3 = Color3.fromRGB(15, 12, 19),
			BorderSizePixel = 0,
			ZIndex = 102,
		}),
		"ThemeBg",
		"Pnl"
	)
	round(tabBar, 5)
	outline(tabBar, 0.35)
	for index, tabTitle in { "Event", "Emit", "Subtitle", "Code Begin", "Code End", "Sound" } do
		local tab = button(
			tabBar,
			tabTitle .. "Tab",
			(
				tabTitle == "Code Begin" and "Begin"
				or tabTitle == "Code End" and "End"
				or tabTitle == "Emit" and "VFX"
				or tabTitle
			),
			UDim2.new((index - 1) / 6, 2, 0, 2),
			UDim2.new(1 / 6, -4, 0, 26)
		)
		neutralHover(tab)
		tabs[tabTitle] = tab
		local page = make("Frame", window, tabTitle .. "Page", {
			Position = UDim2.fromOffset(10, 75),
			Size = UDim2.new(1, -20, 0, 108),
			BackgroundTransparency = 1,
			Visible = tabTitle == selectedTab,
			ZIndex = 102,
		})
		pages[tabTitle] = page
		tab.MouseButton1Click:Connect(function()
			if session.closing then
				return
			end

			Editor.commit(timeline)
			selectedTab = tabTitle
			window.SpeedLabel.Visible = tabTitle ~= "Subtitle"
			speed.Parent.Visible = tabTitle ~= "Subtitle"
			for key, value in pages do
				value.Visible = key == tabTitle
				tabs[key].BackgroundTransparency = key == tabTitle and 0 or 1
			end

			sessionSound.setVisible(tabTitle == "Sound")
			durationLabel.Visible = tabTitle == "Code End"
			duration.Parent.Visible = tabTitle == "Code End"
			speed.Text = tostring(speedValue())
		end)
		tab.BackgroundTransparency = tabTitle == selectedTab and 0 or 1
	end

	local subtitleEdit = button(
		pages.Subtitle,
		"EditSubtitle",
		"Edit subtitle…",
		UDim2.fromOffset(0, 0),
		UDim2.new(1, 0, 0, 30)
	)
	label(
		pages.Subtitle,
		"SubtitleHint",
		"text, presets, motion and style keys",
		UDim2.fromOffset(0, 40),
		UDim2.new(1, 0, 0, 26)
	)
	subtitleEdit.Activated:Connect(function()
		if session.closing then
			return
		end

		Editor.commit(timeline)
		if not track.Events[id].Subtitle then
			change("Subtitle", require("SubtitleData").preset("Clean"))
			Editor.commit(timeline)
		end

		Editor.close(timeline)
		require("SubtitleEditor").open(track, id)
	end)
	local Picker = require("EffectPicker")
	local Data = require("ClipboardRows")
	local action, actionButtons = "Emit", {}

	local function eventAction(rows)
		local chosen
		for _, row in Data.copy(rows) do
			local value = row.Action or "Emit"
			if chosen and chosen ~= value then
				return nil
			end

			chosen = value
		end

		return chosen or action
	end

	local choose = button(
		pages.Emit,
		"ChooseTargets",
		"Choose targets…",
		UDim2.fromOffset(0, 34),
		UDim2.new(1, -64, 0, 30)
	)
	local clear = button(
		pages.Emit,
		"ClearEmits",
		"Clear",
		UDim2.new(1, -58, 0, 34),
		UDim2.fromOffset(58, 30)
	)
	local summary =
		label(pages.Emit, "Summary", "", UDim2.fromOffset(0, 68), UDim2.new(1, 0, 0, 18))

	local function paintEmits()
		local current = track.Events[id]
		if not current then
			return
		end

		action = eventAction(current.Emits)
		for value, control in actionButtons do
			control.Text = (action == value and "\u{2713} " or "")
				.. (value == "Emit" and "Emit / pulse" or value)
		end

		local count = #Picker.selection(track.Rig, current.Emits, action):export()
		summary.Text = count == 0 and "nothing selected"
			or tostring(count) .. (count == 1 and " effect selected" or " effects selected")
		clear.Interactable = #Data.copy(current.Emits) > 0
		clear.TextTransparency = clear.Interactable and 0 or 0.6
	end

	session.openEmitPicker = function()
		if session.closing or session.emitPicker or not track.Events[id] then
			return
		end

		Editor.commit(timeline)
		session.emitPicker = Picker.open({
			window = window,
			root = track.Rig,
			entries = track.Events[id].Emits,
			action = action,
			label = label,
			button = button,
			apply = function(entries)
				if session.closing or timeline._eventEditor ~= session or not track.Events[id] then
					return
				end

				change("Emits", entries)
				Editor.commit(timeline)
				paintEmits()
			end,
			closed = function()
				session.emitPicker = nil
				place(session, restingPosition(window))
			end,
		})
	end

	choose.Activated:Connect(session.openEmitPicker)
	clear.Activated:Connect(function()
		change("Emits", {})
		Editor.commit(timeline)
		paintEmits()
	end)
	for index, value in { "Emit", "Enable", "Disable" } do
		local control = button(
			pages.Emit,
			value .. "Action",
			value,
			UDim2.new((index - 1) / 3, 0, 0, 0),
			UDim2.new(1 / 3, -4, 0, 28)
		)
		actionButtons[value] = control
		control.Activated:Connect(function()
			if session.closing or not track.Events[id] then
				return
			end

			action = value
			local rows = Data.copy(track.Events[id].Emits)
			for _, row in rows do
				row.Action = value
			end

			rows = Picker.selection(track.Rig, rows, value):export()
			change("Emits", rows)
			Editor.commit(timeline)
			paintEmits()
		end)
	end

	paintEmits()

	local eventPage = pages.Event
	local markerIndex, painting = 1, false
	local count =
		label(eventPage, "EventCount", "", UDim2.fromOffset(0, 0), UDim2.fromOffset(106, 24))
	local previous =
		button(eventPage, "PreviousEvent", "<", UDim2.fromOffset(112, 0), UDim2.fromOffset(24, 24))
	local nextMarker =
		button(eventPage, "NextEvent", ">", UDim2.fromOffset(140, 0), UDim2.fromOffset(24, 24))
	local add = button(
		eventPage,
		"AddMarker",
		"+ Event",
		UDim2.fromOffset(170, 0),
		UDim2.fromOffset(70, 24)
	)
	local remove =
		button(eventPage, "RemoveMarker", "-", UDim2.fromOffset(246, 0), UDim2.fromOffset(44, 24))
	label(eventPage, "NameLabel", "Name", UDim2.fromOffset(0, 36), UDim2.fromOffset(172, 16))
	label(
		eventPage,
		"ParameterLabel",
		"Parameter",
		UDim2.fromOffset(182, 36),
		UDim2.fromOffset(108, 16)
	)
	local name = box(eventPage, "Name", "", UDim2.fromOffset(0, 56), UDim2.fromOffset(172, 28))
	local parameter =
		box(eventPage, "Parameter", "", UDim2.fromOffset(182, 56), UDim2.fromOffset(108, 28))

	local function paintMarkers()
		painting = true
		local markers = Events.markers(track.Events[id])
		markerIndex = math.clamp(markerIndex, 1, math.max(1, #markers))
		local marker = markers[markerIndex]
		count.Text = string.format("Event %d / %d", marker and markerIndex or 0, #markers)
		name.Text = marker and marker.Name or ""
		parameter.Text = marker and marker.Parameter or ""
		name.TextEditable = marker ~= nil
		parameter.TextEditable = marker ~= nil
		previous.Interactable = markerIndex > 1
		nextMarker.Interactable = markerIndex < #markers
		remove.Interactable = #markers > 0
		previous.TextTransparency = previous.Interactable and 0 or 0.6
		nextMarker.TextTransparency = nextMarker.Interactable and 0 or 0.6
		remove.TextTransparency = remove.Interactable and 0 or 0.6
		painting = false
	end

	local function editMarker(field, value)
		if painting or session.closing then
			return
		end

		local markers = Events.markers(track.Events[id])
		local marker = markers[markerIndex]
		if not marker or marker[field] == value then
			return
		end

		marker[field] = value
		change("Markers", markers)
	end

	name:GetPropertyChangedSignal("Text"):Connect(function()
		editMarker("Name", name.Text)
	end)
	parameter:GetPropertyChangedSignal("Text"):Connect(function()
		editMarker("Parameter", parameter.Text)
	end)
	previous.Activated:Connect(function()
		Editor.commit(timeline)
		markerIndex -= 1
		paintMarkers()
	end)
	nextMarker.Activated:Connect(function()
		Editor.commit(timeline)
		markerIndex += 1
		paintMarkers()
	end)
	add.Activated:Connect(function()
		if session.closing then
			return
		end

		Editor.commit(timeline)
		local markers = Events.markers(track.Events[id])
		table.insert(markers, { Name = "Event", Parameter = "" })
		markerIndex = #markers
		change("Markers", markers)
		paintMarkers()
		Editor.commit(timeline)
	end)
	remove.Activated:Connect(function()
		if session.closing then
			return
		end

		Editor.commit(timeline)
		local markers = Events.markers(track.Events[id])
		table.remove(markers, markerIndex)
		change("Markers", markers)
		paintMarkers()
		Editor.commit(timeline)
	end)
	paintMarkers()
	local enabled = button(
		window,
		"Enabled",
		event.Enabled ~= false and "✓ Enabled" or "Disabled",
		UDim2.fromOffset(121, FOOTER_Y),
		UDim2.fromOffset(86, FIELD_HEIGHT)
	)
	outline(enabled, 0.65)
	enabled.MouseButton1Click:Connect(function()
		if session.closing then
			return
		end

		local current = track.Events[id]
		if not current then
			return
		end

		change("Enabled", current.Enabled == false)
		enabled.Text = current.Enabled and "✓ Enabled" or "Disabled"
	end)
	for _, field in { "CodeBegin", "CodeEnd" } do
		local page = pages[field == "CodeBegin" and "Code Begin" or "Code End"]
		local isEnd = field == "CodeEnd"
		local notice = label(
			page,
			"CodePreviewNotice",
			"Runs in exported cutscenes; Studio preview skips custom code.",
			UDim2.new(),
			UDim2.new(1, 0, 0, 28)
		)
		notice.TextSize = 11
		notice.TextWrapped = true
		local shell = fieldShell(page, field, UDim2.fromOffset(0, 32), UDim2.new(1, 0, 1, -32))
		local scroll = tag(
			make("ScrollingFrame", shell, "CodeScroll", {
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(1, -4, 1, -4),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.XY,
				ScrollingDirection = Enum.ScrollingDirection.XY,
				ZIndex = 103,
			}),
			"ThemeScr",
			"Scr"
		)
		local code = textBox(scroll, field, event[field], true)
		code.PlaceholderText = "Exported cutscene code..."
		code.Size = UDim2.fromOffset(WIDTH - 38, 94)
		code.AutomaticSize = Enum.AutomaticSize.XY
		code.TextWrapped = false
		code:GetPropertyChangedSignal("Text"):Connect(function()
			change(field, code.Text, true)
		end)
	end

	local speedLabel = label(
		window,
		"SpeedLabel",
		"Speed",
		UDim2.fromOffset(10, SPEED_Y),
		UDim2.fromOffset(42, FIELD_HEIGHT)
	)
	speedLabel.TextSize = 14
	speedLabel.Visible = selectedTab ~= "Subtitle"
	speed = box(
		window,
		"Speed",
		tostring(event.Speed or 1),
		UDim2.fromOffset(FIELD_X, SPEED_Y),
		UDim2.fromOffset(FIELD_WIDTH, FIELD_HEIGHT)
	)
	speed.TextSize = 14
	speed.Position = UDim2.fromOffset(4, 2)
	speed.Size = UDim2.new(1, -8, 1, -4)
	speed.ClearTextOnFocus = true
	speed.Parent.Visible = selectedTab ~= "Subtitle"
	speed.TextXAlignment = Enum.TextXAlignment.Center
	numeric(speed, "Speed")
	durationLabel = label(
		window,
		"DurationLabel",
		"Duration",
		UDim2.fromOffset(118, SPEED_Y),
		UDim2.fromOffset(56, FIELD_HEIGHT)
	)
	duration = box(
		window,
		"Duration",
		tostring(event.Duration),
		UDim2.fromOffset(174, SPEED_Y),
		UDim2.fromOffset(FIELD_WIDTH, FIELD_HEIGHT)
	)
	duration.TextSize = 14
	duration.TextXAlignment = Enum.TextXAlignment.Center
	duration.ClearTextOnFocus = true
	duration.Position = UDim2.fromOffset(4, 2)
	duration.Size = UDim2.new(1, -8, 1, -4)
	durationLabel.Visible = false
	duration.Parent.Visible = false
	numeric(duration, "Duration")
	sessionSound = SoundEditor.bind({
		page = pages.Sound,
		window = window,
		speedY = SPEED_Y,
		timeline = timeline,
		session = session,
		event = function()
			return track.Events[id]
		end,
		label = label,
		box = box,
		button = button,
		change = change,
		commit = function()
			Editor.commit(timeline)
		end,
		beforeSelect = function()
			Editor.commit(timeline)
		end,
		selected = function()
			if selectedTab == "Sound" then
				speed.Text = tostring(speedValue())
			end
		end,
	})
	speed.Text = tostring(speedValue())
	session.sound = sessionSound
	sessionSound.setVisible(selectedTab == "Sound")
	tag(
		make("Frame", window, "FooterDivider", {
			Position = UDim2.fromOffset(10, 223),
			Size = UDim2.new(1, -20, 0, 1),
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.panelOutlineDefault(),
			BackgroundTransparency = 0.35,
			ZIndex = 102,
		}),
		"ThemeBg",
		"Div"
	)
	local frameLabel = label(
		window,
		"FrameLabel",
		"Frame",
		UDim2.fromOffset(10, FOOTER_Y),
		UDim2.fromOffset(42, FIELD_HEIGHT)
	)
	frameLabel.TextSize = 14
	local frame = box(
		window,
		"Frame",
		tostring(event.Frame),
		UDim2.fromOffset(FIELD_X, FOOTER_Y),
		UDim2.fromOffset(FIELD_WIDTH, FIELD_HEIGHT)
	)
	frame.TextSize = 14
	frame.TextXAlignment = Enum.TextXAlignment.Center
	frame.ClearTextOnFocus = true
	frame.Position = UDim2.fromOffset(4, 2)
	frame.Size = UDim2.new(1, -8, 1, -4)
	numeric(frame, "Frame")
	for _, input in { speed, frame, duration } do
		input.TextScaled = true
		make("UITextSizeConstraint", input, "TextSizeLimit", { MinTextSize = 10, MaxTextSize = 14 })
	end

	local done = button(
		window,
		"Done",
		"Done",
		UDim2.new(1, -92, 0, FOOTER_Y),
		UDim2.fromOffset(82, FIELD_HEIGHT)
	)
	outline(done, 0.65)
	local delete =
		button(window, "DeleteEvent", "", UDim2.new(1, -36, 0, SPEED_Y), UDim2.fromOffset(26, 26))
	tag(
		make("ImageLabel", delete, "Icon", {
			Image = DELETE_ICON,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(18, 18),
			ImageColor3 = Color3.fromRGB(230, 223, 238),
			ZIndex = 104,
		}),
		"ThemeImg",
		"Txt"
	)
	delete.MouseButton1Click:Connect(function()
		if not session.closing then
			timeline:DeleteEvent(track, id)
		end
	end)
	local tip = timeline.refs.HoverDialog or State.UIHelpers and State.UIHelpers.hoverDialog
	if tip then
		local cleanup = tip:latchToInstance(delete, "Delete event", { maxWidth = 160 })
		table.insert(session.connections, {
			Disconnect = function()
				tip:disappear(delete)
				cleanup()
			end,
		})
	end

	close.MouseButton1Click:Connect(function()
		Editor.close(timeline)
	end)
	done.MouseButton1Click:Connect(function()
		Editor.close(timeline)
	end)
	window.Parent = parent
	if parent:IsA("LayerCollector") then
		table.insert(
			session.connections,
			parent:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not parent.Enabled then
					Editor.close(timeline)
				end
			end)
		)
	end

	Theme.addRoot(window)
	Theme.applyTree(window)
	local point = anchor or UserInputService:GetMouseLocation()
	place(session, point)
	bindDrag(session, dragHandle)
	task.defer(function()
		if session.closing or not window.Parent then
			return
		end

		place(session, point)
		window.Visible = true
		WindowFX.pop(window)
	end)
	return session
end

function Editor.commit(timeline)
	local session = timeline._eventEditor
	if not session or session.closing then
		return
	end

	session.flush()
	if not session.dirty then
		return
	end

	session.dirty = false
	timeline:RecordEventEdit(session.track, session.before, "Edit event")
	session.before = Events.snapshot(session.track)
end

function Editor.close(timeline)
	local session = timeline._eventEditor
	if not session then
		return
	end

	session.flush()
	local focused = UserInputService:GetFocusedTextBox()
	if focused and focused:IsDescendantOf(session.window) then
		focused:ReleaseFocus()
	end

	Editor.commit(timeline)
	if session.sound then
		session.sound.close()
	end

	if session.emitPicker then
		session.emitPicker.close(true)
	end

	session.closing = true
	timeline._eventEditor = nil
	for _, connection in session.connections do
		connection:Disconnect()
	end

	table.clear(session.connections)
	for _, object in session.window:GetDescendants() do
		if object:IsA("GuiButton") then
			object.Interactable = false
		end

		if object:IsA("TextBox") then
			object.TextEditable = false
		end
	end

	WindowFX.shrink(session.window, function()
		session.window:Destroy()
	end)
end

return Editor
