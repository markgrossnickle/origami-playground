--!strict
-- PhysicsTestGrid v2: Fixed based on testing feedback.
-- DELETE THIS FILE after testing is complete.

local Players = game:GetService("Players")

local GRID_ORIGIN = Vector3.new(-200, 5, -200)
local COL_SPACING = 25
local ROW_SPACING = 25

local function makeLabel(parent: BasePart, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 250, 0, 50)
	bb.StudsOffset = Vector3.new(0, 6, 0)
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
	if props.density or props.friction or props.elasticity then
		part.CustomPhysicalProperties = PhysicalProperties.new(
			props.density or 0.7,
			props.friction or 0.3,
			props.elasticity or 0.5,
			1, 1
		)
	end
	part.Parent = workspace
	return part
end

local function makeAttachment(parent: BasePart, offset: Vector3?, axis: Vector3?): Attachment
	local att = Instance.new("Attachment")
	if offset then
		att.Position = offset
	end
	if axis then
		att.Axis = axis
	end
	att.Parent = parent
	return att
end

-- Helper: add bounce-on-touch to a part (the only way to bounce players)
local function addBouncePad(part: BasePart, force: number)
	local debounce: { [number]: boolean } = {}
	part.Touched:Connect(function(hit)
		local character = hit.Parent
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not rootPart then return end
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end
		if debounce[player.UserId] then return end
		debounce[player.UserId] = true
		-- Apply upward velocity
		rootPart.AssemblyLinearVelocity = Vector3.new(
			rootPart.AssemblyLinearVelocity.X,
			force,
			rootPart.AssemblyLinearVelocity.Z
		)
		task.delay(0.5, function()
			debounce[player.UserId] = nil
		end)
	end)
end

local testNum = 0
local function gridPos(row: number, col: number): Vector3
	return GRID_ORIGIN + Vector3.new(col * COL_SPACING, 0, row * ROW_SPACING)
end

local function spawnTest(row: number, col: number, label: string, builder: (Vector3) -> ())
	testNum += 1
	local pos = gridPos(row, col)
	local plate = makePart({
		position = pos - Vector3.new(0, 4.5, 0),
		size = Vector3.new(20, 1, 20),
		color = Color3.fromRGB(80, 80, 80),
		material = Enum.Material.Concrete,
	})
	makeLabel(plate, "#" .. testNum .. " " .. label)
	builder(pos)
end

task.wait(3)

----------------------------------------------------------------------
-- ROW 0: TRAMPOLINE / BOUNCE (testing what actually bounces players)
----------------------------------------------------------------------
-- 0A: Touched + AssemblyLinearVelocity (direct velocity set)
spawnTest(0, 0, "Bounce: Velocity (50)", function(pos)
	local pad = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(255, 100, 50),
		anchored = true,
	})
	addBouncePad(pad, 50)
end)

-- 0B: Touched + higher velocity
spawnTest(0, 1, "Bounce: Velocity (80)", function(pos)
	local pad = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(255, 200, 50),
		anchored = true,
	})
	addBouncePad(pad, 80)
end)

-- 0C: Touched + mega bounce
spawnTest(0, 2, "Bounce: Velocity (120)", function(pos)
	local pad = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(50, 255, 100),
		anchored = true,
	})
	addBouncePad(pad, 120)
end)

-- 0D: Spring + Touched bounce (visual spring flex + actual player bounce)
spawnTest(0, 3, "Bounce: Spring+Touched", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(6, 1, 6),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local platform = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.5, 8),
		color = Color3.fromRGB(255, 100, 50),
		anchored = false,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAttachment(platform, Vector3.new(0, -0.25, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 800
	spring.Damping = 10
	spring.FreeLength = 2
	spring.Visible = true
	spring.Parent = base
	addBouncePad(platform, 60)
end)

----------------------------------------------------------------------
-- ROW 1: HINGE (fixed axes and attachment points)
----------------------------------------------------------------------
-- 1A: Door (hinge on left edge, Y axis rotation)
spawnTest(1, 0, "Hinge: Door (Y axis)", function(pos)
	local frame = makePart({
		position = pos + Vector3.new(-3, 0, 0),
		size = Vector3.new(0.5, 8, 1),
		color = Color3.fromRGB(120, 80, 40),
		anchored = true,
	})
	local panel = makePart({
		position = pos + Vector3.new(0, 0, 0),
		size = Vector3.new(5, 8, 0.5),
		color = Color3.fromRGB(160, 110, 60),
		anchored = false,
	})
	-- Hinge axis = Y (up), attachment at the edge where frame meets panel
	local att0 = makeAttachment(frame, Vector3.new(0.25, 0, 0))
	att0.Axis = Vector3.new(0, 1, 0)
	local att1 = makeAttachment(panel, Vector3.new(-2.5, 0, 0))
	att1.Axis = Vector3.new(0, 1, 0)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = 0
	hinge.UpperAngle = 100
	hinge.Parent = frame
end)

-- 1B: Seesaw / Teeter-totter (hinge on Z axis so it tips along X length)
spawnTest(1, 1, "Hinge: Seesaw (Z axis)", function(pos)
	local post = makePart({
		position = pos - Vector3.new(0, 1.5, 0),
		size = Vector3.new(2, 3, 2),
		color = Color3.fromRGB(100, 100, 100),
		anchored = true,
	})
	local plank = makePart({
		position = pos + Vector3.new(0, 0.5, 0),
		size = Vector3.new(14, 0.5, 4),
		color = Color3.fromRGB(180, 140, 60),
		anchored = false,
	})
	-- Hinge at top of post, center of plank, rotating around Z
	local att0 = makeAttachment(post, Vector3.new(0, 1.5, 0))
	att0.Axis = Vector3.new(0, 0, 1)
	local att1 = makeAttachment(plank, Vector3.new(0, -0.25, 0))
	att1.Axis = Vector3.new(0, 0, 1)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -25
	hinge.UpperAngle = 25
	hinge.Parent = post
end)

-- 1C: Seesaw v2 (wider, no limits, see if it moves more freely)
spawnTest(1, 2, "Hinge: Seesaw Free", function(pos)
	local post = makePart({
		position = pos - Vector3.new(0, 1.5, 0),
		size = Vector3.new(2, 3, 2),
		color = Color3.fromRGB(100, 100, 100),
		anchored = true,
	})
	local plank = makePart({
		position = pos + Vector3.new(0, 0.5, 0),
		size = Vector3.new(16, 0.5, 5),
		color = Color3.fromRGB(200, 100, 50),
		anchored = false,
		density = 0.3, -- lighter so player weight matters more
	})
	local att0 = makeAttachment(post, Vector3.new(0, 1.5, 0))
	att0.Axis = Vector3.new(0, 0, 1)
	local att1 = makeAttachment(plank, Vector3.new(0, -0.25, 0))
	att1.Axis = Vector3.new(0, 0, 1)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.Parent = post
end)

-- 1D: Flipper (fixed, hinge at base end)
spawnTest(1, 3, "Hinge: Flipper (fixed)", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2.5, 0),
		size = Vector3.new(3, 1, 3),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local flipper = makePart({
		position = pos + Vector3.new(0, -1.5, 4),
		size = Vector3.new(3, 0.5, 8),
		color = Color3.fromRGB(255, 200, 50),
		anchored = false,
		density = 0.3,
	})
	-- Hinge at the base end of the flipper, X axis rotation
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 1.5))
	att0.Axis = Vector3.new(1, 0, 0)
	local att1 = makeAttachment(flipper, Vector3.new(0, 0, -4))
	att1.Axis = Vector3.new(1, 0, 0)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -5
	hinge.UpperAngle = 50
	hinge.Parent = base
end)

----------------------------------------------------------------------
-- ROW 2: BALL SOCKET (these worked, keeping)
----------------------------------------------------------------------
spawnTest(2, 0, "BallSocket: Swing", function(pos)
	local bar = makePart({
		position = pos + Vector3.new(0, 6, 0),
		size = Vector3.new(1, 1, 8),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local seat = makePart({
		position = pos,
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

spawnTest(2, 1, "BallSocket: Wrecking Ball", function(pos)
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
	})
	local att0 = makeAttachment(crane, Vector3.new(0, -0.5, 0))
	local att1 = makeAttachment(ball, Vector3.new(0, 2, 0))
	local bs = Instance.new("BallSocketConstraint")
	bs.Attachment0 = att0
	bs.Attachment1 = att1
	bs.Parent = crane
end)

----------------------------------------------------------------------
-- ROW 3: ROD + ROPE (proven to work)
----------------------------------------------------------------------
-- Rod pendulum
spawnTest(3, 0, "Rod: Pendulum", function(pos)
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
	local att0 = makeAttachment(pivot)
	local att1 = makeAttachment(weight)
	local rod = Instance.new("RodConstraint")
	rod.Attachment0 = att0
	rod.Attachment1 = att1
	rod.Length = 5
	rod.Visible = true
	rod.Parent = pivot
end)

-- Hanging sign (worked great)
spawnTest(3, 1, "Rod: Hanging Sign", function(pos)
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

-- Rope swing (worked)
spawnTest(3, 2, "Rope: Swing", function(pos)
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

-- Rope dangler (worked great)
spawnTest(3, 3, "Rope: Dangler", function(pos)
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
-- ROW 4: PRISMATIC (elevator worked via moving platform)
----------------------------------------------------------------------
spawnTest(4, 0, "Prismatic: Elevator", function(pos)
	local shaft = makePart({
		position = pos,
		size = Vector3.new(1, 12, 1),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
		transparency = 0.5,
	})
	local platform = makePart({
		position = pos - Vector3.new(0, 4, 0),
		size = Vector3.new(6, 0.5, 6),
		color = Color3.fromRGB(50, 150, 255),
		anchored = false,
	})
	local att0 = makeAttachment(shaft)
	att0.Axis = Vector3.new(0, 1, 0) -- slide along Y
	local att1 = makeAttachment(platform)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -5
	prism.UpperLimit = 5
	prism.Parent = shaft
	-- Auto move up and down
	local att_lv = makeAttachment(platform)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 3, 0)
	lv.MaxForce = 5000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = platform
	task.spawn(function()
		local dir = 1
		while platform.Parent do
			task.wait(4)
			dir = -dir
			lv.VectorVelocity = Vector3.new(0, 3 * dir, 0)
		end
	end)
end)

-- Moving platform (worked)
spawnTest(4, 1, "Prismatic: Moving Platform", function(pos)
	local rail = makePart({
		position = pos - Vector3.new(0, 2, 0),
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
	local att_lv = makeAttachment(platform)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(5, 0, 0)
	lv.MaxForce = 5000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = platform
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
-- ROW 5: TORSION SPRING (fixed - stronger, better attachments)
----------------------------------------------------------------------
-- 5A: Auto-close door (much stiffer, proper axis)
spawnTest(5, 0, "TorsionSpring: Door v2", function(pos)
	local frame = makePart({
		position = pos + Vector3.new(-3, 0, 0),
		size = Vector3.new(0.5, 8, 1),
		color = Color3.fromRGB(120, 80, 40),
		anchored = true,
	})
	local door = makePart({
		position = pos + Vector3.new(0, 0, 0),
		size = Vector3.new(5, 8, 0.5),
		color = Color3.fromRGB(160, 110, 60),
		anchored = false,
		density = 0.3,
	})
	local att0 = makeAttachment(frame, Vector3.new(0.25, 0, 0))
	att0.Axis = Vector3.new(0, 1, 0)
	local att1 = makeAttachment(door, Vector3.new(-2.5, 0, 0))
	att1.Axis = Vector3.new(0, 1, 0)
	local ts = Instance.new("TorsionSpringConstraint")
	ts.Attachment0 = att0
	ts.Attachment1 = att1
	ts.Stiffness = 500
	ts.Damping = 30
	ts.MaxAngle = 90
	ts.Parent = frame
end)

-- 5B: Wobbly sign on torsion spring
spawnTest(5, 1, "TorsionSpring: Wobbly Sign", function(pos)
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
		density = 0.2,
	})
	local att0 = makeAttachment(post, Vector3.new(0, -0.5, 0))
	att0.Axis = Vector3.new(0, 0, 1)
	local att1 = makeAttachment(sign, Vector3.new(0, 1.5, 0))
	att1.Axis = Vector3.new(0, 0, 1)
	local ts = Instance.new("TorsionSpringConstraint")
	ts.Attachment0 = att0
	ts.Attachment1 = att1
	ts.Stiffness = 200
	ts.Damping = 5
	ts.MaxAngle = 30
	ts.Parent = post
end)

----------------------------------------------------------------------
-- ROW 6: ANGULAR VELOCITY (spinning things)
----------------------------------------------------------------------
-- 6A: Spinning fan on hinge
spawnTest(6, 0, "AngVel: Fan on Hinge", function(pos)
	local post = makePart({
		position = pos,
		size = Vector3.new(2, 6, 2),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local blade = makePart({
		position = pos + Vector3.new(0, 3.5, 0),
		size = Vector3.new(10, 0.3, 2),
		color = Color3.fromRGB(200, 200, 200),
		anchored = false,
		density = 0.2,
	})
	-- Hinge to keep it attached
	local att_h0 = makeAttachment(post, Vector3.new(0, 3, 0))
	att_h0.Axis = Vector3.new(0, 1, 0)
	local att_h1 = makeAttachment(blade, Vector3.new(0, 0, 0))
	att_h1.Axis = Vector3.new(0, 1, 0)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att_h0
	hinge.Attachment1 = att_h1
	hinge.Parent = post
	-- Spin it
	local att_av = makeAttachment(blade)
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att_av
	av.AngularVelocity = Vector3.new(0, 8, 0)
	av.MaxTorque = 2000
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = blade
end)

-- 6B: Slow spinning platform (rideable)
spawnTest(6, 1, "AngVel: Spin Platform", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2.5, 0),
		size = Vector3.new(1, 1, 1),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local disc = makePart({
		position = pos - Vector3.new(0, 1, 0),
		size = Vector3.new(10, 1, 10),
		color = Color3.fromRGB(100, 200, 100),
		anchored = false,
	})
	local att_h0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_h0.Axis = Vector3.new(0, 1, 0)
	local att_h1 = makeAttachment(disc, Vector3.new(0, -0.5, 0))
	att_h1.Axis = Vector3.new(0, 1, 0)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att_h0
	hinge.Attachment1 = att_h1
	hinge.Parent = base
	local att_av = makeAttachment(disc)
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att_av
	av.AngularVelocity = Vector3.new(0, 1.5, 0)
	av.MaxTorque = 10000
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = disc
end)

-- 6C: Windmill
spawnTest(6, 2, "AngVel: Windmill", function(pos)
	local tower = makePart({
		position = pos,
		size = Vector3.new(2, 8, 2),
		color = Color3.fromRGB(180, 160, 120),
		anchored = true,
	})
	local blades = makePart({
		position = pos + Vector3.new(0, 4, -1.5),
		size = Vector3.new(10, 10, 0.3),
		color = Color3.fromRGB(240, 240, 240),
		anchored = false,
		density = 0.1,
	})
	local att_h0 = makeAttachment(tower, Vector3.new(0, 4, -1))
	att_h0.Axis = Vector3.new(0, 0, 1)
	local att_h1 = makeAttachment(blades)
	att_h1.Axis = Vector3.new(0, 0, 1)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att_h0
	hinge.Attachment1 = att_h1
	hinge.Parent = tower
	local att_av = makeAttachment(blades)
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att_av
	av.AngularVelocity = Vector3.new(0, 0, 3)
	av.MaxTorque = 5000
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = blades
end)

----------------------------------------------------------------------
-- ROW 7: LINEAR VELOCITY (fixed float up force)
----------------------------------------------------------------------
-- 7A: Floating orb (much more force)
spawnTest(7, 0, "LinVel: Float Up (fixed)", function(pos)
	local ground = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(4, 1, 4),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local orb = makePart({
		position = pos + Vector3.new(0, 1, 0),
		size = Vector3.new(3, 3, 3),
		shape = Enum.PartType.Ball,
		color = Color3.fromRGB(100, 200, 255),
		material = Enum.Material.Neon,
		anchored = false,
		density = 0.1, -- very light
	})
	local att_g = makeAttachment(ground, Vector3.new(0, 0.5, 0))
	local att_o = makeAttachment(orb, Vector3.new(0, -1.5, 0))
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = att_g
	rope.Attachment1 = att_o
	rope.Length = 8
	rope.Visible = true
	rope.Parent = ground
	local att_lv = makeAttachment(orb)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 5, 0)
	lv.MaxForce = 2000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = orb
end)

-- 7B: Conveyor block
spawnTest(7, 1, "LinVel: Conveyor Block", function(pos)
	local belt = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(14, 1, 4),
		color = Color3.fromRGB(40, 40, 40),
		anchored = true,
	})
	local slider = makePart({
		position = pos - Vector3.new(4, 0.5, 0),
		size = Vector3.new(2, 1, 2),
		color = Color3.fromRGB(255, 150, 50),
		anchored = false,
		density = 0.3,
	})
	local att0 = makeAttachment(belt, Vector3.new(0, 0.5, 0))
	att0.Axis = Vector3.new(1, 0, 0)
	local att1 = makeAttachment(slider, Vector3.new(0, -0.5, 0))
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -6
	prism.UpperLimit = 6
	prism.Parent = belt
	local att_lv = makeAttachment(slider)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(4, 0, 0)
	lv.MaxForce = 1000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = slider
	task.spawn(function()
		local dir = 1
		while slider.Parent do
			task.wait(3)
			dir = -dir
			lv.VectorVelocity = Vector3.new(4 * dir, 0, 0)
		end
	end)
end)

----------------------------------------------------------------------
-- ROW 8: COMBO OBJECTS (interesting combos)
----------------------------------------------------------------------
-- 8A: Bouncy seesaw (hinge + bounce pads on ends)
spawnTest(8, 0, "Combo: Bounce Seesaw", function(pos)
	local post = makePart({
		position = pos - Vector3.new(0, 1.5, 0),
		size = Vector3.new(2, 3, 2),
		color = Color3.fromRGB(100, 100, 100),
		anchored = true,
	})
	local plank = makePart({
		position = pos + Vector3.new(0, 0.5, 0),
		size = Vector3.new(14, 0.5, 4),
		color = Color3.fromRGB(255, 150, 50),
		anchored = false,
		density = 0.2,
	})
	local att0 = makeAttachment(post, Vector3.new(0, 1.5, 0))
	att0.Axis = Vector3.new(0, 0, 1)
	local att1 = makeAttachment(plank, Vector3.new(0, -0.25, 0))
	att1.Axis = Vector3.new(0, 0, 1)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -25
	hinge.UpperAngle = 25
	hinge.Parent = post
	addBouncePad(plank, 50)
end)

-- 8B: Rope bridge with bounce
spawnTest(8, 1, "Combo: Rope Bridge", function(pos)
	local left = makePart({
		position = pos + Vector3.new(-5, 4, 0),
		size = Vector3.new(1, 1, 6),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	local right = makePart({
		position = pos + Vector3.new(5, 4, 0),
		size = Vector3.new(1, 1, 6),
		color = Color3.fromRGB(80, 80, 80),
		anchored = true,
	})
	-- 3 bridge planks
	for i = -1, 1 do
		local plank = makePart({
			position = pos + Vector3.new(i * 3, 0, 0),
			size = Vector3.new(3, 0.4, 4),
			color = Color3.fromRGB(160, 120, 60),
			anchored = false,
			density = 0.3,
		})
		local attL = makeAttachment(left, Vector3.new(0, -0.5, 0))
		local attPL = makeAttachment(plank, Vector3.new(-1.5, 0, 0))
		local ropeL = Instance.new("RopeConstraint")
		ropeL.Attachment0 = attL
		ropeL.Attachment1 = attPL
		ropeL.Length = 5 + math.abs(i)
		ropeL.Visible = true
		ropeL.Parent = left
		local attR = makeAttachment(right, Vector3.new(0, -0.5, 0))
		local attPR = makeAttachment(plank, Vector3.new(1.5, 0, 0))
		local ropeR = Instance.new("RopeConstraint")
		ropeR.Attachment0 = attR
		ropeR.Attachment1 = attPR
		ropeR.Length = 5 + math.abs(i)
		ropeR.Visible = true
		ropeR.Parent = right
	end
end)

-- 8C: Catapult (hinge + spring combo)
spawnTest(8, 2, "Combo: Catapult", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2.5, 0),
		size = Vector3.new(4, 1, 4),
		color = Color3.fromRGB(80, 60, 40),
		anchored = true,
	})
	local arm = makePart({
		position = pos + Vector3.new(0, 0, 0),
		size = Vector3.new(2, 0.5, 10),
		color = Color3.fromRGB(140, 100, 50),
		anchored = false,
		density = 0.2,
	})
	-- Hinge at center
	local att_h0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_h0.Axis = Vector3.new(1, 0, 0)
	local att_h1 = makeAttachment(arm, Vector3.new(0, 0, 0))
	att_h1.Axis = Vector3.new(1, 0, 0)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att_h0
	hinge.Attachment1 = att_h1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -30
	hinge.UpperAngle = 30
	hinge.Parent = base
	-- Spring pulling one end down (loads the catapult)
	local att_s0 = makeAttachment(base, Vector3.new(0, 0.5, -2))
	local att_s1 = makeAttachment(arm, Vector3.new(0, 0, -4))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att_s0
	spring.Attachment1 = att_s1
	spring.Stiffness = 300
	spring.Damping = 5
	spring.FreeLength = 1
	spring.Visible = true
	spring.Parent = base
	-- Bounce pad on the other end
	local bucket = makePart({
		position = pos + Vector3.new(0, 0.5, 4.5),
		size = Vector3.new(2, 0.3, 2),
		color = Color3.fromRGB(200, 50, 50),
		anchored = false,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = arm
	weld.Part1 = bucket
	weld.Parent = arm
	addBouncePad(bucket, 80)
end)

print("[PhysicsTestGrid v2] Spawned", testNum, "test objects. Grid at", tostring(GRID_ORIGIN))
