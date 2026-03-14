# CLAUDE.md - Origami Playground

AI-powered 3D model generator for Roblox. Players type text prompts, an external LLM API generates structured model data, and the game builds the models in-world as creatures, avatars, vehicles, buildings, tools, hats, and props — all rendered in selectable art styles.

Built on the MindTrust Roblox template using the Knit framework.

## Game-Specific Architecture

### Core Modules

| Module | Path | Purpose |
|--------|------|---------|
| **OrigamiService** | `src/ServerScriptService/Server/Services/OrigamiService.luau` | Server-side API handler. Calls external LLM, returns model data, handles avatar rigging |
| **CreatorController** | `src/ReplicatedStorage/Client/Controllers/CreatorController/init.luau` | Main game UI + all client-side placement/animation/locomotion logic (~1200 lines) |
| **OrigamiBuilder** | `src/ReplicatedStorage/Shared/OrigamiBuilder.luau` | Builds Roblox Models from LLM JSON (shapes, materials, colors, z-fighting fix) |
| **OrigamiConfig** | `src/ReplicatedStorage/Shared/OrigamiConfig.luau` | Categories, art styles, rate limit, placement distance, max parts |
| **Server config** | `src/ReplicatedStorage/Assets/Configuration/Server.luau` | API_URL and API_KEY for the external LLM endpoint |

### Request Flow

1. Player types prompt in CreatorController UI, selects category + style
2. Client calls `OrigamiService:RequestModel(prompt, category, style)` via Knit RPC
3. Server POSTs to `{API_URL}/api/generate` with `X-Api-Key` header
4. Server returns `{ success, model }` — client receives as Promise (Knit)
5. CreatorController routes model by category to the appropriate handler
6. Each request runs in `task.spawn()` for parallel requests with queue UI

### API Request/Response Format

**Request** (JSON POST to `/api/generate`):
```json
{ "prompt": "a cute dragon", "player_id": "12345", "category": "creature", "style": "origami" }
```
- `category`: omitted for "raw" (sends `"raw": true` instead)
- `style`: defaults to "origami" if not provided

**Response**:
```json
{
  "success": true,
  "model": {
    "name": "Dragon",
    "category": "creature",
    "locomotion": "walk",
    "animation": "idle_bob",
    "attackType": "splash",
    "targetPriority": "weakest",
    "defenseType": "armor",
    "parts": [
      { "name": "seg_1", "shape": "Block", "position": [0,0,0], "size": [2,2,2],
        "orientation": [0,0,0], "color": [255,100,50], "material": "SmoothPlastic",
        "transparency": 0, "body_part": "UpperTorso" }
    ]
  }
}
```

**Error codes**: `empty_prompt`, `prompt_too_long`, `api_not_configured`, `request_failed`, `api_error(...)`, `parse_error`, `generation_failed`

### Categories (8)

| Category | Handler | Behavior |
|----------|---------|----------|
| `creature` | `spawnCreature()` | Wandering AI with per-part animations, ground raycast |
| `avatar` | `applyAvatar()` | Server-side character skin via `OrigamiService:ApplyAvatar` |
| `vehicle` | `spawnVehicle()` | VehicleSeat + collision plate + ProximityPrompt |
| `building` | `placeBuilding()` | Raycasts to ground, sits flush on surface |
| `tool` | `equipAsTool()` | Creates Roblox Tool with invisible Handle, auto-equips |
| `hat` | `equipAsHat()` | Welded to head, auto-scaled if > 3 studs |
| `prop` | `placeModel()` | Generic placement in front of player |
| `raw` | `placeModel()` | Unstructured LLM output, generic placement |

### Art Styles (11)

origami, lowpoly, voxel, balloon, wireframe, crystal, plush, steampunk, pixel, neon, freestyle

### Combat Strategy Fields (optional, for creature/building categories)

The LLM can return strategy fields that drive combat behavior in Auto Battler and Tower Defense modes. Picked by the LLM based on the creature/tower description (e.g. "giant turtle" → armor + splash).

| Field | Values | Default | Effect |
|-------|--------|---------|--------|
| `attackType` | `single`, `splash`, `rapid`, `piercing` | `single` | `splash`: AoE damage around target. `rapid`: 2x speed, 0.6x damage. `piercing`: ignores armor defense. |
| `targetPriority` | `nearest`, `weakest`, `strongest`, `fastest` | `nearest` | Who to attack first. `fastest` targets creep closest to reaching the base (TD) or highest speed (AB). |
| `defenseType` | `none`, `armor`, `dodge`, `regen` | `none` | `armor`: -30% damage (except piercing). `dodge`: 25% miss chance. `regen`: heals over time. |

### Creature Animation System

Part names drive animations in `applyCreatureAnimation()`. The LLM names parts with prefixes:

| Prefix | Animation | Details |
|--------|-----------|---------|
| `seg_N` | Accordion fold | Alternating Y offset + yaw, snappy `foldCurve()` easing |
| `wing_L_N` / `wing_R_N` | Flapping | Z-rotation, left/right mirrored |
| `tail_N` | Side-to-side sway | Y-axis rotation |
| `jaw_*` | Open/close | X-axis rotation, 0-15 degrees |
| `leg_FL_*` / `leg_FR_*` / `leg_BL_*` / `leg_BR_*` | Walking cycle | Phase-offset X rotation, left/right + front/back |

`foldCurve(raw) = sign(raw) * abs(raw)^0.6` — snappy paper-fold easing.

### Creature Locomotion (6 types)

| Type | Behavior |
|------|----------|
| `walk` | Ground movement, wander radius 20, speed 4 |
| `slither` | Sinuous S-curves perpendicular to travel, radius 12 |
| `fly` | Swooping sine-wave altitude + banking, hover 12 studs, radius 30 |
| `float` | Gentle hover with vertical bob, hover 6 studs, radius 15 |
| `hop` | Parabolic arcs with forward tilt, radius 18 |
| `stationary` | In-place animation only, no movement |

### OrigamiBuilder

`BuildModel(modelData)` creates a Roblox Model from JSON:
- **Shapes**: Block, Ball, Cylinder, Wedge
- **Materials**: SmoothPlastic, Neon, Glass, Metal, Wood, Concrete, Brick, Marble, Granite, Fabric, Ice, Foil, Sand, Grass
- **Z-fighting fix**: Nudges overlapping small parts 0.15 studs outward
- Sets first part as PrimaryPart

`ApplyAnimation(model, type)` for non-creature models:
- `idle_bob`, `spin_slow`, `bounce`, `wobble`, `flutter`, `breathe`, `none`
- Stores RunService.Heartbeat connection on model; auto-disconnects on Destroying

### Avatar System (OrigamiService server-side)

- **Rigged mode** (parts have `body_part` field): Welds each part to the corresponding character body part. Supports R15 names with R6 fallback mapping.
- **Legacy mode** (no `body_part`): Welds everything to HumanoidRootPart with 180-degree Y flip.
- Saves original appearance (body part transparency, accessories, shirt/pants) for `ResetAvatar()`.
- Origami parts marked with `OrigamiAvatar` attribute for cleanup.

### Vehicle System

- VehicleSeat as PrimaryPart (MaxSpeed 50, Torque 10, TurnSpeed 8)
- All visual parts welded with `Massless = true` to prevent tipping
- Invisible collision plate at bottom for ground contact
- ProximityPrompt triggers `Humanoid:MoveTo(seat.Position)` for auto-sit

## Game-Specific Gotchas

- **API key in source**: `Server.luau` contains a hardcoded API key. Don't commit new keys.
- **Parallel requests**: Each `submitPrompt()` runs in `task.spawn()`. No cooldown enforced client-side (rate limit is in OrigamiConfig but commented out of flow). Multiple requests queue with status dots.
- **Built-in sounds only**: Uses `rbxasset://` URLs (`electronicpingshort.wav`, `uuhhh.mp3`) — no asset ownership needed.
- **Hat max size**: Auto-scales down to 3 studs max dimension. Parts repositioned relative to head center.
- **Vehicle mass**: Collision plate and all visual parts are `Massless = true` so they don't tip the VehicleSeat.
- **Z-fighting**: OrigamiBuilder nudges overlapping parts outward by 0.15 studs after building.
- **Creature raycast exclusion**: Exclude both the creature model and player character from ground raycasts.
- **Creature animation state**: Stored in closures within `task.spawn()`, not on the model — safe GC on destroy via `stopped` flag + `isAlive()` check.
- **Avatar body_part attribute**: Set on each origami part via `part:SetAttribute("BodyPart", name)` during build, read during avatar rigging.
- **ClientEntry naming trick**: `ClientEntry.server.luau` has `.meta.json` setting RunContext to Client — it runs as a LocalScript despite the `.server.luau` extension.

---

## Project Structure

```
src/
  ReplicatedStorage/
    Assets/
      Configuration/Server.luau    # API_URL and API_KEY
    Client/
      ClientEntry.server.luau      # Entry script (RunContext: Client via .meta.json)
      init.luau                    # Client bootstrap
      Controllers/
        CreatorController/init.luau  # Main game UI + placement + animation
        AnimationController.luau     # Animation loading/playback utility
        InputController.luau         # Cross-platform input handling
        UIController/init.luau       # General UI management
        ShopController/init.luau     # Shop UI
        DailyRewardController/init.luau
        CmdrController/init.luau
      Components/                  # Client-only components
    Shared/
      OrigamiBuilder.luau          # Builds Roblox Models from LLM JSON
      OrigamiConfig.luau           # Categories, styles, constraints
      Components/                  # Shared components
      Types/                       # Type definitions
      Enums/                       # Enum definitions
      Environment.luau
      GameConfig.luau              # Runtime-tunable constants
      MonetizationConfig.luau
      ShopConfig.luau
    Packages/                      # Wally shared packages (gitignored)
  ServerScriptService/
    Server/
      Main.server.luau             # Server entry point
      init.luau                    # Server bootstrap
      Services/
        OrigamiService.luau        # External API calls + avatar rigging
        PlayerDataService/init.luau
        MonetizationService/init.luau
        AnalyticsService/init.luau
        ShopService/init.luau
        LiveConfigService/init.luau
        BadgeService.luau
        MTAnalyticsService.luau
        CmdrService/init.luau
      Components/                  # Server-only components
    ServerPackages/                # Wally server packages (gitignored)
```

## Knit Framework

Knit (sleitnick/knit@1.7.0) provides service-oriented architecture with client/server separation.

### Services (Server)

Server-side singletons in `src/ServerScriptService/Server/Services/`. Created with `Knit.CreateService`. `KnitInit()` runs first (reference only), `KnitStart()` runs after all inits (safe to call other services).

### Controllers (Client)

Client-side singletons in `src/ReplicatedStorage/Client/Controllers/`. Created with `Knit.CreateController`. Same init/start lifecycle as services.

### Components

Bind behavior to instances via CollectionService tags. Must be named `*Component` (auto-discovered). Loaded after Knit starts.

### Player Parameter Rules

| Direction | `player` auto-injected? | Who passes it? |
|---|---|---|
| Client calls `Service.Client:Method(player, ...)` | Yes | Knit injects it |
| Client fires `Service.Client.Signal` | Yes | Knit injects it |
| Server fires `self.Client.Signal:Fire(player, ...)` | No | You pass explicitly |
| Server calls internal `Service:Method(player, ...)` | No | You pass explicitly |

Inside a `Client` method, `self.Server` refers to the service root. From the service root, `self.Client` is the client-facing table.

## Promise Handling (IMPORTANT)

Client calls to Knit services return **Promises**. Always handle them.

```lua
-- Blocking await
local ok, data = MyService:GetData():await()

-- Chaining (always add :catch)
MyService:DoThing():andThen(function(result) end):catch(function(err) warn(err) end)

-- In event connections, wrap in task.spawn
task.spawn(function()
    MyService:GetData():andThen(function() end):catch(function(err) warn(err) end)
end)
```

### Server-Side vs Client-Side Read (CRITICAL)

- **Server**: `PlayerDataService:Read(player, { "Key" })` returns value directly — NOT a Promise
- **Client**: `PlayerDataService:Read():await()` — goes through Knit proxy, IS a Promise

## Startup Flow

1. **Server:** `Main.server.luau` → `Knit.AddServices()` → `Knit:Start()` → components → `ServerStatus = "Started"`
2. **Client:** `ClientEntry.server.luau` → waits for `ServerStatus == "Started"` → `Knit.AddControllers()` → `Knit:Start()` → components

## Toolchain

| Tool | Version | Purpose |
|---|---|---|
| Rojo | 7.6.1 | Syncs code to Roblox Studio (port 34872) |
| Wally | 0.3.2 | Package manager |
| StyLua | 2.3.0 | Formatter (tabs/4, 120 cols, double quotes, Unix LF) |
| Selene | 0.29.0 | Linter (roblox standard, excludes Packages/*) |
| wally-package-types | 1.6.2 | Fixes Luau types for Wally packages |
| Lune | 0.8.9 | Luau runtime for tests outside Studio |

Managed via **aftman** (`aftman.toml`).

## Code Style

- **Language**: Luau (strict mode preferred: `--!strict`)
- **Formatter**: StyLua — tabs (width 4), 120 column width, double quotes, Unix line endings
- **Linter**: Selene with `roblox` standard
- **Call parentheses**: Always use parentheses

## Development Commands

```bash
aftman install              # Install toolchain
wally install               # Install packages (or: make wally-install)
make wally-package-types    # Fix Luau types for Wally packages
rojo serve                  # Start Rojo sync server (port 34872)
stylua .                    # Format code
selene .                    # Lint code
make test                   # Run unit tests
lune run tests/runner       # Run tests directly
```

## Dependencies (wally.toml)

**Shared:** Knit 1.7.0, Promise 4.0.0, TableUtil 1.2.1, Signal 2.0.3, Component 2.4.8, Logging 0.3.0, Trove 1.5.1, t 3.1.1
**Server-only:** ProfileStore 1.0.3, Cmdr 1.2.0

## Testing

Unit tests in `tests/unit/*.spec.luau` run via Lune. Framework: `tests/framework.luau` (describe/it/expect). Mocks in `tests/helpers/`. CI: `.github/workflows/ci.yml` (lint + format + tests on push/PR).

## Luau Type Annotation Rules

Type annotations with `:` are only valid on **local variable declarations** and **function parameters** — NOT on module/table field assignments.

```lua
-- WRONG: MyConfig.Items: { [string]: ItemDef } = { ... }
-- CORRECT: MyConfig.Items = { ... }
```

## Cross-Platform (IMPORTANT)

All UI and interactions MUST work on mobile (iOS/Android), PC, Xbox, and PlayStation. Follow these rules strictly:

### Platform Detection
```lua
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local IS_CONSOLE = GuiService:IsTenFootInterface()
```

### UI Layout Rules
- **NEVER use hardcoded pixel sizes** for containers. Use `UDim2.fromScale()` or platform-conditional sizing.
- **Mobile**: containers should be 85-95% screen width. Fixed-width panels must adapt.
- **Console (10-foot UI)**: text and buttons must be ~1.5x larger than desktop.
- Use responsive sizing helpers (FONT_SM/MD/LG, BTN_HEIGHT, ROW_HEIGHT) — see CreatorController for the pattern.
- Queue panels, catalog panels, and overlays must fit on small screens (~390px wide).
- Account for **safe areas** (notches, rounded corners) — avoid placing interactive elements in screen corners.

### Button & Touch Target Rules
- **Minimum touch target**: 44x44px on mobile, 48x48px on console (Apple HIG / Xbox guidelines).
- **Always use `.Activated`** signal — NEVER `.MouseButton1Click`. `Activated` fires on mouse click, touch tap, AND gamepad confirm.
- Sidebar/icon buttons: 34px (desktop), 44px (mobile), 52px (console).

### Input Rules
- **Keyboard actions must have gamepad equivalents**:
  - Space → ButtonA (jump, fly, confirm)
  - E → ButtonX (interact)
  - Q → ButtonY (alternate action)
  - Check with `UserInputService:IsGamepadButtonPressed(Enum.UserInputType.Gamepad1, keyCode)`
- **Vehicle flight**: check both `Enum.KeyCode.Space` AND `Enum.KeyCode.ButtonA`
- **Hat effects**: map EffectKey to corresponding gamepad button
- **TextBox input**: works automatically on mobile (virtual keyboard) and is not available on console — provide alternative UIs for console if text entry is required.
- Use `ContextActionService:BindAction()` with `createTouchButton = true` for mobile action buttons.

### Text Sizing
| Context | Desktop | Mobile | Console |
|---------|---------|--------|---------|
| Small labels | 11px | 13px | 16px |
| Body text | 14px | 16px | 20px |
| Buttons/headings | 16px | 18px | 24px |

### Testing Checklist
Before shipping any UI change, verify:
- [ ] All buttons reachable and tappable on mobile (no overlapping, no tiny targets)
- [ ] Text readable on mobile without squinting (13px minimum)
- [ ] Console text large enough for TV viewing (16px minimum)
- [ ] Gamepad can navigate and activate all interactive elements
- [ ] Virtual keyboard doesn't obscure input fields on mobile
- [ ] No UI extends beyond screen edges on any device

## Built-in Services

See template documentation for: **MonetizationService**, **AnalyticsService**, **ShopService/ShopController**, **DailyRewardController**, **LiveConfigService**, **Cmdr**. Config files in `src/ReplicatedStorage/Shared/` (`MonetizationConfig.luau`, `ShopConfig.luau`, `GameConfig.luau`).

## Conventions

- Services in `Services/` (folder with `init.luau` or single `.luau` file)
- Controllers in `Controllers/` (same structure)
- Components named `*Component` (auto-discovered by bootstrap)
- Use Promises for async, Trove for cleanup, Signal for events
- Clean up player data on `Players.PlayerRemoving`
