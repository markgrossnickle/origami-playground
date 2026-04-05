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

-- NOTE: The Venus fly trap tree is now a voxel structure in WorldGenModule (structureType = "fly_trap").
-- It spawns naturally via the mixed structure system alongside trees, cacti, and bonsai.

return WorldDecorModels
