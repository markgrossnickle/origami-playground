return {
	Name = "givepick",
	Aliases = { "gp" },
	Description = "Give a pickaxe to a player and equip it.",
	Group = "admin",
	Args = {
		{
			Type = "player",
			Name = "Target",
			Description = "Player to give the pickaxe to",
		},
		{
			Type = "ToolId",
			Name = "Tool",
			Description = "Pickaxe ID to give",
		},
	},
}
