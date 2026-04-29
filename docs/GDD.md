# Origami Expedition — Game Design Document

> **Status: WIP.** This document describes the intended design. Scaffolding for many of the systems below exists in code; the design is locked at this layer of specificity but tunable in detail.

---

## Design Philosophy

This is a **mining-and-building sandbox** in the Minecraft tradition, distinguished by a **paper / origami aesthetic** and an **LLM-powered creative brush**.

The "why" of the game is identical to Minecraft's: **because the player can shape the world, and what they shape stays.** No central antagonist. No story. No quest. No dragon to kill. The game gets out of the way and lets the player project their own meaning onto a world that responds. Players mine because gathering feels good and they want stuff. Players build because they have ideas and want a place that's theirs.

The single new thing this game adds is the **LLM as creative brush**: a 7-year-old can't build a dragon out of blocks, but they can describe one, and the LLM hands it back folded in paper. The brush makes a creative range explode that no block sandbox can otherwise reach.

### Pillars (locked)
- **No central antagonist.** No villain, no boss-as-the-point, no story.
- **Persistence is sacred.** Nothing the player creates ever decays or is taken from them.
- **The world IS the reason.** Players invent their own goals.
- **Light Minecraft RPG profile.** Tool tiers + material tiers only. No HP, no levels, no classes, no stats.
- **Cozy by default.** No PvP, no griefing, no theft. Optional opt-in challenge content may exist later.

### What makes this game distinctive
- Paper / origami aesthetic across blocks (the world) and origami (the contents)
- LLM creates one-of-a-kind props/creatures/tools/accessories/vehicles
- Recipes from LLM creations enter a public catalog; other players summon copies with their own materials
- The originator's name stays on every recipe forever — visibility, not currency, is the social reward

---

## Core Loop

1. **Mine** — break blocks for bulk materials and rare ores
2. **Summon** — spend bulk + ore to summon a recipe from the public catalog (no LLM call)
3. **Build** — place blocks to make spaces; fill those spaces with summoned items
4. **Create (rare)** — when you have a Free Create slot or Robux, spend bulk + ore + a Create to author a brand-new recipe (LLM call). Your name goes on it forever.
5. **Show** — other players visit your plot and admire (or summon copies of) what you've made

Same as Minecraft, plus the LLM brush. No mandatory progression, no end-game.

---

## Aesthetic Rule (LOCKED)

The game uses **two visual languages**, each with its own job:

- **Blocks = architecture + terrain.** Houses, walls, floors, roofs, bridges, tunnels, rooms, towers, gates. Built manually by players from mined materials, tile by tile. Minecraft-style.
- **Origami (LLM-generated) = contents.** Props, creatures, vehicles, tools, accessories. Soft, folded, expressive. Generated from prompts.

This rule exists because the two languages each have a proper job and mix badly:
- Players *want* to build structures themselves — it's the skill and mastery loop.
- Players *don't want* to hand-craft every chair, pet, and sword — that's what the LLM is for.
- Freeform LLM output placed *as* architecture never matches a block grid and looks like a foreign object. Freeform LLM output placed *inside* a block interior looks like a tasteful prop.

**No LLM category outputs buildings, walls, rooms, or structural elements.** The `building` category is retired.

**Litmus test:** if you'd imagine an exterior wall *around* it, it's a block. If you'd put it *inside* a wall, it's LLM.

---

## Prop Subcategories

"Prop" is too broad — without scoping, the LLM happily returns a castle when asked. To keep props legible and stylistically tight, the prop category splits into subcategories, each with a hard bounding-box cap enforced server-side.

| Subcategory | Max bounding box | Anchor | Example prompts |
|---|---|---|---|
| **Furniture** | 8 studs any axis | Floor (flat bottom) | chair, table, bed, shelf, wardrobe |
| **Tabletop** | 2 studs any axis | Floor (flat bottom) | teacup, book, candle, figurine, trophy |
| **Wall art** | 4 studs, depth ≤ 0.5 | Back (mounts to wall) | painting, mirror, sconce, mask, flag |
| **Hanging** | 4 studs | Top (suspends from ceiling) | chandelier, banner, wind chime, mobile |
| **Floor decor** | 6 studs any axis | Floor (flat bottom) | plant, vase, rug, statue, mushroom |
| **Light source** | 4 studs any axis | Floor or top | lamp, torch, lantern, glow orb |
| **Container** | 6 studs any axis | Floor (flat bottom) | chest, barrel, bowl, basket |

**Subcategory-specific LLM prompt:** each subcategory ships its own prompt fragment describing the size cap, expected anchor, and a few good examples.

**Category selection IS the guardrail.** Players must pick a subcategory before generating. If a player types "castle" into `floor_decor`, they get a 6-stud toy castle figurine, which is a legitimate output. The category's bounding-box cap + prompt fragment do the scoping work; there is no prompt word blacklist.

**Post-generation bounding-box check:** after the LLM returns, compute the bounding box of `parts` and reject if it exceeds the subcategory's cap. One silent retry may be attempted with a stricter "smaller please" directive; if that also fails, the request surfaces an error.

**Retired categories:** `building` is retired (structures are player-built). `accessory` remains for wearable gear; legacy `hat` folds into `accessory`. The `voxel` category was a failed experiment (flat untextured cubes) — retained in code but not exposed.

---

## World System

### Island
- Procedural island floating in void
- Surface: gentle origami paper hills (FBM heightmap, max ~20 studs elevation). Other surface biome experiments (sunset mesa, forest, etc.) didn't work out and aren't in play.
- Underground: 7 depth layers extending to Y=-2000. Caves feature occasional neon mushroom decorations.

### Depth Layers + Material Tiers (LOCKED)

Each layer drops exactly two materials: **bulk** (common, for building) and **ore** (rare, in pockets, for summoning).

| # | Layer | Depth (Y) | Bulk Material | Ore Material | Tier Name |
|---|---|---|---|---|---|
| 1 | Paper Fields | 0 to -80 | Paper | Inkdrop | Common |
| 2 | Pulp Caverns | -80 to -240 | Pulp | Clay Bead | Uncommon |
| 3 | Fold Tunnels | -240 to -480 | Folded Stone | Quartz | Standard |
| 4 | Origami Depths | -480 to -800 | Origami Rock | Gem Fragment | Premium |
| 5 | Crystal Lattice | -800 to -1200 | Crystal | Foil Shard | Metallic |
| 6 | Void Seams | -1200 to -1600 | Void Stone | Shadow Wisp | Mythic |
| 7 | The Core | -1600 to -2000 | Prismatic Block | Prism Core | Master |

(Names tunable. Structure locked.)

### Chunk System
- Block size: 5 studs
- Chunk size: 16x16x16 blocks (80 studs per chunk edge)
- Streaming radius: 3 horizontal, 1 up, 4 down
- RLE compression for network transfer and DataStore persistence
- Delta-only saves for modified blocks

---

## Mining System

### Two Drops Per Block
Every mined block yields:
- **Bulk** — every block drops 1 of its layer's bulk material. Used for building structures (placed back as blocks) AND as base material for summoning recipes.
- **Ore** — only blocks containing ore pockets drop ore. Required for summoning recipes of that tier.

A player with 10,000 Paper but no Inkdrop can build a paper house but can't summon a paper bed. **Ore is the gate.**

### Ore Pocket Distribution
- **Pocket spawning:** rare clusters of 3–8 ore-bearing blocks within bulk material, like Minecraft veins
- **Visual:** ore pockets glow faintly through surrounding bulk so players see them embedded in walls
- **Drop rate (rough starting points, tunable):**
  - Tier 1 ore (Inkdrop): ~3% of blocks at depth 0 to -80
  - Tier 4 ore (Gem Fragment): ~1.5% of blocks at depth -480 to -800
  - Tier 7 ore (Prism Core): ~0.5% of blocks at depth -1600 to -2000

### No Bulk Substitution Upward
Tier-1 bulk does not convert to tier-7 bulk. Each layer's materials are its own. To summon tier 7, mine tier 7. Same as Minecraft — cobblestone doesn't smelt into iron.

### Tool Tiers

| Tier | Tool | Recipe | Mines Up To |
|---|---|---|---|
| 0 | Paper Hands | (default) | Paper Fields |
| 1 | Cardboard Pick | Paper x20 | Pulp Caverns |
| 2 | Stone Pick | Folded Stone x20, Pulp x10 | Fold Tunnels |
| 3 | Crystal Pick | Crystal x10, Origami Rock x15 | Origami Depths + Crystal Lattice |
| 4 | Void Pick | Void Stone x10, Crystal x5 | Void Seams |
| 5 | Prismatic Pick | Prismatic Block x5, Void Stone x10 | The Core |

Tools are themselves summonable recipes — you summon them like any other LLM creation, with material requirements per the recipe.

### Block Properties
Each block has:
- **Hardness:** Hits required to break (scaled by tool power)
- **Color:** RGB color for rendering
- **Material:** Roblox terrain material
- **minTier:** Minimum tool tier to mine
- **drops:** List of {bulk, ore?, count, chance} drop entries
- **Layer:** Which depth layer it appears in

---

## Browse vs Create — The Recipe Model

### Browse (free of LLM cost, costs materials)
1. Open the Browse UI (catalog of all existing recipes, filterable by category, tier, popularity, recency, originator)
2. Pick a recipe (chair, lamp, fox-creature, sword, hat — anything authored by any player)
3. Spend the recipe's required bulk + ore
4. The item appears in front of you, ready to place

**No LLM call** — the recipe stores the LLM's part data from the *original* creation. New copies execute that data, tinted by the materials you provided. Browse is the dominant verb. Most placements happen here.

### Create (costs a Free Create slot or Robux + materials)
1. Open the Create UI (prompt input + category/style + tier picker)
2. Pick a category (creature, prop subcategory, tool, vehicle, accessory)
3. Choose a tier — determines which ore the new recipe will require
4. Type a prompt
5. Spend bulk + ore + 1 Free Create OR Robux
6. LLM rolls a brand-new origami item; the recipe enters the public catalog with **your name** as originator

Creating is rare. Browsing is constant.

### Originator Attribution
- Every recipe in the catalog has the originator's name forever
- Copies show "originally folded by [name]" on inspect
- Originators see a count of how many times their recipe has been summoned
- Public profile lists every recipe a player has authored

This is the social reward for creating: **visibility, not currency.** No royalties, no marketplaces — pure attribution.

### Material Quality Affects Output
The recipe defines the *shape*. The materials define the *finish*. Same Star-Quilt Bed recipe summoned with Paper looks soft white; summoned with Crystal it has crystal corner posts; summoned with Prism Core it glows with star-flecks. Same shape, richer ingredients, better finish. No new recipe needed.

### Recipe Tiers

| Tier | Required Ore | Example Items |
|---|---|---|
| Common | Inkdrop | Wooden chair, paper lantern, basic tool |
| Standard | Quartz | Stone bench, decorative tools |
| Premium | Gem Fragment | Origami fox companion, fine furniture |
| Metallic | Foil Shard | Crystal armor pieces, ornate lamps |
| Master | Prism Core | Master Helmet, Legendary Mount |

A recipe's tier is set by its originator at creation time and is fixed. Higher-tier recipes are inherently rarer in the catalog because authoring them requires deep mining (you need that tier's ore even to create).

---

## Free LLM Creates & Robux

LLM calls cost real money. Free Creates and Robux are the only mechanism that bounds the bill.

### Free Create Slots (lifetime, per player)

| When earned | Reward |
|---|---|
| Hit the 10-minute mark on your first session | 1 Free Create |
| Play 20 minutes with a Roblox friend in the same server | 1 Free Create |
| Play with a Roblox friend on 5 different calendar days | 1 Free Create |

**Lifetime free total: 3.** Solo players get 1 (the 10-minute one). The other two are designed to encourage social play.

### Free Create Definitions
- **Roblox friend:** mutual friends-list connection at the platform level
- **Same server:** both in the same server instance for the qualifying time
- **5 different days:** 5 distinct UTC calendar days with at least 15 minutes of co-server time. Doesn't have to be the same friend.

### First Creation: Constrained to a Companion Creature
The 10-minute Free Create is **locked to the creature category**. The player ends the tutorial with a companion creature they prompted themselves — a perfect emotional anchor and a high-success-rate first impression.

### Robux SKUs

| SKU | Robux | Per-creation cost |
|---|---|---|
| Single creation | 25 | 25 |
| 5-pack creations | 100 | 20 (16% off) |
| 12-pack creations | 200 | ~17 (33% off) |

Pricing tunable post-launch based on actual LLM cost per category.

### What Robux Cannot Buy
- Mining shortcuts of any kind
- Materials of any tier
- Higher tool tiers
- Any time-skip on progression

**Robux only buys LLM throughput.** Power-skipping is not for sale.

### LLM Cost Sanity Check
- 1 LLM call (flash_lite default): ~$0.001
- Tutorial creation: 1 per new player, ~$0.001 each
- Per-active-player monthly LLM cost: ~$0.003–$0.05 (3–10 creates)
- 10,000 active monthly players: ~$30–$500/month, well within Robux dev-share margin

---

## Creature System

Creatures are the centerpiece of the LLM creative brush — every player's first Free Create is a creature. They give the world life and provide a small ambient utility loop.

### How You Get Creatures
- **First creature:** the 10-minute Free Create, constrained to creature category
- **Egg drops:** while mining, deeper layers occasionally drop a **creature egg** as a rare ore-pocket variant. Each egg is themed by the layer it came from (a Crystal Lattice egg rolls a crystalline creature). Hatching an egg costs a Free Create slot or Robux + the egg's stored materials.
- **Browse:** any creature recipe in the catalog is summonable with the appropriate ore + bulk

### What Creatures Do
- **One active companion follows you.** Provides a small ambient perk based on its kind — faster digging, ore-detection sparkle, a small light source, slightly farther reach. Light enough that not having one is never a punishment.
- **Other creatures live on your plot.** Decorative and ambient. A few kinds (a moss sheep, a tea-leaf turtle) passively produce trace amounts of materials over time, giving idle play a small payoff without becoming a grind engine.
- **All creatures are persistent and named by the player.** They cannot die, cannot be taken, cannot be diminished by other players.

### Creature Properties
- **Category:** creature (origami-style folded model)
- **Locomotion:** walk, slither, fly, float, hop, stationary (LLM picks based on prompt)
- **Companion perk:** small ambient effect derived from kind
- **No HP, no stats, no combat properties.** This is not a battle pet.

### Naming
Players name their creatures at hatch/create time. The name is permanent and visible to anyone who encounters the creature. Names persist forever.

---

## Surface Plots

Each player can claim one surface plot.

- **Size:** 8x8 chunks (128x128 blocks)
- **Build:** place mined blocks to make any structure you want
- **Place creatures:** display your collection
- **Place summoned items:** decorate with anything from the catalog
- **Visit other players' plots:** read their style, summon copies of their recipes
- **Plots are sacred:** no other player can damage, alter, or remove anything on your plot

The plot is the player's permanent showcase — the museum of their taste in the world.

---

## Multiplayer

The game is multiplayer-first but contact is gentle and asynchronous. Players are **fellow expeditioners**, not adversaries.

### Architecture: Shared Surface, Private Persistent Mines

| Zone | Sharing model | Persistence |
|---|---|---|
| **Surface (commons + plots)** | Shared across the ~30-player Roblox server instance | Plots are persistent per player; loaded into whatever instance you join |
| **Personal mine** | Private per player; friends can be invited in via "Mine With Me" | Persistent forever, every dug tunnel stays carved across sessions |
| **Catalog (recipes)** | Global, backed by origami-server | Every recipe ever authored is summonable from any instance |

### Session flow
1. Spawn into a Roblox server instance. Up to ~30 other players visible at the shared surface commons.
2. Plots load around the commons — friends first, then players currently in the instance, then a sprinkling of featured plots for ambient density.
3. Visit plots, browse the catalog, summon items, decorate your own plot.
4. Descend below ground → enter **your personal mine** (instanced, persistent, exactly as you left it).
5. Invite a friend in via "Mine With Me." They keep their own inventory but mine your terrain. Drops go to whoever broke the block.
6. Going back up returns you to the surface commons.

### What persists where

| Data | Storage | Scope |
|---|---|---|
| Inventory, materials, free creates, tools | DataStore per player | Follows you to any server |
| Your plot (blocks, placed items, creatures) | DataStore per player | Loaded into your current instance |
| Your mine (every block broken, tunnels, claims) | DataStore per player | Persistent forever, only visible to you + invited friends |
| Recipes / catalog | origami-server backend | Global, queryable from any instance |
| Stats, achievement counters | DataStore per player | Follows you |

### What strangers can / can't do

| Action | Can do? |
|---|---|
| See your plot from outside | ✅ |
| Walk into your plot | ✅ |
| Summon copies of your authored recipes | ✅ |
| Tap items on your plot to inspect them | ✅ |
| Leave a small "stone" trace beside something they admired | ✅ |
| Damage a block on your plot | ❌ |
| Take an item from your plot | ❌ |
| Enter your mine | ❌ (unless invited) |
| Take materials/ores from you | ❌ |

### Friend-Session Tracking (for Free Creates)
Implemented by `FriendSessionService` server-side:
- On Roblox-friend co-presence in the same instance, accumulate co-time
- 20 min in same instance with a friend → award Free Create #2 (one-time)
- 5 distinct UTC days with ≥15 min co-time → award Free Create #3 (one-time)
- Anti-AFK-farm: minimum activity threshold per session, server-validated

### The Asynchronous-Ghosts Feel
Even though direct PvP / griefing / theft is impossible, multiplayer still feels alive because:
- Plots are everywhere on the shared surface — every plot is someone's voice
- The catalog is a giant, constantly-growing social artifact
- Originator names appear on every summoned copy
- "Times your recipes have been summoned" counter ticks up while you're offline
- Friends can teleport into your mine via TeleportService

Multiplayer feels like **witness and trace**, not raid and trade.

### What Cannot Happen
- **No PvP.** No combat between players.
- **No griefing.** Strangers cannot break, take, or alter anything you've built.
- **No theft.** Materials and recipes are personal.
- **No marketplace, no auctions, no gifting** (v1; controlled gifting may return later).

### What Can Happen
- Visit other players' plots
- Summon copies of recipes others have authored
- Invite friends into your mine
- Play with friends in the same server (earns Free Creates)
- See "X copies of your recipes summoned" counters on your profile

### Trade-off
**No shared deep mining (v1).** You won't bump into a stranger 200 layers deep — the cost of persistent personal mines is solitude in the depths. Mitigation later: **Outposts** (Phase 6) can introduce *shared* deep zones where the asynchronous-ghosts feel reaches its purest form. Deferred from launch.

---

## Economy

**Two currencies. Two jobs. No overlap.**

| Currency | Earned how | Spent on |
|---|---|---|
| **Materials** (bulk + ore) | Mining, exploration, pet production, achievements | Summoning recipes, building, crafting tools |
| **Robux** | Real money | LLM creations after the 3 Free Creates are spent |

That's it. **Cranes are removed. Folds are removed.** No abstract earned currency — materials are concrete, materials are the wallet.

The third "currency" tracked on the HUD is **Free Create slots remaining** (0–3). Not a currency — a non-tradable lifetime allowance.

### Records (non-currency stat counters)
For dopamine without economy bloat, the player profile tracks read-only stats:
- Total blocks mined
- Total recipes summoned
- Total recipes authored (with originator credits visible)
- Days played
- Plot square-footage
- Times others have summoned your recipes
- Layers reached

These count up forever, never spent. They scratch the "number go up" itch without polluting the wallet.

### Sinks
- Bulk consumed by building (placed blocks come from inventory)
- Bulk + ore consumed by summoning
- Bulk + ore consumed by creating (in addition to the Free Create slot or Robux)

### Sources
- Mining (primary, unlimited)
- Pet passive production (small amounts of mid-tier materials)
- Achievements / discoveries (small bonus drops, never abstract currency)
- Daily login (a small bag of low-tier materials)

---

## Onboarding (10-Minute Hook)

The most important moment in the game. The new player must:

1. **Spawn into a world full of other players' creations.** They walk around amazed at what's possible. (Costs us $0 — pure atmospheric hook.)
2. **Mine for ~10 minutes** in Paper Fields. Learn movement, mining, placing.
3. **Discover an Inkdrop ore pocket.** First treasure.
4. **Find the Workbench.** It glows. UI prompt: *"Tell me what to fold — your first companion creature."*
5. **Type a prompt.** Wait 5–15 seconds. Watch their creature fold in front of them.
6. **Name the creature.** It's theirs. Permanent. It follows them.

That's the magic moment. Done well, it converts the player. Done poorly, they bounce. This is the single highest-leverage UX in the game.

---

## Future Considerations (deferred from v1)

These remain interesting but are cut for scope:

- **Breeding** — combine two creatures' themes for a new egg
- **Evolution / fold tiers** — feed materials over time to evolve a creature
- **Trading / gifting** — controlled mechanic for material/recipe exchange
- **Bosses** — opt-in summonable challenges (Ender Dragon style)
- **Combat** — gentle paper-vs-paper interactions if/when added
- **Outposts** — claimable shared territory in the deep mines
- **Multiplayer creature interactions** — pets meeting other pets

None of these gate v1 launch.

---

## Technical Architecture

### Server Services
- **WorldService**: Chunk lifecycle, block state, persistence
- **ChunkStreamService**: Position-based chunk streaming
- **SpawnService**: Surface spawn point management
- **MiningService**: Mining validation, drops (bulk + ore), tool management
- **PlayerDataService**: Inventory, free creates, stats, tools
- **OrigamiService**: LLM text-to-model endpoint
- **WorkshopService**: Browse + Create UI handling
- **CatalogService**: Public recipe storage, search, originator attribution
- **PlotService**: Surface plot claiming and building
- **CreatureService**: Creature behavior, hatching, naming, companion perks
- **BlockPlacementService**: Placing blocks from inventory
- **FriendSessionService**: Tracks co-server time with Roblox friends for Free Create awards

### Client Controllers
- **ChunkRenderController**: Terrain rendering, part pooling (greedy/EditableMesh paths in flight)
- **MiningController**: Input handling, raycasting, visual feedback
- **CreatorController**: Browse + Create UI
- **CompanionController**: Active pet rendering, follow behavior, ambient perks

### Shared Modules
- **BlockType**: Block ID enum
- **ChunkUtil**: Coordinate conversion helpers
- **ChunkSerializer**: RLE compression for chunks
- **BlockRegistry**: Block properties and drop tables
- **MaterialTiers**: Bulk + ore mapping per layer, tier definitions
- **RecipeRegistry**: Recipe schema, originator attribution, tier metadata
- **ToolRegistry**: Tool tier definitions
- **WorldGenModule**: Procedural terrain generation
- **OreVeinPlacement**: Pocket distribution within layer geology

### Retired (cut from earlier drafts)
- **EggCraftingService** — eggs are mined as ore-pocket variants, not crafted
- **BreedingService** — cut for v1

---

## Phase Plan

These phases run roughly in parallel; v1 launch requires Phase 1–4.

### Phase 1: Voxel World + Mining
- Chunk system, 7 layers, tool tiers, **bulk + ore drops**, ore pockets

### Phase 2: Browse + Catalog
- Recipe storage, originator attribution, public catalog UI, Browse → summon flow, material-quality finish system

### Phase 3: Create + Free Creates
- Workbench UI, Free Create slot tracking, Robux SKU integration, friend-session tracking
- Constrained first creation (companion creature)

### Phase 4: Plots + Multiplayer Visibility
- Plot claiming, persistent saves, plot visiting, "summoned by X others" counters, surface town commons

### Phase 5: Polish + Content
- Companion perk variety, more block types, more ore types if needed
- Achievements, daily login, public stats display
- Sound and VFX polish

### Phase 6 (later): Future Considerations
- Breeding, evolution, bosses, outposts, controlled gifting/trading

---

## Open Questions Worth Pinning Later

These are not blockers for v1, but worth a decision when relevant:

- **Companion perk balance:** how strong should ambient perks be? (Current default: small enough that not having a pet is never a punishment.)
- **Daily login bag size:** how much material is appropriate to keep dailies a treat without making mining redundant?
- **Catalog discovery:** how do new players find good recipes? (Suggestion: featured shelf curated by play stats; "newly authored" shelf; per-category top-of-week.)
- **Friend-session anti-cheat:** how do we prevent friend-pair AFK farms from ticking up "5 days with friend"? (Suggestion: require minimum activity per session, not just presence.)
- **Originator showcasing:** should authored recipes show up on the originator's plot automatically as little display tags?
