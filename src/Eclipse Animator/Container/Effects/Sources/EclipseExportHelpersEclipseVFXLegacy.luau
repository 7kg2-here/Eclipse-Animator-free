--!nocheck
-- riftkuro

return function(require)
local sharedLibraries = {
EclipseRGB = require("../Shared/EclipseRGB"),
EclipseOklab = require("../Shared/EclipseOklab"),
EclipsePromise = require("../Shared/EclipsePromise"),
EclipseShake = require("../Shared/EclipseShake"),
}

	return function(env, emitChild)
		local game, workspace, task, os, math, Random, Instance, typeof, coroutine, shared =
			env.game,
			env.workspace,
			env.task,
			env.os,
			env.math,
			env.Random,
			env.Instance,
			env.typeof,
			env.coroutine,
			env.shared
		local type = env.type
		local warn = env.warn
		local taskBase = task
		local pendingTasks = {}
		task = table.clone(taskBase)
		for _, method in { "spawn", "defer", "delay" } do
			task[method] = function(first, second, ...)
				local delay = method == "delay" and first or nil
				local fn = method == "delay" and second or first
				local args = method == "delay" and table.pack(...) or table.pack(second, ...)
				local token = {}
				pendingTasks[token] = true
				local function call()
					local ok, err = pcall(function()
						if type(fn) == "thread" then
							local good, result = coroutine.resume(fn, table.unpack(args, 1, args.n))
							if not good then
								error(result)
							end
						else
							fn(table.unpack(args, 1, args.n))
						end
					end)
					pendingTasks[token] = nil
					if not ok then
						warn(err)
					end
				end
				local thread = method == "delay" and taskBase.delay(delay, call)
					or taskBase[method](call)
				if pendingTasks[token] then
					pendingTasks[token] = thread
				end
				return thread
			end
		end
		local libraryEnvironment = setmetatable({ task = task }, { __index = env })
local factories, cache = {}, {}
		local function getModule(name)
			if cache[name] ~= nil then
				return cache[name]
			end
			local value = assert(factories[name], name)()
			cache[name] = value
			return value
		end

		factories["EmitModule.effects.beam"] = function()
			local tween = getModule("EmitModule.mod.tween")
			local utility = getModule("EmitModule.mod.utility")

			local rng = Random.new()

			local function getLegacyWidths(obj: Beam, scale: number)
				local w0 = utility.getAttribute(obj, "Width0", obj.Width0, true) * scale
				local w1 = utility.getAttribute(obj, "Width1", obj.Width1, true) * scale

				local s_w0 = utility.getAttribute(obj, "StartWidth0", obj.Width0, true) * scale
				local s_w1 = utility.getAttribute(obj, "StartWidth1", obj.Width1, true) * scale

				return w0, w1, s_w0, s_w1
			end

			local beam = {}

			function beam.emit(ref: Beam, obj: Beam, scope: utility.scope, scale: number)
				local a1, a2, a3, a4 = getLegacyWidths(ref, scale)

				local w1 = utility.getAttribute(ref, "Width0_Start", a3)
				local w2 = utility.getAttribute(ref, "Width0_End", a1)
				local w3 = utility.getAttribute(ref, "Width1_Start", a4)
				local w4 = utility.getAttribute(ref, "Width1_End", a2)

				local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

				local legacy_duration = utility.getAttribute(ref, "Duration", 1, true)
				local legacy_tpScale = utility.getAttribute(ref, "EndTransparencyScale", 1, true)

				local durationRange = utility.getRangeAttribute(
					ref,
					"EffectDuration",
					NumberRange.new(legacy_duration, legacy_duration),
					NumberRange.new(0, math.huge)
				)

				local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

				local tStart, tEnd =
					utility.getAttribute(ref, "Transparency_Scale_Start", 1),
					utility.getAttribute(ref, "Transparency_Scale_End", legacy_tpScale)

				local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
				local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

				local baseTexSpeed = obj.TextureSpeed

				task.wait(emitDelay)

				obj.Enabled = true

				local currentSpeed = 1

				local speedTween

				if speedStart ~= speedEnd then
					speedTween = tween.fromParams(
						utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
						utility.getAttribute(obj, "Speed_Duration", 0.1),
						function(alpha, deltaTime)
							currentSpeed = utility.lerp(speedStart, speedEnd, alpha)

							obj.TextureSpeed = baseTexSpeed * currentSpeed

							return deltaTime
						end
					)

					table.insert(scope, speedTween)
				end

				local function setTScale(tscale: number)
					obj.Transparency = utility.scaleNumberSequence(
						ref.Transparency,
						function(value, envelope)
							local base = tscale > 1 and (1 - value) or -value
							local offset = tscale > 1 and tscale - 1 or 1 - tscale

							return value + base * offset, envelope
						end
					)
				end

				if tStart ~= tEnd then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(
								ref,
								"Transparency_Scale_Curve",
								utility.default_bezier
							),
							duration,
							function(alpha, deltaTime)
								setTScale(utility.lerp(tStart, tEnd, alpha))
								return deltaTime * currentSpeed
							end,
							speedTween
						)
					)
				elseif tStart ~= 1 then
					setTScale(tStart)
				end

				if w1 ~= w2 then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(ref, "Width0_Curve", utility.default_bezier),
							duration,
							function(alpha, deltaTime)
								obj.Width0 = utility.lerp(w1, w2, alpha)
								return deltaTime * currentSpeed
							end,
							speedTween
						)
					)
				else
					obj.Width0 = w1
				end

				if w3 ~= w4 then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(ref, "Width1_Curve", utility.default_bezier),
							duration,
							function(alpha, deltaTime)
								obj.Width1 = utility.lerp(w3, w4, alpha)
								return deltaTime * currentSpeed
							end,
							speedTween
						)
					)
				else
					obj.Width1 = w3
				end

				tween.timer(duration, function(deltaTime, elapsed)
					return if currentSpeed > 0
							or (elapsed > 0 and speedTween and speedTween.Connected)
						then deltaTime * currentSpeed
						else nil
				end, speedTween, scope)
			end

			return beam
		end

		factories["EmitModule.effects.bezier"] = function()
			local HttpService = game:GetService("HttpService")
			local CollectionService = game:GetService("CollectionService")

			local tween = getModule("EmitModule.mod.tween")
			local shape = getModule("EmitModule.mod.shape")
			local utility = getModule("EmitModule.mod.utility")

			local Bezier = getModule("EmitModule.obj.Bezier")
			local EclipsePromise = getModule("EmitModule.pkg.EclipsePromise")
			local ObjectCache = getModule("EmitModule.obj.ObjectCache")

			local drawFuncMap = {
				Box = {
					Volume = shape.getPointWithinBox,
					Surface = shape.getPointOnBox,
				},

				Cylinder = {
					Volume = function(seed, cframe, size, normal, partial)
						return shape.getPointWithinCylinder(seed, 0, partial, cframe, size, normal)
					end,

					Surface = function(seed, cframe, size, normal, partial)
						return shape.getPointWithinCylinder(seed, 1, partial, cframe, size, normal)
					end,
				},

				Sphere = {
					Volume = function(seed, cframe, size, normal, partial)
						return shape.getPointWithinSphere(seed, 0, partial, cframe, size, normal)
					end,

					Surface = function(seed, cframe, size, normal, partial)
						return shape.getPointWithinSphere(seed, 1, partial, cframe, size, normal)
					end,
				},

				Disc = {
					Volume = function(seed, cframe, size, normal, partial)
						return shape.getPointWithinDisc(seed, 0, partial, cframe, size, normal)
					end,

					Surface = function(seed, cframe, size, normal, partial)
						return shape.getPointWithinDisc(seed, 1, partial, cframe, size, normal)
					end,
				},
			}

			local bezier = {}

			local part_cache: ObjectCache.ObjectCache?

			function bezier.init(cache)
				part_cache = cache
			end

			function bezier.deinit()
				part_cache = nil
			end

			function bezier.emit(
				ref: Attachment,
				refObj: Part,
				scope: utility.scope,
				mustEmit: boolean?
			)
				local root = ref:FindFirstChild("Points")

				if not root or not root:IsA("Attachment") or not part_cache then
					return
				end

				local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)
				local emitCount = utility.getAttribute(ref, "EmitCount", 1)
				local emitDuration = utility.getAttribute(ref, "EmitDuration", 0)
				local destroyDelay = utility.getAttribute(ref, "DestroyDelay", 0)

				local animDuration = utility.getRangeAttribute(
					ref,
					"Duration",
					NumberRange.new(1, 1),
					NumberRange.new(0, math.huge)
				)

				local face = utility.getEnumAttribute(
					ref,
					"ShapeFace",
					"Outward",
					{ "InAndOut", "Inward", "Outward" }
				)
				local spreadAngle = utility.getAttribute(ref, "SpreadAngle", vector.zero)

				local sync = utility.getAttribute(ref, "SyncPosition", false)

				local mirror = utility.getAttribute(ref, "MirrorPaths", true)
				local mirrorRot =
					utility.getAttribute(ref, "MirrorRotation", vector.create(0, 0, 180))

				local animFacePath = utility.getAttribute(ref, "FacePath", false)
				local animArcSpace = utility.getAttribute(ref, "ArcSpace", false)

				local partial = utility.getAttribute(ref, "ShapePartial", 1)

				local shape = utility.getEnumAttribute(
					ref,
					"Shape",
					"Box",
					{ "Box", "Cylinder", "Sphere", "Disc" }
				)
				local style =
					utility.getEnumAttribute(ref, "ShapeStyle", "Volume", { "Volume", "Surface" })

				local emission_direction = Enum.NormalId[utility.getEnumAttribute(
					ref,
					"EmissionDirection",
					"Top",
					{ "Top", "Bottom", "Left", "Right", "Front", "Back" }
				)]

				local projEnabled = utility.getAttribute(ref, "ProjectileEnabled", false)
				local projMatchEnd = utility.getAttribute(ref, "MatchEndDirection", false)

				local projSpeed = utility.getAttribute(ref, "ProjectileSpeed", 30)
				local projLifetime = utility.getRangeAttribute(
					ref,
					"ProjectileLifetime",
					NumberRange.new(1, 1),
					NumberRange.new(0, math.huge)
				)

				local hbEnabled = utility.getAttribute(ref, "HitboxEnabled", false)
				local hbColGroup = utility.getAttribute(ref, "HitboxCollisionGroup", "Default")
				local hbFilterTag = utility.getAttribute(ref, "HitboxFilterTag", "")
				local hbFilterType = utility.getAttribute(ref, "HitboxFilterType", "Exclude")
				local hbIgnoreCanCollide =
					utility.getAttribute(ref, "HitboxIgnoreCanCollide", false)

				local rotSpeedStartRange =
					utility.getRangeAttribute(ref, "RotSpeed_Start", NumberRange.new(0, 0))
				local rotSpeedEndRange =
					utility.getRangeAttribute(ref, "RotSpeed_End", NumberRange.new(0, 0))

				local minInitRot = utility.getAttribute(ref, "MinInitRot", vector.zero)
				local maxInitRot = utility.getAttribute(ref, "MaxInitRot", vector.zero)

				local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
				local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

				local drawFunc = drawFuncMap[shape] and drawFuncMap[shape][style]

				if not drawFunc then
					return
				end

				local promises = {}

				local useDuration = emitDuration > 0

				task.wait(emitDelay)

				if useDuration and not mustEmit then
					ref:SetAttribute("Enabled", true)

					if speedStart ~= speedEnd then
						ref:SetAttribute("SpeedTweening", true)

						table.insert(
							scope,
							tween.fromParams(
								utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
								utility.getAttribute(ref, "Speed_Duration", 0.1),
								function(alpha, deltaTime)
									ref:SetAttribute(
										"SpeedOverride",
										utility.lerp(speedStart, speedEnd, alpha)
									)
									return deltaTime
								end,
								nil,
								function()
									ref:SetAttribute("SpeedTweening", nil)
								end
							)
						)
					end

					task.wait(emitDuration)

					ref:SetAttribute("Enabled", false)
					ref:SetAttribute("SpeedOverride", nil)

					return
				elseif emitCount > 0 then
					local originSize: Vector3?
					local originCFrame: CFrame?

					local parent = ref.Parent

					if not parent then
						return
					end

					if not parent:IsA("BasePart") and not parent:IsA("Attachment") then
						parent = ref
					end

					if parent:IsA("BasePart") then
						originSize = parent.Size
						originCFrame = parent.CFrame
					elseif parent:IsA("Attachment") then
						originSize = Vector3.zero
						originCFrame = parent.WorldCFrame
					end

					if not originCFrame then
						return
					end

					local endPoint = ref:FindFirstChild("End")
					local endT1 = endPoint and endPoint:FindFirstChild("T1")

					if endPoint and not endPoint:IsA("Attachment") then
						endPoint = nil
					end

					if endT1 and not endT1:IsA("Attachment") then
						endT1 = nil
					end

					local points = utility.getBezierPoints(root)

					local rng = Random.new()
					local bezier = not endPoint and Bezier.new(points)

					local params = OverlapParams.new()
					params.MaxParts = 1
					params.FilterType = Enum.RaycastFilterType[hbFilterType]
					params.CollisionGroup = hbColGroup
					params.RespectCanCollide = not hbIgnoreCanCollide

					params:AddToFilter(CollectionService:GetTagged(hbFilterTag))

					if hbFilterType == "Exclude" then
						params:AddToFilter({
							workspace.Terrain,
							parent,
							root:FindFirstAncestorOfClass("Part"),
						})
					end

					for i = 1, emitCount do
						local rotSpeedStart =
							rng:NextNumber(rotSpeedStartRange.Min, rotSpeedStartRange.Max)
						local rotSpeedEnd =
							rng:NextNumber(rotSpeedEndRange.Min, rotSpeedEndRange.Max)

						local initRot = vector.create(
							rng:NextNumber(minInitRot.x, maxInitRot.x),
							rng:NextNumber(minInitRot.y, maxInitRot.y),
							rng:NextNumber(minInitRot.z, maxInitRot.z)
						)

						local duration = rng:NextNumber(animDuration.Min, animDuration.Max)
						local lifetime = projEnabled
							and rng:NextNumber(projLifetime.Min, projLifetime.Max)

						table.insert(
							promises,
							EclipsePromise.new(function(resolve)
								local cf = if parent:IsA("Attachment")
									then originCFrame * CFrame.new(
										Vector3.zero,
										Vector3.FromNormalId(emission_direction)
									).Rotation
									else drawFunc(
										nil,
										originCFrame,
										originSize,
										emission_direction,
										partial
									)

								local normal = Vector3.FromNormalId(emission_direction)

								local pitchAxis = normal:Cross(originCFrame.LookVector)

								if pitchAxis.Magnitude < 0.001 then
									pitchAxis = normal:Cross(originCFrame.UpVector)
								end

								local spread = CFrame.fromAxisAngle(
									normal,
									math.rad(rng:NextNumber(-spreadAngle.x, spreadAngle.x))
								) * CFrame.fromAxisAngle(
									pitchAxis,
									math.rad(rng:NextNumber(-spreadAngle.y, spreadAngle.y))
								)

								cf *= spread

								if
									face == "Inward"
									or (face == "InAndOut" and rng:NextInteger(0, 1) == 1)
								then
									cf *= CFrame.fromOrientation(0, math.pi, 0)
								end

								if
									endPoint
									and mirror
									and (cf.Position - endPoint.WorldPosition).Unit:Dot(
											cf.RightVector
										)
										>= 0
								then
									local rot = mirrorRot * utility.DEG_TO_RAD
									cf *= CFrame.fromOrientation(rot.x, rot.y, rot.z)
								end

								local bezier = bezier

								if endPoint then
									local pts = {}

									for i, pt in points do
										table.insert(
											pts,
											if i == (#points - 1)
												then endT1 and endT1.WorldPosition
													or endPoint.WorldPosition
												else if i == #points
													then endPoint.WorldPosition
													else cf * (pt - points[1])
										)
									end

									bezier = Bezier.new(pts)
								end

								local function getPos(alpha: number)
									local p = animArcSpace and bezier:getPositionArcSpace(alpha)
										or bezier:getPosition(alpha)

									if endPoint then
										return p
									else
										return cf * (p - points[1])
									end
								end

								local cacheId = HttpService:GenerateGUID(false)

								if not part_cache then
									resolve()
									return
								end

								local objAbstr = part_cache:get(cacheId)
								objAbstr.CFrame = CFrame.new(getPos(0))

								local obj = objAbstr._getReal()

								utility.copyProperties(refObj, obj, utility.COPY_PART_PROPERTIES)
								utility.copyProperties(
									refObj,
									obj,
									utility.COPY_EXTENDED_PART_PROPERTIES
								)

								do
									local clone = refObj:Clone()

									for _, child in clone:GetChildren() do
										child.Parent = obj
									end

									clone:Destroy()
								end

								local emitOnFinish = obj:FindFirstChild("EmitOnFinish")

								if emitOnFinish then
									emitOnFinish.Parent = nil
									table.insert(scope, emitOnFinish)
								end

								if shared.vfx and #obj:GetChildren() ~= 0 then
									local env = shared.vfx.emit(obj)
									table.insert(promises, env.Finished)
								end

								table.insert(scope, function()
									if part_cache then
										part_cache:free(cacheId)
									end
								end)

								local lastPos = Vector3.zero
								local lastVelocity = Vector3.zero

								local finished = false

								local function onFinish()
									if finished then
										return
									end

									finished = true

									local children = emitOnFinish and emitOnFinish:GetChildren()

									if children and #children ~= 0 then
										for _, child in children do
											child.Parent = obj
										end

										local env = shared.vfx.emit(table.unpack(children))

										env.Finished:finally(function()
											resolve()
										end)
									else
										resolve()
									end
								end

								local function shapecast()
									if not hbEnabled then
										return
									end

									local result = workspace:GetPartsInPart(obj, params)

									if result[1] then
										return true
									end

									return false
								end

								local function getOriginCFrame()
									local ocf = originCFrame

									if parent:IsA("BasePart") then
										ocf = parent.CFrame
									elseif parent:IsA("Attachment") then
										ocf = parent.WorldCFrame
									end

									return ocf
								end

								local didHit = false
								local prevCF = CFrame.identity

								local currentSpeed = speedStart
								local currentRotSpeed = rotSpeedStart

								local currentRot =
									CFrame.fromOrientation(initRot.x, initRot.y, initRot.z)

								local speedTween

								if
									speedStart ~= speedEnd
									and not ref:GetAttribute("SpeedOverride")
								then
									speedTween = tween.fromParams(
										utility.getAttribute(
											ref,
											"Speed_Curve",
											utility.default_bezier
										),
										utility.getAttribute(ref, "Speed_Duration", 0.1),
										function(alpha, deltaTime)
											currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
											return deltaTime
										end
									)

									table.insert(scope, speedTween)
								end

								if rotSpeedStart ~= rotSpeedEnd then
									table.insert(
										scope,
										tween.fromParams(
											utility.getAttribute(
												ref,
												"RotSpeed_Curve",
												utility.default_bezier
											),
											duration,
											function(alpha, deltaTime)
												currentRotSpeed =
													utility.lerp(rotSpeedStart, rotSpeedEnd, alpha)
												return deltaTime
													* (
														ref:GetAttribute("SpeedOverride")
														or currentSpeed
													)
											end,
											speedTween
										)
									)
								end

								table.insert(
									scope,
									tween.fromParams(
										utility.getAttribute(
											ref,
											"Easing_Curve",
											utility.linear_bezier
										),
										duration,
										function(alpha, deltaTime, elapsed)
											local pos1 = getPos(alpha)

											local newCF = CFrame.new(pos1)

											if animFacePath then
												local pos2 = getPos(
													math.clamp(
														(elapsed + (1 / 60)) / duration,
														0,
														1
													)
												)

												if pos1 ~= pos2 then
													newCF = CFrame.lookAt(pos1, pos2)
												else
													newCF *= prevCF.Rotation
												end
											end

											local add = initRot:Sign()
												* currentRotSpeed
												* utility.DEG_TO_RAD
												* deltaTime
											currentRot *= CFrame.fromOrientation(
												add.x,
												add.y,
												add.z
											)

											prevCF = newCF

											newCF *= currentRot

											if sync then
												objAbstr.CFrame = getOriginCFrame()
													* originCFrame:ToObjectSpace(newCF)
											else
												objAbstr.CFrame = newCF
											end

											lastVelocity = (pos1 - lastPos) / deltaTime
											lastPos = pos1

											local hit = shapecast()

											if hit then
												onFinish()
												didHit = true
												return nil
											end

											local speed = ref:GetAttribute("SpeedOverride")
												or currentSpeed

											currentSpeed = speed

											if
												speed == 0
												and (
													if speedTween
														then not speedTween.Connected
														else not ref:GetAttribute(
															"SpeedTweening"
														)
												)
											then
												return nil
											end

											if
												(projEnabled and alpha * duration < lifetime)
												or not projEnabled
											then
												return deltaTime * speed
											else
												onFinish()
												return nil
											end
										end,
										speedTween,
										function(organic)
											if not projEnabled or didHit then
												if organic then
													onFinish()
												end

												return
											end

											local dir = if projMatchEnd and endPoint
												then endPoint.WorldCFrame.LookVector
												else lastVelocity.Unit

											if dir ~= dir then
												dir = Vector3.zero
											end

											lastVelocity = dir * projSpeed

											local projectileOrigin = obj.Position
											local originCFrameAtProjectileInit = getOriginCFrame()

											tween.timer(
												lifetime,
												function(deltaTime, elapsed)
													if sync then
														objAbstr.CFrame = getOriginCFrame()
															* originCFrameAtProjectileInit:ToObjectSpace(
																CFrame.new(
																	projectileOrigin
																		+ lastVelocity * elapsed
																)
															)
													else
														objAbstr.CFrame = CFrame.new(
															projectileOrigin
																+ lastVelocity * elapsed
														) * obj.CFrame.Rotation
													end

													local hit = shapecast()

													if hit then
														onFinish()
														didHit = true
														return nil
													end

													local speed = ref:GetAttribute("SpeedOverride")
														or currentSpeed

													currentSpeed = speed

													return if speed > 0
															or (
																elapsed > 0
																and if speedTween
																	then speedTween.Connected
																	else ref:GetAttribute(
																		"SpeedTweening"
																	)
															)
														then deltaTime * speed
														else nil
												end,
												speedTween,
												scope,
												utility.RENDER_PRIORITY + scope.depth
											)

											if not didHit then
												onFinish()
											end
										end,
										true,
										utility.RENDER_PRIORITY + scope.depth
									)
								)
							end)
						)
					end

					EclipsePromise.all(promises):await()

					task.wait(destroyDelay)
				end
			end

			return bezier
		end

		factories["EmitModule.effects.camera_shake"] = function()
			local RunService = game:GetService("RunService")

			local tween = getModule("EmitModule.mod.tween")
			local utility = getModule("EmitModule.mod.utility")

			local EclipseShake = getModule("EmitModule.pkg.EclipseShake")

			local activeShakes = {}
			local totalShakeCF = CFrame.identity

			local function updateCamera()
				if #activeShakes == 0 then
					return
				end

				local camera = workspace.CurrentCamera

				if not RunService:IsRunning() then
					camera.CFrame *= totalShakeCF:Inverse()

					local cf = camera.CFrame
					local rx, ry = cf:ToOrientation()

					camera.CFrame = CFrame.new(cf.Position) * CFrame.fromOrientation(rx, ry, 0)
				end

				local totalPos = vector.zero
				local totalRot = CFrame.identity

				local stillActive = {}

				for _, v in activeShakes do
					if v.done then
						continue
					end

					totalPos += v.pos
					totalRot *= CFrame.Angles(v.rot.x, v.rot.y, v.rot.z)

					table.insert(stillActive, v)
				end

				activeShakes = stillActive

				local total = CFrame.new(totalPos) * totalRot

				if not RunService:IsRunning() then
					totalShakeCF = total
				end

				camera.CFrame *= total
			end

			local camera_shake = {}

			local conn
			local lastCameraCf

			function camera_shake.init()
				if conn then
					return
				end

				if RunService:IsRunning() then
					conn = RunService.Heartbeat:Connect(function()
						if not lastCameraCf then
							return
						end

						workspace.CurrentCamera.CFrame = lastCameraCf
					end)
				end

				RunService:BindToRenderStep(
					"forge_updateCameraShake",
					Enum.RenderPriority.Last.Value + 1,
					updateCamera
				)
			end

			function camera_shake.deinit()
				if conn then
					conn:Disconnect()
					conn = nil
				end

				RunService:UnbindFromRenderStep("forge_updateCameraShake")
			end

			function camera_shake.emit(ref: RayValue, scope: utility.scope)
				local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)
				local emitDuration = utility.getAttribute(ref, "EmitDuration", 0)

				local falloff = utility.getAttribute(ref, "Falloff", 30)

				local amplitude = utility.getAttribute(ref, "Amplitude", 2.5)
				local frequency = utility.getAttribute(ref, "Frequency", 0.2)

				local fadeInTime = utility.getAttribute(ref, "FadeInTime", 0.3)
				local fadeOutTime = utility.getAttribute(ref, "FadeOutTime", 2)
				local sustainTime = utility.getAttribute(ref, "SustainTime", 1)

				local posInfluence = utility.getAttribute(ref, "PositionInfluence", vector.one)
				local rotInfluence =
					utility.getAttribute(ref, "RotationInfluence", vector.one * 0.2)

				local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
				local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

				local sustained = emitDuration > 0

				local shake = EclipseShake.new()
				shake.Sustain = sustained
				shake.Amplitude = amplitude
				shake.Frequency = frequency
				shake.FadeInTime = fadeInTime
				shake.FadeOutTime = fadeOutTime
				shake.SustainTime = sustainTime
				shake.PositionInfluence = posInfluence
				shake.RotationInfluence = rotInfluence

				local currentSpeed = 1

				local elapsed = 0

				shake.TimeFunction = function()
					return elapsed
				end

				if speedStart ~= speedEnd then
					speedTween = tween.fromParams(
						utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
						utility.getAttribute(ref, "Speed_Duration", 0.1),
						function(alpha, deltaTime)
							currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
							return deltaTime
						end
					)

					table.insert(scope, speedTween)
				end

				table.insert(
					scope,
					RunService.RenderStepped:Connect(function(deltaTime)
						elapsed += deltaTime * currentSpeed
					end)
				)

				local obj = {
					done = false,
					pos = vector.zero,
					rot = vector.zero,
				}

				task.wait(emitDelay)

				table.insert(activeShakes, obj)

				local thread = coroutine.running()

				shake:BindToRenderStep(
					EclipseShake.NextRenderName(),
					utility.RENDER_PRIORITY + scope.depth,
					function(pos, rot, isDone)
						local camera = workspace.CurrentCamera

						lastCameraCf = camera.CFrame

						local origin = ref:FindFirstAncestorOfClass("Attachment")
							or ref:FindFirstAncestorWhichIsA("BasePart")

						if origin then
							local alpha = 1
								- math.clamp(
									(
										camera.CFrame.Position
										- (
											origin:IsA("Attachment") and origin.WorldPosition
											or origin.Position
										)
									).Magnitude / falloff,
									0,
									1
								)

							pos *= alpha
							rot *= alpha
						end

						obj.pos = pos
						obj.rot = rot
						obj.done = isDone

						if isDone then
							lastCameraCf = nil
							task.spawn(thread)
						end
					end
				)

				shake:Start()

				if sustained then
					task.wait(emitDuration)
					shake:StopSustain()
				end

				if not obj.done then
					coroutine.yield()
				end
			end

			return camera_shake
		end

		factories["EmitModule.effects.mesh"] = function()
			local RunService = game:GetService("RunService")
			local CollectionService = game:GetService("CollectionService")

			local tween = getModule("EmitModule.mod.tween")
			local utility = getModule("EmitModule.mod.utility")

			local EclipseOklab = getModule("EmitModule.mod.color.EclipseOklab")
			local EclipsePromise = getModule("EmitModule.pkg.EclipsePromise")

			local rng = Random.new()

			local mesh = {}

			function mesh.emit(
				ref: Model,
				obj: BasePart,
				scope: utility.scope,
				scale: number,
				mustEmit: boolean?
			)
				local start = ref:FindFirstChild("Start")
				local goal = ref:FindFirstChild("End")

				if
					not start
					or not goal
					or not start:IsA("BasePart")
					or not goal:IsA("BasePart")
					or (ref:GetAttribute("Enabled") and not mustEmit)
				then
					return
				end

				local legacy_duration = utility.getAttribute(ref, "Duration", 1, true)

				local durationRange = utility.getRangeAttribute(
					ref,
					"EffectDuration",
					NumberRange.new(legacy_duration, legacy_duration),
					NumberRange.new(0, math.huge)
				)

				local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

				local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)
				local emitDuration = utility.getAttribute(ref, "EmitDuration", 0, true)

				local legacy_isFlipbook = utility.getAttribute(ref, "Flipbook", false, true)
				local legacy_flipbookFadeOffset =
					utility.getAttribute(ref, "FlipbookFadeOffset", 0, true)

				do
					local prefix

					if legacy_isFlipbook or not start:FindFirstChildOfClass("Decal") then
						prefix = "Mesh_"
					else
						prefix = "Decal_"
					end

					local ts = ref:GetAttribute("StartTransparency")

					if ts ~= nil then
						ref:SetAttribute(prefix .. "StartTransparency", ts)
						ref:SetAttribute("StartTransparency", nil)
					end

					local te = ref:GetAttribute("EndTransparency")

					if te ~= nil then
						ref:SetAttribute(prefix .. "EndTransparency", te)
						ref:SetAttribute("EndTransparency", nil)
					end
				end

				local useEmitDuration = ref:GetAttribute("Enabled") ~= nil
					and ref:HasTag(utility.ENABLED_VFX_TAG)
					and duration > 0

				local legacy_decalST = utility.getAttribute(ref, "Decal_StartTransparency", 0, true)
				local legacy_decalET = utility.getAttribute(ref, "Decal_EndTransparency", 1, true)

				local partDefaultTp = 0

				do
					local decal = start and start:FindFirstChildOfClass("Decal")

					if decal then
						partDefaultTp = 1
					end
				end

				local legacy_meshST =
					utility.getAttribute(ref, "Mesh_StartTransparency", partDefaultTp, true)
				local legacy_meshET =
					utility.getAttribute(ref, "Mesh_EndTransparency", partDefaultTp, true)

				local sync = utility.getAttribute(ref, "SyncPosition", false)

				local speedStart = utility.getAttribute(ref, "Speed_Start", 1)
				local speedEnd = utility.getAttribute(ref, "Speed_End", 1)

				local tpStart = utility.getAttribute(ref, "Part_Transparency_Start", legacy_meshST)
				local tpEnd = utility.getAttribute(ref, "Part_Transparency_End", legacy_meshET)

				local spreadAngle = utility.getAttribute(ref, "SpreadAngle", vector.zero)

				local rotSpeedStartRange =
					utility.getRangeAttribute(ref, "Part_RotSpeed_Start", NumberRange.new(0, 0))
				local rotSpeedEndRange =
					utility.getRangeAttribute(ref, "Part_RotSpeed_End", NumberRange.new(0, 0))

				local rotAroundOrigin = utility.getAttribute(ref, "RotAroundOrigin", false)

				local minInitRot = utility.getAttribute(ref, "MinInitRot", vector.zero)
				local maxInitRot = utility.getAttribute(ref, "MaxInitRot", vector.zero)

				local rotSpeedStart = rng:NextNumber(rotSpeedStartRange.Min, rotSpeedStartRange.Max)
				local rotSpeedEnd = rng:NextNumber(rotSpeedEndRange.Min, rotSpeedEndRange.Max)

				local initRot = vector.create(
					rng:NextNumber(minInitRot.x, maxInitRot.x),
					rng:NextNumber(minInitRot.y, maxInitRot.y),
					rng:NextNumber(minInitRot.z, maxInitRot.z)
				) * utility.DEG_TO_RAD

				task.wait(emitDelay)

				if useEmitDuration and not mustEmit then
					ref:SetAttribute("Enabled", true)

					if speedStart ~= speedEnd then
						ref:SetAttribute("SpeedTweening", true)

						table.insert(
							scope,
							tween.fromParams(
								utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
								utility.getAttribute(ref, "Speed_Duration", 0.1),
								function(alpha, deltaTime)
									ref:SetAttribute(
										"SpeedOverride",
										utility.lerp(speedStart, speedEnd, alpha)
									)
									return deltaTime
								end,
								nil,
								function()
									ref:SetAttribute("SpeedTweening", nil)
								end
							)
						)
					end

					task.wait(emitDuration)

					ref:SetAttribute("Enabled", false)
					ref:SetAttribute("SpeedOverride", nil)

					return
				end

				local parent = ref:FindFirstAncestorOfClass("Attachment") or start
				local realObj = typeof(obj) == "table" and obj._getReal() or obj

				local function getOrigin()
					return parent:IsA("Attachment") and parent.WorldCFrame or parent.CFrame
				end

				local origin = getOrigin()
				local goalCFrameOffset = start.CFrame:ToObjectSpace(goal.CFrame)

				local currentSpeed = speedStart
				local currentRotSpeed = rotSpeedStart

				local currentRot = CFrame.fromOrientation(initRot.x, initRot.y, initRot.z)
				local currentCFrame = CFrame.identity

				local spread = CFrame.fromOrientation(
					math.rad(rng:NextNumber(-spreadAngle.x, spreadAngle.x)),
					math.rad(rng:NextNumber(-spreadAngle.y, spreadAngle.y)),
					0
				)

				local function updatePos(deltaTime: number)
					local o = sync and getOrigin() or origin
					local add = initRot:Sign() * currentRotSpeed * deltaTime

					currentRot *= CFrame.fromOrientation(add.x, add.y, add.z)

					local cf

					if rotAroundOrigin then
						cf = o * spread * currentRot * currentCFrame
					else
						cf = o * spread * currentCFrame * currentRot
					end

					cf *= currentRot

					obj.CFrame = cf
				end

				updatePos(0)

				do
					local id = utility.getRanomId()

					RunService:BindToRenderStep(
						id,
						utility.RENDER_PRIORITY + scope.depth,
						updatePos
					)

					table.insert(scope, function()
						RunService:UnbindFromRenderStep(id)
					end)
				end

				local promises = {}

				local emitOnFinish = obj:FindFirstChild("EmitOnFinish")

				if emitOnFinish then
					emitOnFinish.Parent = nil
					table.insert(scope, emitOnFinish)
				end

				if shared.vfx and #obj:GetChildren() ~= 0 then
					local env = shared.vfx.emit(obj)
					table.insert(promises, env.Finished)
				end

				local speedTween

				if speedStart ~= speedEnd and not ref:GetAttribute("SpeedOverride") then
					speedTween = tween.fromParams(
						utility.getAttribute(ref, "Speed_Curve", utility.default_bezier),
						utility.getAttribute(ref, "Speed_Duration", 0.1),
						function(alpha, deltaTime)
							currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
							return deltaTime
						end
					)

					table.insert(scope, speedTween)
				end

				if goalCFrameOffset ~= CFrame.identity then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(ref, "Part_CFrame_Curve", utility.default_bezier),
							duration,
							function(alpha, deltaTime)
								currentCFrame = CFrame.identity:Lerp(goalCFrameOffset, alpha)
								return deltaTime
									* (ref:GetAttribute("SpeedOverride") or currentSpeed)
							end,
							speedTween
						)
					)
				end

				if rotSpeedStart ~= rotSpeedEnd then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(ref, "Part_RotSpeed_Curve", utility.default_bezier),
							duration,
							function(alpha, deltaTime)
								currentRotSpeed = utility.lerp(rotSpeedStart, rotSpeedEnd, alpha)
								return deltaTime
									* (ref:GetAttribute("SpeedOverride") or currentSpeed)
							end,
							speedTween
						)
					)
				end

				if tpStart ~= tpEnd then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(
								ref,
								"Part_Transparency_Curve",
								utility.default_bezier
							),
							duration,
							function(alpha, deltaTime)
								obj.Transparency = utility.lerp(tpStart, tpEnd, alpha)
								return deltaTime
									* (ref:GetAttribute("SpeedOverride") or currentSpeed)
							end,
							speedTween
						)
					)
				else
					obj.Transparency = tpStart
				end

				local sizeStart, sizeEnd = start.Size * scale, goal.Size * scale

				if sizeStart ~= sizeEnd then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(ref, "Part_Size_Curve", utility.default_bezier),
							duration,
							function(alpha, deltaTime)
								obj.Size = sizeStart:Lerp(sizeEnd, alpha)
								return deltaTime
									* (ref:GetAttribute("SpeedOverride") or currentSpeed)
							end,
							speedTween
						)
					)
				else
					obj.Size = sizeStart
				end

				local startMesh = start:FindFirstChildOfClass("SpecialMesh")
				local goalMesh = goal:FindFirstChildOfClass("SpecialMesh")

				local objMesh = obj:FindFirstChildOfClass("SpecialMesh")

				if objMesh then
					if startMesh and goalMesh then
						local scaleStart, scaleEnd = startMesh.Scale * scale, goalMesh.Scale * scale

						if scaleStart ~= scaleEnd then
							table.insert(
								scope,
								tween.fromParams(
									utility.getAttribute(
										ref,
										"Mesh_Scale_Curve",
										utility.default_bezier
									),
									duration,
									function(alpha, deltaTime)
										objMesh.Scale = utility.lerp(scaleStart, scaleEnd, alpha)
										return deltaTime
											* (ref:GetAttribute("SpeedOverride") or currentSpeed)
									end,
									speedTween
								)
							)
						end
					else
						objMesh.Parent = nil

						table.insert(scope, function()
							objMesh.Parent = realObj
						end)
					end
				end

				local decals, flipbooks, fromToMap = utility.getMeshDecals(ref, obj)

				local longestFlipbookDuration = 0

				if legacy_isFlipbook then
					table.sort(decals, function(a, b)
						local x = a.Name:match("%d+") or 0
						local y = b.Name:match("%d+") or 0

						return tonumber(x) < tonumber(y)
					end)

					local displayDecal = Instance.new("Decal")

					displayDecal.Parent = realObj

					table.insert(scope, displayDecal)

					if legacy_flipbookFadeOffset > 0 then
						if legacy_decalST ~= legacy_decalET then
							table.insert(
								scope,
								tween.fromParams(
									utility.default_bezier,
									duration + legacy_flipbookFadeOffset,
									function(alpha, deltaTime)
										displayDecal.Transparency =
											utility.lerp(legacy_decalST, legacy_decalET, alpha)
										return deltaTime
											* (ref:GetAttribute("SpeedOverride") or currentSpeed)
									end,
									speedTween
								)
							)
						end
					end

					table.insert(
						scope,
						tween.fromParams(
							utility.default_bezier,
							duration,
							function(alpha, deltaTime)
								local index = math.max(math.round(#decals * alpha), 1)
								local target = decals[index]

								displayDecal.Texture = target.Texture

								displayDecal.Color3 = target.Color3
								displayDecal.ZIndex = target.ZIndex

								if legacy_flipbookFadeOffset == 0 then
									displayDecal.Transparency =
										utility.lerp(legacy_decalST, legacy_decalET, alpha)
									displayDecal.ZIndex = target.ZIndex
								end

								return deltaTime
									* (ref:GetAttribute("SpeedOverride") or currentSpeed)
							end,
							speedTween
						)
					)
				else
					for _, decal in decals do
						local from = decal
						local to = fromToMap[from]

						local decal_tpStart =
							utility.getAttribute(from, "Transparency_Start", legacy_decalST)
						local decal_tpEnd =
							utility.getAttribute(from, "Transparency_End", legacy_decalET)

						if decal_tpStart ~= decal_tpEnd then
							table.insert(
								scope,
								tween.fromParams(
									utility.getAttribute(
										from,
										"Transparency_Curve",
										utility.default_bezier
									),
									duration,
									function(alpha, deltaTime)
										decal.Transparency =
											utility.lerp(decal_tpStart, decal_tpEnd, alpha)
										return deltaTime
											* (ref:GetAttribute("SpeedOverride") or currentSpeed)
									end,
									speedTween
								)
							)
						else
							decal.Transparency = decal_tpStart
						end

						if from.Color3 ~= to.Color3 then
							table.insert(
								scope,
								tween.fromParams(
									utility.getAttribute(
										from,
										"Color_Curve",
										utility.default_bezier
									),
									duration,
									function(alpha, deltaTime)
										local a = EclipseOklab.fromSRGB(from.Color3)
										local b = EclipseOklab.fromSRGB(to.Color3)

										decal.Color3 = EclipseOklab.toSRGB(a:Lerp(b, alpha), true)

										return deltaTime
											* (ref:GetAttribute("SpeedOverride") or currentSpeed)
									end,
									speedTween
								)
							)
						end

						local flipbook = flipbooks[from]

						if flipbook then
							local changeDuration =
								utility.getAttribute(from, "Flipbook_Change_Duration", duration)

							if utility.getAttribute(from, "SyncDuration", false) then
								changeDuration = duration
							end

							if changeDuration > longestFlipbookDuration then
								longestFlipbookDuration = changeDuration
							end

							local temp = false

							if RunService:IsStudio() then
								for _, tag in CollectionService:GetTags(from) do
									if tag:match("^_local_flipbook_") then
										temp = true
										break
									end
								end
							end

							table.insert(
								scope,
								tween.fromParams(
									utility.getAttribute(
										from,
										"Flipbook_Change_Curve",
										utility.linear_bezier
									),
									changeDuration,
									function(alpha, deltaTime)
										local index = math.max(math.round(#flipbook * alpha), 1)
										decal.Texture =
											`{temp and "rbxtemp://" or "rbxassetid://"}{flipbook[index]}`

										return deltaTime
											* (ref:GetAttribute("SpeedOverride") or currentSpeed)
									end,
									speedTween
								)
							)
						end
					end
				end

				tween.timer(
					math.max(duration, longestFlipbookDuration) + legacy_flipbookFadeOffset,
					function(deltaTime, elapsed)
						local speed = ref:GetAttribute("SpeedOverride") or currentSpeed

						currentSpeed = speed

						return if speed > 0
								or (
									elapsed > 0
									and if speedTween
										then speedTween.Connected
										else ref:GetAttribute("SpeedTweening")
								)
							then deltaTime * speed
							else nil
					end,
					speedTween,
					scope
				)

				EclipsePromise.all(promises):await()

				local children = emitOnFinish and emitOnFinish:GetChildren()

				if children and #children ~= 0 then
					for _, child in children do
						child.Parent = realObj
					end

					local env = shared.vfx.emit(table.unpack(children))
					env.Finished:await()
				end
			end

			return mesh
		end

		factories["EmitModule.effects.particle"] = function()
			local tween = getModule("EmitModule.mod.tween")
			local utility = getModule("EmitModule.mod.utility")

			local particle = {}

			function particle.emit(ref: ParticleEmitter, obj: ParticleEmitter, scope: utility.scope)
				if ref.Enabled then
					ref.Enabled = false
				end

				local delay = utility.getAttribute(ref, "EmitDelay", 0)
				local count = utility.getAttribute(ref, "EmitCount", 1)
				local duration = utility.getAttribute(ref, "EmitDuration", 0)

				local useDuration = duration > 0

				if delay > 0 then
					task.wait(delay)
				end

				if useDuration then
					obj.Enabled = true
				end

				local timeScaleDuration = utility.getAttribute(ref, "TimeScale_Duration", 0.1)

				local timeScaleStart = utility.getAttribute(ref, "TimeScale_Start", obj.TimeScale)
				local timeScaleEnd = utility.getAttribute(ref, "TimeScale_End", obj.TimeScale)

				local speedTween

				if timeScaleStart ~= timeScaleEnd then
					speedTween = tween.fromParams(
						utility.getAttribute(ref, "TimeScale_Curve", utility.default_bezier),
						timeScaleDuration,
						function(alpha, deltaTime)
							local speed =
								utility.lerp(timeScaleStart, timeScaleEnd, math.clamp(alpha, 0, 1))

							obj.TimeScale = speed

							return deltaTime
						end
					)

					table.insert(scope, speedTween)
				elseif timeScaleStart ~= 1 then
					obj.TimeScale = timeScaleStart
				end

				obj:Emit(count)

				if useDuration then
					task.wait(duration)
					obj.Enabled = false
				end

				tween.timer(ref.Lifetime.Max, function(deltaTime, elapsed)
					return if ref.TimeScale > 0
							or (elapsed > 0 and speedTween and speedTween.Connected)
						then deltaTime * ref.TimeScale
						else nil
				end, speedTween, scope)
			end

			return particle
		end

		factories["EmitModule.effects.screen"] = function()
			local RunService = game:GetService("RunService")

			local utility = getModule("EmitModule.mod.utility")

			local screen = {}

			function screen.emit(ref: BasePart, scope: utility.scope)
				if not ref:GetAttribute("Enabled") then
					return
				end

				local scale = utility.getAttribute(ref, "PartScale", vector.one)
				local distance = utility.getAttribute(ref, "PartDistance", 1.5)

				local pos = utility.getAttribute(ref, "OffsetPosition", vector.zero)
				local rot = utility.getAttribute(ref, "OffsetRotation", vector.zero)
					* utility.DEG_TO_RAD

				local originalCF = ref.CFrame
				local originalSize = ref.Size
				local originalColGroup = ref.CollisionGroup

				ref.CollisionGroup = "Default"

				table.insert(scope, function()
					ref.Size = originalSize
					ref.CFrame = originalCF
					ref.CollisionGroup = originalColGroup ~= "" and originalColGroup or "Default"
				end)

				local function frame()
					local camera = workspace.CurrentCamera

					local halfFovRad = math.rad(camera.FieldOfView / 2)
					local height = math.tan(halfFovRad) * distance * 2
					local width = (camera.ViewportSize.X / camera.ViewportSize.Y) * height

					local cf = camera.CFrame * CFrame.new(0, 0, -distance)

					ref.Size = Vector3.new(width, height, ref.Size.Z) * scale
					ref.CFrame = cf * CFrame.new(pos) * CFrame.fromOrientation(rot.x, rot.y, rot.z)
				end

				if not RunService:IsRunning() then
					table.insert(scope, RunService.RenderStepped:Connect(frame))
				else
					local id = utility.getRanomId()

					RunService:BindToRenderStep(id, utility.RENDER_PRIORITY + scope.depth, frame)

					table.insert(scope, function()
						RunService:UnbindFromRenderStep(id)
					end)
				end
			end

			return screen
		end

		factories["EmitModule.effects.shockwave_debris"] = function()
			local RunService = game:GetService("RunService")
			local CollectionService = game:GetService("CollectionService")

			local tween = getModule("EmitModule.mod.tween")
			local utility = getModule("EmitModule.mod.utility")

			local EclipsePromise = getModule("EmitModule.pkg.EclipsePromise")
			local ObjectCache = getModule("EmitModule.obj.ObjectCache")

			local rng = Random.new()

			local debris = {}
			local physicsParts = {}
			local previewPhysics = {}

			local function stepPreview(dt)
				local gravity = Vector3.new(0, -workspace.Gravity, 0)
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = physicsParts
				params.RespectCanCollide = true
				for _, part in physicsParts do
					local state = previewPhysics[part]
					if not state or not part.Parent then
						continue
					end
					local cf = part.CFrame
					local displacement = state.velocity * dt + gravity * (0.5 * dt * dt)
					local velocity = state.velocity + gravity * dt
					local position = cf.Position + displacement
					if part.CanCollide and displacement.Magnitude > 1e-6 then
						params.CollisionGroup = part.CollisionGroup

						local hit = workspace:Spherecast(
							cf.Position,
							part.Size.Magnitude * 0.5,
							displacement,
							params
						)
						if hit then
							local normal = hit.Normal
							position = cf.Position
								+ displacement.Unit * math.max(0, hit.Distance - 0.01)
							local properties = part.CustomPhysicalProperties
								or PhysicalProperties.new(part.Material)
							local normalSpeed = velocity:Dot(normal)
							if normalSpeed < 0 then
								local tangent = velocity - normal * normalSpeed
								velocity = tangent
										* (1 - math.clamp(properties.Friction * dt * 10, 0, 1))
									- normal * normalSpeed * properties.Elasticity
								state.angular *= 1 - math.clamp(properties.Friction * dt * 10, 0, 1)
							end
						end
					end
					state.velocity = velocity
					local rotation = cf.Rotation
					local speed = state.angular.Magnitude
					if speed > 1e-6 then
						rotation = CFrame.fromAxisAngle(state.angular / speed, speed * dt)
							* rotation
					end
					part.CFrame = CFrame.new(position) * rotation
				end
			end

			local part_cache: ObjectCache.ObjectCache?
			local physicsStepper: RBXScriptConnection?

			function debris.init(cache)
				if physicsStepper then
					return
				end

				part_cache = cache

				if RunService:IsStudio() and env.EclipsePreview then
					physicsStepper = RunService.RenderStepped:Connect(function(deltaTime)
						if #physicsParts == 0 then
							return
						end

						stepPreview(deltaTime)
					end)
				end
			end

			function debris.deinit()
				if physicsStepper then
					physicsStepper:Disconnect()
					physicsStepper = nil
				end

				part_cache = nil

				for _, part in physicsParts do
					part:Destroy()
				end

				table.clear(physicsParts)
				table.clear(previewPhysics)
			end

			function debris.emit(origin: Attachment, ref: Part, scope: utility.scope)
				if not part_cache then
					return
				end

				local params

				local inherit = utility.getAttribute(ref, "InheritanceEnabled", true)
				local inheritRadius = utility.getAttribute(ref, "InheritanceRadius", 5)

				if inherit then
					local inheritMaxResults = utility.getAttribute(ref, "InheritanceMaxResults", 5)

					local rayColGroup = utility.getAttribute(origin, "RayCollisionGroup", "Default")
					local rayFilterTag = utility.getAttribute(origin, "FilterTag", "")
					local rayFilterType = utility.getAttribute(origin, "FilterType", "Exclude")

					local rayIgnoreCanCollide =
						utility.getAttribute(origin, "IgnoreCanCollide", false)

					params = OverlapParams.new()
					params.MaxParts = inheritMaxResults
					params.CollisionGroup = rayColGroup
					params.RespectCanCollide = not rayIgnoreCanCollide
					params.FilterType = Enum.RaycastFilterType[rayFilterType]
					params.FilterDescendantsInstances = CollectionService:GetTagged(rayFilterTag)

					if rayFilterType == "Exclude" then
						params:AddToFilter({ workspace.Terrain })
					end
				end

				local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

				local amount = utility.getRangeAttribute(
					ref,
					"Amount",
					NumberRange.new(5, 10),
					NumberRange.new(0, math.huge)
				)
				local lifetime = utility.getRangeAttribute(
					ref,
					"Lifetime",
					NumberRange.new(2, 3),
					NumberRange.new(0, math.huge)
				)
				local airtime = utility.getRangeAttribute(
					ref,
					"Airtime",
					NumberRange.new(0.5, 0.5),
					NumberRange.new(0, math.huge)
				)

				local linmag =
					utility.getRangeAttribute(ref, "LinearMagnitude", NumberRange.new(15, 25))
				local angmag =
					utility.getRangeAttribute(ref, "AngularMagnitude", NumberRange.new(5, 15))

				local sizeScaleEnd = utility.getAttribute(ref, "SizeScaleEnd", vector.zero)

				local minSize = utility.getAttribute(ref, "MinSize", vector.create(2, 1, 2))
				local maxSize = utility.getAttribute(ref, "MaxSize", vector.create(3, 2, 3))

				local minDir = utility.getAttribute(ref, "MinDirection", -vector.one)
				local maxDir = utility.getAttribute(ref, "MaxDirection", vector.one)

				local count = rng:NextInteger(amount.Min, amount.Max)

				local sizeCurve = utility.getAttribute(ref, "Size_Curve", utility.default_bezier)
				local tpCurve =
					utility.getAttribute(ref, "Transparency_Curve", utility.default_bezier)

				local tpDuration = utility.getAttribute(ref, "Transparency_Duration", 0.5)
				local sizeDuration = utility.getAttribute(ref, "Size_Duration", 0.5)

				local tpStart = utility.getAttribute(ref, "Transparency_Start", 0)
				local tpEnd = utility.getAttribute(ref, "Transparency_End", 1)

				local partData = {}
				local promises = {}

				ref.CanCollide = false

				if params then
					local parts =
						workspace:GetPartBoundsInRadius(origin.WorldPosition, inheritRadius, params)

					for _, p in parts do
						if p.Transparency == 1 then
							continue
						end

						table.insert(partData, p)
					end
				end

				task.wait(emitDelay)

				for _ = 1, count do
					local iref = #partData ~= 0 and partData[rng:NextInteger(1, #partData)]

					local id = utility.getRanomId()

					local part = part_cache:get(id)

					local realPart = part._getReal()

					utility.copyProperties(ref, realPart, utility.COPY_PART_PROPERTIES)
					utility.copyProperties(ref, realPart, utility.COPY_EXTENDED_PART_PROPERTIES)

					if #ref:GetChildren() ~= 0 then
						local clone = ref:Clone()

						for _, child in clone:GetChildren() do
							child.Parent = realPart
						end

						clone:Destroy()
					end

					part.Anchored = env.EclipsePreview == true
					part.CanCollide = true

					part.Transparency = tpStart

					if part.CollisionGroup == "Default" then
						part.CollisionGroup = "Default"
					end

					part.CFrame = CFrame.new(origin.WorldPosition)

					local size = Vector3.new(
						rng:NextNumber(minSize.X, maxSize.X),
						rng:NextNumber(minSize.Y, maxSize.Y),
						rng:NextNumber(minSize.Z, maxSize.Z)
					)

					part.Size = size

					if iref then
						part.Material = iref.Material
						part.Color = iref.Color
						part.Transparency = iref.Transparency
					end

					table.insert(scope, function()
						local index = table.find(physicsParts, realPart)

						if index then
							table.remove(physicsParts, index)
							previewPhysics[realPart] = nil
						end

						if part_cache then
							part_cache:free(id)
						end
					end)

					table.insert(physicsParts, realPart)

					part.AssemblyLinearVelocity =
						origin.WorldCFrame:VectorToWorldSpace(part.AssemblyLinearVelocity)

					local relDir = utility.randomUnitVector(minDir, maxDir)
					local worldDir = origin.WorldCFrame:VectorToWorldSpace(relDir)

					local velocity = utility.getImpulseForce(
						origin.WorldPosition,
						origin.WorldPosition
							+ worldDir.Unit * rng:NextNumber(linmag.Min, linmag.Max),
						rng:NextNumber(airtime.Min, airtime.Max)
					)
					local angularImpulse = rng:NextUnitVector()
						* rng:NextNumber(angmag.Min, angmag.Max)
					if env.EclipsePreview then
						previewPhysics[realPart] = {
							velocity = part.AssemblyLinearVelocity + velocity,
							angular = angularImpulse,
						}
					else
						part:ApplyImpulse(part.AssemblyMass * velocity)
						part:ApplyAngularImpulse(part.AssemblyMass * angularImpulse)
					end

					if shared.vfx and #part:GetChildren() ~= 0 then
						local env = shared.vfx.emit(part)
						table.insert(promises, env.Finished)
					end

					task.delay(rng:NextNumber(lifetime.Min, lifetime.Max), function()
						local startSize = part.Size

						if startSize ~= size * sizeScaleEnd then
							table.insert(
								scope,
								tween.fromParams(sizeCurve, sizeDuration, function(alpha, deltaTime)
									part.Size = startSize:Lerp(size * sizeScaleEnd, alpha)
									return deltaTime
								end)
							)
						end

						if tpStart ~= tpEnd then
							table.insert(
								scope,
								tween.fromParams(tpCurve, tpDuration, function(alpha, deltaTime)
									part.Transparency = utility.lerp(tpStart, tpEnd, alpha)
									return deltaTime
								end)
							)
						else
							part.Transparency = tpStart
						end
					end)
				end

				task.wait(lifetime.Max + math.max(tpDuration, sizeDuration))

				EclipsePromise.all(promises):await()
			end

			return debris
		end

		factories["EmitModule.effects.shockwave_line"] = function()
			local CollectionService = game:GetService("CollectionService")

			local tween = getModule("EmitModule.mod.tween")
			local logger = getModule("EmitModule.mod.logger")
			local utility = getModule("EmitModule.mod.utility")

			local Bezier = getModule("EmitModule.obj.Bezier")
			local EclipsePromise = getModule("EmitModule.pkg.EclipsePromise")
			local ObjectCache = getModule("EmitModule.obj.ObjectCache")

			local rng = Random.new()

			local line = {}

			local part_cache: ObjectCache.ObjectCache?

			function line.init(cache)
				part_cache = cache
			end

			function line.deinit()
				part_cache = nil
			end

			function line.emit(origin: Attachment, ref: Part, scope: utility.scope)
				if not part_cache then
					return
				end

				local raydir =
					utility.getAttribute(origin, "RayDirection", vector.create(0, -50, 0))

				local rayColGroup = utility.getAttribute(origin, "RayCollisionGroup", "Default")
				local rayFilterTag = utility.getAttribute(origin, "FilterTag", "")
				local rayFilterType = utility.getAttribute(origin, "FilterType", "Exclude")

				local rayIgnoreWater = utility.getAttribute(origin, "IgnoreWater", true)
				local rayIgnoreCanCollide = utility.getAttribute(origin, "IgnoreCanCollide", false)

				local params = RaycastParams.new()
				params.CollisionGroup = rayColGroup
				params.IgnoreWater = rayIgnoreWater
				params.RespectCanCollide = not rayIgnoreCanCollide
				params.FilterType = Enum.RaycastFilterType[rayFilterType]
				params.FilterDescendantsInstances = CollectionService:GetTagged(rayFilterTag)

				if rayFilterType == "Exclude" then
					params:AddToFilter({ workspace.Terrain })
				end

				local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

				local rateStart = utility.getAttribute(ref, "Rate_Start", 30)
				local rateEnd = utility.getAttribute(ref, "Rate_End", 30)

				local fixedAmount = utility.getAttribute(ref, "FixedAmount", 0)

				local scaleStart = utility.getAttribute(ref, "Scale_Start", 1)
				local scaleEnd = utility.getAttribute(ref, "Scale_End", 1)

				local duration = utility.getAttribute(ref, "Duration", 1)
				local direction = utility.getAttribute(ref, "Direction", vector.create(0, 0, -1))
				local lineLength = utility.getAttribute(ref, "Length", 50)

				local rot = utility.getRangeAttribute(ref, "Rotation", NumberRange.new(-180, 180))

				local old_partOffset = utility.getAttribute(ref, "PartOffset", vector.zero, true)

				local baseOffset = utility.getAttribute(ref, "BaseOffset", old_partOffset)
				local offsetStart = utility.getAttribute(ref, "Offset_Start", old_partOffset)
				local offsetEnd = utility.getAttribute(ref, "Offset_End", old_partOffset)

				local offsetStartDuration = utility.getAttribute(ref, "Offset_Start_Duration", 0.5)
				local offsetEndDuration = utility.getAttribute(ref, "Offset_End_Duration", 0.5)

				local lifetime = utility.getRangeAttribute(
					ref,
					"Lifetime",
					NumberRange.new(2, 3),
					NumberRange.new(0, math.huge)
				)

				local sizeScaleStart = utility.getAttribute(ref, "SizeScaleStart", vector.zero)
				local sizeScaleEnd = utility.getAttribute(ref, "SizeScaleEnd", vector.zero)

				local minSize = utility.getAttribute(ref, "MinSize", vector.create(2, 1, 2))
				local maxSize = utility.getAttribute(ref, "MaxSize", vector.create(3, 2, 3))

				local old_sizeCurve =
					utility.getAttribute(ref, "Size_Curve", utility.default_bezier, true)
				local old_sizeDuration = utility.getAttribute(ref, "Size_Duration", 0.5, true)

				local sizeStartCurve = utility.getAttribute(ref, "Size_Start_Curve", old_sizeCurve)
				local sizeEndCurve = utility.getAttribute(ref, "Size_End_Curve", old_sizeCurve)

				local sizeStartDuration =
					utility.getAttribute(ref, "Size_Start_Duration", old_sizeDuration)
				local sizeEndDuration =
					utility.getAttribute(ref, "Size_End_Duration", old_sizeDuration)

				local tpDuration = utility.getAttribute(ref, "Transparency_Duration", 0.5)

				local tpStart = utility.getAttribute(ref, "Transparency_Start", 0)
				local tpEnd = utility.getAttribute(ref, "Transparency_End", 0)

				local sync = utility.getAttribute(ref, "SyncPosition", false)

				duration = math.max(duration, 0.001)

				if fixedAmount > 0 then
					local rate = fixedAmount / duration

					rateStart = rate
					rateEnd = rate
				end

				direction = direction.Unit

				if direction ~= direction then
					direction = -Vector3.zAxis
				end

				task.wait(emitDelay)

				local promises = {}

				local start = origin.WorldCFrame

				local last = 0
				local total = 0

				local currentRate = rateStart
				local currentScale = scaleStart

				if scaleStart ~= scaleEnd then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(ref, "Scale_Curve", utility.default_bezier),
							duration,
							function(alpha, deltaTime)
								currentScale = utility.lerp(scaleStart, scaleEnd, alpha)
								return deltaTime
							end
						)
					)
				end

				if rateStart ~= rateEnd then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(ref, "Rate_Curve", utility.default_bezier),
							duration,
							function(alpha, deltaTime)
								currentRate = utility.lerp(rateStart, rateEnd, alpha)
								return deltaTime
							end
						)
					)
				end

				local pathCurve = utility.getAttribute(ref, "Path_Curve", utility.linear_bezier)

				local ok, points = pcall(function()
					return utility.deserializePath(pathCurve)
				end)

				if not ok then
					logger.error(`failed to decode bezier path data with error: {points}`)
				end

				local bezier = Bezier.new(points, 0)

				table.insert(
					scope,
					tween.fromParams(utility.linear_bezier, duration, function(_, deltaTime)
						last += deltaTime

						local threshold = 1 / currentRate
						local max = duration * currentRate

						if last < threshold or total >= max then
							return deltaTime
						end

						local ticks = last // threshold

						for i = 1, ticks do
							if total >= max then
								continue
							end

							total += 1

							local t = math.clamp(total / max, 0, 1)
							local alpha = 1 - bezier:getEase(t).y

							if sync then
								start = origin.WorldCFrame
							end

							local result = workspace:Raycast(
								start.Position
									+ start:VectorToWorldSpace(direction) * lineLength * alpha,
								origin.WorldCFrame:VectorToWorldSpace(raydir),
								params
							)

							if not result then
								last = 0
								return deltaTime
							end

							local width = rng:NextNumber(minSize.X, maxSize.X)

							local height = rng:NextNumber(minSize.Y, maxSize.Y)
							local length = rng:NextNumber(minSize.Z, maxSize.Z)

							local id = utility.getRanomId()

							local part = part_cache:get(id)

							local realPart = part._getReal()

							utility.copyProperties(ref, realPart, utility.COPY_PART_PROPERTIES)
							utility.copyProperties(
								ref,
								realPart,
								utility.COPY_EXTENDED_PART_PROPERTIES
							)

							if #ref:GetChildren() ~= 0 then
								local clone = ref:Clone()

								for _, child in clone:GetChildren() do
									child.Parent = realPart
								end

								clone:Destroy()
							end

							table.insert(scope, function()
								if part_cache then
									part_cache:free(id)
								end
							end)

							part.Color = result.Instance.Color
							part.Material = result.Material
							part.Transparency = result.Instance.Transparency

							if part.Transparency == 0 then
								part.Transparency = tpStart
							end

							part.Size = Vector3.zero

							local angle = rng:NextNumber(rot.Min, rot.Max)

							local rx = -math.cos(angle)
							local rz = -math.sin(angle)

							local dir =
								origin.WorldCFrame:VectorToWorldSpace(Vector3.new(rx, 0, rz))
							local right = dir:Cross(result.Normal).Unit

							local rotCF = CFrame.fromMatrix(result.Position, right, result.Normal)
								* CFrame.fromOrientation(-math.atan(height / length), 0, 0)

							part.CFrame = CFrame.new(offsetStart) * rotCF

							local sizeTween
							local offsetTween

							local currentOffset = Vector3.zero

							if offsetStart ~= baseOffset then
								offsetTween = tween.fromParams(
									utility.getAttribute(
										ref,
										"Offset_Start_Curve",
										utility.default_bezier
									),
									offsetStartDuration,
									function(alpha, deltaTime)
										currentOffset = offsetStart:Lerp(baseOffset, alpha)
										part.CFrame = CFrame.new(currentOffset) * rotCF
										return deltaTime
									end
								)

								table.insert(scope, offsetTween)
							end

							local size = Vector3.new(width, height, length) * currentScale

							if size * sizeScaleStart ~= size then
								sizeTween = tween.fromParams(
									sizeStartCurve,
									sizeStartDuration,
									function(alpha, deltaTime)
										part.Size = (size * sizeScaleStart):Lerp(size, alpha)
										return deltaTime
									end
								)

								table.insert(scope, sizeTween)
							else
								part.Size = size * sizeScaleStart
							end

							if shared.vfx and #part:GetChildren() ~= 0 then
								local env = shared.vfx.emit(realPart)
								table.insert(promises, env.Finished)
							end

							task.delay(rng:NextNumber(lifetime.Min, lifetime.Max), function()
								if sizeTween then
									sizeTween:Disconnect()
								end

								if offsetTween then
									offsetTween:Disconnect()
								end

								local startSize = part.Size
								local startTp = part.Transparency

								if startSize ~= size * sizeScaleEnd then
									table.insert(
										scope,
										tween.fromParams(
											sizeEndCurve,
											sizeEndDuration,
											function(alpha, deltaTime)
												part.Size =
													startSize:Lerp(size * sizeScaleEnd, alpha)
												return deltaTime
											end
										)
									)
								end

								if currentOffset ~= offsetEnd then
									table.insert(
										scope,
										tween.fromParams(
											utility.getAttribute(
												ref,
												"Offset_End_Curve",
												utility.default_bezier
											),
											offsetEndDuration,
											function(alpha, deltaTime)
												part.CFrame = CFrame.new(
													currentOffset:Lerp(offsetEnd, alpha)
												) * rotCF
												return deltaTime
											end
										)
									)
								end

								if startTp ~= tpEnd then
									table.insert(
										scope,
										tween.fromParams(
											utility.getAttribute(
												ref,
												"Transparency_Curve",
												utility.default_bezier
											),
											tpDuration,
											function(alpha, deltaTime)
												part.Transparency =
													utility.lerp(startTp, tpEnd, alpha)
												return deltaTime
											end
										)
									)
								else
									part.Transparency = startTp
								end
							end)
						end

						last %= threshold

						return deltaTime
					end, nil, nil, true, utility.RENDER_PRIORITY + scope.depth)
				)

				task.wait(lifetime.Max + duration + math.max(sizeEndDuration, offsetEndDuration))

				EclipsePromise.all(promises):await()
			end

			return line
		end

		factories["EmitModule.effects.shockwave_ring"] = function()
			local CollectionService = game:GetService("CollectionService")

			local tween = getModule("EmitModule.mod.tween")
			local utility = getModule("EmitModule.mod.utility")

			local EclipsePromise = getModule("EmitModule.pkg.EclipsePromise")
			local ObjectCache = getModule("EmitModule.obj.ObjectCache")

			local rng = Random.new()

			local ring = {}

			local part_cache: ObjectCache.ObjectCache?

			function ring.init(cache)
				part_cache = cache
			end

			function ring.deinit()
				part_cache = nil
			end

			function ring.emit(origin: Attachment, ref: Part, scope: utility.scope)
				if not part_cache then
					return
				end

				local raydir =
					utility.getAttribute(origin, "RayDirection", vector.create(0, -50, 0))

				local rayColGroup = utility.getAttribute(origin, "RayCollisionGroup", "Default")
				local rayFilterTag = utility.getAttribute(origin, "FilterTag", "")
				local rayFilterType = utility.getAttribute(origin, "FilterType", "Exclude")

				local rayIgnoreWater = utility.getAttribute(origin, "IgnoreWater", true)
				local rayIgnoreCanCollide = utility.getAttribute(origin, "IgnoreCanCollide", false)

				local params = RaycastParams.new()
				params.CollisionGroup = rayColGroup
				params.IgnoreWater = rayIgnoreWater
				params.RespectCanCollide = not rayIgnoreCanCollide
				params.FilterType = Enum.RaycastFilterType[rayFilterType]
				params.FilterDescendantsInstances = CollectionService:GetTagged(rayFilterTag)

				if rayFilterType == "Exclude" then
					params:AddToFilter({ workspace.Terrain })
				end

				local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

				local radius = utility.getAttribute(ref, "Radius", 5)
				local segments = utility.getAttribute(ref, "Segments", 7)

				local lifetime = utility.getRangeAttribute(
					ref,
					"Lifetime",
					NumberRange.new(2, 3),
					NumberRange.new(0, math.huge)
				)

				local old_partOffset = utility.getAttribute(ref, "PartOffset", vector.zero, true)

				local baseOffset = utility.getAttribute(ref, "BaseOffset", old_partOffset)
				local offsetStart = utility.getAttribute(ref, "Offset_Start", old_partOffset)
				local offsetEnd = utility.getAttribute(ref, "Offset_End", old_partOffset)

				local offsetStartDuration = utility.getAttribute(ref, "Offset_Start_Duration", 0.5)
				local offsetEndDuration = utility.getAttribute(ref, "Offset_End_Duration", 0.5)

				local sizeScaleStart = utility.getAttribute(ref, "SizeScaleStart", vector.zero)
				local sizeScaleEnd = utility.getAttribute(ref, "SizeScaleEnd", vector.zero)

				local minSize = utility.getAttribute(ref, "MinSize", vector.create(2, 1, 2))
				local maxSize = utility.getAttribute(ref, "MaxSize", vector.create(3, 2, 3))

				local old_sizeCurve =
					utility.getAttribute(ref, "Size_Curve", utility.default_bezier, true)
				local old_sizeDuration = utility.getAttribute(ref, "Size_Duration", 0.5, true)

				local sizeStartCurve = utility.getAttribute(ref, "Size_Start_Curve", old_sizeCurve)
				local sizeEndCurve = utility.getAttribute(ref, "Size_End_Curve", old_sizeCurve)

				local sizeStartDuration =
					utility.getAttribute(ref, "Size_Start_Duration", old_sizeDuration)
				local sizeEndDuration =
					utility.getAttribute(ref, "Size_End_Duration", old_sizeDuration)

				local tpDuration = utility.getAttribute(ref, "Transparency_Duration", 0.5)

				local tpStart = utility.getAttribute(ref, "Transparency_Start", 0)
				local tpEnd = utility.getAttribute(ref, "Transparency_End", 0)

				task.wait(emitDelay)

				local promises = {}

				for i = 0, segments - 1 do
					local angle = i / segments * math.pi * 2

					local x = radius * math.cos(angle)
					local y = radius * math.sin(angle)

					local result = workspace:Raycast(
						(origin.WorldCFrame * CFrame.new(x, 0, y)).Position,
						origin.WorldCFrame:VectorToWorldSpace(raydir),
						params
					)

					if not result then
						continue
					end

					local width = rng:NextNumber(minSize.X, maxSize.X)

					local height = rng:NextNumber(minSize.Y, maxSize.Y)
					local length = rng:NextNumber(minSize.Z, maxSize.Z)

					local id = utility.getRanomId()

					local part = part_cache:get(id)

					local realPart = part._getReal()

					utility.copyProperties(ref, realPart, utility.COPY_PART_PROPERTIES)
					utility.copyProperties(ref, realPart, utility.COPY_EXTENDED_PART_PROPERTIES)

					if #ref:GetChildren() ~= 0 then
						local clone = ref:Clone()

						for _, child in clone:GetChildren() do
							child.Parent = realPart
						end

						clone:Destroy()
					end

					table.insert(scope, function()
						if part_cache then
							part_cache:free(id)
						end
					end)

					part.Color = result.Instance.Color
					part.Material = result.Material
					part.Transparency = result.Instance.Transparency

					if part.Transparency == 0 then
						part.Transparency = tpStart
					end

					part.Size = Vector3.zero

					local rx = -math.cos(angle)
					local rz = -math.sin(angle)

					local dir = origin.WorldCFrame:VectorToWorldSpace(Vector3.new(rx, 0, rz))
					local right = dir:Cross(result.Normal).Unit

					local rotCF = CFrame.fromMatrix(result.Position, right, result.Normal)
						* CFrame.fromOrientation(-math.atan(height / length), 0, 0)

					part.CFrame = CFrame.new(offsetStart) * rotCF

					local sizeTween
					local offsetTween

					local currentOffset = Vector3.zero

					if offsetStart ~= baseOffset then
						offsetTween = tween.fromParams(
							utility.getAttribute(ref, "Offset_Start_Curve", utility.default_bezier),
							offsetStartDuration,
							function(alpha, deltaTime)
								currentOffset = offsetStart:Lerp(baseOffset, alpha)
								part.CFrame = CFrame.new(currentOffset) * rotCF
								return deltaTime
							end
						)

						table.insert(scope, sizeTween)
					end

					local size = Vector3.new(width, height, length)

					if size * sizeScaleStart ~= size then
						sizeTween = tween.fromParams(
							sizeStartCurve,
							sizeStartDuration,
							function(alpha, deltaTime)
								part.Size = (size * sizeScaleStart):Lerp(size, alpha)
								return deltaTime
							end
						)

						table.insert(scope, sizeTween)
					else
						part.Size = size * sizeScaleStart
					end

					if shared.vfx and #part:GetChildren() ~= 0 then
						local env = shared.vfx.emit(part)
						table.insert(promises, env.Finished)
					end

					task.delay(rng:NextNumber(lifetime.Min, lifetime.Max), function()
						if sizeTween then
							sizeTween:Disconnect()
						end

						if offsetTween then
							offsetTween:Disconnect()
						end

						local startSize = part.Size
						local startTp = part.Transparency

						if startSize ~= size * sizeScaleEnd then
							table.insert(
								scope,
								tween.fromParams(
									sizeEndCurve,
									sizeEndDuration,
									function(alpha, deltaTime)
										part.Size = startSize:Lerp(size * sizeScaleEnd, alpha)
										return deltaTime
									end
								)
							)
						end

						if currentOffset ~= offsetEnd then
							table.insert(
								scope,
								tween.fromParams(
									utility.getAttribute(
										ref,
										"Offset_End_Curve",
										utility.default_bezier
									),
									offsetEndDuration,
									function(alpha, deltaTime)
										part.CFrame = CFrame.new(
											currentOffset:Lerp(offsetEnd, alpha)
										) * rotCF
										return deltaTime
									end
								)
							)
						end

						if startTp ~= tpEnd then
							table.insert(
								scope,
								tween.fromParams(
									utility.getAttribute(
										ref,
										"Transparency_Curve",
										utility.default_bezier
									),
									tpDuration,
									function(alpha, deltaTime)
										part.Transparency = utility.lerp(startTp, tpEnd, alpha)
										return deltaTime
									end
								)
							)
						else
							part.Transparency = startTp
						end
					end)
				end

				task.wait(lifetime.Max + math.max(sizeEndDuration, offsetEndDuration))

				EclipsePromise.all(promises):await()
			end

			return ring
		end

		factories["EmitModule.effects.spin"] = function()
			local tween = getModule("EmitModule.mod.tween")
			local utility = getModule("EmitModule.mod.utility")

			local spin = {}

			function spin.emit(ref: Model, scope: utility.scope)
				local rotation = utility.getAttribute(ref, "SpinRotation", vector.zero, true)
					* utility.DEG_TO_RAD

				local scaleStart = utility.getAttribute(ref, "Scale_Start", 1, true)
				local scaleEnd = utility.getAttribute(ref, "Scale_End", 1, true)

				if rotation == vector.zero and scaleStart == 1 and scaleEnd == 1 then
					return
				end

				local emitDelay = utility.getAttribute(ref, "EmitDelay", 0)

				local sync = utility.getAttribute(ref, "SyncPosition", false)
				local duration = utility.getAttribute(ref, "SpinDuration", 0.5)

				local speedDuration = utility.getAttribute(ref, "SpinSpeed_Duration", 0.1)

				local speedStart = utility.getAttribute(ref, "SpinSpeed_Start", 0)
				local speedEnd = utility.getAttribute(ref, "SpinSpeed_End", 1)

				local currentSpeed = speedStart

				task.wait(emitDelay)

				local speedTween

				if speedStart ~= speedEnd then
					speedTween = tween.fromParams(
						utility.getAttribute(ref, "SpinSpeed_Curve", utility.default_bezier),
						speedDuration,
						function(alpha, deltaTime)
							currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
							return deltaTime
						end
					)

					table.insert(scope, speedTween)
				end

				local originalPivot = ref:GetPivot()
				local originalScale = ref:GetScale()

				if scaleStart ~= scaleEnd then
					table.insert(
						scope,
						tween.fromParams(
							utility.getAttribute(ref, "Scale_Curve", utility.default_bezier),
							duration,
							function(alpha, deltaTime)
								ref:ScaleTo(utility.lerp(scaleStart, scaleEnd, alpha))
								return deltaTime
							end
						)
					)
				else
					ref:ScaleTo(scaleStart)
				end

				local parent = ref:FindFirstAncestorOfClass("Attachment")
					or ref:FindFirstAncestorWhichIsA("BasePart")

				table.insert(scope, function()
					ref:PivotTo(
						parent
								and (parent:IsA("Attachment") and parent.WorldCFrame or parent.CFrame)
							or originalPivot
					)
					ref:ScaleTo(originalScale)
				end)

				rotation *= duration

				tween.timer(duration, function(deltaTime, elapsed)
					local alpha = math.clamp(elapsed / duration, 0, 1)

					local r = rotation * alpha
					local cf = (
						if parent and sync
							then (parent:IsA("Attachment") and parent.WorldCFrame or parent.CFrame)
							else originalPivot
					) * CFrame.fromOrientation(r.x, r.y, r.z)

					ref:PivotTo(cf)

					return if currentSpeed > 0 or (elapsed > 0 and speedTween.Connected)
						then deltaTime * currentSpeed
						else nil
				end, speedTween, scope, utility.RENDER_PRIORITY + scope.depth)
			end

			return spin
		end

		factories["EmitModule.effects.tween_property"] = function()
			local lerp = getModule("EmitModule.mod.lerp")
			local tween = getModule("EmitModule.mod.tween")
			local utility = getModule("EmitModule.mod.utility")

			local rng = Random.new()

			local prop = {}

			function prop.emit(parent: Instance, obj: RayValue, scope: utility.scope)
				local property = obj.Name

				local emitDelay = utility.getAttribute(obj, "EmitDelay", 0)
				local resetOnFinish = utility.getAttribute(obj, "ResetOnFinish", true)

				local durationRange = utility.getRangeAttribute(
					obj,
					"Duration",
					NumberRange.new(1, 1),
					NumberRange.new(0, math.huge)
				)

				if emitDelay > 0 then
					task.wait(emitDelay)
				end

				local endValue = obj:GetAttribute("_END_VALUE")
				local overrideStartValue = obj:GetAttribute("_START_VALUE")

				local ok, startValue = pcall(function()
					return parent[property]
				end)

				if overrideStartValue then
					startValue = overrideStartValue
				end

				local typeName = typeof(startValue)

				if not ok or typeName ~= typeof(endValue) then
					return
				end

				local duration = rng:NextNumber(durationRange.Min, durationRange.Max)

				local speedStart = utility.getAttribute(obj, "Speed_Start", 1)
				local speedEnd = utility.getAttribute(obj, "Speed_End", 1)

				local currentSpeed = speedStart

				local speedTween

				if speedStart ~= speedEnd then
					speedTween = tween.fromParams(
						utility.getAttribute(obj, "Speed_Curve", utility.default_bezier),
						utility.getAttribute(obj, "Speed_Duration", 0.1),
						function(alpha, deltaTime)
							currentSpeed = utility.lerp(speedStart, speedEnd, alpha)
							return deltaTime
						end
					)

					table.insert(scope, speedTween)
				end

				local lfunc = lerp[typeName] or lerp.Other

				table.insert(
					scope,
					tween.fromParams(
						utility.getAttribute(obj, "Easing_Curve", utility.linear_bezier),
						duration,
						function(alpha, deltaTime)
							parent[property] = lfunc(startValue, endValue, alpha)
							return deltaTime * currentSpeed
						end,
						speedTween,
						nil,
						nil,
						utility.RENDER_PRIORITY + scope.depth
					)
				)

				if resetOnFinish then
					table.insert(scope, function()
						parent[property] = startValue
					end)
				end

				tween.timer(duration, function(deltaTime, elapsed)
					return if currentSpeed > 0
							or (elapsed > 0 and speedTween and speedTween.Connected)
						then deltaTime * currentSpeed
						else nil
				end, speedTween, scope)
			end

			return prop
		end

		factories["EmitModule.mod.color.EclipseOklab"] = function()
			return sharedLibraries.EclipseOklab(libraryEnvironment, sharedLibraries)
		end

		factories["EmitModule.mod.color.EclipseRGB"] = function()
			return sharedLibraries.EclipseRGB(libraryEnvironment, sharedLibraries)
		end

		factories["EmitModule.mod.lerp"] = function()
			local EclipseOklab = getModule("EmitModule.mod.color.EclipseOklab")

			local MAX_KEYPOINTS = 20

			local lerp = {}

			function lerp.number(a: number, b: number, t: number)
				return a + (b - a) * t
			end

			function lerp.Vector3(a: Vector3, b: Vector3, t: number)
				return a:Lerp(b, t)
			end

			function lerp.Vector2(a: Vector2, b: Vector2, t: number)
				return a:Lerp(b, t)
			end

			function lerp.CFrame(a: CFrame, b: CFrame, t: number)
				return a:Lerp(b, t)
			end

			function lerp.UDim2(a: UDim2, b: UDim2, t: number)
				return a:Lerp(b, t)
			end

			function lerp.UDim(a: UDim, b: UDim, t: number)
				return UDim.new(
					lerp.number(a.Scale, b.Scale, t),
					lerp.number(a.Offset, b.Offset, t)
				)
			end

			function lerp.NumberRange(a: NumberRange, b: NumberRange, t: number)
				return NumberRange.new(lerp.number(a.Min, b.Min, t), lerp.number(a.Max, b.Max, t))
			end

			function lerp.Color3(a: Color3, b: Color3, t: number)
				return EclipseOklab.toSRGB(EclipseOklab.fromSRGB(a):Lerp(EclipseOklab.fromSRGB(b), t))
			end

			function lerp.PhysicalProperties(
				a: PhysicalProperties,
				b: PhysicalProperties,
				t: number
			)
				return PhysicalProperties.new(
					lerp.number(a.Density, b.Density, t),
					lerp.number(a.Friction, b.Friction, t),
					lerp.number(a.Elasticity, b.Elasticity, t),
					lerp.number(a.FrictionWeight, b.FrictionWeight, t),
					lerp.number(a.ElasticityWeight, b.ElasticityWeight, t)
				)
			end

			function lerp.Rect(a: Rect, b: Rect, t: number)
				return Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
			end

			function lerp.NumberSequence(a: NumberSequence, b: NumberSequence, t: number)
				local keypoints = {}
				local addedTimes = {}

				local keylength = 0

				for _, ap in a.Keypoints do
					local closestAbove, closestBelow

					for _, bp in b.Keypoints do
						if bp.Time == ap.Time then
							closestAbove, closestBelow = bp, bp
							break
						elseif
							bp.Time < ap.Time
							and (closestBelow == nil or bp.Time > closestBelow.Time)
						then
							closestBelow = bp
						elseif
							bp.Time > ap.Time
							and (closestAbove == nil or bp.Time < closestAbove.Time)
						then
							closestAbove = bp
						end
					end

					local bValue, bEnvelope

					if closestAbove == closestBelow then
						bValue, bEnvelope = closestAbove.Value, closestAbove.Envelope
					else
						local p = (ap.Time - closestBelow.Time)
							/ (closestAbove.Time - closestBelow.Time)
						bValue = (closestAbove.Value - closestBelow.Value) * p + closestBelow.Value
						bEnvelope = (closestAbove.Envelope - closestBelow.Envelope) * p
							+ closestBelow.Envelope
					end

					keylength += 1
					keypoints[keylength] = NumberSequenceKeypoint.new(
						ap.Time,
						(bValue - ap.Value) * t + ap.Value,
						(bEnvelope - ap.Envelope) * t + ap.Envelope
					)

					addedTimes[ap.Time] = true
				end

				for _, bp in b.Keypoints do
					if not addedTimes[bp.Time] then
						local closestAbove, closestBelow

						for _, ap in a.Keypoints do
							if ap.Time == bp.Time then
								closestAbove, closestBelow = ap, ap
								break
							elseif
								ap.Time < bp.Time
								and (closestBelow == nil or ap.Time > closestBelow.Time)
							then
								closestBelow = ap
							elseif
								ap.Time > bp.Time
								and (closestAbove == nil or ap.Time < closestAbove.Time)
							then
								closestAbove = ap
							end
						end

						local aValue, aEnvelope

						if closestAbove == closestBelow then
							aValue, aEnvelope = closestAbove.Value, closestAbove.Envelope
						else
							local p = (bp.Time - closestBelow.Time)
								/ (closestAbove.Time - closestBelow.Time)
							aValue = (closestAbove.Value - closestBelow.Value) * p
								+ closestBelow.Value
							aEnvelope = (closestAbove.Envelope - closestBelow.Envelope) * p
								+ closestBelow.Envelope
						end

						keylength += 1
						keypoints[keylength] = NumberSequenceKeypoint.new(
							bp.Time,
							(bp.Value - aValue) * t + aValue,
							(bp.Envelope - aEnvelope) * t + aEnvelope
						)
					end
				end

				table.sort(keypoints, function(a, b)
					return a.Time < b.Time
				end)

				local finalKeypoints

				if #keypoints > MAX_KEYPOINTS then
					finalKeypoints = {}
					local step = (#keypoints - 1) / (MAX_KEYPOINTS - 1)

					for i = 0, MAX_KEYPOINTS - 1 do
						local index = math.floor(i * step + 1)
						table.insert(finalKeypoints, keypoints[index])
					end

					if finalKeypoints[#finalKeypoints].Time < keypoints[#keypoints].Time then
						finalKeypoints[#finalKeypoints] = keypoints[#keypoints]
					end
				else
					finalKeypoints = keypoints
				end

				return NumberSequence.new(finalKeypoints)
			end

			local function getColorAtTime(sequence: ColorSequence, time: number)
				local keypoints = sequence.Keypoints

				if time <= keypoints[1].Time then
					return keypoints[1].Value
				end

				if time >= keypoints[#keypoints].Time then
					return keypoints[#keypoints].Value
				end

				local closestBelow
				local closestAbove

				for i = 1, #keypoints do
					local kp = keypoints[i]
					if kp.Time == time then
						return kp.Value
					elseif kp.Time < time then
						closestBelow = kp
					elseif kp.Time > time then
						closestAbove = kp
						break
					end
				end

				local alpha = (time - closestBelow.Time) / (closestAbove.Time - closestBelow.Time)

				return closestBelow.Value:Lerp(closestAbove.Value, alpha)
			end

			function lerp.ColorSequence(a: ColorSequence, b: ColorSequence, t: number)
				local newKeypoints = {}

				for _, bp in ipairs(b.Keypoints) do
					local aValueAtBTime = getColorAtTime(a, bp.Time)

					local finalColor = aValueAtBTime:Lerp(bp.Value, t)

					table.insert(newKeypoints, ColorSequenceKeypoint.new(bp.Time, finalColor))
				end

				return ColorSequence.new(newKeypoints)
			end

			function lerp.Other(a: any, b: any, t: number)
				return t < 0.5 and a or b
			end

			return lerp
		end

		factories["EmitModule.mod.logger"] = function()
			local function msg(...: string)
				return `[Eclipse Emit API]: {table.concat({ ... }, " ")}`
			end

			local logger = {}

			function logger.error(...)
				error(msg(..., "\n"))
			end

			function logger.warn(...)
				warn(msg(...))
				warn(msg(debug.traceback("stack trace:")))
			end

			function logger.info(...)
				print(msg(...))
			end

			return logger
		end

		factories["EmitModule.mod.shape"] = function()
			local utility = getModule("EmitModule.mod.utility")

			local shape = {}

			function shape.getSurfaceCFrame(cf: CFrame, n: Vector3, pos: Vector3)
				local up = math.abs(n:Dot(Vector3.yAxis)) > 0.99 and Vector3.zAxis or Vector3.yAxis
				local rot = CFrame.lookAt(Vector3.zero, n, up)
				return cf * CFrame.new(pos) * rot
			end

			function shape.getPointWithinBox(
				seed: number,
				cframe: CFrame,
				size: Vector3,
				normal: Enum.NormalId
			)
				debug.profilebegin("getPointWithinBox")

				local rng = Random.new(seed)

				local half = size / 2

				local pos = Vector3.new(
					rng:NextNumber(-1, 1),
					rng:NextNumber(-1, 1),
					rng:NextNumber(-1, 1)
				) * half

				local cf = shape.getSurfaceCFrame(cframe, Vector3.FromNormalId(normal), pos)

				debug.profileend()

				return cf
			end

			function shape.getPointOnBox(
				seed: number,
				cframe: CFrame,
				size: Vector3,
				normal: Enum.NormalId
			)
				debug.profilebegin("getPointOnBox")

				local rng = Random.new(seed)

				local n = Vector3.FromNormalId(normal)

				local half = size / 2
				local axes = Vector3.one - n:Abs()

				local s = Vector3.new(
					rng:NextNumber(-1, 1),
					rng:NextNumber(-1, 1),
					rng:NextNumber(-1, 1)
				) * half * axes

				local cf = shape.getSurfaceCFrame(cframe, n, s + n * half)

				debug.profileend()

				return cf
			end

			function shape.getPointWithinCylinder(
				seed: number,
				min_radius: number,
				partial: number,
				cframe: CFrame,
				size: Vector3,
				normal: Enum.NormalId
			)
				debug.profilebegin("getPointWithinCylinder")

				local rng = Random.new(seed)

				local r = math.sqrt(rng:NextNumber(min_radius, 1))
				local theta = rng:NextNumber(0, 2 * math.pi)

				if normal == Enum.NormalId.Left or normal == Enum.NormalId.Right then
					cframe *= CFrame.fromOrientation(
						0,
						math.pi / 2 * (normal == Enum.NormalId.Right and -1 or 1),
						0
					)
					size = Vector3.new(size.Z, size.Y, size.X)
				elseif normal == Enum.NormalId.Front or normal == Enum.NormalId.Back then
					cframe *= CFrame.fromOrientation(0, math.pi, 0)
				end

				local z = rng:NextNumber()
				local t = 1 - z ^ utility.lerp(0.5, 1, math.sqrt(partial))

				local width = utility.lerp(1, partial, t)

				local pos = Vector3.new(
					t * 2 - 1,
					r * math.sin(theta) * width,
					r * math.cos(theta) * width
				) * size / 2

				local pos2 = Vector3.new(0, math.sin(theta) * width, math.cos(theta) * width)
					* size
					/ 2

				local tangent = Vector3.new(0, math.cos(theta) * width, -math.sin(theta) * width)
					* size
					/ 2
				local up = tangent.Magnitude > 0.001 and tangent.Unit or cframe.UpVector
				local res = cframe * CFrame.new(pos) * CFrame.lookAt(Vector3.zero, pos2, up)

				debug.profileend()

				return res
			end

			function shape.getPointWithinSphere(
				seed: number,
				min_radius: number,
				partial: number,
				cframe: CFrame,
				size: Vector3,
				normal: Enum.NormalId
			)
				debug.profilebegin("getPointWithinSphere")

				local rng = Random.new(seed)

				local u = rng:NextNumber()
				local v = rng:NextNumber()

				local theta = u * 2 * math.pi
				local phi = math.acos(2 * v - 1) * partial
				local r = rng:NextNumber(min_radius, 1) ^ (1 / 3)

				local sinTheta = math.sin(theta)
				local cosTheta = math.cos(theta)
				local sinPhi = math.sin(phi)
				local cosPhi = math.cos(phi)

				local n = Vector3.FromNormalId(normal)

				if normal == Enum.NormalId.Left or normal == Enum.NormalId.Right then
					size = Vector3.new(size.Z, size.Y, size.X)
				elseif normal == Enum.NormalId.Top or normal == Enum.NormalId.Bottom then
					size = Vector3.new(size.X, size.Z, size.Y)
				end

				local half = size / 2
				local cf = shape.getSurfaceCFrame(cframe, n, Vector3.zero)

				local pos = Vector3.new(r * sinPhi * cosTheta, r * sinPhi * sinTheta, r * cosPhi)
					* half

				local tangent = Vector3.new(-sinPhi * sinTheta, sinPhi * cosTheta, 0) * half

				local up = if tangent.Magnitude > 0.001 then tangent.Unit else Vector3.new(1, 0, 0)
				local res = cf
					* CFrame.Angles(0, math.pi, 0)
					* CFrame.new(pos)
					* CFrame.lookAt(Vector3.zero, pos, up)

				debug.profileend()

				return res
			end

			function shape.getPointWithinDisc(
				seed: number,
				min_depth: number,
				partial: number,
				cframe: CFrame,
				size: Vector3,
				normal: Enum.NormalId
			)
				debug.profilebegin("getPointWithinDisc")

				local rng = Random.new(seed)

				local n = Vector3.FromNormalId(normal)
				local axes = Vector3.one - n:Abs() * min_depth

				local half = size / 2

				local z = rng:NextNumber(min_depth, 1)
				local d = utility.lerp(1, 0.5, partial ^ 4)

				local t = z

				local r = rng:NextNumber(1 - partial, 1) ^ d
				local theta = rng:NextNumber(0, 2 * math.pi)

				local s = Vector3.new(t * 2 - 1, r * math.sin(theta), r * math.cos(theta))

				if normal == Enum.NormalId.Bottom or normal == Enum.NormalId.Top then
					s = Vector3.new(s.Z, s.X, s.Y)
				elseif normal == Enum.NormalId.Front or normal == Enum.NormalId.Back then
					s = Vector3.new(s.Y, s.Z, s.X)
				end

				s *= half * axes

				local cf = shape.getSurfaceCFrame(cframe, n, s + n * min_depth * half)

				debug.profileend()

				return cf
			end

			return shape
		end

		factories["EmitModule.mod.tween"] = function()
			local RunService = game:GetService("RunService")

			local logger = getModule("EmitModule.mod.logger")
			local utility = getModule("EmitModule.mod.utility")

			local Bezier = getModule("EmitModule.obj.Bezier")

			local tween = {}

			function tween.fromParams(
				params: string,
				duration: number,
				animator: (
					alpha: number,
					deltaTime: number,
					elapsed: number
				) -> number?,
				awaitTween: RBXScriptConnection?,
				onFinish: (() -> ())?,
				startAtZero: boolean?,
				stepAtPriority: number?
			)
				local success, points = pcall(function()
					return utility.deserializePath(params)
				end)

				if not success then
					logger.error(`failed to decode bezier path data with error: {points}`)
				end

				local bezier = Bezier.new(points, 0)
				local elapsed = 0

				local cleanupStepper

				local function step(deltaTime)
					if not startAtZero and elapsed == 0 then
						elapsed = math.clamp(elapsed + deltaTime, 0, math.max(duration, 0))
					end

					local t = math.clamp(elapsed / duration, 0, 1)
					local alpha = 1 - bezier:getEase(t).y

					local result = animator(alpha, deltaTime, elapsed)

					if
						(
							result == nil
							or (if duration ~= 0 then elapsed >= duration else elapsed > duration)
						) and (not awaitTween or not awaitTween.Connected)
					then
						cleanupStepper()

						if onFinish then
							onFinish(true)
						end

						return
					end

					if result then
						elapsed = math.clamp(elapsed + result, 0, math.max(duration, 0.001))
					end
				end

				if not stepAtPriority then
					local connection: RBXScriptConnection
					connection = RunService.RenderStepped:Connect(step)

					cleanupStepper = function()
						connection:Disconnect()
					end

					return connection
				else
					local id = utility.getRanomId()

					RunService:BindToRenderStep(id, stepAtPriority, step)

					local bound = true

					cleanupStepper = function()
						if not bound then
							return
						end

						bound = false

						RunService:UnbindFromRenderStep(id)
					end

					return cleanupStepper
				end
			end

			function tween.timer(
				duration: number,
				counter: (deltaTime: number, elapsed: number) -> number,
				awaitTween: RBXScriptConnection?,
				scope: {}?,
				stepAtPriority: number?
			)
				local main = coroutine.running()

				local elapsed = 0

				local cleanupStepper

				local function step(deltaTime)
					local result = counter(deltaTime, elapsed)

					if
						(
							result == nil
							or (if duration ~= 0 then elapsed >= duration else elapsed > duration)
						) and (not awaitTween or not awaitTween.Connected)
					then
						cleanupStepper()
						task.spawn(main)
						return
					end

					if result then
						elapsed = math.clamp(elapsed + result, 0, math.max(duration, 0.001))
					end
				end

				if not stepAtPriority then
					local connection = RunService.RenderStepped:Connect(step)

					cleanupStepper = function()
						connection:Disconnect()
					end
				else
					local id = utility.getRanomId()

					RunService:BindToRenderStep(id, stepAtPriority, step)

					local bound = true

					cleanupStepper = function()
						if not bound then
							return
						end

						bound = false

						RunService:UnbindFromRenderStep(id)
					end
				end

				if scope then
					table.insert(scope, cleanupStepper)
				end

				coroutine.yield()
			end

			return tween
		end

		factories["EmitModule.mod.utility"] = function()
			local RunService = game:GetService("RunService")
			local PhysicsService = game:GetService("PhysicsService")

			local logger = getModule("EmitModule.mod.logger")

			type scope = {
				depth: number,
			}

			local utility = {}

			utility.DEG_TO_RAD = math.pi / 180

			utility.BEZIER_TAG = "BezierParticle"
			utility.SHOCKWAVE_TAG = "Shockwave"
			utility.SCREENSHAKE_TAG = "CameraShake"
			utility.ENABLED_VFX_TAG = "ConstantVFX"
			utility.TEXTURE_LOAD_TAG = "LoadVFXTextures"

			utility.RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

			utility.COLLISION_GROUPS = {
				StudioSelectable = {},

				ForgeDebris = {
					ForgeDebris = false,
				},

				ForgeMouseIgnore = {
					StudioSelectable = false,
				},
			}

			utility.COPY_SPECIALMESH_PROPERTIES = {
				"MeshId",
				"MeshType",
				"Offset",
				"Scale",
				"TextureId",
				"VertexColor",
			}

			utility.COPY_PART_PROPERTIES = {
				"CastShadow",

				"Color",

				"Material",
				"MaterialVariant",
				"Reflectance",

				"Shape",

				"FrontSurface",
				"BackSurface",
				"LeftSurface",
				"RightSurface",
				"TopSurface",
				"BottomSurface",
			}

			utility.COPY_EXTENDED_PART_PROPERTIES = {
				"Size",
				"Transparency",

				"CanCollide",
				"CanQuery",
				"CanTouch",

				"CollisionGroup",
			}

			local LOCKS = setmetatable({} :: { [Instance]: boolean }, { __mode = "k" })

			function utility.lock(ref: Instance)
				if LOCKS[ref] then
					return true
				end

				LOCKS[ref] = coroutine.running()

				return false
			end

			function utility.unlock(ref: Instance, key: thread?)
				local thread = LOCKS[ref]

				if coroutine.running() ~= thread and key ~= thread then
					logger.error("attempt to unlock an instance owned by a different thread")
				end

				LOCKS[ref] = nil
			end

			function utility.setCollisionGroups(groups)
				local rules = {}

				for name, list in groups do
					PhysicsService:RegisterCollisionGroup(name)

					if not name:match("Studio") or RunService:IsStudio() then
						rules[name] = list
					end
				end

				for name, list in rules do
					for group, collidable in list do
						if group:match("Studio") and not RunService:IsStudio() then
							continue
						end

						PhysicsService:CollisionGroupSetCollidable(name, group, collidable)
					end
				end
			end

			local bindingPrefix=game:GetService("HttpService"):GenerateGUID(false)..":"
			local last_id = 0

			function utility.getRanomId()
				last_id += 1
				return bindingPrefix..tostring(last_id)
			end

			function utility.copyProperties(from: Instance, to: Instance, list: { string })
				for _, k in list do
					to[k] = from[k]
				end
			end

			function utility.lerp(a: number, b: number, t: number)
				return a + (b - a) * t
			end

			function utility.try<R, A>(msg: string, func: (...A) -> ...R, ...: A): (boolean, ...R)
				local res = {
					xpcall(func, function(err)
						logger.warn(string.format(msg, err))
					end, ...),
				}

				return res[1], table.unpack(res, 2)
			end

			function utility.reboundfn<A>(sec: number, func: (...A) -> never): (...A) -> never
				local lastRunThread

				return function(...)
					if lastRunThread then
						task.cancel(lastRunThread)
					end

					local args = { ... }

					lastRunThread = task.delay(sec, function()
						lastRunThread = nil
						func(table.unpack(args))
					end)
				end
			end

			function utility.randomUnitVector(min: Vector3, max: Vector3, rng: Random?)
				if not rng then
					rng = Random.new()
				end

				return Vector3.new(
					rng:NextNumber(min.X, max.X),
					rng:NextNumber(min.Y, max.Y),
					rng:NextNumber(min.Z, max.Z)
				)
			end

			function utility.getImpulseForce(start: Vector3, goal: Vector3, duration: number)
				return (goal - start) / duration
					+ Vector3.new(0, workspace.Gravity * duration * 0.5, 0)
			end

			function utility.isMeshVFX(obj: Instance)
				return obj
					and obj:IsA("Model")
					and obj:FindFirstChild("Start")
					and obj.Start:IsA("BasePart")
					and obj:FindFirstChild("End")
					and obj.End:IsA("BasePart")
			end

			function utility.cleanupScope(scope: { unknown })
				for _, v in scope do
					local t = typeof(v)

					if t == "Instance" then
						v:Destroy()
					elseif t == "RBXScriptConnection" then
						v:Disconnect()
					elseif t == "thread" then
						if coroutine.status(v) ~= "dead" then
							task.cancel(v)
						end
					elseif t == "function" then
						task.spawn(v)
					elseif t == "table" then
						utility.cleanupScope(v)
					end
				end

				table.clear(scope)
			end

			function utility.protectParent(scope: { unknown }, parent: Instance)
				table.insert(
					scope,
					parent.AncestryChanged:Connect(function(_, new)
						if parent.Parent == workspace.Terrain then
							return
						end

						parent.Parent = workspace.Terrain
					end)
				)
			end

			function utility.findFirstClassWithTag(obj: Instance?, class: string, tag: string)
				if not obj or obj.Parent == game then
					return
				end

				if obj.ClassName == class and obj:HasTag(tag) then
					return obj
				else
					return utility.findFirstClassWithTag(obj.Parent, class, tag)
				end
			end

			function utility.cloneParticleAncestry(
				particle: ParticleEmitter,
				map: { [Instance]: Instance }?
			): (Instance, Instance)
				if
					not particle:FindFirstAncestorWhichIsA("BasePart")
					and not particle:FindFirstAncestorOfClass("Attachment")
				then
					return
				end

				local function findAncestor(obj: Instance)
					local ancestor = obj

					if
						obj.Parent and (obj.Parent:IsA("BasePart") or obj.Parent:IsA("Attachment"))
					then
						ancestor = findAncestor(obj.Parent)
					end

					return ancestor
				end

				local function recurse(obj: Instance)
					local created = map[obj]

					if created then
						return created,
							if obj == particle
								then map[obj.Parent]
								else map[findAncestor(obj.Parent)] or map[obj]
					end

					local clone = Instance.fromExisting(obj)
					clone.Archivable = false

					if clone:IsA("BasePart") then
						clone.Locked = true
					end

					local ancestor = clone

					if map then
						map[obj] = clone
					end

					if
						obj.Parent and (obj.Parent:IsA("BasePart") or obj.Parent:IsA("Attachment"))
					then
						local parent, pa = recurse(obj.Parent)

						if pa then
							ancestor = pa
						end

						if parent then
							clone.Parent = parent
						end
					end

					return clone, ancestor
				end

				return recurse(particle.Parent)
			end

			function utility.getAttribute<T>(
				obj: Instance,
				name: string,
				default: T,
				soft: boolean?
			): T
				local value = obj:GetAttribute(name)

				if value == nil or typeof(value) ~= typeof(default) then
					value = default
				end

				if not soft then
					obj:SetAttribute(name, value)
				end

				return value
			end

			function utility.getRangeAttribute(
				obj: Instance,
				name: string,
				default: NumberRange,
				clamp: NumberRange?,
				soft: boolean?
			)
				local value = obj:GetAttribute(name)

				if typeof(value) ~= "NumberRange" then
					value = default
				end

				if clamp then
					value = NumberRange.new(
						math.clamp(value.Min, clamp.Min, clamp.Max),
						math.clamp(value.Max, clamp.Min, clamp.Max)
					)
				end

				if not soft then
					obj:SetAttribute(name, value)
				end

				return value
			end

			function utility.getEnumAttribute<T>(
				obj: Instance,
				name: string,
				default: T,
				enums: { T },
				soft: boolean?
			): T
				local value = obj:GetAttribute(name)

				if value == nil or not table.find(enums, value) then
					value = default
				end

				if not soft then
					obj:SetAttribute(name, value)
				end

				return value
			end

			function utility.getMeshDecals(ref: Model, start: BasePart)
				local legacy_isFlipbook = utility.getAttribute(ref, "Flipbook", false, true)

				local decals = {}
				local flipbooks = {}
				local fromToMap = {}

				local function filter(list: { Instance }): { Decal }
					local filtered = {}

					for _, v in list do
						if v:IsA("Decal") then
							table.insert(filtered, v)
						end
					end

					return filtered
				end

				if legacy_isFlipbook then
					decals = filter(start:GetChildren())
				else
					local originalEnd = ref:FindFirstChild("End")
					local originalStart = ref:FindFirstChild("Start")

					if originalEnd then
						for _, v in start:GetChildren() do
							if not v:IsA("Decal") then
								continue
							end

							local from = v

							local to = originalEnd:FindFirstChild(v.Name)

							if not to or not to:IsA("Decal") then
								continue
							end

							table.insert(decals, v)

							fromToMap[from] = to

							if not v:GetAttribute("FlipbookEnabled") then
								table.insert(decals, v)
							else
								flipbooks[v] =
									utility.deserializeFlipbook(v:GetAttribute("FlipbookTextures"))
							end
						end

						for _, v in originalStart:GetChildren() do
							if not v:IsA("Decal") then
								continue
							end

							local children = v:GetChildren()

							do
								local offset = 0

								for i = 1, #children do
									i -= offset

									local obj = children[i]

									if not obj:IsA("Decal") then
										table.remove(children, i)
										offset += 1
									end
								end
							end

							if #children ~= 0 then
								local function idx(str: string)
									return tonumber(str:match("%d+")) or 0
								end

								table.sort(children, function(a, b)
									return idx(a.Name) < idx(b.Name)
								end)

								local ids = {}

								for _, obj in children do
									table.insert(ids, idx(obj.Texture))
									obj:Destroy()
								end

								local buf = utility.serializeFlipbook(ids)

								v:SetAttribute("FlipbookEnabled", true)
								v:SetAttribute("FlipbookTextures", buffer.tostring(buf))
							end
						end
					end
				end

				return decals, flipbooks, fromToMap
			end

			function utility.getBezierPoints(root: Attachment, metadata: boolean)
				local objs = root:GetChildren()

				table.sort(objs, function(a, b)
					return tonumber(a.Name) < tonumber(b.Name)
				end)

				local points: { vector } = {}
				local attachments: { Attachment } = {}
				local attachmentToPointMap: { [Attachment]: vector } = {}

				local function vec(p: Attachment)
					local w = root.WorldCFrame:PointToObjectSpace(p.WorldPosition)
					local pos = vector.create(w.X, w.Y, w.Z)

					table.insert(points, pos)

					if metadata then
						attachmentToPointMap[p] = pos
						table.insert(attachments, p)
					end

					return pos
				end

				for i, p in objs do
					local t0 = p:FindFirstChild("T0")
					local t1 = p:FindFirstChild("T1")

					if i == 1 then
						vec(p)
					end

					if i ~= 1 then
						if t1 then
							vec(t1)
						else
							vec(p)
						end
					end

					if i ~= 1 and i ~= #objs then
						vec(p)
					end

					if i ~= #objs then
						if t0 then
							vec(t0)
						else
							vec(p)
						end
					end

					if i == #objs then
						vec(p)
					end
				end

				return points, attachments, attachmentToPointMap
			end

			function utility.scaleNumberSequence(
				seq: NumberSequence,
				scale: number | (
					value: number,
					envelope: number
				) -> (number, number)
			)
				if scale == 1 then
					return seq
				end

				local scaled = {}

				for _, keypoint in seq.Keypoints do
					local value, envelope

					if typeof(scale) == "function" then
						value, envelope = scale(keypoint.Value, keypoint.Envelope)
					else
						value, envelope = keypoint.Value * scale, keypoint.Envelope * scale
					end

					table.insert(scaled, NumberSequenceKeypoint.new(keypoint.Time, value, envelope))
				end

				return NumberSequence.new(scaled)
			end

			@native
			function utility.serializePath(points: { Path2DControlPoint })
				local buf = buffer.create(#points * 4 * 6)

				local offset = 0

				for i, p in points do
					local px = p.Position.X.Scale
					local py = p.Position.Y.Scale

					if i ~= 1 then
						buffer.writef32(buf, offset, px + p.LeftTangent.X.Scale)
						buffer.writef32(buf, offset + 4, py + p.LeftTangent.Y.Scale)

						offset += 8
					end

					buffer.writef32(buf, offset, px)
					buffer.writef32(buf, offset + 4, py)

					offset += 8

					if i ~= #points then
						buffer.writef32(buf, offset, px + p.RightTangent.X.Scale)
						buffer.writef32(buf, offset + 4, py + p.RightTangent.Y.Scale)

						offset += 8
					end
				end

				return buf
			end

			@native
			function utility.deserializePath(data: string | buffer)
				local buf = typeof(data) == "string" and buffer.fromstring(data) or data
				local count = buffer.len(buf) / 24

				local points = {}

				for i = 0, count - 1 do
					local offset = i * 4 * 6

					local px = buffer.readf32(buf, offset)
					local py = buffer.readf32(buf, offset + 4)

					table.insert(points, vector.create(px, py))

					if i ~= count - 1 then
						local t1x = buffer.readf32(buf, offset + 8)
						local t1y = buffer.readf32(buf, offset + 12)

						local t2x = buffer.readf32(buf, offset + 16)
						local t2y = buffer.readf32(buf, offset + 20)

						table.insert(points, vector.create(t1x, t1y))
						table.insert(points, vector.create(t2x, t2y))
					end
				end

				return points
			end

			@native
			function utility.serializeFlipbook(ids: { number })
				local buf = buffer.create(#ids * 8)

				for i, id in ids do
					buffer.writef64(buf, (i - 1) * 8, id)
				end

				return buf
			end

			@native
			function utility.deserializeFlipbook(data: string | buffer)
				local buf = typeof(data) == "string" and buffer.fromstring(data) or data
				local count = buffer.len(buf) / 8

				local ids = {}

				for i = 0, count - 1 do
					table.insert(ids, buffer.readf64(buf, i * 8))
				end

				return ids
			end

			utility.default_bezier = buffer.tostring(utility.serializePath({
				Path2DControlPoint.new(
					UDim2.fromScale(0, 1),
					UDim2.new(),
					UDim2.fromScale(0.215, -0.61)
				),
				Path2DControlPoint.new(
					UDim2.fromScale(1, 0),
					UDim2.fromScale(-0.645, 0),
					UDim2.new()
				),
			}))

			utility.linear_bezier = buffer.tostring(utility.serializePath({
				Path2DControlPoint.new(UDim2.fromScale(0, 1)),
				Path2DControlPoint.new(UDim2.fromScale(1, 0)),
			}))

			return utility
		end

		factories["EmitModule.obj.Bezier"] = function()
			type n = vector | number

			local NEWTON_MIN_TOL = 0.001
			local NEWTON_MAX_ITER = 5

			local function cubicBezier(p0: n, p1: n, p2: n, p3: n, t: n): n
				return (1 - t) ^ 3 * p0
					+ 3 * (1 - t) ^ 2 * t * p1
					+ 3 * (1 - t) * t ^ 2 * p2
					+ t ^ 3 * p3
			end

			local function cubicBezierDerivative(p0: n, p1: n, p2: n, p3: n, t: n): n
				return 3 * (1 - t) ^ 2 * (p1 - p0)
					+ 6 * (1 - t) * t * (p2 - p1)
					+ 3 * t ^ 2 * (p3 - p2)
			end

			local bezier = {}
			bezier.__index = bezier

			type Bezier = typeof(bezier) & {
				points: { vector },
				cumulative_lengths: { number },

				length: number,
				accuracy: number,
				point_count: number,
			}

			function bezier.new(points: { vector }, samplingAccuracy: number?)
				local self = setmetatable({}, bezier)

				self.points = points
				self.accuracy = samplingAccuracy or 20

				self.point_count = 0
				self.cumulative_lengths = {}

				self:_recalculate()

				return self
			end

			function bezier.setPoints(self: Bezier, points: { vector })
				self.points = points
				self:_recalculate()
			end

			function bezier.getSegmentPoints(self: Bezier, index: number)
				if index < 1 or index > self.point_count - 1 then
					if index <= 0 then
						return vector.zero, vector.zero, vector.zero, vector.zero
					end

					error("attempt to get a non-existent segment at index " .. index)
				end

				local offset = (index - 1) * 4 - math.max(index - 2, 0)
				local start = math.max(offset, 1)

				local p0 = self.points[start]
				local p1 = self.points[start + 1]
				local p2 = self.points[start + 2]
				local p3 = self.points[start + 3]

				return p0, p1, p2, p3
			end

			function bezier.forSample(
				self: Bezier,
				size: number,
				callback: (pos: vector, i: number) -> ()
			)
				local amount = self.length // size

				if amount == 0 then
					return
				end

				for i = 0, amount do
					local t = i / amount
					callback(self:getPositionArcSpace(t), i)
				end
			end

			function bezier.getPosition(self: Bezier, t: number)
				local i, u = self:getSegmentIndex(t)
				local p0, p1, p2, p3 = self:getSegmentPoints(i)

				return cubicBezier(p0, p1, p2, p3, u)
			end

			function bezier.getSegmentIndex(self: Bezier, t: number)
				t = math.clamp(t, 0, 1)

				local m = self.point_count - 1
				local s = t * m

				local i = math.min(math.floor(s) + 1, m)
				local u = s - math.floor(s)

				if t == 1 then
					u = 1
				end

				return i, u
			end

			function bezier.getEasedSegmentIndex(self: Bezier, t: number)
				local i = self.point_count - 1
				local u = 1

				for j = 1, i do
					local p0, _, _, p3 = self:getSegmentPoints(j)

					local start = p0.x
					local stop = p3.x

					if t >= start and t < stop then
						i = j
						u = (t - start) / (stop - start)

						break
					end
				end

				return i, u
			end

			function bezier.getEase(self: Bezier, t: number)
				local i, s = self:getEasedSegmentIndex(t)
				local p0, p1, p2, p3 = self:getSegmentPoints(i)

				for i = 1, NEWTON_MAX_ITER do
					local x = cubicBezier(p0.x, p1.x, p2.x, p3.x, s)
					local dx = cubicBezierDerivative(p0.x, p1.x, p2.x, p3.x, s)

					if dx == 0 then
						break
					end

					local ds = (x - t) / dx
					s = s - ds

					if s < 0 then
						s = 0
					elseif s > 1 then
						s = 1
					end

					if math.abs(ds) < NEWTON_MIN_TOL then
						break
					end
				end

				return cubicBezier(p0, p1, p2, p3, s)
			end

			function bezier.getPositionArcSpace(self: Bezier, t: number)
				if self.length <= 0 then
					return self.points[1] or vector.zero
				end

				t = math.clamp(t, 0, 1)

				local targetLength = t * self.cumulative_lengths[self.accuracy + 1]
				local low, high, index = 1, self.accuracy + 1, nil

				while low < high do
					index = low + (high - low) // 2

					if self.cumulative_lengths[index] < targetLength then
						low = index + 1
					else
						high = index
					end
				end

				if self.cumulative_lengths[index] > targetLength and index > 1 then
					index -= 1
				end

				local lengthBefore = self.cumulative_lengths[index]

				if lengthBefore == targetLength then
					return self:getPosition((index - 1) / self.accuracy)
				else
					return self:getPosition(
						(
							(index - 1)
							+ (targetLength - lengthBefore)
								/ (self.cumulative_lengths[index + 1] - lengthBefore)
						) / self.accuracy
					)
				end
			end

			function bezier._recalculate(self: Bezier)
				table.clear(self.cumulative_lengths)
				table.insert(self.cumulative_lengths, 0)

				local count = math.ceil(#self.points / 3)

				self.point_count = count

				local total = 0

				local prev: vector

				for j = 1, self.accuracy do
					local p = self:getPosition(j / self.accuracy)

					if not prev then
						prev = self:getPosition(0)
					end

					total += vector.magnitude(p - prev)
					prev = p

					table.insert(self.cumulative_lengths, total)
				end

				self.length = total

				for i, len in self.cumulative_lengths do
					self.cumulative_lengths[i] = len / total
				end
			end

			return bezier
		end

		factories["EmitModule.obj.ObjectCache"] = function()
			local utility = getModule("EmitModule.mod.utility")

			local RECYCLE_INTERVAL = 15

			local cache = {}
			cache.__index = cache

			type item = {
				key: any,
				value: Instance,

				added: number,
				dependents: number,
			}

			type params = {
				size: number?,
				excess_lifetime: number?,
				on_free: ((item) -> ())?,
			}

			type ObjectCache = typeof(cache) & {
				ref: Instance,
				parent: Instance?,

				params: params,

				amount: number,
				restore_amount: number,

				part_mode: boolean,

				item_map: { [any]: item },
				unused: { item },

				scope: { unknown },
			}

			local function reconcile(a, b)
				for k, v in b do
					if a[k] == nil then
						a[k] = v
					end
				end

				return a
			end

			local moveParts: { BasePart } = table.create(10_000)
			local movePartCFrames: { CFrame } = table.create(10_000)

			local partUpdateScheduled = false

			local bulkPartMoveThread = coroutine.create(function()
				while true do
					workspace:BulkMoveTo(
						moveParts,
						movePartCFrames,
						Enum.BulkMoveMode.FireCFrameChanged
					)

					table.clear(moveParts)
					table.clear(movePartCFrames)

					partUpdateScheduled = false

					coroutine.yield()
				end
			end)

			function cache.new(ref: Instance, parent: Instance?, params: params?)
				local self = setmetatable({}, cache)

				self.ref = ref
				self.parent = parent

				self.amount = 0
				self.restore_amount = 0

				self.params = reconcile(params or {}, {
					size = 100,
					excess_lifetime = 30,
				})

				self.scope = { ref, parent }
				self.unused = table.create(self.params.size)
				self.item_map = {}

				self.part_mode = ref:IsA("BasePart")

				for _ = 1, self.params.size do
					self:_add()
				end

				table.insert(
					self.scope,
					task.spawn(function()
						while task.wait(RECYCLE_INTERVAL) do
							if self.restore_amount > 0 then
								for _ = 1, self.restore_amount do
									self:_add()
									self.restore_amount -= 1
								end
							end

							if self.amount <= self.params.size then
								continue
							end

							local offset = 0

							for i = 1, #self.unused do
								if self.amount <= self.params.size then
									break
								end

								i -= offset

								local item = self.unused[i]

								if
									item.dependents ~= 0
									or (os.clock() - item.added) > self.params.excess_lifetime
								then
									continue
								end

								item:destroy()

								table.remove(self.unused, i)

								self.item_map[item.key] = nil
								self.amount -= 1

								offset += 1
							end
						end
					end)
				)

				return self
			end

			function cache._add(self: ObjectCache, key: any?, excess: boolean?)
				local obj = self.ref:Clone()
				obj.Archivable = false
				obj.Parent = self.parent

				local item = {
					key = key,
					value = obj,

					added = os.clock(),
					dependents = 1,
				}

				local ignoreDestroy = false

				function item:destroy()
					ignoreDestroy = true
					obj:Destroy()
				end

				self.amount += 1

				obj.Destroying:Connect(function()
					if ignoreDestroy then
						return
					end

					local index = table.find(self.unused, item)

					if index then
						table.remove(self.unused, index)
					end

					if item.key then
						self.item_map[item.key] = nil
					end

					self.amount -= 1
					self.restore_amount += 1
				end)

				if key then
					self.item_map[key] = item
				end

				if not excess then
					table.insert(self.unused, item)
				end

				return item
			end

			function cache.has(self: ObjectCache, key: any)
				return if self.item_map[key] then true else false
			end

			function cache.peek(self: ObjectCache, key: any)
				return self.item_map[key]
			end

			function cache.get(self: ObjectCache, key: any)
				if self:has(key) then
					local item = self:peek(key)

					if item then
						item.dependents += 1
					end

					return item.value
				end

				local item = table.remove(self.unused)

				if item then
					item.key = key
					item.added = os.clock()

					self.item_map[key] = item
				else
					item = self:_add(key, true)
				end

				if self.part_mode then
					local meta = {}

					function meta:__newindex(key, value)
						if key == "CFrame" then
							table.insert(moveParts, item.value)
							table.insert(movePartCFrames, value)

							if not partUpdateScheduled then
								partUpdateScheduled = true
								task.defer(bulkPartMoveThread)
							end
						else
							item.value[key] = value
						end
					end

					function meta:__index(key)
						local v = item.value[key]

						if typeof(v) == "function" then
							return function(_, ...)
								return v(item.value, ...)
							end
						else
							return v
						end
					end

					return setmetatable({
						_getReal = function()
							return item.value
						end,
					}, meta)
				else
					return item.value
				end
			end

			function cache.free(self: ObjectCache, key: any)
				local item = self.item_map[key]

				if not item then
					return
				end

				item.dependents = math.max(item.dependents - 1, 0)

				if item.dependents == 0 then
					item.added = os.clock()

					if self.params.on_free then
						task.spawn(self.params.on_free, item)
					end

					table.insert(self.unused, item)
				end
			end

			function cache.destroy(self: ObjectCache)
				utility.cleanupScope(self.scope)

				for _, item in self.item_map do
					item.value:Destroy()
				end

				table.clear(self.unused)
				table.clear(self.item_map)
			end

			return cache
		end

		factories["EmitModule.pkg.EclipsePromise"] = function()
			return sharedLibraries.EclipsePromise(libraryEnvironment, sharedLibraries)
		end

		factories["EmitModule.pkg.EclipseShake"] = function()
			return sharedLibraries.EclipseShake(libraryEnvironment, sharedLibraries)
		end

		factories["EmitVFX.Emit"] = function()
			local GraphMod = getModule("EmitVFX.Graph")
			local RangeMod = getModule("EmitVFX.Range")
			local ParticlesMod = getModule("EmitVFX.Particles")
			local MeshFlipMod = getModule("EmitVFX.Flipbook")
			local Constants = getModule("EmitVFX.PartConstants")
			local DirectionVectors = Constants.DirectionVectors
			local shapeFunctions = Constants.shapeFunctions

			return function(Particle)
				function Particle:EmitPart(part, link)
					local data = self:GetData(part)
					if not data or not data.RenderTemplate then
						return
					end
					link = link or data.Link

					local Time = RangeMod.RandomValueFromRange(data.Lifetime)
					if Time <= 0 then
						Time = 0.001
					end

					local unrotatedCF
					if link then
						local isAtt = link:IsA("Attachment")
						local lPos = isAtt and link.WorldPosition or link.Position
						local lCF = isAtt and link.WorldCFrame or link.CFrame
						if data.LinkMode == "Follow" then
							unrotatedCF = CFrame.new(lPos) * part.CFrame.Rotation
						else
							unrotatedCF = CFrame.new(lPos) * lCF.Rotation * part.CFrame.Rotation
						end
					else
						unrotatedCF = part.CFrame
					end
					local dirInfo = DirectionVectors[data.EmissionDirection]
						or DirectionVectors[Enum.NormalId.Top]
					local rawWorldDirection = unrotatedCF[dirInfo.vector] * dirInfo.multiplier

					local shapeFunc = shapeFunctions[data.ParticleData.Shape]
					local localOffset = Vector3.new()
					local localRotation = CFrame.new()

					if
						shapeFunc
						and data.ParticleData.ShapeInOut
							== Enum.ParticleEmitterShapeInOut.InAndOut
					then
						localOffset, localRotation = shapeFunc(part, data.ParticleData)
					end

					local initialCF = unrotatedCF
					if
						typeof(localRotation) == "CFrame"
						and data.ParticleData.ShapeStyle
							== Enum.ParticleEmitterShapeStyle.Surface
					then
						local rx, ry, rz = initialCF:ToEulerAnglesXYZ()
						initialCF = CFrame.new((initialCF * CFrame.new(localOffset)).Position)
							* localRotation
							* CFrame.Angles(rx, ry, rz)
					else
						initialCF = CFrame.new((initialCF * CFrame.new(localOffset)).Position)
							* initialCF.Rotation
					end

					local RX = RangeMod.RandomValueFromRange(data.RotX)
					local RY = RangeMod.RandomValueFromRange(data.RotY)
					local RZ = RangeMod.RandomValueFromRange(data.RotZ)
					initialCF = initialCF * CFrame.Angles(math.rad(RX), math.rad(RY), math.rad(RZ))

					local baseDirection
					if data.VelocityVectored then
						baseDirection = initialCF[dirInfo.vector] * dirInfo.multiplier
					else
						baseDirection = rawWorldDirection
					end

					local randomX, randomY = 0, 0
					if
						data.ParticleData.SpreadAngle.X > 0
						or data.ParticleData.SpreadAngle.Y > 0
					then
						randomX = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.X
						randomY = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.Y
					end
					local spreadRotation = CFrame.Angles(math.rad(randomX), math.rad(randomY), 0)

					local cf = CFrame.lookAt(Vector3.new(), baseDirection)
					cf = cf * spreadRotation
					baseDirection = cf.LookVector

					local seeds = {
						SizeX = GraphMod.GenerateSeed(data.SizeX),
						SizeY = GraphMod.GenerateSeed(data.SizeY),
						SizeZ = GraphMod.GenerateSeed(data.SizeZ),
						RotSpeedX = GraphMod.GenerateSeed(data.RotSpeedX),
						RotSpeedY = GraphMod.GenerateSeed(data.RotSpeedY),
						RotSpeedZ = GraphMod.GenerateSeed(data.RotSpeedZ),
						Speed = GraphMod.GenerateSeed(data.Speed),
						Brightness = GraphMod.GenerateSeed(data.Brightness),
						Transparency = GraphMod.GenerateSeed(data.Transparency),
					}

					local invertMotion = data.InvertMotion
					local simLocalCFrames = nil

					if invertMotion then
						simLocalCFrames = self:PreSimulateForward(
							data,
							seeds,
							initialCF,
							baseDirection,
							spreadRotation,
							link,
							Time
						)
					end

					local visualPart = data.RenderTemplate:Clone()
					local parentCF_now
					if link then
						local isA = link:IsA("Attachment")
						local lP = isA and link.WorldPosition or link.Position
						local lC = isA and link.WorldCFrame or link.CFrame
						parentCF_now = data.LinkMode == "Follow" and CFrame.new(lP) or lC
					else
						parentCF_now = CFrame.new()
					end
					local localCF

					if invertMotion and simLocalCFrames then
						local endLocalCF = simLocalCFrames[data.TotalKeyFrames]
							or simLocalCFrames[0]
						localCF = endLocalCF
						visualPart.CFrame = parentCF_now * localCF
					else
						localCF = link and parentCF_now:ToObjectSpace(initialCF) or initialCF
						visualPart.CFrame = parentCF_now * localCF
					end

					local pData = {
						Type = "Part",
						VisualPart = visualPart,
						Link = link,
						LinkMode = data.LinkMode,
						SpecialMesh = visualPart:FindFirstChildOfClass("SpecialMesh"),
						Decal = visualPart:FindFirstChildOfClass("Decal"),

						StartTime = os.clock(),
						TotalKeyFrames = math.max(1, data.TotalKeyFrames),
						CurrentStep = 0,
						AccumulatedDT = 0,
						LifeTime = Time,
						PartLife = data.PartLife,
						CurrentPosition = visualPart.Position,
						LocalCF = localCF,

						BaseDirection = baseDirection,
						EmissionDirection = data.EmissionDirection,
						SpreadRotation = spreadRotation,
						Acceleration = data.ParticleData.Acceleration,
						Drag = data.ParticleData.Drag,
						VelocityVectored = data.VelocityVectored,

						InvertMotion = invertMotion,
						SimLocalCFrames = simLocalCFrames,

						RotMode = data.RotMode or "OverLife",
						AccRotX = 0,
						AccRotY = 0,
						AccRotZ = 0,

						NeedsFullIteration = data.VelocityVectored,
						NeedsRotAccum = (data.RotMode == "Speed") and not data.VelocityVectored,
						HasDrag = data.ParticleData.Drag ~= 0,
						HasAccel = data.ParticleData.Acceleration.Magnitude > 0,
						HasDecal = visualPart:FindFirstChildOfClass("Decal") ~= nil,

						Graphs = {
							SizeX = data.SizeX,
							SizeY = data.SizeY,
							SizeZ = data.SizeZ,
							RotSpeedX = data.RotSpeedX,
							RotSpeedY = data.RotSpeedY,
							RotSpeedZ = data.RotSpeedZ,
							Speed = data.Speed,
							Brightness = data.Brightness,
							Transparency = data.Transparency,
							Color = data.Color,
						},

						Seeds = seeds,
					}

					local startSize = Vector3.new(
						GraphMod.QueryPointsWithTime(0, pData.Graphs.SizeX, pData.Seeds.SizeX),
						GraphMod.QueryPointsWithTime(0, pData.Graphs.SizeY, pData.Seeds.SizeY),
						GraphMod.QueryPointsWithTime(0, pData.Graphs.SizeZ, pData.Seeds.SizeZ)
					)
					local startTrans = GraphMod.QueryPointsWithTime(
						0,
						pData.Graphs.Transparency,
						pData.Seeds.Transparency
					)
					local startColor = GraphMod.QueryColorPointWithTime(0, pData.Graphs.Color)
					local startBright = GraphMod.QueryPointsWithTime(
						0,
						pData.Graphs.Brightness,
						pData.Seeds.Brightness
					)

					if pData.SpecialMesh then
						pData.SpecialMesh.Scale = startSize
					else
						pData.VisualPart.Size = startSize
					end

					if pData.Decal then
						pData.Decal.Transparency = startTrans
						pData.Decal.Color3 = Color3.fromRGB(
							startColor.R * 255 * startBright,
							startColor.G * 255 * startBright,
							startColor.B * 255 * startBright
						)
					else
						pData.VisualPart.Transparency = startTrans
						pData.VisualPart.Color = startColor
					end

					visualPart.Parent = data.EmitParent or self:GetFolder()

					for _, desc in visualPart:GetDescendants() do
						if desc:IsA("ParticleEmitter") then
							desc.Enabled = false
						end
					end
					for _, child in visualPart:GetChildren() do
						if child:IsA("Attachment") then
							ParticlesMod.EnableEmitChildrenAndRepeatForAttachments(child)
						end
						ParticlesMod.EnableEmitSingle(child)
					end

					table.insert(self.ActiveEmits, pData)

					if pData.Decal and data.CachedMeshTextures and #data.CachedMeshTextures > 0 then
						MeshFlipMod.Flip(
							data.ParticleData,
							data.CachedMeshTextures,
							pData.Decal,
							Time
						)
					end

					for _, child in visualPart:GetChildren() do
						if child:GetAttribute("Transformed") then
							self:EnableEmit(child, visualPart)
						end
					end
				end

				function Particle:EmitAttachment(attachment, link)
					local data = self:GetData(attachment)
					if not data or not data.RenderTemplate then
						return
					end
					link = link or data.Link

					local Time = RangeMod.RandomValueFromRange(data.Lifetime)
					if Time <= 0 then
						Time = 0.001
					end

					local localCF = attachment.CFrame
					local dirInfo = DirectionVectors[data.EmissionDirection]
						or DirectionVectors[Enum.NormalId.Top]
					local baseDirection = CFrame.new(
						Vector3.new(),
						localCF[dirInfo.vector] * dirInfo.multiplier
					).LookVector

					local RX = RangeMod.RandomValueFromRange(data.RotX)
					local RY = RangeMod.RandomValueFromRange(data.RotY)
					local RZ = RangeMod.RandomValueFromRange(data.RotZ)
					localCF = localCF * CFrame.Angles(math.rad(RX), math.rad(RY), math.rad(RZ))

					local randomX, randomY = 0, 0
					if
						data.ParticleData.SpreadAngle.X > 0
						or data.ParticleData.SpreadAngle.Y > 0
					then
						randomX = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.X
						randomY = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.Y
					end
					local spreadRotation = CFrame.Angles(math.rad(randomX), math.rad(randomY), 0)

					local cf = CFrame.lookAt(Vector3.new(), baseDirection)
					cf = cf * spreadRotation
					baseDirection = cf.LookVector

					local seeds = {
						Speed = GraphMod.GenerateSeed(data.Speed),
						RotSpeedX = GraphMod.GenerateSeed(data.RotSpeedX),
						RotSpeedY = GraphMod.GenerateSeed(data.RotSpeedY),
						RotSpeedZ = GraphMod.GenerateSeed(data.RotSpeedZ),
					}

					local invertMotion = data.InvertMotion
					local simLocalCFrames = nil

					if invertMotion then
						simLocalCFrames = self:PreSimulateAttachmentForward(
							data,
							seeds,
							localCF,
							baseDirection,
							spreadRotation,
							Time
						)
					end

					local visualAttachment = data.RenderTemplate:Clone()

					if invertMotion and simLocalCFrames then
						local endLocalCF = simLocalCFrames[data.TotalKeyFrames]
							or simLocalCFrames[0]
						localCF = endLocalCF
					end

					local actualParent = data.EmitParent or link or attachment.Parent
					local originalParent = attachment.Parent
					if actualParent and actualParent ~= originalParent then
						local worldCF = originalParent:IsA("BasePart")
								and (originalParent.CFrame * localCF)
							or localCF
						localCF = actualParent:IsA("BasePart")
								and actualParent.CFrame:ToObjectSpace(worldCF)
							or worldCF
					end

					visualAttachment.CFrame = localCF
					visualAttachment.Parent = actualParent

					local pData = {
						Type = "Attachment",
						VisualPart = visualAttachment,
						Link = link,
						LinkMode = data.LinkMode,

						StartTime = os.clock(),
						TotalKeyFrames = math.max(1, data.TotalKeyFrames),
						CurrentStep = 0,
						AccumulatedDT = 0,
						LifeTime = Time,
						PartLife = data.PartLife,
						LocalCF = localCF,

						BaseDirection = baseDirection,
						EmissionDirection = data.EmissionDirection,
						SpreadRotation = spreadRotation,
						Acceleration = data.ParticleData.Acceleration,
						Drag = data.ParticleData.Drag,
						VelocityVectored = data.VelocityVectored,

						InvertMotion = invertMotion,
						SimLocalCFrames = simLocalCFrames,

						RotMode = data.RotMode or "OverLife",
						AccRotX = 0,
						AccRotY = 0,
						AccRotZ = 0,

						NeedsFullIteration = data.VelocityVectored,
						NeedsRotAccum = (data.RotMode == "Speed") and not data.VelocityVectored,
						HasDrag = data.ParticleData.Drag ~= 0,
						HasAccel = data.ParticleData.Acceleration.Magnitude > 0,

						Graphs = {
							Speed = data.Speed,
							RotSpeedX = data.RotSpeedX,
							RotSpeedY = data.RotSpeedY,
							RotSpeedZ = data.RotSpeedZ,
						},
						Seeds = seeds,
					}

					table.insert(self.ActiveEmits, pData)

					for _, child in visualAttachment:GetChildren() do
						if child:GetAttribute("Transformed") then
							self:EnableEmit(child, visualAttachment.Parent)
						end
					end
				end

				function Particle:EmitBeam(beam, link)
					local data = self:GetData(beam)
					if not data or not data.RenderTemplate then
						return
					end

					local visualBeam = data.RenderTemplate:Clone()
					visualBeam.Enabled = true
					if data.FaceCamera ~= nil then
						visualBeam.FaceCamera = data.FaceCamera
					end
					visualBeam.Parent = data.EmitParent or self:GetFolder()

					local animatedProps = {}
					for name, sequence in pairs(data.BeamProps) do
						if sequence then
							if GraphMod.IsStatic(sequence) then
								visualBeam[name] =
									GraphMod.GetStaticValue(sequence, visualBeam[name])
							else
								animatedProps[name] =
									{ Sequence = sequence, Seed = GraphMod.GenerateSeed(sequence) }
							end
						end
					end

					local transStates, colorStates = GraphMod.CollectGraphStates(data.GraphBlender)

					local transMergedTimes = {}
					for idx = 1, #transStates - 1 do
						transMergedTimes[idx] = GraphMod.PrecomputeMergedTimes(
							transStates[idx].Graph,
							transStates[idx + 1].Graph
						)
					end
					local colorMergedTimes = {}
					for idx = 1, #colorStates - 1 do
						colorMergedTimes[idx] = GraphMod.PrecomputeMergedColorTimes(
							colorStates[idx].Graph,
							colorStates[idx + 1].Graph
						)
					end

					if #transStates > 0 then
						visualBeam.Transparency = transStates[1].Graph
					end
					if #colorStates > 0 then
						visualBeam.Color = colorStates[1].Graph
					end

					local safeLifeTime = RangeMod.RandomValueFromRange(data.Lifetime)
					if safeLifeTime <= 0 then
						safeLifeTime = 0.001
					end

					local pData = {
						Type = "Beam",
						VisualPart = visualBeam,
						Link = link,
						StartTime = os.clock(),
						TotalKeyFrames = math.max(1, data.TotalKeyFrames),
						CurrentStep = 0,
						LifeTime = safeLifeTime,
						PartLife = 0,

						AnimatedProps = animatedProps,

						TransStates = transStates,
						ColorStates = colorStates,
						TransMergedTimes = transMergedTimes,
						ColorMergedTimes = colorMergedTimes,
					}

					table.insert(self.ActiveEmits, pData)

					if
						data.CachedBeamTextures
						and #data.CachedBeamTextures > 0
						and data.FlipbookParticle
					then
						MeshFlipMod.FlipBeam(
							data.FlipbookParticle,
							data.CachedBeamTextures,
							visualBeam,
							safeLifeTime
						)
					end
				end
			end
		end

		factories["EmitVFX.EmitAnimate"] = function()
			local GraphMod = getModule("EmitVFX.Graph")
			local RangeMod = getModule("EmitVFX.Range")
			local ParticlesMod = getModule("EmitVFX.Particles")
			local Constants = getModule("EmitVFX.PartConstants")
			local DirectionVectors = Constants.DirectionVectors
			local shapeFunctions = Constants.shapeFunctions

			return function(Particle)
				function Particle:EmitPartAnimate(part, link)
					local data = self:GetData(part)
					if not data or not data.RenderTemplate then
						return
					end
					link = link or data.Link

					local Time = RangeMod.RandomValueFromRange(data.Lifetime)
					if Time <= 0 then
						Time = 0.001
					end
					local animateLoop = part:GetAttribute("AnimateLoop") or false

					local visualPart = data.RenderTemplate
					local initialWorldCF = visualPart.CFrame

					local unrotatedCF = part.CFrame
					local dirInfo = DirectionVectors[data.EmissionDirection]
						or DirectionVectors[Enum.NormalId.Top]
					local rawWorldDirection = unrotatedCF[dirInfo.vector] * dirInfo.multiplier

					local shapeFunc = shapeFunctions[data.ParticleData.Shape]
					local localOffset = Vector3.new()
					local localRotation = CFrame.new()

					if
						shapeFunc
						and data.ParticleData.ShapeInOut
							== Enum.ParticleEmitterShapeInOut.InAndOut
					then
						localOffset, localRotation = shapeFunc(part, data.ParticleData)
					end

					local initialCF = unrotatedCF
					if
						typeof(localRotation) == "CFrame"
						and data.ParticleData.ShapeStyle
							== Enum.ParticleEmitterShapeStyle.Surface
					then
						local rx, ry, rz = initialCF:ToEulerAnglesXYZ()
						initialCF = CFrame.new((initialCF * CFrame.new(localOffset)).Position)
							* localRotation
							* CFrame.Angles(rx, ry, rz)
					else
						initialCF = CFrame.new((initialCF * CFrame.new(localOffset)).Position)
							* initialCF.Rotation
					end

					local RX = RangeMod.RandomValueFromRange(data.RotX)
					local RY = RangeMod.RandomValueFromRange(data.RotY)
					local RZ = RangeMod.RandomValueFromRange(data.RotZ)
					initialCF = initialCF * CFrame.Angles(math.rad(RX), math.rad(RY), math.rad(RZ))

					local baseDirection
					if data.VelocityVectored then
						baseDirection = initialCF[dirInfo.vector] * dirInfo.multiplier
					else
						baseDirection = rawWorldDirection
					end

					local randomX, randomY = 0, 0
					if
						data.ParticleData.SpreadAngle.X > 0
						or data.ParticleData.SpreadAngle.Y > 0
					then
						randomX = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.X
						randomY = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.Y
					end
					local spreadRotation = CFrame.Angles(math.rad(randomX), math.rad(randomY), 0)
					local cf = CFrame.lookAt(Vector3.new(), baseDirection)
					cf = cf * spreadRotation
					baseDirection = cf.LookVector

					local seeds = {
						SizeX = GraphMod.GenerateSeed(data.SizeX),
						SizeY = GraphMod.GenerateSeed(data.SizeY),
						SizeZ = GraphMod.GenerateSeed(data.SizeZ),
						RotSpeedX = GraphMod.GenerateSeed(data.RotSpeedX),
						RotSpeedY = GraphMod.GenerateSeed(data.RotSpeedY),
						RotSpeedZ = GraphMod.GenerateSeed(data.RotSpeedZ),
						Speed = GraphMod.GenerateSeed(data.Speed),
						Brightness = GraphMod.GenerateSeed(data.Brightness),
						Transparency = GraphMod.GenerateSeed(data.Transparency),
					}

					local invertMotion = data.InvertMotion
					local simLocalCFrames = nil
					if invertMotion then
						simLocalCFrames = self:PreSimulateForward(
							data,
							seeds,
							initialCF,
							baseDirection,
							spreadRotation,
							link,
							Time
						)
					end

					local parentCF_now
					if link then
						local isA = link:IsA("Attachment")
						local lP = isA and link.WorldPosition or link.Position
						local lC = isA and link.WorldCFrame or link.CFrame
						parentCF_now = data.LinkMode == "Follow" and CFrame.new(lP) or lC
					else
						parentCF_now = CFrame.new()
					end
					local localCF
					if invertMotion and simLocalCFrames then
						local endLocalCF = simLocalCFrames[data.TotalKeyFrames]
							or simLocalCFrames[0]
						localCF = endLocalCF
					else
						localCF = link and parentCF_now:ToObjectSpace(initialCF) or initialCF
					end
					visualPart.CFrame = parentCF_now * localCF

					local pData = {
						Type = "Part",
						VisualPart = visualPart,
						Link = link,
						LinkMode = data.LinkMode,
						SpecialMesh = visualPart:FindFirstChildOfClass("SpecialMesh"),
						Decal = visualPart:FindFirstChildOfClass("Decal"),

						StartTime = os.clock(),
						TotalKeyFrames = math.max(1, data.TotalKeyFrames),
						CurrentStep = 0,
						AccumulatedDT = 0,
						LifeTime = Time,
						PartLife = 0,
						CurrentPosition = visualPart.Position,
						LocalCF = localCF,

						BaseDirection = baseDirection,
						EmissionDirection = data.EmissionDirection,
						SpreadRotation = spreadRotation,
						Acceleration = data.ParticleData.Acceleration,
						Drag = data.ParticleData.Drag,
						VelocityVectored = data.VelocityVectored,

						InvertMotion = invertMotion,
						SimLocalCFrames = simLocalCFrames,

						RotMode = data.RotMode or "OverLife",
						AccRotX = 0,
						AccRotY = 0,
						AccRotZ = 0,

						NeedsFullIteration = data.VelocityVectored,
						NeedsRotAccum = (data.RotMode == "Speed") and not data.VelocityVectored,
						HasDrag = data.ParticleData.Drag ~= 0,
						HasAccel = data.ParticleData.Acceleration.Magnitude > 0,
						HasDecal = visualPart:FindFirstChildOfClass("Decal") ~= nil,

						Graphs = {
							SizeX = data.SizeX,
							SizeY = data.SizeY,
							SizeZ = data.SizeZ,
							RotSpeedX = data.RotSpeedX,
							RotSpeedY = data.RotSpeedY,
							RotSpeedZ = data.RotSpeedZ,
							Speed = data.Speed,
							Brightness = data.Brightness,
							Transparency = data.Transparency,
							Color = data.Color,
						},
						Seeds = seeds,

						IsAnimate = true,
						AnimateLoop = animateLoop,
						AnimateItem = part,
						InitialWorldCF = initialWorldCF,
						InitialLocalCF = localCF,
					}

					local startSize = Vector3.new(
						GraphMod.QueryPointsWithTime(0, pData.Graphs.SizeX, pData.Seeds.SizeX),
						GraphMod.QueryPointsWithTime(0, pData.Graphs.SizeY, pData.Seeds.SizeY),
						GraphMod.QueryPointsWithTime(0, pData.Graphs.SizeZ, pData.Seeds.SizeZ)
					)
					local startTrans = GraphMod.QueryPointsWithTime(
						0,
						pData.Graphs.Transparency,
						pData.Seeds.Transparency
					)
					local startColor = GraphMod.QueryColorPointWithTime(0, pData.Graphs.Color)
					local startBright = GraphMod.QueryPointsWithTime(
						0,
						pData.Graphs.Brightness,
						pData.Seeds.Brightness
					)

					if pData.SpecialMesh then
						pData.SpecialMesh.Scale = startSize
					else
						pData.VisualPart.Size = startSize
					end

					if pData.Decal then
						pData.Decal.Transparency = startTrans
						pData.Decal.Color3 = Color3.fromRGB(
							startColor.R * 255 * startBright,
							startColor.G * 255 * startBright,
							startColor.B * 255 * startBright
						)
					else
						pData.VisualPart.Transparency = startTrans
						pData.VisualPart.Color = startColor
					end

					for _, desc in visualPart:GetDescendants() do
						if desc:IsA("ParticleEmitter") then
							desc.Enabled = false
						end
					end
					for _, child in visualPart:GetChildren() do
						if child:IsA("Attachment") then
							ParticlesMod.EnableEmitChildrenAndRepeatForAttachments(child)
						end
						ParticlesMod.EnableEmitSingle(child)
					end

					table.insert(self.ActiveEmits, pData)
					self.ActiveAnimates[part] = pData

					for _, child in visualPart:GetChildren() do
						if child:GetAttribute("Transformed") then
							self:EnableEmit(child, visualPart)
						end
					end
				end

				function Particle:EmitAttachmentAnimate(attachment, link)
					local data = self:GetData(attachment)
					if not data or not data.RenderTemplate then
						return
					end
					link = link or data.Link

					local Time = RangeMod.RandomValueFromRange(data.Lifetime)
					if Time <= 0 then
						Time = 0.001
					end
					local animateLoop = attachment:GetAttribute("AnimateLoop") or false

					local visualAttachment = data.RenderTemplate
					local initialWorldCF = visualAttachment.CFrame

					local localCF = attachment.CFrame
					local dirInfo = DirectionVectors[data.EmissionDirection]
						or DirectionVectors[Enum.NormalId.Top]
					local baseDirection = CFrame.new(
						Vector3.new(),
						localCF[dirInfo.vector] * dirInfo.multiplier
					).LookVector

					local RX = RangeMod.RandomValueFromRange(data.RotX)
					local RY = RangeMod.RandomValueFromRange(data.RotY)
					local RZ = RangeMod.RandomValueFromRange(data.RotZ)
					localCF = localCF * CFrame.Angles(math.rad(RX), math.rad(RY), math.rad(RZ))

					local randomX, randomY = 0, 0
					if
						data.ParticleData.SpreadAngle.X > 0
						or data.ParticleData.SpreadAngle.Y > 0
					then
						randomX = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.X
						randomY = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.Y
					end
					local spreadRotation = CFrame.Angles(math.rad(randomX), math.rad(randomY), 0)
					local cf = CFrame.lookAt(Vector3.new(), baseDirection)
					cf = cf * spreadRotation
					baseDirection = cf.LookVector

					local seeds = {
						Speed = GraphMod.GenerateSeed(data.Speed),
						RotSpeedX = GraphMod.GenerateSeed(data.RotSpeedX),
						RotSpeedY = GraphMod.GenerateSeed(data.RotSpeedY),
						RotSpeedZ = GraphMod.GenerateSeed(data.RotSpeedZ),
					}

					local invertMotion = data.InvertMotion
					local simLocalCFrames = nil
					if invertMotion then
						simLocalCFrames = self:PreSimulateAttachmentForward(
							data,
							seeds,
							localCF,
							baseDirection,
							spreadRotation,
							Time
						)
					end

					if invertMotion and simLocalCFrames then
						localCF = simLocalCFrames[data.TotalKeyFrames] or simLocalCFrames[0]
					end

					visualAttachment.CFrame = localCF

					local pData = {
						Type = "Attachment",
						VisualPart = visualAttachment,
						Link = link,
						LinkMode = data.LinkMode,
						StartTime = os.clock(),
						TotalKeyFrames = math.max(1, data.TotalKeyFrames),
						CurrentStep = 0,
						AccumulatedDT = 0,
						LifeTime = Time,
						PartLife = 0,
						LocalCF = localCF,
						BaseDirection = baseDirection,
						EmissionDirection = data.EmissionDirection,
						SpreadRotation = spreadRotation,
						Acceleration = data.ParticleData.Acceleration,
						Drag = data.ParticleData.Drag,
						VelocityVectored = data.VelocityVectored,
						InvertMotion = invertMotion,
						SimLocalCFrames = simLocalCFrames,
						RotMode = data.RotMode or "OverLife",
						AccRotX = 0,
						AccRotY = 0,
						AccRotZ = 0,
						NeedsFullIteration = data.VelocityVectored,
						NeedsRotAccum = (data.RotMode == "Speed") and not data.VelocityVectored,
						HasDrag = data.ParticleData.Drag ~= 0,
						HasAccel = data.ParticleData.Acceleration.Magnitude > 0,
						Graphs = {
							Speed = data.Speed,
							RotSpeedX = data.RotSpeedX,
							RotSpeedY = data.RotSpeedY,
							RotSpeedZ = data.RotSpeedZ,
						},
						Seeds = seeds,

						IsAnimate = true,
						AnimateLoop = animateLoop,
						AnimateItem = attachment,
						InitialWorldCF = initialWorldCF,
						InitialLocalCF = localCF,
					}

					table.insert(self.ActiveEmits, pData)
					self.ActiveAnimates[attachment] = pData

					for _, child in visualAttachment:GetChildren() do
						if child:GetAttribute("Transformed") then
							self:EnableEmit(child, visualAttachment.Parent)
						end
					end
				end

				function Particle:EmitBeamAnimate(beam, link)
					local data = self:GetData(beam)
					if not data or not data.RenderTemplate then
						return
					end

					local animateLoop = beam:GetAttribute("AnimateLoop") or false
					local visualBeam = data.RenderTemplate
					visualBeam.Enabled = true
					if data.FaceCamera ~= nil then
						visualBeam.FaceCamera = data.FaceCamera
					end

					local animatedProps = {}
					for name, sequence in pairs(data.BeamProps) do
						if sequence then
							if GraphMod.IsStatic(sequence) then
								visualBeam[name] =
									GraphMod.GetStaticValue(sequence, visualBeam[name])
							else
								animatedProps[name] =
									{ Sequence = sequence, Seed = GraphMod.GenerateSeed(sequence) }
							end
						end
					end

					local transStates, colorStates = GraphMod.CollectGraphStates(data.GraphBlender)

					local transMergedTimes = {}
					for idx = 1, #transStates - 1 do
						transMergedTimes[idx] = GraphMod.PrecomputeMergedTimes(
							transStates[idx].Graph,
							transStates[idx + 1].Graph
						)
					end
					local colorMergedTimes = {}
					for idx = 1, #colorStates - 1 do
						colorMergedTimes[idx] = GraphMod.PrecomputeMergedColorTimes(
							colorStates[idx].Graph,
							colorStates[idx + 1].Graph
						)
					end

					if #transStates > 0 then
						visualBeam.Transparency = transStates[1].Graph
					end
					if #colorStates > 0 then
						visualBeam.Color = colorStates[1].Graph
					end

					local safeLifeTime = RangeMod.RandomValueFromRange(data.Lifetime)
					if safeLifeTime <= 0 then
						safeLifeTime = 0.001
					end

					local pData = {
						Type = "Beam",
						VisualPart = visualBeam,
						Link = link,
						StartTime = os.clock(),
						TotalKeyFrames = math.max(1, data.TotalKeyFrames),
						CurrentStep = 0,
						LifeTime = safeLifeTime,
						PartLife = 0,
						AnimatedProps = animatedProps,
						TransStates = transStates,
						ColorStates = colorStates,
						TransMergedTimes = transMergedTimes,
						ColorMergedTimes = colorMergedTimes,

						IsAnimate = true,
						AnimateLoop = animateLoop,
						AnimateItem = beam,
					}

					table.insert(self.ActiveEmits, pData)
					self.ActiveAnimates[beam] = pData
				end
			end
		end

		factories["EmitVFX.EmitModel"] = function()
			local GraphMod = getModule("EmitVFX.Graph")
			local RangeMod = getModule("EmitVFX.Range")
			local ParticlesMod = getModule("EmitVFX.Particles")
			local Constants = getModule("EmitVFX.PartConstants")
			local DirectionVectors = Constants.DirectionVectors

			return function(Particle)
				function Particle:EmitModel(model, link)
					local data = self:GetData(model)
					if not data or not data.RenderTemplate then
						return
					end
					link = link or data.Link

					local Time = RangeMod.RandomValueFromRange(data.Lifetime)
					if Time <= 0 then
						Time = 0.001
					end

					local unrotatedCF = model:GetPivot()
					local dirInfo = DirectionVectors[data.EmissionDirection]
						or DirectionVectors[Enum.NormalId.Top]
					local rawWorldDirection = unrotatedCF[dirInfo.vector] * dirInfo.multiplier

					local initialCF = unrotatedCF

					local RX = RangeMod.RandomValueFromRange(data.RotX)
					local RY = RangeMod.RandomValueFromRange(data.RotY)
					local RZ = RangeMod.RandomValueFromRange(data.RotZ)
					initialCF = initialCF * CFrame.Angles(math.rad(RX), math.rad(RY), math.rad(RZ))

					local baseDirection
					if data.VelocityVectored then
						baseDirection = initialCF[dirInfo.vector] * dirInfo.multiplier
					else
						baseDirection = rawWorldDirection
					end

					local randomX, randomY = 0, 0
					if
						data.ParticleData.SpreadAngle.X > 0
						or data.ParticleData.SpreadAngle.Y > 0
					then
						randomX = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.X
						randomY = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.Y
					end
					local spreadRotation = CFrame.Angles(math.rad(randomX), math.rad(randomY), 0)

					local cf = CFrame.lookAt(Vector3.new(), baseDirection)
					cf = cf * spreadRotation
					baseDirection = cf.LookVector

					local seeds = {
						RotSpeedX = GraphMod.GenerateSeed(data.RotSpeedX),
						RotSpeedY = GraphMod.GenerateSeed(data.RotSpeedY),
						RotSpeedZ = GraphMod.GenerateSeed(data.RotSpeedZ),
						Speed = GraphMod.GenerateSeed(data.Speed),
						Scale = GraphMod.GenerateSeed(data.Scale),
					}

					local invertMotion = data.InvertMotion
					local simLocalCFrames = nil

					if invertMotion then
						simLocalCFrames = self:PreSimulateForward(
							data,
							seeds,
							initialCF,
							baseDirection,
							spreadRotation,
							link,
							Time
						)
					end

					local visualModel = data.RenderTemplate:Clone()
					local parentCF_now
					if link then
						local isA = link:IsA("Attachment")
						local lP = isA and link.WorldPosition or link.Position
						local lC = isA and link.WorldCFrame or link.CFrame
						parentCF_now = data.LinkMode == "Follow" and CFrame.new(lP) or lC
					else
						parentCF_now = CFrame.new()
					end
					local localCF

					if invertMotion and simLocalCFrames then
						local endLocalCF = simLocalCFrames[data.TotalKeyFrames]
							or simLocalCFrames[0]
						localCF = endLocalCF
						visualModel:PivotTo(parentCF_now * localCF)
					else
						localCF = link and parentCF_now:ToObjectSpace(initialCF) or initialCF
						visualModel:PivotTo(parentCF_now * localCF)
					end

					local peSnapshots = {}
					for _, desc in visualModel:GetDescendants() do
						if desc:IsA("ParticleEmitter") then
							peSnapshots[desc] = desc.Size
						end
					end

					local pData = {
						Type = "Model",
						VisualPart = visualModel,
						Link = link,
						LinkMode = data.LinkMode,

						StartTime = os.clock(),
						TotalKeyFrames = math.max(1, data.TotalKeyFrames),
						CurrentStep = 0,
						AccumulatedDT = 0,
						LifeTime = Time,
						PartLife = data.PartLife,
						CurrentPosition = visualModel:GetPivot().Position,
						LocalCF = localCF,

						BaseDirection = baseDirection,
						EmissionDirection = data.EmissionDirection,
						SpreadRotation = spreadRotation,
						Acceleration = data.ParticleData.Acceleration,
						Drag = data.ParticleData.Drag,
						VelocityVectored = data.VelocityVectored,

						InvertMotion = invertMotion,
						SimLocalCFrames = simLocalCFrames,

						RotMode = data.RotMode or "OverLife",
						AccRotX = 0,
						AccRotY = 0,
						AccRotZ = 0,

						NeedsFullIteration = data.VelocityVectored,
						NeedsRotAccum = (data.RotMode == "Speed") and not data.VelocityVectored,
						HasDrag = data.ParticleData.Drag ~= 0,
						HasAccel = data.ParticleData.Acceleration.Magnitude > 0,

						PESnapshots = peSnapshots,

						Graphs = {
							RotSpeedX = data.RotSpeedX,
							RotSpeedY = data.RotSpeedY,
							RotSpeedZ = data.RotSpeedZ,
							Speed = data.Speed,
							Scale = data.Scale,
						},
						Seeds = seeds,
					}

					local startScale =
						GraphMod.QueryPointsWithTime(0, pData.Graphs.Scale, pData.Seeds.Scale)
					visualModel:ScaleTo(startScale)
					for pe, origSize in pairs(peSnapshots) do
						if pe.Parent then
							pe.Size = GraphMod.ScaleSequence(origSize, startScale)
						end
					end

					visualModel.Parent = data.EmitParent or self:GetFolder()

					for _, desc in visualModel:GetDescendants() do
						if desc:IsA("ParticleEmitter") then
							desc.Enabled = false
						end
					end
					for _, child in visualModel:GetChildren() do
						if child:IsA("Attachment") then
							ParticlesMod.EnableEmitChildrenAndRepeatForAttachments(child)
						end
						ParticlesMod.EnableEmitSingle(child)
					end

					table.insert(self.ActiveEmits, pData)

					for _, child in visualModel:GetChildren() do
						if child:GetAttribute("Transformed") then
							self:EnableEmit(child, visualModel.PrimaryPart or visualModel)
						end
					end
				end

				function Particle:EmitModelAnimate(model, link)
					local data = self:GetData(model)
					if not data or not data.RenderTemplate then
						return
					end
					link = link or data.Link

					local Time = RangeMod.RandomValueFromRange(data.Lifetime)
					if Time <= 0 then
						Time = 0.001
					end
					local animateLoop = model:GetAttribute("AnimateLoop") or false

					local visualModel = data.RenderTemplate
					local initialWorldCF = visualModel:GetPivot()

					local unrotatedCF = model:GetPivot()
					local dirInfo = DirectionVectors[data.EmissionDirection]
						or DirectionVectors[Enum.NormalId.Top]
					local rawWorldDirection = unrotatedCF[dirInfo.vector] * dirInfo.multiplier

					local initialCF = unrotatedCF

					local RX = RangeMod.RandomValueFromRange(data.RotX)
					local RY = RangeMod.RandomValueFromRange(data.RotY)
					local RZ = RangeMod.RandomValueFromRange(data.RotZ)
					initialCF = initialCF * CFrame.Angles(math.rad(RX), math.rad(RY), math.rad(RZ))

					local baseDirection
					if data.VelocityVectored then
						baseDirection = initialCF[dirInfo.vector] * dirInfo.multiplier
					else
						baseDirection = rawWorldDirection
					end

					local randomX, randomY = 0, 0
					if
						data.ParticleData.SpreadAngle.X > 0
						or data.ParticleData.SpreadAngle.Y > 0
					then
						randomX = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.X
						randomY = (math.random() * 2 - 1) * data.ParticleData.SpreadAngle.Y
					end
					local spreadRotation = CFrame.Angles(math.rad(randomX), math.rad(randomY), 0)
					local cf = CFrame.lookAt(Vector3.new(), baseDirection)
					cf = cf * spreadRotation
					baseDirection = cf.LookVector

					local seeds = {
						RotSpeedX = GraphMod.GenerateSeed(data.RotSpeedX),
						RotSpeedY = GraphMod.GenerateSeed(data.RotSpeedY),
						RotSpeedZ = GraphMod.GenerateSeed(data.RotSpeedZ),
						Speed = GraphMod.GenerateSeed(data.Speed),
						Scale = GraphMod.GenerateSeed(data.Scale),
					}

					local invertMotion = data.InvertMotion
					local simLocalCFrames = nil
					if invertMotion then
						simLocalCFrames = self:PreSimulateForward(
							data,
							seeds,
							initialCF,
							baseDirection,
							spreadRotation,
							link,
							Time
						)
					end

					local parentCF_now
					if link then
						local isA = link:IsA("Attachment")
						local lP = isA and link.WorldPosition or link.Position
						local lC = isA and link.WorldCFrame or link.CFrame
						parentCF_now = data.LinkMode == "Follow" and CFrame.new(lP) or lC
					else
						parentCF_now = CFrame.new()
					end
					local localCF
					if invertMotion and simLocalCFrames then
						local endLocalCF = simLocalCFrames[data.TotalKeyFrames]
							or simLocalCFrames[0]
						localCF = endLocalCF
					else
						localCF = link and parentCF_now:ToObjectSpace(initialCF) or initialCF
					end
					visualModel:PivotTo(parentCF_now * localCF)

					local peSnapshots = {}
					for _, desc in visualModel:GetDescendants() do
						if desc:IsA("ParticleEmitter") then
							peSnapshots[desc] = desc.Size
						end
					end

					local pData = {
						Type = "Model",
						VisualPart = visualModel,
						Link = link,
						LinkMode = data.LinkMode,

						StartTime = os.clock(),
						TotalKeyFrames = math.max(1, data.TotalKeyFrames),
						CurrentStep = 0,
						AccumulatedDT = 0,
						LifeTime = Time,
						PartLife = 0,
						CurrentPosition = visualModel:GetPivot().Position,
						LocalCF = localCF,

						BaseDirection = baseDirection,
						EmissionDirection = data.EmissionDirection,
						SpreadRotation = spreadRotation,
						Acceleration = data.ParticleData.Acceleration,
						Drag = data.ParticleData.Drag,
						VelocityVectored = data.VelocityVectored,

						InvertMotion = invertMotion,
						SimLocalCFrames = simLocalCFrames,

						RotMode = data.RotMode or "OverLife",
						AccRotX = 0,
						AccRotY = 0,
						AccRotZ = 0,

						NeedsFullIteration = data.VelocityVectored,
						NeedsRotAccum = (data.RotMode == "Speed") and not data.VelocityVectored,
						HasDrag = data.ParticleData.Drag ~= 0,
						HasAccel = data.ParticleData.Acceleration.Magnitude > 0,

						PESnapshots = peSnapshots,

						Graphs = {
							RotSpeedX = data.RotSpeedX,
							RotSpeedY = data.RotSpeedY,
							RotSpeedZ = data.RotSpeedZ,
							Speed = data.Speed,
							Scale = data.Scale,
						},
						Seeds = seeds,

						IsAnimate = true,
						AnimateLoop = animateLoop,
						AnimateItem = model,
						InitialWorldCF = initialWorldCF,
						InitialLocalCF = localCF,
					}

					local startScale =
						GraphMod.QueryPointsWithTime(0, pData.Graphs.Scale, pData.Seeds.Scale)
					visualModel:ScaleTo(startScale)
					for pe, origSize in pairs(peSnapshots) do
						if pe.Parent then
							pe.Size = GraphMod.ScaleSequence(origSize, startScale)
						end
					end

					for _, desc in visualModel:GetDescendants() do
						if desc:IsA("ParticleEmitter") then
							desc.Enabled = false
						end
					end
					for _, child in visualModel:GetChildren() do
						if child:IsA("Attachment") then
							ParticlesMod.EnableEmitChildrenAndRepeatForAttachments(child)
						end
						ParticlesMod.EnableEmitSingle(child)
					end

					table.insert(self.ActiveEmits, pData)
					self.ActiveAnimates[model] = pData

					for _, child in visualModel:GetChildren() do
						if child:GetAttribute("Transformed") then
							self:EnableEmit(child, visualModel.PrimaryPart or visualModel)
						end
					end
				end
			end
		end

		factories["EmitVFX.Flipbook"] = function()
			local ContentProvider = game:GetService("ContentProvider")
			local RangeMod = getModule("EmitVFX.Range")
			local MeshFlipbook = {}

			function MeshFlipbook.GetSortedTextures(flipbookFolder: Folder): { string }
				local decalObjects = {}
				for _, child in pairs(flipbookFolder:GetChildren()) do
					if child.Texture then
						table.insert(decalObjects, child)
					end
				end
				if #decalObjects == 0 then
					return {}
				end

				table.sort(decalObjects, function(a, b)
					return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
				end)

				local textures = {}
				for _, obj in ipairs(decalObjects) do
					table.insert(textures, obj.Texture)
				end

				if #textures > 0 then
					task.spawn(function()
						ContentProvider:PreloadAsync(textures)
					end)
				end

				return textures
			end

			function MeshFlipbook.GetSortedBeamTextures(flipbookFolder: Folder): { string }
				local decalObjects = {}
				for _, child in pairs(flipbookFolder:GetChildren()) do
					if child:IsA("Decal") then
						table.insert(decalObjects, child)
					end
				end
				if #decalObjects == 0 then
					return {}
				end

				table.sort(decalObjects, function(a, b)
					return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
				end)

				local textures = {}
				for _, obj in ipairs(decalObjects) do
					table.insert(textures, obj.Texture)
				end

				if #textures > 0 then
					task.spawn(function()
						ContentProvider:PreloadAsync(textures)
					end)
				end

				return textures
			end

			local function _loop(particle, decals, target, lifetime)
				if #decals == 0 then
					return
				end

				local framerate = RangeMod.RandomValueFromRange(particle.FlipbookFramerate)
				local frameDelay = 1 / framerate
				local currentFrame = particle.FlipbookStartRandom and math.random(1, #decals) or 1
				local startTime = os.clock()

				task.spawn(function()
					while os.clock() - startTime < lifetime do
						target.Texture = decals[currentFrame]
						currentFrame = currentFrame + 1
						if currentFrame > #decals then
							currentFrame = 1
						end
						task.wait(frameDelay)
					end
				end)
			end

			local function _oneShot(particle, decals, target, lifetime)
				if #decals == 0 then
					return
				end

				local frameDelay = lifetime / #decals
				local currentFrame = particle.FlipbookStartRandom and math.random(1, #decals) or 1

				task.spawn(function()
					for i = 1, #decals do
						if currentFrame > #decals then
							break
						end
						target.Texture = decals[currentFrame]
						currentFrame = currentFrame + 1
						task.wait(frameDelay)
					end
				end)
			end

			function MeshFlipbook.Flip(particle, decals: { string }, decal, lifetime)
				if not particle or not particle.FlipbookMode then
					return
				end

				if particle.FlipbookMode == Enum.ParticleFlipbookMode.Loop then
					_loop(particle, decals, decal, lifetime)
				elseif particle.FlipbookMode == Enum.ParticleFlipbookMode.OneShot then
					_oneShot(particle, decals, decal, lifetime)
				end
			end

			function MeshFlipbook.FlipBeam(flipbookParticle, decals: { string }, beam, lifetime)
				if not flipbookParticle or not decals or not flipbookParticle.FlipbookMode then
					return
				end

				local mode = flipbookParticle.FlipbookMode
				if mode == Enum.ParticleFlipbookMode.Loop then
					_loop(flipbookParticle, decals, beam, lifetime)
				elseif mode == Enum.ParticleFlipbookMode.OneShot then
					_oneShot(flipbookParticle, decals, beam, lifetime)
				end
			end

			MeshFlipbook.Loop = _loop
			MeshFlipbook.OneShot = _oneShot
			MeshFlipbook.BeamLoop = _loop
			MeshFlipbook.BeamOneShot = _oneShot

			return MeshFlipbook
		end

		factories["EmitVFX.GetData"] = function()
			local MeshFlipMod = getModule("EmitVFX.Flipbook")
			local TypeRegistry = getModule("EmitVFX.TypeRegistry")

			return function(Particle)
				function Particle:GetData(item)
					local data = {}

					local config = TypeRegistry.getConfig(item)
					if not config then
						return nil
					end

					local ep = item:FindFirstChild("EmitParent")
					data.EmitParent = ep and ep:IsA("ObjectValue") and ep.Value or nil

					local lk = item:FindFirstChild("Link")
					data.Link = lk and lk:IsA("ObjectValue") and lk.Value or nil
					data.LinkMode = item:GetAttribute("LinkMode") or "Weld"

					data.RenderTemplate = item:FindFirstChild("RenderTemplate")

					local tkf = config:GetAttribute("TotalKeyFrames") or 0
					data.TotalKeyFrames = tkf > 0 and tkf or 100

					data.CheckEnabled = function()
						return config.Parent ~= nil and config:GetAttribute("Enabled") == true
					end

					if item:IsA("Model") then
						data.PartLife = config:GetAttribute("PartLife") or 0
						data.VelocityVectored = config:GetAttribute("VelocityVectored") or false
						data.InvertMotion = config:GetAttribute("InvertMotion") or false
						data.RotMode = config:GetAttribute("RotMode") or "OverLife"
						data.Lifetime = config:GetAttribute("Lifetime") or NumberRange.new(1)
						data.Rate = config:GetAttribute("Rate") or 10

						local emitDirName = config:GetAttribute("EmissionDirection")
						data.EmissionDirection = emitDirName and Enum.NormalId[emitDirName]
							or Enum.NormalId.Top

						data.ParticleData = {
							SpreadAngle = config:GetAttribute("SpreadAngle") or Vector2.new(0, 0),
							Acceleration = config:GetAttribute("Acceleration")
								or Vector3.new(0, 0, 0),
							Drag = config:GetAttribute("Drag") or 0,
						}

						data.Speed = config:GetAttribute("Speed")
						data.Scale = config:GetAttribute("Scale")

						data.RotX = config:GetAttribute("RotX")
						data.RotY = config:GetAttribute("RotY")
						data.RotZ = config:GetAttribute("RotZ")

						data.RotSpeedX = config:GetAttribute("RotSpeedX")
						data.RotSpeedY = config:GetAttribute("RotSpeedY")
						data.RotSpeedZ = config:GetAttribute("RotSpeedZ")

						return data
					end

					if item:IsA("PointLight") then
						data.PartLife = 0
						data.Lifetime = config:GetAttribute("Lifetime") or NumberRange.new(1)
						data.Rate = config:GetAttribute("Rate") or 10
						data.PLRange = config:GetAttribute("PLRange")
						data.PLBrightness = config:GetAttribute("PLBrightness")
						data.PLColor = config:GetAttribute("PLColor")
						return data
					end

					if item:IsA("Attachment") then
						data.PartLife = config:GetAttribute("PartLife") or 0
						data.VelocityVectored = config:GetAttribute("VelocityVectored") or false
						data.InvertMotion = config:GetAttribute("InvertMotion") or false
						data.RotMode = config:GetAttribute("RotMode") or "OverLife"
						data.Lifetime = config:GetAttribute("Lifetime") or NumberRange.new(1)
						data.Rate = config:GetAttribute("Rate") or 10

						local emitDirName = config:GetAttribute("EmissionDirection")
						data.EmissionDirection = emitDirName and Enum.NormalId[emitDirName]
							or Enum.NormalId.Top

						data.ParticleData = {
							SpreadAngle = config:GetAttribute("SpreadAngle") or Vector2.new(0, 0),
							Acceleration = config:GetAttribute("Acceleration")
								or Vector3.new(0, 0, 0),
							Drag = config:GetAttribute("Drag") or 0,
						}

						data.Speed = config:GetAttribute("Speed")

						data.RotX = config:GetAttribute("RotX")
						data.RotY = config:GetAttribute("RotY")
						data.RotZ = config:GetAttribute("RotZ")

						data.RotSpeedX = config:GetAttribute("RotSpeedX")
						data.RotSpeedY = config:GetAttribute("RotSpeedY")
						data.RotSpeedZ = config:GetAttribute("RotSpeedZ")

						return data
					end

					data.PartLife = config:GetAttribute("PartLife") or 0

					if item:IsA("Beam") then
						data.GraphBlender = item:FindFirstChild("GraphBlender")
						data.Lifetime = config:GetAttribute("BeamLifetime") or NumberRange.new(1)
						data.Rate = config:GetAttribute("Rate") or 10

						data.BeamFlipbooks = item:FindFirstChild("BeamFlipbooks")
						data.FlipbookParticle = {
							FlipbookMode = config:GetAttribute("BeamFlipbookMode")
									and Enum.ParticleFlipbookMode[config:GetAttribute(
										"BeamFlipbookMode"
									)]
								or nil,
							FlipbookFramerate = config:GetAttribute("BeamFlipbookFramerate") or nil,
							FlipbookStartRandom = config:GetAttribute("BeamFlipbookStartRandom")
								or false,
						}

						if data.BeamFlipbooks then
							data.CachedBeamTextures =
								MeshFlipMod.GetSortedBeamTextures(data.BeamFlipbooks)
						end

						data.FaceCamera = config:GetAttribute("FaceCamera")
						data.BeamProps = {
							Brightness = config:GetAttribute("BeamBrightness"),
							CurveSize0 = config:GetAttribute("CurveSize0"),
							CurveSize1 = config:GetAttribute("CurveSize1"),
							Width0 = config:GetAttribute("Width0"),
							Width1 = config:GetAttribute("Width1"),
							LightEmission = config:GetAttribute("LightEmission"),
							Segments = config:GetAttribute("Segments"),
							TextureLength = config:GetAttribute("TextureLength"),
							TextureSpeed = config:GetAttribute("TextureSpeed"),
						}
						return data
					end

					data.MeshFlipbooks = item:FindFirstChild("MeshFlipbooks")
					if data.MeshFlipbooks then
						data.CachedMeshTextures = MeshFlipMod.GetSortedTextures(data.MeshFlipbooks)
					end

					data.VelocityVectored = config:GetAttribute("VelocityVectored") or false
					data.InvertMotion = config:GetAttribute("InvertMotion") or false
					data.RotMode = config:GetAttribute("RotMode") or "OverLife"
					data.Lifetime = config:GetAttribute("Lifetime") or NumberRange.new(1)
					data.Rate = config:GetAttribute("Rate") or 10

					local shapeName = config:GetAttribute("Shape")
					local shapeInOutName = config:GetAttribute("ShapeInOut")
					local shapeStyleName = config:GetAttribute("ShapeStyle")
					local emitDirName = config:GetAttribute("EmissionDirection")

					data.Shape = shapeName and Enum.ParticleEmitterShape[shapeName]
						or Enum.ParticleEmitterShape.Box
					data.ShapeInOut = shapeInOutName
							and Enum.ParticleEmitterShapeInOut[shapeInOutName]
						or Enum.ParticleEmitterShapeInOut.Outward
					data.ShapeStyle = shapeStyleName
							and Enum.ParticleEmitterShapeStyle[shapeStyleName]
						or Enum.ParticleEmitterShapeStyle.Volume
					data.EmissionDirection = emitDirName and Enum.NormalId[emitDirName]
						or Enum.NormalId.Top

					data.ParticleData = {
						Shape = data.Shape,
						ShapeInOut = data.ShapeInOut,
						ShapeStyle = data.ShapeStyle,
						ShapePartial = config:GetAttribute("ShapePartial") or 0,
						EmissionDirection = data.EmissionDirection,
						SpreadAngle = config:GetAttribute("SpreadAngle") or Vector2.new(0, 0),
						Acceleration = config:GetAttribute("Acceleration") or Vector3.new(0, 0, 0),
						Drag = config:GetAttribute("Drag") or 0,
						FlipbookMode = config:GetAttribute("FlipbookMode")
								and Enum.ParticleFlipbookMode[config:GetAttribute("FlipbookMode")]
							or nil,
						FlipbookFramerate = config:GetAttribute("FlipbookFramerate") or nil,
						FlipbookStartRandom = config:GetAttribute("FlipbookStartRandom") or false,
					}

					data.Transparency = config:GetAttribute("Transparency")
					data.Color = config:GetAttribute("Color")
					data.Speed = config:GetAttribute("Speed")
					data.Brightness = config:GetAttribute("Brightness")

					data.SizeX = config:GetAttribute("SizeX")
					data.SizeY = config:GetAttribute("SizeY")
					data.SizeZ = config:GetAttribute("SizeZ")

					data.RotX = config:GetAttribute("RotX")
					data.RotY = config:GetAttribute("RotY")
					data.RotZ = config:GetAttribute("RotZ")

					data.RotSpeedX = config:GetAttribute("RotSpeedX")
					data.RotSpeedY = config:GetAttribute("RotSpeedY")
					data.RotSpeedZ = config:GetAttribute("RotSpeedZ")

					return data
				end
			end
		end

		factories["EmitVFX.Graph"] = function()
			local function clamp(x, a, b)
				if x < a then
					return a
				end
				if x > b then
					return b
				end
				return x
			end
			local function lerp(a, b, t)
				return a + (b - a) * t
			end

			local Graph = {}

			function Graph.GenerateSeed(graph: NumberSequence)
				local seed = {}
				local kp = graph.Keypoints
				local intensity = math.random()
				local isPositive = math.random() >= 0.5
				for i = 1, #kp do
					if kp[i].Envelope > 0 then
						if isPositive then
							seed[i] = intensity * kp[i].Envelope
						else
							seed[i] = -intensity * kp[i].Envelope
						end
					end
				end
				return seed
			end

			function Graph.GenerateSeeds(graph: NumberSequence, NoOfSeeds: number)
				local seeds = {}
				for i = 1, NoOfSeeds do
					seeds[i] = Graph.GenerateSeed(graph)
				end
				return seeds
			end

			function Graph.QueryPointsWithTime(t: number, graph: NumberSequence, seed: { number })
				t = math.clamp(t, 0, 1)
				local keypoints = graph.Keypoints
				local n = #keypoints

				if n == 1 then
					return keypoints[1].Value + (seed[1] or 0)
				end

				local lo, hi = 1, n
				while lo < hi - 1 do
					local mid = (lo + hi) // 2
					if keypoints[mid].Time <= t then
						lo = mid
					else
						hi = mid
					end
				end
				local k1 = keypoints[lo]
				local k2 = keypoints[lo + 1]
				local span = k2.Time - k1.Time
				local point = span > 0 and (t - k1.Time) / span or 0
				local k1value = k1.Value + (seed[lo] or 0)
				local k2value = k2.Value + (seed[lo + 1] or 0)
				return k1value + ((k2value - k1value) * point)
			end

			function Graph.QueryColorPointWithTime(t: number, graph: ColorSequence)
				local kp = graph.Keypoints
				local n = #kp
				if n == 0 then
					return Color3.new(1, 1, 1)
				end
				if n == 1 then
					return kp[1].Value
				end
				if t <= kp[1].Time then
					return kp[1].Value
				end

				local lo, hi = 1, n
				while lo < hi - 1 do
					local mid = (lo + hi) // 2
					if kp[mid].Time <= t then
						lo = mid
					else
						hi = mid
					end
				end
				local k1 = kp[lo]
				local k2 = kp[lo + 1]
				local span = k2.Time - k1.Time
				local point = span > 0 and (t - k1.Time) / span or 0
				return k1.Value:Lerp(k2.Value, point)
			end

			function Graph.IsStatic(sequence: NumberSequence): boolean
				if not sequence then
					return true
				end
				local kps = sequence.Keypoints
				if #kps <= 1 then
					return true
				end
				local val = kps[1].Value
				for i = 2, #kps do
					if kps[i].Value ~= val or kps[i].Envelope ~= 0 then
						return false
					end
				end
				return true
			end

			function Graph.GetStaticValue(sequence: NumberSequence, defaultValue: number): number
				if not sequence or #sequence.Keypoints == 0 then
					return defaultValue
				end
				return sequence.Keypoints[1].Value
			end

			local function _mergeSequenceTimes(seqA, seqB)
				local times = {}
				local seen = {}
				for _, seq in ipairs({ seqA, seqB }) do
					for _, kp in ipairs(seq.Keypoints) do
						if not seen[kp.Time] then
							seen[kp.Time] = true
							table.insert(times, kp.Time)
						end
					end
				end
				table.sort(times)
				return times
			end

			function Graph.BlendGraphWithTime(
				GraphA: NumberSequence,
				GraphB: NumberSequence,
				SpeedGraph: NumberSequence,
				alpha: number
			)
				alpha = clamp(alpha or 1, 0, 1)
				local times = _mergeSequenceTimes(GraphA, GraphB)
				local blendFactor = Graph.QueryPointsWithTime(alpha, SpeedGraph, {}) or 1

				local newKps = {}
				for _, t in ipairs(times) do
					local valA = Graph.QueryPointsWithTime(t, GraphA, {})
						or GraphA.Keypoints[#GraphA.Keypoints].Value
					local valB = Graph.QueryPointsWithTime(t, GraphB, {})
						or GraphB.Keypoints[#GraphB.Keypoints].Value
					table.insert(
						newKps,
						NumberSequenceKeypoint.new(t, lerp(valA, valB, blendFactor))
					)
				end
				return NumberSequence.new(newKps)
			end

			function Graph.BlendColorGraphWithTime(
				GraphA: ColorSequence,
				GraphB: ColorSequence,
				SpeedGraph: NumberSequence,
				alpha: number
			)
				alpha = clamp(alpha or 1, 0, 1)
				local times = _mergeSequenceTimes(GraphA, GraphB)
				local blendFactor = Graph.QueryPointsWithTime(alpha, SpeedGraph, {}) or 1

				local newKps = {}
				for _, t in ipairs(times) do
					local colorA = Graph.QueryColorPointWithTime(t, GraphA)
					local colorB = Graph.QueryColorPointWithTime(t, GraphB)
					table.insert(
						newKps,
						ColorSequenceKeypoint.new(t, colorA:Lerp(colorB, blendFactor))
					)
				end
				return ColorSequence.new(newKps)
			end

			function Graph.LerpGraph(
				GraphA: NumberSequence,
				GraphB: NumberSequence,
				alpha: number
			): NumberSequence
				alpha = clamp(alpha or 0, 0, 1)
				local times = _mergeSequenceTimes(GraphA, GraphB)
				local newKps = {}
				for _, t in ipairs(times) do
					local valA = Graph.QueryPointsWithTime(t, GraphA, {})
					local valB = Graph.QueryPointsWithTime(t, GraphB, {})
					table.insert(newKps, NumberSequenceKeypoint.new(t, lerp(valA, valB, alpha)))
				end
				return NumberSequence.new(newKps)
			end

			function Graph.LerpColorGraph(
				GraphA: ColorSequence,
				GraphB: ColorSequence,
				alpha: number
			): ColorSequence
				alpha = clamp(alpha or 0, 0, 1)
				local times = _mergeSequenceTimes(GraphA, GraphB)
				local newKps = {}
				for _, t in ipairs(times) do
					local colorA = Graph.QueryColorPointWithTime(t, GraphA)
					local colorB = Graph.QueryColorPointWithTime(t, GraphB)
					table.insert(newKps, ColorSequenceKeypoint.new(t, colorA:Lerp(colorB, alpha)))
				end
				return ColorSequence.new(newKps)
			end

			function Graph.PrecomputeMergedTimes(
				GraphA: NumberSequence,
				GraphB: NumberSequence
			): { number }
				return _mergeSequenceTimes(GraphA, GraphB)
			end

			function Graph.PrecomputeMergedColorTimes(
				GraphA: ColorSequence,
				GraphB: ColorSequence
			): { number }
				return _mergeSequenceTimes(GraphA, GraphB)
			end

			function Graph.LerpGraphFast(
				GraphA: NumberSequence,
				GraphB: NumberSequence,
				alpha: number,
				mergedTimes: { number }
			): NumberSequence
				alpha = clamp(alpha or 0, 0, 1)
				local newKps = {}
				for _, t in ipairs(mergedTimes) do
					local valA = Graph.QueryPointsWithTime(t, GraphA, {})
					local valB = Graph.QueryPointsWithTime(t, GraphB, {})
					table.insert(newKps, NumberSequenceKeypoint.new(t, lerp(valA, valB, alpha)))
				end
				return NumberSequence.new(newKps)
			end

			function Graph.LerpColorGraphFast(
				GraphA: ColorSequence,
				GraphB: ColorSequence,
				alpha: number,
				mergedTimes: { number }
			): ColorSequence
				alpha = clamp(alpha or 0, 0, 1)
				local newKps = {}
				for _, t in ipairs(mergedTimes) do
					local colorA = Graph.QueryColorPointWithTime(t, GraphA)
					local colorB = Graph.QueryColorPointWithTime(t, GraphB)
					table.insert(newKps, ColorSequenceKeypoint.new(t, colorA:Lerp(colorB, alpha)))
				end
				return ColorSequence.new(newKps)
			end

			function Graph.CollectGraphStates(graphBlender)
				local transStates, colorStates = {}, {}
				if not graphBlender then
					return transStates, colorStates
				end

				for _, child in pairs(graphBlender:GetChildren()) do
					if not child:IsA("Configuration") then
						continue
					end
					local time = child:GetAttribute("Time")
					if time == nil then
						local num = tonumber(string.match(child.Name, "%d+"))
						time = num and (num - 1) or 0
					end
					local trans = child:GetAttribute("Transparency")
					if trans and typeof(trans) == "NumberSequence" then
						table.insert(transStates, { Time = time, Graph = trans })
					end
					local color = child:GetAttribute("Color")
					if color and typeof(color) == "ColorSequence" then
						table.insert(colorStates, { Time = time, Graph = color })
					end
				end

				table.sort(transStates, function(a, b)
					return a.Time < b.Time
				end)
				table.sort(colorStates, function(a, b)
					return a.Time < b.Time
				end)

				for _, states in ipairs({ transStates, colorStates }) do
					if #states > 1 and states[#states].Time > 1 then
						local maxTime = states[#states].Time
						if maxTime > 0 then
							for _, s in ipairs(states) do
								s.Time = s.Time / maxTime
							end
						end
					end
				end

				return transStates, colorStates
			end

			function Graph.ScaleSequence(seq, factor)
				if not seq or typeof(seq) ~= "NumberSequence" then
					return seq
				end
				local kps = seq.Keypoints
				local new = {}
				local absFactor = math.abs(factor)
				for _, kp in ipairs(kps) do
					table.insert(
						new,
						NumberSequenceKeypoint.new(
							kp.Time,
							kp.Value * factor,
							kp.Envelope * absFactor
						)
					)
				end
				return NumberSequence.new(new)
			end

			return Graph
		end

		factories["EmitVFX"] = function()
			local RunService = game:GetService("RunService")
			local GraphMod = getModule("EmitVFX.Graph")
			local RangeMod = getModule("EmitVFX.Range")
			local ParticlesMod = getModule("EmitVFX.Particles")
			local TypeRegistry = getModule("EmitVFX.TypeRegistry")

			local Particle = {}
			Particle.Beam = {}

			Particle.ActiveEmits = {}
			Particle.ActiveLoops = {}
			Particle.ActiveAnimates = {}
			Particle.Connection = nil
			Particle._CachedFolder = nil

			getModule("EmitVFX.GetData")(Particle)
			getModule("EmitVFX.Transform")(Particle)
			getModule("EmitVFX.Update")(Particle)
			getModule("EmitVFX.Emit")(Particle)
			getModule("EmitVFX.EmitAnimate")(Particle)
			getModule("EmitVFX.EmitModel")(Particle)
			getModule("EmitVFX.UpdateModel")(Particle)

			function Particle:Activate()
				if self.Connection then
					return
				end

				self.Connection = RunService.Heartbeat:Connect(function(dt)
					local emits = self.ActiveEmits
					if #emits == 0 then
						self.Connection:Disconnect()
						self.Connection = nil
						return
					end
					local currentTime = os.clock()
					local i = 1

					while i <= #emits do
						local pData = emits[i]
						local isDead = false

						if pData.Type == "Part" then
							isDead = self:UpdatePart(pData, dt, currentTime)
						elseif pData.Type == "Beam" then
							isDead = self:UpdateBeam(pData, dt, currentTime)
						elseif pData.Type == "PointLight" then
							isDead = self:UpdatePointLight(pData, dt, currentTime)
						elseif pData.Type == "Attachment" then
							isDead = self:UpdateAttachment(pData, dt, currentTime)
						elseif pData.Type == "Model" then
							isDead = self:UpdateModel(pData, dt, currentTime)
						end

						if isDead then
							if pData.IsAnimate then
								if
									pData.AnimateItem
									and pData.AnimateItem.Parent
									and pData.AnimateItem:GetAttribute("AnimateLoop")
								then
									pData.StartTime = currentTime
									pData.CurrentStep = 0
									if pData.AccumulatedDT then
										pData.AccumulatedDT = 0
									end
									if pData.InitialLocalCF then
										pData.LocalCF = pData.InitialLocalCF
									end
									if pData.AccRotX then
										pData.AccRotX = 0
										pData.AccRotY = 0
										pData.AccRotZ = 0
									end
									if
										pData.InitialWorldCF
										and pData.VisualPart
										and pData.VisualPart.Parent
									then
										if pData.Type == "Model" then
											pData.VisualPart:PivotTo(pData.InitialWorldCF)
										else
											pData.VisualPart.CFrame = pData.InitialWorldCF
										end
									end
									i += 1
								else
									if
										pData.InitialWorldCF
										and pData.VisualPart
										and pData.VisualPart.Parent
									then
										if pData.Type == "Model" then
											pData.VisualPart:PivotTo(pData.InitialWorldCF)
										else
											pData.VisualPart.CFrame = pData.InitialWorldCF
										end
									end
									if pData.Type == "Beam" then
										pData.VisualPart.Enabled = false
									end
									self.ActiveAnimates[pData.AnimateItem] = nil
									local n = #emits
									if i < n then
										emits[i] = emits[n]
									end
									emits[n] = nil
								end
							else
								local visualPart = pData.VisualPart
								if pData.PartLife and pData.PartLife > 0 then
									task.delay(pData.PartLife, function()
										if visualPart then
											visualPart:Destroy()
										end
									end)
								else
									if visualPart then
										visualPart:Destroy()
									end
								end
								local n = #emits
								if i < n then
									emits[i] = emits[n]
								end
								emits[n] = nil
							end
						else
							i += 1
						end
					end
				end)
			end

			function Particle:Deactivate()
				if self.Connection then
					self.Connection:Disconnect()
					self.Connection = nil
				end

				for i = #self.ActiveEmits, 1, -1 do
					local pData = self.ActiveEmits[i]
					if pData.VisualPart and not pData.IsAnimate then
						pcall(function()
							pData.VisualPart:Destroy()
						end)
					end
					self.ActiveEmits[i] = nil
				end

				for _, aPData in pairs(self.ActiveAnimates) do
					if aPData.InitialWorldCF and aPData.VisualPart then
						if aPData.Type == "Model" then
							pcall(function()
								aPData.VisualPart:PivotTo(aPData.InitialWorldCF)
							end)
						else
							pcall(function()
								aPData.VisualPart.CFrame = aPData.InitialWorldCF
							end)
						end
					end
					if aPData.Type == "Beam" and aPData.VisualPart then
						pcall(function()
							aPData.VisualPart.Enabled = false
						end)
					end
				end
				table.clear(self.ActiveAnimates)

				for item, thread in pairs(self.ActiveLoops) do
					pcall(function()
						task.cancel(thread)
					end)
					self.ActiveLoops[item] = nil
				end
				self._CachedFolder = nil
			end

			function Particle:GetFolder()
				if self._CachedFolder and self._CachedFolder.Parent then
					return self._CachedFolder
				end
				local folder = nil
				if not folder then
					folder = Instance.new("Folder")

					folder.Name = "EclipseVFX Legacy"
					folder.Parent = workspace.Terrain
				end
				self._CachedFolder = folder
				return folder
			end

			function Particle:UpdatePointLight(pData, dt, currentTime)
				local elapsedTime = currentTime - pData.StartTime
				local i = elapsedTime / pData.LifeTime

				if i >= 1 or not pData.VisualPart.Parent then
					return true
				end
				if pData.TotalKeyFrames <= 0 then
					return true
				end

				local targetStep = math.floor(i * pData.TotalKeyFrames)

				if targetStep > pData.CurrentStep then
					pData.CurrentStep = targetStep
					local steppedI = pData.CurrentStep / pData.TotalKeyFrames

					if pData.Graphs.PLRange then
						pData.VisualPart.Range = GraphMod.QueryPointsWithTime(
							steppedI,
							pData.Graphs.PLRange,
							pData.Seeds.PLRange
						)
					end
					if pData.Graphs.PLBrightness then
						pData.VisualPart.Brightness = GraphMod.QueryPointsWithTime(
							steppedI,
							pData.Graphs.PLBrightness,
							pData.Seeds.PLBrightness
						)
					end
					if pData.Graphs.PLColor then
						pData.VisualPart.Color =
							GraphMod.QueryColorPointWithTime(steppedI, pData.Graphs.PLColor)
					end
				end

				return false
			end

			function Particle:EmitPointLight(light, link)
				local data = self:GetData(light)
				if not data or not data.RenderTemplate then
					return
				end

				local visualLight = data.RenderTemplate:Clone()
				local parentPart = data.EmitParent or link or light.Parent
				visualLight.Parent = parentPart

				local safeLifeTime = RangeMod.RandomValueFromRange(data.Lifetime)
				if safeLifeTime <= 0 then
					safeLifeTime = 0.001
				end

				local seedRange = data.PLRange and GraphMod.GenerateSeed(data.PLRange) or {}
				local seedBright = data.PLBrightness and GraphMod.GenerateSeed(data.PLBrightness)
					or {}

				if data.PLRange then
					visualLight.Range = GraphMod.QueryPointsWithTime(0, data.PLRange, seedRange)
				end
				if data.PLBrightness then
					visualLight.Brightness =
						GraphMod.QueryPointsWithTime(0, data.PLBrightness, seedBright)
				end
				if data.PLColor then
					visualLight.Color = GraphMod.QueryColorPointWithTime(0, data.PLColor)
				end

				local pData = {
					Type = "PointLight",
					VisualPart = visualLight,
					Link = link,
					StartTime = os.clock(),
					TotalKeyFrames = math.max(1, data.TotalKeyFrames),
					CurrentStep = 0,
					LifeTime = safeLifeTime,
					PartLife = 0,

					Graphs = {
						PLRange = data.PLRange,
						PLBrightness = data.PLBrightness,
						PLColor = data.PLColor,
					},
					Seeds = {
						PLRange = seedRange,
						PLBrightness = seedBright,
					},
				}

				table.insert(self.ActiveEmits, pData)
			end

			function Particle:Emit(item, link)
				self:Activate()
				if not item or not item.Parent then
					return
				end
				if item:IsA("Beam") then
					self:EmitBeam(item, link)
				elseif item:IsA("PointLight") then
					self:EmitPointLight(item, link)
				elseif item:IsA("Attachment") then
					self:EmitAttachment(item, link)
				elseif item:IsA("Model") then
					self:EmitModel(item, link)
				else
					self:EmitPart(item, link)
				end
			end

			function Particle:Enable(item, link, duration)
				local data = self:GetData(item)
				if not data then
					return
				end

				local emissionMode = item:GetAttribute("EmissionMode") or "Emit"
				if emissionMode == "Animate" then
					item:SetAttribute("AnimateLoop", true)
					self:EmitAnimate(item, link)
					return
				end

				local loopDuration = duration or math.huge
				local config = TypeRegistry.getConfig(item)

				if Particle.ActiveLoops[item] then
					task.cancel(Particle.ActiveLoops[item])
				end

				Particle.ActiveLoops[item] = task.spawn(function()
					local startTime = os.clock()
					while true do
						if not item or not item.Parent then
							Particle.ActiveLoops[item] = nil
							break
						end

						if (os.clock() - startTime >= loopDuration) or not data.CheckEnabled() then
							Particle.ActiveLoops[item] = nil
							break
						end

						self:Emit(item, link)

						local currentRate = config and config:GetAttribute("Rate") or 10
						if currentRate <= 0 then
							currentRate = 1
						end
						task.wait(1 / currentRate)
					end
				end)
			end

			function Particle:EmitAnimate(item, link)
				self:Activate()

				local existing = self.ActiveAnimates[item]
				if existing then
					if existing.InitialWorldCF then
						existing.VisualPart.CFrame = existing.InitialWorldCF
					end
					if existing.Type == "Beam" then
						existing.VisualPart.Enabled = false
					end
					for idx = #self.ActiveEmits, 1, -1 do
						if self.ActiveEmits[idx] == existing then
							local n = #self.ActiveEmits
							if idx < n then
								self.ActiveEmits[idx] = self.ActiveEmits[n]
							end
							self.ActiveEmits[n] = nil
							break
						end
					end
					self.ActiveAnimates[item] = nil
				end

				if item:IsA("Beam") then
					self:EmitBeamAnimate(item, link)
				elseif item:IsA("Attachment") then
					self:EmitAttachmentAnimate(item, link)
				elseif item:IsA("Model") then
					self:EmitModelAnimate(item, link)
				else
					self:EmitPartAnimate(item, link)
				end
			end

			function Particle:EnableEmit(item, link)
				local emissionMode = item:GetAttribute("EmissionMode") or "Emit"
				if emissionMode == "Animate" then
					local emitDelay = item:GetAttribute("EmitDelay") or 0
					local function doAnimate()
						self:EmitAnimate(item, link)
					end
					if emitDelay > 0 then
						task.delay(emitDelay, doAnimate)
					else
						doAnimate()
					end
					return
				end

				local emitCount = item:GetAttribute("EmitCount") or 1
				local emitDelay = item:GetAttribute("EmitDelay") or 0
				local emitDuration = item:GetAttribute("EmitDuration") or 0

				local config = TypeRegistry.getConfig(item)

				local function doEmit()
					for i = 1, emitCount do
						self:Emit(item, link)
					end

					if emitDuration > 0 then
						if config then
							config:SetAttribute("Enabled", true)
						end
						self:Enable(item, link, emitDuration)
						task.delay(emitDuration, function()
							if config and config.Parent then
								config:SetAttribute("Enabled", false)
							end
						end)
					end
				end

				if emitDelay > 0 then
					task.delay(emitDelay, doEmit)
				else
					doEmit()
				end
			end

			function Particle:AbsoluteEmit(item, _parentFiredPE)
				if item:GetAttribute("Transformed") then
					self:EnableEmit(item, nil)
					return
				end

				local shouldFirePE = (
					item:IsA("BasePart")
					or item:IsA("Attachment")
					or item:IsA("Model")
				) and not _parentFiredPE
				if shouldFirePE then
					ParticlesMod.EnableEmit(item)
				end

				for _, child in item:GetChildren() do
					if
						item:IsA("BasePart")
						and child:IsA("BasePart")
						and not child:GetAttribute("Transformed")
					then
						continue
					end
					self:AbsoluteEmit(child, shouldFirePE)
				end
			end

			return Particle
		end

		factories["EmitVFX.PartConstants"] = function()
			local PartConstants = {}

			PartConstants.DirectionVectors = {
				[Enum.NormalId.Top] = { vector = "UpVector", multiplier = 1 },
				[Enum.NormalId.Bottom] = { vector = "UpVector", multiplier = -1 },
				[Enum.NormalId.Front] = { vector = "LookVector", multiplier = 1 },
				[Enum.NormalId.Back] = { vector = "LookVector", multiplier = -1 },
				[Enum.NormalId.Left] = { vector = "RightVector", multiplier = -1 },
				[Enum.NormalId.Right] = { vector = "RightVector", multiplier = 1 },
			}

			PartConstants.shapeFunctions = {
				[Enum.ParticleEmitterShape.Box] = function(p, emitter)
					local Px = (math.random() * 2 - 1) * p.Size.X / 2
					local Py = (math.random() * 2 - 1) * p.Size.Y / 2
					local Pz = (math.random() * 2 - 1) * p.Size.Z / 2
					return Vector3.new(Px, Py, Pz), CFrame.new()
				end,
				[Enum.ParticleEmitterShape.Sphere] = function(p, emitter)
					local outerRadius = p.Size.X / 2
					local innerRadius = outerRadius * emitter.ShapePartial
					local randomRadius = (
						math.random() * (outerRadius ^ 3 - innerRadius ^ 3) + innerRadius ^ 3
					) ^ (1 / 3)
					local theta = math.random() * 2 * math.pi
					local phi = math.acos((math.random() * 2) - 1)
					local direction = Vector3.new(
						math.sin(phi) * math.cos(theta),
						math.sin(phi) * math.sin(theta),
						math.cos(phi)
					)
					return direction * randomRadius, CFrame.lookAt(Vector3.new(), -direction)
				end,
				[Enum.ParticleEmitterShape.Cylinder] = function(p, emitter)
					local radius = p.Size.X / 2
					local height = p.Size.Y
					local innerRadiusRatio = emitter.ShapePartial
					local randomRadius = math.sqrt(math.random()) * (1 - innerRadiusRatio)
						+ innerRadiusRatio
					local angle = math.random() * 2 * math.pi
					local x = randomRadius * radius * math.cos(angle)
					local y = (math.random() * 2 - 1) * (height / 2)
					local z = randomRadius * radius * math.sin(angle)
					local localOffset = Vector3.new(x, y, z)
					local direction
					if math.abs(y) > (height / 2) - 0.01 then
						direction = Vector3.new(0, math.sign(y), 0)
					else
						local lateral = Vector3.new(x, 0, z)
						if lateral.Magnitude < 0.0001 then
							direction = Vector3.new(0, 1, 0)
						else
							direction = lateral.Unit
						end
					end
					return localOffset, CFrame.lookAt(Vector3.new(), -direction)
				end,
				[Enum.ParticleEmitterShape.Disc] = function(p, emitter)
					local radius = p.Size.X / 2
					local innerRadiusRatio = emitter.ShapePartial
					local randomRadiusRatio = math.sqrt(math.random()) * (1 - innerRadiusRatio)
						+ innerRadiusRatio
					local angle = math.random() * 2 * math.pi
					local x = randomRadiusRatio * radius * math.cos(angle)
					local z = randomRadiusRatio * radius * math.sin(angle)
					local localOffset = Vector3.new(x, 0, z)
					if localOffset.Magnitude < 0.0001 then
						return localOffset, CFrame.new()
					end
					local direction = localOffset.Unit
					return localOffset, CFrame.lookAt(Vector3.new(), -direction)
				end,
			}

			return PartConstants
		end

		factories["EmitVFX.Particles"] = function()
			local Range = getModule("EmitVFX.Range")

			local Particle = {}

			local function parseDuration(raw)
				if raw == nil then
					return nil
				end
				if typeof(raw) == "number" then
					return raw
				end
				local text = tostring(raw)
				local vals = {}
				for v in text:gmatch("[^,]+") do
					local n = tonumber(v:match("^%s*(.-)%s*$"))
					if n then
						table.insert(vals, n)
					end
				end
				if #vals == 0 then
					return nil
				end
				if #vals == 1 then
					return vals[1]
				end
				local mn, mx = math.min(vals[1], vals[2]), math.max(vals[1], vals[2])
				return Range.RandomValueFromRange(NumberRange.new(mn, mx))
			end

			Particle.Emit = function(part: Part)
				for i, v in part:GetDescendants() do
					if v:IsA("ParticleEmitter") then
						task.delay(v:GetAttribute("EmitDelay") or 0.001, function()
							v:Emit(v:GetAttribute("EmitCount"))
						end)
					end
				end
			end

			Particle.EnableEmit = function(part)
				task.spawn(function()
					for i, v in part:GetDescendants() do
						if v:IsA("ParticleEmitter") then
							if v:GetAttribute("EmitCount") then
								task.delay(v:GetAttribute("EmitDelay") or 0.001, function()
									v:Emit(v:GetAttribute("EmitCount"))
								end)
							end
							if v:GetAttribute("EmitDuration") then
								task.delay(v:GetAttribute("EmitDelay") or 0.001, function()
									v.Enabled = true
									task.wait(v:GetAttribute("EmitDuration"))
									v.Enabled = false
								end)
							end
						end
						if v:IsA("Trail") then
							local dur = parseDuration(v:GetAttribute("EmitDuration"))
							if dur and dur > 0 then
								task.delay(v:GetAttribute("EmitDelay") or 0.001, function()
									v.Enabled = true
									task.wait(dur)
									v.Enabled = false
								end)
							end
						end
					end
				end)
			end

			Particle.EmitTrail = function(v: Trail)
				local dur = parseDuration(v:GetAttribute("EmitDuration"))
				if dur and dur > 0 then
					task.delay(v:GetAttribute("EmitDelay") or 0.001, function()
						v.Enabled = true
						task.wait(dur)
						v.Enabled = false
					end)
				end
			end

			Particle.EnableEmitSingle = function(v: Instance)
				task.spawn(function()
					if v:IsA("Trail") then
						local dur = parseDuration(v:GetAttribute("EmitDuration"))
						if dur and dur > 0 then
							task.delay(v:GetAttribute("EmitDelay") or 0.001, function()
								v.Enabled = true
								task.wait(dur)
								v.Enabled = false
							end)
						end
					end
					if v:IsA("ParticleEmitter") then
						if v:GetAttribute("EmitCount") then
							task.delay(v:GetAttribute("EmitDelay") or 0.001, function()
								v:Emit(v:GetAttribute("EmitCount"))
							end)
						end
						if v:GetAttribute("EmitDuration") then
							task.delay(v:GetAttribute("EmitDelay") or 0.001, function()
								v.Enabled = true
								task.wait(v:GetAttribute("EmitDuration"))
								v.Enabled = false
							end)
						end
					end
				end)
			end

			Particle.EnableEmitChildrenAndRepeatForAttachments = function(part)
				task.spawn(function()
					for i, v in part:GetChildren() do
						Particle.EnableEmitSingle(v)
						if v:IsA("Attachment") then
							Particle.EnableEmitChildrenAndRepeatForAttachments(v)
						end
					end
				end)
			end

			return Particle
		end

		factories["EmitVFX.Range"] = function()
			local Range = {}

			function Range.RandomValueFromRange(range: NumberRange)
				if range.Min == range.Max then
					return range.Min
				end
				return range.Min + ((range.Max - range.Min) * math.random())
			end

			return Range
		end

		factories["EmitVFX.Transform"] = function()
			local GraphMod = getModule("EmitVFX.Graph")
			local TypeRegistry = getModule("EmitVFX.TypeRegistry")
			local Constants = getModule("EmitVFX.PartConstants")
			local DirectionVectors = Constants.DirectionVectors

			return function(Particle)
				function Particle:Transform(part)
					local typeDef = TypeRegistry.getTypeFor(part)
					if not typeDef or typeDef.directAccess then
						return
					end

					if part:IsA("Model") then
						if not part.PrimaryPart then
							warn("Part-Icles: Model requires PrimaryPart")
							return
						end
						return self:TransformModel(part, typeDef)
					end

					local config = TypeRegistry.createConfig(part, typeDef)

					local renderTemplate = part:Clone()
					renderTemplate.Name = "RenderTemplate"

					for _, child in renderTemplate:GetChildren() do
						if child:GetAttribute("Transformed") or child:IsA("Attachment") then
							continue
						end
						if
							child.Name == TypeRegistry.CONFIG_NAME
							or child.Name == "EmitParent"
							or child.Name == "Link"
						then
							child:Destroy()
						elseif part:IsA("PointLight") then
							child:Destroy()
						elseif part:IsA("Attachment") then
							if
								child.Name == "MeshFlipbooks"
								or child.Name == "BeamFlipbooks"
								or child.Name == "GraphBlender"
							then
								child:Destroy()
							end
						elseif
							not child:IsA("SpecialMesh")
							and not child:IsA("Decal")
							and not child:IsA("Texture")
						then
							child:Destroy()
						end
					end

					for attrName, _ in pairs(renderTemplate:GetAttributes()) do
						renderTemplate:SetAttribute(attrName, nil)
					end

					if renderTemplate:IsA("BasePart") then
						renderTemplate.Anchored = true
						renderTemplate.CanCollide = false
						renderTemplate.CanQuery = false
						renderTemplate.CanTouch = false
						renderTemplate.CastShadow = false
						renderTemplate.Massless = true
						renderTemplate.Transparency = 1
						for _, c in ipairs(renderTemplate:GetChildren()) do
							if c:IsA("Decal") or c:IsA("Texture") then
								c.Transparency = 1
							end
						end
					end

					if renderTemplate:IsA("Attachment") then
						renderTemplate.CFrame = CFrame.new()
					end

					renderTemplate.Parent = part

					if part:IsA("BasePart") then
						for _, child in ipairs(part:GetChildren()) do
							if
								child ~= renderTemplate
								and (
									child:IsA("SpecialMesh")
									or child:IsA("Decal")
									or child:IsA("Texture")
								)
							then
								child:Destroy()
							end
						end
						part.Transparency = 1
					elseif part:IsA("PointLight") then
						part.Enabled = false
					end

					if part:IsA("BasePart") and not part:IsA("Terrain") then
						if not part:FindFirstChild("MeshFlipbooks") then
							local mf = Instance.new("Folder")

							mf.Name = "MeshFlipbooks"
							mf.Parent = part
						end
					end

					if part:IsA("Beam") then
						part.Enabled = false
						if renderTemplate:IsA("Beam") then
							renderTemplate.Enabled = false
						end

						if not part:FindFirstChild("BeamFlipbooks") then
							local bf = Instance.new("Folder")

							bf.Name = "BeamFlipbooks"
							bf.Parent = part
						end

						config:SetAttribute("BeamBrightness", NumberSequence.new(part.Brightness))
						config:SetAttribute("CurveSize0", NumberSequence.new(part.CurveSize0))
						config:SetAttribute("CurveSize1", NumberSequence.new(part.CurveSize1))
						config:SetAttribute("Width0", NumberSequence.new(part.Width0))
						config:SetAttribute("Width1", NumberSequence.new(part.Width1))
						config:SetAttribute("LightEmission", NumberSequence.new(part.LightEmission))
						config:SetAttribute("Segments", NumberSequence.new(part.Segments))
						config:SetAttribute("TextureLength", NumberSequence.new(part.TextureLength))
						config:SetAttribute("TextureSpeed", NumberSequence.new(part.TextureSpeed))
						config:SetAttribute("FaceCamera", part.FaceCamera)

						local gb = Instance.new("Folder")

						gb.Name = "GraphBlender"
						local s1 = Instance.new("Configuration")

						s1.Name = "1"
						s1:SetAttribute("Time", 0)
						s1:SetAttribute("Transparency", part.Transparency)
						s1:SetAttribute("Color", part.Color)
						s1.Parent = gb
						gb.Parent = part
					end

					if not part:FindFirstChild("EmitParent") then
						local ep = Instance.new("ObjectValue")

						ep.Name = "EmitParent"
						ep.Value = nil
						ep.Parent = part
					end

					if
						(part:IsA("BasePart") or part:IsA("Attachment"))
						and not part:FindFirstChild("Link")
					then
						local lk = Instance.new("ObjectValue")

						lk.Name = "Link"
						lk.Value = nil
						lk.Parent = part
					end

					part:SetAttribute("Transformed", true)
					part:SetAttribute("Qwinkle", true)
					part:SetAttribute("EmitCount", part:IsA("Beam") and 1 or 0)
					part:SetAttribute("EmitDuration", 0)
					part:SetAttribute("EmitDelay", 0)
					part:SetAttribute("IsEmitter", true)
					part:SetAttribute("EmissionMode", "Emit")
					part:SetAttribute("AnimateLoop", false)
					part:SetAttribute("LinkMode", "Weld")
				end

				function Particle:PreSimulateForward(
					data,
					seeds,
					initialCF,
					baseDirection,
					spreadRotation,
					link,
					lifetime
				)
					local parentCF = link
							and (link:IsA("Attachment") and link.WorldCFrame or link.CFrame)
						or CFrame.new()
					local totalKeyFrames = math.max(1, data.TotalKeyFrames)
					local stepDT = lifetime / totalKeyFrames

					local currentPosition = initialCF.Position
					local localCF = parentCF:ToObjectSpace(initialCF)
					local baseDir = baseDirection
					local emissionDirection = data.EmissionDirection
					local rotMode = data.RotMode or "OverLife"
					local accRotX, accRotY, accRotZ = 0, 0, 0

					local localCFrames = {}

					localCFrames[0] = parentCF:ToObjectSpace(initialCF)

					for step = 1, totalKeyFrames do
						local steppedI = step / totalKeyFrames
						local elapsedSec = steppedI * lifetime

						local speed =
							GraphMod.QueryPointsWithTime(steppedI, data.Speed, seeds.Speed)
						local draggedSpeed = speed * math.exp(-data.ParticleData.Drag * elapsedSec)

						local accelVelocity = data.ParticleData.Acceleration * elapsedSec

						local displacement = (baseDir * draggedSpeed + accelVelocity) * stepDT

						local parentLocalDelta = parentCF:VectorToObjectSpace(displacement)
						localCF = CFrame.new(parentLocalDelta) * localCF

						local rotSpeedX =
							GraphMod.QueryPointsWithTime(steppedI, data.RotSpeedX, seeds.RotSpeedX)
						local rotSpeedY =
							GraphMod.QueryPointsWithTime(steppedI, data.RotSpeedY, seeds.RotSpeedY)
						local rotSpeedZ =
							GraphMod.QueryPointsWithTime(steppedI, data.RotSpeedZ, seeds.RotSpeedZ)

						local rotCF
						if rotMode == "Speed" then
							accRotX = accRotX + rotSpeedX * stepDT
							accRotY = accRotY + rotSpeedY * stepDT
							accRotZ = accRotZ + rotSpeedZ * stepDT
							rotCF = CFrame.Angles(
								math.rad(accRotX),
								math.rad(accRotY),
								math.rad(accRotZ)
							)
						else
							rotCF = CFrame.Angles(
								math.rad(rotSpeedX),
								math.rad(rotSpeedY),
								math.rad(rotSpeedZ)
							)
						end

						local worldCF = (parentCF * localCF) * rotCF
						currentPosition = worldCF.Position

						if data.VelocityVectored then
							local dirInfo = DirectionVectors[emissionDirection]
								or DirectionVectors[Enum.NormalId.Top]
							baseDir = (worldCF * spreadRotation)[dirInfo.vector]
								* dirInfo.multiplier
						end

						localCFrames[step] = parentCF:ToObjectSpace(worldCF)
					end

					return localCFrames
				end

				function Particle:PreSimulateAttachmentForward(
					data,
					seeds,
					initialCF,
					baseDirection,
					spreadRotation,
					lifetime
				)
					local totalKeyFrames = math.max(1, data.TotalKeyFrames)
					local stepDT = lifetime / totalKeyFrames

					local localCF = initialCF
					local baseDir = baseDirection
					local emissionDirection = data.EmissionDirection
					local rotMode = data.RotMode or "OverLife"
					local accRotX, accRotY, accRotZ = 0, 0, 0

					local localCFrames = {}
					localCFrames[0] = initialCF

					for step = 1, totalKeyFrames do
						local steppedI = step / totalKeyFrames
						local elapsedSec = steppedI * lifetime

						local speed =
							GraphMod.QueryPointsWithTime(steppedI, data.Speed, seeds.Speed)
						local draggedSpeed = speed * math.exp(-data.ParticleData.Drag * elapsedSec)

						local accelVelocity = data.ParticleData.Acceleration * elapsedSec
						local displacement = (baseDir * draggedSpeed + accelVelocity) * stepDT

						localCF = CFrame.new(displacement) * localCF

						local rotSpeedX =
							GraphMod.QueryPointsWithTime(steppedI, data.RotSpeedX, seeds.RotSpeedX)
						local rotSpeedY =
							GraphMod.QueryPointsWithTime(steppedI, data.RotSpeedY, seeds.RotSpeedY)
						local rotSpeedZ =
							GraphMod.QueryPointsWithTime(steppedI, data.RotSpeedZ, seeds.RotSpeedZ)

						local rotCF
						if rotMode == "Speed" then
							accRotX = accRotX + rotSpeedX * stepDT
							accRotY = accRotY + rotSpeedY * stepDT
							accRotZ = accRotZ + rotSpeedZ * stepDT
							rotCF = CFrame.Angles(
								math.rad(accRotX),
								math.rad(accRotY),
								math.rad(accRotZ)
							)
						else
							rotCF = CFrame.Angles(
								math.rad(rotSpeedX),
								math.rad(rotSpeedY),
								math.rad(rotSpeedZ)
							)
						end

						local worldCF = localCF * rotCF

						if data.VelocityVectored then
							local dirVecInfo = DirectionVectors[emissionDirection]
								or DirectionVectors[Enum.NormalId.Top]
							baseDir = (worldCF * spreadRotation)[dirVecInfo.vector]
								* dirVecInfo.multiplier
						end

						localCFrames[step] = worldCF
					end

					return localCFrames
				end

				function Particle:TransformModel(model, typeDef)
					local config = TypeRegistry.createConfig(model, typeDef)

					local renderTemplate = model:Clone()
					renderTemplate.Name = "RenderTemplate"

					for _, child in renderTemplate:GetChildren() do
						if
							child.Name == TypeRegistry.CONFIG_NAME
							or child.Name == "EmitParent"
							or child.Name == "Link"
						then
							child:Destroy()
						end
					end

					for _, attrName in ipairs({
						"Transformed",
						"Qwinkle",
						"IsEmitter",
						"EmitCount",
						"EmitDuration",
						"EmitDelay",
						"EmissionMode",
						"AnimateLoop",
					}) do
						renderTemplate:SetAttribute(attrName, nil)
					end

					for _, desc in renderTemplate:GetDescendants() do
						if desc:IsA("BasePart") then
							desc.Anchored = true
							desc.CanCollide = false
							desc.CanQuery = false
							desc.CanTouch = false
							desc.CastShadow = false
							desc.Massless = true
						end
					end

					renderTemplate.Parent = model

					for _, desc in ipairs(model:GetDescendants()) do
						if desc:IsDescendantOf(renderTemplate) then
							continue
						end
						if desc:IsA("BasePart") then
							desc.Transparency = 1
						elseif
							desc:IsA("SpecialMesh")
							or desc:IsA("Decal")
							or desc:IsA("Texture")
						then
							desc:Destroy()
						end
					end

					if not model:FindFirstChild("EmitParent") then
						local ep = Instance.new("ObjectValue")

						ep.Name = "EmitParent"
						ep.Value = nil
						ep.Parent = model
					end

					if not model:FindFirstChild("Link") then
						local lk = Instance.new("ObjectValue")

						lk.Name = "Link"
						lk.Value = nil
						lk.Parent = model
					end

					model:SetAttribute("Transformed", true)
					model:SetAttribute("Qwinkle", true)
					model:SetAttribute("EmitCount", 0)
					model:SetAttribute("EmitDuration", 0)
					model:SetAttribute("EmitDelay", 0)
					model:SetAttribute("IsEmitter", true)
					model:SetAttribute("EmissionMode", "Emit")
					model:SetAttribute("AnimateLoop", false)
					model:SetAttribute("LinkMode", "Weld")
				end
			end
		end

		factories["EmitVFX.TypeRegistry"] = function()

			local TypeData = getModule("EmitVFX.TypeRegistry.TypeData")

			local TypeRegistry = {}

			TypeRegistry.CONFIG_NAME = "PartIcleProperties"

			TypeRegistry.Types = TypeData.Types

			function TypeRegistry.getTypeFor(item): (any, string?)
				for typeName, typeDef in pairs(TypeRegistry.Types) do
					if typeDef.classCheck(item) then
						return typeDef, typeName
					end
				end
				return nil, nil
			end

			function TypeRegistry.getTypeName(item): string?
				local _, name = TypeRegistry.getTypeFor(item)
				return name
			end

			function TypeRegistry.getConfig(item)
				return item:FindFirstChild(TypeRegistry.CONFIG_NAME)
			end

			function TypeRegistry.getAttrName(typeDef, propName): string
				local propDef = typeDef.properties[propName]
				if propDef and propDef.attrName then
					return propDef.attrName
				end
				return propName
			end

			function TypeRegistry.read(item, propName): any
				local typeDef = TypeRegistry.getTypeFor(item)
				if not typeDef then
					return nil
				end
				local propDef = typeDef.properties[propName]
				if not propDef then
					return nil
				end

				if typeDef.directAccess then
					if propDef.attribute then
						local attrName = propDef.attrName or propName
						local raw = item:GetAttribute(attrName)
						return raw ~= nil and raw or propDef.default
					end
					local ok, val = pcall(function()
						return item[propName]
					end)
					if ok and val ~= nil then
						return val
					end
					return propDef.default
				end

				local config = TypeRegistry.getConfig(item)
				if not config then
					return nil
				end

				local attrName = TypeRegistry.getAttrName(typeDef, propName)
				local raw = config:GetAttribute(attrName)

				if raw == nil then
					return propDef.default
				end

				if propDef.type == "enum" and type(raw) == "string" then
					return Enum[propDef.enumType][raw]
				end

				return raw
			end

			function TypeRegistry.write(item, propName, value)
				local typeDef = TypeRegistry.getTypeFor(item)
				if not typeDef then
					return
				end
				local propDef = typeDef.properties[propName]
				if not propDef then
					return
				end

				if typeDef.directAccess then
					if propDef.attribute then
						local attrName = propDef.attrName or propName
						item:SetAttribute(attrName, value)
					else
						pcall(function()
							item[propName] = value
						end)
					end
					return
				end

				local config = TypeRegistry.getConfig(item)
				if not config then
					return
				end

				local attrName = TypeRegistry.getAttrName(typeDef, propName)

				if propDef.type == "enum" then
					if typeof(value) == "EnumItem" then
						config:SetAttribute(attrName, value.Name)
					else
						config:SetAttribute(attrName, tostring(value))
					end
				else
					config:SetAttribute(attrName, value)
				end
			end

			function TypeRegistry.readAll(item): { [string]: any }?
				local typeDef = TypeRegistry.getTypeFor(item)
				if not typeDef then
					return nil
				end
				local config = TypeRegistry.getConfig(item)
				if not config then
					return nil
				end

				local data = {}
				for propName, propDef in pairs(typeDef.properties) do
					local attrName = TypeRegistry.getAttrName(typeDef, propName)
					local raw = config:GetAttribute(attrName)
					if raw == nil then
						data[propName] = propDef.default
					elseif propDef.type == "enum" and type(raw) == "string" then
						data[propName] = Enum[propDef.enumType][raw]
					else
						data[propName] = raw
					end
				end
				return data
			end

			function TypeRegistry.writeDefaults(config, typeDef)
				for propName, propDef in pairs(typeDef.properties) do
					local attrName = propDef.attrName or propName
					local value = propDef.default
					if propDef.type == "enum" then
						config:SetAttribute(attrName, value.Name)
					else
						config:SetAttribute(attrName, value)
					end
				end
			end

			function TypeRegistry.createConfig(item, typeDef)
				local config = Instance.new("Configuration")

				config.Name = TypeRegistry.CONFIG_NAME
				TypeRegistry.writeDefaults(config, typeDef)
				config.Parent = item
				return config
			end

			function TypeRegistry.isGraph(propDef): boolean
				return propDef.type == "NumberSequence" or propDef.type == "ColorSequence"
			end

			function TypeRegistry.isNonNegative(propDef): boolean
				return propDef.nonNegative == true
			end

			function TypeRegistry.getPropDef(typeName, propName)
				local typeDef = TypeRegistry.Types[typeName]
				if not typeDef then
					return nil
				end
				return typeDef.properties[propName]
			end

			function TypeRegistry.getDefault(propName)
				for _, typeDef in pairs(TypeRegistry.Types) do
					local propDef = typeDef.properties[propName]
					if propDef then
						return propDef.default
					end
				end
				return nil
			end

			return TypeRegistry
		end

		factories["EmitVFX.TypeRegistry.TypeData"] = function()
			local TypeData = {}

			TypeData.PartProperties = {

				Brightness = { type = "NumberSequence", default = NumberSequence.new(1) },
				Color = { type = "ColorSequence", default = ColorSequence.new(Color3.new(1, 1, 1)) },
				SizeX = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					nonNegative = true,
				},
				SizeY = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					nonNegative = true,
				},
				SizeZ = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					nonNegative = true,
				},
				Transparency = { type = "NumberSequence", default = NumberSequence.new(0) },
				Speed = { type = "NumberSequence", default = NumberSequence.new(5) },
				RotSpeedX = { type = "NumberSequence", default = NumberSequence.new(0) },
				RotSpeedY = { type = "NumberSequence", default = NumberSequence.new(0) },
				RotSpeedZ = { type = "NumberSequence", default = NumberSequence.new(0) },

				Lifetime = { type = "NumberRange", default = NumberRange.new(1) },
				Rate = { type = "number", default = 10 },
				Drag = { type = "number", default = 0 },
				Acceleration = { type = "Vector3", default = Vector3.new(0, 0, 0) },
				SpreadAngle = { type = "Vector2", default = Vector2.new(0, 0) },
				RotX = { type = "NumberRange", default = NumberRange.new(0) },
				RotY = { type = "NumberRange", default = NumberRange.new(0) },
				RotZ = { type = "NumberRange", default = NumberRange.new(0) },
				RotMode = { type = "string", default = "OverLife" },
				TotalKeyFrames = { type = "number", default = 100 },
				PartLife = { type = "number", default = 0 },
				ShapePartial = { type = "number", default = 0 },
				VelocityVectored = { type = "boolean", default = false },
				InvertMotion = { type = "boolean", default = false },
				Enabled = { type = "boolean", default = false },

				Shape = {
					type = "enum",
					enumType = "ParticleEmitterShape",
					default = Enum.ParticleEmitterShape.Box,
				},
				ShapeInOut = {
					type = "enum",
					enumType = "ParticleEmitterShapeInOut",
					default = Enum.ParticleEmitterShapeInOut.Outward,
				},
				ShapeStyle = {
					type = "enum",
					enumType = "ParticleEmitterShapeStyle",
					default = Enum.ParticleEmitterShapeStyle.Volume,
				},
				EmissionDirection = {
					type = "enum",
					enumType = "NormalId",
					default = Enum.NormalId.Top,
				},

				FlipbookMode = {
					type = "enum",
					enumType = "ParticleFlipbookMode",
					default = Enum.ParticleFlipbookMode.OneShot,
				},
				FlipbookFramerate = { type = "NumberRange", default = NumberRange.new(1) },
				FlipbookStartRandom = { type = "boolean", default = false },
			}

			TypeData.BeamProperties = {

				Brightness = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					attrName = "BeamBrightness",
					nonNegative = true,
				},
				Width0 = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					nonNegative = true,
				},
				Width1 = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					nonNegative = true,
				},
				CurveSize0 = { type = "NumberSequence", default = NumberSequence.new(0) },
				CurveSize1 = { type = "NumberSequence", default = NumberSequence.new(0) },
				LightEmission = { type = "NumberSequence", default = NumberSequence.new(0) },
				Segments = { type = "NumberSequence", default = NumberSequence.new(10) },
				TextureLength = { type = "NumberSequence", default = NumberSequence.new(1) },
				TextureSpeed = { type = "NumberSequence", default = NumberSequence.new(1) },

				Lifetime = {
					type = "NumberRange",
					default = NumberRange.new(1),
					attrName = "BeamLifetime",
				},
				Rate = { type = "number", default = 10 },
				TotalKeyFrames = { type = "number", default = 100 },
				Enabled = { type = "boolean", default = false },
				FaceCamera = { type = "boolean", default = false },

				FlipbookMode = {
					type = "enum",
					enumType = "ParticleFlipbookMode",
					default = Enum.ParticleFlipbookMode.OneShot,
					attrName = "BeamFlipbookMode",
				},
				FlipbookFramerate = {
					type = "NumberRange",
					default = NumberRange.new(1),
					attrName = "BeamFlipbookFramerate",
				},
				FlipbookStartRandom = {
					type = "boolean",
					default = false,
					attrName = "BeamFlipbookStartRandom",
				},
			}

			TypeData.PointLightProperties = {

				Range = {
					type = "NumberSequence",
					default = NumberSequence.new(8),
					attrName = "PLRange",
					nonNegative = true,
				},
				Brightness = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					attrName = "PLBrightness",
					nonNegative = true,
				},
				Color = {
					type = "ColorSequence",
					default = ColorSequence.new(Color3.new(1, 1, 1)),
					attrName = "PLColor",
				},

				Lifetime = { type = "NumberRange", default = NumberRange.new(1) },
				Rate = { type = "number", default = 10 },
				TotalKeyFrames = { type = "number", default = 100 },
				Enabled = { type = "boolean", default = false },
			}

			TypeData.TrailProperties = {

				Transparency = { type = "NumberSequence", default = NumberSequence.new(0.5) },
				WidthScale = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					nonNegative = true,
				},
				Color = { type = "ColorSequence", default = ColorSequence.new(Color3.new(1, 1, 1)) },

				Brightness = { type = "number", default = 1 },
				LightEmission = { type = "number", default = 0 },
				LightInfluence = { type = "number", default = 1 },
				TextureLength = { type = "number", default = 1 },
				Lifetime = { type = "number", default = 2 },
				MinLength = { type = "number", default = 0.1 },
				MaxLength = { type = "number", default = 0 },

				Duration = {
					type = "string",
					default = "2",
					attribute = true,
					attrName = "EmitDuration",
				},

				Enabled = { type = "boolean", default = true },
				FaceCamera = { type = "boolean", default = false },

				TextureMode = {
					type = "enum",
					enumType = "TextureMode",
					default = Enum.TextureMode.Stretch,
				},
			}

			TypeData.AttachmentProperties = {

				Speed = { type = "NumberSequence", default = NumberSequence.new(5) },
				RotSpeedX = { type = "NumberSequence", default = NumberSequence.new(0) },
				RotSpeedY = { type = "NumberSequence", default = NumberSequence.new(0) },
				RotSpeedZ = { type = "NumberSequence", default = NumberSequence.new(0) },

				Lifetime = { type = "NumberRange", default = NumberRange.new(1) },
				Rate = { type = "number", default = 10 },
				Drag = { type = "number", default = 0 },
				Acceleration = { type = "Vector3", default = Vector3.new(0, 0, 0) },
				SpreadAngle = { type = "Vector2", default = Vector2.new(0, 0) },
				RotX = { type = "NumberRange", default = NumberRange.new(0) },
				RotY = { type = "NumberRange", default = NumberRange.new(0) },
				RotZ = { type = "NumberRange", default = NumberRange.new(0) },
				RotMode = { type = "string", default = "OverLife" },
				TotalKeyFrames = { type = "number", default = 100 },
				PartLife = { type = "number", default = 0 },
				VelocityVectored = { type = "boolean", default = false },
				InvertMotion = { type = "boolean", default = false },
				Enabled = { type = "boolean", default = false },

				EmissionDirection = {
					type = "enum",
					enumType = "NormalId",
					default = Enum.NormalId.Top,
				},
			}

			TypeData.ModelProperties = {

				Speed = { type = "NumberSequence", default = NumberSequence.new(5) },
				RotSpeedX = { type = "NumberSequence", default = NumberSequence.new(0) },
				RotSpeedY = { type = "NumberSequence", default = NumberSequence.new(0) },
				RotSpeedZ = { type = "NumberSequence", default = NumberSequence.new(0) },
				Scale = {
					type = "NumberSequence",
					default = NumberSequence.new(1),
					nonNegative = true,
				},

				Lifetime = { type = "NumberRange", default = NumberRange.new(1) },
				Rate = { type = "number", default = 10 },
				Drag = { type = "number", default = 0 },
				Acceleration = { type = "Vector3", default = Vector3.new(0, 0, 0) },
				SpreadAngle = { type = "Vector2", default = Vector2.new(0, 0) },
				RotX = { type = "NumberRange", default = NumberRange.new(0) },
				RotY = { type = "NumberRange", default = NumberRange.new(0) },
				RotZ = { type = "NumberRange", default = NumberRange.new(0) },
				RotMode = { type = "string", default = "OverLife" },
				TotalKeyFrames = { type = "number", default = 100 },
				PartLife = { type = "number", default = 0 },
				VelocityVectored = { type = "boolean", default = false },
				InvertMotion = { type = "boolean", default = false },
				Enabled = { type = "boolean", default = false },

				EmissionDirection = {
					type = "enum",
					enumType = "NormalId",
					default = Enum.NormalId.Top,
				},
			}

			TypeData.Types = {
				Part = {
					classCheck = function(item)
						return item:IsA("BasePart")
					end,
					pDataType = "Part",
					uiSection = "Meshes",
					properties = TypeData.PartProperties,

					resize = {
						scaleGraphs = { "SizeX", "SizeY", "SizeZ", "Speed" },
						scaleVectors = { "Acceleration" },
					},
					retime = {
						multiplyNumbers = { "Rate", "Drag" },
						divideRanges = { "Lifetime", "FlipbookFramerate" },
						multiplyGraphs = { "Speed", "RotSpeedX", "RotSpeedY", "RotSpeedZ" },
						scaleVectors = { "Acceleration" },
					},
					clipboard = {
						{
							name = "Spawning",
							props = { "Rate", "Lifetime", "SpreadAngle", "EmissionDirection" },
						},
						{
							name = "Appearance",
							props = {
								"Brightness",
								"Color",
								"SizeX",
								"SizeY",
								"SizeZ",
								"Transparency",
								"Material",
							},
						},
						{
							name = "Movement",
							props = {
								"Speed",
								"RotMode",
								"RotSpeedX",
								"RotSpeedY",
								"RotSpeedZ",
								"Acceleration",
								"Drag",
								"VelocityVectored",
								"InvertMotion",
							},
						},
						{
							name = "Shape",
							props = { "Shape", "ShapeInOut", "ShapeStyle", "ShapePartial" },
						},
						{
							name = "Flipbook",
							props = { "FlipbookMode", "FlipbookFramerate", "FlipbookStartRandom" },
						},
						{
							name = "Advanced",
							props = { "TotalKeyFrames", "PartLife", "RotX", "RotY", "RotZ" },
						},
					},
				},

				Beam = {
					classCheck = function(item)
						return item:IsA("Beam")
					end,
					pDataType = "Beam",
					uiSection = "Beams",
					properties = TypeData.BeamProperties,

					resize = {
						scaleGraphs = { "Width0", "Width1" },
					},
					retime = {
						multiplyNumbers = { "Rate" },
						divideRanges = { "Lifetime", "FlipbookFramerate" },
						multiplyGraphs = { "TextureSpeed" },
					},
					clipboard = {
						{ name = "Spawning", props = { "Rate", "Lifetime" } },
						{
							name = "Appearance",
							props = { "Brightness", "Width0", "Width1", "LightEmission" },
						},
						{
							name = "Geometry",
							props = {
								"CurveSize0",
								"CurveSize1",
								"Segments",
								"TextureLength",
								"TextureSpeed",
								"FaceCamera",
							},
						},
						{
							name = "Flipbook",
							props = { "FlipbookMode", "FlipbookFramerate", "FlipbookStartRandom" },
						},
						{ name = "Advanced", props = { "TotalKeyFrames" } },
						{ name = "Blender", props = { "Blender" } },
					},
				},

				PointLight = {
					classCheck = function(item)
						return item:IsA("PointLight")
					end,
					pDataType = "PointLight",
					uiSection = "PointLights",
					properties = TypeData.PointLightProperties,

					resize = {
						scaleGraphs = { "Range" },
					},
					retime = {
						multiplyNumbers = { "Rate" },
						divideRanges = { "Lifetime" },
					},
					clipboard = {
						{ name = "Spawning", props = { "Rate", "Lifetime" } },
						{ name = "Appearance", props = { "Range", "Brightness", "Color" } },
						{ name = "Advanced", props = { "TotalKeyFrames" } },
					},
				},

				Trail = {
					classCheck = function(item)
						return item:IsA("Trail")
					end,
					pDataType = "Trail",
					uiSection = "Trails",
					directAccess = true,
					properties = TypeData.TrailProperties,

					resize = {
						scaleGraphs = { "WidthScale" },
					},
					retime = {
						divideNumbers = { "Lifetime" },
					},
					clipboard = {
						{ name = "Emission", props = { "Duration", "Lifetime" } },
						{
							name = "Appearance",
							props = {
								"Brightness",
								"Transparency",
								"Color",
								"WidthScale",
								"LightEmission",
								"LightInfluence",
							},
						},
						{
							name = "Geometry",
							props = {
								"MinLength",
								"MaxLength",
								"TextureLength",
								"TextureMode",
								"FaceCamera",
							},
						},
					},
				},

				Attachment = {
					classCheck = function(item)
						return item:IsA("Attachment")
					end,
					pDataType = "Attachment",
					uiSection = "Attachments",
					properties = TypeData.AttachmentProperties,

					resize = {
						scaleGraphs = { "Speed" },
						scaleVectors = { "Acceleration" },
					},
					retime = {
						multiplyNumbers = { "Rate", "Drag" },
						divideRanges = { "Lifetime" },
						multiplyGraphs = { "Speed", "RotSpeedX", "RotSpeedY", "RotSpeedZ" },
						scaleVectors = { "Acceleration" },
					},
					clipboard = {
						{
							name = "Spawning",
							props = { "Rate", "Lifetime", "SpreadAngle", "EmissionDirection" },
						},
						{
							name = "Movement",
							props = {
								"Speed",
								"RotMode",
								"RotSpeedX",
								"RotSpeedY",
								"RotSpeedZ",
								"Acceleration",
								"Drag",
								"VelocityVectored",
								"InvertMotion",
							},
						},
						{
							name = "Advanced",
							props = { "TotalKeyFrames", "PartLife", "RotX", "RotY", "RotZ" },
						},
					},
				},

				Model = {
					classCheck = function(item)
						return item:IsA("Model")
					end,
					pDataType = "Model",
					uiSection = "Models",
					properties = TypeData.ModelProperties,

					resize = {
						scaleGraphs = { "Speed", "Scale" },
						scaleVectors = { "Acceleration" },
					},
					retime = {
						multiplyNumbers = { "Rate", "Drag" },
						divideRanges = { "Lifetime" },
						multiplyGraphs = { "Speed", "RotSpeedX", "RotSpeedY", "RotSpeedZ" },
						scaleVectors = { "Acceleration" },
					},
					clipboard = {
						{
							name = "Spawning",
							props = { "Rate", "Lifetime", "SpreadAngle", "EmissionDirection" },
						},
						{ name = "Scale", props = { "Scale" } },
						{
							name = "Movement",
							props = {
								"Speed",
								"RotMode",
								"RotSpeedX",
								"RotSpeedY",
								"RotSpeedZ",
								"Acceleration",
								"Drag",
								"VelocityVectored",
								"InvertMotion",
							},
						},
						{
							name = "Advanced",
							props = { "TotalKeyFrames", "PartLife", "RotX", "RotY", "RotZ" },
						},
					},
				},
			}

			return TypeData
		end

		factories["EmitVFX.Update"] = function()
			local GraphMod = getModule("EmitVFX.Graph")
			local Constants = getModule("EmitVFX.PartConstants")
			local DirectionVectors = Constants.DirectionVectors

			local function getLinkCF(pData)
				local lk = pData.Link
				if not (lk and lk.Parent) then
					return CFrame.new(), false
				end
				local isAtt = lk:IsA("Attachment")
				if pData.LinkMode == "Follow" then
					return CFrame.new(isAtt and lk.WorldPosition or lk.Position), false
				end
				return isAtt and lk.WorldCFrame or lk.CFrame, pData.LinkMode == "Weld"
			end

			return function(Particle)
				function Particle:UpdatePart(pData, dt, currentTime)
					local elapsedTime = currentTime - pData.StartTime
					local i = elapsedTime / pData.LifeTime

					if i >= 1 or not pData.VisualPart or not pData.VisualPart.Parent then
						return true
					end
					if pData.TotalKeyFrames <= 0 then
						return true
					end

					pData.AccumulatedDT += dt
					local targetStep = math.floor(i * pData.TotalKeyFrames)

					if targetStep > pData.CurrentStep then
						local prevStep = pData.CurrentStep
						local stepsToProcess = targetStep - prevStep
						local perStepDT = pData.AccumulatedDT / stepsToProcess
						pData.AccumulatedDT = 0

						if pData.InvertMotion then
							pData.CurrentStep = targetStep
							local reverseStep = pData.TotalKeyFrames - targetStep
							local localCF = pData.SimLocalCFrames[reverseStep]
								or pData.SimLocalCFrames[0]
							local parentCF_now = getLinkCF(pData)
							pData.VisualPart.CFrame = parentCF_now * localCF
							pData.CurrentPosition = pData.VisualPart.Position
						elseif pData.NeedsFullIteration then
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime

								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								local draggedSpeed = hasDrag
										and (speed * math.exp(-pData.Drag * elapsedSec))
									or speed

								local displacement
								if hasAccel then
									displacement = (
										pData.BaseDirection * draggedSpeed
										+ pData.Acceleration * elapsedSec
									) * perStepDT
								else
									displacement = pData.BaseDirection * (draggedSpeed * perStepDT)
								end

								local parentCF_now, useVOS = getLinkCF(pData)
								local parentLocalDelta = useVOS
										and parentCF_now:VectorToObjectSpace(displacement)
									or displacement
								pData.LocalCF = CFrame.new(parentLocalDelta) * pData.LocalCF

								local rotSpeedX = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedX,
									pData.Seeds.RotSpeedX
								)
								local rotSpeedY = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedY,
									pData.Seeds.RotSpeedY
								)
								local rotSpeedZ = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedZ,
									pData.Seeds.RotSpeedZ
								)

								local rotationCFrame
								if pData.RotMode == "Speed" then
									pData.AccRotX = pData.AccRotX + rotSpeedX * perStepDT
									pData.AccRotY = pData.AccRotY + rotSpeedY * perStepDT
									pData.AccRotZ = pData.AccRotZ + rotSpeedZ * perStepDT
									rotationCFrame = CFrame.Angles(
										math.rad(pData.AccRotX),
										math.rad(pData.AccRotY),
										math.rad(pData.AccRotZ)
									)
								else
									rotationCFrame = CFrame.Angles(
										math.rad(rotSpeedX),
										math.rad(rotSpeedY),
										math.rad(rotSpeedZ)
									)
								end

								pData.VisualPart.CFrame = (parentCF_now * pData.LocalCF)
									* rotationCFrame
								pData.CurrentPosition = pData.VisualPart.Position

								local rotatedCF = pData.VisualPart.CFrame * pData.SpreadRotation
								local dirInfo = DirectionVectors[pData.EmissionDirection]
									or DirectionVectors[Enum.NormalId.Top]
								pData.BaseDirection = rotatedCF[dirInfo.vector] * dirInfo.multiplier
							end
							pData.CurrentStep = targetStep
						elseif pData.NeedsRotAccum then
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							local totalScalarDisp = 0
							local totalAccelTimeSum = 0

							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime
								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								if hasDrag then
									speed = speed * math.exp(-pData.Drag * elapsedSec)
								end
								totalScalarDisp = totalScalarDisp + speed * perStepDT
								if hasAccel then
									totalAccelTimeSum = totalAccelTimeSum + elapsedSec * perStepDT
								end

								local rotSpeedX = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedX,
									pData.Seeds.RotSpeedX
								)
								local rotSpeedY = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedY,
									pData.Seeds.RotSpeedY
								)
								local rotSpeedZ = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedZ,
									pData.Seeds.RotSpeedZ
								)
								pData.AccRotX = pData.AccRotX + rotSpeedX * perStepDT
								pData.AccRotY = pData.AccRotY + rotSpeedY * perStepDT
								pData.AccRotZ = pData.AccRotZ + rotSpeedZ * perStepDT
							end

							local totalDisplacement = pData.BaseDirection * totalScalarDisp
							if hasAccel then
								totalDisplacement = totalDisplacement
									+ pData.Acceleration * totalAccelTimeSum
							end

							local parentCF_now, useVOS = getLinkCF(pData)
							local parentLocalDelta = useVOS
									and parentCF_now:VectorToObjectSpace(totalDisplacement)
								or totalDisplacement
							pData.LocalCF = CFrame.new(parentLocalDelta) * pData.LocalCF
							local rotationCFrame = CFrame.Angles(
								math.rad(pData.AccRotX),
								math.rad(pData.AccRotY),
								math.rad(pData.AccRotZ)
							)

							pData.VisualPart.CFrame = (parentCF_now * pData.LocalCF)
								* rotationCFrame
							pData.CurrentPosition = pData.VisualPart.Position
							pData.CurrentStep = targetStep
						else
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							local totalScalarDisp = 0
							local totalAccelTimeSum = 0

							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime
								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								if hasDrag then
									speed = speed * math.exp(-pData.Drag * elapsedSec)
								end
								totalScalarDisp = totalScalarDisp + speed * perStepDT
								if hasAccel then
									totalAccelTimeSum = totalAccelTimeSum + elapsedSec * perStepDT
								end
							end

							local totalDisplacement = pData.BaseDirection * totalScalarDisp
							if hasAccel then
								totalDisplacement = totalDisplacement
									+ pData.Acceleration * totalAccelTimeSum
							end

							local parentCF_now, useVOS = getLinkCF(pData)
							local parentLocalDelta = useVOS
									and parentCF_now:VectorToObjectSpace(totalDisplacement)
								or totalDisplacement
							pData.LocalCF = CFrame.new(parentLocalDelta) * pData.LocalCF

							local steppedI = targetStep / pData.TotalKeyFrames
							local rotX = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedX,
								pData.Seeds.RotSpeedX
							)
							local rotY = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedY,
								pData.Seeds.RotSpeedY
							)
							local rotZ = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedZ,
								pData.Seeds.RotSpeedZ
							)
							local rotationCFrame =
								CFrame.Angles(math.rad(rotX), math.rad(rotY), math.rad(rotZ))

							pData.VisualPart.CFrame = (parentCF_now * pData.LocalCF)
								* rotationCFrame
							pData.CurrentPosition = pData.VisualPart.Position
							pData.CurrentStep = targetStep
						end

						local steppedI = targetStep / pData.TotalKeyFrames
						local sizex = GraphMod.QueryPointsWithTime(
							steppedI,
							pData.Graphs.SizeX,
							pData.Seeds.SizeX
						)
						local sizey = GraphMod.QueryPointsWithTime(
							steppedI,
							pData.Graphs.SizeY,
							pData.Seeds.SizeY
						)
						local sizez = GraphMod.QueryPointsWithTime(
							steppedI,
							pData.Graphs.SizeZ,
							pData.Seeds.SizeZ
						)
						if pData.SpecialMesh then
							pData.SpecialMesh.Scale = Vector3.new(sizex, sizey, sizez)
						else
							pData.VisualPart.Size = Vector3.new(sizex, sizey, sizez)
						end

						local transparency = GraphMod.QueryPointsWithTime(
							steppedI,
							pData.Graphs.Transparency,
							pData.Seeds.Transparency
						)

						if pData.HasDecal then
							local brightness = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.Brightness,
								pData.Seeds.Brightness
							)
							local color =
								GraphMod.QueryColorPointWithTime(steppedI, pData.Graphs.Color)
							pData.Decal.Transparency = transparency
							pData.Decal.Color3 = Color3.fromRGB(
								color.R * 255 * brightness,
								color.G * 255 * brightness,
								color.B * 255 * brightness
							)
						else
							pData.VisualPart.Transparency = transparency
							pData.VisualPart.Color =
								GraphMod.QueryColorPointWithTime(steppedI, pData.Graphs.Color)
						end
					end

					return false
				end
				function Particle:UpdateBeam(pData, dt, currentTime)
					local elapsedTime = currentTime - pData.StartTime
					local i = elapsedTime / pData.LifeTime

					if i >= 1 or not pData.VisualPart.Parent then
						return true
					end
					if pData.TotalKeyFrames <= 0 then
						return true
					end

					local targetStep = math.floor(i * pData.TotalKeyFrames)

					if targetStep > pData.CurrentStep then
						pData.CurrentStep = targetStep
						local steppedI = pData.CurrentStep / pData.TotalKeyFrames

						local transStates = pData.TransStates
						local colorStates = pData.ColorStates

						if transStates and #transStates >= 2 then
							local lastTrans = pData._lastTransIdx or 1
							local pairIdx = #transStates - 1
							for idx = lastTrans, #transStates - 1 do
								if
									steppedI >= transStates[idx].Time
									and steppedI <= transStates[idx + 1].Time
								then
									pairIdx = idx
									break
								end
							end
							pData._lastTransIdx = pairIdx
							local lower = transStates[pairIdx]
							local upper = transStates[pairIdx + 1] or transStates[#transStates]
							local range = upper.Time - lower.Time
							local segmentAlpha = range > 0 and ((steppedI - lower.Time) / range)
								or 0
							local mergedTimes = pData.TransMergedTimes[pairIdx]
							if mergedTimes then
								pData.VisualPart.Transparency = GraphMod.LerpGraphFast(
									lower.Graph,
									upper.Graph,
									segmentAlpha,
									mergedTimes
								)
							else
								pData.VisualPart.Transparency =
									GraphMod.LerpGraph(lower.Graph, upper.Graph, segmentAlpha)
							end
						elseif transStates and #transStates == 1 then
							pData.VisualPart.Transparency = transStates[1].Graph
						end

						if colorStates and #colorStates >= 2 then
							local lastColor = pData._lastColorIdx or 1
							local pairIdx = #colorStates - 1
							for idx = lastColor, #colorStates - 1 do
								if
									steppedI >= colorStates[idx].Time
									and steppedI <= colorStates[idx + 1].Time
								then
									pairIdx = idx
									break
								end
							end
							pData._lastColorIdx = pairIdx
							local lower = colorStates[pairIdx]
							local upper = colorStates[pairIdx + 1] or colorStates[#colorStates]
							local range = upper.Time - lower.Time
							local segmentAlpha = range > 0 and ((steppedI - lower.Time) / range)
								or 0
							local mergedTimes = pData.ColorMergedTimes[pairIdx]
							if mergedTimes then
								pData.VisualPart.Color = GraphMod.LerpColorGraphFast(
									lower.Graph,
									upper.Graph,
									segmentAlpha,
									mergedTimes
								)
							else
								pData.VisualPart.Color =
									GraphMod.LerpColorGraph(lower.Graph, upper.Graph, segmentAlpha)
							end
						elseif colorStates and #colorStates == 1 then
							pData.VisualPart.Color = colorStates[1].Graph
						end

						for name, animData in pairs(pData.AnimatedProps) do
							pData.VisualPart[name] = GraphMod.QueryPointsWithTime(
								steppedI,
								animData.Sequence,
								animData.Seed
							)
						end
					end

					return false
				end

				function Particle:UpdateAttachment(pData, dt, currentTime)
					local elapsedTime = currentTime - pData.StartTime
					local i = elapsedTime / pData.LifeTime
					if i >= 1 or not pData.VisualPart or not pData.VisualPart.Parent then
						return true
					end
					if pData.TotalKeyFrames <= 0 then
						return true
					end
					pData.AccumulatedDT += dt
					local targetStep = math.floor(i * pData.TotalKeyFrames)

					if targetStep > pData.CurrentStep then
						local prevStep = pData.CurrentStep
						local stepsToProcess = targetStep - prevStep
						local perStepDT = pData.AccumulatedDT / stepsToProcess
						pData.AccumulatedDT = 0

						if pData.InvertMotion then
							pData.CurrentStep = targetStep
							local reverseStep = pData.TotalKeyFrames - targetStep
							local localCF = pData.SimLocalCFrames[reverseStep]
								or pData.SimLocalCFrames[0]
							pData.VisualPart.CFrame = localCF
							pData.LocalCF = localCF
						elseif pData.NeedsFullIteration then
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime

								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								local draggedSpeed = hasDrag
										and (speed * math.exp(-pData.Drag * elapsedSec))
									or speed

								local displacement
								if hasAccel then
									displacement = (
										pData.BaseDirection * draggedSpeed
										+ pData.Acceleration * elapsedSec
									) * perStepDT
								else
									displacement = pData.BaseDirection * (draggedSpeed * perStepDT)
								end

								pData.LocalCF = CFrame.new(displacement) * pData.LocalCF

								local rotSpeedX = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedX,
									pData.Seeds.RotSpeedX
								)
								local rotSpeedY = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedY,
									pData.Seeds.RotSpeedY
								)
								local rotSpeedZ = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedZ,
									pData.Seeds.RotSpeedZ
								)

								local rotationCFrame
								if pData.RotMode == "Speed" then
									pData.AccRotX = pData.AccRotX + rotSpeedX * perStepDT
									pData.AccRotY = pData.AccRotY + rotSpeedY * perStepDT
									pData.AccRotZ = pData.AccRotZ + rotSpeedZ * perStepDT
									rotationCFrame = CFrame.Angles(
										math.rad(pData.AccRotX),
										math.rad(pData.AccRotY),
										math.rad(pData.AccRotZ)
									)
								else
									rotationCFrame = CFrame.Angles(
										math.rad(rotSpeedX),
										math.rad(rotSpeedY),
										math.rad(rotSpeedZ)
									)
								end

								pData.VisualPart.CFrame = pData.LocalCF * rotationCFrame

								local rotatedCF = pData.VisualPart.CFrame * pData.SpreadRotation
								local dirInfo = DirectionVectors[pData.EmissionDirection]
									or DirectionVectors[Enum.NormalId.Top]
								pData.BaseDirection = rotatedCF[dirInfo.vector] * dirInfo.multiplier
							end
							pData.CurrentStep = targetStep
						elseif pData.NeedsRotAccum then
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							local totalScalarDisp = 0
							local totalAccelTimeSum = 0

							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime
								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								if hasDrag then
									speed = speed * math.exp(-pData.Drag * elapsedSec)
								end
								totalScalarDisp = totalScalarDisp + speed * perStepDT
								if hasAccel then
									totalAccelTimeSum = totalAccelTimeSum + elapsedSec * perStepDT
								end

								local rotSpeedX = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedX,
									pData.Seeds.RotSpeedX
								)
								local rotSpeedY = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedY,
									pData.Seeds.RotSpeedY
								)
								local rotSpeedZ = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedZ,
									pData.Seeds.RotSpeedZ
								)
								pData.AccRotX = pData.AccRotX + rotSpeedX * perStepDT
								pData.AccRotY = pData.AccRotY + rotSpeedY * perStepDT
								pData.AccRotZ = pData.AccRotZ + rotSpeedZ * perStepDT
							end

							local totalDisplacement = pData.BaseDirection * totalScalarDisp
							if hasAccel then
								totalDisplacement = totalDisplacement
									+ pData.Acceleration * totalAccelTimeSum
							end

							pData.LocalCF = CFrame.new(totalDisplacement) * pData.LocalCF
							local rotationCFrame = CFrame.Angles(
								math.rad(pData.AccRotX),
								math.rad(pData.AccRotY),
								math.rad(pData.AccRotZ)
							)

							pData.VisualPart.CFrame = pData.LocalCF * rotationCFrame
							pData.CurrentStep = targetStep
						else
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							local totalScalarDisp = 0
							local totalAccelTimeSum = 0

							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime
								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								if hasDrag then
									speed = speed * math.exp(-pData.Drag * elapsedSec)
								end
								totalScalarDisp = totalScalarDisp + speed * perStepDT
								if hasAccel then
									totalAccelTimeSum = totalAccelTimeSum + elapsedSec * perStepDT
								end
							end

							local totalDisplacement = pData.BaseDirection * totalScalarDisp
							if hasAccel then
								totalDisplacement = totalDisplacement
									+ pData.Acceleration * totalAccelTimeSum
							end

							pData.LocalCF = CFrame.new(totalDisplacement) * pData.LocalCF

							local steppedI = targetStep / pData.TotalKeyFrames
							local rotX = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedX,
								pData.Seeds.RotSpeedX
							)
							local rotY = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedY,
								pData.Seeds.RotSpeedY
							)
							local rotZ = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedZ,
								pData.Seeds.RotSpeedZ
							)
							local rotationCFrame =
								CFrame.Angles(math.rad(rotX), math.rad(rotY), math.rad(rotZ))

							pData.VisualPart.CFrame = pData.LocalCF * rotationCFrame
							pData.CurrentStep = targetStep
						end
					end

					return false
				end
			end
		end

		factories["EmitVFX.UpdateModel"] = function()
			local GraphMod = getModule("EmitVFX.Graph")
			local Constants = getModule("EmitVFX.PartConstants")
			local DirectionVectors = Constants.DirectionVectors

			local function getLinkCF(pData)
				local lk = pData.Link
				if not (lk and lk.Parent) then
					return CFrame.new(), false
				end
				if pData.LinkMode == "Follow" then
					return CFrame.new(lk.Position), false
				end
				return lk.CFrame, pData.LinkMode == "Weld"
			end

			return function(Particle)
				function Particle:UpdateModel(pData, dt, currentTime)
					local elapsedTime = currentTime - pData.StartTime
					local i = elapsedTime / pData.LifeTime

					if i >= 1 or not pData.VisualPart or not pData.VisualPart.Parent then
						return true
					end
					if pData.TotalKeyFrames <= 0 then
						return true
					end

					pData.AccumulatedDT += dt
					local targetStep = math.floor(i * pData.TotalKeyFrames)

					if targetStep > pData.CurrentStep then
						local prevStep = pData.CurrentStep
						local stepsToProcess = targetStep - prevStep
						local perStepDT = pData.AccumulatedDT / stepsToProcess
						pData.AccumulatedDT = 0

						if pData.InvertMotion then
							pData.CurrentStep = targetStep
							local reverseStep = pData.TotalKeyFrames - targetStep
							local localCF = pData.SimLocalCFrames[reverseStep]
								or pData.SimLocalCFrames[0]
							local parentCF_now = getLinkCF(pData)
							pData.VisualPart:PivotTo(parentCF_now * localCF)
							pData.CurrentPosition = pData.VisualPart:GetPivot().Position
						elseif pData.NeedsFullIteration then
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime

								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								local draggedSpeed = hasDrag
										and (speed * math.exp(-pData.Drag * elapsedSec))
									or speed

								local displacement
								if hasAccel then
									displacement = (
										pData.BaseDirection * draggedSpeed
										+ pData.Acceleration * elapsedSec
									) * perStepDT
								else
									displacement = pData.BaseDirection * (draggedSpeed * perStepDT)
								end

								local parentCF_now, useVOS = getLinkCF(pData)
								local parentLocalDelta = useVOS
										and parentCF_now:VectorToObjectSpace(displacement)
									or displacement
								pData.LocalCF = CFrame.new(parentLocalDelta) * pData.LocalCF

								local rotSpeedX = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedX,
									pData.Seeds.RotSpeedX
								)
								local rotSpeedY = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedY,
									pData.Seeds.RotSpeedY
								)
								local rotSpeedZ = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedZ,
									pData.Seeds.RotSpeedZ
								)

								local rotationCFrame
								if pData.RotMode == "Speed" then
									pData.AccRotX = pData.AccRotX + rotSpeedX * perStepDT
									pData.AccRotY = pData.AccRotY + rotSpeedY * perStepDT
									pData.AccRotZ = pData.AccRotZ + rotSpeedZ * perStepDT
									rotationCFrame = CFrame.Angles(
										math.rad(pData.AccRotX),
										math.rad(pData.AccRotY),
										math.rad(pData.AccRotZ)
									)
								else
									rotationCFrame = CFrame.Angles(
										math.rad(rotSpeedX),
										math.rad(rotSpeedY),
										math.rad(rotSpeedZ)
									)
								end

								pData.VisualPart:PivotTo(
									(parentCF_now * pData.LocalCF) * rotationCFrame
								)
								pData.CurrentPosition = pData.VisualPart:GetPivot().Position

								local rotatedCF = pData.VisualPart:GetPivot() * pData.SpreadRotation
								local dirInfo = DirectionVectors[pData.EmissionDirection]
									or DirectionVectors[Enum.NormalId.Top]
								pData.BaseDirection = rotatedCF[dirInfo.vector] * dirInfo.multiplier
							end
							pData.CurrentStep = targetStep
						elseif pData.NeedsRotAccum then
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							local totalScalarDisp = 0
							local totalAccelTimeSum = 0

							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime
								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								if hasDrag then
									speed = speed * math.exp(-pData.Drag * elapsedSec)
								end
								totalScalarDisp = totalScalarDisp + speed * perStepDT
								if hasAccel then
									totalAccelTimeSum = totalAccelTimeSum + elapsedSec * perStepDT
								end

								local rotSpeedX = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedX,
									pData.Seeds.RotSpeedX
								)
								local rotSpeedY = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedY,
									pData.Seeds.RotSpeedY
								)
								local rotSpeedZ = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.RotSpeedZ,
									pData.Seeds.RotSpeedZ
								)
								pData.AccRotX = pData.AccRotX + rotSpeedX * perStepDT
								pData.AccRotY = pData.AccRotY + rotSpeedY * perStepDT
								pData.AccRotZ = pData.AccRotZ + rotSpeedZ * perStepDT
							end

							local totalDisplacement = pData.BaseDirection * totalScalarDisp
							if hasAccel then
								totalDisplacement = totalDisplacement
									+ pData.Acceleration * totalAccelTimeSum
							end

							local parentCF_now, useVOS = getLinkCF(pData)
							local parentLocalDelta = useVOS
									and parentCF_now:VectorToObjectSpace(totalDisplacement)
								or totalDisplacement
							pData.LocalCF = CFrame.new(parentLocalDelta) * pData.LocalCF
							local rotationCFrame = CFrame.Angles(
								math.rad(pData.AccRotX),
								math.rad(pData.AccRotY),
								math.rad(pData.AccRotZ)
							)

							pData.VisualPart:PivotTo(
								(parentCF_now * pData.LocalCF) * rotationCFrame
							)
							pData.CurrentPosition = pData.VisualPart:GetPivot().Position
							pData.CurrentStep = targetStep
						else
							local hasDrag = pData.HasDrag
							local hasAccel = pData.HasAccel
							local totalScalarDisp = 0
							local totalAccelTimeSum = 0

							for step = prevStep + 1, targetStep do
								local si = step / pData.TotalKeyFrames
								local elapsedSec = si * pData.LifeTime
								local speed = GraphMod.QueryPointsWithTime(
									si,
									pData.Graphs.Speed,
									pData.Seeds.Speed
								)
								if hasDrag then
									speed = speed * math.exp(-pData.Drag * elapsedSec)
								end
								totalScalarDisp = totalScalarDisp + speed * perStepDT
								if hasAccel then
									totalAccelTimeSum = totalAccelTimeSum + elapsedSec * perStepDT
								end
							end

							local totalDisplacement = pData.BaseDirection * totalScalarDisp
							if hasAccel then
								totalDisplacement = totalDisplacement
									+ pData.Acceleration * totalAccelTimeSum
							end

							local parentCF_now, useVOS = getLinkCF(pData)
							local parentLocalDelta = useVOS
									and parentCF_now:VectorToObjectSpace(totalDisplacement)
								or totalDisplacement
							pData.LocalCF = CFrame.new(parentLocalDelta) * pData.LocalCF

							local steppedI = targetStep / pData.TotalKeyFrames
							local rotX = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedX,
								pData.Seeds.RotSpeedX
							)
							local rotY = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedY,
								pData.Seeds.RotSpeedY
							)
							local rotZ = GraphMod.QueryPointsWithTime(
								steppedI,
								pData.Graphs.RotSpeedZ,
								pData.Seeds.RotSpeedZ
							)
							local rotationCFrame =
								CFrame.Angles(math.rad(rotX), math.rad(rotY), math.rad(rotZ))

							pData.VisualPart:PivotTo(
								(parentCF_now * pData.LocalCF) * rotationCFrame
							)
							pData.CurrentPosition = pData.VisualPart:GetPivot().Position
							pData.CurrentStep = targetStep
						end

						local steppedI = targetStep / pData.TotalKeyFrames
						local scale = GraphMod.QueryPointsWithTime(
							steppedI,
							pData.Graphs.Scale,
							pData.Seeds.Scale
						)
						pData.VisualPart:ScaleTo(scale)
						for pe, origSize in pairs(pData.PESnapshots) do
							if pe.Parent then
								pe.Size = GraphMod.ScaleSequence(origSize, scale)
							end
						end
					end

					return false
				end
			end
		end

		shared = table.clone(shared or {})
		if emitChild then
			shared.vfx = {
				emit = function(...)
					local runs = {}
					for _, object in { ... } do
						if
							typeof(object) ~= "Instance"
							and type(object) == "table"
							and object._getReal
						then
							object = object._getReal()
						end
						table.insert(runs, emitChild(object))
					end
					return {
						Finished = getModule("EmitModule.pkg.EclipsePromise").new(function(resolve)
							while true do
								local done = true
								for _, run in runs do
									if not run:IsFinished() then
										done = false
										break
									end
								end
								if done then
									resolve()
									return
								end
								task.wait(0.02)
							end
						end),
					}
				end,
			}
		end
		local api = { scopes = {}, caches = {}, initialized = {} }
		local function clone(item)
			local was = item.Archivable
			item.Archivable = true
			local ok, value = pcall(function()
				return item:Clone()
			end)
			item.Archivable = was
			assert(ok and value, value)
			value.Archivable = false
			for _, v in value:GetDescendants() do
				if v:IsA("LuaSourceContainer") then
					v:Destroy()
				end
			end
			if value:IsA("BasePart") then
				value.Anchored = true
				value.CanCollide = false
				value.CanQuery = false
				value.CanTouch = false
			end
			return value
		end
		local function initCache(name, effect)
			if api.initialized[name] then
				return
			end
			local part = Instance.new("Part")

			part.Transparency = 1
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			local folder = Instance.new("Folder")

			folder.Name = "EclipseVFX Cache"
			folder.Archivable = false
			folder.Parent = workspace.Terrain
			local pool = getModule("EmitModule.obj.ObjectCache").new(part, folder, {
				size = 0,
				on_free = function(entry)
					entry.value.Transparency = 1
					entry.value:ClearAllChildren()
				end,
			})
			effect.init(pool)
			api.caches[name] = pool
			api.initialized[name] = effect
		end
		function api:emit(item)
			if item:GetAttribute("Transformed") then
				local engine = getModule("EmitVFX")
				engine:Activate()
				engine:EnableEmit(item)
				return
			end
			local scope = { depth = 0 }
			self.scopes[scope] = true
			local utility = getModule("EmitModule.mod.utility")
			local ok, err = pcall(function()
				if item:IsA("ParticleEmitter") then
					local value = clone(item)
					value.Enabled = false
					local parent = item.Parent
					if
						parent
						and parent:IsA("Attachment")
						and not parent:FindFirstAncestorWhichIsA("BasePart")
					then
						local sourceParent = parent
						local anchor = Instance.new("Attachment")

						anchor.Name = "EclipseVFX Anchor"
						anchor.Archivable = false
						anchor.CFrame = parent.WorldCFrame
						anchor.Parent = workspace.Terrain
						table.insert(scope, anchor)
						table.insert(
							scope,
							game:GetService("RunService").Heartbeat:Connect(function()
								if sourceParent.Parent then
									anchor.CFrame = sourceParent.WorldCFrame
								end
							end)
						)
						parent = anchor
					end
					value.Parent = parent
					table.insert(scope, value)
					getModule("EmitModule.effects.particle").emit(value, value, scope)
				elseif
					item:IsA("Model")
					and item:FindFirstChild("Start")
					and item:FindFirstChild("End")
				then
					local count = item:GetAttribute("EmitCount") or 1
					for _ = 1, math.clamp(math.floor(count), 0, 1000) do
						task.spawn(function()
							local childScope = { depth = 0 }
							self.scopes[childScope] = true
							local value = clone(item.Start)
							value.Parent = workspace.Terrain
							table.insert(childScope, value)
							local good, why = pcall(
								getModule("EmitModule.effects.mesh").emit,
								item,
								value,
								childScope,
								1
							)
							utility.cleanupScope(childScope)
							self.scopes[childScope] = nil
							if not good then
								warn(why)
							end
						end)
					end
				elseif item:HasTag("BezierParticle") then
					local part = item:FindFirstChildWhichIsA("BasePart")
					if not part then
						return
					end
					local effect = getModule("EmitModule.effects.bezier")
					initCache("bezier", effect)
					local value = clone(part)
					table.insert(scope, value)
					effect.emit(item, value, scope)
				elseif item:IsA("Beam") then
					local value = clone(item)
					table.insert(scope, value)
					value.Parent = workspace.Terrain
					getModule("EmitModule.effects.beam").emit(item, value, scope, 1)
				elseif item:IsA("Model") then
					getModule("EmitModule.effects.spin").emit(item, scope)
				elseif item:IsA("RayValue") then
					if item:HasTag("CameraShake") then
						local effect = getModule("EmitModule.effects.camera_shake")
						if not self.initialized.shake then
							effect.init()
							self.initialized.shake = effect
						end
						effect.emit(item, scope)
					elseif item.Parent then
						getModule("EmitModule.effects.tween_property").emit(item.Parent, item, scope)
					end
				elseif item:IsA("BasePart") then
					local attachment =
						utility.findFirstClassWithTag(item, "Attachment", "Shockwave")
					local names = {
						Rings = "shockwave_ring",
						Lines = "shockwave_line",
						Debris = "shockwave_debris",
					}
					local name = item.Parent and names[item.Parent.Name]
					if attachment and name then
						local effect = getModule("EmitModule.effects." .. name)
						initCache(name, effect)
						effect.emit(attachment, item, scope)
					end
				end
			end)
			utility.cleanupScope(scope)
			self.scopes[scope] = nil
			if not ok then
				error(err, 0)
			end
		end
		function api:active()
			local engine = cache.EmitVFX
			return next(self.scopes) ~= nil
				or next(pendingTasks) ~= nil
				or engine
					and (#engine.ActiveEmits > 0 or next(engine.ActiveLoops) ~= nil or next(
						engine.ActiveAnimates
					) ~= nil)
		end
		function api:Destroy()
			for _, thread in pendingTasks do
				if type(thread) == "thread" and thread ~= coroutine.running() then
					pcall(taskBase.cancel, thread)
				end
			end
			table.clear(pendingTasks)
			if cache.EmitVFX then
				local folder = cache.EmitVFX._CachedFolder
				cache.EmitVFX:Deactivate()
				if folder then
					folder:Destroy()
				end
			end
			if cache["EmitModule.mod.utility"] then
				for scope in self.scopes do
					cache["EmitModule.mod.utility"].cleanupScope(scope)
				end
			end
			for _, effect in self.initialized do
				if effect.deinit then
					effect.deinit()
				end
			end
			for _, pool in self.caches do
				pool:destroy()
			end
			table.clear(self.scopes)
			table.clear(self.caches)
		end
		return api
	end
end
