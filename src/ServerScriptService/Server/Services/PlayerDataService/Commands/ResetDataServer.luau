--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function(context, confirm)
	assert(confirm == "FOREVER", "You must type 'FOREVER' to confirm the reset")
	local PlayerDataService = Knit.GetService("PlayerDataService")
	PlayerDataService:ResetAndKick(context.Executor)
	return "Bye!"
end
