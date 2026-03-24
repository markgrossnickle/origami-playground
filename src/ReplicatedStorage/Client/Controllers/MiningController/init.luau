--!strict
-- MiningController: Client-side mining input, highlighting, and feedback
-- Triangular-folds variant: raycasts work on WedgePart geometry
-- Cross-platform: mouse, touch, and gamepad support

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local MiningConfig = require(ReplicatedStorage.Shared.MiningConfig)
local ChunkUtil = require(ReplicatedStorage.Shared.ChunkUtil)
local BlockType = require(ReplicatedStorage.Shared.Enums.BlockType)

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
local targetCx: number? = nil
local targetCy: number? = nil
local targetCz: number? = nil
local targetLx: number? = nil
local targetLy: number? = nil
local targetLz: number? = nil

-- Highlight box for targeted block
local highlightPart: Part? = nil

-- UI elements
local screenGui: ScreenGui? = nil
local floatingTextTemplate: TextLabel? = nil

-- Services (set in KnitStart)
local MiningService: any = nil
local ChunkStreamService: any = nil
local WorldService: any = nil

function MiningController:KnitInit() end

function MiningController:KnitStart()
	MiningService = Knit.GetService("MiningService")
	ChunkStreamService = Knit.GetService("ChunkStreamService")
	WorldService = Knit.GetService("WorldService")

	GameMode.Changed:Connect(function(newMode: string, _oldMode: string)
		if newMode == "mining" then
			self:_activate()
		elseif active then
			self:_deactivate()
		end
	end)

	MiningService.BlockBroken:Connect(
		function(
			_cx: number,
			_cy: number,
			_cz: number,
			_lx: number,
			_ly: number,
			_lz: number,
			_blockTypeId: number,
			xp: number
		)
			self:_showFloatingText("Block broken!", Color3.fromRGB(100, 255, 100))
			if xp and xp > 0 then
				task.delay(0.2, function()
					self:_showFloatingText("+" .. xp .. " XP", Color3.fromRGB(255, 220, 80))
				end)
			end
		end
	)

	MiningService.MineProgress:Connect(
		function(_cx: number, _cy: number, _cz: number, _lx: number, _ly: number, _lz: number, pct: number)
			self:_updateMiningProgress(pct)
		end
	)

	WorldService.BlockChanged:Connect(
		function(cx: number, cy: number, cz: number, lx: number, ly: number, lz: number, _blockType: number)
			if
				targetCx == cx
				and targetCy == cy
				and targetCz == cz
				and targetLx == lx
				and targetLy == ly
				and targetLz == lz
			then
				targetCx = nil
				self:_hideHighlight()
			end
		end
	)

	self:_setupPortalPrompt()
end

function MiningController:_activate()
	if active then
		return
	end
	active = true

	ChunkStreamService.SetMiningMode:Fire(true)

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

	task.spawn(function()
		MiningService:SetToolTier(1):catch(function(err: any)
			warn("[MiningController] SetToolTier failed:", err)
		end)
	end)

	trove:Add(RunService.Heartbeat:Connect(function()
		self:_update()
	end))
end

function MiningController:_deactivate()
	if not active then
		return
	end
	active = false
	mining = false
	targetCx = nil

	ChunkStreamService.SetMiningMode:Fire(false)
	trove:Clean()

	if highlightPart then
		highlightPart:Destroy()
		highlightPart = nil
	end

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end

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

	local btnSize = if IS_CONSOLE then 52 else if IS_MOBILE then 44 else 34
	local fontSize = if IS_CONSOLE then 20 else if IS_MOBILE then 16 else 14

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

	local tierLabel = Instance.new("TextLabel")
	tierLabel.Name = "TierLabel"
	tierLabel.Size = UDim2.new(0, btnSize * 4, 0, btnSize)
	tierLabel.Position = UDim2.new(0, 10, 0, 10 + btnSize + 6)
	tierLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	tierLabel.BackgroundTransparency = 0.3
	tierLabel.BorderSizePixel = 0
	tierLabel.Text = "Tool: Paper Scissors (T1)"
	tierLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	tierLabel.TextSize = fontSize - 2
	tierLabel.Font = Enum.Font.Gotham
	tierLabel.Parent = gui

	local tierCorner = Instance.new("UICorner")
	tierCorner.CornerRadius = UDim.new(0, 8)
	tierCorner.Parent = tierLabel

	local template = Instance.new("TextLabel")
	template.Name = "FloatingText"
	template.Size = UDim2.new(0, 200, 0, 30)
	template.BackgroundTransparency = 1
	template.TextColor3 = Color3.fromRGB(255, 255, 255)
	template.TextSize = if IS_CONSOLE then 22 else if IS_MOBILE then 18 else 16
	template.Font = Enum.Font.GothamBold
	template.TextStrokeTransparency = 0.5
	template.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	template.Visible = false
	template.Parent = gui
	floatingTextTemplate = template
end

function MiningController:_bindInput()
	ContextActionService:BindAction(
		"MiningAction",
		function(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
			if inputState == Enum.UserInputState.Begin then
				mining = true
			elseif inputState == Enum.UserInputState.End then
				mining = false
			end
			return Enum.ContextActionResult.Pass
		end,
		IS_MOBILE,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.Touch,
		Enum.KeyCode.ButtonR2
	)

	trove:Add(function()
		ContextActionService:UnbindAction("MiningAction")
	end)
end

function MiningController:_update()
	if not active then
		return
	end
	self:_updateTarget()
	if mining and targetCx then
		local now = tick()
		if now - lastMineTick >= MINE_TICK_RATE then
			lastMineTick = now
			self:_tryMine()
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

		if chunkKey and flatIndex then
			local cx, cy, cz = ChunkUtil.parseChunkKey(chunkKey)
			local lx, ly, lz = ChunkUtil.fromFlatIndex(flatIndex)
			targetCx = cx
			targetCy = cy
			targetCz = cz
			targetLx = lx
			targetLy = ly
			targetLz = lz
			local blockCenter = ChunkUtil.blockWorldPosition(cx, cy, cz, lx, ly, lz) + WORLD_OFFSET
			self:_showHighlight(blockCenter)
		else
			self:_hideHighlight()
			targetCx = nil
		end
	else
		self:_hideHighlight()
		targetCx = nil
	end
end

function MiningController:_tryMine()
	if not targetCx then
		return
	end
	local cx = targetCx :: number
	local cy = targetCy :: number
	local cz = targetCz :: number
	local lx = targetLx :: number
	local ly = targetLy :: number
	local lz = targetLz :: number

	task.spawn(function()
		MiningService:MineBlock(cx, cy, cz, lx, ly, lz)
			:andThen(function(_success: boolean) end)
			:catch(function(err: any)
				warn("[MiningController] Mine request failed:", err)
			end)
	end)
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
		highlightPart.Color =
			Color3.fromRGB(math.floor(255 * (1 - progress)), math.floor(255 * progress), 50)
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
		local start = tick()
		local duration = 1.5
		while tick() - start < duration do
			local alpha = (tick() - start) / duration
			label.Position = UDim2.new(0.5, label.Position.X.Offset, 0.4 - alpha * 0.1, 0)
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
			prompt.Triggered:Connect(function(triggerPlayer: Player)
				if triggerPlayer == Player then
					GameMode.SetMode("mining")
				end
			end)
		end
	end)
end

return MiningController
