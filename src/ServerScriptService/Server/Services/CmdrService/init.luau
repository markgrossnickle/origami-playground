local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CmdrHelper = require(ReplicatedStorage.Shared.CmdrHelper)
local Knit = require(ReplicatedStorage.Packages.Knit)
local Cmdr

local CmdrService = Knit.CreateService({
	Name = "CmdrService",
	Client = {},
})

function CmdrService:KnitStart()
	if not Cmdr then
		return
	end
	Cmdr:RegisterDefaultCommands()
	self:RegisterCmdrContent(script)
end

function CmdrService:KnitInit()
	local ServerPackages = ServerScriptService:FindFirstChild("ServerPackages")
	if not ServerPackages then
		warn("[CmdrService] ServerPackages not found — run 'wally install' to enable Cmdr")
		return
	end

	local cmdrRedirect = ServerPackages:FindFirstChild("Cmdr")
	if not cmdrRedirect then
		warn("[CmdrService] Cmdr package not found — run 'wally install' to enable Cmdr")
		return
	end

	-- Try the wally redirect first
	local ok, result = pcall(require, cmdrRedirect)
	if not ok then
		-- Wally redirect fails when it points to a Folder instead of a ModuleScript.
		-- Cmdr's package nests the real module inside cmdr/Cmdr/init.lua.
		-- Search _Index for the actual Cmdr ModuleScript.
		warn("[CmdrService] Wally redirect failed, searching _Index for Cmdr module:", result)
		local index = ServerPackages:FindFirstChild("_Index")
		if index then
			for _, pkg in index:GetChildren() do
				if pkg.Name:find("cmdr") then
					for _, desc in pkg:GetDescendants() do
						if desc:IsA("ModuleScript") and desc.Name == "Cmdr" then
							ok, result = pcall(require, desc)
							if ok then
								break
							end
						end
					end
					if ok then
						break
					end
				end
			end
		end
		if not ok then
			warn("[CmdrService] Failed to load Cmdr:", result)
			return
		end
	end
	Cmdr = result

	Cmdr.Registry:RegisterHook("BeforeRun", function(context)
		if not CmdrHelper.HasCmdrPermissions(context.Executor) then
			return "You don't have permission to run this command."
		end
	end)
end

function CmdrService:RegisterCmdrContent(container: Instance)
	if not Cmdr then
		return
	end
	CmdrHelper.RegisterCmdrContent(Cmdr.Registry, container)
end

return CmdrService
