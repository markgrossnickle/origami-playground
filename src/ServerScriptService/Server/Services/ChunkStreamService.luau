--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)

local POLL_INTERVAL = 0.5
local LOAD_RADIUS_H = 3
local LOAD_RADIUS_UP = 1
local LOAD_RADIUS_DOWN = 4
local MAX_SENDS_PER_CYCLE = 4

--[=[
	@class ChunkStreamService
	Polls player positions and streams chunks in/out via WorldService.
]=]
local ChunkStreamService = Knit.CreateService({
	Name = "ChunkStreamService",
	Client = {},
})

local WorldService

local playerRequiredChunks: { [Player]: { [number]: boolean } } = {}
local playerUpdateInFlight: { [Player]: boolean } = {}

local function _getRequiredChunks(player: Player): { { cx: number, cy: number, cz: number, dist: number } }
	local character = player.Character
	if not character then
		return {}
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return {}
	end

	local pos = rootPart.Position
	local pcx, pcy, pcz = ChunkUtil.worldToChunk(pos.X, pos.Y, pos.Z)

	local required = {}
	for dx = -LOAD_RADIUS_H, LOAD_RADIUS_H do
		for dz = -LOAD_RADIUS_H, LOAD_RADIUS_H do
			for dy = -LOAD_RADIUS_DOWN, LOAD_RADIUS_UP do
				local cx = pcx + dx
				local cy = pcy + dy
				local cz = pcz + dz

				if ChunkUtil.isInMineBounds(cx, cz) then
					local dist = dx * dx + dy * dy + dz * dz
					table.insert(required, { cx = cx, cy = cy, cz = cz, dist = dist })
				end
			end
		end
	end

	table.sort(required, function(a, b)
		return a.dist < b.dist
	end)

	return required
end

local function _updatePlayerChunks(player: Player)
	if not player.Parent then
		return
	end

	-- Prevent overlapping updates (Subscribe now yields, so previous update may still be in flight)
	if playerUpdateInFlight[player] then
		return
	end
	playerUpdateInFlight[player] = true

	local required = _getRequiredChunks(player)

	local requiredSet: { [number]: boolean } = {}
	for _, chunk in required do
		local key = ChunkUtil.chunkKey(chunk.cx, chunk.cy, chunk.cz)
		requiredSet[key] = true
	end

	local currentSubs = playerRequiredChunks[player] or {}

	for chunkKey in currentSubs do
		if not requiredSet[chunkKey] then
			WorldService:Unsubscribe(player, chunkKey)
		end
	end

	local sent = 0
	for _, chunk in required do
		local key = ChunkUtil.chunkKey(chunk.cx, chunk.cy, chunk.cz)
		if not currentSubs[key] then
			if sent < MAX_SENDS_PER_CYCLE then
				WorldService:Subscribe(player, key)
				sent += 1
			else
				requiredSet[key] = nil
			end
		end
	end

	playerRequiredChunks[player] = requiredSet
	playerUpdateInFlight[player] = nil
end

-- Note: _getRequiredChunks above already uses ChunkUtil.chunkKey internally
-- (the `dist` field is a local sort key, not the chunkKey).

function ChunkStreamService:KnitInit()
	Players.PlayerRemoving:Connect(function(player)
		playerRequiredChunks[player] = nil
		playerUpdateInFlight[player] = nil
	end)
end

function ChunkStreamService:KnitStart()
	WorldService = Knit.GetService("WorldService")

	local function onPlayerAdded(player: Player)
		local function onCharacterAdded(character: Model)
			task.defer(function()
				if not player.Parent then
					return
				end

				-- Pre-warm the regions around the player's spawn position so
				-- the first batch of chunk subscribes don't each yield on a
				-- cold DataStore GetAsync. Background, fire-and-forget.
				local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if rootPart then
					local pos = rootPart.Position
					local pcx, pcy, pcz = ChunkUtil.worldToChunk(pos.X, pos.Y, pos.Z)
					WorldService:PrefetchRegionsAround(pcx, pcy, pcz)
				end

				_updatePlayerChunks(player)
			end)
		end

		player.CharacterAdded:Connect(onCharacterAdded)
		if player.Character then
			onCharacterAdded(player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Poll loop
	local elapsed = 0
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < POLL_INTERVAL then
			return
		end
		elapsed = 0

		for _, player in Players:GetPlayers() do
			task.spawn(_updatePlayerChunks, player)
		end
	end)
end

return ChunkStreamService
