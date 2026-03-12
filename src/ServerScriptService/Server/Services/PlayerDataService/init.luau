--!strict
export type TableKeys = { string }

-- Options for controlling read behavior
export type ReadOptions = {
	UseLastSavedData: boolean,
}

export type WriteOptions = {
	UseLastSavedData: boolean,
}

-- Determines the maximum amount of time to wait for a profile to load
-- before the promise returned by WaitForProfile rejects automatically
local DEFAULT_PROFILE_WAIT_TIMEOUT = 5 -- seconds

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local t = require(ReplicatedStorage.Packages.t)
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Promise = require(ReplicatedStorage.Packages.Promise)

local playerDataTemplate = require(script.Template)
export type PlayerData = typeof(playerDataTemplate)
export type ProfileStore = ProfileStore.ProfileStore<PlayerData>
export type Profile = ProfileStore.Profile<PlayerData>

local PlayerStore: ProfileStore.ProfileStore<PlayerData>
local Profiles: { [Player]: Profile } = {}

local CmdrService

--[=[
	@class PlayerDataService
	Profile-based player data persistence service.
]=]
local PlayerDataService = Knit.CreateService({
	Name = "PlayerDataService",
	ProfileReady = Signal.new(),
	PathWritten = Signal.new(), --(player: Player, path: TableKeys, newValue: any)
	Client = {},

	RegisteredServices = {} :: { [Player]: { [string]: boolean } },
})

function PlayerDataService:_loadProfile(player: Player): ()
	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile ~= nil then
		profile:AddUserId(player.UserId)
		profile:Reconcile() -- Update profile data to match current template
		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			player:Kick(`Profile session has ended - Please rejoin`)
		end)
		if player.Parent == Players then
			Profiles[player] = profile
			print(`Profile loaded for {player.DisplayName} ({player.UserId})!`)
			self.ProfileReady:Fire(player)
		else
			profile:EndSession()
		end
	else
		player:Kick(`Failed to load profile - Please rejoin`)
	end
end

function PlayerDataService:_loadPlayerProfiles(): ()
	for _, player in Players:GetPlayers() do
		task.spawn(self._loadProfile, self, player)
	end
end

local function writeAtPath(root: { [string]: any }, path: TableKeys, value: any)
	local target = root
	for i = 1, #path - 1 do
		local pathContext = if i == 1 then "(root)" else path[i - 1]
		assert(typeof(target) == "table", `Invalid write path led to non-table value at key {pathContext}`)
		local key = path[i]
		if target[key] == nil then
			target[key] = {}
		end
		target = target[key]
	end
	assert(value ~= nil, "Value must be a non-nil type.")
	target[path[#path]] = value
end

function PlayerDataService:WaitForProfile(player: Player)
	if not player or not player:IsA("Player") then
		warn("PlayerDataService:WaitForProfile invalid player")
		return Promise.reject("Invalid player passed to WaitForProfile")
	end
	return if Profiles[player]
		then Promise.resolve(Profiles[player])
		else Promise.fromEvent(self.ProfileReady, function(playerReady)
			return playerReady == player
		end)
			:timeout(DEFAULT_PROFILE_WAIT_TIMEOUT)
			:andThen(function(playerReady)
				return Promise.resolve(Profiles[playerReady])
			end)
end

function PlayerDataService:ResetAndKick(player: Player)
	local profile = Profiles[player]
	if profile then
		profile:EndSession()
		local success, err = pcall(function()
			PlayerStore:RemoveAsync(`{player.UserId}`)
		end)
		if not success then
			warn(`Failed to remove profile data for player {player.UserId}: {err}`)
		end
	end
end

function PlayerDataService:RegisterService(player: Player, serviceName: string)
	if self.RegisteredServices[player] then
		self.RegisteredServices[player][serviceName] = true
	end
end

function PlayerDataService:ServiceFinished(player: Player, serviceName: string)
	local profile = Profiles[player]

	if profile then
		if self.RegisteredServices[player] then
			local isAnyoneActive = false
			for service, _ in self.RegisteredServices[player] do
				if service == serviceName then
					self.RegisteredServices[player][serviceName] = false
				end
				if self.RegisteredServices[player][service] == true then
					isAnyoneActive = true
				end
			end
			if not isAnyoneActive then
				print(`All services finished for player {player.Name} ({player.UserId})`)
				profile:EndSession()
			end
		end
	end
end

function PlayerDataService:KnitStart()
	CmdrService = Knit.GetService("CmdrService")

	self:_loadPlayerProfiles()

	CmdrService:RegisterCmdrContent(script)
end

function PlayerDataService:KnitInit()
	PlayerStore = ProfileStore.New("PlayerStore", playerDataTemplate) :: ProfileStore.ProfileStore<PlayerData>
	Players.PlayerAdded:Connect(function(Player: Player)
		self.RegisteredServices[Player] = {}
		self:_loadProfile(Player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self.RegisteredServices[player] = nil
		local profile = Profiles[player]
		if profile ~= nil then
			task.wait(10)
			if Profiles[player] == nil then
				print("Profile already ended for player ", player.Name)
				return
			end
			print("Timeout Ending profile session for player ", player.Name)
			profile:EndSession()
		end
	end)
end

local tRead = t.tuple(
	t.instanceOf("Player"),
	t.optional(t.array(t.string)),
	t.optional(t.interface({ UseLastSavedData = t.boolean }))
)
--[=[
	Read profile data
	@param player -- The target player
	@param path -- Array of strings that represents path to data (optional)
	@param options -- table of read options (optional)
]=]
function PlayerDataService:Read(player: Player, path: TableKeys?, options: ReadOptions?)
	assert(tRead(player, path, options))
	local profile = self:WaitForProfile(player):expect()
	if profile == nil then
		error(`Profile for player {player.UserId} is not loaded`)
	end

	local data: any = if options and options.UseLastSavedData then profile.LastSavedData else profile.Data
	if path ~= nil then
		for i = 1, #path do
			local key = path[i]
			assert(type(data) == "table", "Invalid read path led to non-table value")
			if data[key] == nil then
				return nil
			end
			data = data[key]
		end
	end
	return data
end

local tWrite =
	t.tuple(t.instanceOf("Player"), t.array(t.string), t.any, t.optional(t.interface({ UseLastSavedData = t.boolean })))
--[=[
	Writes the specified value to the player's profile at the specified path
	@param player -- The target player
	@param path -- Array of strings that represents path to entry
	@param value -- The data to be written
	@param _options -- table of write options (optional)
]=]
function PlayerDataService:Write(player: Player, path: TableKeys, value: any, _options: WriteOptions?)
	assert(tWrite(player, path, value, _options))

	local profile = self:WaitForProfile(player):expect()
	if profile == nil then
		error(`Profile for player {player.UserId} is not loaded`)
	end

	if type(value) == "function" then
		value = value(profile.Data)
	end
	writeAtPath(profile.Data, path, value)
	self.PathWritten:Fire(player, path, value)
	if RunService:IsStudio() then
		print(`Wrote to profile for {player.Name} ({player.UserId}): {table.concat(path, ".")} = {value}`)
	end
	if profile:IsActive() then
		profile:Save()
	else
		warn(
			`Profile for player {player.Name} ({player.UserId}) is inactive.`,
			`Profile data for this session was updated, but data was not saved to DataStore.`
		)
	end
end

function PlayerDataService:GetChangedSignal<T>(player: Player, path: TableKeys): (Signal.Signal<T>, Trove.Trove)
	local trove = Trove.new()
	local signal = trove:Construct(Signal) :: Signal.Signal<T>
	trove:Connect(self.PathWritten, function(player_, path_, newValue)
		if player_ ~= player then
			return
		end

		-- Check that the path that was written to partially matches the path of this DataStorePath
		-- e.g. an update to { "Some", "Path", "Here"} should trigger a signal for { "Some", "Path" }
		local matches = true
		for i = 1, #path do
			if path_[i] ~= path[i] then
				matches = false
				break
			end
		end
		if matches then
			signal:Fire(newValue)
		end
	end)
	return signal, trove
end

type TypeChecker = (value: any) -> (boolean, string?)

export type DataStorePath<T> = {
	-- Properties
	Path: TableKeys,
	DefaultValue: T,
	Check: TypeChecker,
	-- Methods
	Read: (self: DataStorePath<T>, player: Player, options: ReadOptions?) -> T,
	Write: (self: DataStorePath<T>, player: Player, value: T, options: WriteOptions?) -> (),
}

function PlayerDataService:BuildDataStorePath<T>(path: TableKeys, defaultValue: T, check: TypeChecker?): DataStorePath<T>
	return {
		Path = table.freeze(table.clone(path)),
		DefaultValue = defaultValue,
		Check = check or t.any,

		Read = function(self_: DataStorePath<T>, player: Player, options: ReadOptions?): T
			local value: any = PlayerDataService:Read(player, self_.Path, options)
			if self_.Check(value) then
				return value
			else
				return defaultValue
			end
		end,

		Write = function(self_: DataStorePath<T>, player: Player, value: T, options: WriteOptions?)
			assert(self_.Check(value))
			return PlayerDataService:Write(player, self_.Path, value, options)
		end,

		--[[
			Returns a Signal that fires when this path or any subpath is written to for the given player.
			Also returns a Trove for cleanup.
		]]
		GetChangedSignal = function(self_: DataStorePath<T>, player: Player): (Signal.Signal<T>, Trove.Trove)
			return PlayerDataService:GetChangedSignal(player, self_.Path)
		end,
	}
end

function PlayerDataService.Client:Read(player: Player)
	return self.Server:Read(player)
end

return PlayerDataService
