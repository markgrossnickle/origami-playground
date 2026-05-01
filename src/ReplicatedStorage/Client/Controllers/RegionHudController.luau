--!strict
--[[
	RegionHudController — top-of-screen HUD showing the local player's
	current Region info, plus per-viewer tinting of the LandmarkService's
	slot pillars (green = yours, yellow = unclaimed, grey = someone else's).

	Listens to:
		* SpawnService.Client.RegionAssigned (fired once on first claim)
		* PlayerDataService:GetData (initial profile load)

	The HUD is intentionally minimal. Phase 6 will replace this with a real
	world map + Return-to-Base button.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RegionConfig = require(ReplicatedStorage.Shared.RegionConfig)

local LocalPlayer = Players.LocalPlayer

local RegionHudController = Knit.CreateController({
	Name = "RegionHudController",
})

local COLOR_OWNED = Color3.fromRGB(120, 230, 130) -- green: your region
local COLOR_UNCLAIMED = Color3.fromRGB(240, 200, 80) -- yellow: free
local COLOR_OTHER = Color3.fromRGB(180, 180, 180) -- grey: someone else's

local _ownedSlotId: string = ""
local _hudLabel: TextLabel? = nil

local function _setLabelText(text: string)
	if _hudLabel then
		_hudLabel.Text = text
	end
end

local function _retintLandmarks()
	local folder = Workspace:FindFirstChild("Landmarks")
	if not folder then
		return
	end
	for _, inst in folder:GetChildren() do
		if not inst:IsA("BasePart") then
			continue
		end
		local kind = inst:GetAttribute("LandmarkKind")
		if kind ~= "slot" then
			continue
		end
		local slotId = inst:GetAttribute("SlotId")
		if type(slotId) ~= "string" then
			continue
		end
		if slotId == _ownedSlotId then
			inst.Color = COLOR_OWNED
		else
			-- Without a remote query we can't know "claimed by another" vs
			-- "unclaimed" client-side. Default unowned slots to yellow
			-- (looks inviting); the server doesn't broadcast ownership map
			-- yet — Phase 6 will add a RegionService:GetClaimedSlots RPC
			-- and we'll switch the non-owner color to grey.
			inst.Color = COLOR_UNCLAIMED
		end
	end
end

local function _createHud()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RegionHud"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.Size = UDim2.new(0, 240, 0, 36)
	frame.Position = UDim2.new(0.5, -120, 0, 8)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = "Loading region info..."
	label.Parent = frame

	_hudLabel = label
end

local function _updateHud()
	if _ownedSlotId == "" then
		_setLabelText("Region: unclaimed (in The Wilds)")
		return
	end
	local center = RegionConfig.getSlotCenter(_ownedSlotId)
	if center then
		_setLabelText(string.format("Region: %s   |   Hearth: 0, 0", _ownedSlotId))
	else
		_setLabelText(string.format("Region: %s", _ownedSlotId))
	end
end

local function _handleAssigned(slotId: string)
	if type(slotId) ~= "string" then
		return
	end
	_ownedSlotId = slotId
	_updateHud()
	_retintLandmarks()
end

function RegionHudController:KnitInit() end

function RegionHudController:KnitStart()
	_createHud()

	-- Pull the current region from the player's profile (if already claimed).
	task.spawn(function()
		local PlayerDataService = Knit.GetService("PlayerDataService")
		local ok, data = PlayerDataService:Read():await()
		if ok and type(data) == "table" then
			local owned = data.OwnedRegionId
			if type(owned) == "string" and owned ~= "" then
				_ownedSlotId = owned
				_updateHud()
				_retintLandmarks()
				return
			end
		end
		_updateHud()
		_retintLandmarks()
	end)

	-- Listen for first-claim assignment.
	task.spawn(function()
		local SpawnService = Knit.GetService("SpawnService")
		if SpawnService and SpawnService.RegionAssigned then
			SpawnService.RegionAssigned:Connect(_handleAssigned)
		end
	end)

	-- Re-tint when Landmarks folder appears (server may finish placing them
	-- after the controller starts).
	task.spawn(function()
		local folder = Workspace:WaitForChild("Landmarks", 30)
		if folder then
			_retintLandmarks()
			folder.ChildAdded:Connect(function()
				_retintLandmarks()
			end)
		end
	end)
end

return RegionHudController
