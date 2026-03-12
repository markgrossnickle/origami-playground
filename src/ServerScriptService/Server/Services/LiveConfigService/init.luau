--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local CmdrService

-- Deep copy a table
local function deepCopy(tbl: { [string]: any }): { [string]: any }
	local copy = {}
	for key, value in tbl do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

-- Runtime overrides (server-lifetime only, not persisted)
local overrides: { [string]: any } = {}

-- Deep copy of baseline for reset
local baseline = deepCopy(GameConfig)

--[=[
	@class LiveConfigService
	Runtime configuration tuning without restarting.
	Reads GameConfig as baseline. Use Cmdr commands to override at runtime.
	Overrides are server-lifetime only (not persisted) - safe for testing.
]=]
local LiveConfigService = Knit.CreateService({
	Name = "LiveConfigService",
	ConfigChanged = Signal.new(), -- (path: string, newValue: any)
	Client = {},
})

-- ============================================================================
-- Path helpers
-- ============================================================================

local function getValueAtPath(root: { [string]: any }, path: string): any
	local current: any = root
	for segment in path:gmatch("[^%.]+") do
		if type(current) ~= "table" then
			return nil
		end
		current = current[segment]
	end
	return current
end

local function setValueAtPath(root: { [string]: any }, path: string, value: any)
	local segments = {}
	for segment in path:gmatch("[^%.]+") do
		table.insert(segments, segment)
	end
	local current: any = root
	for i = 1, #segments - 1 do
		if type(current) ~= "table" then
			return
		end
		if current[segments[i]] == nil then
			current[segments[i]] = {}
		end
		current = current[segments[i]]
	end
	if type(current) == "table" then
		current[segments[#segments]] = value
	end
end

-- ============================================================================
-- Public API
-- ============================================================================

function LiveConfigService:GetValue(path: string): any
	-- Check overrides first
	if overrides[path] ~= nil then
		return overrides[path]
	end
	-- Fall back to baseline
	return getValueAtPath(baseline, path)
end

function LiveConfigService:SetValue(path: string, value: any)
	overrides[path] = value
	-- Also update the live config table so nested reads work
	setValueAtPath(GameConfig, path, value)
	self.ConfigChanged:Fire(path, value)
end

function LiveConfigService:ResetValue(path: string)
	local baselineValue = getValueAtPath(baseline, path)
	overrides[path] = nil
	setValueAtPath(GameConfig, path, baselineValue)
	self.ConfigChanged:Fire(path, baselineValue)
end

function LiveConfigService:GetAllOverrides(): { [string]: any }
	return table.clone(overrides)
end

-- ============================================================================
-- Client API
-- ============================================================================

function LiveConfigService.Client:GetValue(_player: Player, path: string)
	return self.Server:GetValue(path)
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function LiveConfigService:KnitInit() end

function LiveConfigService:KnitStart()
	CmdrService = Knit.GetService("CmdrService")
	CmdrService:RegisterCmdrContent(script)
end

return LiveConfigService
