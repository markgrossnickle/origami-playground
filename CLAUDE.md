# CLAUDE.md - Roblox Project Template

This is the starter template for all MindTrust Roblox projects. It uses the Knit framework for service-oriented architecture.

## Project Structure

```
src/
  ReplicatedStorage/
    Client/                    # Client-side entry point and initialization
      ClientEntry.server.luau  # Entry script (RunContext: Client via metadata)
      init.luau                # Client bootstrap — waits for server, loads controllers/components
      Controllers/             # Knit controllers (client-side singletons)
      Components/              # Client-only components
    Shared/                    # Code shared between server and client
      Components/              # Shared components (loaded by both sides)
      Enums/                   # Enum definitions
      Environment.luau         # Maps game IDs to environments (Studio/Dev/Staging/Review/Production)
      CmdrHelper.luau          # Cmdr permission checks and registration helper
      GameVersion.luau         # Reads version from GameVersion.txt
      MonetizationConfig.luau  # GamePass/DevProduct IDs, daily rewards, premium config
      ShopConfig.luau          # Shop items, currencies, categories
      GameConfig.luau          # Runtime-tunable game constants
    Packages/                  # Wally shared packages (gitignored, auto-installed)
  ServerScriptService/
    Server/
      Main.server.luau         # Server entry point — calls Server:Main()
      init.luau                # Server bootstrap — loads services, then components
      Services/                # Knit services (server-side singletons)
      Components/              # Server-only components
    ServerPackages/            # Wally server packages (gitignored, auto-installed)
```

## Knit Framework

We always use the **Knit** framework (sleitnick/knit@1.7.0). Knit provides a service-oriented architecture with clear client/server separation.

### Services (Server Side)

Services are server-side singletons created with `Knit.CreateService`. They live in `src/ServerScriptService/Server/Services/`.

```lua
local MyService = Knit.CreateService({
    Name = "MyService",
    Client = {},  -- Table for methods/signals exposed to clients
})

function MyService:KnitInit()
    -- Called first. Safe to reference other services, but do NOT call their methods yet.
end

function MyService:KnitStart()
    -- Called after ALL KnitInit methods finish. Safe to use other services fully.
end
```

All services are loaded via `Knit.AddServices(script.Services)` in the server bootstrap.

### Controllers (Client Side)

Controllers are client-side singletons created with `Knit.CreateController`. They live in `src/ReplicatedStorage/Client/Controllers/`.

```lua
local MyController = Knit.CreateController({
    Name = "MyController",
})

function MyController:KnitInit()
    -- Same rules as services: reference only, don't call methods on other controllers.
end

function MyController:KnitStart()
    -- Safe to use other controllers and call server services.
    local MyService = Knit.GetService("MyService")
end
```

All controllers are loaded via `Knit.AddControllers(script.Controllers)` in the client bootstrap.

### Components (Both Sides)

Components use the Component library (sleitnick/component@2.4.8) to bind behavior to instances via CollectionService tags. They work on **both server and client**.

- **Server components:** `src/ServerScriptService/Server/Components/`
- **Client components:** `src/ReplicatedStorage/Client/Components/` (or inside a Controller's Components folder)
- **Shared components:** `src/ReplicatedStorage/Shared/Components/`

Component modules must have names ending in `Component` (e.g., `HealthComponent.luau`). The bootstrap code auto-discovers them by checking `instance.Name:sub(#instance.Name - 8) == "Component"`.

```lua
local Component = require(ReplicatedStorage.Packages.Component)

local HealthComponent = Component.new({
    Tag = "Health",
    Ancestors = { workspace },
})

function HealthComponent:Construct()
    -- Initialize state. self.Instance is the tagged Roblox instance.
end

function HealthComponent:Start()
    -- Component is active. Safe to get sibling components.
end

function HealthComponent:Stop()
    -- Cleanup when tag is removed or instance leaves ancestors.
end
```

Components are loaded **after** Knit starts (via Promise chain in both server and client bootstrap).

### The Player Parameter in Knit

This is critical to understand. The `player` argument is handled differently depending on which side initiates the call:

**Client-to-server calls — `player` is auto-injected:**
When a client calls a method on a service's `Client` table, Knit automatically passes the calling player as the first argument on the server side. The client does NOT pass `player`.

```lua
-- SERVER: define with `player` as first param
function MyService.Client:GetData(player)
    return self.Server:_getData(player)  -- self.Server refers to the service root
end

-- CLIENT: call WITHOUT `player` — Knit injects it
local MyService = Knit.GetService("MyService")
MyService:GetData()  -- player is NOT passed here
```

**Client-to-server signals — `player` is auto-injected:**
```lua
-- SERVER: listener receives `player` automatically
self.Client.SomeSignal:Connect(function(player, data)
    -- player is the client who fired
end)

-- CLIENT: fires WITHOUT `player`
MyService.SomeSignal:Fire(data)
```

**Server-to-client signals — `player` must be passed explicitly:**
```lua
-- SERVER: must specify which player to send to
self.Client.PointsChanged:Fire(player, newPoints)

-- CLIENT: receives only the data, no player
MyService.PointsChanged:Connect(function(newPoints) end)
```

**Internal service methods — no auto-injection:**
Regular methods on the service (not on `Client`) are normal Lua methods. You pass `player` explicitly when needed.

```lua
function MyService:_getData(player)
    return self.data[player]  -- caller must pass player
end
```

**Summary:**
| Direction | `player` auto-injected? | Who passes it? |
|---|---|---|
| Client calls `Service.Client:Method(player, ...)` | Yes | Knit injects it |
| Client fires `Service.Client.Signal` | Yes | Knit injects it |
| Server fires `self.Client.Signal:Fire(player, ...)` | No | You pass it explicitly |
| Server calls internal `Service:Method(player, ...)` | No | You pass it explicitly |

### Knit `self.Server` and `self.Client` References

Inside a `Client` method, `self.Server` refers back to the root service table — use it to delegate to internal service logic. From the service root, `self.Client` refers to the Client table — use it to fire signals or set properties for clients.

## Promise Handling (IMPORTANT)

Knit service methods called from the client return **Promises**, not direct values. You MUST handle them.

### Rules
- **Always await or chain** service method return values: use `:andThen()`, `:await()`, or `:expect()`
- **Never assign a Promise to a variable** expecting a plain value (e.g., `local data = Service:GetData()` is WRONG — use `local ok, data = Service:GetData():await()`)
- **Fire-and-forget** is acceptable ONLY for void methods (signals, events). If the method returns data or can fail, handle the promise
- **Chain `:catch()`** with `:andThen()` to handle errors — never silently drop promise rejections
- **Wrap in `task.spawn()`** when calling promise-returning methods inside event connections where you don't want to block

### Correct Patterns
```lua
-- Blocking await (returns success, value)
local ok, data = MyService:GetData():await()

-- Promise chaining
MyService:DoThing():andThen(function(result)
    -- handle result
end):catch(function(err)
    warn("Failed:", err)
end)

-- Synchronous extraction (throws on failure)
local profile = PlayerDataService:WaitForProfile(player):expect()

-- Fire-and-forget in event connection (wrap in task.spawn)
Players.PlayerAdded:Connect(function(player)
    task.spawn(function()
        PlayerDataService:WaitForProfile(player)
            :andThen(function() --[[ ... ]] end)
            :catch(function(err) warn(err) end)
    end)
end)
```

### Server-Side vs Client-Side Read Calls (CRITICAL)

`PlayerDataService:Read()` behaves **differently** depending on which side you call it from:

**Server-side (inside services):** Returns the value **directly** — NOT a Promise. Do NOT call `:await()`.
```lua
-- CORRECT (server)
local coins = PlayerDataService:Read(player, { "Coins" }) or 0

-- WRONG (server) — Read() is not a Promise, :await() will error
local ok, coins = PlayerDataService:Read(player, { "Coins" }):await()
```

**Client-side (inside controllers):** Goes through Knit's client proxy, which wraps it in a Promise. Use `:await()`.
```lua
-- CORRECT (client)
local ok, data = PlayerDataService:Read():await()
```

### Anti-Patterns (DO NOT DO)
```lua
-- BAD: Assigns Promise object to variable instead of awaited value
local modes = TeamService:GetGameModes()

-- BAD: Ignores returned Promise from method that can fail
PlayerBadgeService:AwardBadge(player, badgeName)

-- BAD: No error handling on chain
MyService:RiskyOperation():andThen(function() end)  -- missing :catch()

-- BAD: Calling :await() on server-side Read (not a Promise!)
local ok, val = PlayerDataService:Read(player, { "Key" }):await()
```

## Startup Flow

1. **Server:** `Main.server.luau` → `Server:Main()` → `Knit.AddServices()` → `Knit:Start()` → load server components → load shared components → set `ServerStatus = "Started"`
2. **Client:** `ClientEntry.server.luau` (RunContext: Client) → waits for `ServerStatus == "Started"` → `Knit.AddControllers()` → `Knit:Start()` → load client components → load shared components

If the server crashes during startup, clients are kicked with an error message.

## Toolchain

| Tool | Version | Purpose |
|---|---|---|
| Rojo | 7.6.1 | Syncs code to Roblox Studio (port 34872) |
| Wally | 0.3.2 | Package manager |
| StyLua | 2.3.0 | Code formatter |
| Selene | 0.29.0 | Linter |
| wally-package-types | 1.6.2 | Fixes Luau types for Wally packages |
| Lune | 0.8.9 | Luau runtime for tests outside Studio |

Managed via **aftman** (`aftman.toml`).

## Code Style

- **Language:** Luau (strict mode preferred: `--!strict`)
- **Formatter:** StyLua — tabs (width 4), 120 column width, double quotes, Unix line endings
- **Linter:** Selene with `roblox` standard (excludes `Packages/*` and `ServerPackages/*`)
- **Quote style:** Double quotes preferred
- **Call parentheses:** Always use parentheses

## Dependencies (wally.toml)

**Shared:** Knit 1.7.0, Promise 4.0.0, TableUtil 1.2.1, Signal 2.0.3, Component 2.4.8, Logging 0.3.0, Trove 1.5.1
**Server-only:** ProfileStore 1.0.3, Cmdr 1.12.0

## Development Commands

```bash
aftman install              # Install toolchain
wally install               # Install packages (or: make wally-install)
make wally-package-types    # Fix Luau types for Wally packages
rojo serve                  # Start Rojo sync server (port 34872)
stylua .                    # Format code
selene .                    # Lint code
make test                  # Run unit tests
lune run tests/runner      # Run tests directly
```

## Environment System

`Environment.luau` maps `game.GameId` to an environment enum. Update the `GameIds` table with real game IDs when forking this template. Studio is always detected automatically. Default for unknown IDs is `Production`.

## Cmdr (Admin Commands)

Cmdr is available in Studio always, in non-production environments always, and in Production/Review only for group members with rank >= 252 (GROUP_ID: 361311171). Activation key: F2. Custom commands go in a `Commands/` folder under your service or controller.

## Cross-Platform (IMPORTANT)

All games must work on **mobile (phone/tablet), PC, Xbox, and console** from the start. Do not treat mobile as an afterthought.

### UI
- Use `UDim2.fromScale()` for positioning/sizing — never hardcode pixel offsets that break on different screen sizes
- Minimum touch target size: **48x48 pixels** for all interactive buttons
- Check `UserInputService.TouchEnabled` to detect mobile and adapt UI layout (e.g., larger buttons, stacked layouts)
- Use `GuiService:IsTenFootInterface()` to detect console/TV and increase text sizes
- Use `Activated` signal on buttons (not `MouseButton1Click`) — it works on all platforms

### Controls
- Always support **WASD + mouse** (PC), **thumbstick + touch** (mobile), and **gamepad** (Xbox/controller)
- Register mobile touch buttons via `ContextActionService:BindAction()` with `createTouchButton = true`
- For gamepad: support D-pad navigation in menus, A/B for confirm/cancel, bumpers for tab switching
- Never rely on hover states — they don't exist on touch or gamepad

### Performance
- On mobile (`TouchEnabled = true`), reduce:
  - Particle emission rates (50% reduction)
  - Max concurrent entities/effects
  - Trail lifetimes
  - Decorative Part counts
- Test that the game runs at 30+ FPS on mobile devices

### Camera
- Ensure your camera setup works with touch drag (if custom camera)
- On mobile, consider slightly more zoomed-out camera for awareness on smaller screens

## Built-in Services & Controllers

### MonetizationService (Server)

`src/ServerScriptService/Server/Services/MonetizationService/init.luau`

Complete monetization framework. Configure in `src/ReplicatedStorage/Shared/MonetizationConfig.luau`.

**GamePasses:** Update `GamePasses` table with real IDs. Ownership is cached on join.
```lua
-- Server
MonetizationService:HasGamePass(player, "VIP") --> boolean
MonetizationService:PromptGamePass(player, "VIP")
MonetizationService.GamePassPurchased:Connect(function(player, passName) end)
```

**Developer Products:** Update `DevProducts` table with IDs. `ProcessReceipt` is registered automatically. Receipts are deduplicated via ProfileStore. Add custom handlers as methods on MonetizationService named in the `Handler` field.

**Daily Login Rewards:** 7-day reward cycle in `DailyRewards` table. Streak tracked in PlayerData. `LoginRewardReady` signal fires to client on join. `ClaimLoginReward` grants the reward.

**Premium:** `IsPremium(player)` checks membership. `PremiumMultiplier` (default 1.5x) applied to coin products and ShopService earnings. `PremiumChanged` signal fires mid-session.

**Client API:** `HasGamePass`, `GetLoginReward`, `ClaimLoginReward`, `IsPremium`, `GamePassPurchased` signal, `LoginRewardReady` signal.

### AnalyticsService (Server)

`src/ServerScriptService/Server/Services/AnalyticsService/init.luau`

Lightweight analytics using Roblox's built-in AnalyticsService (no external dependencies).

```lua
-- Generic events
AnalyticsService:TrackEvent(player, "Category", "Action", "label", numericValue)
AnalyticsService:TrackFunnel(player, "OnboardingFunnel", 1, "StartedTutorial")
AnalyticsService:TrackEconomy(player, "Coins", 100, "Source", "QuestReward")

-- Pre-built helpers
AnalyticsService:LevelUp(player, 5)
AnalyticsService:ItemPurchased(player, "sword", "Coins", 200)
AnalyticsService:StageCompleted(player, "Level3", 45)
AnalyticsService:PlayerDied(player, "fall_damage")

-- Server stats (for admin/Cmdr)
AnalyticsService:GetServerStats() --> { PlayerCount, Uptime, ServerStartTime }
```

Session tracking is automatic: `SessionCount`, `TotalPlayTime`, `FirstJoinDate`, `LastSessionStart` are updated in PlayerData on join/leave.

### ShopService (Server) + ShopController (Client)

**Server:** `src/ServerScriptService/Server/Services/ShopService/init.luau`
**Client:** `src/ReplicatedStorage/Client/Controllers/ShopController/init.luau`
**Config:** `src/ReplicatedStorage/Shared/ShopConfig.luau`

Define items in `ShopConfig.Items`. Each item has `Id`, `Name`, `Category`, `Price`, `Currency`, `Description`, `OneTimePurchase`. Add currencies in `ShopConfig.Currencies`. Set category tab order in `ShopConfig.CategoryOrder`.

```lua
-- Server currency management
ShopService:GetCurrency(player, "Coins") --> number
ShopService:AddCurrency(player, "Coins", 100) -- premium multiplier auto-applied
ShopService:SpendCurrency(player, "Coins", 50) --> boolean

-- Server purchase (validates currency, one-time, grants item)
local success, message = ShopService:PurchaseItem(player, "speed_boost")
```

**Client UI:** Opens/closes with `B` key or `ButtonY` (gamepad). `ShopController:Open()`, `ShopController:Close()`, `ShopController:Toggle()`. Touch-friendly (48px+ buttons), scale-based layout, 2-column on mobile / 3-column on desktop. Purchase uses two-tap confirmation.

**Signals:** `ShopService.ItemPurchased` (server), `ShopService.Client.ItemPurchased` (client), `ShopService.Client.CurrencyChanged` (client).

### DailyRewardController (Client)

`src/ReplicatedStorage/Client/Controllers/DailyRewardController/init.luau`

Popup UI for daily login rewards. Shows automatically on join via `MonetizationService.LoginRewardReady` signal. 7-day calendar with claim button. Auto-dismisses after claim.

### LiveConfigService (Server)

`src/ServerScriptService/Server/Services/LiveConfigService/init.luau`
**Baseline config:** `src/ReplicatedStorage/Shared/GameConfig.luau`

Runtime configuration tuning. Overrides are server-lifetime only (not persisted) — safe for testing.

```lua
-- Read values (dot-path notation)
LiveConfigService:GetValue("Player.MaxHP") --> 100

-- Override at runtime
LiveConfigService:SetValue("Player.MaxHP", 200)
LiveConfigService:ResetValue("Player.MaxHP") -- back to baseline

-- React to changes
LiveConfigService.ConfigChanged:Connect(function(path, newValue) end)
```

**Cmdr commands:** `setconfig <path> <value>`, `getconfig <path>`, `resetconfig <path>`, `listconfigs`. Values are auto-converted (numbers, booleans).

### Shared Config Pattern

All game-specific configuration lives in `src/ReplicatedStorage/Shared/` so both server and client can read it:

| File | Purpose |
|---|---|
| `MonetizationConfig.luau` | GamePass IDs, DevProduct IDs/handlers, daily reward tables, premium multiplier |
| `ShopConfig.luau` | Shop items, currencies, category order |
| `GameConfig.luau` | Runtime-tunable game constants (used by LiveConfigService) |

When forking the template: update IDs in MonetizationConfig, define your items in ShopConfig, add your tunable constants to GameConfig.

## Template Sync Tool

`tools/template-sync.sh` syncs updates from roblox-template into existing game repos without overwriting game-specific code.

### Usage
```bash
# From any game repo (assumes template is at ../roblox-template)
bash ../roblox-template/tools/template-sync.sh

# Explicit paths
bash tools/template-sync.sh /path/to/roblox-template /path/to/game-repo

# Sync all games at once (from roblox-template directory)
bash tools/sync-all-games.sh

# Force sync even if version matches
bash tools/template-sync.sh . ../my-game --force
```

### How It Works
- **Always synced:** Toolchain configs, shared modules, template services/controllers, bootstrap files
- **Never synced:** Game-specific configs (`*Config.luau`), `default.project.json`, `README.md`, game services/controllers
- **Merged:** `Makefile` (new targets appended), `wally.toml` (new deps added), `CLAUDE.md` (new sections appended)
- **Version tracked:** `.template-version` in each game tracks last synced template version

### Configuration
Edit `tools/sync-config.sh` to customize sync rules. When adding new template files, add them to the `ALWAYS_SYNC` array.

## Testing

Unit tests run outside of Roblox Studio using **Lune** (lune-org/lune@0.8.9).

### Running Tests

```bash
make test              # Run all tests
lune run tests/runner  # Run directly
make test-watch        # Re-run on file changes (requires fswatch)
```

### Writing Tests

Test files live in `tests/unit/` and must end in `.spec.luau`. Each spec requires the framework:

```lua
local t = require("../framework")
local describe, it, expect, beforeEach = t.describe, t.it, t.expect, t.beforeEach

describe("MyModule", function()
    it("should work", function()
        expect(1 + 1).to.equal(2)
    end)
end)
```

**Assertions:** `expect(v).to.equal(x)`, `.to.be.ok()`, `.to.be.near(n, tol)`, `.to.be.a("type")`, `.to.be.greaterThan(n)`, `.to.throw()`, `.never.to.equal(x)`

**Loading source modules** (since Lune can't use Roblox requires):
```lua
local fs = require("@lune/fs")
local source = fs.readFile("src/ReplicatedStorage/Shared/MyModule.luau")
source = source:gsub("%-%-!strict\n", "")
source = source:gsub("export%s+type%s+%w+%s*=%s*%b{}\n*", "")
local chunk = assert(loadstring(source, "@MyModule"))
local MyModule = chunk()
```

**Mock helpers:** `tests/helpers/` provides `MockPlayer`, `MockInstance`, `MockSignal`, `MockServices`, `TestHelper`.

### Test Structure

```
tests/
  framework.luau         -- Test framework (describe/it/expect)
  runner.luau             -- Test runner entry point
  helpers/                -- Mock objects and test utilities
  unit/                   -- Unit test spec files (*.spec.luau)
  README.md               -- Detailed testing guide
```

### CI

Tests run automatically via `.github/workflows/ci.yml` on push and PR: lint + format check + tests.

## Luau Type Annotation Rules

Type annotations with `:` are only valid on **local variable declarations** and **function parameters**. They are **NOT** valid on module/table field assignments.

```lua
-- WRONG: parse error "expected identifier when parsing method name"
MyConfig.Items: { [string]: ItemDef } = { ... }

-- CORRECT: no annotation on dotted assignment
MyConfig.Items = { ... }

-- CORRECT: annotate a local, then assign
local items: { [string]: ItemDef } = { ... }
MyConfig.Items = items
```

Use `export type` definitions above the table to document the shape — don't inline type annotations on field assignments.

## Conventions

- Services go in `Services/` as a folder with `init.luau` (or as a single `.luau` file)
- Controllers go in `Controllers/` with the same structure
- Component modules must be named `*Component` (e.g., `HealthComponent.luau`)
- Use Promises (evaera/promise) for async operations
- Use Trove for cleanup/lifecycle management
- Use Signal for custom events
- Clean up player-specific data on `Players.PlayerRemoving` to prevent memory leaks
