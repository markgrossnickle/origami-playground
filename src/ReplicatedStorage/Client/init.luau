local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Promise = require(ReplicatedStorage.Packages.Promise)

local Player = game:GetService("Players").LocalPlayer

local Client = {}

function Client:Main()
	self:WaitForServerStarted():andThenCall(self.Start, self):catch(function(err)
		Player:Kick("Could not connect to server")
		warn("Server did not start:\n" .. tostring(err))
	end)
end

function Client:WaitForServerStarted()
	return Promise.promisify(ReplicatedStorage.WaitForChild)(ReplicatedStorage, "ServerStatus", 5)
		:andThen(function(vServerStatus)
			if vServerStatus.Value == "Started" then
				return Promise.resolve()
			elseif vServerStatus.Value == "Crashed" then
				return Promise.reject("Server crashed")
			end
			return Promise.fromEvent(vServerStatus:GetPropertyChangedSignal("Value"), function(status)
				return status == "Started" or status == "Crashed"
			end)
				:timeout(15)
				:andThen(function()
					if vServerStatus.Value == "Crashed" then
						return Promise.reject("Server crashed")
					end
				end)
		end)
end

function Client:_loadComponentsIn(container: Instance)
	for _, instance in container:GetDescendants() do
		if
			instance:IsA("ModuleScript")
			and (instance.Parent == container or instance.Name:sub(#instance.Name - 8, #instance.Name) == "Component")
		then
			require(instance)
		end
	end
end

function Client:Start()
	Knit.AddControllers(script.Controllers)
	return Knit
		:Start() --
		:andThenCall(self._loadComponentsIn, self, script.Components)
		:andThenCall(self._loadComponentsIn, self, ReplicatedStorage.Shared.Components)
end

return Client
