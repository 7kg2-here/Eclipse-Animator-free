--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local Motion = require("Motion")
local State = require("State")
local Data = require("ProjectData")
local UI = require("UI")
local AnimatorLayout = require("AnimatorLayout")
local MainMenu = require("MainMenu")
local PluginShell = require("PluginShell")
local ModuleInit = require("ModuleInit")
local Project = require("Project")
local Connections = require("Connections")
local Buttons = require("Buttons")
local KeybindActions = require("KeybindActions")
local KeybindModule = require("Keybinds")
local Drag = require("Drag")
local SizeableWindows = require("SizeableWindows")
local History = require("History")
local Notification = require("Notification")
local Alert = require("Alert")
local Export = require("Export")
local HelperMenu = require("HelperMenu")
local MotionPath = require("motionPath")
local ArmatureImport = require("ArmatureImport")
local EventPlayback = require("EventPlayback")
local EventCleanup = require("DumpStorage")
local Preferences = require("Preferences")
local GraphEditor = require("GraphEditor")
local PreferencesEditor = require("PreferencesEditor")
local ArmaturePropertiesEditor = require("ArmaturePropertiesEditor")
local RotationCursor = require("RotateCursor")

local AnimatorDock = require("AnimatorDock")
local Boot = {}

local started = false

function Boot.bindShutdown(plugin, source, gui, cleanup)
	local stopped = false
	local connections = {}

	local function stop()
		if stopped then
			return
		end

		stopped = true
		for _, connection in connections do
			connection:Disconnect()
		end

		table.clear(connections)
		cleanup()
	end

	for _, signal in { plugin.Unloading, source.Destroying, gui.Destroying } do
		table.insert(connections, signal:Connect(stop))
	end

	return stop
end

local function start(plugin: any, eclipseScript: Instance)
	if started then
		return
	end

	started = true
	require("root").migrate()

	do
		local staleGuides = workspace:FindFirstChild("_EclipseAnimator_DragGuides")
		if staleGuides then
			pcall(function()
				staleGuides:Destroy()
			end)
		end

		local cam = workspace.CurrentCamera
		if cam then
			for _, child in ipairs(cam:GetChildren()) do
				local isAxis = child.Name == "_EclipseAnimator_Axis"
					or child.Name == "_EclipseAnimator_DragGuides"
				local isMotionPath = child.Name == "EclipseAnimator_MotionPath"
				local isTaggedBones = child:GetAttribute("EclipseAnimator_BonesFolder") == true
				local isLegacyBones = false
				if
					not isAxis
					and not isMotionPath
					and not isTaggedBones
					and child:IsA("Folder")
					and child.Name:sub(-5) == "Bones"
				then
					for _, grand in ipairs(child:GetChildren()) do
						if grand:GetAttribute("SourcePartName") then
							isLegacyBones = true
							break
						end
					end
				end

				if isAxis or isMotionPath or isTaggedBones or isLegacyBones then
					pcall(function()
						child:Destroy()
					end)
				end
			end
		end
	end

	do
		local attrs = eclipseScript:GetAttributes()
		if attrs then
			for k in pairs(attrs) do
				if string.sub(k, 1, 15) == "EclipseAnimator" then
					pcall(function()
						eclipseScript:SetAttribute(k, nil)
					end)
				end
			end
		end

		for _, child in ipairs(eclipseScript:GetChildren()) do
			if
				child:IsA("Folder")
				and child:GetAttribute("EclipseAnimator_HistoryBoundary") == true
			then
				pcall(function()
					child:Destroy()
				end)
			end
		end
	end

	do
		require("RigPose").recoverStamps(workspace)
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("Motor6D") then
				local saved = descendant:GetAttribute("EclipseAnimatorDefaultC0")
				if saved then
					pcall(function()
						descendant.C0 = saved
					end)
					pcall(function()
						descendant:SetAttribute("EclipseAnimatorDefaultC0", nil)
					end)
				end

				if descendant:GetAttribute("EclipseDisabled") ~= nil then
					pcall(function()
						descendant:SetAttribute("EclipseDisabled", nil)
					end)
				end

				if descendant:GetAttribute("EclipseAddedObject") == true then
					pcall(function()
						descendant.Enabled = false
					end)
				end

				local attrs = descendant:GetAttributes()
				for attrName in pairs(attrs) do
					if string.sub(attrName, 1, 22) == "EclipseChannelDisabled" then
						pcall(function()
							descendant:SetAttribute(attrName, nil)
						end)
					end
				end
			elseif descendant:IsA("Bone") then
				local saved = descendant:GetAttribute("EclipseAnimatorDefaultC0")
				if saved then
					pcall(function()
						descendant.Transform = descendant.CFrame:Inverse() * saved
					end)
					pcall(function()
						descendant:SetAttribute("EclipseAnimatorDefaultC0", nil)
					end)
				end
			end
		end
	end

	pcall(function()
		ArmatureImport.stashAll()
	end)

	Data.setPlugin(plugin, nil, "main", eclipseScript:GetFullName())
	PluginShell.attach(plugin, eclipseScript)
	require("Recovery").init(plugin)
	require("RigCleanup").run()
	EventCleanup.recover()

	Preferences.init({
		GetSetting = Data.getInteractiveSetting,
		SetSetting = Data.queueInteractiveSetting,
		CanRetry = Data.canRetryInteractiveSettings,
	})

	UI.resolve(eclipseScript)

	local function shutdown()
		pcall(PluginShell.destroy)
		local closingRigs = table.clone(State.getAllRigs())
		pcall(function()
			if State.BlenderBridge then
				State.BlenderBridge.destroy()
			end
		end)
		pcall(History.disconnect)
		pcall(KeybindModule.destroy)
		pcall(GraphEditor.destroy)
		pcall(PreferencesEditor.destroy)
		pcall(ArmaturePropertiesEditor.destroy)

		pcall(Connections.destroy)
		pcall(function()
			State.Axis:Destroy()
		end)
		local restored, restoreError = pcall(Project.gracefulShutdown)
		if not restored then
			warn("[Eclipse shutdown] " .. tostring(restoreError))
		end

		for _, rig in closingRigs do
			local ok, err = pcall(Project.restoreRigToDefaultPose, rig)
			if not ok then
				warn("[Eclipse restore] " .. tostring(err))
			end
		end

		Data.shutdownInteractiveSettings()
		pcall(function()
			require("RigCleanup").run()
		end)
		pcall(function()
			require("GifBackground").destroy()
		end)
		pcall(MotionPath.destroy)
		pcall(function()
			require("KeyframeMenu").close()
		end)
		pcall(function()
			require("Focus").cancel()
		end)
		pcall(function()
			if State.UIHelpers then
				State.UIHelpers:Destroy()
			end
		end)
		pcall(function()
			require("UserInputService").destroy()
		end)
		pcall(function()
			local staleGuides = workspace:FindFirstChild("_EclipseAnimator_DragGuides")
			if staleGuides then
				staleGuides:Destroy()
			end

			local cam = workspace.CurrentCamera
			if not cam then
				return
			end

			for _, child in ipairs(cam:GetChildren()) do
				if
					child.Name == "_EclipseAnimator_Axis"
					or child.Name == "EclipseAnimator_MotionPath"
					or child.Name == "_EclipseAnimator_DragGuides"
				then
					child:Destroy()
				end
			end
		end)
		pcall(function()
			for _, descendant in ipairs(workspace:GetDescendants()) do
				if descendant:IsA("Motor6D") then
					if descendant:GetAttribute("EclipseDisabled") ~= nil then
						descendant:SetAttribute("EclipseDisabled", nil)
					end

					if descendant:GetAttribute("EclipseAddedObject") == true then
						descendant.Enabled = false
					end

					local attrs = descendant:GetAttributes()
					for attrName in pairs(attrs) do
						if string.sub(attrName, 1, 22) == "EclipseChannelDisabled" then
							descendant:SetAttribute(attrName, nil)
						end
					end
				end
			end
		end)
		pcall(function()
			UI.EclipseGUI:Destroy()
		end)
		pcall(function()
			local misc = UI.MiscGUI
			if misc then
				misc:Destroy()
			end
		end)
	end

	Boot.shutdown = Boot.bindShutdown(plugin, eclipseScript, UI.EclipseGUI, shutdown)
	MainMenu.attach(UI)
	EventPlayback.attach(plugin, UI.EclipseGUI)

	Data.setAnimSavesTemplate(UI.AnimSavesTemplate)

	State.mouse = plugin:GetMouse()
	RotationCursor.attach(plugin, UI.EclipseGUI, UI.AnimatorFrame)

	ModuleInit.boot(plugin)
	Data.resumeInteractiveSettings()
	AnimatorLayout.attach(UI)
	UI.EclipseGUI.Destroying:Connect(function()
		State.Axis:Destroy()
	end)

	Connections.attach()
	Buttons.attach()
	Export.initProjectsList()
	HelperMenu.init()
	KeybindActions.register()
	KeybindModule.init()

	History.init(eclipseScript)
	History.setActiveCheck(function()
		return UI.isAnimatorActive()
	end)
	History.setGuardCallbacks({
		onWarn = function()
			Notification.show("WARNING", "Can't undo any further!")
		end,
	})

	History.setGuardCleanup(function()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end

		for _, child in ipairs(cam:GetChildren()) do
			if child.Name == "_EclipseAnimator_Axis" then
				pcall(function()
					child:Destroy()
				end)
			end
		end
	end)

	History.setJumpToFrame(function(frame)
		if not State.Timeline then
			return
		end

		local tl = State.Timeline:GetState()
		if not tl or not tl.FPS or tl.FPS <= 0 then
			return
		end

		tl.Playing = false
		if State.Timeline.SetDraggingPlayhead then
			State.Timeline:SetDraggingPlayhead(false)
		end

		tl.CurrentTime = frame / tl.FPS
		if State.currentRig then
			State.Timeline:ApplyPoseAtTime(State.currentRig, tl.CurrentTime)
		end

		State.Timeline:UpdatePlayhead()
	end)

	UI.PrimaryFrame.Visible = true
	UI.AnimatorFrame.Visible = false

	if State.Rig and State.Rig.CleanUpOldLockedRigs then
		State.Rig:CleanUpOldLockedRigs()
	end

	local saveWindow
	local function makeBarDraggable(barFrame, mainFrame, followers)
		if not barFrame then
			return
		end

		local sources = { barFrame }
		for _, descendant in ipairs(barFrame:GetDescendants()) do
			if descendant:IsA("GuiButton") then
				table.insert(sources, descendant)
			end
		end

		Drag.makeDraggable(sources, mainFrame, followers, {
			dragThreshold = 5,
			suppressClickAfterDrag = true,
			onFinished = function()
				local other = mainFrame == UI.PrimaryFrame and UI.AnimatorFrame or UI.PrimaryFrame
				other.Position = mainFrame.Position
				if saveWindow then
					saveWindow()
				end
			end,
		})
	end

	makeBarDraggable(UI.BarFrame, UI.PrimaryFrame, nil)
	makeBarDraggable(UI.AnimatorBarFrame, UI.AnimatorFrame, nil)

	UI.AnimatorFrame.Size = UDim2.fromOffset(686, 355)
	UI.PrimaryFrame.Position = UI.AnimatorFrame.Position
	UI.PrimaryFrame.Size = UI.AnimatorFrame.Size

	UI.PrimaryFrame:GetPropertyChangedSignal("Position"):Connect(function()
		if Motion.isTranslating(UI.PrimaryFrame) then
			return
		end

		UI.AnimatorFrame.Position = UI.PrimaryFrame.Position
	end)
	UI.AnimatorFrame:GetPropertyChangedSignal("Position"):Connect(function()
		if Motion.isTranslating(UI.AnimatorFrame) then
			return
		end

		UI.PrimaryFrame.Position = UI.AnimatorFrame.Position
	end)
	UI.PrimaryFrame:GetPropertyChangedSignal("Size"):Connect(function()
		UI.AnimatorFrame.Size = UI.PrimaryFrame.Size
	end)
	UI.AnimatorFrame:GetPropertyChangedSignal("Size"):Connect(function()
		UI.PrimaryFrame.Size = UI.AnimatorFrame.Size
	end)

	local userLeftDivWidth: number? = Data.getSetting("EclipseAnimator_LeftDivWidth")
	if type(userLeftDivWidth) ~= "number" then
		userLeftDivWidth = nil
	end

	local function updateAnimatorLeftDivWidth(animatorWidth: number)
		if not UI.LeftDiv then
			return
		end

		local maxAllowed = math.max(234, animatorWidth - 240)
		local target: number
		if userLeftDivWidth then
			target = math.clamp(userLeftDivWidth :: number, 234, maxAllowed)
		else
			target = 234
		end

		UI.LeftDiv.Size = UDim2.new(0, target, UI.LeftDiv.Size.Y.Scale, UI.LeftDiv.Size.Y.Offset)
	end

	saveWindow = SizeableWindows.attach({
		frame = UI.AnimatorFrame,
		mouse = State.mouse,
		minSize = AnimatorDock.MINIMUM,
		maxSize = Vector2.new(2494, 1320),
		settingKey = "EclipseAnimator_AnimatorWindow",
		onResize = function(w, _h)
			updateAnimatorLeftDivWidth(w)
			UI.PrimaryFrame.Size = UI.AnimatorFrame.Size
		end,
	})

	SizeableWindows.attach({
		frame = UI.PrimaryFrame,
		mouse = State.mouse,
		minSize = AnimatorDock.MINIMUM,
		maxSize = Vector2.new(2494, 1320),
		settingKey = "EclipseAnimator_AnimatorWindow",
		onResize = function(_w, _h)
			UI.AnimatorFrame.Size = UI.PrimaryFrame.Size
			updateAnimatorLeftDivWidth(UI.AnimatorFrame.Size.X.Offset)
		end,
	})

	if UI.LeftDiv and UI.LeftDiv.Parent then
		local contentFrame = UI.LeftDiv.Parent
		local contentLayout = contentFrame:FindFirstChildOfClass("UIListLayout")
		if contentLayout then
			contentLayout.Padding = UDim.new(0, 0)
		end

		UI.RightDiv.LayoutOrder = 1

		local existingDivider = contentFrame:FindFirstChild("EclipseLeftRightDivider")
		if existingDivider then
			existingDivider:Destroy()
		end

		local divider = Instance.new("ImageButton")
		divider.Name = "EclipseLeftRightDivider"
		divider.LayoutOrder = 0
		divider.Size = UDim2.new(0, 6, 1, 0)
		divider.BackgroundTransparency = 1
		divider.BorderSizePixel = 0
		divider.ImageTransparency = 1
		divider.AutoButtonColor = false
		divider.Active = true
		divider.Selectable = false
		divider.ZIndex = 50
		divider.Parent = contentFrame

		SizeableWindows.attachDivider({
			target = UI.LeftDiv,
			dragHandle = divider,
			mouse = State.mouse,
			minWidth = 234,
			maxWidth = function()
				return math.max(234, UI.AnimatorFrame.Size.X.Offset - 240)
			end,
			settingKey = "EclipseAnimator_LeftDivWidth",
			onChange = function(width)
				userLeftDivWidth = width
			end,
		})
	end

	UI.AnimatorFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		updateAnimatorLeftDivWidth(UI.AnimatorFrame.Size.X.Offset)
	end)
	AnimatorDock.attach(UI, plugin)
	Project.updateUI()

	MainMenu.bindPreferencesTip(UI)
	if Preferences.get("OpenAutomatically") then
		UI.EclipseGUI.Enabled = true
	end

	if Preferences.get("ShowLoadMessage") then
		print("Eclipse Animator successfully loaded! Developed and maintained by @riftkuro")
	end
end

Boot.start = start

return Boot
