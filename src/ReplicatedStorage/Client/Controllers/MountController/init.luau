--[[
	MountController — client-side creature mount/ride system.
	Builds creature model, welds to server VehicleSeat, runs per-locomotion
	drive loop (Heartbeat) and creature animation loop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Knit = require(ReplicatedStorage.Packages.Knit)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local CreatureAI = require(ReplicatedStorage.Shared.CreatureAI)
local MountConfig = require(ReplicatedStorage.Shared.MountConfig)

local Player = Players.LocalPlayer

local MountController = Knit.CreateController({
	Name = "MountController",
})

-- Active mount state
local _mounted = false
local _mountModel: Model? = nil
local _mountSeat: VehicleSeat? = nil
local _mountCreatureId: string? = nil
local _mountLocomotion: string? = nil
local _driveConnection: RBXScriptConnection? = nil
local _dismountConnection: RBXScriptConnection? = nil
local _animator: { apply: (number) -> () }? = nil

-- Lazy service reference
local MountService

-- ═══════════════════════════════════════════════════════════════════════════════
-- INPUT HELPERS (same pattern as CreatorController vehicle drive)
-- ═══════════════════════════════════════════════════════════════════════════════

local HAS_GAMEPAD = UserInputService.GamepadEnabled

local function getGamepadAxis(axisKeyCode: Enum.KeyCode): (number, number)
	if not HAS_GAMEPAD then
		return 0, 0
	end
	local ok, state = pcall(function()
		return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	end)
	if not ok or not state then
		return 0, 0
	end
	for _, input in ipairs(state) do
		if input.KeyCode == axisKeyCode then
			local x = if math.abs(input.Position.X) > 0.15 then input.Position.X else 0
			local y = if math.abs(input.Position.Y) > 0.15 then input.Position.Y else 0
			return x, y
		end
	end
	return 0, 0
end

local function isGamepadDown(buttonKeyCode: Enum.KeyCode): boolean
	if not HAS_GAMEPAD then
		return false
	end
	local ok, pressed = pcall(function()
		return UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, buttonKeyCode)
	end)
	return ok and pressed == true
end

local function getThrottle(): number
	local forward = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		forward += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		forward -= 1
	end
	local _, gpY = getGamepadAxis(Enum.KeyCode.Thumbstick1)
	forward += gpY
	return math.clamp(forward, -1, 1)
end

local function getSteer(): number
	local steer = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		steer -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		steer += 1
	end
	local gpX, _ = getGamepadAxis(Enum.KeyCode.Thumbstick1)
	steer += gpX
	return math.clamp(steer, -1, 1)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- INTERNAL: cleanup
-- ═══════════════════════════════════════════════════════════════════════════════

local function cleanup()
	if _driveConnection then
		_driveConnection:Disconnect()
		_driveConnection = nil
	end
	if _dismountConnection then
		_dismountConnection:Disconnect()
		_dismountConnection = nil
	end
	_mounted = false
	_mountSeat = nil
	_mountCreatureId = nil
	_mountLocomotion = nil
	_animator = nil
	-- Model is NOT destroyed here — caller decides (keep in world or destroy)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- DRIVE LOOP — per-locomotion physics
-- ═══════════════════════════════════════════════════════════════════════════════

local function startDriveLoop(seat: VehicleSeat, locomotion: string, spdStat: number)
	local locoConfig = MountConfig.get(locomotion)
	if not locoConfig then
		return
	end

	local spdMult = MountConfig.speedMultiplier(spdStat)
	local maxSpeed = locoConfig.maxSpeed * spdMult
	local turnSpeed = locoConfig.turnSpeed
	local accel = locoConfig.accel
	local coast = locoConfig.coast
	local BRAKE_RATE = 0.18
	local TURN_DAMPENING = 0.5
	local MIN_SPEED_TO_TURN = 0.5

	local _, initialYaw, _ = seat.CFrame:ToEulerAnglesYXZ()
	local currentSpeed = 0
	local currentYaw = initialYaw
	local currentAltitudeVel = 0

	-- Jump state (hop / walk / slither)
	local jumpCooldown = 0

	-- Float bob phase
	local bobPhase = 0

	-- Raycast params (for grounded checks, wall detection, hover)
	local character = Player.Character
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { seat, character, _mountModel }

	_driveConnection = RunService.Heartbeat:Connect(function(dt: number)
		if not seat or not seat.Parent then
			cleanup()
			return
		end

		local isSeated = seat.Occupant and seat.Occupant.Parent == character
		if not isSeated then
			currentSpeed = 0
			currentAltitudeVel = 0
			return
		end

		local throttle = getThrottle()
		local steer = getSteer()
		local spaceHeld = UserInputService:IsKeyDown(Enum.KeyCode.Space) or isGamepadDown(Enum.KeyCode.ButtonA)
		local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			or isGamepadDown(Enum.KeyCode.ButtonB)

		-- ── Acceleration ──
		local targetSpeed = throttle * maxSpeed
		local rate
		if throttle == 0 then
			rate = coast
		elseif math.sign(targetSpeed) ~= math.sign(currentSpeed) and math.abs(currentSpeed) > 1 then
			rate = BRAKE_RATE
		else
			rate = accel
		end
		currentSpeed += (targetSpeed - currentSpeed) * rate

		-- ── Steering ──
		if math.abs(currentSpeed) > MIN_SPEED_TO_TURN then
			local speedFraction = math.abs(currentSpeed) / maxSpeed
			local turnMult = 1 - speedFraction * TURN_DAMPENING
			currentYaw -= steer * turnSpeed * turnMult * dt
		end

		-- ── Y-axis velocity (per-locomotion) ──
		local yVel = locoConfig.downforce
		local bankZ = 0 -- visual roll for flying/banking

		if locoConfig.canFly and locomotion == "fly" then
			-- Full 3D flight: Space=up, Shift=down
			local altInput = (if spaceHeld then 1 else 0) + (if shiftHeld then -1 else 0)
			local FLY_SPEED = 30 * spdMult
			local FLY_ACCEL = 0.12
			local FLY_HOVER_DAMPING = 0.05
			local targetAltVel = altInput * FLY_SPEED
			if altInput == 0 then
				currentAltitudeVel *= (1 - FLY_HOVER_DAMPING)
			else
				currentAltitudeVel += (targetAltVel - currentAltitudeVel) * FLY_ACCEL
			end
			yVel = currentAltitudeVel
			-- Visual banking on turns
			bankZ = -steer * math.rad(20) * math.clamp(math.abs(currentSpeed) / maxSpeed, 0, 1)
		elseif locoConfig.canFly and locomotion == "float" then
			-- Gentle altitude: Space=up, Shift=down (slow)
			local altInput = (if spaceHeld then 1 else 0) + (if shiftHeld then -1 else 0)
			local FLOAT_SPEED = 10 * spdMult
			local FLOAT_ACCEL = 0.06
			local FLOAT_HOVER_DAMPING = 0.03
			local targetAltVel = altInput * FLOAT_SPEED
			if altInput == 0 then
				currentAltitudeVel *= (1 - FLOAT_HOVER_DAMPING)
			else
				currentAltitudeVel += (targetAltVel - currentAltitudeVel) * FLOAT_ACCEL
			end
			-- Sinusoidal bob overlay
			bobPhase += dt * 1.5
			local bobOffset = math.sin(bobPhase) * locoConfig.bobAmplitude
			yVel = currentAltitudeVel + bobOffset

			-- Terrain hover: maintain minimum height above ground
			local pos = seat.CFrame.Position
			local groundRay = workspace:Raycast(pos, Vector3.new(0, -50, 0), rayParams)
			if groundRay then
				local heightAboveGround = pos.Y - groundRay.Position.Y
				if heightAboveGround < locoConfig.hoverHeight then
					local correction = (locoConfig.hoverHeight - heightAboveGround) * 3
					yVel = math.max(yVel, correction)
				end
			end
		else
			-- Ground-based locomotion (walk, hop, slither)
			jumpCooldown = math.max(0, jumpCooldown - dt)

			if locomotion == "hop" and spaceHeld and jumpCooldown <= 0 then
				-- Grounded check via downward raycast
				local pos = seat.CFrame.Position
				local groundRay = workspace:Raycast(pos, Vector3.new(0, -3, 0), rayParams)
				if groundRay then
					yVel = locoConfig.jumpPower
					jumpCooldown = 0.6
				end
			elseif locomotion == "slither" and locoConfig.canWallClimb and spaceHeld then
				-- Wall climb: forward raycast detects wall within 3 studs
				local pos = seat.CFrame.Position
				local forward = CFrame.Angles(0, currentYaw, 0).LookVector
				local wallRay = workspace:Raycast(pos, forward * 3, rayParams)
				if wallRay then
					-- Climbing: push upward along wall
					yVel = locoConfig.jumpPower * 1.5
				else
					-- Normal small jump
					local groundRay = workspace:Raycast(pos, Vector3.new(0, -3, 0), rayParams)
					if groundRay and jumpCooldown <= 0 then
						yVel = locoConfig.jumpPower
						jumpCooldown = 0.4
					end
				end
			elseif spaceHeld and jumpCooldown <= 0 then
				-- Walk: moderate jump
				local pos = seat.CFrame.Position
				local groundRay = workspace:Raycast(pos, Vector3.new(0, -3, 0), rayParams)
				if groundRay then
					yVel = locoConfig.jumpPower
					jumpCooldown = 0.3
				end
			end
		end

		-- ── Apply direct physics ──
		local forward = CFrame.Angles(0, currentYaw, 0).LookVector
		local targetVel = forward * currentSpeed + Vector3.new(0, yVel, 0)
		seat.AssemblyLinearVelocity = targetVel

		local pos = seat.CFrame.Position
		seat.CFrame = CFrame.new(pos) * CFrame.Angles(0, currentYaw, bankZ)
		seat.AssemblyAngularVelocity = Vector3.zero

		-- ── Animate creature ──
		if _animator then
			_animator.apply(tick())
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════════

--[[
	Mount a creature from the backpack (builds model fresh).
	@param creature — full creature data table (id, name, modelData, stats, etc.)
]]
function MountController:mountCreature(creature: { [string]: any })
	if _mounted then
		self:dismount()
	end

	local character = Player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not creature.modelData then
		return
	end

	local locomotion = creature.modelData.locomotion or "walk"
	if not MountConfig.isMountable(locomotion) then
		return
	end

	-- Validate with server
	local ok, result = MountService:RequestMount(creature.id, locomotion):await()
	if not ok or not result or not result.success then
		return
	end

	-- Build model
	local model = OrigamiBuilder.BuildModel(creature.modelData)
	if not model then
		return
	end
	model.Name = (creature.name or "Mount") .. "_Mount"
	model:SetAttribute("OwnerUserId", Player.UserId)
	model:SetAttribute("CreatureId", creature.id)
	model.Parent = workspace

	-- Scale up if too small to ride
	local _, modelSize = model:GetBoundingBox()
	if modelSize.Y < MountConfig.MIN_RIDE_HEIGHT then
		local scaleFactor = math.min(MountConfig.MIN_RIDE_HEIGHT / modelSize.Y, MountConfig.MAX_SCALE)
		model:ScaleTo(scaleFactor)
		_, modelSize = model:GetBoundingBox()
	end

	self:_attachToSeat(model, creature, locomotion, modelSize)
end

--[[
	Mount a creature already spawned in the world (from ProximityPrompt).
	@param creature — creature data
	@param model — existing Model in workspace
	@param aiCleanup — cleanup function from CreatureAI.Start() to stop AI
]]
function MountController:mountCreatureFromWorld(creature: { [string]: any }, model: Model, aiCleanup: (() -> ())?)
	if _mounted then
		self:dismount()
	end

	local character = Player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local locomotion = creature.modelData.locomotion or "walk"
	if not MountConfig.isMountable(locomotion) then
		return
	end

	local ok, result = MountService:RequestMount(creature.id, locomotion):await()
	if not ok or not result or not result.success then
		return
	end

	-- Stop AI before welding
	if aiCleanup then
		aiCleanup()
	end

	-- Scale up if needed
	local _, modelSize = model:GetBoundingBox()
	if modelSize.Y < MountConfig.MIN_RIDE_HEIGHT then
		local scaleFactor = math.min(MountConfig.MIN_RIDE_HEIGHT / modelSize.Y, MountConfig.MAX_SCALE)
		model:ScaleTo(scaleFactor)
		_, modelSize = model:GetBoundingBox()
	end

	self:_attachToSeat(model, creature, locomotion, modelSize)
end

--[[
	Internal: create seat, weld model, sit player, start drive loop.
]]
function MountController:_attachToSeat(
	model: Model,
	creature: { [string]: any },
	locomotion: string,
	modelSize: Vector3
)
	local character = Player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local placementPos = rootPart.Position + rootPart.CFrame.LookVector * 8
	local _, lookY, _ = rootPart.CFrame:ToEulerAnglesYXZ()

	-- Raycast to ground
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character, model }
	local rayResult = workspace:Raycast(
		Vector3.new(placementPos.X, rootPart.Position.Y + 10, placementPos.Z),
		Vector3.new(0, -50, 0),
		rayParams
	)
	local groundY = if rayResult then rayResult.Position.Y else (rootPart.Position.Y - 3)
	placementPos = Vector3.new(placementPos.X, groundY + 1, placementPos.Z)

	-- Create server seat
	local ok, seat = MountService:CreateMountSeat(
		placementPos,
		lookY,
		{ X = modelSize.X, Y = modelSize.Y, Z = modelSize.Z },
		locomotion,
		creature.id
	):await()

	if not ok or not seat then
		return
	end

	-- Position model above seat
	local modelRise = modelSize.Y / 2 - 1
	model:PivotTo(seat.CFrame * CFrame.new(0, modelRise, 0))

	-- Weld parts: 2-4 largest have mass, rest massless (same as vehicle pattern)
	local partsByVolume = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local sz = part.Size
			table.insert(partsByVolume, { part = part, volume = sz.X * sz.Y * sz.Z })
		end
	end
	table.sort(partsByVolume, function(a, b)
		return a.volume > b.volume
	end)

	local heavyCount = math.clamp(#partsByVolume, 0, 4)
	if heavyCount > 2 then
		heavyCount = 2
	end
	local heavySet = {}
	for i = 1, heavyCount do
		heavySet[partsByVolume[i].part] = true
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			if heavySet[part] then
				part.Massless = false
				part.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.0, 0.3, 0.0)
			else
				part.Massless = true
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = seat
			weld.Part1 = part
			weld.Parent = part
		end
	end

	-- Unanchor seat (tells server to release + set network owner)
	MountService:ReadyMount(seat):await()

	-- Sit player
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		seat:Sit(humanoid)
	end

	-- Store state
	_mounted = true
	_mountModel = model
	_mountSeat = seat
	_mountCreatureId = creature.id
	_mountLocomotion = locomotion

	-- Create animator for creature parts
	_animator = CreatureAI.CreateAnimator(model)

	-- Start drive loop
	local spdStat = (creature.stats and creature.stats.spd) or 10
	startDriveLoop(seat, locomotion, spdStat)

	-- Bind dismount key
	_dismountConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == MountConfig.DISMOUNT_KEY then
			self:dismount()
		end
	end)
end

--[[
	Dismount: stop drive loop, destroy seat, leave creature in world with AI resumed.
]]
function MountController:dismount()
	if not _mounted then
		return
	end

	local model = _mountModel
	local creatureId = _mountCreatureId

	-- Stop drive loop + unbind keys
	cleanup()

	-- Tell server to destroy seat
	task.spawn(function()
		MountService:Dismount():await()
	end)

	-- If model still exists, re-anchor parts and optionally restart AI
	if model and model.Parent then
		-- Remove welds, re-anchor parts at current position
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("WeldConstraint") then
				part:Destroy()
			end
		end
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.Massless = false
			end
		end

		-- Re-enable ProximityPrompt if it exists
		local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			local prompt = primaryPart:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = true
			end
		end
	end

	_mountModel = nil
end

function MountController:isMounted(): boolean
	return _mounted
end

function MountController:getMountedCreatureId(): string?
	return _mountCreatureId
end

function MountController:KnitInit() end

function MountController:KnitStart()
	MountService = Knit.GetService("MountService")

	-- Listen for server-forced dismount (e.g. PlayerRemoving cleanup)
	MountService.MountEnded:Connect(function(creatureId: string)
		if _mounted and _mountCreatureId == creatureId then
			cleanup()
			_mountModel = nil
		end
	end)
end

return MountController
