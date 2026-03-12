# Tests

Unit tests for the roblox-template, running outside of Roblox Studio using [Lune](https://lune-org.github.io/docs).

## Quick Start

```bash
# Install toolchain (includes Lune)
aftman install

# Run all tests
make test

# Or directly:
lune run tests/runner
```

## Writing Tests

### File naming

Test files must end in `.spec.luau` and live in `tests/unit/` (or any subdirectory under `tests/`).

### Test structure

Tests use a describe/it pattern. Each spec file must require the framework:

```lua
local t = require("../framework")
local describe, it, expect = t.describe, t.it, t.expect

describe("MyModule", function()
    it("should do something", function()
        expect(1 + 1).to.equal(2)
    end)

    it("should handle edge cases", function()
        expect(someValue).to.be.ok()
    end)
end)
```

### Available assertions

```lua
expect(value).to.equal(expected)       -- strict equality
expect(value).to.be.ok()              -- truthy (not nil, not false)
expect(value).to.be.near(n, tolerance) -- float comparison
expect(value).to.be.a("string")       -- type check
expect(value).to.be.greaterThan(n)
expect(value).to.be.greaterThanOrEqual(n)
expect(value).to.be.lessThan(n)
expect(value).to.be.lessThanOrEqual(n)
expect(fn).to.throw()                 -- expect function to error
expect(value).never.to.equal(other)   -- negated assertions
```

### Lifecycle hooks

```lua
describe("MyModule", function()
    beforeEach(function()
        -- runs before each it() block
    end)

    afterEach(function()
        -- runs after each it() block
    end)
end)
```

### Skipping tests

Use `itSKIP` instead of `it` to skip a test:

```lua
itSKIP("not implemented yet", function()
    -- this won't run
end)
```

### Loading source modules

Since tests run outside Roblox, you can't use `game:GetService()` or Roblox-style requires. Load source files via the filesystem:

```lua
local fs = require("@lune/fs")

local function loadModule(): any
    local source = fs.readFile("src/ReplicatedStorage/Shared/MyModule.luau")
    -- Strip Roblox-specific syntax if needed
    source = source:gsub("%-%-!strict\n", "")
    source = source:gsub("export%s+type%s+%w+%s*=%s*%b{}\n*", "")
    local chunk = assert(loadstring(source, "@MyModule"))
    return chunk()
end
```

### Using mock helpers

```lua
local MockPlayer = require("../helpers/MockPlayer")
local MockInstance = require("../helpers/MockInstance")
local MockServices = require("../helpers/MockServices")
local MockSignal = require("../helpers/MockSignal")
local TestHelper = require("../helpers/TestHelper")

-- Create a mock player
local player = MockPlayer.new({ Name = "Alice", UserId = 42 })

-- Create mock instances
local part = MockInstance.new("Part", { Name = "MyPart" })
part:SetAttribute("Health", 100)

-- Create mock Roblox services
local players = MockServices.createPlayers()
players:_addPlayer(player)

-- Use TestHelper assertions
TestHelper.assertEquals(1, 1)
TestHelper.assertNear(3.14, 3.14159, 0.01)
TestHelper.assertTableEquals({ a = 1 }, { a = 1 })
TestHelper.assertThrows(function() error("boom") end, "boom")
```

## What to Test

Focus on **pure logic** that doesn't depend on the Roblox runtime:

- Config validation (GameConfig, ShopConfig, MonetizationConfig)
- Math/formulas (damage calculations, economy math, scaling)
- Data transformations and utility functions
- State machines and business logic
- Table lookups and data integrity

Avoid testing code that heavily depends on Roblox APIs (Instance manipulation, physics, rendering). Those are better tested in Studio with integration tests.

## CI

Tests run automatically on push and pull request via GitHub Actions. See `.github/workflows/ci.yml`.
