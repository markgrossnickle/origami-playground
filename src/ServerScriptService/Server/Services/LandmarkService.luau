--!strict
--[[
	LandmarkService — places world-visible markers for the Hearth and the 12
	Region slots so players can navigate. A tall central pillar marks the
	Hearth at world origin; each Region slot center gets a smaller pillar.

	Slot pillars are color-coded based on ownership:
		owner == nil           → yellow  (unclaimed)
		owner == localPlayer   → green   (yours)  -- handled client-side via attribute
		owner ~= localPlayer   → grey    (someone else's)

	Server places parts with attributes; client (BeaconColorController) tints
	them per-viewer based on the local player's OwnedRegionId. The server keeps
	parts neutral grey by default; the client overrides for ownership feedback.

	Beacons are pure decor — anchored, non-collidable, on a streaming-friendly
	folder. They DO NOT live in the voxel world (zone permissions skip them).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)
local WorldGenModule = require(ReplicatedStorage.Shared.WorldGenModule)

local LandmarkService = Knit.CreateService({
	Name = "LandmarkService",
	Client = {},
})

local WorldService

local LANDMARK_FOLDER_NAME = "Landmarks"

-- Hearth pillar geometry — tall, bright, distinctive.
local HEARTH_PILLAR_HEIGHT = 80
local HEARTH_PILLAR_RADIUS = 4
local HEARTH_PILLAR_COLOR = Color3.fromRGB(255, 220, 130) -- warm gold

-- Slot pillar geometry — moderate, visible from afar.
local SLOT_PILLAR_HEIGHT = 40
local SLOT_PILLAR_RADIUS = 2
local SLOT_PILLAR_COLOR_DEFAULT = Color3.fromRGB(180, 180, 180) -- neutral grey

local function _placePillar(opts: {
	name: string,
	x: number,
	z: number,
	groundY: number,
	height: number,
	radius: number,
	color: Color3,
	parent: Instance,
	attributes: { [string]: any }?,
}): Part
	local pillar = Instance.new("Part")
	pillar.Name = opts.name
	pillar.Shape = Enum.PartType.Cylinder
	-- Cylinder is x-axis aligned by default, so size order is { length, diameter, diameter }.
	-- Rotate 90 deg around Z to stand it up vertically.
	pillar.Size = Vector3.new(opts.height, opts.radius * 2, opts.radius * 2)
	pillar.CFrame = CFrame.new(opts.x, opts.groundY + opts.height / 2, opts.z) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanTouch = false
	pillar.CanQuery = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = opts.color
	pillar.TopSurface = Enum.SurfaceType.Smooth
	pillar.BottomSurface = Enum.SurfaceType.Smooth

	if opts.attributes then
		for k, v in opts.attributes do
			pillar:SetAttribute(k, v)
		end
	end

	pillar.Parent = opts.parent
	return pillar
end

local function _addBillboard(pillar: BasePart, text: string, color: Color3, studsOffset: number)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Adornee = pillar
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 220, 0, 50)
	bb.StudsOffset = Vector3.new(0, studsOffset, 0)
	bb.MaxDistance = 600
	bb.Parent = pillar

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.TextColor3 = color
	label.TextScaled = false
	label.TextSize = 18
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
end

function LandmarkService:KnitInit() end

function LandmarkService:KnitStart()
	WorldService = Knit.GetService("WorldService")
	local seed = WorldService:GetSeed()

	local folder = Instance.new("Folder")
	folder.Name = LANDMARK_FOLDER_NAME
	folder.Parent = workspace

	-- Hearth pillar at world origin.
	local hearthGroundY = WorldGenModule.getSurfaceWorldY(seed, RegionConfig.HEARTH_CX, RegionConfig.HEARTH_CZ)
	local hearthPillar = _placePillar({
		name = "HearthPillar",
		x = RegionConfig.HEARTH_CX,
		z = RegionConfig.HEARTH_CZ,
		groundY = hearthGroundY,
		height = HEARTH_PILLAR_HEIGHT,
		radius = HEARTH_PILLAR_RADIUS,
		color = HEARTH_PILLAR_COLOR,
		parent = folder,
		attributes = { LandmarkKind = "hearth" },
	})
	_addBillboard(hearthPillar, "The Hearth", HEARTH_PILLAR_COLOR, HEARTH_PILLAR_HEIGHT / 2 + 4)

	-- Slot pillars at each of the 12 Region centers.
	for i = 0, RegionConfig.SLOT_COUNT - 1 do
		local center = RegionConfig.SLOT_CENTERS[i + 1]
		local slotId = RegionConfig.formatSlotId(i)
		local groundY = WorldGenModule.getSurfaceWorldY(seed, center.x, center.z)
		local pillar = _placePillar({
			name = "SlotPillar_" .. slotId,
			x = center.x,
			z = center.z,
			groundY = groundY,
			height = SLOT_PILLAR_HEIGHT,
			radius = SLOT_PILLAR_RADIUS,
			color = SLOT_PILLAR_COLOR_DEFAULT,
			parent = folder,
			attributes = {
				LandmarkKind = "slot",
				SlotId = slotId,
			},
		})
		_addBillboard(pillar, "Region " .. slotId, Color3.fromRGB(230, 230, 230), SLOT_PILLAR_HEIGHT / 2 + 4)
	end
end

return LandmarkService
