return {
	Name = "regenerateworld",
	Aliases = { "regen" },
	Description = "Regenerate the voxel world with a new seed. Random seed if not provided.",
	Group = "admin",
	Args = {
		{
			Type = "number",
			Name = "Seed",
			Description = "World seed (random if omitted)",
			Optional = true,
		},
	},
}
