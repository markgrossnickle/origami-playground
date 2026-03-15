--!strict
-- PhysicsTestGrid v3: 10 trampoline approaches (pure physics, no Touched handlers)
-- Plus proven working objects from v2.
-- DELETE THIS FILE after testing is complete.

local GRID_ORIGIN = Vector3.new(-200, 5, -200)
local COL_SPACING = 25
local ROW_SPACING = 25

local function makeLabel(parent: BasePart, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 300, 0, 50)
	bb.StudsOffset = Vector3.new(0, 7, 0)
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
	if props.massless then
		part.Massless = true
	end
	if props.density or props.friction or props.elasticity then
		part.CustomPhysicalProperties = PhysicalProperties.new(
			props.density or 0.7,
			props.friction or 0.3,
			props.elasticity or 0.5,
			props.frictionWeight or 1,
			props.elasticityWeight or 1
		)
	end
	part.Parent = workspace
	return part
end

local function makeAttachment(parent: BasePart, offset: Vector3?, axis: Vector3?): Attachment
	local att = Instance.new("Attachment")
	if offset then att.Position = offset end
	if axis then att.Axis = axis end
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
-- ROW 0: TRAMPOLINE TEST 1-3 (Spring variations)
----------------------------------------------------------------------
-- #1: Ultra-stiff spring, featherweight platform
spawnTest(0, 0, "T1: UltraStiff Spring", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(255, 80, 50),
		anchored = false,
		density = 0.01,
		elasticity = 1.0,
		elasticityWeight = 100,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAttachment(pad, Vector3.new(0, -0.15, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 50000
	spring.Damping = 0
	spring.FreeLength = 2
	spring.Visible = true
	spring.Parent = base
end)

-- #2: Pre-loaded spring (FreeLength > distance = always pushing up)
spawnTest(0, 1, "T2: PreLoaded Spring", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(255, 180, 50),
		anchored = false,
		density = 0.01,
		elasticity = 1.0,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAttachment(pad, Vector3.new(0, -0.15, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 10000
	spring.Damping = 0
	spring.FreeLength = 10 -- much longer than actual distance = always pushing up
	spring.Visible = true
	spring.Parent = base
	-- Prismatic to keep it from flying sideways
	local att_p0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_p0.Axis = Vector3.new(0, 1, 0)
	local att_p1 = makeAttachment(pad, Vector3.new(0, 0, 0))
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att_p0
	prism.Attachment1 = att_p1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 4
	prism.Parent = base
end)

-- #3: Triple springs in parallel
spawnTest(0, 2, "T3: Triple Springs", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(50, 255, 100),
		anchored = false,
		density = 0.01,
		elasticity = 1.0,
	})
	for _, offset in { Vector3.new(-2, 0, 0), Vector3.new(0, 0, 0), Vector3.new(2, 0, 0) } do
		local att0 = makeAttachment(base, Vector3.new(offset.X, 0.5, offset.Z))
		local att1 = makeAttachment(pad, Vector3.new(offset.X, -0.15, offset.Z))
		local spring = Instance.new("SpringConstraint")
		spring.Attachment0 = att0
		spring.Attachment1 = att1
		spring.Stiffness = 20000
		spring.Damping = 0
		spring.FreeLength = 2
		spring.Visible = true
		spring.Parent = base
	end
end)

----------------------------------------------------------------------
-- ROW 1: TRAMPOLINE TEST 4-6 (Force/velocity based)
----------------------------------------------------------------------
-- #4: VectorForce up on platform
spawnTest(1, 0, "T4: VectorForce Up", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(100, 100, 255),
		anchored = false,
		density = 0.05,
	})
	-- Prismatic to keep vertical only
	local att_p0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_p0.Axis = Vector3.new(0, 1, 0)
	local att_p1 = makeAttachment(pad)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att_p0
	prism.Attachment1 = att_p1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 6
	prism.Parent = base
	-- Constant upward force
	local att_vf = makeAttachment(pad)
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att_vf
	vf.Force = Vector3.new(0, 3000, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = pad
end)

-- #5: LinearVelocity up + Prismatic
spawnTest(1, 1, "T5: LinVel Up + Prismatic", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(150, 50, 255),
		anchored = false,
		density = 0.05,
	})
	local att_p0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_p0.Axis = Vector3.new(0, 1, 0)
	local att_p1 = makeAttachment(pad)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att_p0
	prism.Attachment1 = att_p1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 5
	prism.Parent = base
	-- Constant upward velocity
	local att_lv = makeAttachment(pad)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 20, 0)
	lv.MaxForce = 5000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = pad
end)

-- #6: AlignPosition (snaps back to target height)
spawnTest(1, 2, "T6: AlignPosition Snap", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(255, 50, 255),
		anchored = false,
		density = 0.05,
	})
	-- Prismatic for vertical only
	local att_p0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_p0.Axis = Vector3.new(0, 1, 0)
	local att_p1 = makeAttachment(pad)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att_p0
	prism.Attachment1 = att_p1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 6
	prism.Parent = base
	-- AlignPosition pulling pad to target height
	local att_ap = makeAttachment(pad)
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att_ap
	ap.Position = pos + Vector3.new(0, 2, 0) -- target position above rest
	ap.MaxForce = 10000
	ap.Responsiveness = 200
	ap.Parent = pad
end)

----------------------------------------------------------------------
-- ROW 2: TRAMPOLINE TEST 7-10 (Creative approaches)
----------------------------------------------------------------------
-- #7: Massless platform + stiff spring
spawnTest(2, 0, "T7: Massless + Spring", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(255, 255, 50),
		anchored = false,
		massless = true,
		elasticity = 1.0,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAttachment(pad, Vector3.new(0, -0.15, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 30000
	spring.Damping = 0
	spring.FreeLength = 2
	spring.Visible = true
	spring.Parent = base
end)

-- #8: TorsionSpring catapult pad (tilting launcher)
spawnTest(2, 1, "T8: TorsionSpring Catapult", function(pos)
	local pivot = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(2, 2, 2),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos + Vector3.new(0, -0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(50, 200, 255),
		anchored = false,
		density = 0.05,
	})
	local att0 = makeAttachment(pivot, Vector3.new(0, 1, 0))
	att0.Axis = Vector3.new(0, 0, 1)
	local att1 = makeAttachment(pad, Vector3.new(0, 0, 0))
	att1.Axis = Vector3.new(0, 0, 1)
	local ts = Instance.new("TorsionSpringConstraint")
	ts.Attachment0 = att0
	ts.Attachment1 = att1
	ts.Stiffness = 5000
	ts.Damping = 0
	ts.MaxAngle = 30
	ts.Parent = pivot
end)

-- #9: Motor-driven hinge flipper (continuous rotation hits player)
spawnTest(2, 2, "T9: Motor Hinge Flipper", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2.5, 0),
		size = Vector3.new(3, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local flipper = makePart({
		position = pos + Vector3.new(0, -1, 4),
		size = Vector3.new(3, 0.5, 8),
		color = Color3.fromRGB(255, 100, 100),
		anchored = false,
		density = 0.3,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att0.Axis = Vector3.new(1, 0, 0)
	local att1 = makeAttachment(flipper, Vector3.new(0, 0, -4))
	att1.Axis = Vector3.new(1, 0, 0)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = 5
	hinge.MotorMaxTorque = 5000
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -10
	hinge.UpperAngle = 80
	hinge.Parent = base
	-- Reverse motor direction when it hits limit
	task.spawn(function()
		while hinge.Parent do
			task.wait(2)
			hinge.AngularVelocity = -hinge.AngularVelocity
		end
	end)
end)

-- #10: Spring + VectorForce combo (spring for oscillation + force for energy)
spawnTest(2, 3, "T10: Spring + VectorForce", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(100, 255, 200),
		anchored = false,
		density = 0.01,
		elasticity = 1.0,
	})
	-- Prismatic vertical constraint
	local att_p0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_p0.Axis = Vector3.new(0, 1, 0)
	local att_p1 = makeAttachment(pad)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att_p0
	prism.Attachment1 = att_p1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 5
	prism.Parent = base
	-- Spring for bounce
	local att_s0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att_s1 = makeAttachment(pad, Vector3.new(0, -0.15, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att_s0
	spring.Attachment1 = att_s1
	spring.Stiffness = 30000
	spring.Damping = 0
	spring.FreeLength = 3
	spring.Visible = true
	spring.Parent = base
	-- VectorForce for extra push
	local att_vf = makeAttachment(pad)
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att_vf
	vf.Force = Vector3.new(0, 2000, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = pad
end)

----------------------------------------------------------------------
-- ROW 3: LUDICROUS MODE (should launch to space or nothing works)
----------------------------------------------------------------------
-- #11: Ludicrous VectorForce (100k newtons up)
spawnTest(3, 0, "LUDICROUS: 100k VectorForce", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(255, 0, 0),
		anchored = false,
		density = 0.01,
	})
	local att_p0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_p0.Axis = Vector3.new(0, 1, 0)
	local att_p1 = makeAttachment(pad)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att_p0
	prism.Attachment1 = att_p1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 15
	prism.Parent = base
	local att_vf = makeAttachment(pad)
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att_vf
	vf.Force = Vector3.new(0, 100000, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = pad
end)

-- #12: Ludicrous LinearVelocity (200 studs/s up, infinite force)
spawnTest(3, 1, "LUDICROUS: LinVel 200 up", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(255, 0, 255),
		anchored = false,
		density = 0.01,
	})
	local att_p0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_p0.Axis = Vector3.new(0, 1, 0)
	local att_p1 = makeAttachment(pad)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att_p0
	prism.Attachment1 = att_p1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 15
	prism.Parent = base
	local att_lv = makeAttachment(pad)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 200, 0)
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = pad
end)

-- #13: Ludicrous Spring (stiffness 1 million, zero damping)
spawnTest(3, 2, "LUDICROUS: 1M Spring", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(0, 255, 0),
		anchored = false,
		density = 0.01,
		elasticity = 1.0,
	})
	local att0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAttachment(pad, Vector3.new(0, -0.15, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 1000000
	spring.Damping = 0
	spring.FreeLength = 5
	spring.Visible = true
	spring.Parent = base
end)

-- #14: Ludicrous AlignPosition (target 500 studs up, max everything)
spawnTest(3, 3, "LUDICROUS: AlignPos 500up", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makePart({
		position = pos - Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.3, 8),
		color = Color3.fromRGB(0, 200, 255),
		anchored = false,
		density = 0.01,
	})
	local att_p0 = makeAttachment(base, Vector3.new(0, 0.5, 0))
	att_p0.Axis = Vector3.new(0, 1, 0)
	local att_p1 = makeAttachment(pad)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att_p0
	prism.Attachment1 = att_p1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = 20
	prism.Parent = base
	local att_ap = makeAttachment(pad)
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att_ap
	ap.Position = pos + Vector3.new(0, 500, 0)
	ap.MaxForce = math.huge
	ap.Responsiveness = 200
	ap.Parent = pad
end)

-- #15: No prismatic, just raw VectorForce on free part (see if pad flies)
spawnTest(3, 4, "LUDICROUS: Free VectorForce", function(pos)
	local pad = makePart({
		position = pos - Vector3.new(0, 2, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(255, 255, 0),
		anchored = false,
		density = 0.01,
	})
	local att_vf = makeAttachment(pad)
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att_vf
	vf.Force = Vector3.new(0, 50000, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = pad
end)

----------------------------------------------------------------------
-- ROW 4-7: PROVEN WORKING OBJECTS (from v2)
----------------------------------------------------------------------
-- Seesaw (works!)
spawnTest(4, 0, "Hinge: Seesaw", function(pos)
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
		density = 0.2,
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

-- Hinge door (fixed)
spawnTest(4, 1, "Hinge: Door", function(pos)
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

-- Rod hanging sign (works!)
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

-- Rope dangler (works!)
spawnTest(4, 3, "Rope: Dangler", function(pos)
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

-- Moving platform (works!)
spawnTest(5, 0, "Prismatic: Moving Platform", function(pos)
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

-- Spinning platform (from v2)
spawnTest(5, 1, "AngVel: Spin Platform", function(pos)
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

-- Windmill
spawnTest(5, 2, "AngVel: Windmill", function(pos)
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

-- Elevator
spawnTest(5, 3, "Prismatic: Elevator", function(pos)
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
	att0.Axis = Vector3.new(0, 1, 0)
	local att1 = makeAttachment(platform)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -5
	prism.UpperLimit = 5
	prism.Parent = shaft
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

print("[PhysicsTestGrid v3] Spawned", testNum, "test objects. Grid at", tostring(GRID_ORIGIN))
