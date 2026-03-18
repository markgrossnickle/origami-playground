--[[
	VehicleAnalyzer — derives vehicle physics from model geometry.
	Big heavy trucks are slow and stable; small cars are nimble; tall narrow vehicles tip easily.
]]

local VehicleAnalyzer = {}

local function clamp(value: number, min: number, max: number): number
	return math.clamp(value, min, max)
end

local function getPartVolume(part: BasePart): number
	local size = part.Size
	if part.Shape == Enum.PartType.Ball then
		local radius = math.min(size.X, size.Y, size.Z) / 2
		return (4 / 3) * math.pi * radius ^ 3
	elseif part.Shape == Enum.PartType.Cylinder then
		local radius = math.min(size.Y, size.Z) / 2
		local height = size.X
		return math.pi * radius ^ 2 * height
	else
		-- Block (default)
		return size.X * size.Y * size.Z
	end
end

function VehicleAnalyzer.analyzeModel(model: Model): { [string]: any }
	local totalVolume = 0
	local weightedPos = Vector3.zero
	local wheelCount = 0
	local wheelRadiusSum = 0
	local parts: { { part: BasePart, volume: number } } = {}

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local vol = getPartVolume(part)
			totalVolume += vol
			weightedPos += part.Position * vol
			table.insert(parts, { part = part, volume = vol })

			local lowerName = string.lower(part.Name)
			if string.find(lowerName, "wheel") or string.find(lowerName, "tire") then
				wheelCount += 1
				wheelRadiusSum += part.Size.Y
			end
		end
	end

	local centerOfMass = if totalVolume > 0 then weightedPos / totalVolume else Vector3.zero
	local _, boundingBox = model:GetBoundingBox()

	return {
		volume = totalVolume,
		boundingBox = boundingBox,
		centerOfMass = centerOfMass,
		wheelCount = wheelCount,
		wheelRadius = if wheelCount > 0 then wheelRadiusSum / wheelCount else 0,
		heightToWidthRatio = if boundingBox.X > 0 then boundingBox.Y / boundingBox.X else 1,
		parts = parts,
	}
end

function VehicleAnalyzer.derivePhysics(analysis: { [string]: any }, llmAttrs: { [string]: any }?): { [string]: any }
	local attrs = llmAttrs or {}
	local baseSpeed = attrs.Speed or 50
	local baseTorque = attrs.Torque or 40
	local baseTurnSpeed = attrs.TurnSpeed or 8

	-- Scale factors from geometry (80 studs³ = reference mid-size car)
	local massRatio = clamp(analysis.volume / 80, 0.3, 3.0)
	local speedMod = 1 / (massRatio ^ 0.3)
	local torqueMod = massRatio ^ 0.5
	local turnMod = 1 / (massRatio ^ 0.4)

	-- Wheel bonus
	local grip = 0.5
	if analysis.wheelCount >= 4 then
		speedMod *= 1.1
		grip = 1.0
	elseif analysis.wheelCount == 3 then
		grip = 0.85
	elseif analysis.wheelCount == 2 then
		grip = 0.7
		turnMod *= 1.3
	end

	-- Tip resistance: wide & low = stable, tall & narrow = tippy
	local tipResistance = clamp(1 - analysis.heightToWidthRatio + 0.5, 0.1, 1.0)

	return {
		speed = clamp(baseSpeed * speedMod, 10, 150),
		torque = clamp(baseTorque * torqueMod, 10, 200),
		turnSpeed = clamp(baseTurnSpeed * turnMod, 2, 20),
		grip = grip,
		tipResistance = tipResistance,
		massRatio = massRatio,
	}
end

return VehicleAnalyzer
