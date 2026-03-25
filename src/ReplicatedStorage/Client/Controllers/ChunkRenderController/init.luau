--!strict
-- ChunkRenderController: Mixed-geometry block renderer
-- Each block type has a distinct shape from BlockRegistry: Block, Ball, Cylinder, Wedge
-- Separate part pools per shape type. Hidden-face optimization only for Block-shaped blocks.
-- Parts store ChunkKey and FlatIndex attributes for mining raycast targeting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local _ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

local CHUNK_SIZE = MiningConfig.CHUNK_SIZE
local BLOCK_SIZE = MiningConfig.BLOCK_SIZE
local WORLD_OFFSET = MiningConfig.WORLD_OFFSET
local MAX_POOL_SIZE = 5000

local ChunkRenderController = Knit.CreateController({ Name = "ChunkRenderController" })

local chunkBlocks: { [string]: buffer } = {}
local chunkFolders: { [string]: Folder } = {}

-- Part pools per shape type
local partPools: { [string]: { BasePart } } = {
	Block = {},
	Ball = {},
	Cylinder = {},
	Wedge = {},
}

-- Cardinal rotations for Wedge parts (seeded by position)
local WEDGE_ROTATIONS = {
	CFrame.Angles(0, 0, 0),
	CFrame.Angles(0, math.rad(90), 0),
	CFrame.Angles(0, math.rad(180), 0),
	CFrame.Angles(0, math.rad(270), 0),
}

local active = false

local function acquirePart(shape: string): BasePart
	local pool = partPools[shape]
	if pool and #pool > 0 then
		local part = table.remove(pool) :: BasePart
		part.Transparency = 0
		part.CanCollide = true
		return part
	end

	local part: BasePart
	if shape == "Wedge" then
		local wedge = Instance.new("WedgePart")
		wedge.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		part = wedge
	else
		local p = Instance.new("Part")
		if shape == "Ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			p.Shape = Enum.PartType.Cylinder
		else
			p.Shape = Enum.PartType.Block
		end
		p.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		part = p
	end

	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = true
	return part
end

local function releasePart(part: BasePart)
	local shape = part:GetAttribute("Shape") or "Block"
	part.Parent = nil
	part:SetAttribute("ChunkKey", nil)
	part:SetAttribute("FlatIndex", nil)
	part:SetAttribute("Shape", nil)
	local pool = partPools[shape]
	if pool and #pool < MAX_POOL_SIZE then
		table.insert(pool, part)
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

local function isFullyHidden(blocks: buffer, lx: number, ly: number, lz: number, blockId: number): boolean
	local def = BlockRegistry.get(blockId)
	if not def or def.shape ~= "Block" then
		return false
	end
	return isNeighborSolid(blocks, lx + 1, ly, lz)
		and isNeighborSolid(blocks, lx - 1, ly, lz)
		and isNeighborSolid(blocks, lx, ly + 1, lz)
		and isNeighborSolid(blocks, lx, ly - 1, lz)
		and isNeighborSolid(blocks, lx, ly, lz + 1)
		and isNeighborSolid(blocks, lx, ly, lz - 1)
end

local function renderChunk(chunkKey: string, cx: number, cy: number, cz: number, blocks: buffer)
	local oldFolder = chunkFolders[chunkKey]
	if oldFolder then
		for _, child in oldFolder:GetChildren() do
			if child:IsA("BasePart") then
				releasePart(child :: BasePart)
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

				if isFullyHidden(blocks, lx, ly, lz, blockId) then
					continue
				end

				local blockDef = BlockRegistry.get(blockId)
				if not blockDef then
					continue
				end

				local shape = blockDef.shape
				local part = acquirePart(shape)

				local wx = worldBaseX + lx * BLOCK_SIZE + halfBlock
				local wy = worldBaseY + ly * BLOCK_SIZE + halfBlock
				local wz = worldBaseZ + lz * BLOCK_SIZE + halfBlock

				if shape == "Cylinder" then
					part.CFrame = CFrame.new(wx, wy, wz) * CFrame.Angles(0, 0, math.rad(90))
				elseif shape == "Wedge" then
					local rotIndex = ((lx * 7 + ly * 13 + lz * 23) % 4) + 1
					part.CFrame = CFrame.new(wx, wy, wz) * WEDGE_ROTATIONS[rotIndex]
				else
					part.CFrame = CFrame.new(wx, wy, wz)
				end

				part.Color = blockDef.color
				part.Material = blockDef.material
				part.Transparency = blockDef.transparency

				if blockId == BlockType.Water then
					part.CanCollide = false
				end

				part:SetAttribute("ChunkKey", chunkKey)
				part:SetAttribute("FlatIndex", idx)
				part:SetAttribute("Shape", shape)
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
			if child:IsA("BasePart") then
				releasePart(child :: BasePart)
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
	for shapeName, pool in pairs(partPools) do
		for _, part in ipairs(pool) do
			part:Destroy()
		end
		partPools[shapeName] = {}
	end
end

return ChunkRenderController
