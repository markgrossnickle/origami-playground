--[[
	DemoShowcaseSpawner — spawns demo models in a semicircle for showcase.
	- Creatures/props: built, anchored, animated, and labeled with a billboard.
	- Vehicles: built with VehicleSeat, ProximityPrompt, collision plate — fully driveable.
	Called from Server init after Knit starts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)

local DemoShowcaseSpawner = {}

local FOLDER_NAME = "DemoShowcase"

local function makeBillboard(parent: Instance, text: string, offset: Vector3)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.StudsOffset = offset
	bb.Size = UDim2.new(0, 180, 0, 50)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 120

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = false
	label.TextSize = 14
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextWrapped = true
	label.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	bb.Adornee = parent
	bb.Parent = parent
	return bb
end

----------------------------------------------------------------------
-- Vehicle setup: creates VehicleSeat + collision plate + ProximityPrompt
-- Mirrors OrigamiService:CreateVehicleSeat logic for demo vehicles
----------------------------------------------------------------------
local function setupVehicle(builtModel: Model, position: Vector3, modelData: { [string]: any }, folder: Folder)
	local _, modelSize = builtModel:GetBoundingBox()
	local modelName = modelData.name or "Vehicle"

	-- Detect flight from name
	local nameLower = string.lower(modelName)
	local canFly = string.find(nameLower, "airship")
		or string.find(nameLower, "carpet")
		or string.find(nameLower, "plane")
		or string.find(nameLower, "helicopter")
		or string.find(nameLower, "jet")
		or string.find(nameLower, "blimp")
		or string.find(nameLower, "drone")
	canFly = canFly and true or false

	-- Create VehicleSeat at ground level + 1 stud
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.CFrame = CFrame.new(position.X, position.Y + 1, position.Z)
	seat.Anchored = true
	seat.CanCollide = true
	seat.Transparency = 1
	seat.MaxSpeed = 50
	seat.Torque = 0
	seat.TurnSpeed = 8
	seat:SetAttribute("DriveSpeed", 50)
	seat:SetAttribute("DriveTorque", 40)
	seat:SetAttribute("DriveTurnSpeed", 8)
	seat:SetAttribute("OrigamiVehicle", true)
	seat:SetAttribute("OwnerUserId", 0) -- demo vehicle, anyone can drive
	if canFly then
		seat:SetAttribute("CanFly", true)
		seat:SetAttribute("FlySpeed", 30)
	end
	seat.Material = Enum.Material.SmoothPlastic
	seat.Parent = folder

	-- Collision plate for traction
	local collisionPlate = Instance.new("Part")
	collisionPlate.Name = "CollisionPlate"
	collisionPlate.Size = Vector3.new(math.min(modelSize.X * 0.8, 14), 0.5, math.min(modelSize.Z * 0.8, 16))
	collisionPlate.Transparency = 1
	collisionPlate.CanCollide = true
	collisionPlate.Massless = false
	collisionPlate.Anchored = false
	collisionPlate.Material = Enum.Material.SmoothPlastic
	collisionPlate.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.8, 0.0, 0.8, 0.0)
	collisionPlate.CFrame = seat.CFrame * CFrame.new(0, -1, 0)
	collisionPlate.Parent = folder

	local plateWeld = Instance.new("WeldConstraint")
	plateWeld.Part0 = seat
	plateWeld.Part1 = collisionPlate
	plateWeld.Parent = collisionPlate

	-- Position visual model: seat is 1 stud above ground, model centered on seat
	local modelRise = modelSize.Y / 2 - 1
	builtModel:PivotTo(seat.CFrame * CFrame.new(0, modelRise, 0))
	builtModel.Parent = folder

	-- Weld all visual parts to the seat (massless to prevent tipping)
	for _, part in builtModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = seat
			weld.Part1 = part
			weld.Parent = part
		end
	end

	-- ProximityPrompt to enter
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = modelName
	prompt.ActionText = "Drive"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat

	prompt.Triggered:Connect(function(player: Player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			seat.Anchored = false
			seat:SetNetworkOwner(player)
			prompt.Enabled = false
			seat:Sit(humanoid)
		end
	end)

	-- Re-show prompt on exit
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if not seat.Occupant then
			prompt.Enabled = true
		end
	end)

	-- Name label on the seat
	makeBillboard(seat, modelName, Vector3.new(0, modelSize.Y / 2 + 3, 0))
end

----------------------------------------------------------------------
-- Main build function
----------------------------------------------------------------------
function DemoShowcaseSpawner.Build()
	-- Clean up previous
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end

	local DemoShowcase = require(ReplicatedStorage.Shared.DemoShowcase)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local count = 0
	for _, entry in ipairs(DemoShowcase.MODELS) do
		local modelData = entry.modelData
		local position = Vector3.new(entry.position[1], entry.position[2], entry.position[3])

		local buildOk, builtModel = pcall(function()
			return OrigamiBuilder.BuildModel(modelData)
		end)

		if buildOk and builtModel then
			if entry.category == "vehicle" then
				-- Driveable vehicle with VehicleSeat + ProximityPrompt
				setupVehicle(builtModel, position, modelData, folder)
			else
				-- Static prop/creature: anchor, animate, label
				builtModel.Parent = folder

				for _, part in builtModel:GetDescendants() do
					if part:IsA("BasePart") then
						part.Anchored = true
					end
				end

				-- Position: sit model on ground at target position
				local cf, size = builtModel:GetBoundingBox()
				local pivot = builtModel:GetPivot()
				local pivotAboveBottom = pivot.Position.Y - (cf.Position.Y - size.Y / 2)
				builtModel:PivotTo(CFrame.new(position.X, position.Y + pivotAboveBottom, position.Z))

				-- Apply animation
				local animType = modelData.animation
				if animType and animType ~= "none" then
					pcall(function()
						OrigamiBuilder.ApplyAnimation(builtModel, animType)
					end)
				end

				-- Name label
				local name = modelData.name or "Creation"
				local primary = builtModel.PrimaryPart or builtModel:FindFirstChildWhichIsA("BasePart")
				if primary then
					makeBillboard(primary, name, Vector3.new(0, size.Y / 2 + 3, 0))
				end
			end

			count += 1
		else
			warn("[DemoShowcase] Failed to build:", modelData.name, builtModel)
		end
	end

	folder.Parent = workspace
	print("[DemoShowcase] Spawned", count, "models")
end

function DemoShowcaseSpawner.Clear()
	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
	end
end

return DemoShowcaseSpawner
