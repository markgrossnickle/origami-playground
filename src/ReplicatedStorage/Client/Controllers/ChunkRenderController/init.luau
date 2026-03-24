--!strict
-- ChunkRenderController: Renders chunks as Parts in workspace.MiningWorld
-- FACETED-SURFACE VARIANT:
--   Surface blocks get slight random CFrame rotation (1-3 degrees)
--   Surface edges get WedgePart "fold caps" (50% chance, seeded)
--   Crystal ores render as Ball shapes
--   Hidden face optimization skips fully enclosed blocks

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local ChunkSerializer = require(ReplicatedStorage.Shared.ChunkSerializer)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)

local CHUNK_SIZE = MiningConfig.CHUNK_SIZE
local BLOCK_SIZE = MiningConfig.BLOCK_SIZE
local WORLD_OFFSET = MiningConfig.WORLD_OFFSET

local ChunkRenderController = Knit.CreateController({ Name = "ChunkRenderController" })

-- Chunk render data
local chunkFolders: { [string]: Folder } = {}
local chunkBlocks: { [string]: buffer } = {} -- decompressed block data per chunk

-- Part pool
local MAX_POOL_SIZE = 5000
local partPool: { Part } = {}
local wedgePool: { WedgePart } = {}

-- Neighbor offsets for hidden face check (dx, dy, dz)
local NEIGHBOR_OFFSETS = {
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 1, 0 },
	{ 0, -1, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
}

-- Horizontal neighbor offsets for surface edge detection
local H_NEIGHBOR_OFFSETS = {
	{ 1, 0, 0 },
	{ -1, 0, 0 },
	{ 0, 0, 1 },
	{ 0, 0, -1 },
}

-- Deterministic hash for seeded randomness
local function posHash(x: number, y: number, z: number, seed: number): number
	local h = seed + x * 374761393 + y * 668265263 + z * 1274126177
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = h * 1103515245 + 12345
	return (h % 10000) / 10000
end

-- Get a Part from pool or create new
local function acquirePart(): Part
	if #partPool > 0 then
		local part = table.remove(partPool) :: Part
		part.Shape = Enum.PartType.Block
		part.Transparency = 0
		return part
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Get a WedgePart from pool or create new
local function acquireWedge(): WedgePart
	if #wedgePool > 0 then
		return table.remove(wedgePool) :: WedgePart
	end
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.CastShadow = true
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	return wedge
end

-- Return a Part to pool
local function releasePart(part: Part)
	part.Parent = nil
	if #partPool < MAX_POOL_SIZE then
		table.insert(partPool, part)
	else
		part:Destroy()
	end
end

-- Return a WedgePart to pool
local function releaseWedge(wedge: WedgePart)
	wedge.Parent = nil
	if #wedgePool < MAX_POOL_SIZE then
		table.insert(wedgePool, wedge)
	else
		wedge:Destroy()
	end
end

-- Check if a block at local coords is solid (for hidden face optimization)
local function isBlockSolid(blocks: buffer, lx: number, ly: number, lz: number): boolean
	if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE then
		-- Out of chunk bounds — treat as air (show face)
		return false
	end
	local index = ChunkUtil.flatIndex(lx, ly, lz)
	local blockTypeId = buffer.readu8(blocks, index)
	return blockTypeId ~= BlockType.Air and blockTypeId ~= BlockType.Water
end

-- Check if a block has air above (surface block)
local function isSurfaceBlock(blocks: buffer, lx: number, ly: number, lz: number): boolean
	if ly >= CHUNK_SIZE - 1 then
		return true -- Top of chunk, assume surface
	end
	local aboveIndex = ChunkUtil.flatIndex(lx, ly + 1, lz)
	local aboveType = buffer.readu8(blocks, aboveIndex)
	return aboveType == BlockType.Air or aboveType == BlockType.Water
end

-- Check if a horizontal neighbor is air (for edge fold caps)
local function hasExposedHorizontalFace(blocks: buffer, lx: number, ly: number, lz: number): { { number } }
	local exposed = {}
	for _, offset in H_NEIGHBOR_OFFSETS do
		local nx = lx + offset[1]
		local ny = ly
		local nz = lz + offset[3]
		if not isBlockSolid(blocks, nx, ny, nz) then
			table.insert(exposed, offset)
		end
	end
	return exposed
end

-- Darken a color slightly for fold caps
local function darkenColor(color: Color3, amount: number): Color3
	return Color3.new(math.max(0, color.R - amount), math.max(0, color.G - amount), math.max(0, color.B - amount))
end

function ChunkRenderController:KnitInit() end

function ChunkRenderController:KnitStart()
	local WorldService = Knit.GetService("WorldService")

	-- Listen for chunk loads
	WorldService.ChunkLoaded:Connect(function(cx: number, cy: number, cz: number, compressed: buffer)
		self:_renderChunk(cx, cy, cz, compressed)
	end)

	-- Listen for chunk unloads
	WorldService.ChunkUnloaded:Connect(function(cx: number, cy: number, cz: number)
		local key = ChunkUtil.chunkKey(cx, cy, cz)
		self:_unloadChunk(key)
	end)

	-- Listen for block changes
	WorldService.BlockChanged:Connect(
		function(cx: number, cy: number, cz: number, lx: number, ly: number, lz: number, newBlockType: number)
			self:_updateBlock(cx, cy, cz, lx, ly, lz, newBlockType)
		end
	)
end

function ChunkRenderController:_renderChunk(cx: number, cy: number, cz: number, compressed: buffer)
	local key = ChunkUtil.chunkKey(cx, cy, cz)

	-- Unload existing chunk if re-rendering
	if chunkFolders[key] then
		self:_unloadChunk(key)
	end

	-- Decompress block data
	local blocks = ChunkSerializer.decompress(compressed)
	chunkBlocks[key] = blocks

	-- Create folder for this chunk (build off-screen, then parent)
	local folder = Instance.new("Folder")
	folder.Name = "Chunk_" .. key

	-- Render visible blocks
	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local index = ChunkUtil.flatIndex(lx, ly, lz)
				local blockTypeId = buffer.readu8(blocks, index)

				if blockTypeId == BlockType.Air or blockTypeId == BlockType.Water then
					continue
				end

				-- Hidden face optimization: skip if all 6 neighbors are solid
				local allSolid = true
				for _, offset in NEIGHBOR_OFFSETS do
					if not isBlockSolid(blocks, lx + offset[1], ly + offset[2], lz + offset[3]) then
						allSolid = false
						break
					end
				end
				if allSolid then
					continue
				end

				local blockDef = BlockRegistry.get(blockTypeId)
				if not blockDef then
					continue
				end

				-- Calculate world position (with world offset)
				local worldPos = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz) + WORLD_OFFSET

				-- Create the block part
				local part = acquirePart()
				part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
				part.Color = blockDef.color
				part.Material = blockDef.material
				part.Transparency = blockDef.transparency

				-- Shape handling
				if blockDef.shape == "Ball" then
					part.Shape = Enum.PartType.Ball
				elseif blockDef.shape == "Cylinder" then
					part.Shape = Enum.PartType.Cylinder
				else
					part.Shape = Enum.PartType.Block
				end

				-- FACETED SURFACE: slight random rotation on surface blocks
				local isSurface = isSurfaceBlock(blocks, lx, ly, lz)
				if isSurface and blockDef.shape == "Block" then
					-- Deterministic random rotation 1-3 degrees per axis
					local hash1 = posHash(lx + cx * CHUNK_SIZE, ly + cy * CHUNK_SIZE, lz + cz * CHUNK_SIZE, 111)
					local hash2 = posHash(lx + cx * CHUNK_SIZE, ly + cy * CHUNK_SIZE, lz + cz * CHUNK_SIZE, 222)
					local hash3 = posHash(lx + cx * CHUNK_SIZE, ly + cy * CHUNK_SIZE, lz + cz * CHUNK_SIZE, 333)

					local rotX = (hash1 - 0.5) * 6 -- -3 to +3 degrees
					local rotY = (hash2 - 0.5) * 6
					local rotZ = (hash3 - 0.5) * 6

					part.CFrame = CFrame.new(worldPos) * CFrame.Angles(math.rad(rotX), math.rad(rotY), math.rad(rotZ))
				else
					part.CFrame = CFrame.new(worldPos)
				end

				-- Store metadata for mining raycasts
				part:SetAttribute("ChunkKey", key)
				part:SetAttribute("FlatIndex", index)
				part.Name = "Block_" .. index
				part.Parent = folder

				-- FACETED SURFACE: wedge fold caps on surface edges
				if isSurface and blockDef.shape == "Block" then
					local exposedFaces = hasExposedHorizontalFace(blocks, lx, ly, lz)
					for _, offset in exposedFaces do
						-- 50% chance, seeded by position + direction
						local dirSeed = offset[1] * 100 + offset[3] * 200
						local capHash =
							posHash(lx + cx * CHUNK_SIZE, ly + cy * CHUNK_SIZE, lz + cz * CHUNK_SIZE, 444 + dirSeed)
						if capHash < 0.5 then
							local wedge = acquireWedge()
							wedge.Size = Vector3.new(BLOCK_SIZE, 1, BLOCK_SIZE)
							wedge.Color = darkenColor(blockDef.color, 0.08)
							wedge.Material = blockDef.material
							wedge.Transparency = blockDef.transparency

							-- Position on top edge of the exposed face
							local wedgePos = worldPos + Vector3.new(0, BLOCK_SIZE / 2 + 0.5, 0)

							-- Rotate wedge to face the exposed direction
							local angle = 0
							if offset[1] == 1 then
								angle = math.rad(-90)
							elseif offset[1] == -1 then
								angle = math.rad(90)
							elseif offset[3] == 1 then
								angle = math.rad(0)
							elseif offset[3] == -1 then
								angle = math.rad(180)
							end

							wedge.CFrame = CFrame.new(wedgePos) * CFrame.Angles(0, angle, 0)
							wedge:SetAttribute("ChunkKey", key)
							wedge:SetAttribute("FoldCap", true)
							wedge.Name = "FoldCap_" .. index .. "_" .. offset[1] .. "_" .. offset[3]
							wedge.Parent = folder
						end
					end
				end
			end
		end
	end

	-- Parent to MiningWorld
	local miningWorld = workspace:FindFirstChild("MiningWorld")
	if miningWorld then
		folder.Parent = miningWorld
	end

	chunkFolders[key] = folder
end

function ChunkRenderController:_unloadChunk(key: string)
	local folder = chunkFolders[key]
	if not folder then
		return
	end

	-- Return parts to pool
	for _, child in folder:GetChildren() do
		if child:IsA("WedgePart") then
			releaseWedge(child :: WedgePart)
		elseif child:IsA("Part") then
			releasePart(child :: Part)
		else
			child:Destroy()
		end
	end

	folder:Destroy()
	chunkFolders[key] = nil
	chunkBlocks[key] = nil
end

function ChunkRenderController:_updateBlock(
	cx: number,
	cy: number,
	cz: number,
	lx: number,
	ly: number,
	lz: number,
	newBlockType: number
)
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	local folder = chunkFolders[key]
	local blocks = chunkBlocks[key]
	if not folder or not blocks then
		return
	end

	local index = ChunkUtil.flatIndex(lx, ly, lz)

	-- Update local block data
	buffer.writeu8(blocks, index, newBlockType)

	-- Remove existing part for this block
	local partName = "Block_" .. index
	local existing = folder:FindFirstChild(partName)
	if existing and existing:IsA("Part") then
		releasePart(existing :: Part)
	end

	-- Remove associated fold caps
	for _, child in folder:GetChildren() do
		if child:IsA("WedgePart") and child.Name:find("FoldCap_" .. index .. "_") then
			releaseWedge(child :: WedgePart)
		end
	end

	-- If block was set to air, neighboring blocks may now be visible
	-- For simplicity, we don't re-render neighbors here; they will show
	-- when the chunk is next fully re-rendered. The broken block is removed instantly.
end

return ChunkRenderController
