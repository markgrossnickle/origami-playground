--!strict
-- PhysicsTestGrid v5: Fixed AlignOrientation (TwoAttachment mode), lowered limits.
-- Testing momentum-transfer bounce: pad accelerates up → prismatic limit stops pad → player keeps going.
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
	if props.shape then part.Shape = props.shape end
	if props.transparency then part.Transparency = props.transparency end
	if props.canCollide ~= nil then part.CanCollide = props.canCollide end
	if props.massless then part.Massless = true end
	if props.density or props.friction or props.elasticity then
		part.CustomPhysicalProperties = PhysicalProperties.new(
			props.density or 0.7, props.friction or 0.3, props.elasticity or 0.5, 1, 1
		)
	end
	part.Parent = workspace
	return part
end

local function makeAtt(parent: BasePart, offset: Vector3?, axis: Vector3?): Attachment
	local att = Instance.new("Attachment")
	if offset then att.Position = offset end
	if axis then att.Axis = axis end
	att.Parent = parent
	return att
end

-- Keep a part level (no rotation) by matching an anchored reference part's orientation
local function keepFlat(part: BasePart, referencePart: BasePart)
	local att0 = makeAtt(part)
	local att1 = makeAtt(referencePart)
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	ao.Attachment0 = att0
	ao.Attachment1 = att1
	ao.MaxTorque = math.huge
	ao.Responsiveness = 200
	ao.Parent = part
end

-- Create a standard vertical-only pad with AlignOrientation (stays flat using base as reference)
local function makeBouncePad(base: BasePart, pos: Vector3, color: Color3, upperLimit: number): Part
	local pad = makePart({
		position = pos + Vector3.new(0, 0.5, 0),
		size = Vector3.new(8, 0.5, 8),
		color = color,
		anchored = false,
		density = 0.1,
	})
	keepFlat(pad, base)
	-- Prismatic: vertical only
	local att0 = makeAtt(base, Vector3.new(0, 0.5, 0))
	att0.Axis = Vector3.new(0, 1, 0)
	local att1 = makeAtt(pad)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = 0
	prism.UpperLimit = upperLimit
	prism.Parent = base
	return pad
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
-- ROW 0: SPRING BOUNCE (pad stays flat, spring rebounds when player jumps)
----------------------------------------------------------------------
-- Player stands on pad → spring compresses → player jumps → spring flings pad up → pad hits player?
spawnTest(0, 0, "Spring 2k stiff", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(255, 80, 50), 4)
	local att0 = makeAtt(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAtt(pad, Vector3.new(0, -0.25, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 2000
	spring.Damping = 0
	spring.FreeLength = 2
	spring.Visible = true
	spring.Parent = base
end)

spawnTest(0, 1, "Spring 5k stiff", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(255, 150, 50), 4)
	local att0 = makeAtt(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAtt(pad, Vector3.new(0, -0.25, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 5000
	spring.Damping = 0
	spring.FreeLength = 2
	spring.Visible = true
	spring.Parent = base
end)

spawnTest(0, 2, "Spring 10k stiff", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(50, 255, 100), 4)
	local att0 = makeAtt(base, Vector3.new(0, 0.5, 0))
	local att1 = makeAtt(pad, Vector3.new(0, -0.25, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = att0
	spring.Attachment1 = att1
	spring.Stiffness = 10000
	spring.Damping = 0
	spring.FreeLength = 2
	spring.Visible = true
	spring.Parent = base
end)

----------------------------------------------------------------------
-- ROW 1: VECTORFORCE LAUNCHER (pad carries player up, limit stops pad)
-- Concept: pad has constant upward force but gravity keeps it at bottom.
-- Player stands on it → pad held down by player+gravity.
-- The upward force means pad+player accelerate up. Prismatic stops pad. Player has momentum.
----------------------------------------------------------------------
spawnTest(1, 0, "VForce 3k + limit 5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(100, 100, 255), 5)
	local att_vf = makeAtt(pad)
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att_vf
	vf.Force = Vector3.new(0, 3000, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = pad
end)

spawnTest(1, 1, "VForce 5k + limit 5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(150, 50, 255), 5)
	local att_vf = makeAtt(pad)
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att_vf
	vf.Force = Vector3.new(0, 5000, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = pad
end)

spawnTest(1, 2, "VForce 10k + limit 5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(255, 50, 255), 5)
	local att_vf = makeAtt(pad)
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att_vf
	vf.Force = Vector3.new(0, 10000, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = pad
end)

spawnTest(1, 3, "VForce 20k + limit 5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(255, 0, 100), 5)
	local att_vf = makeAtt(pad)
	local vf = Instance.new("VectorForce")
	vf.Attachment0 = att_vf
	vf.Force = Vector3.new(0, 20000, 0)
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Parent = pad
end)

----------------------------------------------------------------------
-- ROW 2: LINEAR VELOCITY LAUNCHER (pad moves up at set speed, carries player)
----------------------------------------------------------------------
spawnTest(2, 0, "LinVel 10 up, limit 5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(50, 200, 200), 5)
	local att_lv = makeAtt(pad)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 10, 0)
	lv.MaxForce = 10000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = pad
end)

spawnTest(2, 1, "LinVel 30 up, limit 5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(50, 255, 150), 5)
	local att_lv = makeAtt(pad)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 30, 0)
	lv.MaxForce = 20000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = pad
end)

spawnTest(2, 2, "LinVel 60 up, limit 5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(200, 255, 50), 5)
	local att_lv = makeAtt(pad)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 60, 0)
	lv.MaxForce = 50000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = pad
end)

spawnTest(2, 3, "LinVel 100 up, limit 5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(255, 200, 50), 5)
	local att_lv = makeAtt(pad)
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att_lv
	lv.VectorVelocity = Vector3.new(0, 100, 0)
	lv.MaxForce = math.huge
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = pad
end)

----------------------------------------------------------------------
-- ROW 3: ALIGNPOSITION LAUNCHER (pad snaps to high target, carries player)
----------------------------------------------------------------------
spawnTest(3, 0, "AlignPos target +5", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(255, 100, 255), 5)
	local att_ap = makeAtt(pad)
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att_ap
	ap.Position = pos + Vector3.new(0, 5, 0)
	ap.MaxForce = 10000
	ap.Responsiveness = 50
	ap.Parent = pad
end)

spawnTest(3, 1, "AlignPos target +5 fast", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(200, 50, 200), 5)
	local att_ap = makeAtt(pad)
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att_ap
	ap.Position = pos + Vector3.new(0, 5, 0)
	ap.MaxForce = 30000
	ap.Responsiveness = 100
	ap.Parent = pad
end)

spawnTest(3, 2, "AlignPos target +5 max", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 3, 0),
		size = Vector3.new(8, 1, 8),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local pad = makeBouncePad(base, pos, Color3.fromRGB(150, 0, 255), 5)
	local att_ap = makeAtt(pad)
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att_ap
	ap.Position = pos + Vector3.new(0, 5, 0)
	ap.MaxForce = math.huge
	ap.Responsiveness = 200
	ap.Parent = pad
end)

----------------------------------------------------------------------
-- ROW 4: MOTOR HINGE FLIPPER (fixed — hinge that swings up and flings player)
----------------------------------------------------------------------
spawnTest(4, 0, "Motor Flipper slow", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2.5, 0),
		size = Vector3.new(10, 1, 3),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local flipper = makePart({
		position = pos + Vector3.new(5, -1.5, 0),
		size = Vector3.new(10, 0.5, 8),
		color = Color3.fromRGB(255, 100, 100),
		anchored = false,
		density = 0.1,
	})
	local att0 = makeAtt(base, Vector3.new(0, 0.5, 0))
	att0.Axis = Vector3.new(0, 0, 1)
	local att1 = makeAtt(flipper, Vector3.new(-5, 0, 0))
	att1.Axis = Vector3.new(0, 0, 1)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = 3
	hinge.MotorMaxTorque = 10000
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -5
	hinge.UpperAngle = 70
	hinge.Parent = base
	task.spawn(function()
		while hinge.Parent do
			task.wait(3)
			hinge.AngularVelocity = -hinge.AngularVelocity
		end
	end)
end)

spawnTest(4, 1, "Motor Flipper fast", function(pos)
	local base = makePart({
		position = pos - Vector3.new(0, 2.5, 0),
		size = Vector3.new(10, 1, 3),
		color = Color3.fromRGB(60, 60, 60),
		anchored = true,
	})
	local flipper = makePart({
		position = pos + Vector3.new(5, -1.5, 0),
		size = Vector3.new(10, 0.5, 8),
		color = Color3.fromRGB(255, 200, 50),
		anchored = false,
		density = 0.1,
	})
	local att0 = makeAtt(base, Vector3.new(0, 0.5, 0))
	att0.Axis = Vector3.new(0, 0, 1)
	local att1 = makeAtt(flipper, Vector3.new(-5, 0, 0))
	att1.Axis = Vector3.new(0, 0, 1)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = 8
	hinge.MotorMaxTorque = 50000
	hinge.LimitsEnabled = true
	hinge.LowerAngle = -5
	hinge.UpperAngle = 80
	hinge.Parent = base
	task.spawn(function()
		while hinge.Parent do
			task.wait(2)
			hinge.AngularVelocity = -hinge.AngularVelocity
		end
	end)
end)

----------------------------------------------------------------------
-- ROW 5: PROVEN WORKING OBJECTS
----------------------------------------------------------------------
spawnTest(5, 0, "Hinge: Seesaw", function(pos)
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
	local att0 = makeAtt(post, Vector3.new(0, 1.5, 0))
	att0.Axis = Vector3.new(0, 0, 1)
	local att1 = makeAtt(plank, Vector3.new(0, -0.25, 0))
	att1.Axis = Vector3.new(0, 0, 1)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.Parent = post
end)

spawnTest(5, 1, "Hinge: Door", function(pos)
	local frame = makePart({
		position = pos + Vector3.new(-3, 0, 0),
		size = Vector3.new(0.5, 8, 1),
		color = Color3.fromRGB(120, 80, 40),
		anchored = true,
	})
	local panel = makePart({
		position = pos,
		size = Vector3.new(5, 8, 0.5),
		color = Color3.fromRGB(160, 110, 60),
		anchored = false,
	})
	local att0 = makeAtt(frame, Vector3.new(0.25, 0, 0))
	att0.Axis = Vector3.new(0, 1, 0)
	local att1 = makeAtt(panel, Vector3.new(-2.5, 0, 0))
	att1.Axis = Vector3.new(0, 1, 0)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att0
	hinge.Attachment1 = att1
	hinge.LimitsEnabled = true
	hinge.LowerAngle = 0
	hinge.UpperAngle = 100
	hinge.Parent = frame
end)

spawnTest(5, 2, "Rod: Hanging Sign", function(pos)
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
	for _, xOff in { -2, 2 } do
		local a0 = makeAtt(bar, Vector3.new(xOff, 0, 0))
		local a1 = makeAtt(sign, Vector3.new(xOff, 1.5, 0))
		local rod = Instance.new("RodConstraint")
		rod.Attachment0 = a0
		rod.Attachment1 = a1
		rod.Length = 2
		rod.Visible = true
		rod.Parent = bar
	end
end)

spawnTest(5, 3, "Rope: Dangler", function(pos)
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
	local a0 = makeAtt(hook, Vector3.new(0, -0.5, 0))
	local a1 = makeAtt(weight, Vector3.new(0, 1.5, 0))
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = a0
	rope.Attachment1 = a1
	rope.Length = 5
	rope.Visible = true
	rope.Parent = hook
end)

----------------------------------------------------------------------
-- ROW 6: MORE PROVEN OBJECTS
----------------------------------------------------------------------
spawnTest(6, 0, "Prismatic: Moving Platform", function(pos)
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
	keepFlat(platform, rail)
	local att0 = makeAtt(rail, Vector3.new(0, 0.25, 0))
	att0.Axis = Vector3.new(1, 0, 0)
	local att1 = makeAtt(platform, Vector3.new(0, -0.5, 0))
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -6
	prism.UpperLimit = 6
	prism.Parent = rail
	local att_lv = makeAtt(platform)
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
	local att_h0 = makeAtt(base, Vector3.new(0, 0.5, 0))
	att_h0.Axis = Vector3.new(0, 1, 0)
	local att_h1 = makeAtt(disc, Vector3.new(0, -0.5, 0))
	att_h1.Axis = Vector3.new(0, 1, 0)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att_h0
	hinge.Attachment1 = att_h1
	hinge.Parent = base
	local att_av = makeAtt(disc)
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att_av
	av.AngularVelocity = Vector3.new(0, 1.5, 0)
	av.MaxTorque = 10000
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = disc
end)

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
	local att_h0 = makeAtt(tower, Vector3.new(0, 4, -1))
	att_h0.Axis = Vector3.new(0, 0, 1)
	local att_h1 = makeAtt(blades)
	att_h1.Axis = Vector3.new(0, 0, 1)
	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = att_h0
	hinge.Attachment1 = att_h1
	hinge.Parent = tower
	local att_av = makeAtt(blades)
	local av = Instance.new("AngularVelocity")
	av.Attachment0 = att_av
	av.AngularVelocity = Vector3.new(0, 0, 3)
	av.MaxTorque = 5000
	av.RelativeTo = Enum.ActuatorRelativeTo.World
	av.Parent = blades
end)

spawnTest(6, 3, "Prismatic: Elevator", function(pos)
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
	keepFlat(platform, shaft)
	local att0 = makeAtt(shaft)
	att0.Axis = Vector3.new(0, 1, 0)
	local att1 = makeAtt(platform)
	local prism = Instance.new("PrismaticConstraint")
	prism.Attachment0 = att0
	prism.Attachment1 = att1
	prism.LimitsEnabled = true
	prism.LowerLimit = -5
	prism.UpperLimit = 5
	prism.Parent = shaft
	local att_lv = makeAtt(platform)
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

print("[PhysicsTestGrid v5] Spawned", testNum, "test objects at", tostring(GRID_ORIGIN))
