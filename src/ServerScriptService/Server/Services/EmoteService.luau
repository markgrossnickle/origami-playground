--[[
	EmoteService — server-side emote generation, validation, and broadcasting.
	Preset emotes cost Folds (free currency). Custom LLM emotes cost Cranes (paid currency).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local OrigamiConfig = require(ReplicatedStorage.Shared.OrigamiConfig)

local EmoteService = Knit.CreateService({
	Name = "EmoteService",
	Client = {
		EmotePlayed = Knit.CreateSignal(),
	},
})

-- Rate limiting per player
local _lastEmoteTime: { [number]: number } = {}
local EMOTE_COOLDOWN = 3 -- seconds between emote plays
local GENERATION_COOLDOWN = 10 -- seconds between LLM generations

local _lastGenerationTime: { [number]: number } = {}

-- Cost for preset emotes (Folds)
local PRESET_EMOTE_COST = 0 -- free to play, they already earned them

-- R15 body part whitelist
local VALID_JOINTS: { [string]: boolean } = {
	Neck = true,
	Waist = true,
	RightShoulder = true,
	LeftShoulder = true,
	RightElbow = true,
	LeftElbow = true,
	RightHip = true,
	LeftHip = true,
	RightKnee = true,
	LeftKnee = true,
	RightAnkle = true,
	LeftAnkle = true,
	RightWrist = true,
	LeftWrist = true,
	Root = true,
}

-- Preset emotes (hardcoded, no LLM call needed)
local PRESET_EMOTES = {
	celebration = {
		name = "Celebration",
		duration = 2.0,
		loop = false,
		keyframes = {
			{ time = 0, joints = {} },
			{
				time = 0.4,
				joints = { RightShoulder = { 0, 0, -170 }, LeftShoulder = { 0, 0, 170 }, Waist = { -10, 0, 0 } },
			},
			{
				time = 0.8,
				joints = { RightShoulder = { 0, 0, -160 }, LeftShoulder = { 0, 0, 160 }, Waist = { -5, 15, 0 } },
			},
			{
				time = 1.2,
				joints = { RightShoulder = { 0, 0, -170 }, LeftShoulder = { 0, 0, 170 }, Waist = { -5, -15, 0 } },
			},
			{
				time = 1.6,
				joints = { RightShoulder = { 0, 0, -160 }, LeftShoulder = { 0, 0, 160 }, Waist = { -5, 10, 0 } },
			},
			{ time = 2.0, joints = {} },
		},
	},
	thank_you = {
		name = "Thank You",
		duration = 2.0,
		loop = false,
		keyframes = {
			{ time = 0, joints = {} },
			{
				time = 0.5,
				joints = {
					Waist = { 30, 0, 0 },
					RightShoulder = { 30, 0, -20 },
					RightElbow = { 60, 0, 0 },
					Neck = { 15, 0, 0 },
				},
			},
			{
				time = 1.2,
				joints = {
					Waist = { 35, 0, 0 },
					RightShoulder = { 30, 0, -20 },
					RightElbow = { 60, 0, 0 },
					Neck = { 15, 0, 0 },
				},
			},
			{ time = 2.0, joints = {} },
		},
	},
	wave = {
		name = "Wave",
		duration = 2.0,
		loop = false,
		keyframes = {
			{ time = 0, joints = {} },
			{ time = 0.3, joints = { RightShoulder = { 0, 0, -150 }, RightElbow = { 30, 0, 0 } } },
			{ time = 0.6, joints = { RightShoulder = { 0, 0, -160 }, RightElbow = { 50, 0, 0 } } },
			{ time = 0.9, joints = { RightShoulder = { 0, 0, -150 }, RightElbow = { 20, 0, 0 } } },
			{ time = 1.2, joints = { RightShoulder = { 0, 0, -160 }, RightElbow = { 50, 0, 0 } } },
			{ time = 1.5, joints = { RightShoulder = { 0, 0, -150 }, RightElbow = { 30, 0, 0 } } },
			{ time = 2.0, joints = {} },
		},
	},
	dance = {
		name = "Dance",
		duration = 3.0,
		loop = true,
		keyframes = {
			{ time = 0, joints = { Waist = { 0, 0, 0 }, RightShoulder = { 0, 0, -40 }, LeftShoulder = { 0, 0, 40 } } },
			{
				time = 0.5,
				joints = {
					Waist = { 0, 20, 0 },
					RightShoulder = { 0, 0, -90 },
					LeftShoulder = { 0, 0, 20 },
					RightHip = { 0, 0, 0 },
					LeftHip = { -20, 0, 0 },
				},
			},
			{
				time = 1.0,
				joints = {
					Waist = { 0, -20, 0 },
					RightShoulder = { 0, 0, -20 },
					LeftShoulder = { 0, 0, 90 },
					RightHip = { -20, 0, 0 },
					LeftHip = { 0, 0, 0 },
				},
			},
			{
				time = 1.5,
				joints = {
					Waist = { 0, 20, 0 },
					RightShoulder = { 0, 0, -90 },
					LeftShoulder = { 0, 0, 20 },
					RightHip = { 0, 0, 0 },
					LeftHip = { -20, 0, 0 },
				},
			},
			{
				time = 2.0,
				joints = {
					Waist = { 0, -20, 0 },
					RightShoulder = { 0, 0, -20 },
					LeftShoulder = { 0, 0, 90 },
					RightHip = { -20, 0, 0 },
					LeftHip = { 0, 0, 0 },
				},
			},
			{
				time = 2.5,
				joints = { Waist = { 0, 15, 0 }, RightShoulder = { 0, 0, -70 }, LeftShoulder = { 0, 0, 40 } },
			},
			{
				time = 3.0,
				joints = { Waist = { 0, 0, 0 }, RightShoulder = { 0, 0, -40 }, LeftShoulder = { 0, 0, 40 } },
			},
		},
	},
}

-- Content safety: detect inappropriate movement patterns
local function isInappropriate(keyframes: { any }): (boolean, string?)
	for _, kf in ipairs(keyframes) do
		local joints = kf.joints
		if not joints then
			continue
		end

		-- Check for thrusting: rapid hip forward motion combined with waist motion
		local waist = joints.Waist
		local rightHip = joints.RightHip
		local leftHip = joints.LeftHip

		-- Flag: waist X > 25 (leaning forward) combined with hip X < -15 (thrust forward)
		if waist and (rightHip or leftHip) then
			local waistX = if type(waist) == "table" then (waist[1] or 0) else 0
			local hipForward = false
			if rightHip and type(rightHip) == "table" then
				if (rightHip[1] or 0) < -15 then
					hipForward = true
				end
			end
			if leftHip and type(leftHip) == "table" then
				if (leftHip[1] or 0) < -15 then
					hipForward = true
				end
			end
			if waistX > 25 and hipForward then
				return true, "Inappropriate hip/waist combination detected"
			end
		end

		-- Flag: repeated hip extension patterns (both hips pushing forward)
		if rightHip and leftHip and type(rightHip) == "table" and type(leftHip) == "table" then
			local rX = rightHip[1] or 0
			local lX = leftHip[1] or 0
			if rX < -20 and lX < -20 then
				return true, "Both hips extending forward simultaneously"
			end
		end
	end

	-- Check for thrusting cycle: waist X oscillating rapidly between +/- values
	local waistXValues = {}
	for _, kf in ipairs(keyframes) do
		if kf.joints and kf.joints.Waist and type(kf.joints.Waist) == "table" then
			table.insert(waistXValues, kf.joints.Waist[1] or 0)
		end
	end
	-- Detect oscillation: 3+ sign changes with amplitude > 15
	local signChanges = 0
	for i = 2, #waistXValues do
		if math.abs(waistXValues[i]) > 15 and math.abs(waistXValues[i - 1]) > 15 then
			if (waistXValues[i] > 0) ~= (waistXValues[i - 1] > 0) then
				signChanges += 1
			end
		end
	end
	if signChanges >= 3 then
		return true, "Repetitive thrusting motion pattern"
	end

	return false, nil
end

-- Validate emote keyframe data for safety and correctness.
local function validateEmoteData(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "Emote data must be a table"
	end

	-- Duration check
	local duration = data.duration
	if type(duration) ~= "number" or duration <= 0 or duration > 5 then
		return false, "Duration must be 0-5 seconds"
	end

	local keyframes = data.keyframes
	if type(keyframes) ~= "table" or #keyframes == 0 or #keyframes > 20 then
		return false, "Must have 1-20 keyframes"
	end

	-- Validate each keyframe
	for i, kf in ipairs(keyframes) do
		if type(kf) ~= "table" then
			return false, "Keyframe " .. i .. " must be a table"
		end
		if type(kf.time) ~= "number" or kf.time < 0 or kf.time > duration then
			return false, "Keyframe " .. i .. " has invalid time"
		end
		if kf.joints and type(kf.joints) == "table" then
			for jointName, rotation in pairs(kf.joints) do
				if not VALID_JOINTS[jointName] then
					return false, "Invalid joint: " .. tostring(jointName)
				end
				if type(rotation) ~= "table" or #rotation < 3 then
					return false, "Joint " .. jointName .. " rotation must be [rx, ry, rz]"
				end
				-- Clamp rotations
				for j = 1, 3 do
					if type(rotation[j]) ~= "number" then
						return false, "Joint " .. jointName .. " has non-number rotation"
					end
					rotation[j] = math.clamp(rotation[j], -180, 180)
				end
			end
		end
	end

	-- Content safety check
	local inappropriate, reason = isInappropriate(keyframes)
	if inappropriate then
		return false, reason
	end

	return true, nil
end

-- Get a preset emote by name.
function EmoteService.Client:GetPresetEmotes(_player: Player)
	local result = {}
	for key, emote in pairs(PRESET_EMOTES) do
		result[key] = {
			name = emote.name,
			duration = emote.duration,
			loop = emote.loop,
		}
	end
	return result
end

-- Play a preset emote (free — no currency cost).
function EmoteService.Client:PlayPresetEmote(player: Player, presetName: string)
	local now = os.clock()
	local lastTime = _lastEmoteTime[player.UserId] or 0
	if now - lastTime < EMOTE_COOLDOWN then
		return { success = false, error = "Emote cooldown" }
	end

	local emote = PRESET_EMOTES[presetName]
	if not emote then
		return { success = false, error = "Unknown preset: " .. tostring(presetName) }
	end

	_lastEmoteTime[player.UserId] = now
	-- Broadcast to all clients
	self.EmotePlayed:FireAll(player, emote)
	return { success = true }
end

-- Play a saved/custom emote.
function EmoteService.Client:PlayEmote(player: Player, keyframeData: any)
	local now = os.clock()
	local lastTime = _lastEmoteTime[player.UserId] or 0
	if now - lastTime < EMOTE_COOLDOWN then
		return { success = false, error = "Emote cooldown" }
	end

	local valid, err = validateEmoteData(keyframeData)
	if not valid then
		return { success = false, error = err }
	end

	_lastEmoteTime[player.UserId] = now
	self.EmotePlayed:FireAll(player, keyframeData)
	return { success = true }
end

-- Request a custom emote from LLM (costs Cranes).
function EmoteService.Client:RequestEmote(player: Player, prompt: string, style: string?)
	-- Rate limit
	local now = os.clock()
	local lastGen = _lastGenerationTime[player.UserId] or 0
	if now - lastGen < GENERATION_COOLDOWN then
		return {
			success = false,
			error = "Generation cooldown (" .. math.ceil(GENERATION_COOLDOWN - (now - lastGen)) .. "s)",
		}
	end

	-- Validate prompt
	if type(prompt) ~= "string" or #prompt < 2 or #prompt > 200 then
		return { success = false, error = "Prompt must be 2-200 characters" }
	end

	-- Deduct Cranes
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	local cost = OrigamiConfig.CRANE_COSTS.emote_generation or 1
	if data.Cranes < cost then
		return { success = false, error = "Need " .. cost .. " Cranes" }
	end

	_lastGenerationTime[player.UserId] = now

	-- Call LLM via OrigamiService (server-side call to Client method with player)
	local OrigamiService = Knit.GetService("OrigamiService")
	local result = OrigamiService.Client:RequestModel(player, prompt, "emote", style or "origami")

	if not result or not result.success then
		return { success = false, error = result and result.error or "Generation failed" }
	end

	-- The LLM returns animation-style data; validate it
	local emoteData = result.model
	if not emoteData then
		return { success = false, error = "No emote data returned" }
	end

	local valid, err = validateEmoteData(emoteData)
	if not valid then
		return { success = false, error = "Generated emote failed validation: " .. (err or "unknown") }
	end

	-- Deduct cost after successful generation
	local currentCranes = PlayerDataService:Read(player, { "Cranes" }) or 0
	PlayerDataService:Write(player, { "Cranes" }, currentCranes - cost)

	return { success = true, emote = emoteData }
end

-- Get saved emotes for a player.
function EmoteService.Client:GetSavedEmotes(player: Player)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	return data and data.SavedEmotes or {}
end

-- Save a custom emote (max 10).
function EmoteService.Client:SaveEmote(player: Player, name: string, keyframeData: any)
	if type(name) ~= "string" or #name < 1 or #name > 30 then
		return { success = false, error = "Name must be 1-30 characters" }
	end

	local valid, err = validateEmoteData(keyframeData)
	if not valid then
		return { success = false, error = err }
	end

	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	if #data.SavedEmotes >= 10 then
		return { success = false, error = "Max 10 saved emotes" }
	end

	local emotes = data.SavedEmotes or {}
	table.insert(emotes, {
		name = name,
		duration = keyframeData.duration,
		loop = keyframeData.loop,
		keyframes = keyframeData.keyframes,
	})
	PlayerDataService:Write(player, { "SavedEmotes" }, emotes)

	return { success = true }
end

-- Delete a saved emote by index.
function EmoteService.Client:DeleteEmote(player: Player, index: number)
	local PlayerDataService = Knit.GetService("PlayerDataService")
	local data = PlayerDataService:Read(player)
	if not data then
		return { success = false, error = "Player data not loaded" }
	end

	if index < 1 or index > #data.SavedEmotes then
		return { success = false, error = "Invalid index" }
	end

	local emotes = data.SavedEmotes or {}
	table.remove(emotes, index)
	PlayerDataService:Write(player, { "SavedEmotes" }, emotes)
	return { success = true }
end

function EmoteService:KnitInit() end
function EmoteService:KnitStart() end

return EmoteService
