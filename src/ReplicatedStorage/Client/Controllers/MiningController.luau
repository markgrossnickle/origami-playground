--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local BlockRegistry = require(ReplicatedStorage.Shared.BlockRegistry)
local ToolRegistry = require(ReplicatedStorage.Shared.ToolRegistry)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

local BLOCK_SIZE = ChunkUtil.BLOCK_SIZE
local MAX_RAYCAST_DISTANCE = 60

--[=[
	@class MiningController
	Handles mining input, raycasting, client-side prediction, and visual feedback.
]=]
local MiningController = Knit.CreateController({
	Name = "MiningController",
})

local WorldService
local MiningService
local ChunkRenderController

local LocalPlayer = Players.LocalPlayer
local camera: Camera

-- Mining state
local isMining = false
local targetChunkKey: string? = nil
local targetFlatIndex: number? = nil
local miningProgress = 0
local lastSendTime = 0

-- Equipped tool
local equippedToolId = "paper_hands"

-- Tier blocked feedback
local tierBlockedGui: ScreenGui? = nil
local tierBlockedLabel: TextLabel? = nil
local tierBlockedHideTime = 0

-- Visual feedback
local highlightInstance: Highlight? = nil
local highlightPart: Part? = nil
local blockNameGui: BillboardGui? = nil
local blockNameLabel: TextLabel? = nil
local crackBillboard: BillboardGui? = nil
local crackLabel: TextLabel? = nil

-- Mining progress bar
local miningProgressGui: BillboardGui? = nil
local miningProgressNameLabel: TextLabel? = nil
local miningProgressBarBg: Frame? = nil
local miningProgressFill: Frame? = nil

-------------------------------------------------
-- Raycast helpers
-------------------------------------------------

local _cachedRaycastParams: RaycastParams = RaycastParams.new()
_cachedRaycastParams.FilterType = Enum.RaycastFilterType.Include
local _cachedChunkFolder: Instance? = nil

local function _getMouseRay(): Ray?
	local mouse = LocalPlayer:GetMouse()
	if not mouse then
		return nil
	end

	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	return Ray.new(unitRay.Origin, unitRay.Direction * MAX_RAYCAST_DISTANCE)
end

local function _raycastToBlock(): (string?, number?, Vector3?, Vector3?)
	local ray = _getMouseRay()
	if not ray then
		return nil, nil, nil, nil
	end

	if not _cachedChunkFolder or not _cachedChunkFolder.Parent then
		_cachedChunkFolder = workspace:FindFirstChild("ChunkRender")
	end
	if not _cachedChunkFolder then
		return nil, nil, nil, nil
	end
	_cachedRaycastParams.FilterDescendantsInstances = { _cachedChunkFolder }

	local result = workspace:Raycast(ray.Origin, ray.Direction, _cachedRaycastParams)
	if not result or not result.Instance then
		return nil, nil, nil, nil
	end

	-- Offset slightly into the block to avoid edge cases
	local hitPos = result.Position - result.Normal * (BLOCK_SIZE * 0.1)
	local cx, cy, cz = ChunkUtil.worldToChunk(hitPos.X, hitPos.Y, hitPos.Z)
	local chunkKey = ChunkUtil.chunkKey(cx, cy, cz)
	local flatIndex = ChunkUtil.worldToFlatIndex(hitPos.X, hitPos.Y, hitPos.Z)

	-- Walk towards camera to find the outermost solid block
	for _ = 1, 5 do
		local frontPos = hitPos + result.Normal * BLOCK_SIZE
		local fcx, fcy, fcz = ChunkUtil.worldToChunk(frontPos.X, frontPos.Y, frontPos.Z)
		local frontKey = ChunkUtil.chunkKey(fcx, fcy, fcz)
		local frontIndex = ChunkUtil.worldToFlatIndex(frontPos.X, frontPos.Y, frontPos.Z)
		local frontBlock = ChunkRenderController:GetBlockAt(frontKey, frontIndex)

		if frontBlock == BlockType.Air then
			break
		end

		hitPos = frontPos
		cx, cy, cz = fcx, fcy, fcz
		chunkKey = frontKey
		flatIndex = frontIndex
	end

	return chunkKey, flatIndex, hitPos, result.Normal
end

-------------------------------------------------
-- Visual feedback
-------------------------------------------------

local function _createHighlight()
	highlightPart = Instance.new("Part")
	highlightPart.Anchored = true
	highlightPart.CanCollide = false
	highlightPart.Transparency = 1
	highlightPart.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	highlightPart.Name = "MiningHighlight"
	highlightPart.Parent = workspace

	highlightInstance = Instance.new("Highlight")
	highlightInstance.DepthMode = Enum.HighlightDepthMode.Occluded
	highlightInstance.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlightInstance.FillTransparency = 1
	highlightInstance.OutlineTransparency = 0.1
	highlightInstance.Adornee = highlightPart
	highlightInstance.Parent = highlightPart

	-- Block name billboard
	blockNameGui = Instance.new("BillboardGui")
	blockNameGui.Size = UDim2.new(0, 120, 0, 28)
	blockNameGui.StudsOffset = Vector3.new(0, BLOCK_SIZE * 0.8, 0)
	blockNameGui.AlwaysOnTop = true
	blockNameGui.Parent = highlightPart

	blockNameLabel = Instance.new("TextLabel")
	blockNameLabel.Size = UDim2.new(1, 0, 1, 0)
	blockNameLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	blockNameLabel.BackgroundTransparency = 0.3
	blockNameLabel.TextColor3 = Color3.new(1, 1, 1)
	blockNameLabel.Font = Enum.Font.GothamBold
	blockNameLabel.TextSize = 14
	blockNameLabel.Text = ""
	blockNameLabel.Parent = blockNameGui

	local nameCorner = Instance.new("UICorner")
	nameCorner.CornerRadius = UDim.new(0, 4)
	nameCorner.Parent = blockNameLabel

	-- Crack overlay
	crackBillboard = Instance.new("BillboardGui")
	crackBillboard.Size = UDim2.new(BLOCK_SIZE, 0, BLOCK_SIZE, 0)
	crackBillboard.AlwaysOnTop = false
	crackBillboard.Parent = highlightPart

	crackLabel = Instance.new("TextLabel")
	crackLabel.Size = UDim2.new(1, 0, 1, 0)
	crackLabel.BackgroundTransparency = 1
	crackLabel.TextColor3 = Color3.new(0, 0, 0)
	crackLabel.TextScaled = true
	crackLabel.Font = Enum.Font.GothamBold
	crackLabel.Text = ""
	crackLabel.Parent = crackBillboard

	-- Mining progress billboard
	miningProgressGui = Instance.new("BillboardGui")
	miningProgressGui.Size = UDim2.new(0, 120, 0, 34)
	miningProgressGui.StudsOffset = Vector3.new(0, BLOCK_SIZE * 0.8, 0)
	miningProgressGui.AlwaysOnTop = true
	miningProgressGui.Enabled = false
	miningProgressGui.Parent = highlightPart

	miningProgressNameLabel = Instance.new("TextLabel")
	miningProgressNameLabel.Size = UDim2.new(1, 0, 0, 18)
	miningProgressNameLabel.Position = UDim2.new(0, 0, 0, 0)
	miningProgressNameLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	miningProgressNameLabel.BackgroundTransparency = 0.3
	miningProgressNameLabel.TextColor3 = Color3.new(1, 1, 1)
	miningProgressNameLabel.Font = Enum.Font.GothamBold
	miningProgressNameLabel.TextSize = 12
	miningProgressNameLabel.Text = ""
	miningProgressNameLabel.Parent = miningProgressGui

	local progressNameCorner = Instance.new("UICorner")
	progressNameCorner.CornerRadius = UDim.new(0, 4)
	progressNameCorner.Parent = miningProgressNameLabel

	miningProgressBarBg = Instance.new("Frame")
	miningProgressBarBg.Size = UDim2.new(1, -4, 0, 10)
	miningProgressBarBg.Position = UDim2.new(0, 2, 0, 22)
	miningProgressBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	miningProgressBarBg.BackgroundTransparency = 0.2
	miningProgressBarBg.BorderSizePixel = 0
	miningProgressBarBg.Parent = miningProgressGui

	local progressBarCorner = Instance.new("UICorner")
	progressBarCorner.CornerRadius = UDim.new(0, 3)
	progressBarCorner.Parent = miningProgressBarBg

	miningProgressFill = Instance.new("Frame")
	miningProgressFill.Size = UDim2.new(0, 0, 1, 0)
	miningProgressFill.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
	miningProgressFill.BorderSizePixel = 0
	miningProgressFill.Parent = miningProgressBarBg

	local progressFillCorner = Instance.new("UICorner")
	progressFillCorner.CornerRadius = UDim.new(0, 3)
	progressFillCorner.Parent = miningProgressFill
end

local function _updateHighlight(chunkKey: string, flatIndex: number, blockTypeId: number?)
	if not highlightPart then
		return
	end

	local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
	local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
	local pos = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz)

	highlightPart.Position = pos
	highlightPart.Transparency = 1

	if highlightInstance then
		highlightInstance.Enabled = true
	end
	if blockNameGui then
		blockNameGui.Enabled = true
	end

	if blockNameLabel and blockTypeId then
		local config = BlockRegistry.get(blockTypeId)
		blockNameLabel.Text = if config then config.name else ""
		if config and config.minTier >= 4 then
			blockNameLabel.TextColor3 = Color3.fromRGB(255, 150, 255)
		elseif config and config.minTier >= 3 then
			blockNameLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
		elseif config and config.minTier >= 2 then
			blockNameLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
		else
			blockNameLabel.TextColor3 = Color3.new(1, 1, 1)
		end
	end
end

local function _updateCrackOverlay(progress: number)
	if not crackLabel then
		return
	end

	if progress <= 0 then
		crackLabel.Text = ""
	elseif progress < 0.25 then
		crackLabel.Text = "."
		crackLabel.TextTransparency = 0.6
	elseif progress < 0.5 then
		crackLabel.Text = "X"
		crackLabel.TextTransparency = 0.5
	elseif progress < 0.75 then
		crackLabel.Text = "XX"
		crackLabel.TextTransparency = 0.3
	else
		crackLabel.Text = "XXX"
		crackLabel.TextTransparency = 0.1
	end
end

local function _hideHighlight()
	if highlightInstance then
		highlightInstance.Enabled = false
	end
	if crackLabel then
		crackLabel.Text = ""
	end
	if blockNameGui then
		blockNameGui.Enabled = false
	end
	if blockNameLabel then
		blockNameLabel.Text = ""
	end
	if miningProgressGui then
		miningProgressGui.Enabled = false
	end
end

local function _createTierBlockedUI()
	tierBlockedGui = Instance.new("ScreenGui")
	tierBlockedGui.Name = "TierBlockedUI"
	tierBlockedGui.ResetOnSpawn = false
	tierBlockedGui.IgnoreGuiInset = true
	tierBlockedGui.Parent = LocalPlayer.PlayerGui

	tierBlockedLabel = Instance.new("TextLabel")
	tierBlockedLabel.Size = UDim2.new(0, 300, 0, 40)
	tierBlockedLabel.Position = UDim2.new(0.5, -150, 0.7, 0)
	tierBlockedLabel.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	tierBlockedLabel.BackgroundTransparency = 0.2
	tierBlockedLabel.BorderSizePixel = 0
	tierBlockedLabel.TextColor3 = Color3.new(1, 1, 1)
	tierBlockedLabel.Font = Enum.Font.GothamBold
	tierBlockedLabel.TextSize = 16
	tierBlockedLabel.Text = ""
	tierBlockedLabel.Visible = false
	tierBlockedLabel.Parent = tierBlockedGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tierBlockedLabel
end

local function _showTierBlocked(blockName: string, requiredTier: number)
	if not tierBlockedLabel then
		return
	end
	if requiredTier >= 999 then
		tierBlockedLabel.Text = `{blockName} is unbreakable!`
	else
		tierBlockedLabel.Text = `Need better pickaxe for {blockName}!`
	end
	tierBlockedLabel.Visible = true
	tierBlockedHideTime = os.clock() + 2
end

local function _updateTierBlockedUI()
	if tierBlockedLabel and tierBlockedLabel.Visible and os.clock() >= tierBlockedHideTime then
		tierBlockedLabel.Visible = false
	end
end

-------------------------------------------------
-- Mining logic
-------------------------------------------------

local function _getCurrentToolConfig()
	return ToolRegistry.get(equippedToolId) or ToolRegistry.getDefault()
end

local function _startMining()
	isMining = true
	miningProgress = 0
end

local function _stopMining()
	isMining = false
	targetChunkKey = nil
	targetFlatIndex = nil
	miningProgress = 0
	_hideHighlight()
end

local function _updateHoverHighlight()
	if isMining then
		return
	end

	local chunkKey, flatIndex, _ = _raycastToBlock()
	if not chunkKey or not flatIndex then
		_hideHighlight()
		return
	end

	local blockTypeId = ChunkRenderController:GetBlockAt(chunkKey, flatIndex)
	if blockTypeId == BlockType.Air then
		_hideHighlight()
		return
	end

	_updateHighlight(chunkKey, flatIndex, blockTypeId)
end

local function _updateMining(dt: number)
	if not isMining then
		return
	end

	local chunkKey, flatIndex, _ = _raycastToBlock()

	if not chunkKey or not flatIndex then
		_hideHighlight()
		targetChunkKey = nil
		targetFlatIndex = nil
		miningProgress = 0
		return
	end

	local blockTypeId = ChunkRenderController:GetBlockAt(chunkKey, flatIndex)
	if blockTypeId == BlockType.Air then
		_hideHighlight()
		targetChunkKey = nil
		targetFlatIndex = nil
		miningProgress = 0
		return
	end

	-- Client-side tier pre-check
	local tool = _getCurrentToolConfig()
	local blockConfig = BlockRegistry.get(blockTypeId)
	if blockConfig and tool.tier < (blockConfig.minTier or 1) then
		_updateHighlight(chunkKey, flatIndex, blockTypeId)
		_showTierBlocked(blockConfig.name, blockConfig.minTier or 1)
		miningProgress = 0
		return
	end

	-- If target changed, reset progress
	if chunkKey ~= targetChunkKey or flatIndex ~= targetFlatIndex then
		targetChunkKey = chunkKey
		targetFlatIndex = flatIndex
		miningProgress = 0
	end

	_updateHighlight(chunkKey, flatIndex, blockTypeId)
	local hardness = BlockRegistry.getHardness(blockTypeId)
	if hardness > 0 and hardness < math.huge then
		miningProgress += (tool.power / hardness) * dt
	end

	-- Update crack overlay
	_updateCrackOverlay(math.clamp(miningProgress, 0, 1))

	-- Update mining progress bar
	if miningProgress > 0.01 then
		if blockNameLabel then
			blockNameLabel.Text = ""
		end
		if miningProgressGui then
			miningProgressGui.Enabled = true
		end
		if miningProgressNameLabel and blockConfig then
			miningProgressNameLabel.Text = blockConfig.name
			if blockConfig.minTier >= 4 then
				miningProgressNameLabel.TextColor3 = Color3.fromRGB(255, 150, 255)
			elseif blockConfig.minTier >= 3 then
				miningProgressNameLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
			elseif blockConfig.minTier >= 2 then
				miningProgressNameLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
			else
				miningProgressNameLabel.TextColor3 = Color3.new(1, 1, 1)
			end
		end
		if miningProgressFill then
			local p = math.clamp(miningProgress, 0, 1)
			miningProgressFill.Size = UDim2.new(p, 0, 1, 0)
			if p < 0.5 then
				local t = p * 2
				miningProgressFill.BackgroundColor3 = Color3.fromRGB(50 + t * 205, 200, 50)
			else
				local t = (p - 0.5) * 2
				miningProgressFill.BackgroundColor3 = Color3.fromRGB(255, 200 - t * 150, 50)
			end
		end
	else
		if miningProgressGui then
			miningProgressGui.Enabled = false
		end
	end

	-- Send mine request to server at throttled rate
	local now = os.clock()
	local sendInterval = 1 / tool.speed
	if now - lastSendTime >= sendInterval then
		lastSendTime = now
		WorldService.RequestMine:Fire(chunkKey, flatIndex)
	end

	-- Client prediction: if progress >= 1, assume break
	if miningProgress >= 1 then
		miningProgress = 0
		_hideHighlight()
	end
end

-------------------------------------------------
-- Knit lifecycle
-------------------------------------------------

function MiningController:KnitInit()
	camera = workspace.CurrentCamera :: Camera
	_createHighlight()
	_createTierBlockedUI()
end

function MiningController:KnitStart()
	WorldService = Knit.GetService("WorldService")
	MiningService = Knit.GetService("MiningService")
	ChunkRenderController = Knit.GetController("ChunkRenderController")

	-- Input: left click to mine
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			_startMining()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			_stopMining()
		end
	end)

	-- Update mining every frame
	RunService.RenderStepped:Connect(function(dt)
		_updateHoverHighlight()
		_updateMining(dt)
		_updateTierBlockedUI()
	end)

	-- Listen for mining results from server
	MiningService.MiningResult:Connect(function(success: boolean, _itemId: string?, _count: number?, _xp: number?)
		if success then
			miningProgress = 0
		end
	end)

	-- Listen for tool equip confirmations
	MiningService.ToolEquipped:Connect(function(toolId: string)
		equippedToolId = toolId
	end)

	-- Listen for tier blocked messages
	MiningService.TierBlocked:Connect(function(blockName: string, requiredTier: number)
		_showTierBlocked(blockName, requiredTier)
	end)
end

return MiningController
