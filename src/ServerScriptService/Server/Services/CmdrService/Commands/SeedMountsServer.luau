local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Pre-built mountable creatures, one for each locomotion type.
-- All sized ~5+ studs tall so they pass MountConfig.MIN_RIDE_HEIGHT without heavy scaling.
-- IMPORTANT: OrigamiBuilder flips models 180° around Y at build time (LLM +Z → Roblox -Z).
-- So in raw data, the HEAD must be at +Z (positive Z) and tail at -Z. Front legs at +Z, back at -Z.
-- Animation field is "none" — locomotion drives per-part leg/tail animation via name prefixes,
-- and idle_bob would override Position every frame and clip walking creatures into the ground.

local function horse()
	return {
		name = "Paper Steed",
		category = "creature",
		locomotion = "walk",
		animation = "none",
		parts = {
			{
				name = "seg_1",
				shape = "Block",
				position = { 0, 3.5, 0 },
				size = { 3, 2.5, 6 },
				color = { 140, 90, 55 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_2",
				shape = "Block",
				position = { 0, 5, 2.8 },
				size = { 1.8, 2.5, 1.8 },
				orientation = { 15, 0, 0 },
				color = { 150, 100, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_3",
				shape = "Block",
				position = { 0, 6, 4 },
				size = { 2, 1.8, 2.5 },
				color = { 160, 110, 65 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_FL_1",
				shape = "Block",
				position = { -1, 1.5, 2 },
				size = { 0.9, 3, 0.9 },
				color = { 120, 75, 40 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_FR_1",
				shape = "Block",
				position = { 1, 1.5, 2 },
				size = { 0.9, 3, 0.9 },
				color = { 120, 75, 40 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_BL_1",
				shape = "Block",
				position = { -1, 1.5, -2 },
				size = { 0.9, 3, 0.9 },
				color = { 120, 75, 40 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_BR_1",
				shape = "Block",
				position = { 1, 1.5, -2 },
				size = { 0.9, 3, 0.9 },
				color = { 120, 75, 40 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_1",
				shape = "Block",
				position = { 0, 4, -3.5 },
				size = { 0.5, 0.5, 2.5 },
				color = { 100, 60, 30 },
				material = "SmoothPlastic",
			},
		},
	}
end

local function dragon()
	return {
		name = "Paper Dragon",
		category = "creature",
		locomotion = "fly",
		animation = "none",
		parts = {
			{
				name = "seg_1",
				shape = "Block",
				position = { 0, 4, 0 },
				size = { 3, 2, 5 },
				color = { 200, 50, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_2",
				shape = "Block",
				position = { 0, 5, 3 },
				size = { 1.6, 1.6, 2 },
				orientation = { 20, 0, 0 },
				color = { 215, 60, 70 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_3",
				shape = "Block",
				position = { 0, 5.6, 4.3 },
				size = { 2, 1.6, 2 },
				color = { 230, 70, 75 },
				material = "SmoothPlastic",
			},
			{
				name = "wing_L_1",
				shape = "Block",
				position = { -3.5, 5, 0 },
				size = { 5, 0.3, 3 },
				orientation = { 0, 0, 18 },
				color = { 220, 100, 100 },
				material = "SmoothPlastic",
			},
			{
				name = "wing_R_1",
				shape = "Block",
				position = { 3.5, 5, 0 },
				size = { 5, 0.3, 3 },
				orientation = { 0, 0, -18 },
				color = { 220, 100, 100 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_1",
				shape = "Block",
				position = { 0, 4, -3.5 },
				size = { 0.8, 0.8, 3 },
				color = { 180, 40, 50 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_FL_1",
				shape = "Block",
				position = { -1, 2, 1.5 },
				size = { 0.7, 2, 0.7 },
				color = { 180, 40, 50 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_FR_1",
				shape = "Block",
				position = { 1, 2, 1.5 },
				size = { 0.7, 2, 0.7 },
				color = { 180, 40, 50 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_BL_1",
				shape = "Block",
				position = { -1, 2, -1.5 },
				size = { 0.7, 2, 0.7 },
				color = { 180, 40, 50 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_BR_1",
				shape = "Block",
				position = { 1, 2, -1.5 },
				size = { 0.7, 2, 0.7 },
				color = { 180, 40, 50 },
				material = "SmoothPlastic",
			},
		},
	}
end

local function rabbit()
	return {
		name = "Paper Hopper",
		category = "creature",
		locomotion = "hop",
		animation = "none",
		parts = {
			{
				name = "seg_1",
				shape = "Block",
				position = { 0, 3, 0 },
				size = { 2.5, 2.5, 3 },
				color = { 240, 240, 235 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_2",
				shape = "Block",
				position = { 0, 4.5, 1.8 },
				size = { 2.2, 2, 2 },
				color = { 250, 250, 245 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_3",
				shape = "Block",
				position = { -0.7, 6.2, 1.8 },
				size = { 0.5, 2, 0.6 },
				orientation = { 0, 0, -8 },
				color = { 255, 210, 200 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_4",
				shape = "Block",
				position = { 0.7, 6.2, 1.8 },
				size = { 0.5, 2, 0.6 },
				orientation = { 0, 0, 8 },
				color = { 255, 210, 200 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_FL_1",
				shape = "Block",
				position = { -0.9, 1.2, 0.8 },
				size = { 0.7, 1.5, 0.9 },
				color = { 230, 230, 225 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_FR_1",
				shape = "Block",
				position = { 0.9, 1.2, 0.8 },
				size = { 0.7, 1.5, 0.9 },
				color = { 230, 230, 225 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_BL_1",
				shape = "Block",
				position = { -0.9, 1.6, -1 },
				size = { 0.9, 2.3, 1.3 },
				color = { 230, 230, 225 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_BR_1",
				shape = "Block",
				position = { 0.9, 1.6, -1 },
				size = { 0.9, 2.3, 1.3 },
				color = { 230, 230, 225 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_1",
				shape = "Ball",
				position = { 0, 3, -1.8 },
				size = { 0.8, 0.8, 0.8 },
				color = { 255, 255, 250 },
				material = "SmoothPlastic",
			},
		},
	}
end

local function snake()
	return {
		name = "Paper Serpent",
		category = "creature",
		locomotion = "slither",
		animation = "none",
		parts = {
			{
				name = "seg_1",
				shape = "Block",
				position = { 0, 2, 3 },
				size = { 2, 1.8, 2.2 },
				color = { 80, 170, 70 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_2",
				shape = "Block",
				position = { 0, 2, 1 },
				size = { 1.8, 1.8, 2 },
				color = { 90, 180, 80 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_3",
				shape = "Block",
				position = { 0, 2, -1 },
				size = { 1.8, 1.8, 2 },
				color = { 100, 190, 90 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_4",
				shape = "Block",
				position = { 0, 2, -3 },
				size = { 1.6, 1.6, 2 },
				color = { 110, 200, 100 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_5",
				shape = "Block",
				position = { 0, 2, -5 },
				size = { 1.3, 1.3, 2 },
				color = { 90, 180, 80 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_1",
				shape = "Block",
				position = { 0, 2, -6.5 },
				size = { 0.8, 0.8, 1.2 },
				color = { 70, 160, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "jaw_1",
				shape = "Wedge",
				position = { 0, 2.6, 4 },
				size = { 1.6, 0.6, 1.3 },
				color = { 60, 150, 50 },
				material = "SmoothPlastic",
			},
		},
	}
end

local function jellyfish()
	return {
		name = "Paper Drifter",
		category = "creature",
		locomotion = "float",
		animation = "none",
		parts = {
			{
				name = "seg_1",
				shape = "Ball",
				position = { 0, 5, 0 },
				size = { 5, 4, 5 },
				color = { 180, 150, 230 },
				material = "Neon",
				transparency = 0.2,
			},
			{
				name = "seg_2",
				shape = "Ball",
				position = { 0, 6, 0 },
				size = { 4, 2.5, 4 },
				color = { 210, 180, 250 },
				material = "Neon",
				transparency = 0.3,
			},
			{
				name = "tail_1",
				shape = "Block",
				position = { -1.5, 2.5, 1.5 },
				size = { 0.4, 3, 0.4 },
				color = { 160, 120, 220 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_2",
				shape = "Block",
				position = { 1.5, 2.5, 1.5 },
				size = { 0.4, 3, 0.4 },
				color = { 160, 120, 220 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_3",
				shape = "Block",
				position = { -1.5, 2.5, -1.5 },
				size = { 0.4, 3, 0.4 },
				color = { 160, 120, 220 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_4",
				shape = "Block",
				position = { 1.5, 2.5, -1.5 },
				size = { 0.4, 3, 0.4 },
				color = { 160, 120, 220 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_5",
				shape = "Block",
				position = { 0, 2, 0 },
				size = { 0.4, 4, 0.4 },
				color = { 140, 100, 210 },
				material = "SmoothPlastic",
			},
		},
	}
end

local SEED_CREATURES = {
	{ model = horse(), rarity = "Common", stats = { hp = 80, atk = 10, def = 8, spd = 60 } },
	{ model = dragon(), rarity = "Rare", stats = { hp = 90, atk = 14, def = 6, spd = 80 } },
	{ model = rabbit(), rarity = "Common", stats = { hp = 60, atk = 7, def = 5, spd = 70 } },
	{ model = snake(), rarity = "Uncommon", stats = { hp = 70, atk = 11, def = 6, spd = 50 } },
	{ model = jellyfish(), rarity = "Uncommon", stats = { hp = 65, atk = 6, def = 10, spd = 30 } },
}

return function(_context, player)
	local CreatureService = Knit.GetService("CreatureService")
	local added = 0
	for _, seed in ipairs(SEED_CREATURES) do
		local ok, err = pcall(function()
			CreatureService:AddCreature(player, {
				name = seed.model.name,
				modelData = seed.model,
				rarity = seed.rarity,
				stats = seed.stats,
				source = "crafted",
			})
		end)
		if ok then
			added += 1
		else
			warn("[seedmounts] failed to add", seed.model.name, "—", err)
		end
	end
	return string.format("Gave %d mountable creatures to %s.", added, player.Name)
end
