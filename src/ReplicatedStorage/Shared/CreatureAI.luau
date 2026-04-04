-- CreatureAI: Shared creature locomotion + animation module
-- Works on both client and server (uses task.spawn + task.wait, workspace:Raycast, model:PivotTo)

local CreatureAI = {}

-- Snappy paper-fold curve: sharp snap at zero-crossing, holds at extremes
local function foldCurve(raw: number): number
	return math.sign(raw) * math.abs(raw) ^ 0.6
end

-- Animation type enum (pre-classified at startup, avoids per-tick string:match)
local ANIM_WING_L = 1
local ANIM_WING_R = 2
local ANIM_TAIL = 3
local ANIM_JAW = 4
local ANIM_LEG = 5
local ANIM_SEG = 6
local ANIM_NONE = 0

-- Cached identity CFrame (avoid allocating CFrame.new() every tick)
local IDENTITY_CFRAME = CFrame.new()

-- Pre-classify a part name into animation type + parameters
local function classifyPart(name: string): (number, number, number)
	-- Returns: animType, idx/phase param 1, param 2
	if name:match("^wing_L") then
		return ANIM_WING_L, tonumber(name:match("%d+")) or 1, 0
	elseif name:match("^wing_R") then
		return ANIM_WING_R, tonumber(name:match("%d+")) or 1, 0
	elseif name:match("^tail_") then
		return ANIM_TAIL, tonumber(name:match("%d+")) or 1, 0
	elseif name:match("^jaw_") then
		return ANIM_JAW, 0, 0
	elseif name:match("^leg_") then
		local isLeft = name:match("_[FB]L_")
		local isFront = name:match("_F[LR]_")
		local phase = (if isLeft then 0 else math.pi) + (if isFront then 0 else math.pi / 2)
		return ANIM_LEG, phase, 0
	elseif name:match("^seg_") then
		return ANIM_SEG, tonumber(name:match("%d+")) or 1, 0
	end
	return ANIM_NONE, 0, 0
end

type AnimPartData = {
	part: BasePart,
	baseOffset: CFrame,
	animType: number,
	param1: number,
	param2: number,
}

-- Apply per-part creature animation using pre-classified types
local function applyCreatureAnimation(model: Model, animList: { AnimPartData }, t: number)
	local pivot = model:GetPivot()

	for _, data in animList do
		if not data.part.Parent then
			continue
		end

		local animOffset = IDENTITY_CFRAME

		if data.animType == ANIM_WING_L then
			local flapAngle = foldCurve(math.sin(t * 4.0 + data.param1 * 0.3)) * math.rad(35)
			animOffset = CFrame.Angles(0, 0, flapAngle)
		elseif data.animType == ANIM_WING_R then
			local flapAngle = foldCurve(math.sin(t * 4.0 + data.param1 * 0.3)) * math.rad(35)
			animOffset = CFrame.Angles(0, 0, -flapAngle)
		elseif data.animType == ANIM_TAIL then
			local swayAngle = math.sin(t * 3.0 + data.param1 * 0.6) * math.rad(20)
			animOffset = CFrame.Angles(0, swayAngle, 0)
		elseif data.animType == ANIM_JAW then
			local openAngle = (math.sin(t * 2.0) * 0.5 + 0.5) * math.rad(15)
			animOffset = CFrame.Angles(openAngle, 0, 0)
		elseif data.animType == ANIM_LEG then
			local walkAngle = math.sin(t * 5.0 + data.param1) * math.rad(25)
			animOffset = CFrame.Angles(walkAngle, 0, 0)
		elseif data.animType == ANIM_SEG then
			local yOffset = math.sin(t * 2.5 + data.param1 * 1.0) * 0.25
			animOffset = CFrame.new(0, yOffset, 0)
		end

		data.part.CFrame = pivot * data.baseOffset * animOffset
	end
end

-- Locomotion configs: speed, wanderRadius, hover height, behavior
local LOCOMOTION_CONFIG = {
	walk = { speed = 4, radius = 20, hoverHeight = 0, pauseMin = 1, pauseMax = 3 },
	slither = { speed = 2, radius = 12, hoverHeight = 0, pauseMin = 2, pauseMax = 5 },
	fly = { speed = 6, radius = 30, hoverHeight = 12, pauseMin = 0.5, pauseMax = 2 },
	float = { speed = 1.5, radius = 15, hoverHeight = 6, pauseMin = 3, pauseMax = 6 },
	hop = { speed = 5, radius = 18, hoverHeight = 0, pauseMin = 0.8, pauseMax = 2 },
	stationary = { speed = 0, radius = 0, hoverHeight = 0, pauseMin = 2, pauseMax = 4 },
}

-- Start creature AI. Returns a cleanup function that stops the loop.
-- @param model: The built creature Model (already parented to workspace)
-- @param modelData: The LLM response data (contains locomotion field)
-- @param spawnPosition: World position where the creature was placed
-- @param excludeFromRaycast: Instances to exclude from ground raycasts (e.g. {model, character})
-- @param tickRate: Optional override for task.wait interval (default 0.03)
function CreatureAI.Start(
	model: Model,
	modelData: { [string]: any },
	spawnPosition: Vector3,
	excludeFromRaycast: { Instance }?,
	tickRate: number?
): () -> ()
	local dt = tickRate or 0.03

	-- Compute pivot offset from bottom for flush ground placement
	local cf, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)

	-- Pre-classify ALL parts by animation type at startup (avoids per-tick string:match)
	local animList: { AnimPartData } = {}
	local currentPivot = model:GetPivot()
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			local animType, param1, param2 = classifyPart(child.Name)
			table.insert(animList, {
				part = child,
				baseOffset = currentPivot:ToObjectSpace(child.CFrame),
				animType = animType,
				param1 = param1,
				param2 = param2,
			})
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
	local RAYCAST_INTERVAL = 3 -- raycast every Nth call

	local function raycastGround(x: number, z: number): number
		_groundRaycastCounter += 1
		if _groundRaycastCounter % RAYCAST_INTERVAL == 0 then
			-- Cast from well above terrain to handle any elevation
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
				applyCreatureAnimation(model, animList, tick())
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

				-- Slither: curved sinuous path
				local slitherPhase = math.random() * math.pi * 2

				-- Hop: pre-compute hop count
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
						-- Sinuous S-curve perpendicular to travel direction
						local perpX = -(targetZ - startPos.Z)
						local perpZ = targetX - startPos.X
						local perpLen = math.sqrt(perpX * perpX + perpZ * perpZ)
						if perpLen > 0.01 then
							perpX, perpZ = perpX / perpLen, perpZ / perpLen
						end
						local sway = math.sin(t * math.pi * 4 + slitherPhase) * 1.2
						baseX = baseX + perpX * sway
						baseZ = baseZ + perpZ * sway
						-- Gentle yaw to follow the S-curve (clamped to avoid spinning)
						local yawOffset = math.cos(t * math.pi * 4 + slitherPhase) * math.rad(20)
						finalRot = lookRot * CFrame.Angles(0, yawOffset, 0)
						finalY = baseGroundY + pivotAboveBottom
					elseif locomotion == "fly" then
						-- Swooping flight: sine wave altitude + bank into turns
						local swoopY = math.sin(t * math.pi * 2) * 4
						finalY = baseGroundY + pivotAboveBottom + locoConfig.hoverHeight + swoopY
						-- Clamp: never go below terrain surface + 2 studs
						finalY = math.max(finalY, baseGroundY + pivotAboveBottom + 2)
						-- Bank slightly into the swoop
						local bankAngle = math.cos(t * math.pi * 2) * math.rad(15)
						finalRot = lookRot * CFrame.Angles(0, 0, bankAngle)
					elseif locomotion == "float" then
						-- Gentle hover with vertical bob
						local bobY = math.sin(tick() * 1.5) * 1.0
						finalY = baseGroundY + pivotAboveBottom + locoConfig.hoverHeight + bobY
						-- Clamp: never go below terrain surface + 2 studs
						finalY = math.max(finalY, baseGroundY + pivotAboveBottom + 2)
						-- Slow gentle yaw drift
						local driftYaw = math.sin(tick() * 0.5) * math.rad(10)
						finalRot = lookRot * CFrame.Angles(0, driftYaw, 0)
					elseif locomotion == "hop" then
						-- Parabolic arc per hop
						local hopIndex = math.floor((step - 1) / hopStepsPerHop)
						local hopT = ((step - 1) % hopStepsPerHop) / hopStepsPerHop
						local arcHeight = math.sin(hopT * math.pi) * 2.5
						finalY = baseGroundY + pivotAboveBottom + arcHeight
						-- Slight forward tilt during hop
						local tiltAngle = math.sin(hopT * math.pi) * math.rad(-20)
						finalRot = lookRot * CFrame.Angles(tiltAngle, 0, 0)
					else -- walk (default)
						finalY = baseGroundY + pivotAboveBottom
					end

					model:PivotTo(CFrame.new(baseX, finalY, baseZ) * finalRot)
					applyCreatureAnimation(model, animList, tick())
					task.wait(dt)
				end
			end

			-- Pause at destination with animation
			local pauseTime = locoConfig.pauseMin + math.random() * (locoConfig.pauseMax - locoConfig.pauseMin)

			-- Float/fly: keep bobbing during pause
			if locomotion == "float" or locomotion == "fly" then
				local pauseStart = tick()
				while isAlive() and (tick() - pauseStart) < pauseTime do
					local currentPos = model:GetPivot().Position
					local curGroundY = raycastGround(currentPos.X, currentPos.Z)
					local bobY = math.sin(tick() * 1.5) * 1.0
					local targetY = curGroundY + pivotAboveBottom + locoConfig.hoverHeight + bobY
					-- Clamp: never go below terrain surface + 2 studs
					targetY = math.max(targetY, curGroundY + pivotAboveBottom + 2)
					local currentRot = model:GetPivot() - model:GetPivot().Position
					model:PivotTo(CFrame.new(currentPos.X, targetY, currentPos.Z) * currentRot)
					applyCreatureAnimation(model, animList, tick())
					task.wait(dt)
				end
			else
				local pauseStart = tick()
				while isAlive() and (tick() - pauseStart) < pauseTime do
					applyCreatureAnimation(model, animList, tick())
					task.wait(dt)
				end
			end
		end
	end)

	-- Return cleanup function
	return function()
		stopped = true
	end
end

return CreatureAI
