local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CmdrController = Knit.CreateController({
	Name = "CmdrController",
})
CmdrController.CmdrClient = nil

function CmdrController:KnitInit() end

function CmdrController:KnitStart()
	-- Create button FIRST, before loading Cmdr (WaitForChild can block)
	local isMobile = UserInputService.TouchEnabled
	local btnSize = if isMobile then 48 else 44

	local PlayerGui = Knit.Player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "CmdrToggleGui"
	gui.DisplayOrder = 100
	gui.ResetOnSpawn = false
	gui.Parent = PlayerGui

	-- Position where the plot button used to be: below the inventory button
	local btn = Instance.new("TextButton")
	btn.Name = "CmdrToggle"
	btn.Size = UDim2.fromOffset(btnSize, btnSize)
	btn.Position = UDim2.new(0, 10, 0.5, 30)
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

	-- Connect click handler immediately — toggles Cmdr if loaded
	btn.Activated:Connect(function()
		if CmdrController.CmdrClient then
			CmdrController.CmdrClient:Toggle()
		end
	end)

	-- Load Cmdr async so the button is visible immediately
	task.spawn(function()
		local cmdrModule = ReplicatedStorage:WaitForChild("CmdrClient", 60)
		if not cmdrModule then
			warn("[CmdrController] CmdrClient not found — Cmdr may not be installed")
			btn.TextColor3 = Color3.fromRGB(120, 120, 120)
			btn.Text = "x"
			return
		end

		local ok, result = pcall(require, cmdrModule)
		if not ok then
			warn("[CmdrController] Failed to require CmdrClient:", result)
			btn.TextColor3 = Color3.fromRGB(120, 120, 120)
			btn.Text = "x"
			return
		end

		CmdrController.CmdrClient = result
		CmdrController.CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })

		for _, module in script.Components:GetChildren() do
			assert(module:IsA("ModuleScript"), "Expected ModuleScript")
			require(module)
		end
	end)
end

function CmdrController:RegisterCmdrContent(container: Instance)
	if not self.CmdrClient then
		return
	end
	local CmdrHelper = require(ReplicatedStorage.Shared.CmdrHelper)
	CmdrHelper.RegisterCmdrContent(self.CmdrClient.Registry, container)
end

return CmdrController
