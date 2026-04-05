local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CmdrController = Knit.CreateController({
	Name = "CmdrController",
})
CmdrController.CmdrClient = nil

function CmdrController:KnitInit() end

function CmdrController:KnitStart()
	CmdrController.CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient"))
	CmdrController.CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })

	for _, module in script.Components:GetChildren() do
		assert(module:IsA("ModuleScript"), "Expected ModuleScript")
		require(module)
	end

	-- Cmdr toggle button — positioned directly above the inventory (📦) button
	-- Inventory button: Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = (0, 0.5), Size = 44-48
	local isMobile = UserInputService.TouchEnabled
	local btnSize = if isMobile then 48 else 44

	local PlayerGui = Knit.Player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "CmdrToggleGui"
	gui.DisplayOrder = 100
	gui.ResetOnSpawn = false
	gui.Parent = PlayerGui

	local btn = Instance.new("TextButton")
	btn.Name = "CmdrToggle"
	btn.Size = UDim2.fromOffset(btnSize, btnSize)
	btn.Position = UDim2.new(0, 10, 0.5, -(btnSize + 6))
	btn.AnchorPoint = Vector2.new(0, 0.5)
	btn.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	btn.Text = ">_"
	btn.TextColor3 = Color3.fromRGB(220, 220, 220)
	btn.TextSize = 16
	btn.Font = Enum.Font.Code
	btn.BorderSizePixel = 0
	btn.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = btn

	btn.Activated:Connect(function()
		CmdrController.CmdrClient:Toggle()
	end)
end

function CmdrController:RegisterCmdrContent(container: Instance)
	local CmdrHelper = require(ReplicatedStorage.Shared.CmdrHelper)
	CmdrHelper.RegisterCmdrContent(self.CmdrClient.Registry, container)
end

return CmdrController
