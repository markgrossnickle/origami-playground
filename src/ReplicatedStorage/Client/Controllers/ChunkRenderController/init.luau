--!strict
-- ChunkRenderController: Pure-cubes block renderer
-- All blocks render as Part (Block shape, Size 4x4x4). Color and material from BlockRegistry.
-- Hidden-face culling: skip blocks with solid neighbors on all 6 sides.
-- Part pooling: single pool up to 5000 parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

local CHUNK_SIZE = MiningConfig.CHUNK_SIZE
local BLOCK_SIZE = MiningConfig.BLOCK_SIZE
local WORLD_OFFSET = MiningConfig.WORLD_OFFSET
local MAX_POOL_SIZE = 5000

local ChunkRenderController = Knit.CreateController({ Name = "ChunkRenderController" })

local chunkBlocks: { [string]: buffer } = {}
local chunkFolders: { [string]: Folder } = {}
local partPool: { Part } = {}
local active = false

local function acquirePart(): Part
	if #partPool > 0 then
		local part = table.remove(partPool) :: Part
		part.Transparency = 0
		part.CanCollide = true
		return part
	end
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = true
	return part
end

local function releasePart(part: Part)
	part.Parent = nil
	part:SetAttribute("ChunkKey", nil)
	part:SetAttribute("FlatIndex", nil)
	if #partPool < MAX_POOL_SIZE then
		table.insert(partPool, part)
	else
		part:Destroy()
	end
end

local function isNeighborSolid(buf: buffer, lx: number, ly: number, lz: number): boolean
	if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE then
		return false
	end
	local idx = ly * 256 + lz * 16 + lx
	local blockId = buffer.readu8(buf, idx)
	return BlockRegistry.isSolid(blockId)
end

local function renderChunk(chunkKey: string, cx: number, cy: number, cz: number, blocks: buffer)
	local oldFolder = chunkFolders[chunkKey]
	if oldFolder then
		for _, child in oldFolder:GetChildren() do
			if child:IsA("Part") then
				releasePart(child :: Part)
			else
				child:Destroy()
			end
		end
		oldFolder:Destroy()
		chunkFolders[chunkKey] = nil
	end

	local miningWorld = workspace:FindFirstChild("MiningWorld")
	if not miningWorld then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "Chunk_" .. chunkKey

	local worldBaseX = cx * CHUNK_SIZE * BLOCK_SIZE + WORLD_OFFSET.X
	local worldBaseY = cy * CHUNK_SIZE * BLOCK_SIZE + WORLD_OFFSET.Y
	local worldBaseZ = cz * CHUNK_SIZE * BLOCK_SIZE + WORLD_OFFSET.Z
	local halfBlock = BLOCK_SIZE / 2

	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ly * 256 + lz * 16 + lx
				local blockId = buffer.readu8(blocks, idx)

				if blockId == BlockType.Air then
					continue
				end

				if
					isNeighborSolid(blocks, lx + 1, ly, lz)
					and isNeighborSolid(blocks, lx - 1, ly, lz)
					and isNeighborSolid(blocks, lx, ly + 1, lz)
					and isNeighborSolid(blocks, lx, ly - 1, lz)
					and isNeighborSolid(blocks, lx, ly, lz + 1)
					and isNeighborSolid(blocks, lx, ly, lz - 1)
				then
					continue
				end

				local blockDef = BlockRegistry.get(blockId)
				if not blockDef then
					continue
				end

				local part = acquirePart()
				part.Position = Vector3.new(
					worldBaseX + lx * BLOCK_SIZE + halfBlock,
					worldBaseY + ly * BLOCK_SIZE + halfBlock,
					worldBaseZ + lz * BLOCK_SIZE + halfBlock
				)
				part.Color = blockDef.color
				part.Material = blockDef.material
				part.Transparency = blockDef.transparency

				if blockId == BlockType.Water then
					part.CanCollide = false
				end

				part:SetAttribute("ChunkKey", chunkKey)
				part:SetAttribute("FlatIndex", idx)
				part.Name = "Block_" .. idx
				part.Parent = folder
			end
		end
	end

	folder.Parent = miningWorld
	chunkFolders[chunkKey] = folder
	print(string.format("[ChunkRenderController] Rendered chunk %s: %d parts created", chunkKey, #folder:GetChildren()))
end

local function unloadChunk(chunkKey: string)
	local folder = chunkFolders[chunkKey]
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Part") then
				releasePart(child :: Part)
			else
				child:Destroy()
			end
		end
		folder:Destroy()
	end
	chunkFolders[chunkKey] = nil
	chunkBlocks[chunkKey] = nil
end

function ChunkRenderController:KnitInit() end

function ChunkRenderController:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	GameMode.Changed:Connect(function(newMode: string, _oldMode: string)
		if newMode == "mining" then
			self:_activate()
		elseif active then
			self:_deactivate()
		end
	end)

	WorldService.ChunkLoaded:Connect(function(chunkKey: string, compressed: buffer, cx: number, cy: number, cz: number)
		print(
			string.format(
				"[ChunkRenderController] Received chunk (%d,%d,%d), compressed size=%d",
				cx,
				cy,
				cz,
				buffer.len(compressed)
			)
		)
		if not active then
			return
		end
		local blocks = ChunkSerializer.decompress(compressed)
		chunkBlocks[chunkKey] = blocks
		renderChunk(chunkKey, cx, cy, cz, blocks)
	end)

	WorldService.ChunkUnloaded:Connect(function(chunkKey: string)
		unloadChunk(chunkKey)
	end)

	WorldService.BlockChanged:Connect(
		function(
			chunkKey: string,
			flatIndex: number,
			newBlockType: number,
			_lx: number,
			_ly: number,
			_lz: number,
			cx: number,
			cy: number,
			cz: number
		)
			if not active then
				return
			end
			local blocks = chunkBlocks[chunkKey]
			if blocks then
				buffer.writeu8(blocks, flatIndex, newBlockType)
				renderChunk(chunkKey, cx, cy, cz, blocks)
			end
		end
	)
end

function ChunkRenderController:_activate()
	if active then
		return
	end
	active = true
	-- MiningWorld folder is created by Server:_setupWorld()
	-- Wait for it to replicate to client
	if not workspace:FindFirstChild("MiningWorld") then
		workspace:WaitForChild("MiningWorld", 10)
	end
	print(
		"[ChunkRenderController] MiningWorld folder:",
		workspace:FindFirstChild("MiningWorld") and "found" or "NOT FOUND"
	)
end

function ChunkRenderController:_deactivate()
	if not active then
		return
	end
	active = false
	for chunkKey, _ in pairs(chunkFolders) do
		unloadChunk(chunkKey)
	end
	chunkBlocks = {}
	chunkFolders = {}
end

return ChunkRenderController
