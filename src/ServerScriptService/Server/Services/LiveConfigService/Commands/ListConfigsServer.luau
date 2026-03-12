--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

return function(_context)
	local LiveConfigService = Knit.GetService("LiveConfigService")
	local overrides = LiveConfigService:GetAllOverrides()

	local lines = {}
	local count = 0
	for path, value in overrides do
		count += 1
		table.insert(lines, `  {path} = {tostring(value)}`)
	end

	if count == 0 then
		return "No active overrides"
	end

	table.sort(lines)
	return `Active overrides ({count}):\n` .. table.concat(lines, "\n")
end
