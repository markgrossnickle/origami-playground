-- Roblox Services
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Packages
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local InputController = Knit.CreateController({
	Name = "InputController",
	InputStateChanged = Signal.new(),
	InputState = {},
})

function InputController:_onRegisteredInputChanged(actionName: string, inputState: Enum.UserInputState)
	self.InputState[actionName] = if inputState == Enum.UserInputState.Begin then true else false
	self.InputStateChanged:Fire(actionName)
end

function InputController:JumpRequest(callback: () -> ()): RBXScriptConnection
	return UserInputService.JumpRequest:Connect(callback)
end

function InputController:RegisterInput(
	name: string,
	callback: (inputState: Enum.UserInputState) -> (),
	createMobileButton: boolean,
	inputSources: { Enum.KeyCode },
	priority: number?,
	overrideExistingMapping: boolean?
): boolean
	ContextActionService:BindActionAtPriority(
		name,
		function(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
			if callback then
				callback(inputState)
			end
			self:_onRegisteredInputChanged(actionName, inputState)
			if overrideExistingMapping then
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		createMobileButton,
		priority or math.huge,
		table.unpack(inputSources)
	)
	local currentInputState = false
	for _, inputSource in inputSources do
		if UserInputService:IsKeyDown(inputSource) then
			currentInputState = true
			self.InputState[name] = currentInputState
			break
		end
	end
	return currentInputState
end

function InputController:UnregisterInput(name: string)
	ContextActionService:UnbindAction(name)
	self.InputState[name] = nil
end

function InputController:KnitInit() end

function InputController:KnitStart() end

return InputController
