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
RegionConfig.SLOT_HALF_EDGE = 1000
RegionConfig.SLOT_ANGLE_STEP_RAD = math.pi * 2 / RegionConfig.SLOT_COUNT

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

return RegionConfig
