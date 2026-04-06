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
		warn("[CmdrService] KnitStart: Cmdr not loaded, skipping command registration")
		return
	end
	warn("[CmdrService] KnitStart: registering default commands")
	Cmdr:RegisterDefaultCommands()
	self:RegisterCmdrContent(script)
end

function CmdrService:KnitInit()
	warn("[CmdrService] KnitInit: starting Cmdr load")

	local ServerPackages = ServerScriptService:FindFirstChild("ServerPackages")
	if not ServerPackages then
		warn("[CmdrService] ServerPackages not found — run 'wally install' to enable Cmdr")
		return
	end

	local cmdrRedirect = ServerPackages:FindFirstChild("Cmdr")
	if not cmdrRedirect then
		warn("[CmdrService] Cmdr package not found in ServerPackages — run 'wally install'")
		return
	end
	warn("[CmdrService] Found redirect:", cmdrRedirect.ClassName, cmdrRedirect:GetFullName())

	-- Strategy 1: Try the wally redirect (ServerPackages/Cmdr.lua)
	local ok, result = pcall(require, cmdrRedirect)
	if ok then
		warn("[CmdrService] Wally redirect succeeded")
		Cmdr = result
	else
		warn("[CmdrService] Wally redirect failed:", result)

		-- Strategy 2: Navigate _Index directly, handling both Rojo interpretations
		-- Rojo may or may not process cmdr/default.project.json:
		--   Processed: cmdr = ModuleScript (lowercase name)
		--   Not processed: cmdr = Folder containing Cmdr ModuleScript
		local index = ServerPackages:FindFirstChild("_Index")
		if not index then
			warn("[CmdrService] _Index folder not found in ServerPackages")
			return
		end

		local cmdrPkg = nil
		for _, pkg in index:GetChildren() do
			if pkg.Name:lower():find("cmdr") then
				cmdrPkg = pkg
				break
			end
		end

		if not cmdrPkg then
			warn("[CmdrService] No cmdr package found in _Index")
			return
		end

		warn("[CmdrService] Found package:", cmdrPkg.Name)

		-- List children for diagnostics
		for _, child in cmdrPkg:GetChildren() do
			warn("[CmdrService]   child:", child.Name, "(" .. child.ClassName .. ")")
		end

		-- Find the cmdr entry (the wally package root)
		local cmdrEntry = cmdrPkg:FindFirstChild("cmdr")
		if not cmdrEntry then
			warn("[CmdrService] No 'cmdr' child in package folder")
			return
		end

		warn("[CmdrService] cmdr entry:", cmdrEntry.ClassName, cmdrEntry:GetFullName())

		local moduleToRequire = nil

		if cmdrEntry:IsA("ModuleScript") then
			-- Rojo processed the nested default.project.json
			moduleToRequire = cmdrEntry
			warn("[CmdrService] cmdr is a ModuleScript (Rojo processed nested project)")
		elseif cmdrEntry:IsA("Folder") then
			-- Rojo did NOT process the nested project — look for Cmdr child
			warn("[CmdrService] cmdr is a Folder, listing children:")
			for _, child in cmdrEntry:GetChildren() do
				warn("[CmdrService]     ", child.Name, "(" .. child.ClassName .. ")")
			end
			local innerCmdr = cmdrEntry:FindFirstChild("Cmdr")
			if innerCmdr and innerCmdr:IsA("ModuleScript") then
				moduleToRequire = innerCmdr
				warn("[CmdrService] Found inner Cmdr ModuleScript")
			else
				warn("[CmdrService] No Cmdr ModuleScript inside cmdr Folder")
			end
		else
			warn("[CmdrService] cmdr is unexpected type:", cmdrEntry.ClassName)
		end

		if not moduleToRequire then
			warn("[CmdrService] Could not locate Cmdr module — all strategies exhausted")
			return
		end

		ok, result = pcall(require, moduleToRequire)
		if not ok then
			warn("[CmdrService] Failed to require Cmdr module:", result)
			return
		end

		warn("[CmdrService] Cmdr module required successfully via fallback")
		Cmdr = result
	end

	-- Verify CmdrClient was moved to ReplicatedStorage by Cmdr's Initialize
	local cmdrClient = ReplicatedStorage:FindFirstChild("CmdrClient")
	if cmdrClient then
		warn("[CmdrService] CmdrClient is in ReplicatedStorage:", cmdrClient.ClassName)
	else
		warn("[CmdrService] WARNING: CmdrClient NOT found in ReplicatedStorage after Cmdr loaded!")
		warn(
			"[CmdrService] Cmdr type:",
			typeof(Cmdr),
			"— keys:",
			table.concat(
				(function()
					local keys = {}
					for k in pairs(Cmdr) do
						table.insert(keys, tostring(k))
					end
					return keys
				end)(),
				", "
			)
		)
	end

	Cmdr.Registry:RegisterHook("BeforeRun", function(context)
		if not CmdrHelper.HasCmdrPermissions(context.Executor) then
			return "You don't have permission to run this command."
		end
	end)

	warn("[CmdrService] KnitInit: Cmdr fully initialized")
end

function CmdrService:RegisterCmdrContent(container: Instance)
	if not Cmdr then
		return
	end
	CmdrHelper.RegisterCmdrContent(Cmdr.Registry, container)
end

return CmdrService
