--!strict
--[[
	RegionConfig — locked spatial layout for the Zone System (Phase 2).

	Hearth: circular safe zone at world origin, radius 240 studs.
	Regions: 12 slots equidistant on a ring of radius 4000 studs (angles i*30°
	         for i = 0..11), each slot a 2000x2000 stud square. Players claim
	         one slot on first join.
	Wilds: everything else inside the world boundary.
]]

local RegionConfig = {}

RegionConfig.HEARTH_CX = 0
RegionConfig.HEARTH_CZ = 0
RegionConfig.HEARTH_RADIUS = 240
RegionConfig.HEARTH_RADIUS_SQ = RegionConfig.HEARTH_RADIUS * RegionConfig.HEARTH_RADIUS

RegionConfig.SLOT_COUNT = 12
RegionConfig.SLOT_RING_RADIUS = 4000
-- 720-stud half-edge = 1440-stud (18x18-chunk) slots. Sized so the twelve
-- axis-aligned slots on the ring are DISJOINT — at the old 1000 (2000-stud
-- squares) adjacent slots overlapped diagonally (min center max(|dx|,|dz|)
-- across pairs is ~1464 studs, so 2*halfEdge must be <= that). Disjoint slots
-- are required for portable per-player region content: a chunk must belong to
-- exactly one slot or two players' builds would collide. 720 is also the
-- largest whole-chunk half-edge that fits, and keeps slots off the island
-- falloff void that the old 2000-squares' far corners hung over.
RegionConfig.SLOT_HALF_EDGE = 720
RegionConfig.SLOT_ANGLE_STEP_RAD = math.pi * 2 / RegionConfig.SLOT_COUNT

-- Slot footprint in whole chunks (18). Used for portable content coordinate
-- mapping; CHUNK_STUDS inlined below to avoid a require cycle with ChunkUtil.
RegionConfig.SLOT_CHUNK_SPAN = math.floor((RegionConfig.SLOT_HALF_EDGE * 2) / 80)
RegionConfig.SLOT_CHUNK_HALF = math.floor(RegionConfig.SLOT_CHUNK_SPAN / 2)

export type SlotCenter = { x: number, z: number }

RegionConfig.SLOT_CENTERS = {} :: { SlotCenter }
for i = 0, RegionConfig.SLOT_COUNT - 1 do
	local angle = i * RegionConfig.SLOT_ANGLE_STEP_RAD
	table.insert(RegionConfig.SLOT_CENTERS, {
		x = RegionConfig.SLOT_RING_RADIUS * math.cos(angle),
		z = RegionConfig.SLOT_RING_RADIUS * math.sin(angle),
	})
end

function RegionConfig.formatSlotId(i: number): string
	return string.format("r:%d", i)
end

function RegionConfig.parseSlotId(slotId: string): number?
	local n = tonumber(string.match(slotId, "^r:(%d+)$"))
	if n == nil then
		return nil
	end
	if n < 0 or n >= RegionConfig.SLOT_COUNT then
		return nil
	end
	return n
end

function RegionConfig.getSlotCenter(slotId: string): SlotCenter?
	local i = RegionConfig.parseSlotId(slotId)
	if i == nil then
		return nil
	end
	return RegionConfig.SLOT_CENTERS[i + 1]
end

function RegionConfig.getRegionAtPosition(wx: number, wz: number): string?
	local half = RegionConfig.SLOT_HALF_EDGE
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local center = RegionConfig.SLOT_CENTERS[i + 1]
		if math.abs(wx - center.x) <= half and math.abs(wz - center.z) <= half then
			return RegionConfig.formatSlotId(i)
		end
	end
	return nil
end

-- ── Portable-region coordinate mapping ─────────────────────────────────────
-- A region's CONTENT is stored per-player in LOCAL coordinates (relative to
-- the slot's min XZ corner) so the same build renders identically in any of
-- the 12 display slots. Slots are full vertical columns, so Y (cy) is global
-- and never rebased — only XZ shifts between local and world.

local CHUNK_STUDS = 80 -- ChunkUtil.CHUNK_STUDS; inlined to avoid a require cycle

-- Min XZ corner of a slot, in CHUNK coordinates. localChunk (0,0) maps here.
-- The SLOT_CHUNK_SPAN footprint is CENTERED on the chunk nearest the slot
-- center (round, not floor) so every slot has an IDENTICAL footprint shape —
-- essential for portability: a build saved as local deltas must render into
-- any slot the same way. Verified disjoint + round-trip-consistent + aligned
-- with the stud-AABB permission zones for the 12-slot R=4000 layout.
function RegionConfig.getSlotMinChunk(slotId: string): (number?, number?)
	local i = RegionConfig.parseSlotId(slotId)
	if i == nil then
		return nil, nil
	end
	local center = RegionConfig.SLOT_CENTERS[i + 1]
	local minCx = math.floor(center.x / CHUNK_STUDS + 0.5) - RegionConfig.SLOT_CHUNK_HALF
	local minCz = math.floor(center.z / CHUNK_STUDS + 0.5) - RegionConfig.SLOT_CHUNK_HALF
	return minCx, minCz
end

-- World chunk (cx, cz) -> local chunk offset within slotId. Returns nil if the
-- chunk lies outside the slot's footprint.
function RegionConfig.worldChunkToLocal(slotId: string, cx: number, cz: number): (number?, number?)
	local minCx, minCz = RegionConfig.getSlotMinChunk(slotId)
	if minCx == nil or minCz == nil then
		return nil, nil
	end
	local lcx = cx - minCx
	local lcz = cz - minCz
	local span = RegionConfig.SLOT_CHUNK_SPAN
	if lcx < 0 or lcz < 0 or lcx >= span or lcz >= span then
		return nil, nil
	end
	return lcx, lcz
end

-- Local chunk offset -> world chunk (cx, cz) for a given slot.
function RegionConfig.localChunkToWorld(slotId: string, lcx: number, lcz: number): (number?, number?)
	local minCx, minCz = RegionConfig.getSlotMinChunk(slotId)
	if minCx == nil or minCz == nil then
		return nil, nil
	end
	return minCx + lcx, minCz + lcz
end

-- Authoritative chunk->slot membership for portable content (disjoint, so at
-- most one slot ever owns a chunk). This is the chunk-grid analogue of
-- getRegionAtPosition and agrees with it across the whole footprint.
function RegionConfig.getRegionChunkSlot(cx: number, cz: number): string?
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local slotId = RegionConfig.formatSlotId(i)
		local lcx, lcz = RegionConfig.worldChunkToLocal(slotId, cx, cz)
		if lcx ~= nil and lcz ~= nil then
			return slotId
		end
	end
	return nil
end

return RegionConfig
