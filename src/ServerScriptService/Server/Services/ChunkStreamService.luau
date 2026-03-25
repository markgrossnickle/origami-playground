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
local TICK_INTERVAL = 0.5

local playerChunks: { [Player]: { [string]: boolean } } = {}
local miningPlayers: { [Player]: boolean } = {}

function ChunkStreamService:KnitInit() end

function ChunkStreamService:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	self.Client.EnterMiningWorld:Connect(function(player: Player)
		print("[ChunkStreamService] Player entered mining world:", player.Name)
		self:AddPlayer(player)
	end)

	self.Client.LeaveMiningWorld:Connect(function(player: Player)
		print("[ChunkStreamService] Player left mining world:", player.Name)
		self:RemovePlayer(player)
	end)

	local elapsed = 0
	local tickCount = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed = elapsed + dt
		if elapsed < TICK_INTERVAL then
			return
		end
		elapsed = 0
		tickCount += 1

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

			local offset = MiningConfig.WORLD_OFFSET
			local relX = rootPart.Position.X - offset.X
			local relY = rootPart.Position.Y - offset.Y
			local relZ = rootPart.Position.Z - offset.Z

			local pcx, pcy, pcz = ChunkUtil.worldToChunk(relX, relY, relZ)

			if tickCount <= 3 then
				print(
					string.format(
						"[ChunkStreamService] tick %d: pos=(%.0f,%.0f,%.0f) rel=(%.0f,%.0f,%.0f) chunk=(%d,%d,%d)",
						tickCount,
						rootPart.Position.X,
						rootPart.Position.Y,
						rootPart.Position.Z,
						relX,
						relY,
						relZ,
						pcx,
						pcy,
						pcz
					)
				)
			end

			local desired: { [string]: boolean } = {}
			for dy = -STREAM_RADIUS_V, STREAM_RADIUS_V do
				for dz = -STREAM_RADIUS_H, STREAM_RADIUS_H do
					for dx = -STREAM_RADIUS_H, STREAM_RADIUS_H do
						local cy = pcy + dy
						if cy >= 0 and cy < MiningConfig.WORLD_HEIGHT_CHUNKS then
							local key = ChunkUtil.chunkKey(pcx + dx, cy, pcz + dz)
							desired[key] = true
						end
					end
				end
			end

			local current = playerChunks[player] or {}

			for key, _ in pairs(current) do
				if not desired[key] then
					WorldService:Unsubscribe(player, key)
					current[key] = nil
				end
			end

			local loaded = 0
			for key, _ in pairs(desired) do
				if not current[key] then
					if loaded >= MAX_CHUNKS_PER_FRAME then
						break
					end
					WorldService:Subscribe(player, key)
					current[key] = true
					loaded = loaded + 1
				end
			end

			if tickCount <= 3 then
				local desiredCount = 0
				for _ in desired do
					desiredCount += 1
				end
				local currentCount = 0
				for _ in current do
					currentCount += 1
				end
				print(
					string.format(
						"[ChunkStreamService] tick %d: desired=%d current=%d newLoaded=%d",
						tickCount,
						desiredCount,
						currentCount,
						loaded
					)
				)
			end

			playerChunks[player] = current
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_removePlayer(player)
	end)
end

function ChunkStreamService:AddPlayer(player: Player)
	miningPlayers[player] = true
	playerChunks[player] = {}
end

function ChunkStreamService:RemovePlayer(player: Player)
	self:_removePlayer(player)
end

function ChunkStreamService:_removePlayer(player: Player)
	miningPlayers[player] = nil
	local current = playerChunks[player]
	if current then
		local WorldService = Knit.GetService("WorldService")
		for key, _ in pairs(current) do
			WorldService:Unsubscribe(player, key)
		end
	end
	playerChunks[player] = nil
end

return ChunkStreamService
