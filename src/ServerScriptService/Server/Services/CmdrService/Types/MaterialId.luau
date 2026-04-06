return function(registry)
	local materialIds = {
		"paper_scrap",
		"cardboard",
		"wood",
		"dried_pulp",
		"compressed_pulp",
		"clay_chunk",
		"folded_stone",
		"quartz_shard",
		"paper_crystal",
		"ink_stone",
		"origami_rock",
		"gem_fragment",
		"foil_ore",
		"ruby_paper",
		"crystal_shard",
		"foil_sheet",
		"metal_origami",
		"sapphire_crystal",
		"void_stone",
		"dark_paper",
		"shadow_fold",
		"void_crystal",
		"prismatic_shard",
		"core_fragment",
		"rainbow_paper",
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
