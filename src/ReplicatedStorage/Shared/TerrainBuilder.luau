--[[
	TerrainBuilder — procedural origami-themed world terrain + race track.
	Called once from Server:_setupWorld(). All parts are anchored & static.
	Everything uses SmoothPlastic + pastel colors to maintain the paper aesthetic.
]]

local TerrainBuilder = {}

-- Palette

local MAT = Enum.Material.SmoothPlastic

local C = {
	-- Base / ground
	paper = Color3.fromRGB(220, 200, 170),
	paperLight = Color3.fromRGB(235, 225, 210),
	spawn = Color3.fromRGB(240, 235, 225),
	-- Mountains
	peakGreen = Color3.fromRGB(180, 210, 170),
	peakBlue = Color3.fromRGB(170, 195, 215),
	peakWhite = Color3.fromRGB(235, 228, 218),
	peakMint = Color3.fromRGB(175, 215, 195),
	-- Canyon
	canyonWall = Color3.fromRGB(195, 165, 135),
	canyonFloor = Color3.fromRGB(205, 185, 155),
	canyonDark = Color3.fromRGB(175, 150, 120),
	-- Water
	water = Color3.fromRGB(140, 185, 225),
	wave = Color3.fromRGB(160, 200, 235),
	-- Forest
	trunk = Color3.fromRGB(180, 150, 110),
	leafGreen = Color3.fromRGB(155, 200, 140),
	leafDark = Color3.fromRGB(135, 185, 125),
	leafLight = Color3.fromRGB(175, 215, 160),
	-- Floating islands
	islandPink = Color3.fromRGB(230, 185, 195),
	islandLavender = Color3.fromRGB(195, 185, 225),
	islandMint = Color3.fromRGB(185, 225, 195),
	islandPeach = Color3.fromRGB(235, 210, 185),
	-- Track
	track = Color3.fromRGB(245, 235, 220),
	trackLine = Color3.fromRGB(200, 85, 85),
	barrierRed = Color3.fromRGB(220, 130, 130),
	barrierWhite = Color3.fromRGB(240, 235, 230),
	checkerBlack = Color3.fromRGB(60, 55, 50),
	checkerWhite = Color3.fromRGB(240, 240, 235),
}

-- Helpers

local function makePart(folder: Folder, props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local part = Instance.new(className)
	part.Anchored = true
	part.Material = MAT
	part.CastShadow = true

	if className == "Part" then
		part.Shape = props.Shape or Enum.PartType.Block
	end

	part.Name = props.Name or "Terrain"
	part.Size = props.Size or Vector3.new(4, 4, 4)
	part.Color = props.Color or C.paper
	part.Transparency = props.Transparency or 0
	part.CanCollide = if props.CanCollide ~= nil then props.CanCollide else true

	if props.CFrame then
		part.CFrame = props.CFrame
	elseif props.Position then
		part.Position = props.Position
	end

	if props.Orientation then
		part.Orientation = props.Orientation
	end

	part.Parent = folder
	return part
end

local function makeWedge(folder: Folder, props: { [string]: any }): WedgePart
	props.ClassName = "WedgePart"
	return makePart(folder, props) :: WedgePart
end

-- Baseplate & Spawn

local function createBaseplate(folder: Folder)
	-- Main ground — warm paper tan
	makePart(folder, {
		Name = "Baseplate",
		Size = Vector3.new(512, 4, 512),
		Position = Vector3.new(0, -2, 0),
		Color = C.paper,
	})
end

local function createSpawnPlatform(folder: Folder)
	-- Slightly raised cream platform at origin
	makePart(folder, {
		Name = "SpawnPlatform",
		Size = Vector3.new(50, 0.5, 50),
		Position = Vector3.new(0, 0.25, 0),
		Color = C.spawn,
	})

	-- Decorative edge folds (4 wedges around the platform)
	local edgeSize = Vector3.new(50, 1.5, 3)
	local offsets = {
		{ pos = Vector3.new(0, 0.75, -26.5), rot = Vector3.new(0, 0, 0) },
		{ pos = Vector3.new(0, 0.75, 26.5), rot = Vector3.new(0, 180, 0) },
		{ pos = Vector3.new(-26.5, 0.75, 0), rot = Vector3.new(0, 90, 0) },
		{ pos = Vector3.new(26.5, 0.75, 0), rot = Vector3.new(0, -90, 0) },
	}
	for _, edge in ipairs(offsets) do
		makeWedge(folder, {
			Name = "SpawnEdge",
			Size = edgeSize,
			Position = edge.pos,
			Orientation = edge.rot,
			Color = C.paperLight,
		})
	end
end

-- Mountains (NE quadrant)

local function createMountainRange(folder: Folder)
	local peaks = {
		-- { position, size, yRotation, color }
		-- ALL peaks pushed far NE to avoid the track corridor entirely
		-- Track corridor runs: (110,-75) → (140,-100) → (160,-115) → (160,-80) → (185,-20)
		-- Peaks stay at X>200 or Z<-140 to be well clear
		{ Vector3.new(210, 15, -150), Vector3.new(35, 30, 30), 20, C.peakGreen },
		{ Vector3.new(230, 20, -170), Vector3.new(40, 40, 35), -15, C.peakBlue },
		{ Vector3.new(220, 30, -130), Vector3.new(45, 60, 40), 45, C.peakWhite },
		{ Vector3.new(200, 18, -180), Vector3.new(35, 36, 30), 70, C.peakMint },
		{ Vector3.new(240, 22, -155), Vector3.new(38, 44, 32), -30, C.peakGreen },
		{ Vector3.new(250, 25, -120), Vector3.new(42, 50, 38), 10, C.peakBlue },
		{ Vector3.new(195, 12, -165), Vector3.new(30, 24, 28), 55, C.peakWhite },
		{ Vector3.new(245, 15, -140), Vector3.new(32, 30, 26), -60, C.peakMint },
		{ Vector3.new(215, 10, -115), Vector3.new(28, 20, 25), 35, C.peakGreen },
		{ Vector3.new(235, 18, -185), Vector3.new(36, 36, 30), 80, C.peakBlue },
	}

	for i, peak in ipairs(peaks) do
		local pos, size, yRot, color = peak[1], peak[2], peak[3], peak[4]
		makeWedge(folder, {
			Name = "Peak_" .. tostring(i),
			Size = size,
			CFrame = CFrame.new(pos.X, pos.Y + size.Y / 2 - 2, pos.Z) * CFrame.Angles(0, math.rad(yRot), 0),
			Color = color,
		})
	end

	-- Plateau surfaces between peaks (walkable areas among mountains)
	makePart(folder, {
		Name = "Plateau_1",
		Size = Vector3.new(25, 2, 20),
		Position = Vector3.new(225, 18, -140),
		Color = C.peakWhite,
	})
	makePart(folder, {
		Name = "Plateau_2",
		Size = Vector3.new(20, 2, 18),
		Position = Vector3.new(210, 12, -165),
		Color = C.peakMint,
	})
end

-- Canyon (SE quadrant)

local function createCanyon(folder: Folder)
	-- Canyon is in the SE quadrant, well away from the track which goes around its rim
	-- Canyon center at (160, -15, 60), track passes at X=150-200 Z=70-120 at Y=0.5
	local CX, CZ = 160, 55 -- canyon center

	-- Canyon floor (sunken 15 studs below ground)
	makePart(folder, {
		Name = "CanyonFloor",
		Size = Vector3.new(80, 1, 60),
		Position = Vector3.new(CX, -15, CZ),
		Color = C.canyonFloor,
	})

	-- Canyon walls (all 4 sides)
	makePart(folder, {
		Name = "CanyonWall_W",
		Size = Vector3.new(4, 16, 60),
		Position = Vector3.new(CX - 40, -7, CZ),
		Color = C.canyonWall,
	})
	makePart(folder, {
		Name = "CanyonWall_E",
		Size = Vector3.new(4, 16, 60),
		Position = Vector3.new(CX + 40, -7, CZ),
		Color = C.canyonWall,
	})
	makePart(folder, {
		Name = "CanyonWall_N",
		Size = Vector3.new(80, 16, 4),
		Position = Vector3.new(CX, -7, CZ - 30),
		Color = C.canyonDark,
	})
	makePart(folder, {
		Name = "CanyonWall_S",
		Size = Vector3.new(80, 16, 4),
		Position = Vector3.new(CX, -7, CZ + 30),
		Color = C.canyonDark,
	})

	-- Angular wall tops (crease decoration)
	makeWedge(folder, {
		Name = "CanyonCrest_W",
		Size = Vector3.new(60, 4, 6),
		CFrame = CFrame.new(CX - 40, 1, CZ) * CFrame.Angles(0, 0, math.rad(-20)),
		Color = C.canyonWall,
	})
	makeWedge(folder, {
		Name = "CanyonCrest_E",
		Size = Vector3.new(60, 4, 6),
		CFrame = CFrame.new(CX + 40, 1, CZ) * CFrame.Angles(0, math.rad(180), math.rad(-20)),
		Color = C.canyonWall,
	})

	-- Walking ramp from surface into canyon (south side)
	makeWedge(folder, {
		Name = "CanyonRamp",
		Size = Vector3.new(12, 15, 25),
		CFrame = CFrame.new(CX, -7.5, CZ + 42.5) * CFrame.Angles(0, math.rad(180), 0),
		Color = C.canyonFloor,
	})
end

-- Water Area (SW quadrant)

local function createWaterArea(folder: Folder)
	-- Main water surface — CanCollide = false! Players fall through.
	makePart(folder, {
		Name = "Water",
		Size = Vector3.new(110, 0.5, 100),
		Position = Vector3.new(-80, -1.5, 120),
		Color = C.water,
		Transparency = 0.35,
		CanCollide = false,
	})

	-- Water bottom (catch/visual)
	makePart(folder, {
		Name = "WaterBottom",
		Size = Vector3.new(110, 1, 100),
		Position = Vector3.new(-80, -20, 120),
		Color = Color3.fromRGB(90, 120, 160),
	})

	-- Paper waves (decorative wedges on surface)
	local wavePositions = {
		Vector3.new(-60, -1, 100),
		Vector3.new(-95, -1, 135),
		Vector3.new(-70, -1, 150),
		Vector3.new(-110, -1, 110),
		Vector3.new(-50, -1, 130),
	}
	for i, wPos in ipairs(wavePositions) do
		makeWedge(folder, {
			Name = "Wave_" .. tostring(i),
			Size = Vector3.new(8, 1.5, 4),
			CFrame = CFrame.new(wPos) * CFrame.Angles(0, math.rad(i * 47), 0),
			Color = C.wave,
			Transparency = 0.3,
			CanCollide = false,
		})
	end

	-- Shoreline raised edges
	local shores = {
		{ Vector3.new(-25, -0.5, 120), Vector3.new(2, 1.5, 100) }, -- east shore
		{ Vector3.new(-135, -0.5, 120), Vector3.new(2, 1.5, 100) }, -- west shore
		{ Vector3.new(-80, -0.5, 70), Vector3.new(110, 1.5, 2) }, -- north shore
		{ Vector3.new(-80, -0.5, 170), Vector3.new(110, 1.5, 2) }, -- south shore
	}
	for i, shore in ipairs(shores) do
		makePart(folder, {
			Name = "Shore_" .. tostring(i),
			Size = shore[2],
			Position = shore[1],
			Color = C.paperLight,
		})
	end
end

-- Floating Islands (NW quadrant)

local function createFloatingIslands(folder: Folder)
	local islands = {
		-- { centerPos, platformSize, color, undersideCount }
		{ Vector3.new(-100, 30, -80), Vector3.new(22, 3, 18), C.islandPink, 2 },
		{ Vector3.new(-130, 40, -110), Vector3.new(18, 3, 16), C.islandLavender, 3 },
		{ Vector3.new(-80, 50, -130), Vector3.new(25, 4, 20), C.islandMint, 3 },
		{ Vector3.new(-150, 35, -70), Vector3.new(15, 3, 14), C.islandPeach, 2 },
		{ Vector3.new(-110, 45, -140), Vector3.new(20, 3, 18), C.islandPink, 2 },
	}

	for i, island in ipairs(islands) do
		local pos, size, color, underCount = island[1], island[2], island[3], island[4]

		-- Platform top (walkable)
		makePart(folder, {
			Name = "Island_" .. tostring(i),
			Size = size,
			Position = pos,
			Color = color,
		})

		-- Inverted wedges underneath (paper fold look)
		for u = 1, underCount do
			local xOff = (u - 1 - (underCount - 1) / 2) * (size.X / underCount)
			local wedgeSize = Vector3.new(size.X / underCount + 2, size.Y * 3, size.Z * 0.7)
			makeWedge(folder, {
				Name = "IslandUnder_" .. tostring(i) .. "_" .. tostring(u),
				Size = wedgeSize,
				CFrame = CFrame.new(pos.X + xOff, pos.Y - size.Y / 2 - wedgeSize.Y / 2, pos.Z)
					* CFrame.Angles(math.rad(180), math.rad(u * 60), 0),
				Color = color,
				CanCollide = false, -- visual only underneath
			})
		end
	end

	-- Beacon on the highest island to attract attention
	makePart(folder, {
		Name = "IslandBeacon",
		Size = Vector3.new(3, 6, 3),
		Position = Vector3.new(-80, 55, -130),
		Color = Color3.fromRGB(255, 230, 100),
		CanCollide = false,
	})
	-- Make it Neon for glow
	local beacon = folder:FindFirstChild("IslandBeacon")
	if beacon and beacon:IsA("BasePart") then
		beacon.Material = Enum.Material.Neon
	end
end

-- Paper Forest (W area)

local function makePaperTree(folder: Folder, pos: Vector3, scale: number, leafColor: Color3)
	local treeFolder = Instance.new("Folder")
	treeFolder.Name = "Tree"
	treeFolder.Parent = folder

	-- Trunk — tall thin wedge
	local trunkH = 6 * scale
	makeWedge(treeFolder, {
		Name = "Trunk",
		Size = Vector3.new(2 * scale, trunkH, 2 * scale),
		CFrame = CFrame.new(pos.X, pos.Y + trunkH / 2, pos.Z),
		Color = C.trunk,
	})

	-- Canopy — 2-3 stacked angular wedges, each rotated
	local canopyBase = pos.Y + trunkH
	local layers = if scale > 1.2 then 3 else 2

	for layer = 1, layers do
		local layerScale = 1 - (layer - 1) * 0.25
		local w = 7 * scale * layerScale
		local h = 4 * scale * layerScale
		local yOff = (layer - 1) * (h * 0.65)
		makeWedge(treeFolder, {
			Name = "Canopy_" .. tostring(layer),
			Size = Vector3.new(w, h, w * 0.8),
			CFrame = CFrame.new(pos.X, canopyBase + yOff + h / 2, pos.Z)
				* CFrame.Angles(0, math.rad(layer * 40 + pos.X), 0),
			Color = if layer % 2 == 0 then C.leafDark else leafColor,
		})
	end
end

local function createPaperForest(folder: Folder)
	local trees = {
		-- { position, scale, color }
		-- Trees positioned west of the track (track passes at X≈-65, Z=50-85)
		-- Keep trees at X < -80 or Z < 30 to stay clear
		{ Vector3.new(-100, 0, -10), 1.0, C.leafGreen },
		{ Vector3.new(-120, 0, 5), 1.3, C.leafDark },
		{ Vector3.new(-95, 0, 15), 0.9, C.leafLight },
		{ Vector3.new(-135, 0, -5), 1.1, C.leafGreen },
		{ Vector3.new(-110, 0, 25), 1.4, C.leafDark },
		{ Vector3.new(-90, 0, -25), 1.0, C.leafLight },
		{ Vector3.new(-130, 0, 30), 1.2, C.leafGreen },
		{ Vector3.new(-145, 0, 15), 0.8, C.leafDark },
		{ Vector3.new(-105, 0, -35), 1.1, C.leafLight },
		{ Vector3.new(-115, 0, -30), 1.3, C.leafGreen },
		{ Vector3.new(-85, 0, -15), 0.9, C.leafDark },
		{ Vector3.new(-140, 0, -20), 1.0, C.leafLight },
	}

	for _, tree in ipairs(trees) do
		makePaperTree(folder, tree[1], tree[2], tree[3])
	end
end

-- Race Track

local TRACK_WIDTH = 16
local BARRIER_HEIGHT = 2.5
local TRACK_THICKNESS = 0.8

local WAYPOINTS = {
	Vector3.new(50, 0.5, -40), -- 1: Start/finish (east of spawn)
	Vector3.new(80, 0.5, -55), -- 2: Curve toward mountains
	Vector3.new(120, 0.5, -80), -- 3: Heading NE
	Vector3.new(170, 0.5, -65), -- 4: East side pass
	Vector3.new(200, 0.5, -30), -- 5: Curving south
	Vector3.new(200, 0.5, 30), -- 6: East straightaway
	Vector3.new(185, 0.5, 70), -- 7: Approaching canyon rim
	Vector3.new(150, 0.5, 110), -- 8: South of canyon (along rim)
	Vector3.new(105, 0.5, 120), -- 9: Turning west
	Vector3.new(50, 3, 135), -- 10: Bridge start
	Vector3.new(-25, 3, 128), -- 11: Bridge end
	Vector3.new(-65, 0.5, 85), -- 12: Past forest
	Vector3.new(-65, 0.5, 50), -- 13: Forest straightaway
	Vector3.new(-55, 0.5, -15), -- 14: Curve south of spawn
	Vector3.new(10, 0.5, -40), -- 15: Final approach back to start
}

local function makeTrackSegment(folder: Folder, p1: Vector3, p2: Vector3, index: number)
	local mid = (p1 + p2) / 2
	local dir = p2 - p1
	local length = dir.Magnitude

	if length < 0.1 then
		return
	end

	local cf = CFrame.lookAt(mid, mid + dir) * CFrame.Angles(0, 0, 0)

	-- Track surface
	makePart(folder, {
		Name = "Track_" .. tostring(index),
		Size = Vector3.new(TRACK_WIDTH, TRACK_THICKNESS, length),
		CFrame = cf,
		Color = C.track,
	})

	-- Center line (dashed look — just one continuous line for simplicity, raised slightly)
	makePart(folder, {
		Name = "TrackLine_" .. tostring(index),
		Size = Vector3.new(0.4, 0.05, length),
		CFrame = cf * CFrame.new(0, TRACK_THICKNESS / 2 + 0.03, 0),
		Color = C.trackLine,
		CanCollide = false,
	})

	-- No barriers — easy to drive on/off track
end

local function makeStartFinishLine(folder: Folder)
	local p1 = WAYPOINTS[1]
	local p2 = WAYPOINTS[#WAYPOINTS]
	local dir = (p1 - p2).Unit
	local cf = CFrame.lookAt(p1, p1 + dir)

	-- Checkered pattern (4x2 grid)
	local checkerSize = TRACK_WIDTH / 4
	for col = 0, 3 do
		for row = 0, 1 do
			local isBlack = (col + row) % 2 == 0
			local xOff = (col - 1.5) * checkerSize
			local zOff = (row - 0.5) * checkerSize
			makePart(folder, {
				Name = "Checker_" .. tostring(col) .. "_" .. tostring(row),
				Size = Vector3.new(checkerSize, 0.06, checkerSize),
				CFrame = cf * CFrame.new(xOff, TRACK_THICKNESS / 2 + 0.04, zOff),
				Color = if isBlack then C.checkerBlack else C.checkerWhite,
				CanCollide = false,
			})
		end
	end
end

local function createBridge(folder: Folder)
	-- Bridge spans waypoints 10 to 11 (over water)
	local p1 = WAYPOINTS[10]
	local p2 = WAYPOINTS[11]
	local mid = (p1 + p2) / 2
	local dir = p2 - p1
	local length = dir.Magnitude

	-- Bridge deck is created by the track segment.
	-- Add support columns underneath.
	local numColumns = 4
	for i = 1, numColumns do
		local t = i / (numColumns + 1)
		local colPos = p1:Lerp(p2, t)
		makePart(folder, {
			Name = "BridgeColumn_" .. tostring(i),
			Size = Vector3.new(2, 20, 2),
			Position = Vector3.new(colPos.X, -8, colPos.Z),
			Color = C.paperLight,
		})
	end

	-- No rails — easy to drive on/off bridge
end

local function createRaceTrack(folder: Folder)
	local trackFolder = Instance.new("Folder")
	trackFolder.Name = "RaceTrack"
	trackFolder.Parent = folder

	-- Create track segments between consecutive waypoints (closed loop)
	for i = 1, #WAYPOINTS do
		local nextI = if i == #WAYPOINTS then 1 else i + 1
		makeTrackSegment(trackFolder, WAYPOINTS[i], WAYPOINTS[nextI], i)
	end

	-- Start/finish line
	makeStartFinishLine(trackFolder)

	-- Bridge over water
	createBridge(trackFolder)
end

-- Decorative details

local function createDecorations(folder: Folder)
	-- Scattered paper fold decorations around the world
	-- Decorations placed away from track and spawn (spawn is 0,0; track starts at 50,-40)
	local folds = {
		{ Vector3.new(20, 0.5, 25), Vector3.new(6, 2, 4), 30, C.paperLight },
		{ Vector3.new(-25, 0.5, 30), Vector3.new(5, 1.5, 3), -45, C.peakMint },
		{ Vector3.new(15, 0.5, -20), Vector3.new(4, 1, 3), 60, C.islandPeach },
		{ Vector3.new(-35, 0.5, -30), Vector3.new(7, 2, 5), -20, C.islandLavender },
		{ Vector3.new(-20, 0.5, 15), Vector3.new(5, 1.5, 4), 75, C.peakGreen },
	}

	for i, fold in ipairs(folds) do
		makeWedge(folder, {
			Name = "Decoration_" .. tostring(i),
			Size = fold[2],
			CFrame = CFrame.new(fold[1]) * CFrame.Angles(0, math.rad(fold[3]), 0),
			Color = fold[4],
		})
	end
end

-- Public API

function TerrainBuilder.Build()
	-- Clean up any existing terrain
	local existing = workspace:FindFirstChild("WorldTerrain")
	if existing then
		existing:Destroy()
	end

	-- Also remove old flat baseplate if it exists
	local oldBase = workspace:FindFirstChild("Baseplate")
	if oldBase then
		oldBase:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "WorldTerrain"
	folder.Parent = workspace

	createBaseplate(folder)
	createSpawnPlatform(folder)
	createMountainRange(folder)
	createCanyon(folder)
	createWaterArea(folder)
	createFloatingIslands(folder)
	createPaperForest(folder)
	createRaceTrack(folder)
	createDecorations(folder)

	print("[TerrainBuilder] World built:", #folder:GetDescendants(), "instances")
end

return TerrainBuilder
