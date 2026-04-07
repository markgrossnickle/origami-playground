return function(registry)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ToolRegistry = require(ReplicatedStorage.Shared.ToolRegistry)

	local toolIds = {}
	for id, _ in ToolRegistry.getAllTools() do
		table.insert(toolIds, id)
	end
	table.sort(toolIds)

	registry:RegisterType("toolId", {
		Transform = function(text)
			return text:lower()
		end,
		Validate = function(value)
			if ToolRegistry.get(value) then
				return true
			end
			return false, "Unknown tool. Options: " .. table.concat(toolIds, ", ")
		end,
		Autocomplete = function(value)
			local results = {}
			local search = value:lower()
			for _, id in toolIds do
				if id:find(search, 1, true) then
					table.insert(results, id)
				end
			end
			return results
		end,
		Parse = function(value)
			return value:lower()
		end,
	})
end
