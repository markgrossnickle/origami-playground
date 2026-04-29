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

1. **Mine in The Wilds** — go out to the shared zones, break blocks for bulk materials and ore. First-break wins drops.
2. **Summon** — spend bulk + ore to summon a recipe from the public catalog (no LLM call).
3. **Build / Decorate in your Region** — return to your personal Region (your kingdom on the island) and use materials to build structures and place summoned items.
4. **Create (rare)** — when you have a Free Create slot or Robux, spend bulk + ore + a Create to author a brand-new recipe (LLM call). Your name goes on it forever.
5. **Visit** — wander into other players' Regions to see their work. View-only — no breaking, placing, or interfering.
6. **Anticipate the weekly reset** — The Wilds refresh every week. Ore respawns. Pre-reset hours are charged. Post-reset hours are an ore rush.

Same as Minecraft in spirit, plus the LLM brush, plus the Region/Wilds split. No mandatory progression, no end-game.

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

### One Big Island
- The world is a single huge paper island floating in a void.
- Bounded horizontally — does NOT generate infinitely outward. The island has edges.
- Vertically, 7 depth layers extending to Y=-2000.
- Surface: gentle origami paper hills (FBM heightmap, max ~20 studs elevation). Other surface biome experiments (sunset mesa, forest, etc.) didn't work out and aren't in play. Caves underground feature occasional neon mushroom decorations.

### Three Zones On The Island
The island is divided into three persistent zone types:

1. **The Hearth** — a permanent dev-curated commons at the world's center. Spawn point for new players. Has signage, tutorial elements, the Workbench, and a portal mechanic ("Return to Base"). Cannot be modified by anyone.
2. **Regions** — personal player-owned zones scattered across the island (see **Regions** section). Each player gets one. 25×25 surface chunks, full vertical depth.
3. **The Wilds** — everything between The Hearth and Regions. Shared, contested, mineable. Where multiplayer encounter happens. Resets weekly.

Players spawn at The Hearth on first play, are auto-assigned a Region somewhere on the island, and travel through The Wilds for adventure and mining.

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

### Where Ore Lives — Mostly The Wilds
Ore distribution is heavily skewed by zone, by design:

| Zone | Ore density | Player intent |
|---|---|---|
| **Your Region** | Very sparse — minimal Tier 1, almost nothing higher | Building, decorating, customizing |
| **The Wilds** | Full distribution — all 7 tiers at standard rates | Mining, ore hunting, encountering others |
| **The Hearth** | None — protected zone | Tutorial, gathering, traveling |

This makes Regions the **building/customization** zone and The Wilds the **mining adventure** zone. You leave home to gather; you return home to make.

### Ore Pocket Distribution (in The Wilds)
- **Pocket spawning:** rare clusters of 3–8 ore-bearing blocks within bulk material, like Minecraft veins
- **Visual:** ore pockets glow faintly through surrounding bulk so players see them embedded in walls
- **Drop rate (rough starting points, tunable):**
  - Tier 1 ore (Inkdrop): ~3% of blocks at depth 0 to -80
  - Tier 4 ore (Gem Fragment): ~1.5% of blocks at depth -480 to -800
  - Tier 7 ore (Prism Core): ~0.5% of blocks at depth -1600 to -2000
- **In Regions:** ore pockets exist but at perhaps 10% the density — you can find a little Inkdrop in your own backyard, but for serious mining you go to The Wilds.

### Wilds Reset
Every week (proposed: Sunday morning UTC), The Wilds refresh:
- All bulk and ore broken in The Wilds is restored to base terrain
- All blocks placed in The Wilds by players are removed
- Ore pockets respawn at their original positions
- Pre-reset countdown is visible to all players ("Wilds refresh in 14 hours")

This is reframed as a **scheduled world event**, not regen. Players plan around it. Ore rushes happen post-reset; cleanup happens pre-reset (don't leave anything in The Wilds you want to keep).

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
- **Other creatures live in your Region.** Decorative and ambient. A few kinds (a moss sheep, a tea-leaf turtle) passively produce trace amounts of materials over time, giving idle play a small payoff without becoming a grind engine.
- **All creatures are persistent and named by the player.** They cannot die, cannot be taken, cannot be diminished by other players.

### Creature Properties
- **Category:** creature (origami-style folded model)
- **Locomotion:** walk, slither, fly, float, hop, stationary (LLM picks based on prompt)
- **Companion perk:** small ambient effect derived from kind
- **No HP, no stats, no combat properties.** This is not a battle pet.

### Naming
Players name their creatures at hatch/create time. The name is permanent and visible to anyone who encounters the creature. Names persist forever.

---

## Regions

Every player owns a **Region** — a vertical column of the island that is theirs alone.

### Geometry
- **Size:** 25×25 surface chunks (400×400 blocks)
- **Depth:** full vertical column from sky to The Core (Y=0 to Y=-2000)
- **Layout:** Regions are scattered across the island with The Wilds between them
- **Quantity:** the island holds a fixed number of Region slots, distributed across its area

### Ownership
- **Auto-assigned** to a player on their first session — randomly placed in an open slot
- **Persistent forever** while the owner is active
- **Loads with the owner** to whatever Roblox shard they join (Region chunks live in player's DataStore)
- **One Region per player.** No multiple plots, no transfers (yet — could be a Robux-priced "move my Region" SKU later)

### Region Lifecycle (the cycling problem)
- A Region whose owner has been **inactive for 6 months** is marked **Dormant**: still visible, but flagged
- After **12 months total inactivity**, a Dormant Region becomes **Reclaimable**: a new player joining the world can be assigned to it
- When reclaimed, the previous owner's *physical* content is cleared (their structures wipe, the Region resets to procedural base state)
- The previous owner's *authored recipes* stay in the public catalog forever — creative legacy is preserved even if their physical Region is recycled
- Communicated transparently: "your Region will be Dormant in X days unless you log in"

### Inside Your Region — What You Can Do
- Build any structures with mined materials (this is the *primary* purpose of your Region)
- Mine the small amount of ore that exists in your column (mostly Tier 1, sparse)
- Place creatures (display, hosting, ambient)
- Place summoned items from the catalog
- Decorate freely — this is where customization lives
- Host friends (they can visit, but cannot modify)

### Inside Your Region — What Visitors Can / Can't Do

| Action | Visitor allowed? |
|---|---|
| Walk freely through your Region | ✅ |
| Inspect your placed items, read attribution | ✅ |
| Summon copies of recipes from items they see | ✅ |
| Leave a small "stone" emote / trace beside something | ✅ |
| Break or place a block | ❌ |
| Dig | ❌ |
| Block your movement / "bully" with their body | ❌ (player-collision disabled in non-owner Regions; visitors can pass through everyone) |
| Take, modify, or damage anything | ❌ |
| Take ore from your Region | ❌ |

**No bullying.** Specifically, visitor-vs-owner physical collision is disabled inside a Region. Visitors are ghosts; they cannot trap, push, or block the owner.

### Return to Base
A **"Return to Base"** button is always available in the UI. Pressing it teleports the player to their Region's spawn point. Used to:
- Escape if stuck in The Wilds
- Bail out of someone else's Region (if they got lost)
- Quick travel home to deposit materials

The button has no cooldown (or a very short one to prevent spam). Players cannot be trapped in this game.

---

## The Wilds

The Wilds are everywhere on the island that isn't a Region or The Hearth. They're the **shared, contested, mineable open world**.

### What The Wilds Are For
- **Mining ore** at full distribution density — the primary mining destination
- **Encountering other players** — the only place strangers actually mine alongside you
- **First-break-wins** — when you and a stranger race for the same vein, whoever lands the killing blow gets the drops
- **Building temporary stuff** — anyone can place blocks in The Wilds, knowing it wipes weekly. Outposts, signs, lanterns at forks, ramps.

### What's Allowed in The Wilds
- ✅ Mining (anyone, anywhere, all 7 layers)
- ✅ Placing blocks (anyone, knowing they'll wipe at reset)
- ✅ Building temporary structures (outposts, paths, scaffolds — wipe at reset)
- ⚠️ Placing creatures: **discouraged** — creatures left in The Wilds at reset time auto-return to the owner's inventory (no permanent loss)
- ⚠️ Placing summoned items: **same rule** — auto-return to inventory at reset

Permanent stuff lives in your Region. The Wilds are for activity.

### What Cannot Happen in The Wilds
- No PvP, no combat between players
- No theft from inventories
- No trapping (Return to Base button always works)

### Weekly Reset
Every week (proposed: Sunday morning UTC):
- All bulk and ore broken in The Wilds is restored to base terrain
- All blocks placed in The Wilds are removed
- Ore pockets respawn at their original positions
- Player-placed creatures and items in The Wilds auto-return to owner inventories before reset
- Pre-reset countdown visible to all players

This isn't "regeneration" — it's a **scheduled world event** with anticipation, rushes, and rhythm. Players plan their week around it.

---

## The Hearth

The Hearth is a permanent dev-curated public commons at the center of the island.

- **Cannot be modified by any player** — fixed terrain, fixed structures
- **Spawn point for new players** on their first session
- **Has the Workbench** (the LLM-creation altar)
- **Has the catalog Browse interface**
- **Tutorial signage and onboarding flow**
- **Visible from many parts of the world** — a recognizable landmark
- **Houses the Region map** — players can see Region locations on a map and teleport to friends or visit other players' Regions

The Hearth is the only zone that survives forever and never changes. It anchors the world.

---

## Multiplayer

The game is multiplayer-first. Players share **one big island** with three zones (The Hearth, Regions, The Wilds) and a global recipe catalog.

### Server Topology
- **~16 players per Roblox shard** (smaller than the Roblox default — designed for intimacy, fewer strangers in a session, easier social cohesion). Tunable; could go up if too sparse, down if too crowded.
- Multiple shards run in parallel
- Each shard reads/writes the same persistent island data via shared DataStore + backend cache for The Wilds
- Region data is per-player and follows the player into any shard

### What Persists Where

| Data | Storage | Scope |
|---|---|---|
| Inventory, materials, Free Creates, tools | DataStore per player | Follows you to any shard |
| Your Region (all blocks, placed items, creatures) | DataStore per player | Loaded with you into any shard |
| The Wilds (current week's terrain edits) | Shard state, synced via backend | Resets weekly across all shards |
| The Hearth | Static, baked into game data | Never changes |
| Recipe catalog | origami-server backend | Global, queryable from any shard |
| Stats, achievement counters, Free-Create progress | DataStore per player | Follows you |
| Region ownership map (who owns which slot) | Backend index | Global authoritative source |

### Session Flow
1. Open the game. Roblox places you in a ~16-player shard.
2. **First session:** spawn at The Hearth. Tutorial. Auto-assigned a Region somewhere on the island. Travel to it via map portal.
3. **Subsequent sessions:** spawn at your Region's home point.
4. Mine in The Wilds, build in your Region, visit other Regions, gather at The Hearth.
5. **Return to Base** button always available — teleport home anytime, no cooldown (or short cooldown to prevent spam).
6. Logging out preserves all your Region work (DataStore). The Wilds keep ticking toward the next reset.

### What Strangers Can / Can't Do

| Action | Allowed? |
|---|---|
| See your Region on the world map | ✅ |
| Visit your Region (walk through) | ✅ |
| Summon copies of your authored recipes | ✅ |
| Leave a "stone" emote-trace beside something they admired | ✅ |
| Mine alongside you in The Wilds | ✅ |
| Place blocks in The Wilds (knowing they wipe at reset) | ✅ |
| Break/place blocks in your Region | ❌ |
| Block your movement (push, trap, body-block) anywhere | ❌ |
| Combat or PvP | ❌ |
| Take from your inventory | ❌ |
| Take ore from your Region | ❌ |

### No Bullying
Visitor-vs-owner physical collision is **disabled inside someone else's Region**. Visitors are functionally ghosts: they cannot trap, push, or body-block the owner or other visitors. They can only walk and admire.

### Friend-Session Tracking (for Free Creates)
Implemented by `FriendSessionService` server-side:
- On Roblox-friend co-presence in the same shard, accumulate co-time
- 20 min co-time → award Free Create #2 (one-time)
- 5 distinct UTC days with ≥15 min co-time → award Free Create #3 (one-time)
- Friends can request the same shard at join-time
- Anti-AFK-farm: minimum activity threshold per session, server-validated

### The Alive-World Feel
- The Wilds are visibly active — you walk in and see ore pockets being mined, signs left at forks, partial scaffolds being built before the reset
- Other players' Regions dot the surface — a constellation of personal kingdoms
- The world map shows recently-active Regions (a soft glow on Region tiles whose owners are online)
- The catalog grows constantly with new recipes; originators are credited on every copy
- The Hearth is a steady gathering point — new arrivals constantly cycle through

### What Cannot Happen
- **No PvP.** No combat between players.
- **No griefing.** Strangers cannot break/take/alter Region content.
- **No trapping.** Return to Base always works.
- **No theft.** Materials and recipes are personal.
- **No marketplace, no auctions, no gifting** (v1; controlled gifting may return later).

### Trade-offs Honestly Named
- **The Wilds reset weekly.** Outposts and structures built in The Wilds don't persist. This is deliberate — keeps The Wilds fresh, prevents depletion, creates rhythm. Permanent work belongs in your Region.
- **Bounded island, finite Region slots.** Inactive-region cycling (6 / 12 month timers) handles long-term churn. Authored recipes stay in the catalog forever even after a Region is reclaimed.
- **No shared persistent deep mining.** Within a week of The Wilds you can encounter other players' digs at depth, but resets clean it. Players who want permanent deep work do it inside their own Region's vertical column.

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
- Region square-footage built (number of blocks placed in your Region)
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
- **RegionService**: Region claiming, ownership, scattered placement, persistence, inactivity tracking, recycling
- **WildsService**: Wilds zone management, weekly reset orchestration, ore pocket regeneration, cross-shard sync
- **HearthService**: Static commons, spawn flow, world map, Return to Base teleport
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

### Phase 4: Regions + Wilds + Hearth
- Region claiming, 25×25-chunk vertical column allocation, scattered placement on the island
- Region persistence to per-player DataStore
- Region visiting (visit-only, no edit, no body-block)
- Return to Base teleport
- The Wilds zone definition and weekly reset infrastructure
- The Hearth fixed commons + spawn flow
- World map with recently-active glow on online-owner Regions
- Inactivity-based Region cycling (6/12-month timers)

### Phase 5: Polish + Content
- Companion perk variety, more block types, more ore types if needed
- Achievements, daily login, public stats display, "summoned by X others" counters
- Sound and VFX polish
- Wilds reset event ceremony (countdown timer, "fresh ore!" announcement)

### Phase 6 (later): Future Considerations
- Breeding, evolution, bosses, controlled gifting/trading
- Outposts (claimable persistent zones inside The Wilds — soft-claim mechanic)
- Region-to-Region neighbor invites (friends adjacent on the map)
- "Move my Region" Robux SKU

---

## Open Questions Worth Pinning Later

These are not blockers for v1, but worth a decision when relevant:

- **Server size tuning:** 16 is the proposal. May need to flex up/down based on testing — too small feels empty in The Wilds; too large feels chaotic.
- **Region size tuning:** 25×25 surface chunks is the proposal. May want smaller if too sparse, bigger if too cramped.
- **Wilds layout on the island:** how exactly are Regions arranged across the island? Grid, organic clusters, themed districts?
- **Companion perk balance:** how strong should ambient perks be? (Current default: small enough that not having a pet is never a punishment.)
- **Daily login bag size:** how much material is appropriate to keep dailies a treat without making mining redundant?
- **Catalog discovery:** how do new players find good recipes? (Suggestion: featured shelf curated by play stats; "newly authored" shelf; per-category top-of-week.)
- **Friend-session anti-cheat:** how do we prevent friend-pair AFK farms from ticking up "5 days with friend"? (Suggestion: require minimum activity per session, not just presence.)
- **Originator showcasing:** should authored recipes show up on the originator's Region automatically as little display tags?
- **Wilds reset day/time:** Sunday morning UTC is the proposal. Should we A/B-test alternatives based on player base time zones?
- **Region geometry shape:** square is simplest; could be hex tiles or organic blob shapes for visual variety.
- **Inactivity timers:** 6 months Dormant / 12 months Reclaimable is the proposal. Could be shorter (faster churn) or longer (more permanence).
