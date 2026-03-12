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
	Cmdr:RegisterDefaultCommands()
	self:RegisterCmdrContent(script)
end

function CmdrService:KnitInit()
	Cmdr = require(ServerScriptService.ServerPackages.Cmdr)
end

function CmdrService:RegisterCmdrContent(container: Instance)
	CmdrHelper.RegisterCmdrContent(Cmdr.Registry, container)
end

return CmdrService
