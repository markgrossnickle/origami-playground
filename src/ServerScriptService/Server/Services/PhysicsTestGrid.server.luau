--!strict
-- PhysicsTestGrid: Spawns 10 constraint types × 3 varieties in a grid for testing.
-- Walk around and test which physics objects actually work.
-- DELETE THIS FILE after testing is complete.

local GRID_ORIGIN = Vector3.new(-200, 5, -200) -- far corner so it doesn't interfere
local COL_SPACING = 25
local ROW_SPACING = 25

local function makeLabel(parent: BasePart, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 50)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = true
	bb.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = bb
end

local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = if props.anchored ~= nil then props.anchored else true
	part.Size = props.size or Vector3.new(2, 2, 2)
	part.Position = props.position or Vector3.new(0, 5, 0)
	part.Color = props.color or Color3.fromRGB(100, 150, 200)
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if props.shape then
		part.Shape = props.shape
	end
	if props.transparency then
		part.Transparency = props.transparency
	end
	if props.canCollide ~= nil then
		part.CanCollide = props.canCollide
	end
	if props.elasticity then
		part.CustomPhysicalProperties = PhysicalProperties.new(
			props.density or 0.7,
			props.friction or 0.3,
			props.elasticity,
			1, 1
		)
	end
	part.Parent = workspace
	return part
end

local function makeAttachment(parent: BasePart, offset: Vector3?): Attachment
	local att = Instance.new("Attachment")
	if offset then
		att.Position = offset
	end
	att.Parent = parent
	return att
end

local testNum = 0
local function gridPos(row: number, col: number): Vector3
	return GRID_ORIGIN + Vector3.new(col * COL_SPACING, 0, row * ROW_SPACING)
end

local function spawnTest(row: number, col: number, label: string, builder: (Vector3) -> ())
	testNum += 1
	local pos = gridPos(row, col)
	-- Ground plate
	local plate = makePart({
		position = pos - Vector3.new(0, 4.5, 0),
		size = Vector3.new(20, 1, 20),
		color = Color3.fromRGB(80, 80, 80),
		material = Enum.Material.Concrete,
	})
	makeLabel(plate, "#" .. testNum .. " " .. label)
	builder(pos)
end

task.wait(3) -- wait for game to load

----------------------------------------------------------------------
-- ROW 0: SPRING
----------------------------------------------------------------------
-- 0A: Basic trampoline (spring between anchored base and unanchored platform)
spawnTest(0, 0, "Spring: Trampoline", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(6, 1, 6),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local platform = makePart({
		position = pos + Vector3.new(0, 1, 0),
		size = Vector3.new(6, 0.5, 6),
		color = Color3.fromRGB(255, 100, 50),
		anchored = false,
		elasticity = 1.0,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAttachment(platform, Vector3.new(0, -0.25, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 500
	spring.Damping = 5
	spring.FreeLength = 2
	spring.Parent = base
end)

-- 0B: Stiff spring (barely moves)
spawnTest(0, 1, "Spring: Stiff", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(6, 1, 6),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local platform = makePart({
		position = pos + Vector3.new(0, 1, 0),
		size = Vector3.new(6, 0.5, 6),
		color = Color3.fromRGB(50, 200, 50),
		anchored = false,
		elasticity = 0.8,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAttachment(platform, Vector3.new(0, -0.25, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 5000
	spring.Damping = 50
	spring.FreeLength = 2
	spring.Parent = base
end)

-- 0C: Bouncy ball on spring
spawnTest(0, 2, "Spring: Bouncy Ball", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(2, 1, 2),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local ball = makePart({
		position = pos + Vector3.new(0, 2, 0),
		size = Vector3.new(3, 3, 3),
		shape = Enum.PartType.Ball,
		color = Color3.fromRGB(255, 50, 50),
		anchored = false,
		elasticity = 1.0,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAttachment(ball, Vector3.new(0, -1.5, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 200
	spring.Damping = 3
	spring.FreeLength = 3
	spring.Visible = true
	spring.Parent = base
end)

----------------------------------------------------------------------
-- ROW 1: HINGE
----------------------------------------------------------------------
-- 1A: Door
spawnTest(1, 0, "Hinge: Door", function(pos)
	local frame = makePart({
		position = pos + Vector3.new(-2.5, 0, 0),
		size = Vector3.new(1, 8, 1),
		color = Color3.fromRGB(120, 80, 40),
		anchored = true,
	})
	local panel = makePart({
		position = pos + Vector3.new(0, 0, 0),
		size = Vector3.new(4, 8, 0.5),
		color = Color3.fromRGB(160, 110, 60),
		anchored = false,
	})
	local att0 = makeAttachment(frame, Vector3.new(0.5, 0, 0))
	local att1 = makeAttachment(panel, Vector3.new(-2, 0, 0))
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = 0
	hinge.UpperAngle = 90
	hinge.Parent = frame
end)

-- 1B: Seesaw / Teeter-totter
spawnTest(1, 1, "Hinge: Seesaw", function(pos)
	local post = makePart({
		position = pos - Vector3.new(0, 1, 0),
		size = Vector3.new(2, 4, 2),
		color = Color3.fromRGB(100, 100, 100),
		anchored = true,
	})
	local plank = makePart({
		position = pos + Vector3.new(0, 1.5, 0),
		size = Vector3.new(12, 0.5, 4),
		color = Color3.fromRGB(180, 140, 60),
		anchored = false,
	})
	local att0 = makeAttachment(post, Vector3.new(0, 2, 0))
	local att1 = makeAttachment(plank, Vector3.new(0, 0, 0))
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -20
	hinge.UpperAngle = 20
	hinge.Parent = post
end)

-- 1C: Flipper (hinge at one end)
spawnTest(1, 2, "Hinge: Flipper", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(2, 2, 6),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local flipper = makePart({
		position = pos + Vector3.new(0, 0, 3),
		size = Vector3.new(2, 1, 8),
		color = Color3.fromRGB(255, 200, 50),
		anchored = false,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 1, 3))
	local att1 = makeAttachment(flipper, Vector3.new(0, 0, -4))
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -10
	hinge.UpperAngle = 45
	hinge.Parent = base
end)

----------------------------------------------------------------------
-- ROW 2: BALL SOCKET
----------------------------------------------------------------------
-- 2A: Swing
spawnTest(2, 0, "BallSocket: Swing", function(pos)
	local bar = makePart({
		position = pos + Vector3.new(0, 6, 0),
		size = Vector3.new(1, 1, 8),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local seat = makePart({
		position = pos + Vector3.new(0, 0, 0),
		size = Vector3.new(3, 0.5, 3),
		color = Color3.fromRGB(200, 50, 50),
		anchored = false,
	})
	local att0 = makeAttachment(bar, Vector3.new(0, -0.5, 0))
	local att1 = makeAttachment(seat, Vector3.new(0, 0, 0))
	local bs = Instance.new("BallSocketConstraint")
	bs.Attachment0 = att0
	bs.Attachment1 = att1
	bs.LimitsEnabled = true
	bs.UpperAngle = 45
	bs.Parent = bar
end)

-- 2B: Wrecking ball
spawnTest(2, 1, "BallSocket: Wrecker", function(pos)
	local crane = makePart({
		position = pos + Vector3.new(0, 8, 0),
		size = Vector3.new(2, 1, 2),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local ball = makePart({
		position = pos + Vector3.new(0, 1, 0),
		size = Vector3.new(4, 4, 4),
		shape = Enum.PartType.Ball,
		color = Color3.fromRGB(40, 40, 40),
		anchored = false,
		density = 5,
		friction = 0.5,
		elasticity = 0.3,
	})
	local att0 = makeAttachment(crane, Vector3.new(0, -0.5, 0))
	local att1 = makeAttachment(ball, Vector3.new(0, 2, 0))
	local bs = Instance.new("BallSocketConstraint")
	bs.Attachment0 = att0
	bs.Attachment1 = att1
	bs.Parent = crane
end)

-- 2C: Hanging lantern (free swing, small)
spawnTest(2, 2, "BallSocket: Lantern", function(pos)
	local hook = makePart({
		position = pos + Vector3.new(0, 5, 0),
		size = Vector3.new(1, 1, 1),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local lantern = makePart({
		position = pos + Vector3.new(0, 2, 0),
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(255, 200, 50),
		material = Enum.Material.Neon,
		anchored = false,
	})
	local att0 = makeAttachment(hook, Vector3.new(0, -0.5, 0))
	local att1 = makeAttachment(lantern, Vector3.new(0, 1, 0))
	local bs = Instance.new("BallSocketConstraint")
	bs.Attachment0 = att0
	bs.Attachment1 = att1
	bs.LimitsEnabled = true
	bs.UpperAngle = 60
	bs.Parent = hook
end)

----------------------------------------------------------------------
-- ROW 3: WELD
----------------------------------------------------------------------
-- 3A: Welded tower (should stay rigid)
spawnTest(3, 0, "Weld: Tower", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(4, 2, 4),
		color = Color3.fromRGB(100, 100, 100),
		anchored = true,
	})
	local top = makePart({
		position = pos + Vector3.new(0, 1, 0),
		size = Vector3.new(3, 4, 3),
		color = Color3.fromRGB(200, 50, 50),
		anchored = false,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = top
	weld.Parent = base
end)

-- 3B: Welded L-shape
spawnTest(3, 1, "Weld: L-Shape", function(pos)
	local vertical = makePart({
		position = pos,
		size = Vector3.new(2, 6, 2),
		color = Color3.fromRGB(50, 150, 200),
		anchored = true,
	})
	local horizontal = makePart({
		position = pos + Vector3.new(3, 3, 0),
		size = Vector3.new(4, 2, 2),
		color = Color3.fromRGB(50, 200, 150),
		anchored = false,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = vertical
	weld.Part1 = horizontal
	weld.Parent = vertical
end)

-- 3C: Welded chain of 3 parts
spawnTest(3, 2, "Weld: Chain", function(pos)
	local p1 = makePart({
		position = pos - Vector3.new(3, 0, 0),
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(200, 100, 50),
		anchored = true,
	})
	local p2 = makePart({
		position = pos,
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(150, 200, 50),
		anchored = false,
	})
	local p3 = makePart({
		position = pos + Vector3.new(3, 0, 0),
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(50, 100, 200),
		anchored = false,
	})
	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = p1
	w1.Part1 = p2
	w1.Parent = p1
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = p2
	w2.Part1 = p3
	w2.Parent = p2
end)

----------------------------------------------------------------------
-- ROW 4: ROD
----------------------------------------------------------------------
-- 4A: Pendulum
spawnTest(4, 0, "Rod: Pendulum", function(pos)
	local pivot = makePart({
		position = pos + Vector3.new(0, 6, 0),
		size = Vector3.new(1, 1, 1),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local weight = makePart({
		position = pos + Vector3.new(3, 1, 0),
		size = Vector3.new(2, 2, 2),
		shape = Enum.PartType.Ball,
		color = Color3.fromRGB(200, 180, 50),
		anchored = false,
	})
	local att0 = makeAttachment(pivot, Vector3.new(0, 0, 0))
	local att1 = makeAttachment(weight, Vector3.new(0, 0, 0))
	local rod = Instance.new("RodConstraint")
	rod.Attachment0 = att0
	rod.Attachment1 = att1
	rod.Length = 5
	rod.Visible = true
	rod.Parent = pivot
end)

-- 4B: Tethered ball (short rod)
spawnTest(4, 1, "Rod: Short Tether", function(pos)
	local anchor = makePart({
		position = pos + Vector3.new(0, 4, 0),
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local ball = makePart({
		position = pos + Vector3.new(2, 2, 0),
		size = Vector3.new(2, 2, 2),
		shape = Enum.PartType.Ball,
		color = Color3.fromRGB(100, 200, 255),
		anchored = false,
	})
	local att0 = makeAttachment(anchor, Vector3.new(0, -1, 0))
	local att1 = makeAttachment(ball, Vector3.new(0, 0, 0))
	local rod = Instance.new("RodConstraint")
	rod.Attachment0 = att0
	rod.Attachment1 = att1
	rod.Length = 2
	rod.Visible = true
	rod.Parent = anchor
end)

-- 4C: Hanging sign
spawnTest(4, 2, "Rod: Hanging Sign", function(pos)
	local bar = makePart({
		position = pos + Vector3.new(0, 6, 0),
		size = Vector3.new(6, 0.5, 0.5),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local sign = makePart({
		position = pos + Vector3.new(0, 2, 0),
		size = Vector3.new(5, 3, 0.3),
		color = Color3.fromRGB(240, 230, 200),
		anchored = false,
	})
	local att0L = makeAttachment(bar, Vector3.new(-2, 0, 0))
	local att1L = makeAttachment(sign, Vector3.new(-2, 1.5, 0))
	local rod1 = Instance.new("RodConstraint")
	rod1.Attachment0 = att0L
	rod1.Attachment1 = att1L
	rod1.Length = 2
	rod1.Visible = true
	rod1.Parent = bar
	local att0R = makeAttachment(bar, Vector3.new(2, 0, 0))
	local att1R = makeAttachment(sign, Vector3.new(2, 1.5, 0))
	local rod2 = Instance.new("RodConstraint")
	rod2.Attachment0 = att0R
	rod2.Attachment1 = att1R
	rod2.Length = 2
	rod2.Visible = true
	rod2.Parent = bar
end)

----------------------------------------------------------------------
-- ROW 5: ROPE
----------------------------------------------------------------------
-- 5A: Rope swing
spawnTest(5, 0, "Rope: Swing", function(pos)
	local bar = makePart({
		position = pos + Vector3.new(0, 8, 0),
		size = Vector3.new(1, 1, 6),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local seat = makePart({
		position = pos + Vector3.new(0, 1, 0),
		size = Vector3.new(3, 0.5, 2),
		color = Color3.fromRGB(180, 120, 60),
		anchored = false,
	})
	local att0 = makeAttachment(bar, Vector3.new(0, -0.5, 0))
	local att1 = makeAttachment(seat, Vector3.new(0, 0.25, 0))
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = att0
	rope.Attachment1 = att1
	rope.Length = 6
	rope.Visible = true
	rope.Parent = bar
end)

-- 5B: Rope bridge segment
spawnTest(5, 1, "Rope: Bridge Plank", function(pos)
	local left = makePart({
		position = pos + Vector3.new(-4, 4, 0),
		size = Vector3.new(1, 1, 1),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local right = makePart({
		position = pos + Vector3.new(4, 4, 0),
		size = Vector3.new(1, 1, 1),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local plank = makePart({
		position = pos + Vector3.new(0, 1, 0),
		size = Vector3.new(6, 0.5, 3),
		color = Color3.fromRGB(160, 120, 60),
		anchored = false,
	})
	local att0L = makeAttachment(left, Vector3.new(0, -0.5, 0))
	local att1L = makeAttachment(plank, Vector3.new(-3, 0, 0))
	local rope1 = Instance.new("RopeConstraint")
	rope1.Attachment0 = att0L
	rope1.Attachment1 = att1L
	rope1.Length = 4
	rope1.Visible = true
	rope1.Parent = left
	local att0R = makeAttachment(right, Vector3.new(0, -0.5, 0))
	local att1R = makeAttachment(plank, Vector3.new(3, 0, 0))
	local rope2 = Instance.new("RopeConstraint")
	rope2.Attachment0 = att0R
	rope2.Attachment1 = att1R
	rope2.Length = 4
	rope2.Visible = true
	rope2.Parent = right
end)

-- 5C: Dangling weight
spawnTest(5, 2, "Rope: Dangling Weight", function(pos)
	local hook = makePart({
		position = pos + Vector3.new(0, 7, 0),
		size = Vector3.new(1, 1, 1),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local weight = makePart({
		position = pos + Vector3.new(0, 1, 0),
		size = Vector3.new(3, 3, 3),
		shape = Enum.PartType.Ball,
		color = Color3.fromRGB(60, 60, 60),
		anchored = false,
		density = 3,
	})
	local att0 = makeAttachment(hook, Vector3.new(0, -0.5, 0))
	local att1 = makeAttachment(weight, Vector3.new(0, 1.5, 0))
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = att0
	rope.Attachment1 = att1
	rope.Length = 5
	rope.Visible = true
	rope.Parent = hook
end)

----------------------------------------------------------------------
-- ROW 6: PRISMATIC
----------------------------------------------------------------------
-- 6A: Elevator
spawnTest(6, 0, "Prismatic: Elevator", function(pos)
	local shaft = makePart({
		position = pos,
		size = Vector3.new(1, 10, 1),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
		transparency = 0.5,
	})
	local platform = makePart({
		position = pos + Vector3.new(0, -3, 0),
		size = Vector3.new(6, 0.5, 6),
		color = Color3.fromRGB(50, 150, 255),
		anchored = false,
	})
	local att0 = makeAttachment(shaft, Vector3.new(0, 0, 0))
	local att1 = makeAttachment(platform, Vector3.new(0, 0, 0))
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -5
	prism.UpperLimit = 5
	prism.Parent = shaft
end)

-- 6B: Sliding door
spawnTest(6, 1, "Prismatic: Slide Door", function(pos)
	local frame = makePart({
		position = pos,
		size = Vector3.new(1, 6, 6),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
		transparency = 0.7,
	})
	local door = makePart({
		position = pos + Vector3.new(0, 0, -2),
		size = Vector3.new(0.5, 5, 4),
		color = Color3.fromRGB(180, 180, 200),
		anchored = false,
	})
	local att0 = makeAttachment(frame, Vector3.new(0, 0, 0))
	att0.Axis = Vector3.new(0, 0, 1) -- slide along Z
	local att1 = makeAttachment(door, Vector3.new(0, 0, 0))
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -3
	prism.UpperLimit = 0
	prism.Parent = frame
end)

-- 6C: Piston (spring-loaded prismatic)
spawnTest(6, 2, "Prismatic: Piston", function(pos)
	local cylinder = makePart({
		position = pos - Vector3.new(0, 1, 0),
		size = Vector3.new(2, 4, 2),
		shape = Enum.PartType.Cylinder,
		color = Color3.fromRGB(150, 150, 150),
		anchored = true,
	})
	local piston = makePart({
		position = pos + Vector3.new(0, 2, 0),
		size = Vector3.new(1.5, 2, 1.5),
		color = Color3.fromRGB(200, 200, 50),
		anchored = false,
	})
	local att0 = makeAttachment(cylinder, Vector3.new(0, 2, 0))
	local att1 = makeAttachment(piston, Vector3.new(0, -1, 0))
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 4
	prism.Parent = cylinder
end)

----------------------------------------------------------------------
-- ROW 7: TORSION SPRING
----------------------------------------------------------------------
-- 7A: Auto-close door
spawnTest(7, 0, "TorsionSpring: AutoDoor", function(pos)
	local frame = makePart({
		position = pos + Vector3.new(-2.5, 0, 0),
		size = Vector3.new(1, 8, 1),
		color = Color3.fromRGB(120, 80, 40),
		anchored = true,
	})
	local door = makePart({
		position = pos + Vector3.new(0, 0, 0),
		size = Vector3.new(4, 8, 0.5),
		color = Color3.fromRGB(160, 110, 60),
		anchored = false,
	})
	local att0 = makeAttachment(frame, Vector3.new(0.5, 0, 0))
	local att1 = makeAttachment(door, Vector3.new(-2, 0, 0))
	local ts = Instance.new("TorsionSpringConstraint")
	ts.Attachment0 = att0
	ts.Attachment1 = att1
	ts.Stiffness = 100
	ts.Damping = 10
	ts.MaxAngle = 90
	ts.Parent = frame
end)

-- 7B: Wobbly sign
spawnTest(7, 1, "TorsionSpring: Wobble Sign", function(pos)
	local post = makePart({
		position = pos + Vector3.new(0, 4, 0),
		size = Vector3.new(0.5, 1, 0.5),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local sign = makePart({
		position = pos + Vector3.new(0, 2, 0),
		size = Vector3.new(4, 3, 0.3),
		color = Color3.fromRGB(255, 255, 200),
		anchored = false,
	})
	local att0 = makeAttachment(post, Vector3.new(0, -0.5, 0))
	local att1 = makeAttachment(sign, Vector3.new(0, 1.5, 0))
	local ts = Instance.new("TorsionSpringConstraint")
	ts.Attachment0 = att0
	ts.Attachment1 = att1
	ts.Stiffness = 50
	ts.Damping = 2
	ts.MaxAngle = 30
	ts.Parent = post
end)

-- 7C: Spring flipper
spawnTest(7, 2, "TorsionSpring: Flipper", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local flipper = makePart({
		position = pos + Vector3.new(3, 0, 0),
		size = Vector3.new(8, 1, 3),
		color = Color3.fromRGB(255, 100, 100),
		anchored = false,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 1, 0))
	local att1 = makeAttachment(flipper, Vector3.new(-4, 0, 0))
	local ts = Instance.new("TorsionSpringConstraint")
	ts.Attachment0 = att0
	ts.Attachment1 = att1
	ts.Stiffness = 300
	ts.Damping = 5
	ts.MaxAngle = 45
	ts.Parent = base
end)

----------------------------------------------------------------------
-- ROW 8: ANGULAR VELOCITY
----------------------------------------------------------------------
-- 8A: Spinning fan (Y axis)
spawnTest(8, 0, "AngVel: Fan (Y)", function(pos)
	local post = makePart({
		position = pos,
		size = Vector3.new(2, 4, 2),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local blade = makePart({
		position = pos + Vector3.new(0, 3, 0),
		size = Vector3.new(10, 0.3, 2),
		color = Color3.fromRGB(200, 200, 200),
		anchored = false,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = post
	weld.Part1 = blade
	weld.Parent = post
	-- Unanchor post temporarily so weld takes hold, then re-anchor?
	-- Actually: AngularVelocity on the blade
	local att = makeAttachment(blade, Vector3.new(0, 0, 0))
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att
	av.AngularVelocity = Vector3.new(0, 10, 0)
	av.MaxTorque = 1000
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = blade
end)

-- 8B: Spinning platform (slow, X axis)
spawnTest(8, 1, "AngVel: Platform (slow)", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(1, 2, 1),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local disc = makePart({
		position = pos + Vector3.new(0, 0, 0),
		size = Vector3.new(8, 1, 8),
		shape = Enum.PartType.Cylinder,
		color = Color3.fromRGB(100, 200, 100),
		anchored = false,
	})
	local hinge_att0 = makeAttachment(base, Vector3.new(0, 1, 0))
	local hinge_att1 = makeAttachment(disc, Vector3.new(0, -0.5, 0))
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = hinge_att0
	hinge.Attachment1 = hinge_att1
	hinge.Parent = base
	local att = makeAttachment(disc, Vector3.new(0, 0, 0))
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att
	av.AngularVelocity = Vector3.new(0, 2, 0)
	av.MaxTorque = 5000
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = disc
end)

-- 8C: Windmill (Z axis)
spawnTest(8, 2, "AngVel: Windmill (Z)", function(pos)
	local tower = makePart({
		position = pos,
		size = Vector3.new(2, 8, 2),
		color = Color3.fromRGB(180, 160, 120),
		anchored = true,
	})
	local blades = makePart({
		position = pos + Vector3.new(0, 4, -1.5),
		size = Vector3.new(12, 12, 0.3),
		color = Color3.fromRGB(240, 240, 240),
		anchored = false,
	})
	local att_t = makeAttachment(tower, Vector3.new(0, 4, -1))
	local att_b = makeAttachment(blades, Vector3.new(0, 0, 0))
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att_t
	hinge.Attachment1 = att_b
	hinge.Parent = tower
	local att = makeAttachment(blades, Vector3.new(0, 0, 0))
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att
	av.AngularVelocity = Vector3.new(0, 0, 3)
	av.MaxTorque = 5000
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = blades
end)

----------------------------------------------------------------------
-- ROW 9: LINEAR VELOCITY
----------------------------------------------------------------------
-- 9A: Conveyor belt (moves things along X)
spawnTest(9, 0, "LinVel: Conveyor", function(pos)
	local belt = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(12, 1, 4),
		color = Color3.fromRGB(40, 40, 40),
		anchored = true,
		friction = 1.0,
		elasticity = 0,
	})
	-- LinearVelocity on an anchored part won't move it, but
	-- we can use surface velocity via Velocity property
	-- Actually let's test with an unanchored sliding block on top
	local slider = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(2, 1, 2),
		color = Color3.fromRGB(255, 150, 50),
		anchored = false,
	})
	-- Keep slider on the belt with prismatic
	local att0 = makeAttachment(belt, Vector3.new(0, 0.5, 0))
	att0.Axis = Vector3.new(1, 0, 0)
	local att1 = makeAttachment(slider, Vector3.new(0, -0.5, 0))
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -5
	prism.UpperLimit = 5
	prism.Parent = belt
	local att_lv = makeAttachment(slider, Vector3.new(0, 0, 0))
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(5, 0, 0)
	lv.MaxForce = 500
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = slider
end)

-- 9B: Floating orb (upward)
spawnTest(9, 1, "LinVel: Float Up", function(pos)
	local ground = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(4, 1, 4),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local orb = makePart({
		position = pos,
		size = Vector3.new(3, 3, 3),
		shape = Enum.PartType.Ball,
		color = Color3.fromRGB(100, 200, 255),
		material = Enum.Material.Neon,
		anchored = false,
	})
	-- Rope to keep it from flying away
	local att_g = makeAttachment(ground, Vector3.new(0, 0.5, 0))
	local att_o = makeAttachment(orb, Vector3.new(0, -1.5, 0))
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = att_g
	rope.Attachment1 = att_o
	rope.Length = 8
	rope.Visible = true
	rope.Parent = ground
	local att_lv = makeAttachment(orb, Vector3.new(0, 0, 0))
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 3, 0)
	lv.MaxForce = 200
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = orb
end)

-- 9C: Moving platform (back and forth via script)
spawnTest(9, 2, "LinVel: Moving Platform", function(pos)
	local rail = makePart({
		position = pos + Vector3.new(0, -2, 0),
		size = Vector3.new(16, 0.5, 4),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
		transparency = 0.5,
	})
	local platform = makePart({
		position = pos,
		size = Vector3.new(6, 1, 4),
		color = Color3.fromRGB(50, 200, 50),
		anchored = false,
	})
	local att0 = makeAttachment(rail, Vector3.new(0, 0.25, 0))
	att0.Axis = Vector3.new(1, 0, 0)
	local att1 = makeAttachment(platform, Vector3.new(0, -0.5, 0))
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -6
	prism.UpperLimit = 6
	prism.Parent = rail
	local att_lv = makeAttachment(platform, Vector3.new(0, 0, 0))
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(5, 0, 0)
	lv.MaxForce = 2000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = platform
	-- Reverse direction when hitting limits
	task.spawn(function()
		local dir = 1
		while platform.Parent do
			task.wait(3)
			dir = -dir
			lv.VectorVelocity = Vector3.new(5 * dir, 0, 0)
		end
	end)
end)

----------------------------------------------------------------------
-- BONUS: PURE ELASTICITY (no constraints)
----------------------------------------------------------------------
spawnTest(0, 3, "NO CONSTRAINT: Elastic Pad", function(pos)
	local pad = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(255, 100, 200),
		anchored = true,
		elasticity = 1.0,
	})
end)

print("[PhysicsTestGrid] Spawned", testNum, "test objects. Grid at", tostring(GRID_ORIGIN))
