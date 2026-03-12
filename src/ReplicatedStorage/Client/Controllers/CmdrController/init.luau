local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
end

function CmdrController:RegisterCmdrContent(container: Instance)
	CmdrHelper.RegisterCmdrContent(self.CmdrClient.Registry, container)
end

return CmdrController
