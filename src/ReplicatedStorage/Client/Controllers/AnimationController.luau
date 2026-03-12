--!strict
-- Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Packages
local Packages = ReplicatedStorage.Packages
local Knit = require(Packages.Knit)
local Promise = require(Packages.Promise)

-- Constants
local CONTENT_ID_PREFIX = "rbxassetid://"
local CONTENT_ID_TEMPLATE = CONTENT_ID_PREFIX .. "%s"
local DEFAULT_ANIMATION_LOAD_TIMEOUT_SECONDS = 5

-- Types
local Types = ReplicatedStorage.Shared.Types
local AnimationControllerTypes = require(Types.Controllers.AnimationControllerTypes)
type AnimationOptions = AnimationControllerTypes.AnimationOptions
type BulkAnimationLoadOptions = AnimationControllerTypes.BulkAnimationLoadOptions

local PromiseTypes = require(Types.PromiseTypes)
type Promise<T> = PromiseTypes.Promise<T>

-- Cache: per-animator, keyed by animation asset ID
local CachedAnimationTracks: { [Animator]: { [string]: AnimationTrack } } = {}
local AnimatorCleanupConnections: { [Animator]: RBXScriptConnection } = {}

local function ensureAnimatorCleanup(animator: Animator)
	if AnimatorCleanupConnections[animator] then
		return
	end
	AnimatorCleanupConnections[animator] = animator.Destroying:Connect(function()
		CachedAnimationTracks[animator] = nil
		AnimatorCleanupConnections[animator] = nil
	end)
end

local AnimationController = Knit.CreateController({
	Name = "AnimationController",
}) :: AnimationControllerTypes.AnimationController

local function createAnimationLoadedPromise(animationTrack: AnimationTrack, timeoutSeconds: number?)
	if animationTrack.Length > 0 then
		return Promise.resolve(animationTrack)
	end
	local timeout = timeoutSeconds or DEFAULT_ANIMATION_LOAD_TIMEOUT_SECONDS
	return Promise.fromEvent(animationTrack:GetPropertyChangedSignal("Length"), function()
		return animationTrack.Length > 0
	end)
		:timeout(
			timeout,
			string.format("Timed out waiting for animation %s to load after %.2f seconds", animationTrack.Name, timeout)
		)
		:andThen(function()
			return animationTrack
		end)
end

function AnimationController:LoadAnimations(
	animator: Animator,
	animationIds: { [any]: number | string },
	options: BulkAnimationLoadOptions?
): { [any]: AnimationTrack }
	local preserveOriginalKey = options and options.PreserveOriginalKey or false
	local loadedAnimationTracks = {}
	for originalKey: any, animationId: number | string in pairs(animationIds) do
		local trackKey = if preserveOriginalKey then originalKey else tostring(animationId)
		loadedAnimationTracks[trackKey] = self:LoadAnimation(animator, animationId)
	end
	return loadedAnimationTracks
end

function AnimationController:LoadAnimation(animator: Animator, animationId: number | string): AnimationTrack
	local animationKey = type(animationId) == "string" and string.gsub(animationId, CONTENT_ID_PREFIX, "")
		or tostring(animationId)

	local animatorCache = CachedAnimationTracks[animator]
	if animatorCache and animatorCache[animationKey] then
		return animatorCache[animationKey]
	end

	local success, result = pcall(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = CONTENT_ID_TEMPLATE:format(animationKey)
		local animationTrack = animator:LoadAnimation(animation)
		animation:Destroy()
		return animationTrack
	end)
	assert(success, `Failed to load animation with id: {animationId}. {animator:GetFullName()}\nReason: {result}`)

	if not CachedAnimationTracks[animator] then
		CachedAnimationTracks[animator] = {}
	end
	CachedAnimationTracks[animator][animationKey] = result

	ensureAnimatorCleanup(animator)

	return result
end

function AnimationController:PlayAnimation(
	target: Instance,
	animationId: number | string,
	options: AnimationOptions?
): Promise<AnimationTrack>
	local animator = self:GetAnimator(target)
	local animationTrack: AnimationTrack = self:LoadAnimation(animator, animationId)
	return self:PlayAnimationTrack(animationTrack, options)
end

function AnimationController:PlayAnimationTrack(
	animationTrack: AnimationTrack,
	animationOptions: AnimationOptions?
): Promise<AnimationTrack>
	animationTrack.Looped = animationOptions and animationOptions.Looped or false
	return createAnimationLoadedPromise(animationTrack, animationOptions and animationOptions.TimeoutSeconds):andThen(
		function()
			animationTrack:Play(
				animationOptions and animationOptions.BlendTime,
				animationOptions and animationOptions.Weight,
				animationOptions and animationOptions.Speed
			)
			return animationTrack
		end
	)
end

function AnimationController:StopPlayingAnimations(animator: Animator, fadeTime: number?): { AnimationTrack }
	local stoppedAnimations = {}
	for _, animationTrack in animator:GetPlayingAnimationTracks() do
		table.insert(stoppedAnimations, self:StopAnimationTrack(animationTrack, fadeTime))
	end
	return stoppedAnimations
end

function AnimationController:StopAnimationTrack(animationTrack: AnimationTrack, fadeTime: number?): AnimationTrack
	animationTrack:Stop(fadeTime)
	return animationTrack
end

function AnimationController:GetAnimator(instance: Instance): Animator
	local humanoid: Humanoid? = instance:FindFirstChildOfClass("Humanoid")
	local animator: Animator? = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	local animationController: AnimationController? = instance:FindFirstChildOfClass("AnimationController")
	if not animationController then
		local temp: AnimationController = Instance.new("AnimationController")
		temp.Parent = instance
		animationController = temp
	end
	animator = (animationController :: AnimationController):FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	local newAnimator: Animator = Instance.new("Animator")
	newAnimator.Parent = animationController
	return newAnimator
end

function AnimationController:KnitStart() end

function AnimationController:KnitInit() end

return AnimationController
