-- Pre-built demo models for Demo mode
-- Players type a prompt and if it fuzzy-matches a keyword here, the pre-built model is used
-- instead of calling the LLM API.

local DemoModels = {}

DemoModels.MODELS = {
	-- ═══════════════════════════════════════════════════════════════
	-- VEHICLE: Monster Truck
	-- ═══════════════════════════════════════════════════════════════
	{
		keywords = { "monster truck", "truck", "monster" },
		category = "vehicle",
		modelData = {
			name = "Monster Truck",
			category = "vehicle",
			locomotion = "drive",
			animation = "none",
			parts = {
				-- Chassis body
				{
					name = "chassis",
					shape = "Block",
					position = { 0, 3, 0 },
					size = { 6, 2, 10 },
					rotation = { 0, 0, 0 },
					color = { 200, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Cabin
				{
					name = "cabin",
					shape = "Block",
					position = { 0, 5, -1 },
					size = { 5, 2.5, 5 },
					rotation = { 0, 0, 0 },
					color = { 200, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Windshield
				{
					name = "windshield",
					shape = "Block",
					position = { 0, 5, 1.8 },
					size = { 4.5, 2, 0.3 },
					rotation = { -15, 0, 0 },
					color = { 180, 220, 255 },
					material = "Glass",
					transparency = 0.4,
				},
				-- Front left wheel
				{
					name = "wheel_FL",
					shape = "Cylinder",
					position = { -3.8, 2, 3 },
					size = { 3.5, 3.5, 3.5 },
					rotation = { 0, 0, 90 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Front right wheel
				{
					name = "wheel_FR",
					shape = "Cylinder",
					position = { 3.8, 2, 3 },
					size = { 3.5, 3.5, 3.5 },
					rotation = { 0, 0, 90 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Back left wheel
				{
					name = "wheel_BL",
					shape = "Cylinder",
					position = { -3.8, 2, -4 },
					size = { 3.5, 3.5, 3.5 },
					rotation = { 0, 0, 90 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Back right wheel
				{
					name = "wheel_BR",
					shape = "Cylinder",
					position = { 3.8, 2, -4 },
					size = { 3.5, 3.5, 3.5 },
					rotation = { 0, 0, 90 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Roof rack
				{
					name = "rack",
					shape = "Block",
					position = { 0, 6.5, -1 },
					size = { 4.5, 0.3, 4.5 },
					rotation = { 0, 0, 0 },
					color = { 60, 60, 60 },
					material = "Metal",
					transparency = 0,
				},
				-- Headlight left
				{
					name = "headlight_L",
					shape = "Ball",
					position = { -2, 3.5, 5 },
					size = { 1, 1, 0.5 },
					rotation = { 0, 0, 0 },
					color = { 255, 255, 200 },
					material = "Neon",
					transparency = 0,
				},
				-- Headlight right
				{
					name = "headlight_R",
					shape = "Ball",
					position = { 2, 3.5, 5 },
					size = { 1, 1, 0.5 },
					rotation = { 0, 0, 0 },
					color = { 255, 255, 200 },
					material = "Neon",
					transparency = 0,
				},
				-- Bumper
				{
					name = "bumper",
					shape = "Block",
					position = { 0, 2.2, 5.3 },
					size = { 6.5, 1.2, 0.5 },
					rotation = { 0, 0, 0 },
					color = { 80, 80, 80 },
					material = "Metal",
					transparency = 0,
				},
				-- Exhaust pipes
				{
					name = "exhaust_L",
					shape = "Cylinder",
					position = { -2.5, 4, -5.2 },
					size = { 3, 0.8, 0.8 },
					rotation = { 90, 0, 0 },
					color = { 100, 100, 100 },
					material = "Metal",
					transparency = 0,
				},
				{
					name = "exhaust_R",
					shape = "Cylinder",
					position = { 2.5, 4, -5.2 },
					size = { 3, 0.8, 0.8 },
					rotation = { 90, 0, 0 },
					color = { 100, 100, 100 },
					material = "Metal",
					transparency = 0,
				},
			},
		},
	},

	-- ═══════════════════════════════════════════════════════════════
	-- PROP: Trampoline
	-- ═══════════════════════════════════════════════════════════════
	{
		keywords = { "trampoline", "bouncy", "bounce pad" },
		category = "prop",
		modelData = {
			name = "Trampoline",
			category = "prop",
			animation = "breathe",
			parts = {
				-- Base ring
				{
					name = "ring_base",
					shape = "Cylinder",
					position = { 0, 1, 0 },
					size = { 1, 10, 10 },
					rotation = { 0, 0, 0 },
					color = { 50, 50, 60 },
					material = "Metal",
					transparency = 0,
				},
				-- Bounce surface
				{
					name = "surface",
					shape = "Cylinder",
					position = { 0, 1.6, 0 },
					size = { 0.3, 9, 9 },
					rotation = { 0, 0, 0 },
					color = { 30, 30, 30 },
					material = "Fabric",
					transparency = 0,
				},
				-- Leg front-left
				{
					name = "leg_FL",
					shape = "Cylinder",
					position = { -3.5, 0.5, 3.5 },
					size = { 1.5, 0.6, 0.6 },
					rotation = { 0, 0, 0 },
					color = { 60, 60, 70 },
					material = "Metal",
					transparency = 0,
				},
				-- Leg front-right
				{
					name = "leg_FR",
					shape = "Cylinder",
					position = { 3.5, 0.5, 3.5 },
					size = { 1.5, 0.6, 0.6 },
					rotation = { 0, 0, 0 },
					color = { 60, 60, 70 },
					material = "Metal",
					transparency = 0,
				},
				-- Leg back-left
				{
					name = "leg_BL",
					shape = "Cylinder",
					position = { -3.5, 0.5, -3.5 },
					size = { 1.5, 0.6, 0.6 },
					rotation = { 0, 0, 0 },
					color = { 60, 60, 70 },
					material = "Metal",
					transparency = 0,
				},
				-- Leg back-right
				{
					name = "leg_BR",
					shape = "Cylinder",
					position = { 3.5, 0.5, -3.5 },
					size = { 1.5, 0.6, 0.6 },
					rotation = { 0, 0, 0 },
					color = { 60, 60, 70 },
					material = "Metal",
					transparency = 0,
				},
				-- Safety pad (ring)
				{
					name = "pad",
					shape = "Cylinder",
					position = { 0, 1.8, 0 },
					size = { 0.4, 10.5, 10.5 },
					rotation = { 0, 0, 0 },
					color = { 60, 130, 255 },
					material = "Fabric",
					transparency = 0,
				},
				-- Inner gap (creates visual ring effect)
				{
					name = "pad_inner",
					shape = "Cylinder",
					position = { 0, 1.85, 0 },
					size = { 0.5, 8.5, 8.5 },
					rotation = { 0, 0, 0 },
					color = { 30, 30, 30 },
					material = "Fabric",
					transparency = 0,
				},
			},
		},
	},

	-- ═══════════════════════════════════════════════════════════════
	-- PROP: Seesaw
	-- ═══════════════════════════════════════════════════════════════
	{
		keywords = { "seesaw", "teeter totter", "see saw" },
		category = "prop",
		modelData = {
			name = "Seesaw",
			category = "prop",
			animation = "wobble",
			parts = {
				-- Fulcrum (triangle base)
				{
					name = "fulcrum",
					shape = "Wedge",
					position = { 0, 1.5, 0 },
					size = { 2, 3, 3 },
					rotation = { 0, 0, 0 },
					color = { 180, 120, 60 },
					material = "Wood",
					transparency = 0,
				},
				-- Plank
				{
					name = "plank",
					shape = "Block",
					position = { 0, 3.2, 0 },
					size = { 2, 0.5, 14 },
					rotation = { 0, 0, 0 },
					color = { 140, 90, 40 },
					material = "Wood",
					transparency = 0,
				},
				-- Handle left
				{
					name = "handle_L",
					shape = "Cylinder",
					position = { 0, 4, 5.5 },
					size = { 1.5, 0.4, 0.4 },
					rotation = { 0, 0, 0 },
					color = { 200, 50, 50 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Handle right
				{
					name = "handle_R",
					shape = "Cylinder",
					position = { 0, 4, -5.5 },
					size = { 1.5, 0.4, 0.4 },
					rotation = { 0, 0, 0 },
					color = { 50, 50, 200 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Seat left
				{
					name = "seat_L",
					shape = "Block",
					position = { 0, 3.5, 6 },
					size = { 2.2, 0.3, 2 },
					rotation = { 0, 0, 0 },
					color = { 200, 50, 50 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Seat right
				{
					name = "seat_R",
					shape = "Block",
					position = { 0, 3.5, -6 },
					size = { 2.2, 0.3, 2 },
					rotation = { 0, 0, 0 },
					color = { 50, 50, 200 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Base platform
				{
					name = "base",
					shape = "Block",
					position = { 0, 0.15, 0 },
					size = { 3, 0.3, 4 },
					rotation = { 0, 0, 0 },
					color = { 100, 100, 100 },
					material = "Concrete",
					transparency = 0,
				},
			},
		},
	},

	-- ═══════════════════════════════════════════════════════════════
	-- CREATURE: Balloon Frog Catching a Fly (balloon style, hopping)
	-- ═══════════════════════════════════════════════════════════════
	{
		keywords = { "balloon frog", "frog catching fly", "frog fly", "frog" },
		category = "creature",
		modelData = {
			name = "Balloon Frog Catching a Fly",
			category = "creature",
			locomotion = "hop",
			animation = "idle_bob",
			attackType = "single",
			targetPriority = "nearest",
			defenseType = "dodge",
			parts = {
				-- Body (big round balloon)
				{
					name = "seg_1",
					shape = "Ball",
					position = { 0, 3, 0 },
					size = { 6, 5, 5 },
					rotation = { 0, 0, 0 },
					color = { 80, 200, 80 },
					material = "SmoothPlastic",
					transparency = 0.05,
				},
				-- Belly (lighter)
				{
					name = "seg_2",
					shape = "Ball",
					position = { 0, 2.2, 1 },
					size = { 4.5, 3.5, 3.5 },
					rotation = { 0, 0, 0 },
					color = { 150, 230, 120 },
					material = "SmoothPlastic",
					transparency = 0.05,
				},
				-- Head
				{
					name = "seg_3",
					shape = "Ball",
					position = { 0, 5.5, 2 },
					size = { 4, 3, 3.5 },
					rotation = { 0, 0, 0 },
					color = { 80, 200, 80 },
					material = "SmoothPlastic",
					transparency = 0.05,
				},
				-- Eye left
				{
					name = "eye_L",
					shape = "Ball",
					position = { -1.2, 6.8, 2.8 },
					size = { 1.4, 1.6, 1.4 },
					rotation = { 0, 0, 0 },
					color = { 255, 255, 255 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Pupil left
				{
					name = "pupil_L",
					shape = "Ball",
					position = { -1.2, 6.9, 3.4 },
					size = { 0.7, 0.8, 0.5 },
					rotation = { 0, 0, 0 },
					color = { 20, 20, 20 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Eye right
				{
					name = "eye_R",
					shape = "Ball",
					position = { 1.2, 6.8, 2.8 },
					size = { 1.4, 1.6, 1.4 },
					rotation = { 0, 0, 0 },
					color = { 255, 255, 255 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Pupil right
				{
					name = "pupil_R",
					shape = "Ball",
					position = { 1.2, 6.9, 3.4 },
					size = { 0.7, 0.8, 0.5 },
					rotation = { 0, 0, 0 },
					color = { 20, 20, 20 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Mouth (wide grin)
				{
					name = "jaw_lower",
					shape = "Block",
					position = { 0, 4.8, 3.2 },
					size = { 3, 0.4, 0.5 },
					rotation = { 0, 0, 0 },
					color = { 200, 50, 50 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Front left leg
				{
					name = "leg_FL_upper",
					shape = "Ball",
					position = { -2.8, 1.5, 2 },
					size = { 1.8, 1.5, 1.5 },
					rotation = { 0, 0, 0 },
					color = { 70, 180, 70 },
					material = "SmoothPlastic",
					transparency = 0.05,
				},
				-- Front right leg
				{
					name = "leg_FR_upper",
					shape = "Ball",
					position = { 2.8, 1.5, 2 },
					size = { 1.8, 1.5, 1.5 },
					rotation = { 0, 0, 0 },
					color = { 70, 180, 70 },
					material = "SmoothPlastic",
					transparency = 0.05,
				},
				-- Back left leg (big powerful hop legs)
				{
					name = "leg_BL_upper",
					shape = "Ball",
					position = { -3, 1.5, -2 },
					size = { 2.5, 2, 2.5 },
					rotation = { 0, 0, 0 },
					color = { 70, 180, 70 },
					material = "SmoothPlastic",
					transparency = 0.05,
				},
				-- Back right leg
				{
					name = "leg_BR_upper",
					shape = "Ball",
					position = { 3, 1.5, -2 },
					size = { 2.5, 2, 2.5 },
					rotation = { 0, 0, 0 },
					color = { 70, 180, 70 },
					material = "SmoothPlastic",
					transparency = 0.05,
				},
				-- Tongue (reaching for the fly!)
				{
					name = "tongue",
					shape = "Block",
					position = { 0, 6, 5.5 },
					size = { 0.4, 0.2, 4 },
					rotation = { 20, 0, 0 },
					color = { 255, 80, 100 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- The fly (tiny, at end of tongue)
				{
					name = "fly_body",
					shape = "Ball",
					position = { 0, 6.8, 7.5 },
					size = { 0.5, 0.4, 0.6 },
					rotation = { 0, 0, 0 },
					color = { 30, 30, 30 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Fly wings
				{
					name = "wing_L_1",
					shape = "Ball",
					position = { -0.4, 7.1, 7.5 },
					size = { 0.6, 0.1, 0.4 },
					rotation = { 0, 0, 20 },
					color = { 200, 220, 255 },
					material = "Glass",
					transparency = 0.3,
				},
				{
					name = "wing_R_1",
					shape = "Ball",
					position = { 0.4, 7.1, 7.5 },
					size = { 0.6, 0.1, 0.4 },
					rotation = { 0, 0, -20 },
					color = { 200, 220, 255 },
					material = "Glass",
					transparency = 0.3,
				},
			},
		},
	},

	-- ═══════════════════════════════════════════════════════════════
	-- CREATURE: Giant Sandworm (slither locomotion)
	-- ═══════════════════════════════════════════════════════════════
	{
		keywords = { "worm", "sandworm", "sand worm", "giant worm" },
		category = "creature",
		modelData = {
			name = "Giant Sandworm",
			category = "creature",
			locomotion = "slither",
			animation = "idle_bob",
			attackType = "splash",
			targetPriority = "nearest",
			defenseType = "armor",
			parts = {
				-- Head segment
				{
					name = "seg_1",
					shape = "Ball",
					position = { 0, 4, 6 },
					size = { 4, 4, 4 },
					rotation = { 0, 0, 0 },
					color = { 180, 140, 80 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Mouth ring
				{
					name = "jaw_ring",
					shape = "Cylinder",
					position = { 0, 4, 8 },
					size = { 3.5, 3.5, 1 },
					rotation = { 90, 0, 0 },
					color = { 160, 60, 60 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Upper jaw fang left
				{
					name = "jaw_fang_L",
					shape = "Wedge",
					position = { -1.2, 5.5, 8.5 },
					size = { 0.6, 1.5, 0.6 },
					rotation = { 0, 0, 0 },
					color = { 240, 230, 200 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Upper jaw fang right
				{
					name = "jaw_fang_R",
					shape = "Wedge",
					position = { 1.2, 5.5, 8.5 },
					size = { 0.6, 1.5, 0.6 },
					rotation = { 0, 0, 0 },
					color = { 240, 230, 200 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Body segment 2
				{
					name = "seg_2",
					shape = "Ball",
					position = { 0, 3.5, 2 },
					size = { 4.5, 4, 4.5 },
					rotation = { 0, 0, 0 },
					color = { 190, 150, 90 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Body segment 3
				{
					name = "seg_3",
					shape = "Ball",
					position = { 0, 3, -2 },
					size = { 4.2, 3.8, 4.2 },
					rotation = { 0, 0, 0 },
					color = { 180, 140, 80 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Body segment 4
				{
					name = "seg_4",
					shape = "Ball",
					position = { 0, 2.8, -6 },
					size = { 3.8, 3.5, 3.8 },
					rotation = { 0, 0, 0 },
					color = { 190, 150, 90 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Tail segment 5
				{
					name = "tail_1",
					shape = "Ball",
					position = { 0, 2.5, -9.5 },
					size = { 3, 2.8, 3 },
					rotation = { 0, 0, 0 },
					color = { 180, 140, 80 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Tail tip
				{
					name = "tail_2",
					shape = "Ball",
					position = { 0, 2.2, -12 },
					size = { 2, 2, 2.5 },
					rotation = { 0, 0, 0 },
					color = { 170, 130, 70 },
					material = "SmoothPlastic",
					transparency = 0,
				},
				-- Eyes (bioluminescent)
				{
					name = "eye_L",
					shape = "Ball",
					position = { -1.5, 5, 7 },
					size = { 0.8, 0.8, 0.5 },
					rotation = { 0, 0, 0 },
					color = { 255, 200, 50 },
					material = "Neon",
					transparency = 0,
				},
				{
					name = "eye_R",
					shape = "Ball",
					position = { 1.5, 5, 7 },
					size = { 0.8, 0.8, 0.5 },
					rotation = { 0, 0, 0 },
					color = { 255, 200, 50 },
					material = "Neon",
					transparency = 0,
				},
				-- Armored plates along body
				{
					name = "plate_1",
					shape = "Block",
					position = { 0, 5.2, 4 },
					size = { 3, 0.5, 2 },
					rotation = { 10, 0, 0 },
					color = { 140, 100, 50 },
					material = "Metal",
					transparency = 0,
				},
				{
					name = "plate_2",
					shape = "Block",
					position = { 0, 4.6, 0 },
					size = { 3.2, 0.5, 2 },
					rotation = { 5, 0, 0 },
					color = { 140, 100, 50 },
					material = "Metal",
					transparency = 0,
				},
				{
					name = "plate_3",
					shape = "Block",
					position = { 0, 4.2, -4 },
					size = { 3, 0.5, 2 },
					rotation = { 0, 0, 0 },
					color = { 140, 100, 50 },
					material = "Metal",
					transparency = 0,
				},
			},
		},
	},

	-- ═══════════════════════════════════════════════════════════════
	-- CREATURE: Crystal Dragon (flying)
	-- ═══════════════════════════════════════════════════════════════
	{
		keywords = { "dragon", "crystal dragon", "flying dragon", "fire dragon" },
		category = "creature",
		modelData = {
			name = "Crystal Dragon",
			category = "creature",
			locomotion = "fly",
			animation = "flutter",
			attackType = "splash",
			targetPriority = "strongest",
			defenseType = "armor",
			parts = {
				-- Head
				{
					name = "seg_1",
					shape = "Ball",
					position = { 0, 8, 5 },
					size = { 2.5, 2.5, 3 },
					rotation = { 0, 0, 0 },
					color = { 100, 50, 200 },
					material = "Glass",
					transparency = 0.15,
				},
				-- Snout
				{
					name = "jaw_upper",
					shape = "Wedge",
					position = { 0, 7.8, 7 },
					size = { 1.5, 1, 2 },
					rotation = { 0, 0, 0 },
					color = { 120, 60, 220 },
					material = "Glass",
					transparency = 0.1,
				},
				-- Lower jaw
				{
					name = "jaw_lower",
					shape = "Wedge",
					position = { 0, 7, 6.5 },
					size = { 1.2, 0.6, 1.5 },
					rotation = { 180, 0, 0 },
					color = { 120, 60, 220 },
					material = "Glass",
					transparency = 0.1,
				},
				-- Eyes
				{
					name = "eye_L",
					shape = "Ball",
					position = { -1, 8.5, 5.8 },
					size = { 0.6, 0.6, 0.4 },
					rotation = { 0, 0, 0 },
					color = { 255, 100, 255 },
					material = "Neon",
					transparency = 0,
				},
				{
					name = "eye_R",
					shape = "Ball",
					position = { 1, 8.5, 5.8 },
					size = { 0.6, 0.6, 0.4 },
					rotation = { 0, 0, 0 },
					color = { 255, 100, 255 },
					material = "Neon",
					transparency = 0,
				},
				-- Neck
				{
					name = "seg_2",
					shape = "Block",
					position = { 0, 7.5, 3 },
					size = { 2, 2, 3 },
					rotation = { 0, 0, 0 },
					color = { 110, 55, 210 },
					material = "Glass",
					transparency = 0.15,
				},
				-- Body
				{
					name = "seg_3",
					shape = "Ball",
					position = { 0, 7, 0 },
					size = { 4, 3, 5 },
					rotation = { 0, 0, 0 },
					color = { 90, 40, 190 },
					material = "Glass",
					transparency = 0.15,
				},
				-- Left wing
				{
					name = "wing_L_1",
					shape = "Block",
					position = { -4, 8, 0 },
					size = { 5, 0.3, 4 },
					rotation = { 0, 0, 15 },
					color = { 150, 80, 255 },
					material = "Glass",
					transparency = 0.25,
				},
				{
					name = "wing_L_2",
					shape = "Block",
					position = { -8, 9, 0 },
					size = { 4, 0.2, 3 },
					rotation = { 0, 0, 25 },
					color = { 170, 100, 255 },
					material = "Glass",
					transparency = 0.35,
				},
				-- Right wing
				{
					name = "wing_R_1",
					shape = "Block",
					position = { 4, 8, 0 },
					size = { 5, 0.3, 4 },
					rotation = { 0, 0, -15 },
					color = { 150, 80, 255 },
					material = "Glass",
					transparency = 0.25,
				},
				{
					name = "wing_R_2",
					shape = "Block",
					position = { 8, 9, 0 },
					size = { 4, 0.2, 3 },
					rotation = { 0, 0, -25 },
					color = { 170, 100, 255 },
					material = "Glass",
					transparency = 0.35,
				},
				-- Tail
				{
					name = "tail_1",
					shape = "Block",
					position = { 0, 6.5, -3 },
					size = { 2.5, 2, 3 },
					rotation = { 0, 0, 0 },
					color = { 100, 50, 200 },
					material = "Glass",
					transparency = 0.15,
				},
				{
					name = "tail_2",
					shape = "Block",
					position = { 0, 6, -6 },
					size = { 1.8, 1.5, 3 },
					rotation = { 0, 0, 0 },
					color = { 110, 55, 210 },
					material = "Glass",
					transparency = 0.2,
				},
				{
					name = "tail_3",
					shape = "Wedge",
					position = { 0, 5.8, -8.5 },
					size = { 1.2, 1, 2 },
					rotation = { 0, 180, 0 },
					color = { 130, 70, 230 },
					material = "Glass",
					transparency = 0.25,
				},
				-- Crystal spines
				{
					name = "spine_1",
					shape = "Wedge",
					position = { 0, 9.5, 3.5 },
					size = { 0.6, 1.5, 0.8 },
					rotation = { -20, 0, 0 },
					color = { 200, 150, 255 },
					material = "Neon",
					transparency = 0.1,
				},
				{
					name = "spine_2",
					shape = "Wedge",
					position = { 0, 9, 1 },
					size = { 0.8, 2, 1 },
					rotation = { 0, 0, 0 },
					color = { 200, 150, 255 },
					material = "Neon",
					transparency = 0.1,
				},
				{
					name = "spine_3",
					shape = "Wedge",
					position = { 0, 8.5, -1.5 },
					size = { 0.6, 1.5, 0.8 },
					rotation = { 10, 0, 0 },
					color = { 200, 150, 255 },
					material = "Neon",
					transparency = 0.1,
				},
				-- Legs
				{
					name = "leg_FL_1",
					shape = "Block",
					position = { -2, 5.5, 1.5 },
					size = { 1, 2, 1 },
					rotation = { 0, 0, 0 },
					color = { 100, 50, 200 },
					material = "Glass",
					transparency = 0.15,
				},
				{
					name = "leg_FR_1",
					shape = "Block",
					position = { 2, 5.5, 1.5 },
					size = { 1, 2, 1 },
					rotation = { 0, 0, 0 },
					color = { 100, 50, 200 },
					material = "Glass",
					transparency = 0.15,
				},
				{
					name = "leg_BL_1",
					shape = "Block",
					position = { -2, 5.5, -2 },
					size = { 1, 2, 1 },
					rotation = { 0, 0, 0 },
					color = { 100, 50, 200 },
					material = "Glass",
					transparency = 0.15,
				},
				{
					name = "leg_BR_1",
					shape = "Block",
					position = { 2, 5.5, -2 },
					size = { 1, 2, 1 },
					rotation = { 0, 0, 0 },
					color = { 100, 50, 200 },
					material = "Glass",
					transparency = 0.15,
				},
			},
		},
	},

	-- ═══════════════════════════════════════════════════════════════
	-- AVATAR: Crystal Knight
	-- ═══════════════════════════════════════════════════════════════
	{
		keywords = { "knight", "crystal knight", "warrior", "armor" },
		category = "avatar",
		modelData = {
			name = "Crystal Knight",
			category = "avatar",
			animation = "none",
			parts = {
				-- Helmet
				{
					name = "helmet",
					shape = "Ball",
					position = { 0, 0.5, 0 },
					size = { 1.6, 1.8, 1.6 },
					rotation = { 0, 0, 0 },
					color = { 100, 60, 200 },
					material = "Glass",
					transparency = 0.15,
					body_part = "Head",
				},
				-- Visor
				{
					name = "visor",
					shape = "Block",
					position = { 0, 0.3, -0.7 },
					size = { 1.2, 0.4, 0.2 },
					rotation = { 0, 0, 0 },
					color = { 200, 150, 255 },
					material = "Neon",
					transparency = 0.2,
					body_part = "Head",
				},
				-- Helmet crest
				{
					name = "crest",
					shape = "Wedge",
					position = { 0, 1.2, 0 },
					size = { 0.4, 1, 1.5 },
					rotation = { 0, 0, 0 },
					color = { 150, 80, 255 },
					material = "Neon",
					transparency = 0,
					body_part = "Head",
				},
				-- Chest plate
				{
					name = "chestplate",
					shape = "Block",
					position = { 0, 0, -0.3 },
					size = { 2.2, 2, 1.2 },
					rotation = { 0, 0, 0 },
					color = { 90, 50, 180 },
					material = "Glass",
					transparency = 0.15,
					body_part = "UpperTorso",
				},
				-- Shoulder left
				{
					name = "shoulder_L",
					shape = "Ball",
					position = { -1.2, 0.6, 0 },
					size = { 1.2, 1.2, 1.2 },
					rotation = { 0, 0, 0 },
					color = { 120, 70, 220 },
					material = "Glass",
					transparency = 0.15,
					body_part = "LeftUpperArm",
				},
				-- Shoulder right
				{
					name = "shoulder_R",
					shape = "Ball",
					position = { 1.2, 0.6, 0 },
					size = { 1.2, 1.2, 1.2 },
					rotation = { 0, 0, 0 },
					color = { 120, 70, 220 },
					material = "Glass",
					transparency = 0.15,
					body_part = "RightUpperArm",
				},
				-- Gauntlet left
				{
					name = "gauntlet_L",
					shape = "Block",
					position = { 0, 0, 0 },
					size = { 1.1, 1.3, 1.1 },
					rotation = { 0, 0, 0 },
					color = { 100, 60, 200 },
					material = "Glass",
					transparency = 0.15,
					body_part = "LeftLowerArm",
				},
				-- Gauntlet right
				{
					name = "gauntlet_R",
					shape = "Block",
					position = { 0, 0, 0 },
					size = { 1.1, 1.3, 1.1 },
					rotation = { 0, 0, 0 },
					color = { 100, 60, 200 },
					material = "Glass",
					transparency = 0.15,
					body_part = "RightLowerArm",
				},
				-- Belt
				{
					name = "belt",
					shape = "Block",
					position = { 0, 0.2, 0 },
					size = { 2, 0.5, 1.2 },
					rotation = { 0, 0, 0 },
					color = { 80, 40, 160 },
					material = "SmoothPlastic",
					transparency = 0,
					body_part = "LowerTorso",
				},
				-- Leg armor left
				{
					name = "legarmor_L",
					shape = "Block",
					position = { 0, 0, 0 },
					size = { 1.2, 1.5, 1.2 },
					rotation = { 0, 0, 0 },
					color = { 90, 50, 180 },
					material = "Glass",
					transparency = 0.15,
					body_part = "LeftUpperLeg",
				},
				-- Leg armor right
				{
					name = "legarmor_R",
					shape = "Block",
					position = { 0, 0, 0 },
					size = { 1.2, 1.5, 1.2 },
					rotation = { 0, 0, 0 },
					color = { 90, 50, 180 },
					material = "Glass",
					transparency = 0.15,
					body_part = "RightUpperLeg",
				},
				-- Boot left
				{
					name = "boot_L",
					shape = "Block",
					position = { 0, -0.2, 0 },
					size = { 1.1, 1.3, 1.4 },
					rotation = { 0, 0, 0 },
					color = { 80, 40, 160 },
					material = "Glass",
					transparency = 0.15,
					body_part = "LeftFoot",
				},
				-- Boot right
				{
					name = "boot_R",
					shape = "Block",
					position = { 0, -0.2, 0 },
					size = { 1.1, 1.3, 1.4 },
					rotation = { 0, 0, 0 },
					color = { 80, 40, 160 },
					material = "Glass",
					transparency = 0.15,
					body_part = "RightFoot",
				},
			},
		},
	},

	-- ═══════════════════════════════════════════════════════════════
	-- ACCESSORY (HAT): Crown of Flames
	-- ═══════════════════════════════════════════════════════════════
	{
		keywords = { "crown", "flame crown", "fire crown", "hat", "crown of flames" },
		category = "accessory",
		modelData = {
			name = "Crown of Flames",
			category = "accessory",
			slot = "head",
			animation = "none",
			parts = {
				-- Crown base ring
				{
					name = "base",
					shape = "Cylinder",
					position = { 0, 0, 0 },
					size = { 0.6, 2, 2 },
					rotation = { 0, 0, 0 },
					color = { 255, 180, 0 },
					material = "Metal",
					transparency = 0,
				},
				-- Front spike
				{
					name = "spike_F",
					shape = "Wedge",
					position = { 0, 0.8, -0.7 },
					size = { 0.3, 1.2, 0.4 },
					rotation = { 0, 0, 0 },
					color = { 255, 200, 30 },
					material = "Metal",
					transparency = 0,
				},
				-- Back spike
				{
					name = "spike_B",
					shape = "Wedge",
					position = { 0, 0.6, 0.7 },
					size = { 0.3, 0.9, 0.4 },
					rotation = { 0, 180, 0 },
					color = { 255, 200, 30 },
					material = "Metal",
					transparency = 0,
				},
				-- Left spike
				{
					name = "spike_L",
					shape = "Wedge",
					position = { -0.7, 0.7, 0 },
					size = { 0.3, 1, 0.4 },
					rotation = { 0, 90, 0 },
					color = { 255, 200, 30 },
					material = "Metal",
					transparency = 0,
				},
				-- Right spike
				{
					name = "spike_R",
					shape = "Wedge",
					position = { 0.7, 0.7, 0 },
					size = { 0.3, 1, 0.4 },
					rotation = { 0, -90, 0 },
					color = { 255, 200, 30 },
					material = "Metal",
					transparency = 0,
				},
				-- Flame center (glow)
				{
					name = "flame_center",
					shape = "Ball",
					position = { 0, 1.3, 0 },
					size = { 0.8, 1.2, 0.8 },
					rotation = { 0, 0, 0 },
					color = { 255, 100, 20 },
					material = "Neon",
					transparency = 0.2,
				},
				-- Flame left
				{
					name = "flame_L",
					shape = "Ball",
					position = { -0.5, 1, 0 },
					size = { 0.5, 0.8, 0.5 },
					rotation = { 0, 0, 15 },
					color = { 255, 60, 10 },
					material = "Neon",
					transparency = 0.3,
				},
				-- Flame right
				{
					name = "flame_R",
					shape = "Ball",
					position = { 0.5, 1, 0 },
					size = { 0.5, 0.8, 0.5 },
					rotation = { 0, 0, -15 },
					color = { 255, 60, 10 },
					material = "Neon",
					transparency = 0.3,
				},
				-- Gem (center front)
				{
					name = "gem",
					shape = "Ball",
					position = { 0, 0.3, -1 },
					size = { 0.5, 0.5, 0.3 },
					rotation = { 0, 0, 0 },
					color = { 255, 50, 50 },
					material = "Neon",
					transparency = 0,
				},
			},
		},
	},
}

-- Find a demo model by fuzzy keyword match against user prompt
function DemoModels.FindMatch(prompt: string): { keywords: { string }, category: string, modelData: { [string]: any } }?
	local lower = string.lower(prompt)

	-- First pass: check for exact keyword containment (longest keyword first for specificity)
	local bestMatch = nil
	local bestLen = 0

	for _, entry in ipairs(DemoModels.MODELS) do
		for _, kw in ipairs(entry.keywords) do
			if string.find(lower, string.lower(kw), 1, true) then
				if #kw > bestLen then
					bestLen = #kw
					bestMatch = entry
				end
			end
		end
	end

	return bestMatch
end

return DemoModels
