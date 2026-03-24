--!strict
-- ChunkStreamService: Stream chunks around mining-mode players at 2Hz
-- Uses WorldService Subscribe/Unsubscribe for chunk lifecycle management

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

local ChunkStreamService = Knit.CreateService({
	Name = "ChunkStreamService",
	Client = {
		EnterMiningWorld = Knit.CreateSignal(),
		LeaveMiningWorld = Knit.CreateSignal(),
	},
})

local STREAM_RADIUS_H = MiningConfig.STREAM_RADIUS_H
local STREAM_RADIUS_V = MiningConfig.STREAM_RADIUS_V
local MAX_CHUNKS_PER_FRAME = MiningConfig.MAX_CHUNKS_PER_FRAME
local TICK_INTERVAL = 0.5 -- 2Hz

-- Per-player tracking
local playerChunks: { [Player]: { [string]: boolean } } = {}
local miningPlayers: { [Player]: boolean } = {}

function ChunkStreamService:KnitInit() end

function ChunkStreamService:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	-- Listen for client enter/leave signals
	self.Client.EnterMiningWorld:Connect(function(player: Player)
		self:AddPlayer(player)
	end)

	self.Client.LeaveMiningWorld:Connect(function(player: Player)
		self:RemovePlayer(player)
	end)

	-- Heartbeat stream loop
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed = elapsed + dt
		if elapsed < TICK_INTERVAL then
			return
		end
		elapsed = 0

		for player, _ in pairs(miningPlayers) do
			if not player.Parent then
				self:_removePlayer(player)
				continue
			end

			local character = player.Character
			if not character then
				continue
			end

			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not rootPart then
				continue
			end

			local worldPos = rootPart.Position
			local offset = MiningConfig.WORLD_OFFSET
			local relX = worldPos.X - offset.X
			local relY = worldPos.Y - offset.Y
			local relZ = worldPos.Z - offset.Z

			local pcx, pcy, pcz = ChunkUtil.worldToChunk(relX, relY, relZ)

			-- Determine desired chunks
			local desired: { [string]: boolean } = {}
			for dy = -STREAM_RADIUS_V, STREAM_RADIUS_V do
				for dz = -STREAM_RADIUS_H, STREAM_RADIUS_H do
					for dx = -STREAM_RADIUS_H, STREAM_RADIUS_H do
						local cx = pcx + dx
						local cy = pcy + dy
						local cz = pcz + dz
						-- Clamp to world bounds
						if cy >= 0 and cy < MiningConfig.WORLD_HEIGHT_CHUNKS then
							local key = ChunkUtil.chunkKey(cx, cy, cz)
							desired[key] = true
						end
					end
				end
			end

			local current = playerChunks[player] or {}

			-- Unsubscribe chunks no longer needed
			for key, _ in pairs(current) do
				if not desired[key] then
					local ucx, ucy, ucz = ChunkUtil.parseChunkKey(key)
					WorldService:Unsubscribe(ucx, ucy, ucz)
					WorldService.Client.ChunkUnloaded:Fire(player, ucx, ucy, ucz)
					current[key] = nil
				end
			end

			-- Subscribe new chunks (rate-limited)
			local loaded = 0
			for key, _ in pairs(desired) do
				if not current[key] then
					if loaded >= MAX_CHUNKS_PER_FRAME then
						break
					end
					local scx, scy, scz = ChunkUtil.parseChunkKey(key)
					WorldService:Subscribe(scx, scy, scz)
					local blockData = WorldService:GetChunkData(scx, scy, scz)
					local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
					local compressed = ChunkSerializer.compress(blockData)
					WorldService.Client.ChunkLoaded:Fire(player, scx, scy, scz, compressed)
					current[key] = true
					loaded = loaded + 1
				end
			end

			playerChunks[player] = current
		end
	end)

	-- Clean up on player leaving
	Players.PlayerRemoving:Connect(function(player: Player)
		self:_removePlayer(player)
	end)
end

-- Register a player as being in mining mode
function ChunkStreamService:AddPlayer(player: Player)
	miningPlayers[player] = true
	playerChunks[player] = {}
end

-- Remove a player from mining mode
function ChunkStreamService:RemovePlayer(player: Player)
	self:_removePlayer(player)
end

function ChunkStreamService:_removePlayer(player: Player)
	miningPlayers[player] = nil

	local current = playerChunks[player]
	if current then
		local WorldService = Knit.GetService("WorldService")
		for key, _ in pairs(current) do
			local cx, cy, cz = ChunkUtil.parseChunkKey(key)
			WorldService:Unsubscribe(cx, cy, cz)
		end
	end
	playerChunks[player] = nil
end

return ChunkStreamService
