return {
	Name = "vehicletest",
	Aliases = { "vtest" },
	Description = "Spawns 10 vehicle test variants in a ring around you.",
	Group = "group",
	Args = {},
	ClientRun = function(context)
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Knit = require(ReplicatedStorage.Packages.Knit)
		local OrigamiService = Knit.GetService("OrigamiService")

		local player = context.Executor
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return "No character found."
		end

		OrigamiService:CreateTestVehicleRing(rootPart.Position)
		return "Spawning 10 vehicle test variants..."
	end,
}
