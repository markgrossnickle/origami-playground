local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameVersion = ReplicatedStorage.GameVersion

return GameVersion.Value:match("^%s*([^%s]*)%s*$")
