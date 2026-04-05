return {
	Name = "testfold",
	Aliases = { "tf" },
	Description = "Spawns a demo model 10 studs in front of you with the selected fold animation.",
	Group = "group",
	Args = {
		{
			Type = "foldStyle",
			Name = "Style",
			Description = "Fold animation style (scale, flip, accordion)",
		},
		{
			Type = "foldDemo",
			Name = "Demo",
			Description = "Which demo model to build",
		},
	},
	ClientRun = function(context, style, demoName)
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Workspace = game:GetService("Workspace")
		local OrigamiBuilder = require(ReplicatedStorage.Shared.OrigamiBuilder)
		local OrigamiUnfold = require(ReplicatedStorage.Shared.OrigamiUnfold)
		local FoldDemoData = require(ReplicatedStorage.Shared.FoldDemoData)

		local player = context.Executor
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return "No character found."
		end

		local demoData = FoldDemoData.Demos[demoName]
		if not demoData then
			return "Unknown demo: " .. tostring(demoName)
		end

		local model = OrigamiBuilder.BuildModel(demoData)
		local spawnPos = rootPart.Position + rootPart.CFrame.LookVector * 10 + Vector3.new(0, 2, 0)
		model:PivotTo(CFrame.new(spawnPos))
		model.Parent = Workspace

		OrigamiUnfold.Animate(model, spawnPos, style)

		task.delay(10, function()
			if model.Parent then
				model:Destroy()
			end
		end)

		return string.format("Spawned '%s' with '%s' fold animation.", demoName, style)
	end,
}
