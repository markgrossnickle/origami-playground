--!strict
--[=[
	@class ModelLinkController

	Client UI for the bring-your-own-model (BYOM) feature:
	  - a "Link your AI model" panel that requests a one-time code from the
	    server and shows the player the CODE + the linking website URL;
	  - a simple demo "Ask AI" box that sends a prompt to the player's linked
	    model (via the server proxy) and displays the text-filtered response.

	Cross-platform per CLAUDE.md: responsive sizing, `.Activated` signals,
	UDim2.fromScale containers, mobile/console-aware text sizes.
]=]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Player = Knit.Player
local PlayerGui = Player:WaitForChild("PlayerGui")

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()

local ModelLinkController = Knit.CreateController({
	Name = "ModelLinkController",
})

ModelLinkController._trove = Trove.new()
ModelLinkController._gui = nil :: ScreenGui?
ModelLinkController._service = nil :: any

-- ============================================================================
-- Responsive helpers
-- ============================================================================

local function fontBody(): number
	if IS_CONSOLE then
		return 20
	elseif IS_MOBILE then
		return 16
	end
	return 14
end

local function fontHeading(): number
	if IS_CONSOLE then
		return 24
	elseif IS_MOBILE then
		return 18
	end
	return 16
end

local function buttonHeight(): number
	if IS_CONSOLE then
		return 52
	elseif IS_MOBILE then
		return 44
	end
	return 38
end

local function make<T>(className: string, props: { [string]: any }): T
	local inst = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst :: any
end

-- ============================================================================
-- Panel
-- ============================================================================

function ModelLinkController:_setStatus(label: TextLabel, text: string, isError: boolean)
	label.Text = text
	label.TextColor3 = isError and Color3.fromRGB(255, 150, 150) or Color3.fromRGB(180, 230, 190)
end

function ModelLinkController:_buildPanel()
	if self._gui then
		self._gui:Destroy()
	end
	self._trove:Clean()

	local gui = make("ScreenGui", {
		Name = "ModelLinkGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = PlayerGui,
	})
	self._gui = gui
	self._trove:Add(gui)

	local panel = make("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		-- Mobile: ~92% width; desktop: capped narrower.
		Size = if IS_MOBILE then UDim2.fromScale(0.92, 0.8) else UDim2.fromScale(0.45, 0.7),
		BackgroundColor3 = Color3.fromRGB(26, 29, 39),
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 14), Parent = panel })
	make("UIPadding", {
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
		Parent = panel,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})

	make("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, fontHeading() + 10),
		BackgroundTransparency = 1,
		Text = "Link your AI model",
		Font = Enum.Font.GothamBold,
		TextSize = fontHeading(),
		TextColor3 = Color3.fromRGB(235, 238, 245),
		LayoutOrder = 1,
		Parent = panel,
	})

	make("TextLabel", {
		Name = "Blurb",
		Size = UDim2.new(1, 0, 0, fontBody() * 4),
		BackgroundTransparency = 1,
		Text = "Connect your own AI provider key to unlock AI NPC chat. "
			.. "Tap below to get a one-time code, then enter it on the website.",
		Font = Enum.Font.Gotham,
		TextSize = fontBody(),
		TextColor3 = Color3.fromRGB(170, 176, 188),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
		Parent = panel,
	})

	local getCodeBtn = make("TextButton", {
		Name = "GetCodeButton",
		Size = UDim2.new(1, 0, 0, buttonHeight()),
		BackgroundColor3 = Color3.fromRGB(108, 140, 255),
		Text = "Get my link code",
		Font = Enum.Font.GothamBold,
		TextSize = fontBody() + 1,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = true,
		LayoutOrder = 3,
		Parent = panel,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 9), Parent = getCodeBtn })

	local codeLabel = make("TextLabel", {
		Name = "CodeLabel",
		Size = UDim2.new(1, 0, 0, fontHeading() * 3),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = fontHeading(),
		TextColor3 = Color3.fromRGB(235, 238, 245),
		TextWrapped = true,
		RichText = true,
		LayoutOrder = 4,
		Parent = panel,
	})

	-- Demo "Ask AI" section.
	local askBox = make("TextBox", {
		Name = "AskBox",
		Size = UDim2.new(1, 0, 0, buttonHeight()),
		BackgroundColor3 = Color3.fromRGB(17, 20, 27),
		Text = "",
		PlaceholderText = "Ask the shopkeeper something...",
		Font = Enum.Font.Gotham,
		TextSize = fontBody(),
		TextColor3 = Color3.fromRGB(235, 238, 245),
		ClearTextOnFocus = false,
		LayoutOrder = 5,
		Parent = panel,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 9), Parent = askBox })

	local askBtn = make("TextButton", {
		Name = "AskButton",
		Size = UDim2.new(1, 0, 0, buttonHeight()),
		BackgroundColor3 = Color3.fromRGB(70, 90, 160),
		Text = "Ask AI",
		Font = Enum.Font.GothamBold,
		TextSize = fontBody() + 1,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = true,
		LayoutOrder = 6,
		Parent = panel,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 9), Parent = askBtn })

	local statusLabel = make("TextLabel", {
		Name = "Status",
		Size = UDim2.new(1, 0, 0, fontBody() * 4),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.Gotham,
		TextSize = fontBody(),
		TextColor3 = Color3.fromRGB(180, 230, 190),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 7,
		Parent = panel,
	})

	local closeBtn = make("TextButton", {
		Name = "CloseButton",
		Size = UDim2.new(1, 0, 0, buttonHeight()),
		BackgroundColor3 = Color3.fromRGB(60, 64, 75),
		Text = "Close",
		Font = Enum.Font.Gotham,
		TextSize = fontBody(),
		TextColor3 = Color3.fromRGB(230, 233, 240),
		AutoButtonColor = true,
		LayoutOrder = 8,
		Parent = panel,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 9), Parent = closeBtn })

	-- Floating open button (always reachable).
	local openBtn = make("TextButton", {
		Name = "OpenButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 80),
		Size = UDim2.fromOffset(buttonHeight() * 3.2, buttonHeight()),
		BackgroundColor3 = Color3.fromRGB(108, 140, 255),
		Text = "🤖 AI Model",
		Font = Enum.Font.GothamBold,
		TextSize = fontBody(),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = true,
		Parent = gui,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 9), Parent = openBtn })

	-- Wiring (always use .Activated for cross-platform).
	self._trove:Connect(openBtn.Activated, function()
		panel.Visible = true
	end)
	self._trove:Connect(closeBtn.Activated, function()
		panel.Visible = false
	end)

	self._trove:Connect(getCodeBtn.Activated, function()
		self:_setStatus(statusLabel, "Requesting code...", false)
		task.spawn(function()
			self._service
				:GetLinkCode()
				:andThen(function(result)
					if result.success then
						codeLabel.Text = string.format(
							"Your code: <b>%s</b>\nGo to <b>%s</b> and enter it.",
							tostring(result.code),
							tostring(result.url)
						)
						self:_setStatus(statusLabel, "Code ready — it expires soon.", false)
					else
						self:_setStatus(statusLabel, "Could not get a code: " .. tostring(result.error), true)
					end
				end)
				:catch(function(err)
					self:_setStatus(statusLabel, "Request failed: " .. tostring(err), true)
				end)
		end)
	end)

	self._trove:Connect(askBtn.Activated, function()
		local prompt = askBox.Text
		if prompt == "" then
			self:_setStatus(statusLabel, "Type a question first.", true)
			return
		end
		self:_setStatus(statusLabel, "Asking your model...", false)
		task.spawn(function()
			self._service
				:AskModel(prompt)
				:andThen(function(result)
					if result.success then
						self:_setStatus(statusLabel, "🛒 " .. tostring(result.text), false)
					elseif result.error == "subscription_required" then
						self:_setStatus(statusLabel, "This feature needs the AI Model subscription.", true)
					elseif result.error == "not_linked" then
						self:_setStatus(statusLabel, "Link a model first (Get my link code).", true)
					else
						self:_setStatus(statusLabel, "Error: " .. tostring(result.error), true)
					end
				end)
				:catch(function(err)
					self:_setStatus(statusLabel, "Request failed: " .. tostring(err), true)
				end)
		end)
	end)
end

function ModelLinkController:KnitStart()
	self._service = Knit.GetService("ModelLinkService")
	self:_buildPanel()
end

return ModelLinkController
