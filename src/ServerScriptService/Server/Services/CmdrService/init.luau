local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CmdrHelper = require(ReplicatedStorage.Shared.CmdrHelper)
local Knit = require(ReplicatedStorage.Packages.Knit)
local Cmdr

local CmdrService = Knit.CreateService({
	Name = "CmdrService",
	Client = {},
})

function CmdrService:KnitStart()
	if not Cmdr then
		return
	end
	Cmdr:RegisterDefaultCommands()
	self:RegisterCmdrContent(script)
end

function CmdrService:KnitInit()
	local ServerPackages = ServerScriptService:FindFirstChild("ServerPackages")
	if not ServerPackages or not ServerPackages:FindFirstChild("Cmdr") then
		warn("[CmdrService] Cmdr package not found — run 'wally install' to enable Cmdr")
		return
	end

	local ok, result = pcall(require, ServerPackages.Cmdr)
	if not ok then
		warn("[CmdrService] Failed to load Cmdr:", result)
		return
	end
	Cmdr = result

	Cmdr.Registry:RegisterHook("BeforeRun", function(context)
		if not CmdrHelper.HasCmdrPermissions(context.Executor) then
			return "You don't have permission to run this command."
		end
	end)
end

function CmdrService:RegisterCmdrContent(container: Instance)
	if not Cmdr then
		return
	end
	CmdrHelper.RegisterCmdrContent(Cmdr.Registry, container)
end

return CmdrService
