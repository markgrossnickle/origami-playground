--!strict
--[[
	RegionTints — per-slot color multipliers applied at chunk render time so
	each Region has a subtle visual identity.

	Auto-assigns 12 deterministic pastel hues evenly around the color wheel
	(30° apart), pre-baked as multipliers biased toward white so the effect
	reads as "the light here is faintly warm/cool" rather than "the paper is
	now red." Strength is a single dial (TINT_STRENGTH).

	Customization (per-owner override stored in DataStore) is a planned
	follow-up; the API is shaped so a future SetSlotTint(slotId, color) and
	a replicated overrides table slot in here without touching the
	ChunkRenderController call sites.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

local RegionTints = {}

-- 0 = neutral white, 1 = full pastel; keep this small so rocks underground
-- don't look like they're under a coloured spotlight. ~0.12 is enough to
-- distinguish neighbouring regions on the surface but doesn't shout.
local TINT_STRENGTH = 0.12

local DEFAULT_TINTS: { Color3 } = {}

for i = 0, RegionConfig.SLOT_COUNT - 1 do
	local hue = i / RegionConfig.SLOT_COUNT
	-- Saturation 0.6 / value 1.0 → vivid pastel, then we lerp it back toward
	-- white by (1 - TINT_STRENGTH) so we get a gentle multiplier. Pre-baking
	-- the lerp here means the per-block path is one Color3.new + 3 floats.
	local pastel = Color3.fromHSV(hue, 0.6, 1.0)
	local r = (1 - TINT_STRENGTH) + TINT_STRENGTH * pastel.R
	local g = (1 - TINT_STRENGTH) + TINT_STRENGTH * pastel.G
	local b = (1 - TINT_STRENGTH) + TINT_STRENGTH * pastel.B
	table.insert(DEFAULT_TINTS, Color3.new(r, g, b))
end

-- Per-slot override placeholder. Stays empty until customization lands;
-- getMultiplierForSlot prefers an override over the default when present.
local _overrides: { [string]: Color3 } = {}

function RegionTints.getMultiplierForSlot(slotId: string): Color3?
	local override = _overrides[slotId]
	if override then
		return override
	end
	local idx = RegionConfig.parseSlotId(slotId)
	if idx == nil then
		return nil
	end
	return DEFAULT_TINTS[idx + 1]
end

function RegionTints.getMultiplierAtPosition(wx: number, wz: number): Color3?
	local slotId = RegionConfig.getRegionAtPosition(wx, wz)
	if slotId == nil then
		return nil
	end
	return RegionTints.getMultiplierForSlot(slotId)
end

-- Future customization hook. Server-side will validate (must be the slot's
-- owner) and persist; replication mechanism TBD. This signature exists so
-- callers don't have to change once that lands.
function RegionTints.setOverrideForSlot(slotId: string, multiplier: Color3?)
	if multiplier == nil then
		_overrides[slotId] = nil
		return
	end
	_overrides[slotId] = multiplier
end

function RegionTints.getStrength(): number
	return TINT_STRENGTH
end

return RegionTints
