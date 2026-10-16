--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local PartRigging = require("PartRigging")
local FileTools = require("FileTools")
local Visibility = require("Visibility")
local PropertySettings = require("PropertySettings")
local PropertyGizmo = require("PropertyGizmo")
local CameraRig = require("CameraRig")
local CameraPreview = require("CameraPreview")
local CameraControls = require("CameraControls")
local ExportResults = require("ExportResults")
local Export = require("Export")
local ImagePreviewer = require("ImagePreviewer")
local VideoWindow = require("VideoWindow")
local LiveSession = require("LiveSession")
local GreasePencil = require("GreasePencil")
local BlenderImport = require("BlenderImport")
local AnimationCleanup = require("AnimationCleanup")
local PhysicsWindow = require("PhysicsWindow")
local Library = require("ArmatureWorkflow")
local Selection = game:GetService("Selection")

local State = require("State")
local UI = require("UI")
local UIHelpersModule = require("UIHelpersModule")
local TimelineStatic = require("TimelineStatic")
local RigStatic = require("RigStatic")
local AxisStatic = require("AxisStatic")
local OnionSkinStatic = require("OnionSkinStatic")
local KeyframeMenu = require("KeyframeMenu")
local MotorMath = require("MotorMath")
local History = require("History")
local Notification = require("Notification")
local Alert = require("Alert")
local Project = require("Project")
local MenuBar = require("MenuBar")
local EditActions = require("EditActions")
local Theme = require("Theme")
local Customize = require("Customize")
local ArmatureImport = require("ArmatureImport")
local ArmatureRemoval = require("ArmatureRemoval")
local Data = require("ProjectData")
local RawTimelineState = require("RawState")
local Confirm = require("Confirm")
local Organization = require("Organization")
local Assets = require("AssetIds")
local GraphEditor = require("GraphEditor")
local PreferencesEditor = require("PreferencesEditor")
local ArmaturePropertiesEditor = require("ArmaturePropertiesEditor")
local Preferences = require("Preferences")
local ArmatureRuntime = require("ArmatureRuntime")
local LimbIK = require("LimbIK")
local BoneIK = require("BoneIK")

local MasterControl = require("MasterControl")
local ModuleInit = {}

local Shortcuts = require("Shortcuts")
local SavedDefaults = require("SavedDefaults")
local KeybindsEditor = require("KeybindsEditor")
local booted = false

local function refreshIKPreferences(key)
	if key == "R6IKLegPole" then
		if State.Rig and State.currentRig then
			State.Rig:RefreshIKChildren(State.currentRig)
		end

		if State.Axis then
			State.Axis:RefreshAxis()
		end

		return
	end

	if
		(key ~= "SoftIKPercent" and key ~= "R6BendPercent" and key ~= "IKFeetPlanted")
		or not State.Timeline
	then
		return
	end

	if key == "IKFeetPlanted" then
		local before = {}
		local value = Preferences.get(key)
		for _, rig in State.getAllRigs() do
			before[rig] = { rig:GetAttribute("EclipseIKFeetPlanted") }
			rig:SetAttribute("EclipseIKFeetPlanted", value)
			LimbIK.invalidate(rig)
		end

		State.currentProjectSaved = false

		local function apply(redo)
			for rig, old in before do
				if rig.Parent then
					local setting = old[1]
					if redo then
						setting = value
					end

					rig:SetAttribute("EclipseIKFeetPlanted", setting)
					LimbIK.invalidate(rig)
				end
			end

			if State.currentRig then
				State.Timeline:ApplyPoseAtTime(
					State.currentRig,
					State.Timeline:GetState().CurrentTime
				)
			end
		end

		History.record(function()
			apply(false)
		end, function()
			apply(true)
		end, "Planted feet")
	end

	if key == "R6BendPercent" then
		local before = {}
		local value = Preferences.get(key)
		for _, rig in State.getAllRigs() do
			before[rig] = { rig:GetAttribute("EclipseR6BendPercent") }
			rig:SetAttribute("EclipseR6BendPercent", value)
		end

		State.currentProjectSaved = false

		local function apply(redo)
			for rig, old in before do
				if rig.Parent then
					rig:SetAttribute("EclipseR6BendPercent", redo and value or old[1])
				end
			end

			if State.currentRig then
				State.Timeline:ApplyPoseAtTime(
					State.currentRig,
					State.Timeline:GetState().CurrentTime
				)
			end
		end

		History.record(function()
			apply(false)
		end, function()
			apply(true)
		end, "R6 bend")
	end

	local time = State.Timeline:GetState().CurrentTime
	for _, rig in State.getAllRigs() do
		if rig.Parent then
			if ArmatureRuntime.isRig(rig) then
				ArmatureRuntime.evaluate(rig, true)
			else
				LimbIK.apply(rig, time, false)
				BoneIK.solveAllForRig(rig)
			end

			if State.Rig then
				State.Rig:UpdateBonesFollowRig(rig)
			end
		end
	end

	if State.Axis and State.Axis:GetSelectedBone() then
		State.Axis:RefreshAxis()
	end
end

local function addObjectOrRig()
	if not UI.isAnimatorActive() then
		return
	end

	local selected = Selection:Get()[1]
	if not selected then
		Notification.show(
			"NOTHING SELECTED",
			"Select a rig or an object to add it to the timeline."
		)
		return
	end

	Project.addSelectionToTimeline()
end

local function openArmaturePanel()
	local target = ArmatureImport.captureTarget and ArmatureImport.captureTarget()
	if not target then
		Notification.show(
			"SELECT A RIG",
			"Select one rig in the timeline or viewport before importing an armature."
		)
		return
	end

	ArmatureImport.open(target)
end

local function masterTarget()
	local item = State.Rig and State.Rig._lastClickedItem
	local part = item and item.linkedRigInstance or Selection:Get()[1]
	for _, rig in State.getAllRigs() do
		if part and (part == rig or typeof(part) == "Instance" and part:IsDescendantOf(rig)) then
			return rig
		end
	end

	return State.currentRig
end

local function toggleMaster()
	if not UI.isAnimatorActive() then
		return
	end

	local rig = masterTarget()
	if not MasterControl.root(rig) then
		return
	end

	local was = MasterControl.enabled(rig)

	local function apply(enabled)
		if not rig.Parent then
			return
		end

		MasterControl.setEnabled(rig, enabled)
		State.Timeline:CaptureDefaultPoseAdditive(rig)
		State.Timeline:InvalidateMotorListCache()
		LimbIK.invalidate(rig)
		State.Rig:CreateBonesForRig(rig)
		State.Rig:BuildRigHierarchy(State.currentRig)
		State.Timeline:ApplyPoseAtTime(rig, State.Timeline:GetState().CurrentTime)
		State.currentProjectSaved = false
	end

	apply(not was)
	History.record(function()
		apply(was)
	end, function()
		apply(not was)
	end, "Master Control")
end

local function addCamera()
	if not UI.isAnimatorActive() then
		Project.openEmptyProject(nil)
	end

	Project.finalizeCurrentManipulation()
	local name = CameraRig.nextName(State.getAllRigs())
	local view = workspace.CurrentCamera
	local rig = CameraRig.create(
		CameraRig.spawnFrame(
			CameraRig.spawnTarget(State),
			view and view.CFrame or CFrame.new(0, 5, 0)
		),
		name
	)
	rig.Parent = workspace
	CameraRig.organize(rig, Project.getProjectExportName())
	Project.addRigToTimeline(rig)

	local sourceRig = rig
	rig = require("rig").localOf(rig)
	if not table.find(State.getAllRigs(), rig) then
		sourceRig:Destroy()
		return
	end

	for _, item in State.Rig._orderedItems do
		if item.linkedRigInstance == rig.CamPart then
			State.Rig:SetSingleItemSelection(item)
			break
		end
	end
end

local function boot(plugin)
	require("NativeJoints").recover(workspace)
	if booted then
		return
	end

	booted = true
	CameraRig.organizeAll()
	Organization.subscribe(function(reason)
		if reason ~= "load" and reason ~= "reset" then
			State.currentProjectSaved = false
		end
	end)

	State.UIHelpers = UIHelpersModule.new({
		PluginGui = UI.EclipseGUI,
		mouse = State.mouse,
	})

	Notification.setNotificationFrame(UI.NotificationFrame)
	Alert.setRefs({
		alertFrame = UI.AlertFrame,
		animatorFrame = UI.AnimatorFrame,
		headerLabel = UI.HeaderLabel,
		descriptionLabel = UI.DescriptionLabel,
	})

	State.Timeline = TimelineStatic.Initialize({
		PluginGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		AnimatorFrames = UI.AnimatorFrames,
		Tabs = UI.Tabs,
		TimelineContainer = UI.TimelineContainer,
		Scale = UI.Scale,
		Fit = UI.Fit,
		KeysRoot = UI.KeysRoot,
		Misc = UI.Misc,
		GuidesFolder = UI.GuidesFolder,
		GuideTemplate = UI.GuideTemplate,
		TickFrame = UI.TickFrame,
		TickNumberContainer = UI.TickNumberContainer,
		TickTemplate = UI.TickTemplate,
		TopSelector = UI.TopSelector,
		DragBarHitbox = UI.DragBarHitbox,
		TopSelectorDragHitbox = UI.DragBarHitbox,
		TopSelectorLabel = UI.TopSelectorLabel,
		SelectorContainer = UI.SelectorContainer,
		SelectionBox = UI.SelectionBox,
		Selector = UI.Selector,
		BottomContainer = UI.AnimatorMain.BottomContainer,
		TopSlider = UI.TopSlider,
		LeftDrag = UI.LeftDrag,
		RightDrag = UI.RightDrag,
		FPSLabel = UI.FPSLabel,
		GetSetting = Data.getSetting,
		SetSetting = Data.setSetting,
		RefreshSelectionFilter = function()
			if State.Rig and State.Rig.onlyShowSelected then
				State.Rig:RefreshSelectionFilter()
			end
		end,
		SetSelectionFilter = function(enabled)
			if State.Rig then
				State.Rig:SetSelectionFilter(enabled)
			end
		end,
		TimeLabel = UI.TimeLabel,
		LoopButton = UI.LoopButton,
		RecordButton = UI.RecordButton,
		ProjectNameTextBox = UI.ProjectNameTextBox,
		GetAllRigs = State.getAllRigs,
		IsObjectMotorActive = function(motor)
			return State.activeObjectMotors[motor] == true
		end,
		TrackContainer = UI.TrackContainer,
		TrackTemplate = UI.TrackTemplate,
		RigListScroll = UI.RigListScroll,
		RigItemTemplate = UI.RigItemTemplate,
		UIHelpers = State.UIHelpers,
		Axis = AxisStatic,
		BeforePlayback = Project.finalizeCurrentManipulation,
		GetCurrentRig = function()
			return State.currentRig
		end,
		SetCurrentRigUnsaved = function()
			State.currentProjectSaved = false
		end,
		AnimSavesTemplate = UI.AnimSavesTemplate,
	})

	UI.FPSLabel = State.Timeline.refs.FPSLabel

	State.Rig = RigStatic.Initialize({
		FolderIcon = Assets.Folder,
		OpenItemSettings = PropertySettings.open,
		PropertySelection = function(motor)
			if State.ScaleGizmo then
				State.ScaleGizmo.select(motor)
			else
				PropertyGizmo.select(motor)
			end
		end,
		AddPropertyKey = PropertySettings.addFirstFreeKey,
		RequestRemoveRig = function(rig)
			if not UI.isAnimatorActive() then
				return
			end

			Confirm.open(
				UI.EclipseGUI,
				UI.RigItemTemplate,
				"REMOVE RIG",
				'Remove "'
					.. rig.Name
					.. '" from this animation? Its tracks and events will be removed.'
					.. (
						rig.Parent and " The rig stays in the workspace."
						or " The scene rig is missing."
					),
				"Remove",

				function()
					Project.removeRigFromTimeline(rig)
				end
			)
		end,
		RequestDeleteFolder = function(id)
			if not UI.isAnimatorActive() or not Organization.isFolder(id) then
				return
			end

			Confirm.open(
				UI.EclipseGUI,
				UI.RigItemTemplate,
				"DELETE FOLDER",
				"Delete this folder? Its contents will not be deleted. They will move up one level.",
				"Delete",

				function()
					if State.Rig then
						State.Rig:DeleteFolder(id)
					end
				end
			)
		end,
		Axis = AxisStatic,
		Timeline = State.Timeline,
		UIHelpers = State.UIHelpers,
		KeysRoot = UI.KeysRoot,
		RigListScroll = UI.RigListScroll,
		RigItemTemplate = UI.RigItemTemplate,
		GetExtraRigs = function()
			return State.extraRigs
		end,
		IsObjectMotorActive = function(motor)
			return State.activeObjectMotors[motor] == true
		end,
	})

	AxisStatic:Initialize(UI.AxisPackage, UI.AnimatorFrame)
	AxisStatic:SetGizmoMode(State.GizmoMode)
	AxisStatic:SetEnabledCheck(function()
		return UI.isAnimatorActive()
	end)
	State.Axis = AxisStatic

	OnionSkinStatic:Initialize({
		State = State,
		UI = UI,
		History = History,
		MotorMath = MotorMath,
	})
	State.OnionSkin = OnionSkinStatic

	KeyframeMenu.init({
		DropdownsFolder = UI.Dropdowns,
	})
	State.KeyframeMenu = KeyframeMenu

	Customize.init({
		ScreenGui = UI.EclipseGUI,
		GetSetting = Data.getSetting,
		SetSetting = Data.setSetting,
	})

	ArmatureImport.init({
		ScreenGui = UI.EclipseGUI,
	})
	ArmaturePropertiesEditor.init({
		ScreenGui = UI.EclipseGUI,
		HoverDialog = State.UIHelpers.hoverDialog,
		RigItemTemplate = UI.RigItemTemplate,
		GetRig = function()
			local selected = Selection:Get()[1]
			if selected then
				for _, rig in State.getAllRigs() do
					if selected == rig or selected:IsDescendantOf(rig) then
						return rig
					end
				end
			end

			local bone = State.Axis and State.Axis:GetSelectedBone()
			local source = bone and bone.Parent and bone.Parent:FindFirstChild("EclipseSourceRig")
			return source and source.Value or State.currentRig
		end,
		GetFrame = function()
			local s = State.Timeline:GetState()
			return State.Timeline:TimeToFrame(s.CurrentTime)
		end,
	})
	PhysicsWindow.init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
		Active = UI.isAnimatorActive,
		Finalize = Project.finalizeCurrentManipulation,
		AddObject = Project.addObjectToTimeline,
		AddRig = Project.addRigToTimeline,
		RefreshStructure = Project.refreshTimelineAfterStructureChange,
	})
	require("SmartBone").init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		State = State,
		Active = UI.isAnimatorActive,
	})
	require("customRest").init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		State = State,
		Active = UI.isAnimatorActive,
	})
	AnimationCleanup.init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
		Active = UI.isAnimatorActive,
		HoverDialog = State.UIHelpers.hoverDialog,
		Finalize = Project.finalizeCurrentManipulation,
	})
	BlenderImport.init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
		Active = UI.isAnimatorActive,
		TrackContainer = UI.TrackContainer,
		Finalize = Project.finalizeCurrentManipulation,
	})
	require("InputRouter").init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
		Active = UI.isAnimatorActive,
	})
	CameraPreview.init({
		PlaybackOwnsRefresh = true,
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
		Active = UI.isAnimatorActive,
	})
	CameraControls.init({
		ScreenGui = UI.EclipseGUI,
		State = State,
		Active = UI.isAnimatorActive,
		TrackContainer = UI.TrackContainer,
	})
	ImagePreviewer.init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
	})
	VideoWindow.init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
	})
	require("AboutEclipse").init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		GetSetting = Data.getSetting,
		SetSetting = Data.setSetting,
	})
	local creativeRefs = {
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
		Active = UI.isAnimatorActive,
		Finalize = Project.finalizeCurrentManipulation,
		Save = Export.saveProject,
		OpenSave = Export.openProjectSave,
		RigItemTemplate = UI.RigItemTemplate,
		AddRig = Project.addRigToTimeline,
		RemoveRig = Project.removeRigFromTimeline,
		RestoreRig = Project.restoreRigMembership,
		Batch = Project.batchStructure,
		RefreshStructure = Project.refreshTimelineAfterStructureChange,
	}
	require("ModuleExporter").init(
		setmetatable(
			{ Archive = Export.buildProjectArchive, Name = Project.getProjectExportName },
			{ __index = creativeRefs }
		)
	)
	require("MotionPaths").init(creativeRefs)
	require("AnimationLayers").init(creativeRefs)
	require("Organization").initCollections(creativeRefs)
	require("Subtitles").init(creativeRefs)
	require("MarkerHandles").init(creativeRefs)
	PartRigging.init(creativeRefs)
	ArmatureRemoval.init(
		setmetatable({ RigItemTemplate = UI.RigItemTemplate }, { __index = creativeRefs })
	)
	PropertySettings.init(setmetatable({
		Remove = function(rig)
			State.Rig.refs.RequestRemoveRig(rig)
		end,
	}, { __index = creativeRefs }))
	PropertyGizmo.init(
		setmetatable(
			{ Template = UI.EclipseGUI.Axis:FindFirstChild("Scale") },
			{ __index = creativeRefs }
		)
	)
	require("Transport").init(creativeRefs)
	require("PropertyEditing").init(creativeRefs)
	require("Faces").init(creativeRefs)
	GreasePencil.init(creativeRefs)
	require("Effects").init(creativeRefs)
	require("ObjectEditing").init(creativeRefs)
	require("InterpolationPanel").init(creativeRefs)
	LiveSession.init(setmetatable({ Save = Export.saveLiveProject }, { __index = creativeRefs }))
	Library.init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
		HoverDialog = State.UIHelpers.hoverDialog,
		Finalize = Project.finalizeCurrentManipulation,
		BuildPreview = Export.buildLibraryPreview,
		AddRig = Project.addRigToTimeline,
		RefreshStructure = function(rig)
			LimbIK.invalidate(rig)
			State.Rig:CreateBonesForRig(rig)
			State.Rig:BuildRigHierarchy(State.currentRig)
		end,
	})
	FileTools.init({ State = State, UI = UI, Plugin = plugin, Project = Project, Export = Export })
	ExportResults.init({
		Plugin = plugin,
		ScreenGui = UI.EclipseGUI,
		AnimatorFrame = UI.AnimatorFrame,
		State = State,
		Mouse = State.mouse,
	})
	GraphEditor.init({
		Plugin = plugin,
		Parent = UI.RootFrame,
		HoverDialog = State.UIHelpers.hoverDialog,
		OnOpen = Project.finalizeCurrentManipulation,
	})
	Shortcuts.init({
		GetSetting = Data.getInteractiveSetting,
		SetSetting = Data.queueInteractiveSetting,
		CanRetry = Data.canRetryInteractiveSettings,
	})
	local stopQE = Preferences.subscribe(function(key, value, previous)
		if key ~= "DisableCameraQE" or not value or previous == true then
			return
		end

		local ok, message = Shortcuts.setMany({
			JumpKeyframeLeft = { Key = "Q", Modifiers = {} },
			JumpKeyframeRight = {
				Key = "E",
				Modifiers = {},
			},
		}, true)
		local notify = require("Notification")
		if ok then
			notify.show(
				"KEYBINDS UPDATED",
				"Jump Keyframes Left and Jump Keyframes Right keybinds changed to Q/E",
				4
			)
		else
			notify.show("KEYBINDS NEED ATTENTION", message, 4)
		end
	end)
	UI.EclipseGUI.Destroying:Once(stopQE)
	SavedDefaults.init({ GetSetting = Data.getSetting, SetSetting = Data.setSetting })
	KeybindsEditor.init({ ScreenGui = UI.EclipseGUI })
	UI.EclipseGUI.Destroying:Once(KeybindsEditor.close)
	UI.EclipseGUI:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not UI.EclipseGUI.Enabled then
			KeybindsEditor.close()
			KeyframeMenu.close()
		end
	end)
	UI.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not UI.AnimatorFrame.Visible then
			KeybindsEditor.close()
			KeyframeMenu.close()
		end
	end)
	PreferencesEditor.init({
		ScreenGui = UI.EclipseGUI,
		HoverDialog = State.UIHelpers.hoverDialog,
		RigItemTemplate = UI.RigItemTemplate,
	})
	local unsubscribeChannels = Preferences.subscribe(function(key, value)
		if key ~= "TransformChannels" or not State.Timeline then
			return
		end

		if value then
			State.Timeline:EnsureTransformChannelStarts()
		end

		local timeline = State.Timeline
		local raw = timeline:GetState()
		table.clear(raw._motorUniform)
		table.clear(raw._motorHasScale)
		if raw._evaluationBuckets then
			table.clear(raw._evaluationBuckets)
		end

		table.clear(raw.SelectedChannelKeyframes)
		if State.Rig and State.Rig._selectedChannels then
			table.clear(State.Rig._selectedChannels)
		end

		if State.GraphEditor then
			State.GraphEditor.invalidate()
		end

		if State.currentRig then
			timeline:ApplyPoseAtTime(State.currentRig, raw.CurrentTime)
		end

		timeline:RefreshAllKeyframeVisuals()
		if State.Axis and State.Axis:GetSelectedBone() then
			State.Axis:RefreshAxis()
		end
	end)
	UI.EclipseGUI.Destroying:Once(unsubscribeChannels)
	local unsubscribeIKPreferences = Preferences.subscribe(refreshIKPreferences)
	UI.EclipseGUI.Destroying:Once(unsubscribeIKPreferences)
	UI.EclipseGUI:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not UI.EclipseGUI.Enabled then
			PartRigging.close()
			PreferencesEditor.close()
			ArmaturePropertiesEditor.close()
			Confirm.close(true)
		end
	end)
	UI.AnimatorFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not UI.AnimatorFrame.Visible then
			PreferencesEditor.close()
			ArmaturePropertiesEditor.close()
			Confirm.close(true)
		end
	end)

	local animatorBar = UI.AnimatorFrame:FindFirstChild("Bar")
	local animatorMenuButtons = animatorBar and animatorBar:FindFirstChild("MenuButtons")
	MenuBar.init({
		DocumentKind = Export.documentKind,
		MenuButtons = animatorMenuButtons,
		ExtraMenuButtons = { UI.MenuButtons },
		PrimaryFrame = UI.PrimaryFrame,
		DropdownsFolder = UI.Dropdowns,
		AnimatorFrame = UI.AnimatorFrame,
		Checks = {
			MasterControl = function()
				return MasterControl.enabled(masterTarget())
			end,
			Grid = CameraPreview.mainGridEnabled,
			FullCamera = CameraPreview.isFull,
		},
		Actions = {
			ToggleOnionSkin = function()
				if State.OnionSkin then
					State.OnionSkin:Toggle()
				end
			end,
			CaptureOnionSkin = function()
				if State.OnionSkin then
					State.OnionSkin:Capture()
				end
			end,
			ApplyOnionSkin = function()
				if State.OnionSkin then
					State.OnionSkin:ApplyToRig()
				end
			end,
			ClearOnionSkin = function()
				if State.OnionSkin then
					State.OnionSkin:Clear()
				end
			end,
			GroupKeyframes = function()
				if State.Timeline then
					State.Timeline:GroupSelectedKeyframes()
				end
			end,
			UngroupKeyframes = function()
				if State.Timeline then
					State.Timeline:UngroupSelectedKeyframes()
				end
			end,
			UngroupAllKeyframes = function()
				if State.Timeline then
					State.Timeline:UngroupSelectedKeyframes(true)
				end
			end,
			MasterControl = toggleMaster,
			ExportAnimation = Export.exportCurrentAnimation,
			ExportResults = ExportResults.open,
			ImportToRig = FileTools.openImport,
			FitTimeline = function()
				State.Timeline:FitTimeline()
			end,
			AnimationSettings = FileTools.openSettings,
			Hide = Visibility.toggle,
			Undo = EditActions.Undo,
			Redo = EditActions.Redo,
			BakeAnimation = Export.openBake,
			StretchFrames = function()
				require("fill").open("stretch")
			end,
			FillFrames = function()
				require("fill").open("fill")
			end,
			CopyKeys = EditActions.CopyKeys,
			PasteKeys = EditActions.PasteKeys,
			PasteFlipped = EditActions.PasteFlipped,
			ReverseKeys = EditActions.ReverseKeys,
			ReversePaste = EditActions.ReversePaste,
			SelectAll = EditActions.SelectAll,
			DeselectAll = EditActions.DeselectAll,
			Customization = Customize.open,
			AboutEclipse = require("AboutEclipse").open,
			Preferences = PreferencesEditor.open,
			MotionPaths = require("MotionPaths").toggle,
			Keybinds = KeybindsEditor.open,
			DefaultEasing = KeyframeMenu.openDefaults,
			OpenInterpolation = KeyframeMenu.openInterpolation,
			GraphEditor = GraphEditor.toggle,
			ArmatureControls = ArmaturePropertiesEditor.open,
			AddObject = addObjectOrRig,
			DeleteItem = function()
				if UI.isAnimatorActive() then
					require("SelectionBridge").selected()
				end
			end,
			AddCamera = addCamera,
			AddVignette = function()
				State.EffectsWindow.open("Vignette")
			end,
			AddLetterbox = function()
				State.EffectsWindow.open("Letterbox")
			end,
			AddScreenCover = function()
				State.EffectsWindow.open("Screen Cover")
			end,
			AddImpactFrames = function()
				State.EffectsWindow.open("Impact Frames")
			end,
			AddCameraShake = function()
				State.EffectsWindow.open("Camera Shake")
			end,
			Grid = CameraPreview.toggleMainGrid,
			GridSettings = CameraPreview.toggleGridSettings,
			FullCamera = CameraPreview.toggleFull,
			EclipseVideo = VideoWindow.toggle,
			ImagePreviewer = ImagePreviewer.toggle,
			AnimationLayers = require("AnimationLayers").toggle,
			BoneCollection = require("Organization").toggleCollections,
			DynamicParenter = function()
				require("Targets").toggleParenter()
			end,
			Subtitles = require("SubtitleEditor").toggle,
			LiveSession = LiveSession.toggle,
			GreasePencil = GreasePencil.toggle,
			AnimationCleanup = AnimationCleanup.toggle,
			ClearTransform = AnimationCleanup.clearTransform,
			BoneSettings = function()
				require("IKPanel").open()
			end,
			EditPivot = function()
				require("Transport").toggle()
			end,
			Physics = PhysicsWindow.toggle,
			SmartBone = require("SmartBone").toggle,
			AutoIK = require("customRest").toggle,
			SaveProject = Export.saveProject,
			SaveProjectAs = FileTools.openSaveAs,
			Recovery = require("Recovery").openAutosaves,
			SaveAndCloseProject = Export.saveAndCloseProject,
			ModuleExporter = require("ModuleExporter").open,
			AddEffects = function()
				State.EffectsWindow.open()
			end,
			AddFolder = function()
				if UI.isAnimatorActive() and State.Rig then
					State.Rig:CreateFolder()
				end
			end,
			RigParts = PartRigging.open,
			BoneControls = PartRigging.openBoneControls,
			AddArmature = openArmaturePanel,
			RemoveArmature = ArmatureRemoval.open,
		},
	})

	Theme.init({
		UpdateSetting = Data.updateSetting,
		ScreenGui = UI.EclipseGUI,
		GetSetting = Data.getSetting,
		SetSetting = Data.setSetting,
		TimelineState = RawTimelineState,
		GetTimeline = function()
			return State.Timeline
		end,
	})

	require("Recovery").initAutosave(setmetatable({
		HomeMenu = UI.MenuButtons,
		Archive = Export.buildRecoveryArchive,
		Name = Project.getProjectExportName,
	}, { __index = creativeRefs }))

	task.defer(function()
		if State.Timeline then
			State.Timeline:BuildTimelineUI(function()
				return State.currentRig
			end)
			State.Timeline:UpdatePlayhead()
		end
	end)
end

ModuleInit.boot = boot

return ModuleInit
