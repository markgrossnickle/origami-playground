-- NOTE: Although this file name is Main.server.lua, the Main.meta.json file
-- sets the RunContext property to Client, therefore making this script
-- behave like a LocalScript.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Client = require(ReplicatedStorage.Client)

Client:Main()
