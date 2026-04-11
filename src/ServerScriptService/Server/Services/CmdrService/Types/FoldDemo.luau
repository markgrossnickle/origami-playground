return function(registry)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local FoldDemoData = require(ReplicatedStorage.Shared.FoldDemoData)

	registry:RegisterType("foldDemo", {
		Transform = function(text)
			return text:lower()
		end,
		Validate = function(value)
			if FoldDemoData.Demos[value] then
				return true
			end
			return false, "Unknown demo. Options: " .. table.concat(FoldDemoData.GetNames(), ", ")
		end,
		Autocomplete = function(value)
			local results = {}
			local search = value:lower()
			for _, id in FoldDemoData.GetNames() do
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
