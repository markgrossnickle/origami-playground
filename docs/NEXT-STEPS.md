# Origami Expedition — Next Steps Review

*End-to-end review by Claude Fable, 2026-07-11. Snapshot at v1.0.93 (426 commits since 2026-03-11). Read-only review; nothing in the codebase was changed.*

---

## ASSESSMENT

**What it is.** A cozy Minecraft-style voxel mining-and-building sandbox on a floating paper island, distinguished by an LLM "creative brush": players prompt one-of-a-kind origami creatures/props/tools, and (per the GDD) those creations become recipes in a public catalog others can summon with mined materials. Roblox Luau on Knit, external `origami-server` backend (Fly.io) for LLM generation and the catalog, GitHub Actions auto-publish to Roblox on push to `main`.

**Current state: two games stacked on each other.** The post-pivot **mining sandbox is genuinely strong** — GDD Phases 1 and 4 are substantially done and well-engineered:

- 7 depth layers with bulk+ore drops, ore veins (3–8 blocks), tool-tier gating, zone-skewed ore density (`BiomeConfig`, `MaterialTiers`, `MiningService`)
- Weekly Wilds reset that is genuinely cross-shard: atomic `UpdateAsync` election + MessagingService broadcast (`WildsService.luau`)
- Portable player Regions on session-locked ProfileStore with per-server slot leasing, oldest-vacated reuse, visitor edit-protection (`RegionContentService`, `RegionService`, `ZonePermissions`)
- Return to Base, world map, minimap, region HUD/toasts, milestone analytics funnel
- Perf discipline throughout (pooled parts, batched 10Hz block updates, RLE chunks, throttled raycasts)

Meanwhile the **pre-pivot "creative brush" prototype is half-retired but still loaded**: a persistent Creator sidebar, an orphaned GameMode system, Cranes/Folds currencies, breeding/egg-crafting with combat stats, shopkeeper NPCs (spawning disabled). It contributes most of the dead weight and UX confusion.

**Launch-ready? No — but closer than it looks.** The blockers are concentrated, not diffuse:

1. **GDD Phases 2–3 (Browse/Catalog + Free Creates) are essentially not built.** These are the game's differentiator *and* its entire monetization *and* the mechanism that bounds the LLM bill. Today every Workshop craft is a live LLM call, there is no recipe reuse, no originator attribution, no Free Create slots, and no purchasable create packs.
2. **A progression-blocking bug**: tools above Cardboard Pick cannot be crafted (see Feedback #1), so no player can legitimately mine below layer 2. The core loop dead-ends ~30 minutes in.
3. **Onboarding does not exist** — the GDD's 10-minute hook is measured (MilestoneService) but not driven by anything.
4. **Monetization is at zero**: every product ID is a placeholder `0`.

**Biggest strengths.** World/persistence tech (the cross-shard reset and portable-region architecture are the hard parts, and they're done right); clean green CI (selene, stylua, 72 Lune tests); a thoughtful locked GDD; cheap LLM cost model (~$0.001/call via flash_lite).

**Biggest risks.** LLM spend is ungated server-side (exploitable cost exposure on a live endpoint); a live API key is committed to git; ~29% of the 55K-line tree is confirmed dead code; retention risk from zero onboarding + a loop that hard-blocks at tier 2.

---

## FEEDBACK

### Bugs and exposure (fix before anything else)

1. **Tier-2+ tool crafting is broken.** `MiningService.luau:456-465` (`CraftTool`) reads and deducts *every* recipe ingredient from the `bulk` inventory namespace, but tier-2+ recipes require ore (`clay_bead`, `quartz`, … per `ToolRegistry.luau:45-75`), which is stored under the `ore` namespace. Ore reads always return 0 → only `cardboard_pick` is craftable. **Progression stops at Pulp Caverns for every player.**
2. **LLM spend has no server-side gate.** `OrigamiService.Client:RequestModel` (`OrigamiService.luau:65-160`) calls the backend unconditionally; `checkRateLimit` (`:48-63`) is defined but never called; `WorkshopService.CraftItem` (`WorkshopService.luau:300,345`) fires an LLM call per craft with no currency/credit check. All gating (Paper deduction, ProCreation credit) lives client-side in `CreatorController` — bypassable by any exploiter, and the bill is yours.
3. **Live API key committed to git.** `src/ServerStorage/Configuration/Server.luau:5` holds the (recently rotated) key in plaintext, tracked in HEAD. The move out of ReplicatedStorage fixed client exposure, but the secret is still in version control with no `HttpService:GetSecret`/env fallback.
4. **Latent crash path**: `PlotController/init.luau:456` calls `Knit.GetService("PlotService")`, but PlotService lives in `Services/_deprecated/` and is never registered — throws if the (Phase-2-hidden) claim button path ever executes.
5. **Failed world saves are silently dropped.** `WorldService/init.luau:629-677` snapshot-and-clears dirty regions before saving; a failed `SetAsync` (`:175-179`, warn only) does not re-mark the region dirty, so the data survives only in memory until the next edit — a crash loses it. No retry/backoff anywhere in the global save path.
6. **Ore drop rates are untuned dead config.** The per-block `chance` guard at `WorldGenModule.luau:566` (`rng() > chance * 10`) is effectively always true; density is governed solely by `veinsPerChunk`, so the GDD's 3%/1.5%/0.5% targets are not what ships.

### GDD divergence (the design pivot never landed in code)

7. **No recipe model.** No `CatalogService`; Browse is a thin HTTP fetch (`OrigamiService.luau:570-654`) with no originator attribution, summon counts, or author profiles anywhere. `WorkshopService` is a static 24-recipe crafting table where every craft is a fresh LLM call — the exact opposite of the GDD's "Browse = execute stored part data, no LLM call". Material quality does not affect output finish.
8. **No Free Creates.** No slot counter in `PlayerData` (`Template.luau`), none of the 3 earn paths, and `FriendSessionService` does not exist. `MilestoneService` records the funnel but grants nothing.
9. **Removed currencies still live.** `Folds`, `Cranes`, `Paper`, template `Coins`/`Gems` all persist in `Template.luau:7-77`; Cmdr commands, `GetCurrency`, and `BreedingService` (charges Cranes) still use them. Browse summon cost is commented out (`CreatorController/init.luau:2755-2757`) — summoning is currently free. Daily rewards grant Paper/Coins/Gems (`MonetizationConfig.DailyRewards`), not the GDD's material bag — and `DailyRewardController` is disabled anyway (`:269`).
10. **GDD-cut systems are live.** `EggCraftingService`, `BreedingService` (8h hatch, mutations), and creature combat stats `{hp, atk, def, spd}` (`CreatureService.luau:20-32`) are all registered and reachable via BackpackController — contradicting "retired / cut for v1 / no HP, no stats".
11. **Missing GDD v1 items**: Wilds auto-return of placed creatures/items at reset (`WildsService.luau:26-28`, explicitly unimplemented); `WorldDecorService` stubbed off (`:64-66`); shopkeeper spawning disabled (`ShopKeeperService.luau:18-20`); visitor "ghost collision" not found server-side; no recipe tiers or tint-by-material.

### Monetization & retention

12. **Every Robux ID is `0`** (`MonetizationConfig.luau:28-42`, `OrigamiConfig.luau:91`). The GDD's 25/100/200 create packs don't exist — only a single unpriced `ProCreation` handler plus leftover template coin packs. Revenue is currently impossible.
13. **No onboarding flow at all.** No tutorial, hints, or first-session sequence (clean grep). The Workshop — the magic moment — is buried as a tab inside the 📦 Backpack panel; a new player has no reason to open it. No workbench glow, no constrained creature-first create, and the naming step exists only as a generic rename.

### UX / cross-platform

14. **Primary crafting UI is not console-usable**: `BackpackController/init.luau` (10×) and `WorkshopTab.luau` (8×) use `MouseButton1Click`, which never fires for gamepad — CLAUDE.md mandates `.Activated`.
15. **Mobile players cannot open the shop**: `ShopController:485-493` binds only `B` / `ButtonY`, no touch button.
16. **Two UX paradigms fight on screen**: the vestigial Creator sidebar (default `GameMode = "sandbox"`) overlaps the live Backpack UI with hand-tuned offsets (`CreatorController:666-667`); per-controller copy-pasted `COLORS` tables mean no consistent theme.

### Tech debt

17. **~15.9K lines (~29%) confirmed dead**: `CompetitionData.luau` (11,971) + `CompetitionGrid`, the DemoShowcase cluster (~2,945), `ShopKeepers.luau`, `_deprecated/PlotService` + `PlotConfig`. Orphaned controllers: GameModeController (bar never shown), PlayController (mode `"play"` doesn't exist), AnimatorController, EditController, PlotController (822 lines), DailyRewardController (no-op).
18. **Tests are green but shallow**: 72 passing Lune tests cover config tables only; zero coverage of WorldService, MiningService, OrigamiService, WorkshopService, or region persistence — the riskiest code.
19. **Publish isn't gated**: `publish.yml` runs lint/test with `continue-on-error: true`, so broken code ships to Roblox; `analyze.yml` duplicates `ci.yml`.
20. **Perf nits**: `MinimapController:361/:247` runs unthrottled per-frame slot loops with string allocs; `WorldService._saveRegion` (`init.luau:704-718`) is O(dirty × all saved chunks).
21. **Docs drift**: GDD says both 25×25 and 18×18 for region size (code = 18×18); `docs/ABILITIES_SYSTEM.md` is design-only with zero implementation; PR #10 is open but superseded by merged #13.

---

## NEXT STEPS

Prioritized; effort is S (≤1 day), M (2–5 days), L (1–3 weeks).

### P0 — Unblock the loop, stop the bleeding (do first, all S)

1. **Fix the tool-crafting namespace bug** (S) — read ore ingredients from the `ore` namespace in `MiningService.CraftTool`. Without this, no player ever sees layers 3–7; every other investment is wasted. Add a Lune test for the recipe→namespace mapping.
2. **Gate LLM spend server-side** (S) — call `checkRateLimit` in `RequestModel`, and require a server-verified charge (Paper/credit/free-create) before any backend call, including `WorkshopService.CraftItem`. Today an exploiter can drain the LLM budget from the client.
3. **Get the API key out of git** (S) — move to `HttpService:GetSecret` (or a gitignored override file), rotate the key a second time, and scrub it going forward.
4. **Make publish gate on CI** (S) — remove `continue-on-error` from `publish.yml`'s lint/test job (or make `publish` depend on the CI workflow); merge `analyze.yml` into `ci.yml`. Close or rebase stale PR #10.

### P1 — Build the game the GDD describes (launch-critical)

5. **Phase 2: real Browse/Catalog** (L) — store the LLM's part data as recipes on origami-server; Browse executes stored data with **no LLM call**, charges bulk+ore server-side, and shows originator attribution + summon counts. This is the differentiator, the social reward, and the thing that turns LLM cost from per-craft to per-create. Retire `WorkshopConfig`'s static-recipes-that-call-the-LLM model.
6. **Phase 3: Free Creates + Robux SKUs** (M) — `FreeCreates` counter in `PlayerData`; award #1 from the existing MilestoneService 10-minute event; new `FriendSessionService` for awards #2–3; real developer products for 25/100/200 create packs with server-side credit consumption. Revenue is impossible until this lands.
7. **Build the 10-minute onboarding hook** (M) — first-session flow: spawn at Hearth, guided "mine your first block" prompt, ore-discovery beat, glowing Workbench with the "fold your first companion" prompt, creature-constrained first create, naming ceremony. MilestoneService already measures every step of this funnel — it just needs the experience in front of it. Highest-leverage retention work in the project.
8. **Economy cleanup to match the GDD** (M) — delete `Folds`/`Cranes`/`Coins`/`Gems` from `PlayerData` and all plumbing (Cmdr, GetCurrency, BreedingService); re-enable summon costs against materials; daily reward = small low-tier material bag. Decide the fate of Breeding/EggCrafting/combat stats — recommendation: flag them off for v1 (GDD already cut them) rather than delete, since the code is substantial and Phase-6-adjacent.

### P2 — Quality, durability, reach

9. **Delete the dead ~16K lines** (M) — Competition cluster, DemoShowcase cluster, ShopKeepers, `_deprecated/PlotService` + PlotConfig, and the orphaned GameMode/Play/Animator/Edit/Plot/DailyReward controllers (including the `GetService("PlotService")` crash path). Cuts the tree ~29% with zero behavior change and removes the sidebar/Backpack UI collision.
10. **Console/mobile pass on the live UI** (S/M) — convert BackpackController/WorkshopTab to `.Activated`; add a touch button for the shop; audit the CLAUDE.md cross-platform checklist against the surviving controllers.
11. **Persistence hardening** (S) — re-mark regions dirty on failed `SetAsync` with retry/backoff; add a per-region index of `savedDeltas` to kill the quadratic save scan.
12. **Wilds reset completeness** (M) — auto-return placed creatures/items to owner inventories before reset; countdown/ceremony UI ("Wilds refresh in 14h" → "Fresh ore!"). The cross-shard reset machinery is already done; this is the player-facing half.
13. **Tune ore rates** (S) — remove or fix the dead `chance` field in `WorldGenModule.luau:566` and tune `veinsPerChunk` toward the GDD's per-layer targets; add Cmdr commands to inspect drop-rate telemetry.

### P3 — Polish and content (post-loop-completion)

14. **Visual/theme unification** (M) — shared UI theme module (colors, fonts, sizes) replacing per-controller COLORS tables; real icons instead of emoji glyphs.
15. **World life** (M) — re-enable WorldDecorService (cave mushrooms, surface decor); Hearth build-out with signage and the region map portal.
16. **Records & discovery** (M) — read-only stat counters (blocks mined, recipes authored, "summoned by X others"), catalog featured/new shelves. Cheap "number go up" retention per the GDD.
17. **Test the risky code** (M, ongoing) — Lune specs for MiningService drops/crafting, ChunkSerializer round-trip, RegionContentService encode/decode, ZonePermissions matrix.

### Suggested launch gate

Public launch when: P0 all done; Browse works without LLM calls and Create consumes a server-verified Free Create or Robux credit; the onboarding flow lands a first companion creature; removed currencies are gone; and one full week of Wilds reset has run clean in a staging universe.
