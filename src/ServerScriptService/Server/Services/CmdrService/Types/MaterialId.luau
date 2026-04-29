return function(registry)
	local materialIds = {
		"paper",
		"pulp",
		"folded_stone",
		"origami_rock",
		"crystal",
		"void_stone",
		"prismatic_block",
		"inkdrop",
		"clay_bead",
		"quartz",
		"gem_fragment",
		"foil_shard",
		"shadow_wisp",
		"prism_core",
		"wood",
	}

	registry:RegisterType("materialId", {
		Transform = function(text)
			return text:lower()
		end,
		Validate = function(value)
			for _, id in materialIds do
				if id == value then
					return true
				end
			end
			return false, "Unknown material. Options: " .. table.concat(materialIds, ", ")
		end,
		Autocomplete = function(value)
			local results = {}
			local search = value:lower()
			for _, id in materialIds do
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
