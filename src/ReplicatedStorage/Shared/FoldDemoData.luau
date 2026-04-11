--[[
	FoldDemoData — hardcoded test model definitions for the `testfold` Cmdr command.
	Shapes match the OrigamiBuilder JSON format so each entry can be passed directly
	to OrigamiBuilder.BuildModel.
]]

local FoldDemoData = {}

FoldDemoData.Demos = {
	cube = {
		name = "CubeAnimal",
		category = "creature",
		parts = {
			{
				name = "seg_1",
				shape = "Block",
				position = { 0, 0, 0 },
				size = { 2, 2, 2 },
				orientation = { 0, 0, 0 },
				color = { 220, 90, 80 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_2",
				shape = "Block",
				position = { 0, 2.2, 0 },
				size = { 1.6, 1.6, 1.6 },
				orientation = { 0, 0, 0 },
				color = { 240, 180, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_FL_1",
				shape = "Block",
				position = { -0.8, -1.2, 0.8 },
				size = { 0.4, 1, 0.4 },
				orientation = { 0, 0, 0 },
				color = { 180, 70, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_FR_1",
				shape = "Block",
				position = { 0.8, -1.2, 0.8 },
				size = { 0.4, 1, 0.4 },
				orientation = { 0, 0, 0 },
				color = { 180, 70, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_BL_1",
				shape = "Block",
				position = { -0.8, -1.2, -0.8 },
				size = { 0.4, 1, 0.4 },
				orientation = { 0, 0, 0 },
				color = { 180, 70, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "leg_BR_1",
				shape = "Block",
				position = { 0.8, -1.2, -0.8 },
				size = { 0.4, 1, 0.4 },
				orientation = { 0, 0, 0 },
				color = { 180, 70, 60 },
				material = "SmoothPlastic",
			},
		},
	},

	bird = {
		name = "PaperBird",
		category = "creature",
		parts = {
			{
				name = "seg_1",
				shape = "Block",
				position = { 0, 0, 0 },
				size = { 1.4, 1.2, 2.2 },
				orientation = { 0, 0, 0 },
				color = { 250, 240, 210 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_2",
				shape = "Wedge",
				position = { 0, 0.4, 1.6 },
				size = { 0.8, 0.8, 1.2 },
				orientation = { 0, 0, 0 },
				color = { 250, 200, 80 },
				material = "SmoothPlastic",
			},
			{
				name = "wing_L_1",
				shape = "Wedge",
				position = { -1.4, 0.2, 0 },
				size = { 0.1, 1.2, 2 },
				orientation = { 0, 0, 15 },
				color = { 240, 220, 180 },
				material = "SmoothPlastic",
			},
			{
				name = "wing_R_1",
				shape = "Wedge",
				position = { 1.4, 0.2, 0 },
				size = { 0.1, 1.2, 2 },
				orientation = { 0, 180, -15 },
				color = { 240, 220, 180 },
				material = "SmoothPlastic",
			},
			{
				name = "tail_1",
				shape = "Wedge",
				position = { 0, 0.2, -1.4 },
				size = { 0.8, 0.6, 1 },
				orientation = { 0, 180, 0 },
				color = { 220, 180, 140 },
				material = "SmoothPlastic",
			},
		},
	},

	snake = {
		name = "PaperSnake",
		category = "creature",
		parts = {
			{
				name = "seg_1",
				shape = "Ball",
				position = { 0, 0, 1.4 },
				size = { 1.2, 1.2, 1.2 },
				orientation = { 0, 0, 0 },
				color = { 90, 180, 90 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_2",
				shape = "Ball",
				position = { 0, 0, 0.6 },
				size = { 1, 1, 1 },
				orientation = { 0, 0, 0 },
				color = { 100, 200, 100 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_3",
				shape = "Ball",
				position = { 0, 0, -0.2 },
				size = { 0.9, 0.9, 0.9 },
				orientation = { 0, 0, 0 },
				color = { 110, 210, 110 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_4",
				shape = "Ball",
				position = { 0, 0, -1 },
				size = { 0.8, 0.8, 0.8 },
				orientation = { 0, 0, 0 },
				color = { 120, 220, 120 },
				material = "SmoothPlastic",
			},
			{
				name = "seg_5",
				shape = "Ball",
				position = { 0, 0, -1.7 },
				size = { 0.6, 0.6, 0.6 },
				orientation = { 0, 0, 0 },
				color = { 130, 230, 130 },
				material = "SmoothPlastic",
			},
		},
	},

	tower = {
		name = "PaperTower",
		category = "building",
		parts = {
			{
				name = "base",
				shape = "Block",
				position = { 0, 0, 0 },
				size = { 4, 1, 4 },
				orientation = { 0, 0, 0 },
				color = { 200, 170, 120 },
				material = "SmoothPlastic",
			},
			{
				name = "mid",
				shape = "Block",
				position = { 0, 1.6, 0 },
				size = { 3, 2.2, 3 },
				orientation = { 0, 0, 0 },
				color = { 220, 190, 140 },
				material = "SmoothPlastic",
			},
			{
				name = "top",
				shape = "Block",
				position = { 0, 3.6, 0 },
				size = { 2, 1.6, 2 },
				orientation = { 0, 0, 0 },
				color = { 240, 210, 160 },
				material = "SmoothPlastic",
			},
			{
				name = "roof",
				shape = "Wedge",
				position = { 0, 5.2, 0 },
				size = { 2, 1.4, 2 },
				orientation = { 0, 0, 0 },
				color = { 200, 60, 60 },
				material = "SmoothPlastic",
			},
		},
	},

	flower = {
		name = "PaperFlower",
		category = "prop",
		parts = {
			{
				name = "stem",
				shape = "Cylinder",
				position = { 0, 0, 0 },
				size = { 3, 0.3, 0.3 },
				orientation = { 0, 0, 90 },
				color = { 60, 160, 60 },
				material = "SmoothPlastic",
			},
			{
				name = "petal_1",
				shape = "Wedge",
				position = { 0, 2, 0.4 },
				size = { 0.1, 1.2, 1 },
				orientation = { 0, 0, 0 },
				color = { 240, 100, 150 },
				material = "SmoothPlastic",
			},
			{
				name = "petal_2",
				shape = "Wedge",
				position = { 0, 2, -0.4 },
				size = { 0.1, 1.2, 1 },
				orientation = { 0, 180, 0 },
				color = { 240, 120, 170 },
				material = "SmoothPlastic",
			},
			{
				name = "petal_3",
				shape = "Wedge",
				position = { 0.4, 2, 0 },
				size = { 0.1, 1.2, 1 },
				orientation = { 0, 90, 0 },
				color = { 240, 140, 190 },
				material = "SmoothPlastic",
			},
			{
				name = "petal_4",
				shape = "Wedge",
				position = { -0.4, 2, 0 },
				size = { 0.1, 1.2, 1 },
				orientation = { 0, -90, 0 },
				color = { 240, 160, 200 },
				material = "SmoothPlastic",
			},
			{
				name = "center",
				shape = "Ball",
				position = { 0, 2, 0 },
				size = { 0.6, 0.6, 0.6 },
				orientation = { 0, 0, 0 },
				color = { 250, 220, 80 },
				material = "SmoothPlastic",
			},
		},
	},
}

function FoldDemoData.GetNames(): { string }
	local names = {}
	for name in pairs(FoldDemoData.Demos) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return FoldDemoData
