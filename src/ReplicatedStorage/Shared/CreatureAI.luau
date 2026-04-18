-- CreatureAI: Shared creature locomotion + animation module
-- Works on both client and server (uses task.spawn + task.wait, workspace:Raycast, model:PivotTo)
--
-- Animation is driven by part name prefixes (pre-classified at startup):
--   seg_*           body segments (body wiggle / slither wave)
--   wing_L_* / R_*  wings (flap from shoulder, progressive bending)
--   tail_*          tail segments (phase-offset sway)
--   jaw_*           jaw (open/close)
--   leg_FL/FR/BL/BR legs (pivot-based walk cycle, diagonal tetrapod gait)
--   foot/paw/claw/hoof  extremities (follow parent leg)
--   arm_*           arms (swing like front limbs)
--   fist/hand_*     hands (follow parent arm)
--   knee_*          knee joints (translate with parent upper leg)
--   tentacle/tendril  trailing tendrils (drift + twist)
--   puff_*          breathing/pulsing parts (size oscillation)

local CreatureAI = {}

local function foldCurve(raw: number): number
	return math.sign(raw) * math.abs(raw) ^ 0.6
end

-- Animation type enum
local ANIM_NONE = 0
local ANIM_WING_L = 1
local ANIM_WING_R = 2
local ANIM_TAIL = 3
local ANIM_JAW = 4
local ANIM_LEG = 5
local ANIM_SEG = 6
local ANIM_TENTACLE = 7
local ANIM_PUFF = 8
local ANIM_PUFF_EYE = 9

local IDENTITY_CFRAME = CFrame.new()

local function classifyPart(name: string): (number, number, number)
	local lower = name:lower()
	if lower:match("^wing_l") then
		return ANIM_WING_L, tonumber(lower:match("%d+")) or 1, 0
	elseif lower:match("^wing_r") then
		return ANIM_WING_R, tonumber(lower:match("%d+")) or 1, 0
	elseif lower:match("^tail") then
		return ANIM_TAIL, tonumber(lower:match("%d+")) or 1, 0
	elseif lower:match("^jaw") then
		return ANIM_JAW, 0, 0
	elseif lower:match("^leg") or lower:match("^horse_leg") then
		local isLeft = lower:match("_[fb]l") ~= nil
		local isFront = lower:match("_f[lr]") ~= nil
		local phase = if isLeft == isFront then 0 else math.pi
		local segNum = tonumber(lower:match("_(%d+)$")) or 1
		return ANIM_LEG, phase, segNum
	elseif lower:match("^foot") or lower:match("^paw") or lower:match("^claw") or lower:match("^hoof") then
		local posSuffix = lower:match("_([fb][lr])") or lower:match("_([lr])")
		local isLeft = if posSuffix then posSuffix:match("l") ~= nil else true
		local isFront = if posSuffix then posSuffix:match("f") ~= nil else true
		if posSuffix and not posSuffix:match("[fb]") then
			isFront = false
		end
		local phase = if isLeft == isFront then 0 else math.pi
		return ANIM_LEG, phase, 0
	elseif lower:match("^arm") then
		local isLeft = lower:match("_[fb]?l") ~= nil
		local phase = if isLeft then 0 else math.pi
		return ANIM_LEG, phase, 1
	elseif lower:match("^fist") or lower:match("^hand") then
		local posSuffix = lower:match("_([fb][lr])") or lower:match("_([lr])")
		local isLeft = if posSuffix then posSuffix:match("l") ~= nil else true
		local isFront = if posSuffix then posSuffix:match("f") ~= nil else true
		if posSuffix and not posSuffix:match("[fb]") then
			isFront = true
		end
		local phase = if isLeft == isFront then 0 else math.pi
		return ANIM_LEG, phase, 0
	elseif lower:match("^puff") then
		return ANIM_PUFF, tonumber(lower:match("%d+")) or 1, 0
	elseif lower:match("^seg") then
		return ANIM_SEG, tonumber(lower:match("%d+")) or 1, 0
	elseif lower:match("^tentacle") or lower:match("^tendril") then
		return ANIM_TENTACLE, tonumber(lower:match("%d+")) or 1, 0
	end
	return ANIM_NONE, 0, 0
end

type AnimPartData = {
	part: BasePart,
	baseOffset: CFrame,
	baseSize: Vector3,
	animType: number,
	param1: number,
	param2: number,
	legTopOffset: Vector3,
	parentPivotPos: Vector3?,
	parentKneeRestPos: Vector3?,
	legHorizontal: boolean,
	wingRootPos: Vector3?,
	wingSegIndex: number,
}

local function applyCreatureAnimation(model: Model, animList: { AnimPartData }, t: number, locomotion: string)
	local pivot = model:GetPivot()

	for _, data in animList do
		if not data.part.Parent then
			continue
		end

		local animOffset = IDENTITY_CFRAME

		if data.animType == ANIM_WING_L then
			local rootPos = data.wingRootPos
			local baseFlapAngle = foldCurve(math.sin(t * 6.0)) * math.rad(40)
			local segFlexAngle = math.sin(t * 6.0 - data.wingSegIndex * 0.5) * math.rad(15) * data.wingSegIndex
			local totalAngle = baseFlapAngle + segFlexAngle
			if rootPos then
				local swing = CFrame.new(rootPos) * CFrame.Angles(0, 0, totalAngle) * CFrame.new(-rootPos)
				data.part.CFrame = pivot * swing * data.baseOffset
			else
				data.part.CFrame = pivot * data.baseOffset * CFrame.Angles(0, 0, totalAngle)
			end
			continue
		elseif data.animType == ANIM_WING_R then
			local rootPos = data.wingRootPos
			local baseFlapAngle = foldCurve(math.sin(t * 6.0)) * math.rad(40)
			local segFlexAngle = math.sin(t * 6.0 - data.wingSegIndex * 0.5) * math.rad(15) * data.wingSegIndex
			local totalAngle = -(baseFlapAngle + segFlexAngle)
			if rootPos then
				local swing = CFrame.new(rootPos) * CFrame.Angles(0, 0, totalAngle) * CFrame.new(-rootPos)
				data.part.CFrame = pivot * swing * data.baseOffset
			else
				data.part.CFrame = pivot * data.baseOffset * CFrame.Angles(0, 0, totalAngle)
			end
			continue
		elseif data.animType == ANIM_TAIL then
			local ampScale = math.clamp(data.param1 * 0.15, 0.6, 1.5)
			local swayAngle = math.sin(t * 4.0 + data.param1 * 0.7) * math.rad(28) * ampScale
			animOffset = CFrame.Angles(0, swayAngle, 0)
		elseif data.animType == ANIM_JAW then
			local openAngle = (math.sin(t * 2.5) * 0.5 + 0.5) * math.rad(18)
			animOffset = CFrame.Angles(openAngle, 0, 0)
		elseif data.animType == ANIM_LEG then
			local topPos = data.parentPivotPos or (data.baseOffset.Position + data.legTopOffset)
			local legAngle: number
			if locomotion == "hop" then
				local HOP_PERIOD = 1.2
				local phase = (t % HOP_PERIOD) / HOP_PERIOD
				if phase < 0.6 then
					legAngle = math.sin(phase / 0.6 * math.pi) * math.rad(30)
				else
					local groundPhase = (phase - 0.6) / 0.4
					legAngle = -math.sin(groundPhase * math.pi) * math.rad(10)
				end
			else
				legAngle = math.sin(t * 6.0 + data.param1) * math.rad(25)
			end
			if data.parentKneeRestPos then
				local hipPos = data.parentPivotPos :: Vector3
				local kneeRest = data.parentKneeRestPos
				local parentSwing = CFrame.new(hipPos) * CFrame.Angles(0, legAngle, 0) * CFrame.new(-hipPos)
				local kneeDelta = (parentSwing * CFrame.new(kneeRest)).Position - kneeRest
				data.part.CFrame = pivot * CFrame.new(kneeDelta) * data.baseOffset
			else
				local swingRot = if data.legHorizontal
					then CFrame.Angles(0, legAngle, 0)
					else CFrame.Angles(legAngle, 0, 0)
				local swing = CFrame.new(topPos) * swingRot * CFrame.new(-topPos)
				data.part.CFrame = pivot * swing * data.baseOffset
			end
			continue
		elseif data.animType == ANIM_SEG then
			if locomotion == "slither" then
				local yOffset = math.sin(t * 4.0 + data.param1 * 1.0) * 0.3
				local swayAngle = math.sin(t * 4.0 + data.param1 * 0.8) * math.rad(12)
				animOffset = CFrame.new(0, yOffset, 0) * CFrame.Angles(0, swayAngle, 0)
			else
				local yawWiggle = math.sin(t * 4 + data.param1 * 0.8) * math.rad(6)
					+ math.sin(t * 2 + data.param1 * 1.4) * math.rad(3)
				local pitchBob = math.sin(t * 3 + data.param1 * 0.5) * math.rad(4)
				animOffset = CFrame.Angles(pitchBob, yawWiggle, 0)
			end
		elseif data.animType == ANIM_TENTACLE then
			local sway = math.sin(t * 2 + data.param1 * 0.7) * math.rad(18)
			local twist = math.cos(t * 1.5 + data.param1 * 0.5) * math.rad(12)
			animOffset = CFrame.Angles(twist, 0, sway)
		elseif data.animType == ANIM_PUFF then
			local breathCycle = math.sin(t * 2 + data.param1 * 0.3)
			local scale = 1.0 + breathCycle * 0.15
			data.part.Size = data.baseSize * scale
			animOffset = IDENTITY_CFRAME
		elseif data.animType == ANIM_PUFF_EYE then
			local breathCycle = math.sin(t * 2)
			local inwardPull = breathCycle * 0.3
			local dir = data.baseOffset.Position
			local dirLen = dir.Magnitude
			if dirLen > 0.01 then
				animOffset = CFrame.new(dir.Unit * -inwardPull)
			end
		end

		data.part.CFrame = pivot * data.baseOffset * animOffset
	end
end

-- Locomotion configs
local LOCOMOTION_CONFIG = {
	walk = { speed = 4, radius = 20, hoverHeight = 0, pauseMin = 1, pauseMax = 3 },
	slither = { speed = 2, radius = 12, hoverHeight = 0, pauseMin = 2, pauseMax = 5 },
	fly = { speed = 6, radius = 30, hoverHeight = 12, pauseMin = 0.5, pauseMax = 2 },
	float = { speed = 1.5, radius = 15, hoverHeight = 6, pauseMin = 3, pauseMax = 6 },
	hop = { speed = 5, radius = 18, hoverHeight = 0, pauseMin = 0.8, pauseMax = 2 },
	stationary = { speed = 0, radius = 0, hoverHeight = 0, pauseMin = 2, pauseMax = 4 },
}

function CreatureAI.Start(
	model: Model,
	modelData: { [string]: any },
	spawnPosition: Vector3,
	excludeFromRaycast: { Instance }?,
	tickRate: number?
): () -> ()
	local dt = tickRate or 0.03

	-- Ensure all parts are anchored for pure-CFrame locomotion
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
		end
	end

	local pivotCF = model:GetPivot()

	-- Insert invisible anchor as PrimaryPart so the model pivot stays stable
	-- when per-part animation moves body segments (e.g. seg_1 in slither).
	if not model:FindFirstChild("_LocomotionAnchor") then
		local anchor = Instance.new("Part")
		anchor.Name = "_LocomotionAnchor"
		anchor.Size = Vector3.new(0.05, 0.05, 0.05)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Massless = true
		anchor.CastShadow = false
		anchor.CFrame = pivotCF
		anchor.Parent = model
		model.PrimaryPart = anchor
	end

	local cf, size = model:GetBoundingBox()
	local pivotAboveBottom = pivotCF.Position.Y - (cf.Position.Y - size.Y / 2)

	-- Pre-classify ALL parts by animation type at startup
	local animList: { AnimPartData } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "_LocomotionAnchor" then
			local animType, param1, param2 = classifyPart(child.Name)
			local baseOffset = pivotCF:ToObjectSpace(child.CFrame)

			local legTopOffset = Vector3.zero
			local legHorizontal = false
			if animType == ANIM_LEG then
				local halfLen = child.Size.X * 0.5
				local longAxisModel = baseOffset:VectorToWorldSpace(Vector3.xAxis)
				if math.abs(longAxisModel.Y) > 0.5 then
					local dir = if longAxisModel.Y >= 0 then longAxisModel else -longAxisModel
					legTopOffset = dir * halfLen
				else
					legHorizontal = true
					local pos = baseOffset.Position
					local dot = pos.X * longAxisModel.X + pos.Y * longAxisModel.Y + pos.Z * longAxisModel.Z
					local inwardDir = if dot >= 0 then -longAxisModel else longAxisModel
					legTopOffset = inwardDir * halfLen
				end
			end

			table.insert(animList, {
				part = child,
				baseOffset = baseOffset,
				baseSize = child.Size,
				animType = animType,
				param1 = param1,
				param2 = param2,
				legTopOffset = legTopOffset,
				parentPivotPos = nil,
				parentKneeRestPos = nil,
				legHorizontal = legHorizontal,
				wingRootPos = nil,
				wingSegIndex = 0,
			})
		end
	end

	-- Link multi-segment legs (upper odd → lower even)
	local upperLegLookup: { [string]: AnimPartData } = {}
	for _, data in animList do
		if data.animType == ANIM_LEG then
			local lower = data.part.Name:lower()
			local prefix = lower:match("^(.+)_%d+$")
			if prefix and lower:match("^leg") and data.param2 % 2 == 1 then
				local pairIdx = math.ceil(data.param2 / 2)
				upperLegLookup[prefix .. "_pair" .. pairIdx] = data
			end
		end
	end
	for _, data in animList do
		if data.animType == ANIM_LEG and data.param2 % 2 == 0 then
			local lower = data.part.Name:lower()
			local prefix = lower:match("^(.+)_%d+$")
			if prefix and lower:match("^leg") then
				local pairIdx = data.param2 / 2
				local parent = upperLegLookup[prefix .. "_pair" .. pairIdx]
				if parent then
					data.parentPivotPos = parent.baseOffset.Position + parent.legTopOffset
					if parent.legHorizontal then
						data.parentKneeRestPos = parent.baseOffset.Position - parent.legTopOffset
					end
				end
			end
		end
	end

	-- Link knee joints to parent upper legs
	for _, data in animList do
		if data.animType == ANIM_NONE then
			local lower = data.part.Name:lower()
			local posPrefix = lower:match("^knee_([fb][lr])_")
			if posPrefix then
				local kneePairNum = tonumber(lower:match("_(%d+)$")) or 1
				local parentKey = "leg_" .. posPrefix .. "_pair" .. kneePairNum
				local parent = upperLegLookup[parentKey]
				if parent and parent.legHorizontal then
					data.animType = ANIM_LEG
					data.param1 = parent.param1
					data.parentPivotPos = parent.baseOffset.Position + parent.legTopOffset
					data.parentKneeRestPos = parent.baseOffset.Position - parent.legTopOffset
				end
			end
		end
	end

	-- Link extremities (feet/paws/claws/hoofs/fists/hands) to parent legs
	local legInfoByPos: { [string]: { pivot: Vector3, horizontal: boolean } } = {}
	for _, data in animList do
		if data.animType == ANIM_LEG and data.part.Name:lower():match("^leg") and data.param2 == 1 then
			local lower = data.part.Name:lower()
			local posSuffix = lower:match("_([fb][lr])_")
			if posSuffix then
				legInfoByPos[posSuffix] = {
					pivot = data.baseOffset.Position + data.legTopOffset,
					horizontal = data.legHorizontal,
				}
			end
		end
	end
	local armInfoByPos: { [string]: { pivot: Vector3, horizontal: boolean } } = {}
	for _, data in animList do
		if data.animType == ANIM_LEG and data.part.Name:lower():match("^arm") then
			local lower = data.part.Name:lower()
			local side = lower:match("_([lr])") or lower:match("_[fb]([lr])")
			if side then
				armInfoByPos[side] = {
					pivot = data.baseOffset.Position + data.legTopOffset,
					horizontal = data.legHorizontal,
				}
			end
		end
	end
	for _, data in animList do
		if
			data.animType == ANIM_LEG
			and not data.part.Name:lower():match("^leg")
			and not data.part.Name:lower():match("^arm")
			and not data.part.Name:lower():match("^knee")
		then
			local lower = data.part.Name:lower()
			local posSuffix = lower:match("_([fb][lr])") or lower:match("_([lr])")
			if posSuffix then
				local isHand = lower:match("^fist") or lower:match("^hand")
				local info = nil
				if isHand then
					local side = posSuffix:match("[lr]")
					info = armInfoByPos[side or ""]
				end
				if not info then
					info = legInfoByPos[posSuffix] or legInfoByPos["f" .. posSuffix] or legInfoByPos["b" .. posSuffix]
				end
				if info then
					data.parentPivotPos = info.pivot
					data.legHorizontal = info.horizontal
				end
			end
		end
	end

	-- Link wing segments to innermost root on same side
	local wingRootL: Vector3? = nil
	local wingRootR: Vector3? = nil
	local wingMinL, wingMinR = math.huge, math.huge
	for _, data in animList do
		if data.animType == ANIM_WING_L and data.param1 < wingMinL then
			wingMinL = data.param1
			wingRootL = data.baseOffset.Position
		elseif data.animType == ANIM_WING_R and data.param1 < wingMinR then
			wingMinR = data.param1
			wingRootR = data.baseOffset.Position
		end
	end
	if wingRootL or wingRootR then
		for _, data in animList do
			if data.animType == ANIM_WING_L and wingRootL then
				data.wingRootPos = wingRootL
				data.wingSegIndex = data.param1 - wingMinL
			elseif data.animType == ANIM_WING_R and wingRootR then
				data.wingRootPos = wingRootR
				data.wingSegIndex = data.param1 - wingMinR
			end
		end
	end

	-- Detect puff eyes: if any ANIM_PUFF parts exist, reclassify eye parts
	local hasPuff = false
	for _, data in animList do
		if data.animType == ANIM_PUFF then
			hasPuff = true
			break
		end
	end
	if hasPuff then
		for _, data in animList do
			if data.animType == ANIM_NONE and data.part.Name:lower():match("eye") then
				data.animType = ANIM_PUFF_EYE
			end
		end
	end

	-- Locomotion type
	local locomotion = modelData.locomotion or "walk"
	local locoConfig = LOCOMOTION_CONFIG[locomotion] or LOCOMOTION_CONFIG.walk

	-- Wandering state
	local spawnPos = spawnPosition
	local stopped = false

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = excludeFromRaycast or { model }

	model.Destroying:Connect(function()
		stopped = true
	end)

	local _cachedGroundY = spawnPos.Y
	local _groundRaycastCounter = 0
	local RAYCAST_INTERVAL = 3

	local function raycastGround(x: number, z: number): number
		_groundRaycastCounter += 1
		if _groundRaycastCounter % RAYCAST_INTERVAL == 0 then
			local originY = math.max(spawnPos.Y + 100, _cachedGroundY + 100)
			local result = workspace:Raycast(Vector3.new(x, originY, z), Vector3.new(0, -300, 0), rayParams)
			_cachedGroundY = if result then result.Position.Y else spawnPos.Y
		end
		return _cachedGroundY
	end

	local function isAlive(): boolean
		return not stopped and model ~= nil and model.Parent ~= nil and model.PrimaryPart ~= nil
	end

	-- Stationary: just animate in place
	if locomotion == "stationary" then
		task.spawn(function()
			while isAlive() do
				applyCreatureAnimation(model, animList, tick(), locomotion)
				task.wait(dt)
			end
		end)
		return function()
			stopped = true
		end
	end

	task.spawn(function()
		while isAlive() do
			-- Pick a random target within wander radius
			local angle = math.random() * math.pi * 2
			local dist = math.random() * locoConfig.radius
			local targetX = spawnPos.X + math.cos(angle) * dist
			local targetZ = spawnPos.Z + math.sin(angle) * dist
			local groundY = raycastGround(targetX, targetZ)

			local startPos = model.PrimaryPart.Position
			local distance = (Vector3.new(targetX, 0, targetZ) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude

			if distance > 1 then
				local lookCF = CFrame.lookAt(startPos, Vector3.new(targetX, startPos.Y, targetZ))
				-- Flip 180°: animation offsets are relative (ToObjectSpace cancels OrigamiBuilder flip),
				-- so in local space the face is still +Z. CFrame.lookAt points -Z at target → flip needed.
				local lookRot = (lookCF - lookCF.Position) * CFrame.Angles(0, math.pi, 0)
				local steps = math.max(1, math.floor(distance / (locoConfig.speed * dt)))

				local slitherPhase = math.random() * math.pi * 2

				local hopCount = 0
				local hopStepsPerHop = 0
				if locomotion == "hop" then
					hopCount = math.max(1, math.floor(distance / 3))
					hopStepsPerHop = math.max(1, math.floor(steps / hopCount))
				end

				for step = 1, steps do
					if not isAlive() then
						break
					end

					local t = step / steps
					local baseX = startPos.X + (targetX - startPos.X) * t
					local baseZ = startPos.Z + (targetZ - startPos.Z) * t
					local baseGroundY = raycastGround(baseX, baseZ)
					local finalY = baseGroundY + pivotAboveBottom
					local finalRot = lookRot

					if locomotion == "slither" then
						local perpX = -(targetZ - startPos.Z)
						local perpZ = targetX - startPos.X
						local perpLen = math.sqrt(perpX * perpX + perpZ * perpZ)
						if perpLen > 0.01 then
							perpX, perpZ = perpX / perpLen, perpZ / perpLen
						end
						local sway = math.sin(t * math.pi * 4 + slitherPhase) * 1.2
						baseX = baseX + perpX * sway
						baseZ = baseZ + perpZ * sway
						local yawOffset = math.cos(t * math.pi * 4 + slitherPhase) * math.rad(20)
						finalRot = lookRot * CFrame.Angles(0, yawOffset, 0)
						finalY = baseGroundY + pivotAboveBottom
					elseif locomotion == "fly" then
						local swoopY = math.sin(t * math.pi * 2) * 4
						finalY = baseGroundY + pivotAboveBottom + locoConfig.hoverHeight + swoopY
						finalY = math.max(finalY, baseGroundY + pivotAboveBottom + 2)
						local bankAngle = math.cos(t * math.pi * 2) * math.rad(15)
						finalRot = lookRot * CFrame.Angles(0, 0, bankAngle)
					elseif locomotion == "float" then
						local bobY = math.sin(tick() * 1.5) * 1.0
						finalY = baseGroundY + pivotAboveBottom + locoConfig.hoverHeight + bobY
						finalY = math.max(finalY, baseGroundY + pivotAboveBottom + 2)
						local driftYaw = math.sin(tick() * 0.5) * math.rad(10)
						finalRot = lookRot * CFrame.Angles(0, driftYaw, 0)
					elseif locomotion == "hop" then
						local hopT = ((step - 1) % hopStepsPerHop) / hopStepsPerHop
						local arcHeight = math.sin(hopT * math.pi) * 2.5
						finalY = baseGroundY + pivotAboveBottom + arcHeight
						local tiltAngle = math.sin(hopT * math.pi) * math.rad(-20)
						finalRot = lookRot * CFrame.Angles(tiltAngle, 0, 0)
					else -- walk
						finalY = baseGroundY + pivotAboveBottom
					end

					model:PivotTo(CFrame.new(baseX, finalY, baseZ) * finalRot)
					applyCreatureAnimation(model, animList, tick(), locomotion)
					task.wait(dt)
				end
			end

			-- Pause at destination with animation
			local pauseTime = locoConfig.pauseMin + math.random() * (locoConfig.pauseMax - locoConfig.pauseMin)

			if locomotion == "float" or locomotion == "fly" then
				local pauseStart = tick()
				while isAlive() and (tick() - pauseStart) < pauseTime do
					local currentPos = model:GetPivot().Position
					local curGroundY = raycastGround(currentPos.X, currentPos.Z)
					local bobY = math.sin(tick() * 1.5) * 1.0
					local targetY = curGroundY + pivotAboveBottom + locoConfig.hoverHeight + bobY
					targetY = math.max(targetY, curGroundY + pivotAboveBottom + 2)
					local currentRot = model:GetPivot() - model:GetPivot().Position
					model:PivotTo(CFrame.new(currentPos.X, targetY, currentPos.Z) * currentRot)
					applyCreatureAnimation(model, animList, tick(), locomotion)
					task.wait(dt)
				end
			else
				local pauseStart = tick()
				while isAlive() and (tick() - pauseStart) < pauseTime do
					applyCreatureAnimation(model, animList, tick(), locomotion)
					task.wait(dt)
				end
			end
		end
	end)

	return function()
		stopped = true
	end
end

return CreatureAI
