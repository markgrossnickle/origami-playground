--!strict
-- MiningController: Client-side mining input, highlighting, and feedback
-- Pure-cubes variant: sends world-relative coordinates to MiningService
-- Cross-platform: mouse, touch, and gamepad support

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local ContextActionService = game:GetService("ContextActionService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()

local WORLD_OFFSET = MiningConfig.WORLD_OFFSET
local BLOCK_SIZE = MiningConfig.BLOCK_SIZE
local MINE_TICK_RATE = MiningConfig.MINE_TICK_RATE

local MiningController = Knit.CreateController({ Name = "MiningController" })

local trove = Trove.new()
local active = false
local mining = false
local lastMineTick = 0
local targetRelPos: Vector3? = nil
local highlightPart: Part? = nil
local screenGui: ScreenGui? = nil
local floatingTextTemplate: TextLabel? = nil
local tierLabel: TextLabel? = nil
local currentTier = 1
local breakSound: Sound
local hitSound: Sound
local MiningService: any = nil
local ChunkStreamService: any = nil

function MiningController:KnitInit()
	breakSound = Instance.new("Sound")
	breakSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	breakSound.Volume = 0.4
	breakSound.Parent = SoundService
	hitSound = Instance.new("Sound")
	hitSound.SoundId = "rbxasset://sounds/uuhhh.mp3"
	hitSound.Volume = 0.15
	hitSound.PlaybackSpeed = 2.0
	hitSound.Parent = SoundService
end

function MiningController:KnitStart()
	MiningService = Knit.GetService("MiningService")
	ChunkStreamService = Knit.GetService("ChunkStreamService")

	GameMode.Changed:Connect(function(newMode: string, _oldMode: string)
		if newMode == "mining" then
			self:_activate()
		elseif active then
			self:_deactivate()
		end
	end)

	MiningService.MineResult:Connect(function(success: boolean, info: string, value: number)
		if success then
			breakSound:Play()
			self:_showFloatingText("+" .. info, Color3.fromRGB(100, 255, 100))
			if value and value > 0 then
				task.delay(0.2, function()
					self:_showFloatingText("+" .. value .. " XP", Color3.fromRGB(255, 220, 80))
				end)
			end
		elseif info == "progress" then
			hitSound:Play()
			self:_updateMiningProgress(value)
		elseif info == "tier_too_low" then
			self:_showFloatingText("Tool too weak!", Color3.fromRGB(255, 80, 80))
		end
	end)

	self:_setupPortalPrompt()
end

function MiningController:_activate()
	if active then
		return
	end
	active = true
	ChunkStreamService.EnterMiningWorld:Fire()
	local character = Player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			rootPart.CFrame = CFrame.new(WORLD_OFFSET + Vector3.new(0, 220, 0))
		end
	end
	self:_createHighlight()
	self:_createUI()
	self:_bindInput()
	trove:Add(RunService.Heartbeat:Connect(function()
		self:_update()
	end))
	task.spawn(function()
		local ok, tier = MiningService:GetTier():await()
		if ok then
			currentTier = tier
			self:_updateTierLabel()
		end
	end)
end

function MiningController:_deactivate()
	if not active then
		return
	end
	active = false
	mining = false
	targetRelPos = nil
	ChunkStreamService.LeaveMiningWorld:Fire()
	trove:Clean()
	if highlightPart then
		highlightPart:Destroy()
		highlightPart = nil
	end
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	ContextActionService:UnbindAction("MiningAction")
	local character = Player.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			rootPart.CFrame = CFrame.new(0, 10, 0)
		end
	end
end

function MiningController:_createHighlight()
	local part = Instance.new("Part")
	part.Name = "MiningHighlight"
	part.Size = Vector3.new(BLOCK_SIZE + 0.2, BLOCK_SIZE + 0.2, BLOCK_SIZE + 0.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 0.7
	part.Color = Color3.fromRGB(255, 255, 255)
	part.Material = Enum.Material.Neon
	part.CastShadow = false
	part.Parent = nil
	highlightPart = part
end

function MiningController:_createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MiningUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Player:WaitForChild("PlayerGui")
	screenGui = gui
	local btnSize = if IS_CONSOLE then 52 elseif IS_MOBILE then 44 else 34
	local fontSize = if IS_CONSOLE then 20 elseif IS_MOBILE then 16 else 14
	local btn = Instance.new("TextButton")
	btn.Name = "ReturnButton"
	btn.Size = UDim2.new(0, btnSize * 4, 0, btnSize)
	btn.Position = UDim2.new(0, 10, 0, 10)
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	btn.BackgroundTransparency = 0.2
	btn.BorderSizePixel = 0
	btn.Text = "Return to Spawn"
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = fontSize
	btn.Font = Enum.Font.GothamBold
	btn.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn
	btn.Activated:Connect(function()
		GameMode.SetMode("sandbox")
	end)
	local tLabel = Instance.new("TextLabel")
	tLabel.Name = "TierLabel"
	tLabel.Size = UDim2.new(0, btnSize * 4, 0, btnSize)
	tLabel.Position = UDim2.new(0, 10, 0, 10 + btnSize + 6)
	tLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	tLabel.BackgroundTransparency = 0.3
	tLabel.BorderSizePixel = 0
	tLabel.Text = "Tool: Paper Scissors (T1)"
	tLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	tLabel.TextSize = fontSize - 2
	tLabel.Font = Enum.Font.Gotham
	tLabel.Parent = gui
	local tierCorner = Instance.new("UICorner")
	tierCorner.CornerRadius = UDim.new(0, 8)
	tierCorner.Parent = tLabel
	tierLabel = tLabel
	local upgradeBtn = Instance.new("TextButton")
	upgradeBtn.Name = "UpgradeButton"
	upgradeBtn.Size = UDim2.new(0, btnSize * 4, 0, btnSize)
	upgradeBtn.Position = UDim2.new(0, 10, 0, 10 + (btnSize + 6) * 2)
	upgradeBtn.BackgroundColor3 = Color3.fromRGB(80, 140, 80)
	upgradeBtn.BackgroundTransparency = 0.2
	upgradeBtn.BorderSizePixel = 0
	upgradeBtn.Text = "Upgrade Tool"
	upgradeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	upgradeBtn.TextSize = fontSize
	upgradeBtn.Font = Enum.Font.GothamBold
	upgradeBtn.Parent = gui
	local upgradeCorner = Instance.new("UICorner")
	upgradeCorner.CornerRadius = UDim.new(0, 8)
	upgradeCorner.Parent = upgradeBtn
	upgradeBtn.Activated:Connect(function()
		task.spawn(function()
			local ok, result = MiningService:UpgradeTier():await()
			if ok then
				local success = result[1]
				local newTier = result[2]
				if success then
					currentTier = newTier
					self:_updateTierLabel()
					self:_showFloatingText("Tool upgraded!", Color3.fromRGB(100, 255, 200))
				else
					self:_showFloatingText("Max tier!", Color3.fromRGB(255, 200, 80))
				end
			end
		end)
	end)
	local crosshair = Instance.new("Frame")
	crosshair.Name = "Crosshair"
	crosshair.Size = UDim2.new(0, 6, 0, 6)
	crosshair.Position = UDim2.new(0.5, -3, 0.5, -3)
	crosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	crosshair.BackgroundTransparency = 0.3
	crosshair.BorderSizePixel = 0
	crosshair.Parent = gui
	local crossCorner = Instance.new("UICorner")
	crossCorner.CornerRadius = UDim.new(0.5, 0)
	crossCorner.Parent = crosshair
	local template = Instance.new("TextLabel")
	template.Name = "FloatingText"
	template.Size = UDim2.new(0, 200, 0, 30)
	template.BackgroundTransparency = 1
	template.TextColor3 = Color3.fromRGB(255, 255, 255)
	template.TextSize = if IS_CONSOLE then 22 elseif IS_MOBILE then 18 else 16
	template.Font = Enum.Font.GothamBold
	template.TextStrokeTransparency = 0.5
	template.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	template.Visible = false
	template.Parent = gui
	floatingTextTemplate = template
end

function MiningController:_updateTierLabel()
	if not tierLabel then
		return
	end
	local toolDef = MiningConfig.TOOL_TIERS[currentTier]
	if toolDef then
		tierLabel.Text = "Tool: " .. toolDef.name .. " (T" .. currentTier .. ")"
	end
end

function MiningController:_bindInput()
	ContextActionService:BindAction("MiningAction", function(_actionName, inputState, _inputObject)
		if inputState == Enum.UserInputState.Begin then
			mining = true
		elseif inputState == Enum.UserInputState.End then
			mining = false
		end
		return Enum.ContextActionResult.Pass
	end, IS_MOBILE, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.ButtonR2)
	trove:Add(function()
		ContextActionService:UnbindAction("MiningAction")
	end)
end

function MiningController:_update()
	if not active then
		return
	end
	self:_updateTarget()
	if mining and targetRelPos then
		local now = tick()
		if now - lastMineTick >= MINE_TICK_RATE then
			lastMineTick = now
			MiningService.RequestMine:Fire(targetRelPos.X, targetRelPos.Y, targetRelPos.Z)
		end
	end
end

function MiningController:_updateTarget()
	local miningWorld = workspace:FindFirstChild("MiningWorld")
	if not miningWorld then
		self:_hideHighlight()
		return
	end
	local screenCenter = Camera.ViewportSize / 2
	local ray = Camera:ViewportPointToRay(screenCenter.X, screenCenter.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { miningWorld }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 50, rayParams)
	if result and result.Instance then
		local hitPart = result.Instance
		local chunkKey = hitPart:GetAttribute("ChunkKey") :: string?
		local flatIndex = hitPart:GetAttribute("FlatIndex") :: number?
		if chunkKey and flatIndex ~= nil then
			local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
			local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
			local blockPos = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz)
			targetRelPos = blockPos
			self:_showHighlight(blockPos + WORLD_OFFSET)
		else
			self:_hideHighlight()
			targetRelPos = nil
		end
	else
		self:_hideHighlight()
		targetRelPos = nil
	end
end

function MiningController:_showHighlight(position: Vector3)
	if highlightPart then
		highlightPart.Position = position
		highlightPart.Parent = workspace
	end
end

function MiningController:_hideHighlight()
	if highlightPart then
		highlightPart.Parent = nil
	end
end

function MiningController:_updateMiningProgress(progress: number)
	if highlightPart then
		highlightPart.Transparency = 0.7 - progress * 0.5
		highlightPart.Color = Color3.fromRGB(math.floor(255 * (1 - progress)), math.floor(255 * progress), 50)
	end
end

function MiningController:_showFloatingText(text: string, color: Color3)
	if not screenGui or not floatingTextTemplate then
		return
	end
	local label = floatingTextTemplate:Clone()
	label.Text = text
	label.TextColor3 = color
	label.Position = UDim2.new(0.5, math.random(-50, 50), 0.4, 0)
	label.Visible = true
	label.Parent = screenGui
	task.spawn(function()
		local startTime = tick()
		local duration = 1.5
		local startOffset = label.Position.X.Offset
		while tick() - startTime < duration do
			local alpha = (tick() - startTime) / duration
			label.Position = UDim2.new(0.5, startOffset, 0.4 - alpha * 0.1, 0)
			label.TextTransparency = alpha
			label.TextStrokeTransparency = 0.5 + alpha * 0.5
			task.wait()
		end
		label:Destroy()
	end)
end

function MiningController:_setupPortalPrompt()
	task.spawn(function()
		local portal = workspace:WaitForChild("MiningPortal", 30)
		if not portal then
			return
		end
		local prompt = portal:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(triggerPlayer)
				if triggerPlayer == Player then
					GameMode.SetMode("mining")
				end
			end)
		end
	end)
end

return MiningController
