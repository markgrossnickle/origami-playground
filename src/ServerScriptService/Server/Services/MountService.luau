--[[
	MountService — server-side mount seat creation, cleanup, and ownership validation.
	Mirrors OrigamiService.CreateVehicleSeat pattern for creature mounts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local MountConfig = require(ReplicatedStorage.Shared.MountConfig)

local MountService = Knit.CreateService({
	Name = "MountService",
	Client = {
		MountStarted = Knit.CreateSignal(), -- (creatureId, seat)
		MountEnded = Knit.CreateSignal(), -- (creatureId)
	},
})

-- Per-player active mount: { seat: VehicleSeat, plate: Part, creatureId: string }
local _activeMounts: { [number]: { seat: VehicleSeat, plate: Part, creatureId: string } } = {}

-- Validate creature ownership via CreatureService
local function playerOwnsCreature(player: Player, creatureId: string): boolean
	local CreatureService = Knit.GetService("CreatureService")
	local ok, creatures = pcall(function()
		return CreatureService.Client:GetCreatures(player)
	end)
	if not ok or type(creatures) ~= "table" then
		return false
	end
	for _, c in ipairs(creatures) do
		if c.id == creatureId then
			return true
		end
	end
	return false
end

function MountService.Client:RequestMount(player: Player, creatureId: string, locomotion: string)
	-- Validate
	if not MountConfig.isMountable(locomotion) then
		return { success = false, reason = "not_mountable" }
	end
	if not playerOwnsCreature(player, creatureId) then
		return { success = false, reason = "not_owned" }
	end
	-- Dismount existing mount first
	local existing = _activeMounts[player.UserId]
	if existing then
		self.Server:_cleanupMount(player)
	end
	return { success = true }
end

function MountService.Client:CreateMountSeat(
	player: Player,
	position: Vector3,
	lookY: number,
	boundingSizeData: { X: number, Y: number, Z: number },
	locomotion: string,
	creatureId: string
)
	local locoConfig = MountConfig.get(locomotion)
	if not locoConfig then
		return nil
	end

	-- Create invisible VehicleSeat (server-side so Sit() works)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "MountSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.CFrame = CFrame.new(position) * CFrame.Angles(0, lookY, 0)
	seat.Anchored = true
	seat.CanCollide = true
	seat.Transparency = 1
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Material = Enum.Material.SmoothPlastic
	seat:SetAttribute("MountCreature", true)
	seat:SetAttribute("OwnerUserId", player.UserId)
	seat:SetAttribute("Locomotion", locomotion)
	seat:SetAttribute("CreatureId", creatureId)
	seat.Parent = workspace

	-- Collision plate for ground contact
	local modelSize = Vector3.new(boundingSizeData.X or 4, boundingSizeData.Y or 2, boundingSizeData.Z or 4)
	local collisionPlate = Instance.new("Part")
	collisionPlate.Name = "MountCollisionPlate"
	collisionPlate.Size = Vector3.new(math.min(modelSize.X * 0.8, 14), 0.5, math.min(modelSize.Z * 0.8, 16))
	collisionPlate.Transparency = 1
	collisionPlate.CanCollide = true
	collisionPlate.Massless = false
	collisionPlate.Anchored = false
	collisionPlate.Material = Enum.Material.SmoothPlastic
	collisionPlate.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.6, 0.0, 0.6, 0.0)
	collisionPlate.CFrame = seat.CFrame * CFrame.new(0, -1, 0)
	collisionPlate.Parent = workspace

	local plateWeld = Instance.new("WeldConstraint")
	plateWeld.Part0 = seat
	plateWeld.Part1 = collisionPlate
	plateWeld.Parent = collisionPlate

	-- Auto-dismount when occupant leaves
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Occupant then
			local mount = _activeMounts[player.UserId]
			if mount and mount.seat == seat then
				self.Server:_cleanupMount(player)
			end
		end
	end)

	-- Store active mount
	_activeMounts[player.UserId] = {
		seat = seat,
		plate = collisionPlate,
		creatureId = creatureId,
	}

	return seat
end

function MountService.Client:ReadyMount(player: Player, seat: VehicleSeat)
	if seat and seat.Parent and seat:GetAttribute("OwnerUserId") == player.UserId then
		seat.Anchored = false
		seat:SetNetworkOwner(player)
	end
end

function MountService.Client:Dismount(player: Player)
	self.Server:_cleanupMount(player)
end

function MountService:_cleanupMount(player: Player)
	local mount = _activeMounts[player.UserId]
	if not mount then
		return
	end

	local creatureId = mount.creatureId

	if mount.seat and mount.seat.Parent then
		mount.seat:Destroy()
	end
	if mount.plate and mount.plate.Parent then
		mount.plate:Destroy()
	end

	_activeMounts[player.UserId] = nil
	self.Client.MountEnded:Fire(player, creatureId)
end

function MountService:KnitInit() end

function MountService:KnitStart()
	-- Cleanup on player leaving
	Players.PlayerRemoving:Connect(function(player: Player)
		self:_cleanupMount(player)
	end)
end

return MountService
