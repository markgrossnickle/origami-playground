--[[
	MountConfig — shared per-locomotion mount physics.
	Referenced by MountService (server) and MountController (client).
]]

local MountConfig = {}

-- Minimum creature bounding-box Y to ride without scaling up
MountConfig.MIN_RIDE_HEIGHT = 4

-- Max scale multiplier when auto-sizing small creatures
MountConfig.MAX_SCALE = 3

-- Dismount keybind
MountConfig.DISMOUNT_KEY = Enum.KeyCode.E

-- Map creature stats.spd [1..100] to speed multiplier [0.5..2.0]
function MountConfig.speedMultiplier(spd: number): number
	return 0.5 + math.clamp((spd - 1) / 99, 0, 1) * 1.5
end

export type LocomotionConfig = {
	maxSpeed: number,
	jumpPower: number,
	canFly: boolean,
	canWallClimb: boolean,
	hoverHeight: number,
	bobAmplitude: number,
	accel: number,
	coast: number,
	turnSpeed: number,
	downforce: number,
}

local LOCOMOTION: { [string]: LocomotionConfig } = {
	walk = {
		maxSpeed = 40,
		jumpPower = 30,
		canFly = false,
		canWallClimb = false,
		hoverHeight = 0,
		bobAmplitude = 0,
		accel = 0.10,
		coast = 0.04,
		turnSpeed = 4,
		downforce = -3,
	},
	fly = {
		maxSpeed = 50,
		jumpPower = 0,
		canFly = true,
		canWallClimb = false,
		hoverHeight = 0,
		bobAmplitude = 0,
		accel = 0.12,
		coast = 0.05,
		turnSpeed = 3.5,
		downforce = 0,
	},
	hop = {
		maxSpeed = 35,
		jumpPower = 80,
		canFly = false,
		canWallClimb = false,
		hoverHeight = 0,
		bobAmplitude = 0,
		accel = 0.10,
		coast = 0.04,
		turnSpeed = 4,
		downforce = -3,
	},
	slither = {
		maxSpeed = 30,
		jumpPower = 20,
		canFly = false,
		canWallClimb = true,
		hoverHeight = 0,
		bobAmplitude = 0,
		accel = 0.08,
		coast = 0.03,
		turnSpeed = 5,
		downforce = -3,
	},
	float = {
		maxSpeed = 20,
		jumpPower = 0,
		canFly = true,
		canWallClimb = false,
		hoverHeight = 4,
		bobAmplitude = 1.2,
		accel = 0.06,
		coast = 0.03,
		turnSpeed = 3,
		downforce = 0,
	},
}

function MountConfig.get(locomotion: string): LocomotionConfig?
	return LOCOMOTION[locomotion]
end

function MountConfig.isMountable(locomotion: string): boolean
	return locomotion ~= "stationary" and LOCOMOTION[locomotion] ~= nil
end

return MountConfig
