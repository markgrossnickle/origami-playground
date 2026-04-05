local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CmdrHelper = require(ReplicatedStorage.Shared.CmdrHelper)

local CmdrController = Knit.CreateController({
	Name = "CmdrController",
})
CmdrController.CmdrClient = nil

function CmdrController:_shouldSetActivationKeys(): boolean
	return CmdrHelper.HasCmdrPermissions(Knit.Player)
end

function CmdrController:KnitInit() end

function CmdrController:KnitStart()
	if not self:_shouldSetActivationKeys() then
		return
	end

	CmdrController.CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient"))

	CmdrController.CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })

	for _, module in script.Components:GetChildren() do
		assert(module:IsA("ModuleScript"), "Expected ModuleScript")
		require(module)
	end

	-- Mobile Cmdr button (touch devices only)
	if UserInputService.TouchEnabled then
		local PlayerGui = Knit.Player:WaitForChild("PlayerGui")
		local gui = Instance.new("ScreenGui")
		gui.Name = "CmdrMobile"
		gui.DisplayOrder = 100
		gui.ResetOnSpawn = false
		gui.Parent = PlayerGui

		local btn = Instance.new("TextButton")
		btn.Name = "CmdrToggle"
		btn.Size = UDim2.fromOffset(36, 36)
		btn.Position = UDim2.fromOffset(10, 40)
		btn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		btn.BackgroundTransparency = 0.7
		btn.Text = ">_"
		btn.TextColor3 = Color3.fromRGB(200, 200, 200)
		btn.TextSize = 14
		btn.Font = Enum.Font.Code
		btn.BorderSizePixel = 0
		btn.Parent = gui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn

		btn.Activated:Connect(function()
			CmdrController.CmdrClient:Toggle()
		end)
	end
end

function CmdrController:RegisterCmdrContent(container: Instance)
	CmdrHelper.RegisterCmdrContent(self.CmdrClient.Registry, container)
end

return CmdrController
