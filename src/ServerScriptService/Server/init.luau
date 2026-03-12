local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local vServerStatus = Instance.new("StringValue")
vServerStatus.Name = "ServerStatus"
vServerStatus.Value = "Loading"
vServerStatus.Parent = ReplicatedStorage

local Server = {}

function Server:Main()
	self:Start()
end

function Server:_loadComponentsIn(container: Instance)
	for _, instance in container:GetDescendants() do
		if instance:IsA("ModuleScript") and instance.Name:sub(#instance.Name - 8, #instance.Name) == "Component" then
			require(instance)
		end
	end
end

function Server:Start()
	Knit.AddServices(script.Services)
	return Knit:Start()
		:andThenCall(self._loadComponentsIn, self, script.Components)
		:andThenCall(self._loadComponentsIn, self, ReplicatedStorage.Shared.Components)
		:andThen(function()
			vServerStatus.Value = "Started"
		end)
		:catch(function(msg: string)
			warn(msg)
			vServerStatus.Value = "Crashed"
		end)
end

return Server
