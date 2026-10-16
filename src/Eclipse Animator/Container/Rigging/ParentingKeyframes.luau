--!nocheck
-- riftkuro

local require = require(script:FindFirstAncestor("Container").Require)

local BlenderEdit = require("BlenderEdit")
local TimelineState = require("RawState").Timeline
local Parenting = require("Parenting")
local GraphCurves = require("GraphCurves")
local LimbIK = require("LimbIK")
local HeadStabilizer = require("HeadStabilizer")
local History = require("History")

return function(Timeline)
	function Timeline:IsParentedAtTime(motor, time)
		local link = require("Target").childAt(motor, time)
		if link then
			return not link.world
		end

		return LimbIK.isDriven(motor, time)
			or Parenting.isParentedAt(
				motor,
				TimelineState.Keyframes[motor],
				time,
				TimelineState.ParentingDefaults[motor]
			)
	end

	function Timeline:CaptureKeyframeParenting(motor, keyData, c0, skipChildCapture)
		if typeof(keyData.Parented) ~= "boolean" then
			local previous = nil
			for _, candidate in pairs(TimelineState.Keyframes[motor] or {}) do
				if
					candidate ~= keyData
					and not candidate.GraphOnly
					and not candidate.Disabled
					and candidate.Time <= keyData.Time
					and (not previous or candidate.Time > previous.Time)
				then
					previous = candidate
				end
			end

			keyData.Parented =
				Parenting.keyIsParented(motor, previous, TimelineState.ParentingDefaults[motor])
		end

		if keyData.Parented then
			keyData.WorldCFrame = nil
		else
			local parentMotor = TimelineState.MotorByPart[Parenting.realPart0(motor)]
			local parentWorld = parentMotor
					and Parenting.worldOf(parentMotor, TimelineState.MotorByPart)
				or motor.Part0.CFrame
			keyData.WorldCFrame = parentWorld * c0 * motor.C1:Inverse()
		end

		LimbIK.captureKey(motor, keyData)
		HeadStabilizer.captureKey(motor, keyData, c0)
		if not skipChildCapture then
			require("Target").capture(motor, keyData, c0)
		end

		keyData.MasterWorld = keyData.WorldCFrame and require("MasterControl").worldDelta(motor)
			or nil
		GraphCurves.invalidate(TimelineState.Keyframes[motor])
	end

	function Timeline:RefreshParentingControls(time, isParentedAt, childAt)
		time = time or TimelineState.CurrentTime
		for button, entry in pairs(self._parentingControls or {}) do
			if not button.Parent then
				self._parentingControls[button] = nil
			else
				local parented
				if isParentedAt then
					parented = isParentedAt(entry.motor, time)
				end

				if parented == nil then
					parented = self:IsParentedAtTime(entry.motor, time)
				end

				local link = require("Target").childAt(entry.motor, time)
				if link then
					parented = not link.world
				end

				local driven = LimbIK.isDriven(entry.motor, time)
					or HeadStabilizer.isEnabled(entry.motor, time)
				local child = (not childAt or childAt(entry.motor, time))
					and require("Target").childAt(entry.motor, time) ~= nil
				if entry.parented ~= parented or entry.driven ~= driven or entry.child ~= child then
					entry.parented, entry.driven, entry.child = parented, driven, child
					entry.refresh(parented, driven, child)
				end
			end
		end
	end

	function Timeline:RegisterParentingControl(button, motor, refresh, rig)
		self._parentingControls = self._parentingControls or setmetatable({}, { __mode = "k" })
		local parented = self:IsParentedAtTime(motor, TimelineState.CurrentTime)
		LimbIK.getRig(rig)
		local driven = LimbIK.isDriven(motor, TimelineState.CurrentTime)
			or HeadStabilizer.isEnabled(motor, TimelineState.CurrentTime)
		local child = require("Target").childAt(motor, TimelineState.CurrentTime) ~= nil
		self._parentingControls[button] = {
			motor = motor,
			refresh = refresh,
			parented = parented,
			driven = driven,
			child = child,
			rig = rig,
		}
		refresh(parented, driven, child)
	end

	function Timeline:SwitchParentingAtCurrentTime(motor, rig)
		if BlenderEdit.blocked() then
			return
		end

		if not motor or not motor.Parent or not rig or motor:GetAttribute("EclipseDisabled") then
			return
		end

		if require("Targets").switchSpace(motor, rig) then
			return
		end

		local driven = LimbIK.drivingChain(motor, TimelineState.CurrentTime)
		if driven then
			return self:SwitchIKAtCurrentTime(
				driven.owner,
				rig,
				{ motor = motor, parented = false }
			)
		end

		if HeadStabilizer.isEnabled(motor, TimelineState.CurrentTime) then
			return
		end

		TimelineState.Playing = false
		self:CaptureDefaultPoseAdditive(rig)
		local frame = self:TimeToFrame(TimelineState.CurrentTime)
		local time = self:FrameToTime(frame)
		TimelineState.CurrentTime = time
		self:ApplyPoseAtTime(rig, time)
		local parented = not self:IsParentedAtTime(motor, time)
		local before = self:_snapshotMotorBucket(motor)
		local c0 = motor.C0
		local world = Parenting.worldOf(motor, TimelineState.MotorByPart)
		local sanitize = self.refs.UIHelpers.SanitizeName
		self:RecordKeyframeForMotorAtCurrentTime(motor.Part1, motor, c0, nil, sanitize)
		local key = TimelineState.Keyframes[motor][frame]
		key.Parented = parented
		key.WorldCFrame = not parented and world or nil
		key.MasterWorld = not parented and require("MasterControl").worldDelta(motor) or nil
		key.PathTangentIn = nil
		key.PathTangentOut = nil
		GraphCurves.invalidate(TimelineState.Keyframes[motor])
		local after = self:_snapshotMotorBucket(motor)

		local function refresh()
			self:ApplyPoseAtTime(rig, TimelineState.CurrentTime)
			self:RefreshAllKeyframeVisuals()
			self:RefreshAllChannelDiamondColors()
			if self.refs.SetCurrentRigUnsaved then
				self.refs.SetCurrentRigUnsaved()
			end
		end

		History.record(function()
			self:_restoreMotorBucket(motor, before)
			refresh()
		end, function()
			self:_restoreMotorBucket(motor, after)
			refresh()
		end, "Switch " .. motor.Part1.Name .. " to " .. (parented and "Parent" or "World"), frame)
		refresh()
	end
end
