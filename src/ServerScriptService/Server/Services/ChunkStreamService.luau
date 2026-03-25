--!strict
-- ChunkStreamService: Stream chunks around mining-mode players at 2Hz

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

local ChunkStreamService = Knit.CreateService({
	Name = "ChunkStreamService",
	Client = {
		SetMiningMode = Knit.CreateSignal(),
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

	self.Client.SetMiningMode:Connect(function(player: Player, enabled: boolean)
		if enabled then
			print("[ChunkStreamService] Player entered mining world:", player.Name)
			self:AddPlayer(player)
		else
			print("[ChunkStreamService] Player left mining world:", player.Name)
			self:RemovePlayer(player)
		end
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

			local worldPos = rootPart.Position
			local offset = MiningConfig.WORLD_OFFSET
			local relX = worldPos.X - offset.X
			local relY = worldPos.Y - offset.Y
			local relZ = worldPos.Z - offset.Z
			local pcx, pcy, pcz = ChunkUtil.worldToChunk(relX, relY, relZ)

			if tickCount <= 3 then
				print(
					string.format(
						"[ChunkStreamService] tick %d: pos=(%.0f,%.0f,%.0f) rel=(%.0f,%.0f,%.0f) chunk=(%d,%d,%d)",
						tickCount,
						worldPos.X,
						worldPos.Y,
						worldPos.Z,
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
						local cx = pcx + dx
						local cy = pcy + dy
						local cz = pcz + dz
						if cy >= 0 and cy < MiningConfig.WORLD_HEIGHT_CHUNKS then
							local key = ChunkUtil.chunkKey(cx, cy, cz)
							desired[key] = true
						end
					end
				end
			end

			local current = playerChunks[player] or {}

			for key, _ in pairs(current) do
				if not desired[key] then
					local ucx, ucy, ucz = ChunkUtil.parseChunkKey(key)
					WorldService:Unsubscribe(ucx, ucy, ucz)
					WorldService.Client.ChunkUnloaded:Fire(player, key)
					current[key] = nil
				end
			end

			local loaded = 0
			for key, _ in pairs(desired) do
				if not current[key] then
					if loaded >= MAX_CHUNKS_PER_FRAME then
						break
					end
					local scx, scy, scz = ChunkUtil.parseChunkKey(key)
					WorldService:Subscribe(scx, scy, scz)
					local blockData = WorldService:GetChunkData(scx, scy, scz)
					local nonAir = 0
					for i = 0, buffer.len(blockData) - 1 do
						if buffer.readu8(blockData, i) ~= 0 then
							nonAir += 1
						end
					end
					local compressed = ChunkSerializer.compress(blockData)
					print(
						string.format(
							"[ChunkStreamService] Subscribe chunk %s (cx=%d,cy=%d,cz=%d): %d non-air blocks, %d bytes compressed",
							key,
							scx,
							scy,
							scz,
							nonAir,
							buffer.len(compressed)
						)
					)
					WorldService.Client.ChunkLoaded:Fire(player, key, compressed, scx, scy, scz)
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
			local cx, cy, cz = ChunkUtil.parseChunkKey(key)
			WorldService:Unsubscribe(cx, cy, cz)
		end
	end
	playerChunks[player] = nil
end

return ChunkStreamService
