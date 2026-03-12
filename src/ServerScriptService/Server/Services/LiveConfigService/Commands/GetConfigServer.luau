--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function(_context, path: string)
	local LiveConfigService = Knit.GetService("LiveConfigService")
	local value = LiveConfigService:GetValue(path)
	if value == nil then
		return `Config "{path}" not found`
	end
	return `{path} = {tostring(value)}`
end
