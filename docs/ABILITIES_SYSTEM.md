# Custom Abilities System — Design Doc

## Philosophy

Players prompt anything. The LLM returns pure JSON data. Pre-built Luau modules interpret it. No runtime code execution, no security risk. The creativity comes from the LLM combining a small set of building blocks in ways we didn't anticipate.

---

## 1. Property Bag — The Core

Every ability ultimately **sets properties** on a character or target. Instead of hardcoding "invisibility" or "super speed", we expose ~20 properties the LLM can manipulate:

### Character Properties

| Property | Type | Range | What it does |
|----------|------|-------|-------------|
| `transparency` | number | 0-1 | Character visibility (1 = invisible) |
| `scale` | number | 0.3-3 | Character size multiplier |
| `speed` | multiply | 0.1-3 | Walk/run speed |
| `jump_power` | multiply | 0.5-5 | Jump height |
| `gravity` | multiply | 0-2 | 0 = flight, 0.5 = moon, 2 = heavy |
| `damage_mult` | multiply | 0.5-3 | Outgoing damage multiplier |
| `defense_mult` | multiply | 0.5-3 | Incoming damage reduction |
| `hp_add` | number | 0-200 | Bonus health points |
| `hp_regen` | number | 0-10 | HP per second |
| `collision` | bool | — | Pass through walls |
| `nametag` | bool | — | Show/hide display name |
| `anchored` | bool | — | Freeze in place (stun) |

### Visual Properties

| Property | Type | Range | What it does |
|----------|------|-------|-------------|
| `glow` | color | — | Neon outline around character |
| `trail` | color+size | — | Movement trail effect |
| `particles` | type+color | — | Particle emitter (fire, smoke, sparkle, snow) |
| `aura_color` | color | — | Glowing sphere around character |
| `sound` | string | preset | Loop a sound (hum, crackle, wind, heartbeat) |

### Camera Properties (self only)

| Property | Type | Range | What it does |
|----------|------|-------|-------------|
| `camera_fov` | number | 40-120 | Zoom in/out effect |
| `camera_shake` | number | 0-5 | Screen shake intensity |

### Ability JSON Format

```json
{
  "name": "Shadow Form",
  "delivery": "self",
  "duration": 8,
  "cooldown": 20,
  "actions": [
    { "set": "transparency", "value": 0.8, "duration": 8 },
    { "set": "speed", "multiply": 1.5, "duration": 8 },
    { "set": "collision", "value": false, "duration": 8 },
    { "set": "nametag", "value": false, "duration": 8 },
    { "set": "trail", "color": [20, 0, 40], "size": 0.5, "duration": 8 },
    { "set": "glow", "color": [80, 0, 120], "duration": 8 }
  ]
}
```

### Luau Implementation

One `applyAction` function per property — each is 3-5 lines. A generic loop applies them:

```lua
function AbilityService:executeActions(character, actions)
    for _, action in actions do
        local duration = action.duration or 0
        self:applyAction(character, action)
        if duration > 0 then
            task.delay(duration, function()
                self:revertAction(character, action)
            end)
        end
    end
end
```

---

## 2. Delivery Methods

How the ability reaches its target:

| Delivery | Description | Parameters |
|----------|------------|------------|
| `self` | Apply to caster | — |
| `target` | Apply to looked-at player/creature | `range` |
| `area` | Apply to all in radius | `radius`, `shape` (sphere/cone) |
| `projectile` | Fire a projectile (see §3) | full projectile config |
| `dash` | Lunge forward, hit along path | `distance`, `speed` |
| `aura` | Persistent ticking zone around caster | `radius`, `tick_rate`, `duration` |
| `summon` | Spawn an origami creature | `generate: "creature"`, `prompt` |
| `transform` | Swap avatar model | `generate: "avatar"`, `prompt` |
| `shield` | Absorb damage | `amount`, `on_break` effects |
| `phase` | Invulnerable + noclip | `duration` |
| `grapple` | Pull self to point or pull target to self | `range`, `direction` |

---

## 3. Customizable Projectiles — Physics-Driven

No enum menus. The LLM sets **continuous physics properties** and the trajectory/behavior emerges naturally.

### The Projectile is an Origami Model

The LLM generates a tiny model (1-5 parts) for the projectile itself:

```json
{
  "projectile": {
    "model": {
      "parts": [
        { "shape": "Ball", "size": [0.5, 0.5, 0.5], "color": [255, 100, 0], "material": "Neon" },
        { "shape": "Wedge", "size": [0.3, 0.6, 0.3], "color": [255, 50, 0], "material": "Neon", "position": [0, 0, -0.4] }
      ]
    }
  }
}
```

### Physics Properties

Every projectile behavior comes from a small set of continuous values:

| Property | Type | Default | What it does |
|----------|------|---------|-------------|
| `speed` | number | 40 | Studs per second |
| `gravity` | number | 0 | 0=straight, 1=arc, -0.5=floats up, 3=meteor |
| `homing` | number | 0 | 0=dumb, 3=gentle tracking, 10=aggressive lock-on |
| `spin` | number | 0 | 0=none, 5=spiral, negative=opposite rotation |
| `count` | number | 1 | How many projectiles |
| `spread_angle` | number | 0 | 0=single, 30=shotgun, 360=ring |
| `spawn_offset_y` | number | 0 | 0=from caster, 40=rain from sky |
| `lifetime` | number | 3 | Seconds before auto-destroy |
| `pierce` | bool | false | Pass through targets or stop |
| `returns` | bool | false | Boomerang back to caster |
| `bounce_count` | number | 0 | Ricochets off surfaces |
| `trail` | color+size | nil | Visual trail behind projectile |

### On-Hit Properties

Also continuous — zero means off:

| Property | Type | Default | What it does |
|----------|------|---------|-------------|
| `explode_radius` | number | 0 | 0=no explosion, 8=big boom |
| `split_count` | number | 0 | 0=none, 4=splits into 4 sub-projectiles |
| `linger_radius` | number | 0 | 0=none, 6=leaves a ground zone |
| `linger_duration` | number | 0 | How long the zone persists |
| `stick_duration` | number | 0 | 0=none, 5=attaches to target |
| `effects` | array | [] | Property effects applied to hit targets |

### The Luau Physics Loop (~15 lines)

```lua
-- Every frame per projectile
velocity = velocity + Vector3.new(0, -gravity, 0) * dt

if homing > 0 and target then
    local toTarget = (target.Position - position).Unit
    velocity = velocity:Lerp(toTarget * speed, homing * dt)
end

if spin ~= 0 then
    local perp = velocity.Unit:Cross(Vector3.yAxis)
    velocity = velocity + perp * math.sin(elapsed * spin) * dt * 10
end

position = position + velocity * dt
```

That's it. The LLM describes whatever it wants with just numbers.

### Emergent Behaviors

The LLM doesn't pick from a menu — behaviors emerge from the numbers:

- **"Drunk missile"** → `speed: 30, homing: 2, spin: 8`
- **"Meteor rain"** → `count: 6, gravity: 3, spawn_offset_y: 50, spread_angle: 20, explode_radius: 5`
- **"Shotgun blast"** → `count: 8, speed: 60, spread_angle: 25, lifetime: 0.5`
- **"Boomerang disc"** → `speed: 35, returns: true, pierce: true, spin: 3`
- **"Homing swarm"** → `count: 5, speed: 20, homing: 6, spread_angle: 60`
- **"Bouncing orb"** → `speed: 25, bounce_count: 4, gravity: 0.5`
- **"Cluster bomb"** → `gravity: 1, explode_radius: 6, split_count: 6` (sub-projectiles with their own config)
- **"Healing rain"** → `count: 8, spawn_offset_y: 30, gravity: 1, spread_angle: 40, effects: [{ "type": "heal", "amount": 10 }]`
- **"Spider web"** → `speed: 20, gravity: 0.8, stick_duration: 5, effects: [{ "set": "slow", "percent": 80 }]`
- **"Gatling stream"** → `count: 20, speed: 60, spread_angle: 5, lifetime: 0.4` (fired in rapid sequence)

We didn't design any of these. The physics just produce them.

### Split is Recursive

`split_count > 0` spawns sub-projectiles, which can have their own physics config:

```json
{
  "speed": 30, "gravity": 1, "explode_radius": 4,
  "split_count": 4,
  "sub_projectile": {
    "speed": 20, "gravity": 0.5, "spread_angle": 90,
    "linger_radius": 3, "linger_duration": 5,
    "effects": [{ "type": "damage", "amount": 5, "element": "fire" }]
  }
}
```

Missile → explodes → splits into 4 → each leaves a fire zone. All from nested numbers.

### Luau Module

```
ProjectileService
├── spawn(origin, direction, config) → create origami micro-model, set initial velocity
├── update(dt) → physics loop for all active projectiles
├── onHit(projectile, target) → apply effects, check explode/split/linger/stick
│   └── spawn() again for splits (recursive, capped at depth 2)
└── cleanup() → destroy on lifetime expire or range
```

---

## 4. Triggers — Reactive Abilities

For abilities that activate automatically based on conditions:

```json
{
  "name": "Last Stand",
  "trigger": { "when": "hp_below", "threshold": 0.2 },
  "cooldown": 60,
  "actions": [
    { "set": "defense_mult", "multiply": 3, "duration": 8 },
    { "set": "glow", "color": [255, 200, 0], "duration": 8 },
    { "set": "scale", "value": 1.3, "duration": 8 },
    { "set": "camera_shake", "value": 2, "duration": 0.5 }
  ]
}
```

Available triggers:

| Trigger | Parameters | Fires when... |
|---------|-----------|--------------|
| `hp_below` | `threshold` (0-1) | HP drops below % |
| `hp_above` | `threshold` (0-1) | HP rises above % |
| `on_hit_taken` | — | Character takes damage |
| `on_kill` | — | Character defeats a target |
| `on_death` | — | Character dies |
| `interval` | `seconds` | Every N seconds |
| `on_sprint` | — | Player starts sprinting |
| `on_land` | — | Player lands after falling |

---

## 5. The `generate` Action — Self-Referencing

The most powerful primitive. Mid-ability, call back to the origami API:

```json
{ "generate": "creature", "prompt": "fire elemental minion", "count": 2, "duration": 20 }
{ "generate": "avatar", "prompt": "giant wolf beast", "duration": 15 }
{ "generate": "tool", "prompt": "lightning sword" }
{ "generate": "building", "prompt": "ice wall barrier", "position": "forward_5" }
```

This reuses the entire existing origami pipeline. Shapeshifting, summoning, weapon conjuring — all one primitive.

---

## 6. Safety & Balance

### Server-Side Clamping

Every property has hard limits checked on the server before applying:

```python
ABILITY_CLAMPS = {
    "damage": (0, 50),         # max 50 per hit
    "hp_add": (0, 200),        # max 200 bonus HP
    "speed": (0.1, 3.0),       # can't go faster than 3x
    "scale": (0.3, 3.0),       # can't be microscopic or huge
    "duration": (0, 30),       # max 30s per ability
    "cooldown": (2, 60),       # min 2s cooldown
    "projectile_count": (1, 12), # max 12 projectiles per cast
    "radius": (0, 20),         # max 20 stud radius
    "split_depth": (0, 2),     # max 2 levels of splitting
}
```

### Anti-Exploit

- All abilities validated server-side before applying
- Generate actions rate-limited (reuses existing API rate limit)
- Ability cooldowns tracked server-side, not client
- Can't stack conflicting properties (latest wins)
- Total active buffs capped at 5

---

## 7. Implementation Order

1. **PropertyService** — apply/revert the ~20 property setters
2. **EffectRunner** — process an actions list, handle durations
3. **ProjectileService** — spawn, trajectory, on-hit, split
4. **TriggerService** — monitor conditions, fire abilities
5. **AbilityManager** — keybind slots (Q/E/R), cooldown UI
6. **Server validation** — clamp all values, rate limit generates
7. **LLM prompt update** — add ability schema to system prompt
8. **UI** — ability bar with icons, cooldown indicators, buff display
