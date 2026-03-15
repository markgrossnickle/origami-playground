local RunService = game:GetService("RunService")

local OrigamiBuilder = {}

-- Map shape names to Roblox part types (case-insensitive, with aliases)
local SHAPE_MAP = {
	block = Enum.PartType.Block,
	cube = Enum.PartType.Block,
	box = Enum.PartType.Block,
	ball = Enum.PartType.Ball,
	sphere = Enum.PartType.Ball,
	cylinder = Enum.PartType.Cylinder,
	tube = Enum.PartType.Cylinder,
	wedge = Enum.PartType.Wedge,
}

local MATERIAL_MAP = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Neon = Enum.Material.Neon,
	Glass = Enum.Material.Glass,
	Metal = Enum.Material.Metal,
	Wood = Enum.Material.Wood,
	Concrete = Enum.Material.Concrete,
	Brick = Enum.Material.Brick,
	Marble = Enum.Material.Marble,
	Granite = Enum.Material.Granite,
	Fabric = Enum.Material.Fabric,
	Ice = Enum.Material.Ice,
	Foil = Enum.Material.Foil,
	Sand = Enum.Material.Sand,
	Grass = Enum.Material.Grass,
}

function OrigamiBuilder.BuildModel(modelData: { [string]: any }): Model
	local model = Instance.new("Model")
	model.Name = modelData.name or "Creation"

	local parts = modelData.parts or {}
	for i, partData in ipairs(parts) do
		local shape = string.lower(partData.shape or "block")
		local part: Part

		if shape == "wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			part.Shape = SHAPE_MAP[shape] or Enum.PartType.Block
		end

		part.Name = partData.name or ("Part" .. i)
		part.Anchored = if partData.anchored ~= nil then partData.anchored else true
		part.CanCollide = if partData.canCollide ~= nil then partData.canCollide else true

		-- Position
		if partData.position then
			part.Position = Vector3.new(
				partData.position[1] or partData.position.x or 0,
				partData.position[2] or partData.position.y or 0,
				partData.position[3] or partData.position.z or 0
			)
		end

		-- Size
		if partData.size then
			part.Size = Vector3.new(
				partData.size[1] or partData.size.x or 1,
				partData.size[2] or partData.size.y or 1,
				partData.size[3] or partData.size.z or 1
			)
		end

		-- Orientation (accept both "orientation" and "rotation" from LLM)
		local orient = partData.orientation or partData.rotation
		if orient then
			part.Orientation = Vector3.new(
				orient[1] or orient.x or 0,
				orient[2] or orient.y or 0,
				orient[3] or orient.z or 0
			)
		end

		-- Color
		if partData.color then
			local r = partData.color[1] or partData.color.r or 255
			local g = partData.color[2] or partData.color.g or 255
			local b = partData.color[3] or partData.color.b or 255
			part.Color = Color3.fromRGB(r, g, b)
		end

		-- Material
		if partData.material then
			part.Material = MATERIAL_MAP[partData.material] or Enum.Material.SmoothPlastic
		end

		-- Transparency
		if partData.transparency then
			part.Transparency = partData.transparency
		end

		-- Custom physical properties from LLM
		if partData.density or partData.friction or partData.elasticity then
			local density = partData.density or 0.7
			local friction = partData.friction or 0.3
			local elasticity = partData.elasticity or 0.5
			local frictionWeight = partData.frictionWeight or 1
			local elasticityWeight = partData.elasticityWeight or 1
			part.CustomPhysicalProperties =
				PhysicalProperties.new(density, friction, elasticity, frictionWeight, elasticityWeight)
		end

		-- Body part mapping (for avatar rigging)
		if partData.body_part then
			part:SetAttribute("BodyPart", partData.body_part)
		end

		-- Arbitrary attributes from LLM (store any extra fields as Roblox attributes)
		if partData.attributes then
			for attrName, attrValue in pairs(partData.attributes) do
				pcall(function()
					part:SetAttribute(attrName, attrValue)
				end)
			end
		end

		part.Parent = model
	end

	-- Flip model 180° on Y so LLM's +Z forward becomes Roblox's -Z forward
	-- LLM models face +Z but Roblox convention is -Z (CFrame.LookVector)
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then
			child.CFrame = CFrame.Angles(0, math.pi, 0) * child.CFrame
		end
	end

	-- Set primary part to first part
	if #model:GetChildren() > 0 then
		model.PrimaryPart = model:GetChildren()[1]
	end

	-- Model-level attributes from LLM (interaction hints, behaviors, etc.)
	if modelData.attributes then
		for attrName, attrValue in pairs(modelData.attributes) do
			pcall(function()
				model:SetAttribute(attrName, attrValue)
			end)
		end
	end

	-- Physics constraints from LLM (springs, hinges, etc.)
	local constraints = modelData.constraints
	if constraints and #constraints > 0 then
		-- Build name→part lookup
		local partsByName = {}
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") then
				partsByName[child.Name] = child
			end
		end

		local CONSTRAINT_CLASS = {
			Spring = "SpringConstraint",
			Hinge = "HingeConstraint",
			BallSocket = "BallSocketConstraint",
			Weld = "WeldConstraint",
			Rod = "RodConstraint",
			Rope = "RopeConstraint",
			Prismatic = "PrismaticConstraint",
			TorsionSpring = "TorsionSpringConstraint",
			AngularVelocity = "AngularVelocity",
			LinearVelocity = "LinearVelocity",
			VectorForce = "VectorForce",
		}

		-- These only act on one part (no part1 needed)
		local SINGLE_ATTACHMENT = {
			AngularVelocity = true,
			LinearVelocity = true,
			VectorForce = true,
		}

		local function readVector3(t)
			return Vector3.new(t[1] or 0, t[2] or 0, t[3] or 0)
		end

		local maxConstraints = math.min(#constraints, 20)
		for i = 1, maxConstraints do
			local cData = constraints[i]
			local className = CONSTRAINT_CLASS[cData.type]
			if not className then
				continue
			end

			local p0 = partsByName[cData.part0]
			if not p0 then
				continue
			end

			if SINGLE_ATTACHMENT[cData.type] then
				-- Single-attachment constraints (AngularVelocity, LinearVelocity, VectorForce)
				local att0 = Instance.new("Attachment")
				if cData.offset0 then
					att0.Position = readVector3(cData.offset0)
				end
				if cData.axis then
					att0.Axis = readVector3(cData.axis)
				end
				att0.Parent = p0

				local constraint = Instance.new(className)
				constraint.Attachment0 = att0

				if cData.type == "AngularVelocity" then
					if cData.angularVelocity then
						constraint.AngularVelocity = readVector3(cData.angularVelocity)
					end
					if cData.maxTorque then constraint.MaxTorque = cData.maxTorque end
					constraint.RelativeTo = Enum.ActuatorRelativeTo.World
				elseif cData.type == "LinearVelocity" then
					if cData.vectorVelocity then
						constraint.VectorVelocity = readVector3(cData.vectorVelocity)
					end
					if cData.maxForce then constraint.MaxForce = cData.maxForce end
					constraint.RelativeTo = Enum.ActuatorRelativeTo.World
				elseif cData.type == "VectorForce" then
					if cData.force then
						constraint.Force = readVector3(cData.force)
					end
					constraint.RelativeTo = Enum.ActuatorRelativeTo.World
				end

				constraint.Parent = p0

			elseif className == "WeldConstraint" then
				local p1 = partsByName[cData.part1]
				if not p1 then continue end
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = p0
				weld.Part1 = p1
				weld.Parent = p0

			else
				local p1 = partsByName[cData.part1]
				if not p1 then continue end

				local att0 = Instance.new("Attachment")
				if cData.offset0 then
					att0.Position = readVector3(cData.offset0)
				end
				if cData.axis then
					att0.Axis = readVector3(cData.axis)
				end
				att0.Parent = p0

				local att1 = Instance.new("Attachment")
				if cData.offset1 then
					att1.Position = readVector3(cData.offset1)
				end
				if cData.axis then
					att1.Axis = readVector3(cData.axis)
				end
				att1.Parent = p1

				local constraint = Instance.new(className)
				constraint.Attachment0 = att0
				constraint.Attachment1 = att1

				-- Type-specific properties
				if cData.type == "Spring" then
					if cData.stiffness then constraint.Stiffness = cData.stiffness end
					if cData.damping then constraint.Damping = cData.damping end
					if cData.freeLength then constraint.FreeLength = cData.freeLength end
				elseif cData.type == "Hinge" then
					if cData.limitsEnabled then constraint.LimitsEnabled = true end
					if cData.lowerAngle then constraint.LowerAngle = cData.lowerAngle end
					if cData.upperAngle then constraint.UpperAngle = cData.upperAngle end
					if cData.actuatorType == "Motor" then
						constraint.ActuatorType = Enum.ActuatorType.Motor
						if cData.motorSpeed then constraint.AngularVelocity = cData.motorSpeed end
						if cData.motorMaxTorque then constraint.MotorMaxTorque = cData.motorMaxTorque end
					end
				elseif cData.type == "BallSocket" then
					if cData.limitsEnabled then constraint.LimitsEnabled = true end
					if cData.upperAngle then constraint.UpperAngle = cData.upperAngle end
				elseif cData.type == "Rod" then
					if cData.length then constraint.Length = cData.length end
				elseif cData.type == "Rope" then
					if cData.length then constraint.Length = cData.length end
					if cData.restitution then constraint.Restitution = cData.restitution end
				elseif cData.type == "Prismatic" then
					if cData.limitsEnabled then constraint.LimitsEnabled = true end
					if cData.lowerLimit then constraint.LowerLimit = cData.lowerLimit end
					if cData.upperLimit then constraint.UpperLimit = cData.upperLimit end
				elseif cData.type == "TorsionSpring" then
					if cData.stiffness then constraint.Stiffness = cData.stiffness end
					if cData.damping then constraint.Damping = cData.damping end
					if cData.maxAngle then constraint.MaxAngle = cData.maxAngle end
				end

				constraint.Parent = p0
			end
		end
	end

	return model
end

function OrigamiBuilder.ApplyAnimation(model: Model, animationType: string)
	if not animationType or animationType == "none" then
		return
	end

	local parts = model:GetDescendants()
	local startTime = tick()
	local connection: RBXScriptConnection

	if animationType == "idle_bob" then
		local origins = {}
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") and part.Anchored then
				origins[part] = part.Position
			end
		end
		connection = RunService.Heartbeat:Connect(function()
			local t = tick() - startTime
			local offset = math.sin(t * 2) * 0.5
			for part, origin in pairs(origins) do
				if part.Parent then
					part.Position = origin + Vector3.new(0, offset, 0)
				end
			end
		end)

	elseif animationType == "spin_slow" then
		connection = RunService.Heartbeat:Connect(function(dt)
			if model.PrimaryPart and model.PrimaryPart.Parent then
				local pivot = model:GetPivot()
				model:PivotTo(pivot * CFrame.Angles(0, math.rad(30) * dt, 0))
			end
		end)

	elseif animationType == "bounce" then
		local origins = {}
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") and part.Anchored then
				origins[part] = part.Position
			end
		end
		connection = RunService.Heartbeat:Connect(function()
			local t = tick() - startTime
			local offset = math.abs(math.sin(t * 3)) * 2
			for part, origin in pairs(origins) do
				if part.Parent then
					part.Position = origin + Vector3.new(0, offset, 0)
				end
			end
		end)

	elseif animationType == "wobble" then
		connection = RunService.Heartbeat:Connect(function()
			local t = tick() - startTime
			if model.PrimaryPart and model.PrimaryPart.Parent then
				local pivot = model:GetPivot()
				local wobbleX = math.sin(t * 2.5) * math.rad(3)
				local wobbleZ = math.cos(t * 3.1) * math.rad(3)
				model:PivotTo(CFrame.new(pivot.Position) * CFrame.Angles(wobbleX, 0, wobbleZ))
			end
		end)

	elseif animationType == "flutter" then
		-- Wing-like movement on parts named with "wing" or outer parts
		local wingParts = {}
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") and part.Anchored then
				local name = part.Name:lower()
				if name:find("wing") or name:find("fin") or name:find("arm") then
					table.insert(wingParts, { part = part, origin = part.CFrame })
				end
			end
		end
		connection = RunService.Heartbeat:Connect(function()
			local t = tick() - startTime
			for _, data in ipairs(wingParts) do
				if data.part.Parent then
					local angle = math.sin(t * 4) * math.rad(20)
					data.part.CFrame = data.origin * CFrame.Angles(0, 0, angle)
				end
			end
		end)

	elseif animationType == "breathe" then
		local origins = {}
		for _, part in ipairs(parts) do
			if part:IsA("BasePart") and part.Anchored then
				origins[part] = part.Size
			end
		end
		connection = RunService.Heartbeat:Connect(function()
			local t = tick() - startTime
			local scale = 1 + math.sin(t * 1.5) * 0.05
			for part, origSize in pairs(origins) do
				if part.Parent then
					part.Size = origSize * scale
				end
			end
		end)
	end

	-- Store connection on model for cleanup
	if connection then
		local tag = Instance.new("ObjectValue")
		tag.Name = "_AnimConnection"
		tag.Parent = model

		model.Destroying:Connect(function()
			connection:Disconnect()
		end)
	end
end

return OrigamiBuilder
