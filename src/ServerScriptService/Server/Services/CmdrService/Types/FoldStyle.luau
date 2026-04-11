return function(registry)
	local styles = { "scale", "flip", "accordion" }

	registry:RegisterType("foldStyle", {
		Transform = function(text)
			return text:lower()
		end,
		Validate = function(value)
			for _, id in styles do
				if id == value then
					return true
				end
			end
			return false, "Unknown fold style. Options: " .. table.concat(styles, ", ")
		end,
		Autocomplete = function(value)
			local results = {}
			local search = value:lower()
			for _, id in styles do
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
