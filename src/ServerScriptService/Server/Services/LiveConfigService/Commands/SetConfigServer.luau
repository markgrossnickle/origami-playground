--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function(_context, path: string, valueStr: string)
	local LiveConfigService = Knit.GetService("LiveConfigService")

	-- Auto-convert value types
	local value: any = valueStr
	if tonumber(valueStr) then
		value = tonumber(valueStr)
	elseif valueStr == "true" then
		value = true
	elseif valueStr == "false" then
		value = false
	end

	local oldValue = LiveConfigService:GetValue(path)
	LiveConfigService:SetValue(path, value)
	return `Set {path}: {tostring(oldValue)} -> {tostring(value)}`
end
