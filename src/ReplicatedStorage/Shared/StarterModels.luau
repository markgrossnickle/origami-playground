--!strict
-- StarterModels: Hardcoded model data for starter content scattered around spawn.
-- Each entry uses the same format as the LLM API response so OrigamiBuilder.BuildModel() works directly.

local StarterModels = {}

export type StarterEntry = {
	modelData: { [string]: any },
	position: { number },
	category: string,
	animation: string?,
}

StarterModels.MODELS = {
	-- ═══════════════════════════════════════
	-- PROPS
	-- ═══════════════════════════════════════

	-- 1. Stone Bench
	{
		category = "prop",
		position = { 8, 0, -12 },
		animation = "none",
		modelData = {
			name = "Stone Bench",
			category = "prop",
			parts = {
				-- Seat
				{
					name = "seat",
					shape = "Block",
					position = { 0, 2, 0 },
					size = { 6, 0.6, 2 },
					orientation = { 0, 0, 0 },
					color = { 160, 160, 160 },
					material = "Concrete",
					transparency = 0,
				},
				-- Left leg
				{
					name = "leg_left",
					shape = "Block",
					position = { -2.2, 0.85, 0 },
					size = { 1, 1.7, 1.8 },
					orientation = { 0, 0, 0 },
					color = { 140, 140, 140 },
					material = "Concrete",
					transparency = 0,
				},
				-- Right leg
				{
					name = "leg_right",
					shape = "Block",
					position = { 2.2, 0.85, 0 },
					size = { 1, 1.7, 1.8 },
					orientation = { 0, 0, 0 },
					color = { 140, 140, 140 },
					material = "Concrete",
					transparency = 0,
				},
			},
		},
	},

	-- ═══════════════════════════════════════
	-- CREATURES
	-- ═══════════════════════════════════════

	-- 4. Paper Crane (flying)
	{
		category = "creature",
		position = { 0, 0, 30 },
		modelData = {
			name = "Paper Crane",
			category = "creature",
			locomotion = "fly",
			animation = "idle_bob",
			parts = {
				-- Body
				{
					name = "seg_1",
					shape = "Block",
					position = { 0, 0, 0 },
					size = { 1.5, 1, 3 },
					orientation = { 0, 0, 0 },
					color = { 255, 80, 80 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Head/neck
				{
					name = "seg_2",
					shape = "Wedge",
					position = { 0, 0.3, 2.2 },
					size = { 0.8, 0.8, 2 },
					orientation = { 0, 0, 0 },
					color = { 255, 100, 100 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Tail
				{
					name = "tail_1",
					shape = "Wedge",
					position = { 0, 0.3, -2 },
					size = { 0.6, 0.6, 1.8 },
					orientation = { 0, 180, 0 },
					color = { 255, 60, 60 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Left wing
				{
					name = "wing_L_1",
					shape = "Block",
					position = { -2.5, 0.2, 0 },
					size = { 3.5, 0.3, 2 },
					orientation = { 0, 0, 10 },
					color = { 255, 120, 120 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Right wing
				{
					name = "wing_R_1",
					shape = "Block",
					position = { 2.5, 0.2, 0 },
					size = { 3.5, 0.3, 2 },
					orientation = { 0, 0, -10 },
					color = { 255, 120, 120 },
					material = "SmoothPlastic",
					transparency = 0,
				},
			},
		},
	},

	-- ═══════════════════════════════════════
	-- VEHICLES (spawned as static props for MVP)
	-- ═══════════════════════════════════════

	-- 6. Paper Boat
	{
		category = "prop",
		position = { 30, 0, 0 },
		animation = "wobble",
		modelData = {
			name = "Paper Boat",
			category = "prop",
			parts = {
				-- Hull bottom
				{
					name = "hull",
					shape = "Wedge",
					position = { 0, 0.5, 0 },
					size = { 3, 1, 6 },
					orientation = { 0, 0, 0 },
					color = { 240, 240, 230 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Left side
				{
					name = "side_left",
					shape = "Block",
					position = { -1.6, 1.2, 0 },
					size = { 0.3, 1, 5.5 },
					orientation = { 0, 0, -10 },
					color = { 230, 230, 220 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Right side
				{
					name = "side_right",
					shape = "Block",
					position = { 1.6, 1.2, 0 },
					size = { 0.3, 1, 5.5 },
					orientation = { 0, 0, 10 },
					color = { 230, 230, 220 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Mast
				{
					name = "mast",
					shape = "Cylinder",
					position = { 0, 3, 0 },
					size = { 0.3, 4, 0.3 },
					orientation = { 0, 0, 0 },
					color = { 180, 140, 80 },
					material = "Wood",
					transparency = 0,
				},
				-- Sail
				{
					name = "sail",
					shape = "Block",
					position = { 0.8, 3.5, 0 },
					size = { 2, 3, 0.15 },
					orientation = { 0, 0, 5 },
					color = { 255, 255, 240 },
					material = "Fabric",
					transparency = 0,
				},
			},
		},
	},

	-- 7. Toy Car
	{
		category = "prop",
		position = { -30, 0, -10 },
		animation = "idle_bob",
		modelData = {
			name = "Toy Car",
			category = "prop",
			parts = {
				-- Body
				{
					name = "body",
					shape = "Block",
					position = { 0, 1, 0 },
					size = { 3, 1.2, 5 },
					orientation = { 0, 0, 0 },
					color = { 200, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Cabin
				{
					name = "cabin",
					shape = "Block",
					position = { 0, 2, -0.3 },
					size = { 2.6, 1.2, 2.5 },
					orientation = { 0, 0, 0 },
					color = { 180, 220, 255 },
					material = "Glass",
					transparency = 0.3,
				},
				-- Front-left wheel
				{
					name = "wheel_fl",
					shape = "Cylinder",
					position = { -1.7, 0.4, 1.5 },
					size = { 0.8, 0.5, 0.8 },
					orientation = { 0, 0, 90 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Front-right wheel
				{
					name = "wheel_fr",
					shape = "Cylinder",
					position = { 1.7, 0.4, 1.5 },
					size = { 0.8, 0.5, 0.8 },
					orientation = { 0, 0, 90 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Rear-left wheel
				{
					name = "wheel_rl",
					shape = "Cylinder",
					position = { -1.7, 0.4, -1.5 },
					size = { 0.8, 0.5, 0.8 },
					orientation = { 0, 0, 90 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Rear-right wheel
				{
					name = "wheel_rr",
					shape = "Cylinder",
					position = { 1.7, 0.4, -1.5 },
					size = { 0.8, 0.5, 0.8 },
					orientation = { 0, 0, 90 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Headlight left
				{
					name = "headlight_l",
					shape = "Cylinder",
					position = { -1, 1, 2.6 },
					size = { 0.5, 0.3, 0.5 },
					orientation = { 90, 0, 0 },
					color = { 255, 255, 200 },
					material = "Neon",
					transparency = 0,
				},
				-- Headlight right
				{
					name = "headlight_r",
					shape = "Cylinder",
					position = { 1, 1, 2.6 },
					size = { 0.5, 0.3, 0.5 },
					orientation = { 90, 0, 0 },
					color = { 255, 255, 200 },
					material = "Neon",
					transparency = 0,
				},
			},
		},
	},
}

return StarterModels
