--!strict
-- ChunkRenderController: TRIANGULAR-FOLDS VARIANT
-- Each block = pair of WedgeParts with diagonal crease. Alternating fold pattern.
-- Surface blocks get slight rotation. Ore blocks = single angular wedge crystals.
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
local chunkFolders: { [string]: Folder } = {}
local chunkBlocks: { [string]: buffer } = {}
local MAX_POOL = 8000
local wedgePool: { WedgePart } = {}
local MAX_PART_POOL = 1000
local partPool: { Part } = {}
local NEIGHBORS = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
local function posHash(x: number, y: number, z: number, seed: number): number
	local h = seed + x * 374761393 + y * 668265263 + z * 1274126177
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = h * 1103515245 + 12345
	return (h % 10000) / 10000
end
local function darkenColor(c: Color3, f: number): Color3
	return Color3.new(math.max(0, c.R * (1 - f)), math.max(0, c.G * (1 - f)), math.max(0, c.B * (1 - f)))
end
local function acquireWedge(): WedgePart
	if #wedgePool > 0 then
		local w = table.remove(wedgePool) :: WedgePart
		w.Transparency = 0
		w.CanCollide = true
		return w
	end
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = true
	w.CastShadow = true
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	return w
end
local function releaseWedge(w: WedgePart)
	w.Parent = nil
	if #wedgePool < MAX_POOL then
		table.insert(wedgePool, w)
	else
		w:Destroy()
	end
end
local function acquirePart(): Part
	if #partPool > 0 then
		local pp = table.remove(partPool) :: Part
		pp.Shape = Enum.PartType.Block
		pp.Transparency = 0
		pp.CanCollide = true
		return pp
	end
	local pp = Instance.new("Part")
	pp.Anchored = true
	pp.CanCollide = true
	pp.CastShadow = true
	pp.TopSurface = Enum.SurfaceType.Smooth
	pp.BottomSurface = Enum.SurfaceType.Smooth
	return pp
end
local function releasePart(pp: Part)
	pp.Parent = nil
	if #partPool < MAX_PART_POOL then
		table.insert(partPool, pp)
	else
		pp:Destroy()
	end
end
local function isSolid(blocks: buffer, lx: number, ly: number, lz: number): boolean
	if lx < 0 or lx >= CHUNK_SIZE or ly < 0 or ly >= CHUNK_SIZE or lz < 0 or lz >= CHUNK_SIZE then
		return false
	end
	local bt = buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly, lz))
	return bt ~= BlockType.Air and bt ~= BlockType.Water
end
local function isSurface(blocks: buffer, lx: number, ly: number, lz: number): boolean
	if ly >= CHUNK_SIZE - 1 then
		return true
	end
	local above = buffer.readu8(blocks, ChunkUtil.flatIndex(lx, ly + 1, lz))
	return above == BlockType.Air or above == BlockType.Water
end
function ChunkRenderController:KnitInit() end
function ChunkRenderController:KnitStart()
	local WorldService = Knit.GetService("WorldService")
	if not workspace:FindFirstChild("MiningWorld") then
		local f = Instance.new("Folder")
		f.Name = "MiningWorld"
		f.Parent = workspace
	end
	WorldService.ChunkLoaded:Connect(function(cx: number, cy: number, cz: number, compressed: buffer)
		self:_renderChunk(cx, cy, cz, compressed)
	end)
	WorldService.ChunkUnloaded:Connect(function(cx: number, cy: number, cz: number)
		self:_unloadChunk(ChunkUtil.chunkKey(cx, cy, cz))
	end)
	WorldService.BlockChanged:Connect(
		function(cx: number, cy: number, cz: number, lx: number, ly: number, lz: number, nb: number)
			self:_updateBlock(cx, cy, cz, lx, ly, lz, nb)
		end
	)
end
function ChunkRenderController:_renderChunk(cx: number, cy: number, cz: number, compressed: buffer)
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	if chunkFolders[key] then
		self:_unloadChunk(key)
	end
	local blocks = ChunkSerializer.decompress(compressed)
	chunkBlocks[key] = blocks
	local folder = Instance.new("Folder")
	folder.Name = "Chunk_" .. key
	for ly = 0, CHUNK_SIZE - 1 do
		for lz = 0, CHUNK_SIZE - 1 do
			for lx = 0, CHUNK_SIZE - 1 do
				local idx = ChunkUtil.flatIndex(lx, ly, lz)
				local bid = buffer.readu8(blocks, idx)
				if bid == BlockType.Air then
					continue
				end
				local allSolid = true
				for _, o in NEIGHBORS do
					if not isSolid(blocks, lx + o[1], ly + o[2], lz + o[3]) then
						allSolid = false
						break
					end
				end
				if allSolid then
					continue
				end
				local def = BlockRegistry.get(bid)
				if not def then
					continue
				end
				local wp = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz) + WORLD_OFFSET
				local gx, gy, gz = lx + cx * CHUNK_SIZE, ly + cy * CHUNK_SIZE, lz + cz * CHUNK_SIZE
				if bid == BlockType.Water or bid == BlockType.Bedrock then
					local part = acquirePart()
					part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
					part.Color = def.color
					part.Material = def.material
					part.Transparency = def.transparency
					part.CFrame = CFrame.new(wp)
					part:SetAttribute("ChunkKey", key)
					part:SetAttribute("FlatIndex", idx)
					part.Name = "Block_" .. idx
					if bid == BlockType.Water then
						part.CanCollide = false
					end
					part.Parent = folder
					continue
				end
				if BlockRegistry.isOre(bid) then
					local wedge = acquireWedge()
					wedge.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
					wedge.Color = def.color
					wedge.Material = def.material
					wedge.Transparency = def.transparency
					wedge.CFrame = CFrame.new(wp) * CFrame.Angles(0, math.rad(posHash(gx, gy, gz, 777) * 360), 0)
					wedge:SetAttribute("ChunkKey", key)
					wedge:SetAttribute("FlatIndex", idx)
					wedge.Name = "Block_" .. idx
					wedge.Parent = folder
					continue
				end
				local surf = isSurface(blocks, lx, ly, lz)
				local checker = (gx + gz) % 2
				local wA = acquireWedge()
				wA.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
				wA.Color = def.color
				wA.Material = def.material
				wA.Transparency = def.transparency
				local wB = acquireWedge()
				wB.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
				wB.Color = darkenColor(def.color, 0.05)
				wB.Material = def.material
				wB.Transparency = def.transparency
				local base = CFrame.new(wp)
				local srA, srB = 0, 0
				if surf then
					srA = (posHash(gx, gy, gz, 555) - 0.5) * 5
					srB = (posHash(gx, gy, gz, 666) - 0.5) * 5
				end
				if checker == 0 then
					wA.CFrame = base * CFrame.Angles(0, math.rad(srA), 0)
					wB.CFrame = base * CFrame.Angles(0, math.rad(180 + srB), 0)
				else
					wA.CFrame = base * CFrame.Angles(0, math.rad(90 + srA), 0)
					wB.CFrame = base * CFrame.Angles(0, math.rad(270 + srB), 0)
				end
				wA:SetAttribute("ChunkKey", key)
				wA:SetAttribute("FlatIndex", idx)
				wA.Name = "Block_" .. idx
				wA.Parent = folder
				wB:SetAttribute("ChunkKey", key)
				wB:SetAttribute("FlatIndex", idx)
				wB.Name = "Block_" .. idx .. "B"
				wB.Parent = folder
			end
		end
	end
	local mw = workspace:FindFirstChild("MiningWorld")
	if mw then
		folder.Parent = mw
	end
	chunkFolders[key] = folder
end
function ChunkRenderController:_unloadChunk(key: string)
	local folder = chunkFolders[key]
	if not folder then
		return
	end
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
	newBT: number
)
	local key = ChunkUtil.chunkKey(cx, cy, cz)
	local folder = chunkFolders[key]
	local blocks = chunkBlocks[key]
	if not folder or not blocks then
		return
	end
	local idx = ChunkUtil.flatIndex(lx, ly, lz)
	buffer.writeu8(blocks, idx, newBT)
	local nA = "Block_" .. idx
	local nB = nA .. "B"
	for _, child in folder:GetChildren() do
		if child.Name == nA or child.Name == nB then
			if child:IsA("WedgePart") then
				releaseWedge(child :: WedgePart)
			elseif child:IsA("Part") then
				releasePart(child :: Part)
			end
		end
	end
end
return ChunkRenderController
