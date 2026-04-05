--[[
	WorldDecorService — places animated origami decorations near spawn.
	Uses OrigamiBuilder to construct models and CreatureAI for animation.
	Runs server-side; single instances = negligible perf cost.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
local CreatureAI = require(ReplicatedStorage.Shared.CreatureAI)
local WorldDecorModels = require(ReplicatedStorage.Shared.WorldDecorModels)

local WorldDecorService = Knit.CreateService({
	Name = "WorldDecorService",
	Client = {},
})

local _cleanups: { () -> () } = {}

local function placeModel(modelData: { [string]: any }, position: Vector3, facingYaw: number?)
	local model = OrigamiBuilder.BuildModel(modelData)
	if not model then
		warn("[WorldDecor] Failed to build:", modelData.name)
		return
	end

	model.Name = modelData.name or "Decor"
	model:SetAttribute("WorldDecor", true)
	model.Parent = workspace

	-- Position at ground level facing the given yaw
	local yaw = facingYaw or 0
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))

	-- Start stationary animation via CreatureAI (jaw snap, wing flap, tail sway, etc.)
	local cleanup = CreatureAI.Start(model, modelData, position, { model })
	table.insert(_cleanups, cleanup)

	print("[WorldDecor] Placed", modelData.name, "at", position)
end

local function getSpawnPosition(): Vector3?
	-- Wait for SpawnService to create the SpawnLocation
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if not spawnLocation then
		-- SpawnService may not have run yet; wait briefly
		for _ = 1, 30 do
			task.wait(0.5)
			spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
			if spawnLocation then
				break
			end
		end
	end
	if spawnLocation then
		-- SpawnLocation is 1 stud below terrain; return terrain surface level
		return spawnLocation.Position + Vector3.new(0, 1, 0)
	end
	return nil
end

function WorldDecorService:KnitInit() end

function WorldDecorService:KnitStart()
	task.spawn(function()
		local spawnPos = getSpawnPosition()
		if not spawnPos then
			warn("[WorldDecor] Could not find spawn position, skipping decor placement")
			return
		end

		-- Place small Venus fly trap creature: 15 studs to the right of spawn
		local creaturePos = spawnPos + Vector3.new(15, 0, 5)
		placeModel(WorldDecorModels.VenusFlyTrap, creaturePos, math.rad(-30))

		-- Place giant Venus fly trap tree: 20 studs to the left of spawn
		local treePos = spawnPos + Vector3.new(-20, 0, -8)
		placeModel(WorldDecorModels.VenusFlyTrapTree, treePos, math.rad(15))
	end)
end

return WorldDecorService
