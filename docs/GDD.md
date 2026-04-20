# Origami Expedition — Game Design Document

> **Status: WIP.** This document describes the intended design. Scaffolding for most of the systems below exists in code, but nearly everything is actively in-progress and subject to change. Phases are generally worked on in parallel, not strictly sequentially.

## Overview
Origami Expedition is a mining + creature + breeding game built on origami-playground. Players mine through 7 depth layers of origami-themed terrain, find materials to craft items and eggs that hatch LLM-generated creatures, breed creatures socially, and build on surface plots.

The project grew out of the origami-playground text-to-model sandbox (`CreatorController`), where players type prompts and an LLM returns JSON that builds creatures, vehicles, buildings, tools, hats, and props in-world. That sandbox remains the foundation for creature generation; the expedition layer adds a persistent voxel world, mining progression, and crafting on top.

## Core Loop
1. **Mine** — Dig through layered terrain, collect materials
2. **Craft** — Use materials to craft tools, items, and creature eggs
3. **Hatch** — Eggs produce unique LLM-generated creatures
4. **Breed** — Combine creatures with other players for new species
5. **Build** — Develop surface plots with materials and creatures

---

## World System

### Island
- Procedural island floating in void
- Surface: gentle origami paper hills (FBM heightmap, max ~20 studs elevation). Early experiments with varied surface biomes (sunset mesa, forest, etc.) mostly didn't work out and aren't in play.
- Underground: 7 depth layers extending to Y=-2000. Caves feature occasional neon mushroom decorations — the one biome flourish that survived.

### Depth Layers

| # | Layer | Depth (Y) | Key Blocks | Material Tier | Multiplier |
|---|-------|-----------|------------|---------------|------------|
| 1 | Paper Fields | 0 to -80 | Paper, Cardboard, Grass | Cardboard | 1x |
| 2 | Pulp Caverns | -80 to -240 | Compressed Pulp, Clay | Recycled | 1.5x |
| 3 | Fold Tunnels | -240 to -480 | Folded Stone, Quartz | Standard | 2x |
| 4 | Origami Depths | -480 to -800 | Origami Rock, Gems | Premium | 3x |
| 5 | Crystal Lattice | -800 to -1200 | Crystal formations | Metallic | 4x |
| 6 | Void Seams | -1200 to -1600 | Void stone, rare veins | Mythic | 6x |
| 7 | The Core | -1600 to -2000 | Prismatic blocks | Prismatic | 8x |

### Chunk System
- Block size: 5 studs
- Chunk size: 16x16x16 blocks (80 studs per chunk edge)
- Streaming radius: 3 horizontal, 1 up, 4 down
- RLE compression for network transfer and DataStore persistence
- Delta-only saves for modified blocks

---

## Mining System

### Mechanics
- Click/tap to mine targeted block
- Server-validated damage accumulation vs block hardness
- Tool tier gating — can't mine blocks below your tool tier
- Drop calculation from BlockRegistry tables
- Anti-cheat: distance checks, rate limiting, tier validation

### Tool Tiers

| Tier | Tool | Craftable From | Mines Up To |
|------|------|---------------|-------------|
| 0 | Paper Hands | (default) | Paper Fields |
| 1 | Cardboard Pick | Cardboard x20 | Pulp Caverns |
| 2 | Stone Pick | Folded Stone x20, Pulp x10 | Fold Tunnels |
| 3 | Crystal Pick | Crystal x10, Origami Rock x15 | Origami Depths + Crystal Lattice |
| 4 | Void Pick | Void Stone x10, Crystal x5 | Void Seams |
| 5 | Prismatic Pick | Prismatic Shard x5, Void Stone x10 | The Core |

### Block Properties
Each block has:
- **Hardness**: Hits required to break (scaled by tool power)
- **Color**: RGB color for rendering
- **Material**: Roblox terrain material
- **minTier**: Minimum tool tier to mine
- **drops**: List of {itemId, count, chance} drop entries
- **Layer**: Which depth layer it appears in

---

## Materials System

### Material Categories
Materials are tiered by depth layer:
- **Cardboard Tier** (Paper Fields): Paper Scrap, Cardboard, Dried Pulp
- **Recycled Tier** (Pulp Caverns): Compressed Pulp, Clay Chunk, Recycled Fiber
- **Standard Tier** (Fold Tunnels): Folded Stone, Quartz Shard, Paper Crystal
- **Premium Tier** (Origami Depths): Origami Rock, Gem Fragments, Ink Stone
- **Metallic Tier** (Crystal Lattice): Crystal Shard, Foil Sheet, Metal Origami
- **Mythic Tier** (Void Seams): Void Stone, Dark Paper, Shadow Fold
- **Prismatic Tier** (The Core): Prismatic Shard, Core Fragment, Rainbow Paper

### Ore Veins
- Random-walk vein placement within appropriate depth layers
- Vein size and frequency scale with depth
- Rare ores appear as special block types in the terrain

---

## Creature System (WIP)

### Egg Crafting
- Combine materials of specific tiers to craft eggs
- Higher tier materials = rarer/stronger creature potential
- Each egg has a "theme prompt" derived from materials used

### LLM Generation
- Egg hatching sends prompt to origami-server LLM API
- Returns JSON creature definition (parts, colors, animations, stats)
- OrigamiBuilder constructs the Roblox model from JSON
- Each creature is unique — procedurally generated appearance and stats

### Creature Properties
- Category: creature (from existing origami system)
- Locomotion: walk, slither, fly, float, hop, stationary
- Stats: HP, attack, defense, speed (influenced by egg materials)
- Abilities: derived from material tier + LLM creativity
- Rarity: Common → Uncommon → Rare → Epic → Legendary → Mythic

### Combat Strategy Fields (WIP)
Creature JSON may include optional strategy fields that influence combat behavior:
- `attackType`: `single`, `splash`, `rapid`, `piercing`
- `targetPriority`: `nearest`, `weakest`, `strongest`, `fastest`
- `defenseType`: `none`, `armor`, `dodge`, `regen`

The LLM picks these based on creature description (e.g. "giant turtle" → armor + splash). How and where combat actually shows up in the game is still being figured out.

---

## Breeding System (WIP)

### Social Mechanics
- Two players place their creatures at a breeding station
- Creatures must be compatible (checked by AI)
- Breeding produces a new egg combining traits from both parents
- Cooldown per creature between breedings

### Inheritance
- Child creature prompt combines elements from both parents
- Material tier of parents influences child's base stats
- Chance for mutations (rare trait appearances)

---

## Surface Plots (WIP)

### Plot System
- Each player can claim one surface plot
- Plot size: 8x8 chunks (128x128 blocks)
- Build using mined materials
- Display creatures on your plot
- Visit other players' plots

### Building
- Place blocks from inventory onto plot
- Material appearance matches the block type
- Creatures can be assigned to guard/decorate plots

---

## Multiplayer

### Shared World
- All players share the same voxel world
- Block changes replicate to all nearby players
- Chunk streaming based on player position
- DataStore persistence for world modifications

### Social Features
- See other players mining nearby
- Trade materials and creatures
- Breed creatures cooperatively
- Visit and rate surface plots

---

## Economy

### Currencies
- **Folds** (existing) — Premium currency
- **Cranes** (existing) — Earned currency
- **Materials** — Directly used for crafting

### Sinks
- Tool crafting consumes materials
- Egg crafting consumes materials
- Plot building consumes materials
- Tool upgrades require increasingly rare materials

### Sources
- Mining blocks → material drops
- Deeper layers → more valuable materials
- Daily login rewards
- Trading with other players

---

## Technical Architecture

### Server Services
- **WorldService**: Chunk lifecycle, block state, persistence
- **ChunkStreamService**: Position-based chunk streaming
- **SpawnService**: Surface spawn point management
- **MiningService**: Mining validation, drops, tool management
- **PlayerDataService**: Player inventory, stats, tools

### Client Controllers
- **ChunkRenderController**: Terrain rendering, part pooling
- **MiningController**: Input handling, raycasting, visual feedback
- **CreatorController**: Origami-playground text-to-model sandbox UI (foundation)

### Shared Modules
- **BlockType**: Block ID enum
- **ChunkUtil**: Coordinate conversion helpers
- **ChunkSerializer**: RLE compression for chunks
- **BlockRegistry**: Block properties and drop tables
- **BiomeConfig**: Depth layer definitions
- **ToolRegistry**: Tool tier definitions
- **WorldGenModule**: Procedural terrain generation

### Additional Services (WIP, beyond Phase 1)
- **OrigamiService**: LLM text-to-model endpoint (foundation, shared with sandbox)
- **EggCraftingService**: Craft eggs from materials, request LLM creature generation
- **BreedingService**: Breeding stations and inheritance
- **PlotService**: Surface plot claiming and building
- **WorkshopService**: Crafting recipes and UI
- **CreatureService** / **CreatureAI**: Creature behavior and AI
- **BlockPlacementService**: Placing blocks from inventory (plots)

---

## Phase Plan

These phases are not strictly sequential — scaffolding for most of them already exists in code, and they're being iterated on in parallel as WIP.

### Phase 1: Voxel World + Mining (WIP, primary focus)
- Chunk system ported from forgefire
- 7 depth layers with origami-themed blocks
- Tool tier progression
- Basic mining with drops

### Phase 2: Creatures + Eggs (WIP)
- Egg crafting from materials
- LLM creature generation (leverages existing origami-playground text-to-model)
- Creature display and basic AI

### Phase 3: Breeding + Social (WIP)
- Breeding stations
- Creature inheritance
- Trading system

### Phase 4: Surface Plots (WIP)
- Plot claiming and building
- Creature placement on plots
- Plot visiting and rating

### Phase 5: Polish + Content
- More block types and materials
- Achievement system
- Leaderboards
- Sound and VFX polish
