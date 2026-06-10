--!strict
--[=[
	@class ModelLinkController

	Client UI for the bring-your-own-model (BYOM) feature:
	  - a "Link your AI model" panel that requests a one-time code from the
	    server and shows the player the CODE + the linking website URL. The
	    player opens the site in a browser, enters the code, and either signs in
	    with ChatGPT (OpenAI) or pastes a Claude API key;
	  - a live link-status row showing whether a model is linked and which
	    provider (refreshes on open, after requesting a code, and on demand);
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

local ModelLinkConfig = require(ReplicatedStorage.Shared.ModelLinkConfig)

local Player = Knit.Player
local PlayerGui = Player:WaitForChild("PlayerGui")

local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()

-- After requesting a code, poll link status so the panel flips to "Linked" once
-- the player finishes on the website, without them re-opening the panel.
local STATUS_POLL_INTERVAL = 4
local STATUS_POLL_DURATION = 90

local ModelLinkController = Knit.CreateController({
	Name = "ModelLinkController",
})

ModelLinkController._trove = Trove.new()
ModelLinkController._gui = nil :: ScreenGui?
ModelLinkController._service = nil :: any
ModelLinkController._pollToken = 0

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

-- Render the current link state into the dedicated link-status row.
function ModelLinkController:_renderLinkState(label: TextLabel, state: { [string]: any })
	if not state.success then
		label.Text = "Link status: unavailable"
		label.TextColor3 = Color3.fromRGB(200, 170, 120)
		return
	end
	if state.linked then
		local provider = ModelLinkConfig.ProviderLabel(state.provider)
		local modelSuffix = (state.model ~= nil and state.model ~= "") and (" · " .. tostring(state.model)) or ""
		label.Text = "Linked ✓  " .. provider .. modelSuffix
		label.TextColor3 = Color3.fromRGB(150, 220, 165)
	else
		label.Text = "Not linked yet"
		label.TextColor3 = Color3.fromRGB(200, 170, 120)
	end
end

-- Fetch link status once and render it. Returns the resolved state table.
function ModelLinkController:_refreshLinkState(label: TextLabel)
	label.Text = "Checking link status..."
	label.TextColor3 = Color3.fromRGB(170, 176, 188)
	self._service
		:IsLinked()
		:andThen(function(state)
			self:_renderLinkState(label, state)
		end)
		:catch(function()
			label.Text = "Link status: unavailable"
			label.TextColor3 = Color3.fromRGB(200, 170, 120)
		end)
end

-- Poll link status for a while after a code is issued so the panel updates as
-- soon as the player finishes linking on the website. Cancels any prior poll.
function ModelLinkController:_startStatusPoll(label: TextLabel)
	self._pollToken += 1
	local token = self._pollToken
	task.spawn(function()
		local elapsed = 0
		while elapsed < STATUS_POLL_DURATION and token == self._pollToken do
			task.wait(STATUS_POLL_INTERVAL)
			elapsed += STATUS_POLL_INTERVAL
			if token ~= self._pollToken then
				return
			end
			local ok, state = self._service:IsLinked():await()
			if ok and token == self._pollToken then
				self:_renderLinkState(label, state)
				if state.success and state.linked then
					return
				end
			end
		end
	end)
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
		Size = if IS_MOBILE then UDim2.fromScale(0.92, 0.85) else UDim2.fromScale(0.45, 0.72),
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
		Text = "Connect your own AI to unlock AI NPC chat — Sign in with ChatGPT, or "
			.. "paste a Claude API key. Tap below for a one-time code, then enter it on the website.",
		Font = Enum.Font.Gotham,
		TextSize = fontBody(),
		TextColor3 = Color3.fromRGB(170, 176, 188),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 2,
		Parent = panel,
	})

	-- Live link-status row.
	local linkStateLabel = make("TextLabel", {
		Name = "LinkState",
		Size = UDim2.new(1, 0, 0, fontBody() * 2),
		BackgroundColor3 = Color3.fromRGB(17, 20, 27),
		BackgroundTransparency = 0.35,
		Text = "Checking link status...",
		Font = Enum.Font.GothamMedium,
		TextSize = fontBody(),
		TextColor3 = Color3.fromRGB(170, 176, 188),
		TextWrapped = true,
		LayoutOrder = 3,
		Parent = panel,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 8), Parent = linkStateLabel })

	local getCodeBtn = make("TextButton", {
		Name = "GetCodeButton",
		Size = UDim2.new(1, 0, 0, buttonHeight()),
		BackgroundColor3 = Color3.fromRGB(108, 140, 255),
		Text = "Get my link code",
		Font = Enum.Font.GothamBold,
		TextSize = fontBody() + 1,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = true,
		LayoutOrder = 4,
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
		LayoutOrder = 5,
		Parent = panel,
	})

	local refreshBtn = make("TextButton", {
		Name = "RefreshButton",
		Size = UDim2.new(1, 0, 0, buttonHeight()),
		BackgroundColor3 = Color3.fromRGB(60, 64, 75),
		Text = "Check link status",
		Font = Enum.Font.Gotham,
		TextSize = fontBody(),
		TextColor3 = Color3.fromRGB(230, 233, 240),
		AutoButtonColor = true,
		LayoutOrder = 6,
		Parent = panel,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 9), Parent = refreshBtn })

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
		LayoutOrder = 7,
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
		LayoutOrder = 8,
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
		LayoutOrder = 9,
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
		LayoutOrder = 10,
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
		self:_refreshLinkState(linkStateLabel)
	end)
	self._trove:Connect(closeBtn.Activated, function()
		panel.Visible = false
		-- Stop any in-flight status poll when the panel closes.
		self._pollToken += 1
	end)

	self._trove:Connect(refreshBtn.Activated, function()
		self:_refreshLinkState(linkStateLabel)
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
						self:_setStatus(
							statusLabel,
							"Code ready — it expires soon. Waiting for you to link...",
							false
						)
						-- Poll so the status row flips to "Linked" automatically.
						self:_startStatusPoll(linkStateLabel)
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
						self:_setStatus(statusLabel, "Link a model first — tap “Get my link code”.", true)
						self:_refreshLinkState(linkStateLabel)
					elseif result.error == "rate_limited" or result.error == "cooldown" then
						self:_setStatus(statusLabel, "Slow down a moment, then try again.", true)
					else
						local msg = result.message or result.error
						self:_setStatus(statusLabel, "Error: " .. tostring(msg), true)
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
