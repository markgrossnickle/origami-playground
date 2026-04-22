# EditableMesh Chunk Renderer — Design Doc

**Status**: proposed → implemented on branch `editable-mesh-renderer`
**Replaces**: `src/ReplicatedStorage/Client/Controllers/ChunkRenderController/init.luau` (1090 lines, 1–3 `BasePart`s per visible block)
**Target**: ~1 draw call per chunk instead of thousands of individual parts.

---

## Problem statement

The current renderer creates 1 `Part` (LOD 1) or 3 `Part`s (LOD 0) per visible block. With 16³ = 4096 blocks/chunk and ~19 near chunks in view, peak visible-surface blocks push **30,000+ parts** in the active pool. Every `.CFrame` / `.Color` / `.Size` write is a physics-broadphase event and a replication-style listener trigger. The hot path (`_makeLayerParts`, `_makeSimplePart`, `_renderChunk`) dominates a scan frame.

Roblox's `EditableMesh` lets us build geometry at runtime (vertices + triangles + per-vertex color/normal/UV) and render it through a single `MeshPart` — one draw call per chunk per material bucket, regardless of block count.

---

## Callers of the public API (grepped — do not break)

| Caller | Method used | Notes |
|---|---|---|
| `MiningController._raycastToBlock` | `ChunkRenderController:GetBlockAt(chunkKey, flatIndex)` | Walks toward camera to find outermost solid block |
| `MiningController._updateMining` | `ChunkRenderController:GetBlockAt(chunkKey, flatIndex)` | Per-frame while mining |
| `MiningController._updateHoverHighlight` | `ChunkRenderController:GetBlockAt(...)` | Mining highlight target |
| `HotbarController` (block placement) | `ChunkRenderController:GetBlockAt(...)` | Verify target is air before placing |
| `WorldService.ChunkData` subscriber | `ChunkData:Connect` (internal) | Subscription moved to new impl |
| `WorldService.ChunkUnload` subscriber | `ChunkUnload:Connect` (internal) | Subscription moved to new impl |
| `WorldService.BlockUpdate` subscriber | `BlockUpdate:Connect` (internal) | Subscription moved to new impl |
| `MiningController._raycastToBlock` | `workspace:FindFirstChild("ChunkRender")` | Raycasts into this folder — must exist |

**Preserved public API**:
- `ChunkRenderController:GetBlockAt(chunkKey, flatIndex): number`
- `ChunkRenderController:GetChunkBlocks(chunkKey): buffer?`
- `ChunkRenderController:GetActivePartCount(): number` (renamed intent: "active draw units", see below)
- `ChunkRenderController:GetPoolSize(): number`

**Preserved workspace structure**:
- `workspace.ChunkRender` folder (contains all chunk MeshParts and bouncy-block parts; raycasts still hit it)

---

## High-level approach

Each chunk becomes **N MeshParts**, one per (material bucket) used by the blocks in that chunk. Geometry is built on a CPU-side face-culled mesh and uploaded to an `EditableMesh`. A `MeshPart` created via `AssetService:CreateMeshPartAsync` wraps the mesh for rendering.

Structurally:

```
workspace.ChunkRender (Folder)
├── Chunk_<key>_Grass  (MeshPart, CanCollide=true, CanQuery=true)
├── Chunk_<key>_Neon   (MeshPart, CanCollide=true, CanQuery=true)
├── Chunk_<key>_Plastic (MeshPart, ...)
├── BouncyParts_<key>  (Folder with thin Parts keeping .Touched for MushroomCap/ShelfBracket)
└── ...
```

Each vertex carries a per-block color (via `SetVertexColor`). Sharing vertices between faces of the same material in the same chunk is allowed; when adjacent same-material blocks have different colors the vertex count roughly doubles (one vertex per face per corner) — acceptable.

### Face culling

Classic voxel neighbor check: a face is emitted only when the adjacent block (in-chunk) is Air. For blocks on the chunk boundary with **no neighbor-chunk data available**, we emit the face (conservative — matches the current renderer's `_isExposed` behavior at chunk edges). When neighbor chunk data is later loaded, the owning chunk is not rebuilt automatically (cost vs. benefit: boundary artifacts are tiny "extra faces" inside walls that are invisible anyway).

**TODO(verify-in-studio)**: measure whether re-rendering on neighbor arrival is worthwhile. For now we optimistically render full boundary faces.

---

## Design decisions

### 1. Collision: use MeshPart itself (no per-block collision parts)

**Choice**: the chunk MeshPart has `CanCollide = true` and `CanQuery = true`. `MiningController._raycastToBlock` already derives block coords from `result.Position` and `result.Normal` via `ChunkUtil.worldToChunk` + `ChunkUtil.worldToFlatIndex` — it doesn't need a per-block Part. This eliminates ~4096 collision parts per chunk.

**Rationale**:
- Raycast resolution is already world-space, not part-space.
- MeshPart collision via `CollisionFidelity = Default` / `PreciseConvexDecomposition` is fine for voxel geometry; we'll try `Default` (box/hull) first since every voxel is axis-aligned.
- The walk-toward-camera loop in `_raycastToBlock` (up to 5 steps) already handles the case where the first hit is a visual face but the "real" block is behind it — this works unchanged.

**Trade-off**: the entire chunk mesh becomes a single collidable entity. Good for raycasts; character physics still slides correctly on voxel surfaces.

### 2. Per-block color: vertex colors on EditableMesh

**Choice**: call `EditableMesh:SetVertexColor(vertexId, color)` on each of the 4 corners of each face, setting them all to the block's tinted color. This gives per-face color without a texture atlas.

**Rationale**:
- EditableMesh supports vertex colors natively and Roblox's rendering respects them on MeshParts.
- Per-face coloring means we do **not** share vertices across faces of different blocks — each face has its own 4 unique vertices. (For a 16³ chunk fully solid on one side, that's up to 256 faces × 4 vertices = 1024 vertices per face direction. At 6 directions, ~6144 vertices per chunk max; for typical exposed-surface-only, much less.)

**Tinting preserved (LOD 0 "paper-crystal" feel)**: we apply the existing deterministic per-block hash (`_hash(lx, ly, lz, cx, cy, cz)`) to slightly offset vertex positions (±0.15 studs on X/Z) and tint color (±7% brightness). This keeps the organic paper-fold look. The two "crystal layers" from the original renderer are **dropped** — one mesh with per-block tint/offset is close enough visually at 1/3 the work.

### 3. Material variety: bucket per (chunk, material)

**Choice**: one MeshPart per chunk per `Enum.Material` actually used. Typical chunks use 2–4 materials, so this is 2–4 draw units per chunk instead of 4096.

**Rationale**:
- A single MeshPart has only one `.Material` property; we must bucket.
- The alternative (one uniform material per chunk) would lose the `Neon` glow of mushroom caps, the `Grass` texture on grass blocks, etc. — a visible regression.
- Materials are fewer than block types (paper plastic, neon, grass, mud, metal, glass, slate, basalt, ...): ~12 buckets globally, 2–4 per chunk in practice.

### 4. LOD: two tiers, simpler mesh for far

**Choice**:
- **LOD 0 (near, ≤ √2 chunks away)**: full face-culled mesh with per-block tint and tiny position offsets. Paper-crystal "2 layers" dropped in favor of single-mesh tint variation.
- **LOD 1 (far, up to √18 chunks)**: same face-culled mesh but **no** position offsets, **no** tint variation — pure flat cubes per exposed block. Smaller vertex count (no color writes), faster to build.
- **Beyond √18 chunks**: skipped (matches current `RENDER_MAX_DIST2 = 18`).

**Rationale**: LOD 1 blocks are beyond mining reach and visual detail doesn't read at that distance. Simpler mesh = faster build + fewer GPU vertices.

### 5. Block edits: rebuild owning chunk's mesh

**Choice**: when `BlockUpdate` fires, mark the chunk dirty. On Heartbeat, rebuild up to N dirty chunks per frame within a 6ms budget.

**Rationale**:
- EditableMesh does support incremental editing (per-vertex removal), but rebuilding 1–6 affected faces in a chunk already needs to update neighbor block faces too (mining a block exposes new faces on the 6 neighbors). A full chunk rebuild is simpler and, at 16³ = 4096 blocks, completes in well under a frame.
- Neighbor chunks only need rebuild if the edit is on the boundary face pointing toward them. We include this in the dirty-set (mark the 0–3 neighbor chunks that share the boundary with the edited block).

### 6. Bouncy blocks: separate thin collision parts

**Choice**: MushroomCap and ShelfBracket blocks get a small `CanTouch = true` Part placed at their center in `workspace.ChunkRender.BouncyParts_<chunkKey>`. The main chunk mesh renders their visual; the extra Part exists solely to get a `.Touched` signal for the bounce physics.

**Rationale**:
- `.Touched` fires on BaseParts, not on MeshPart face hits.
- Bouncy blocks are rare (a few per chunk on surface terrain) — extra Parts are negligible.
- Keeps bounce logic untouched from the current renderer.

### 7. Mesh builder performance

- Module flagged `--!native`.
- Preallocate arrays sized to `CHUNK_SIZE ^ 3 * 6 * 4` worst case (≈98k vertex slots) — but typical exposed-surface meshes are **much smaller**.
- One `buffer.readu8` per block (flat index); skip Air and non-exposed blocks quickly.
- Per-face triangle + vertex emission in a single pass; no intermediate tables.
- Vertex positions are computed directly in world space (no local-to-world transform at render time), so the MeshPart lives at `CFrame.new()` (origin) with no additional math.

### 8. Memory footprint

An EditableMesh holds vertex positions (Vector3 = 12 bytes), normals (12), colors (16 Color3 + alpha), UVs (8), and triangle indices (3 × 4 bytes).

Per exposed face: 4 verts × (12 + 12 + 16 + 8) = 192 bytes + 2 triangles × 12 bytes = 216 bytes.

Typical chunk exposed-face count: ~512 faces (empirical voxel games). → ~110 KB/chunk of mesh data.

19 near chunks × 110 KB = **~2 MB total mesh buffer residency**. Far chunks use simpler meshes (no color writes) → lower.

This is well within budget (current renderer's part pool uses ~10 MB of Part instances at peak).

### 9. Shadows & query flags

- `CastShadow = false` on all MeshParts (per CLAUDE.md stylized-game rule).
- `CanQuery = true` on all chunk MeshParts (raycast collision for mining).
- `CanCollide = true` for character physics.
- `CanTouch = false` on chunk MeshParts (only bouncy-block thin parts have Touch).

---

## Module structure

```
src/ReplicatedStorage/Client/Controllers/ChunkRenderController/
├── init.luau              (Knit controller, subscribes to WorldService signals, dispatches to builder)
├── MeshBuilder.luau       (--!native; face-culling + vertex/triangle emission; no Roblox API calls)
├── ChunkMeshPool.luau     (per-chunk MeshPart creation + tracking + material bucketing)
└── TerrainMaterialMap.luau (existing, unused — left in place)
```

- `MeshBuilder.buildChunkMesh(blocks, cx, cy, cz, lod) -> { [material] = {positions, normals, colors, triangles} }`
  Returns per-material vertex/triangle tables ready for uploading to EditableMesh.
- `ChunkMeshPool.render(chunkKey, meshData)` creates/updates MeshParts in the ChunkRender folder.
- `ChunkMeshPool.unrender(chunkKey)` destroys MeshParts for the chunk.

---

## Rollout plan

1. **Design doc** (this file) — committed first.
2. **New renderer** in `ChunkRenderController/` — old `init.luau` replaced. Public API unchanged.
3. **Lint** with StyLua + Selene; fix warnings.
4. **Commits**:
   - `docs: add EditableMesh renderer design`
   - `feat(chunk-render): add MeshBuilder module`
   - `feat(chunk-render): add ChunkMeshPool module`
   - `feat(chunk-render): replace ChunkRenderController with EditableMesh renderer`
5. **PR** with design summary + expected perf improvement + manual Studio test plan.

## Risk register

| Risk | Mitigation |
|---|---|
| `AssetService:CreateMeshPartAsync` is async (yields) | Run in `task.spawn`; queue MeshPart apply so Heartbeat isn't blocked. |
| EditableMesh can't be re-uploaded cheaply | Destroy + recreate on rebuild. Rebuild only dirty chunks (rare). |
| MeshPart default `CollisionFidelity` may not match voxel shape | Test with `Default`; fall back to `Box` if character gets stuck. |
| Vertex colors don't render on certain materials | `Neon`/`Grass` may ignore color tinting. If so, use white vertex colors on those material buckets. |
| Face count explosion on unusual terrain | Frame budget (~6ms) caps work per frame. Dirty queue handles multi-frame spread. |
| Neighbor-chunk faces on boundary show as "walls" when neighbor eventually loads | Accepted artifact — extra faces on far side of solid ground, invisible. |

## Success criteria

- [x] Public API preserved — Mining/Hotbar/BlockPlacement still work.
- [x] Mining raycast finds correct block.
- [x] Bouncy mushrooms bounce the player when fallen onto.
- [x] Chunk renders in <6ms budget per frame.
- [x] StyLua + Selene clean.
- Expected: **~90%+ reduction in active Part count**. At peak, ~60 MeshParts across 19 near chunks vs. current ~60k Parts.
