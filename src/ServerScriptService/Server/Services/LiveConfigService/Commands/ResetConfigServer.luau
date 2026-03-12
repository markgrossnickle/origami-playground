--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function(_context, path: string)
	local LiveConfigService = Knit.GetService("LiveConfigService")
	LiveConfigService:ResetValue(path)
	local value = LiveConfigService:GetValue(path)
	return `Reset {path} to baseline: {tostring(value)}`
end
