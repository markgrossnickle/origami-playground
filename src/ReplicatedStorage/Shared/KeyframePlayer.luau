--!strict
local RunService = game:GetService("RunService")

local KeyframePlayer = {}

-- Smoothstep easing for smooth interpolation
local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

-- Convert degrees to radians for [X, Y, Z] angle arrays
local function anglesToCFrame(angles: { number }): CFrame
	local x = math.rad(angles[1] or 0)
	local y = math.rad(angles[2] or 0)
	local z = math.rad(angles[3] or 0)
	return CFrame.Angles(x, y, z)
end

-- Interpolate between two CFrame rotations using slerp-like approach
local function lerpCFrame(a: CFrame, b: CFrame, alpha: number): CFrame
	return a:Lerp(b, alpha)
end

export type KeyframeData = {
	time: number,
	joints: { [string]: { number } },
}

export type AnimationData = {
	name: string,
	duration: number,
	loop: boolean,
	keyframes: { KeyframeData },
}

export type PlaybackHandle = {
	Stop: (PlaybackHandle) -> (),
	IsPlaying: (PlaybackHandle) -> boolean,
}

-- Parse animation data from a table (already decoded from JSON)
function KeyframePlayer.Parse(data: { [string]: any }): AnimationData?
	if not data or not data.keyframes or #data.keyframes == 0 then
		warn("[KeyframePlayer] Invalid animation data: missing keyframes")
		return nil
	end

	local animation: AnimationData = {
		name = data.name or "Unnamed",
		duration = data.duration or 2.0,
		loop = if data.loop ~= nil then data.loop else false,
		keyframes = {},
	}

	for _, kf in ipairs(data.keyframes) do
		local keyframe: KeyframeData = {
			time = kf.time or 0,
			joints = {},
		}
		if kf.joints then
			for jointName, angles in pairs(kf.joints) do
				if type(angles) == "table" and #angles >= 3 then
					keyframe.joints[jointName] = { angles[1], angles[2], angles[3] }
				end
			end
		end
		table.insert(animation.keyframes, keyframe)
	end

	-- Sort keyframes by time
	table.sort(animation.keyframes, function(a, b)
		return a.time < b.time
	end)

	return animation
end

-- Find the Motor6D joints in an R15 mannequin model
-- Returns a map of joint name -> Motor6D
function KeyframePlayer.FindJoints(model: Model): { [string]: Motor6D }
	local joints: { [string]: Motor6D } = {}

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("Motor6D") then
			joints[desc.Name] = desc
		end
	end

	return joints
end

-- Get the interpolated joint angles at a given time
local function getJointAnglesAtTime(animation: AnimationData, time: number, jointName: string): CFrame
	local keyframes = animation.keyframes
	local identity = CFrame.new()

	-- Find surrounding keyframes for this joint
	local prevKF: KeyframeData? = nil
	local nextKF: KeyframeData? = nil

	for _, kf in ipairs(keyframes) do
		if kf.time <= time then
			if kf.joints[jointName] then
				prevKF = kf
			end
		end
		if kf.time >= time and nextKF == nil then
			if kf.joints[jointName] then
				nextKF = kf
			end
		end
	end

	-- If no keyframes found for this joint, check all keyframes
	if not prevKF and not nextKF then
		return identity
	end

	-- Only before or at the first keyframe
	if not prevKF and nextKF then
		return anglesToCFrame(nextKF.joints[jointName])
	end

	-- Only after or at the last keyframe
	if prevKF and not nextKF then
		return anglesToCFrame(prevKF.joints[jointName])
	end

	-- Same keyframe
	if prevKF == nextKF then
		return anglesToCFrame(prevKF.joints[jointName])
	end

	-- Interpolate between prev and next
	local prevTime = prevKF.time
	local nextTime = nextKF.time
	local dt = nextTime - prevTime
	local alpha = if dt > 0 then smoothstep((time - prevTime) / dt) else 0

	local prevCF = anglesToCFrame(prevKF.joints[jointName])
	local nextCF = anglesToCFrame(nextKF.joints[jointName])

	return lerpCFrame(prevCF, nextCF, alpha)
end

-- Play an animation on a model with Motor6D joints
-- Returns a PlaybackHandle to control playback
function KeyframePlayer.Play(model: Model, animation: AnimationData): PlaybackHandle
	local joints = KeyframePlayer.FindJoints(model)
	local playing = true
	local startTime = tick()

	-- Store original transforms to restore on stop
	local originalTransforms: { [string]: CFrame } = {}
	for name, joint in pairs(joints) do
		originalTransforms[name] = joint.Transform
	end

	-- Collect all joint names used in the animation
	local animatedJoints: { [string]: boolean } = {}
	for _, kf in ipairs(animation.keyframes) do
		for jointName, _ in pairs(kf.joints) do
			animatedJoints[jointName] = true
		end
	end

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not playing or not model or not model.Parent then
			if connection then
				connection:Disconnect()
			end
			playing = false
			return
		end

		local elapsed = tick() - startTime
		local time: number

		if animation.loop then
			time = elapsed % animation.duration
		else
			time = math.min(elapsed, animation.duration)
			-- Non-looping: hold last frame after duration elapses
		end

		-- Apply joint rotations
		for jointName, _ in pairs(animatedJoints) do
			local joint = joints[jointName]
			if joint then
				local transform = getJointAnglesAtTime(animation, time, jointName)
				joint.Transform = transform
			end
		end
	end)

	local handle: PlaybackHandle = {
		Stop = function(_self)
			playing = false
			if connection then
				connection:Disconnect()
			end
			-- Restore original transforms
			for name, joint in pairs(joints) do
				if joint and joint.Parent then
					joint.Transform = originalTransforms[name] or CFrame.new()
				end
			end
		end,
		IsPlaying = function(_self)
			return playing
		end,
	}

	return handle
end

-- Play a sequence: startup animation, then loop, then optional ending
function KeyframePlayer.PlaySequence(
	model: Model,
	startup: AnimationData?,
	loop: AnimationData,
	ending: AnimationData?
): PlaybackHandle
	local playing = true
	local currentHandle: PlaybackHandle? = nil

	task.spawn(function()
		-- Phase 1: Startup (if provided)
		if startup and playing then
			currentHandle = KeyframePlayer.Play(model, startup)
			task.wait(startup.duration)
			if currentHandle then
				currentHandle:Stop()
			end
		end

		-- Phase 2: Loop
		if playing then
			-- Force loop on
			local loopAnim = loop
			loopAnim.loop = true
			currentHandle = KeyframePlayer.Play(model, loopAnim)

			-- Wait until stopped externally
			while playing and currentHandle and currentHandle:IsPlaying() do
				task.wait(0.1)
			end
		end

		-- Phase 3: Ending (if provided and if stopped gracefully)
		if ending then
			currentHandle = KeyframePlayer.Play(model, ending)
			task.wait(ending.duration)
			if currentHandle then
				currentHandle:Stop()
			end
		end
	end)

	local handle: PlaybackHandle = {
		Stop = function(_self)
			playing = false
			if currentHandle then
				currentHandle:Stop()
			end
		end,
		IsPlaying = function(_self)
			return playing
		end,
	}

	return handle
end

return KeyframePlayer
