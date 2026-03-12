--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PromiseTypes = require(ReplicatedStorage.Shared.Types.PromiseTypes)
type Promise<T> = PromiseTypes.Promise<T>

-- Option types
export type AnimationOptions = {
	BlendTime: number?,
	Looped: boolean?,
	Speed: number?,
	Weight: number?,
	TimeoutSeconds: number?,
}

export type BulkAnimationLoadOptions = {
	PreserveOriginalKey: boolean?,
}

-- Public methods only
export type AnimationController = {
	-- Knit metadata
	Name: "AnimationController",

	-- Animation loading
	LoadAnimation: (
		self: AnimationController,
		animator: Animator,
		animationId: number | string
	) -> AnimationTrack,

	LoadAnimations: (
		self: AnimationController,
		animator: Animator,
		animationIds: { [any]: number | string },
		options: BulkAnimationLoadOptions?
	) -> { [any]: AnimationTrack },

	-- Animation playback
	PlayAnimation: (
		self: AnimationController,
		target: Instance,
		animationId: number | string,
		options: AnimationOptions?
	) -> Promise<AnimationTrack>,

	PlayAnimationTrack: (
		self: AnimationController,
		animationTrack: AnimationTrack,
		animationOptions: AnimationOptions?
	) -> Promise<AnimationTrack>,

	-- Stopping animations
	StopPlayingAnimations: (
		self: AnimationController,
		animator: Animator,
		fadeTime: number?
	) -> { AnimationTrack },

	StopAnimationTrack: (
		self: AnimationController,
		animationTrack: AnimationTrack,
		fadeTime: number?
	) -> AnimationTrack,

	-- Utilities
	GetAnimator: (self: AnimationController, instance: Instance) -> Animator,
}

return {}
