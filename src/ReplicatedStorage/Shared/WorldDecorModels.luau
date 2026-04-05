--[[
	WorldDecorModels — hand-crafted origami modelData for world decorations.
	Uses OrigamiBuilder part format + CreatureAI animation naming conventions
	(jaw_ = snap, wing_L/R = flap, tail_ = sway, seg_ = bob, leg_ = wiggle).
]]

local WorldDecorModels = {}

-- Small stationary Venus fly trap creature (~4 studs tall)
-- Paper origami carnivorous plant: snapping jaw, swaying leaves, curling tendrils
WorldDecorModels.VenusFlyTrap = {
	name = "Paper Venus Fly Trap",
	category = "creature",
	locomotion = "stationary",
	description = "A carnivorous paper plant that snaps at passing origami bugs.",
	parts = {
		-- Earthy base pot
		{
			name = "seg_1",
			shape = "Block",
			position = { 0, 0, 0 },
			size = { 2.2, 1.2, 2.2 },
			color = { 140, 100, 60 },
			material = "SmoothPlastic",
		},
		-- Main stem
		{
			name = "seg_2",
			shape = "Block",
			position = { 0, 1.8, 0 },
			size = { 0.7, 2.4, 0.7 },
			color = { 80, 160, 55 },
			material = "SmoothPlastic",
		},
		-- Trap head upper jaw (snaps open/closed)
		{
			name = "jaw_1",
			shape = "Wedge",
			position = { 0, 3.6, 0.6 },
			size = { 1.8, 0.8, 2 },
			color = { 210, 50, 65 },
			material = "SmoothPlastic",
		},
		-- Trap lower lip (static, red interior)
		{
			name = "seg_3",
			shape = "Wedge",
			position = { 0, 3, 0.6 },
			size = { 1.6, 0.6, 1.8 },
			orientation = { 180, 0, 0 },
			color = { 190, 70, 80 },
			material = "SmoothPlastic",
		},
		-- Left leaf (gentle flap)
		{
			name = "wing_L_1",
			shape = "Block",
			position = { -1.6, 1.2, 0 },
			size = { 2.2, 0.2, 1.4 },
			orientation = { 0, 0, 20 },
			color = { 65, 150, 45 },
			material = "SmoothPlastic",
		},
		-- Right leaf
		{
			name = "wing_R_1",
			shape = "Block",
			position = { 1.6, 1.2, 0 },
			size = { 2.2, 0.2, 1.4 },
			orientation = { 0, 0, -20 },
			color = { 65, 150, 45 },
			material = "SmoothPlastic",
		},
		-- Rear tendril (sways)
		{
			name = "tail_1",
			shape = "Block",
			position = { 0, 0.8, -1.4 },
			size = { 0.3, 0.3, 2.2 },
			color = { 55, 135, 38 },
			material = "SmoothPlastic",
		},
		-- Side tendril
		{
			name = "tail_2",
			shape = "Block",
			position = { 0.7, 0.6, -1.6 },
			size = { 0.3, 0.3, 1.6 },
			orientation = { 0, 20, 0 },
			color = { 50, 125, 32 },
			material = "SmoothPlastic",
		},
		-- Tiny white teeth dots on upper jaw
		{
			name = "seg_4",
			shape = "Ball",
			position = { -0.5, 3.5, 1.4 },
			size = { 0.25, 0.25, 0.25 },
			color = { 240, 240, 230 },
			material = "SmoothPlastic",
		},
		{
			name = "seg_5",
			shape = "Ball",
			position = { 0, 3.5, 1.5 },
			size = { 0.25, 0.25, 0.25 },
			color = { 240, 240, 230 },
			material = "SmoothPlastic",
		},
		{
			name = "seg_6",
			shape = "Ball",
			position = { 0.5, 3.5, 1.4 },
			size = { 0.25, 0.25, 0.25 },
			color = { 240, 240, 230 },
			material = "SmoothPlastic",
		},
	},
}

-- Large Venus fly trap tree (~14 studs tall)
-- Animated paper tree with multiple trap heads, creeping roots, broad canopy leaves
WorldDecorModels.VenusFlyTrapTree = {
	name = "Giant Paper Fly Trap Tree",
	category = "prop",
	locomotion = "stationary",
	description = "A towering carnivorous tree of folded paper. Its traps snap lazily in the breeze.",
	parts = {
		-- Thick trunk base
		{
			name = "seg_1",
			shape = "Block",
			position = { 0, 0, 0 },
			size = { 3.5, 4, 3.5 },
			color = { 75, 130, 50 },
			material = "SmoothPlastic",
		},
		-- Trunk middle
		{
			name = "seg_2",
			shape = "Block",
			position = { 0, 4, 0 },
			size = { 2.8, 3.5, 2.8 },
			color = { 85, 140, 55 },
			material = "SmoothPlastic",
		},
		-- Trunk upper
		{
			name = "seg_3",
			shape = "Block",
			position = { 0, 7.5, 0 },
			size = { 2.2, 2.5, 2.2 },
			color = { 95, 155, 60 },
			material = "SmoothPlastic",
		},
		-- Main trap head (large, snapping jaw)
		{
			name = "jaw_1",
			shape = "Wedge",
			position = { 0, 10.5, 1.2 },
			size = { 3.5, 1.5, 4 },
			color = { 210, 45, 55 },
			material = "SmoothPlastic",
		},
		-- Main trap lower lip
		{
			name = "seg_4",
			shape = "Wedge",
			position = { 0, 9.5, 1.2 },
			size = { 3, 1, 3.5 },
			orientation = { 180, 0, 0 },
			color = { 190, 60, 70 },
			material = "SmoothPlastic",
		},
		-- Left canopy branch (flaps gently)
		{
			name = "wing_L_1",
			shape = "Block",
			position = { -3.5, 6, 0 },
			size = { 5, 0.5, 2.5 },
			orientation = { 0, 0, 22 },
			color = { 60, 140, 42 },
			material = "SmoothPlastic",
		},
		-- Right canopy branch
		{
			name = "wing_R_1",
			shape = "Block",
			position = { 3.5, 6, 0 },
			size = { 5, 0.5, 2.5 },
			orientation = { 0, 0, -22 },
			color = { 60, 140, 42 },
			material = "SmoothPlastic",
		},
		-- Left upper leaf
		{
			name = "wing_L_2",
			shape = "Wedge",
			position = { -5, 7, 0.5 },
			size = { 3, 0.3, 2 },
			orientation = { 0, 0, 12 },
			color = { 50, 130, 38 },
			material = "SmoothPlastic",
		},
		-- Right upper leaf
		{
			name = "wing_R_2",
			shape = "Wedge",
			position = { 5, 7, 0.5 },
			size = { 3, 0.3, 2 },
			orientation = { 0, 0, -12 },
			color = { 50, 130, 38 },
			material = "SmoothPlastic",
		},
		-- Hanging vine left (sways)
		{
			name = "tail_1",
			shape = "Block",
			position = { -2, 4, -2.5 },
			size = { 0.4, 0.4, 4 },
			orientation = { 0, 15, 0 },
			color = { 55, 125, 35 },
			material = "SmoothPlastic",
		},
		-- Hanging vine right
		{
			name = "tail_2",
			shape = "Block",
			position = { 2, 3.5, -3 },
			size = { 0.4, 0.4, 3.5 },
			orientation = { 0, -10, 0 },
			color = { 50, 120, 30 },
			material = "SmoothPlastic",
		},
		-- Creeping root front-left (wiggles)
		{
			name = "leg_FL_1",
			shape = "Block",
			position = { -2, -1.5, 1.5 },
			size = { 0.9, 3, 0.9 },
			orientation = { 18, 0, 18 },
			color = { 65, 105, 40 },
			material = "SmoothPlastic",
		},
		-- Creeping root front-right
		{
			name = "leg_FR_1",
			shape = "Block",
			position = { 2, -1.5, 1.5 },
			size = { 0.9, 3, 0.9 },
			orientation = { 18, 0, -18 },
			color = { 65, 105, 40 },
			material = "SmoothPlastic",
		},
		-- Creeping root back-left
		{
			name = "leg_BL_1",
			shape = "Block",
			position = { -2, -1.5, -1.5 },
			size = { 0.9, 3, 0.9 },
			orientation = { -18, 0, 18 },
			color = { 65, 105, 40 },
			material = "SmoothPlastic",
		},
		-- Creeping root back-right
		{
			name = "leg_BR_1",
			shape = "Block",
			position = { 2, -1.5, -1.5 },
			size = { 0.9, 3, 0.9 },
			orientation = { -18, 0, -18 },
			color = { 65, 105, 40 },
			material = "SmoothPlastic",
		},
		-- Trunk moss patches (visual detail)
		{
			name = "seg_5",
			shape = "Block",
			position = { -1.5, 2.5, 1.5 },
			size = { 1, 0.8, 0.3 },
			color = { 45, 110, 30 },
			material = "SmoothPlastic",
		},
		{
			name = "seg_6",
			shape = "Block",
			position = { 1.2, 5, -1.2 },
			size = { 0.8, 1, 0.3 },
			color = { 40, 105, 28 },
			material = "SmoothPlastic",
		},
		-- Teeth on main trap
		{
			name = "seg_7",
			shape = "Ball",
			position = { -1, 10.2, 2.8 },
			size = { 0.35, 0.35, 0.35 },
			color = { 245, 240, 225 },
			material = "SmoothPlastic",
		},
		{
			name = "seg_8",
			shape = "Ball",
			position = { 0, 10.2, 3 },
			size = { 0.35, 0.35, 0.35 },
			color = { 245, 240, 225 },
			material = "SmoothPlastic",
		},
		{
			name = "seg_9",
			shape = "Ball",
			position = { 1, 10.2, 2.8 },
			size = { 0.35, 0.35, 0.35 },
			color = { 245, 240, 225 },
			material = "SmoothPlastic",
		},
	},
}

return WorldDecorModels
