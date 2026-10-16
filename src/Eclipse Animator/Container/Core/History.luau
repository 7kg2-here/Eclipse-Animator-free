--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)
local Shortcuts = require("Shortcuts")
local BlenderEdit = require("BlenderEdit")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local UserInputService = require("UserInputService")
local RunService = game:GetService("RunService")

local GraphRootState = require("State")
local History = {}

local undoStack = {}
local redoStack = {}
local maxSize = 1000

local applyingUndoRedo = false
local connections = {}
local onNotify = nil
local listeners = {}

local function changed()
	for callback in listeners do
		task.defer(callback)
	end
end

function History.subscribe(callback)
	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

local jumpToFrameCallback = nil
local activeCheckFn = nil
local beforeUndoRedo = nil
local shortcutHeld = {}

function History.isApplying()
	return applyingUndoRedo
end

local guardCallbacks = {}
local guardCleanupCallback = nil

local function push(stack, item)
	table.insert(stack, item)
	if #stack > maxSize then
		table.remove(stack, 1)
	end
end

local function isActive()
	if GraphRootState.WorkspaceSelection then
		return false
	end

	if GraphRootState.GraphEditor and GraphRootState.GraphEditor.hasFocus() then
		return false
	end

	if GraphRootState.CameraPreview and GraphRootState.CameraPreview.isFull() then
		return true
	end

	if not activeCheckFn then
		return true
	end

	local ok, result = pcall(activeCheckFn)
	return ok and result == true
end

local function resetStudioWaypoints(force)
	if force or ChangeHistoryService:GetCanUndo() or ChangeHistoryService:GetCanRedo() then
		ChangeHistoryService:SetWaypoint("EclipseAnimator_Reset_Begin")
		ChangeHistoryService:SetWaypoint("EclipseAnimator_Reset_End")
		ChangeHistoryService:ResetWaypoints()
	end
end

local function wipeStudioHistory()
	pcall(resetStudioWaypoints)
end

function History.protectSavedAnimations()
	local ok, err = pcall(resetStudioWaypoints, true)
	if not ok then
		warn("Eclipse could not protect saved animations from Studio undo:", err)
	end

	return ok
end

local function jumpIfNeeded(entry, direction)
	if not entry then
		return
	end

	if not jumpToFrameCallback then
		return
	end

	local target = nil
	if direction == "undo" and entry.undoContextFrame ~= nil then
		target = entry.undoContextFrame
	elseif direction == "redo" and entry.redoContextFrame ~= nil then
		target = entry.redoContextFrame
	else
		target = entry.contextFrame
	end

	if target == nil then
		return
	end

	pcall(jumpToFrameCallback, target)
end

function History.record(undoFn, redoFn, description, contextFrame, redoContextFrame)
	if type(undoFn) ~= "function" or type(redoFn) ~= "function" then
		warn("History.record: undoFn and redoFn must be functions")
		return
	end

	if applyingUndoRedo then
		return
	end

	local undoCF, redoCF
	if type(contextFrame) == "table" then
		undoCF = contextFrame.undo
		redoCF = contextFrame.redo
	else
		undoCF = contextFrame
		redoCF = redoContextFrame
	end

	local raw = require("RawState").Timeline
	local layerId = raw.AnimationLayers and raw.AnimationLayers.active
	local master = raw.AnimationLayers and raw.AnimationLayers.master
	local activeByRig = raw.AnimationLayers and table.clone(raw.AnimationLayers.activeByRig or {})

	local function bound(fn)
		return function()
			return require("Layers").history(layerId, fn, master, activeByRig)
		end
	end

	local entry = {
		undo = bound(undoFn),
		redo = bound(redoFn),
		description = description or "Action",
		contextFrame = undoCF,
		undoContextFrame = undoCF,
		redoContextFrame = (redoCF ~= nil) and redoCF or undoCF,
		afterUndo = type(contextFrame) == "table" and contextFrame.afterUndo or nil,
		afterRedo = type(contextFrame) == "table" and contextFrame.afterRedo or nil,
	}

	push(undoStack, entry)
	table.clear(redoStack)

	wipeStudioHistory()
	changed()
end

function History.undo()
	local picker = require("Picker")
	if picker.isOpen() then
		if BlenderEdit.blocked(true) then
			return false
		end

		return picker.undo()
	end

	if GraphRootState.PivotEditor and GraphRootState.PivotEditor.isActive() then
		GraphRootState.PivotEditor.undo()
		return
	end

	if
		GraphRootState.LiveSession
		and GraphRootState.LiveSession.isJoined()
		and GraphRootState.LiveSession.undo
	then
		task.spawn(GraphRootState.LiveSession.undo)
		return
	end

	if BlenderEdit.blocked(true) then
		return
	end

	if applyingUndoRedo then
		return false, nil
	end

	if GraphRootState.GreasePencil and GraphRootState.GreasePencil.isDrawing() then
		GraphRootState.GreasePencil.cancelStroke()
	end

	if beforeUndoRedo then
		beforeUndoRedo()
	end

	local action = table.remove(undoStack)
	if not action then
		if guardCleanupCallback then
			pcall(guardCleanupCallback)
		end

		return false, nil
	end

	applyingUndoRedo = true
	local ok, err = pcall(function()
		action.undo()
		jumpIfNeeded(action, "undo")
		if action.afterUndo then
			action.afterUndo()
		end
	end)
	applyingUndoRedo = false

	if not ok then
		warn("History undo failed:", err)
		push(undoStack, action)
		return false, nil
	end

	push(redoStack, action)
	pcall(function()
		require("motionPath").markDirty()
	end)

	wipeStudioHistory()
	changed()
	return true, action.description
end

function History.redo()
	local picker = require("Picker")
	if picker.isOpen() then
		if BlenderEdit.blocked(true) then
			return false
		end

		return picker.redo()
	end

	if GraphRootState.PivotEditor and GraphRootState.PivotEditor.isActive() then
		GraphRootState.PivotEditor.redo()
		return
	end

	if
		GraphRootState.LiveSession
		and GraphRootState.LiveSession.isJoined()
		and GraphRootState.LiveSession.redo
	then
		task.spawn(GraphRootState.LiveSession.redo)
		return
	end

	if BlenderEdit.blocked(true) then
		return
	end

	if applyingUndoRedo then
		return false, nil
	end

	if GraphRootState.GreasePencil and GraphRootState.GreasePencil.isDrawing() then
		GraphRootState.GreasePencil.cancelStroke()
	end

	if beforeUndoRedo then
		beforeUndoRedo()
	end

	local action = table.remove(redoStack)
	if not action then
		return false, nil
	end

	applyingUndoRedo = true
	local ok, err = pcall(function()
		action.redo()
		jumpIfNeeded(action, "redo")
		if action.afterRedo then
			action.afterRedo()
		end
	end)
	applyingUndoRedo = false

	if not ok then
		warn("History redo failed:", err)
		push(redoStack, action)
		return false, nil
	end

	push(undoStack, action)
	pcall(function()
		require("motionPath").markDirty()
	end)

	wipeStudioHistory()
	changed()
	return true, action.description
end

function History.clear()
	table.clear(undoStack)
	table.clear(redoStack)
	History.protectSavedAnimations()
end

function History.hasAnimationEdits()
	for _, entry in undoStack do
		if entry.description ~= "Add rig" then
			return true
		end
	end

	return false
end

function History.canUndo()
	return #undoStack > 0
end

function History.canRedo()
	return #redoStack > 0
end

function History.getStats()
	return {
		undo = #undoStack,
		redo = #redoStack,
		max = maxSize,
		undoTotal = #undoStack,
		redoTotal = #redoStack,
	}
end

function History.setMaxSize(n)
	maxSize = math.max(1, math.floor(n))
end

function History.setNotifyHandler(fn)
	onNotify = fn
end

function History.setJumpToFrame(fn)
	jumpToFrameCallback = fn
end

function History.setGuardCleanup(fn)
	guardCleanupCallback = fn
end

function History.setBeforeUndoRedo(fn)
	beforeUndoRedo = fn
end

function History.setActiveCheck(fn)
	activeCheckFn = fn
end

function History.setGuardCallbacks(cbs)
	guardCallbacks = cbs or {}
end

function History.setGuardExpiry(_seconds) end

function History.armGuard() end

local function isCtrlHeld()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function isShiftHeld()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

function History.init(_markerInst)
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)

	wipeStudioHistory()

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, _gameProcessed)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end

			if UserInputService:GetFocusedTextBox() then
				return
			end

			if not isActive() then
				return
			end

			local action
			if
				Shortcuts.matches("Redo", input)
				or Shortcuts.matches("RedoAlternate", input)
				or Shortcuts.matches("RedoShift", input)
			then
				action = History.redo
			elseif
				Shortcuts.matches("Undo", input) or Shortcuts.matches("UndoAlternate", input)
			then
				action = History.undo
			end

			if action and not shortcutHeld[input.KeyCode] then
				shortcutHeld[input.KeyCode] = true
				action()
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			shortcutHeld[input.KeyCode] = nil
		end)
	)
	table.insert(
		connections,
		UserInputService.WindowFocusReleased:Connect(function()
			table.clear(shortcutHeld)
		end)
	)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			for key in shortcutHeld do
				if not UserInputService:IsKeyDown(key) then
					shortcutHeld[key] = nil
				end
			end

			if not isActive() then
				return
			end

			wipeStudioHistory()
		end)
	)
end

function History.disconnect()
	table.clear(shortcutHeld)
	for _, c in connections do
		c:Disconnect()
	end

	table.clear(connections)
end

return History
