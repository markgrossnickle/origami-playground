--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local MonetizationConfig = require(ReplicatedStorage.Shared.MonetizationConfig)

local PlayerDataService
local AnalyticsService

-- Cache of game pass ownership per player: { [Player]: { [passName]: boolean } }
local gamePassCache: { [Player]: { [string]: boolean } } = {}

-- Reverse lookup: productId -> productName
local devProductIdToName: { [number]: string } = {}
for name, entry in MonetizationConfig.DevProducts do
	if entry.Id > 0 then
		devProductIdToName[entry.Id] = name
	end
end

-- Reverse lookup: gamePassId -> passName
local gamePassIdToName: { [number]: string } = {}
for name, entry in MonetizationConfig.GamePasses do
	if entry.Id > 0 then
		gamePassIdToName[entry.Id] = name
	end
end

--[=[
	@class MonetizationService
	Complete monetization framework: GamePasses, Developer Products, Daily Login Rewards, Premium Benefits.
]=]
local MonetizationService = Knit.CreateService({
	Name = "MonetizationService",
	GamePassPurchased = Signal.new(), -- (player: Player, passName: string)
	PremiumChanged = Signal.new(), -- (player: Player, isPremium: boolean)
	Client = {
		GamePassPurchased = Knit.CreateSignal(), -- (passName: string)
		LoginRewardReady = Knit.CreateSignal(), -- (day: number, reward: DailyReward)
	},
})

-- ============================================================================
-- GamePass Support
-- ============================================================================

function MonetizationService:_cacheGamePasses(player: Player)
	gamePassCache[player] = {}
	for passName, entry in MonetizationConfig.GamePasses do
		if entry.Id > 0 then
			local success, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.Id)
			end)
			if success then
				gamePassCache[player][passName] = owns
			else
				gamePassCache[player][passName] = false
			end
		end
	end
end

function MonetizationService:HasGamePass(player: Player, passName: string): boolean
	local cache = gamePassCache[player]
	if cache and cache[passName] ~= nil then
		return cache[passName]
	end
	-- Fallback: check live
	local entry = MonetizationConfig.GamePasses[passName]
	if not entry or entry.Id == 0 then
		return false
	end
	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.Id)
	end)
	if success then
		if cache then
			cache[passName] = owns
		end
		return owns
	end
	return false
end

function MonetizationService:PromptGamePass(player: Player, passName: string)
	local entry = MonetizationConfig.GamePasses[passName]
	if not entry or entry.Id == 0 then
		warn(`MonetizationService: Unknown game pass "{passName}"`)
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, entry.Id)
end

-- ============================================================================
-- Developer Products
-- ============================================================================

function MonetizationService:PromptProduct(player: Player, productName: string)
	local entry = MonetizationConfig.DevProducts[productName]
	if not entry or entry.Id == 0 then
		warn(`MonetizationService: Unknown dev product "{productName}"`)
		return
	end
	MarketplaceService:PromptProductPurchase(player, entry.Id)
end

function MonetizationService:_handleCoinProduct(player: Player, productName: string): boolean
	local amount = MonetizationConfig.DevProductCoinAmounts[productName]
	if not amount then
		warn(`MonetizationService: No coin amount for product "{productName}"`)
		return false
	end
	-- Apply premium multiplier
	if self:IsPremium(player) then
		amount = math.floor(amount * MonetizationConfig.PremiumMultiplier)
	end
	local currentCoins = PlayerDataService:Read(player, { "Coins" }) or 0
	PlayerDataService:Write(player, { "Coins" }, currentCoins + amount)
	if AnalyticsService then
		AnalyticsService:TrackEconomy(player, "Coins", amount, "Source", `DevProduct_{productName}`)
	end
	return true
end

function MonetizationService:_handleBoostProduct(_player: Player, _productName: string): boolean
	-- Override in your game to grant the boost effect
	return true
end

function MonetizationService:_processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local playerId = receiptInfo.PlayerId
	local receiptId = tostring(receiptInfo.PurchaseId)
	local productId = receiptInfo.ProductId

	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Check for duplicate receipt
	local processedReceipts = PlayerDataService:Read(player, { "ProcessedReceipts" })
	if processedReceipts and processedReceipts[receiptId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Find product handler
	local productName = devProductIdToName[productId]
	if not productName then
		warn(`MonetizationService: No handler for product ID {productId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local entry = MonetizationConfig.DevProducts[productName]
	local handlerName = entry.Handler
	local handler = self[handlerName]
	if not handler then
		warn(`MonetizationService: Handler "{handlerName}" not found`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local success = handler(self, player, productName)
	if not success then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Mark receipt as processed
	local receipts = processedReceipts or {}
	receipts[receiptId] = true
	PlayerDataService:Write(player, { "ProcessedReceipts" }, receipts)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ============================================================================
-- Daily Login Rewards
-- ============================================================================

function MonetizationService:_processLoginReward(player: Player)
	PlayerDataService:WaitForProfile(player)
		:andThen(function()
			local today = os.date("!%Y-%m-%d", os.time())
			local lastLoginDate = PlayerDataService:Read(player, { "LastLoginDate" }) or ""
			local loginStreak = PlayerDataService:Read(player, { "LoginStreak" }) or 0
			local lastClaimed = PlayerDataService:Read(player, { "LastLoginRewardClaimed" })

			-- Already claimed today
			if lastLoginDate == today and lastClaimed then
				return
			end

			-- Calculate streak
			local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
			if lastLoginDate == yesterday then
				loginStreak = loginStreak + 1
			elseif lastLoginDate ~= today then
				loginStreak = 1
			end

			-- Cycle through 7-day rewards
			local dayIndex = ((loginStreak - 1) % #MonetizationConfig.DailyRewards) + 1
			local reward = MonetizationConfig.DailyRewards[dayIndex]

			PlayerDataService:Write(player, { "LoginStreak" }, loginStreak)
			PlayerDataService:Write(player, { "LastLoginDate" }, today)
			PlayerDataService:Write(player, { "LastLoginRewardClaimed" }, false)

			-- Fire signal to client for popup
			self.Client.LoginRewardReady:Fire(player, loginStreak, reward)
		end)
		:catch(function(err)
			warn(`MonetizationService: Login reward error for {player.Name}: {err}`)
		end)
end

function MonetizationService:GetLoginReward(player: Player): { day: number, reward: MonetizationConfig.DailyReward }?
	local loginStreak = PlayerDataService:Read(player, { "LoginStreak" }) or 0
	local lastClaimed = PlayerDataService:Read(player, { "LastLoginRewardClaimed" })
	if loginStreak == 0 then
		return nil
	end
	local dayIndex = ((loginStreak - 1) % #MonetizationConfig.DailyRewards) + 1
	local reward = MonetizationConfig.DailyRewards[dayIndex]
	return { day = loginStreak, reward = reward, claimed = lastClaimed or false }
end

function MonetizationService:ClaimLoginReward(player: Player): boolean
	local lastClaimed = PlayerDataService:Read(player, { "LastLoginRewardClaimed" })
	if lastClaimed then
		return false
	end
	local loginStreak = PlayerDataService:Read(player, { "LoginStreak" }) or 0
	if loginStreak == 0 then
		return false
	end

	local dayIndex = ((loginStreak - 1) % #MonetizationConfig.DailyRewards) + 1
	local reward = MonetizationConfig.DailyRewards[dayIndex]

	-- Grant reward
	if reward.Type == "Currency" and reward.Currency and reward.Amount then
		local current = PlayerDataService:Read(player, { reward.Currency }) or 0
		PlayerDataService:Write(player, { reward.Currency }, current + reward.Amount)
		if AnalyticsService then
			AnalyticsService:TrackEconomy(
				player,
				reward.Currency,
				reward.Amount,
				"Source",
				`DailyReward_Day{loginStreak}`
			)
		end
	end

	PlayerDataService:Write(player, { "LastLoginRewardClaimed" }, true)
	return true
end

-- ============================================================================
-- Premium Benefits
-- ============================================================================

function MonetizationService:IsPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

function MonetizationService:GetPremiumMultiplier(): number
	return MonetizationConfig.PremiumMultiplier
end

-- ============================================================================
-- Client API
-- ============================================================================

function MonetizationService.Client:HasGamePass(player: Player, passName: string): boolean
	return self.Server:HasGamePass(player, passName)
end

function MonetizationService.Client:GetLoginReward(player: Player)
	return self.Server:GetLoginReward(player)
end

function MonetizationService.Client:ClaimLoginReward(player: Player): boolean
	return self.Server:ClaimLoginReward(player)
end

function MonetizationService.Client:IsPremium(player: Player): boolean
	return self.Server:IsPremium(player)
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

function MonetizationService:KnitInit()
	PlayerDataService = Knit.GetService("PlayerDataService")
	AnalyticsService = Knit.GetService("AnalyticsService")

	-- Register receipt processor
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		return self:_processReceipt(receiptInfo)
	end

	-- Listen for game pass purchases mid-session
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
		if not purchased then
			return
		end
		local passName = gamePassIdToName[gamePassId]
		if passName and gamePassCache[player] then
			gamePassCache[player][passName] = true
		end
		if passName then
			self.GamePassPurchased:Fire(player, passName)
			self.Client.GamePassPurchased:Fire(player, passName)
		end
	end)

	-- Listen for premium status changes
	Players.PlayerMembershipChanged:Connect(function(player)
		local isPremium = self:IsPremium(player)
		self.PremiumChanged:Fire(player, isPremium)
	end)

	-- Player setup
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:_cacheGamePasses(player)
		end)
		task.spawn(function()
			self:_processLoginReward(player)
		end)
	end)

	-- Player cleanup
	Players.PlayerRemoving:Connect(function(player)
		gamePassCache[player] = nil
	end)
end

function MonetizationService:KnitStart()
	-- Handle players that joined before KnitInit connected
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_cacheGamePasses(player)
		end)
		task.spawn(function()
			self:_processLoginReward(player)
		end)
	end
end

return MonetizationService
