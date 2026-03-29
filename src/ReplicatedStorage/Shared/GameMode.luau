-- GameMode: Shared state module for switching between game modes
-- All controllers observe GameMode.Changed to show/hide their UIs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

local GameMode = {}

GameMode.MODES = {
	{ key = "expedition", display = "Expedition" },
	{ key = "sandbox", display = "Sandbox" },
	{ key = "auto_battler", display = "Auto Battler" },
	{ key = "animate", display = "Animate" },
	{ key = "demo", display = "Demo" },
}

GameMode.Current = "sandbox"
GameMode.Changed = Signal.new() -- fires (newMode, oldMode)

function GameMode.SetMode(key: string)
	if key == GameMode.Current then
		return
	end

	-- Validate mode key
	local valid = false
	for _, mode in ipairs(GameMode.MODES) do
		if mode.key == key then
			valid = true
			break
		end
	end
	if not valid then
		warn("[GameMode] Invalid mode:", key)
		return
	end

	local oldMode = GameMode.Current
	GameMode.Current = key
	GameMode.Changed:Fire(key, oldMode)
end

return GameMode
