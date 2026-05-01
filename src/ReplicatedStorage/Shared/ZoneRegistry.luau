--!strict
--[[
	ZoneRegistry — classifies a world (X, Z) position into hearth | regions | wilds.
	Pure spatial logic; no state. Phase 2 implementation backed by RegionConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

local ZoneRegistry = {}

export type Zone = "hearth" | "regions" | "wilds"

ZoneRegistry.OreMultipliers = {
	wilds = 1.0,
	regions = 0.1,
	hearth = 0.0,
} :: { [string]: number }

function ZoneRegistry.getZone(wx: number, wz: number): Zone
	local dx = wx - RegionConfig.HEARTH_CX
	local dz = wz - RegionConfig.HEARTH_CZ
	if dx * dx + dz * dz <= RegionConfig.HEARTH_RADIUS_SQ then
		return "hearth"
	end
	if RegionConfig.getRegionAtPosition(wx, wz) ~= nil then
		return "regions"
	end
	return "wilds"
end

function ZoneRegistry.getRegionAt(wx: number, wz: number): string?
	return RegionConfig.getRegionAtPosition(wx, wz)
end

function ZoneRegistry.getOreMultiplier(wx: number, wz: number): number
	local zone = ZoneRegistry.getZone(wx, wz)
	return ZoneRegistry.OreMultipliers[zone] or 1.0
end

return ZoneRegistry
