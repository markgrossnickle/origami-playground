return {
	Name = "seedmounts",
	Aliases = { "sm" },
	Description = "Give a player one mountable creature for each locomotion type (walk/fly/hop/slither/float).",
	Group = "admin",
	Args = {
		{
			Type = "player",
			Name = "Target",
			Description = "Player to give the creatures to",
		},
	},
}
