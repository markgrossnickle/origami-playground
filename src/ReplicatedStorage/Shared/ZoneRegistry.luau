--!strict
--[[
	ZoneRegistry — classifies a world position into one of three zones.
	Phase 1 stub returns "wilds" everywhere. Phase 4 implements spatial logic.
]]

local ZoneRegistry = {}

export type Zone = "hearth" | "regions" | "wilds"

ZoneRegistry.OreMultipliers = {
	wilds = 1.0,
	regions = 0.1,
	hearth = 0.0,
} :: { [string]: number }

function ZoneRegistry.getZone(_wx: number, _wz: number): Zone
	return "wilds"
end

function ZoneRegistry.getOreMultiplier(wx: number, wz: number): number
	local zone = ZoneRegistry.getZone(wx, wz)
	return ZoneRegistry.OreMultipliers[zone] or 1.0
end

return ZoneRegistry
