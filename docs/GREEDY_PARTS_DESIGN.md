# Greedy-Meshed Parts Renderer — Design Doc

## Goal

Cut the number of Roblox `Part` instances emitted by `ChunkRenderController` by merging
runs of same-type exposed blocks into single stretched Parts. Stay on standard Parts
(not EditableMesh). Target 80-90% part-count reduction on typical terrain.

## Non-goals

- No asset/mesh changes. No EditableMesh. No UnionOperation. Pure `Part` with
  `Size` + `CFrame`.
- No change to chunk compression, network protocol, or server-side world gen.

## Callers of ChunkRenderController (API contract to preserve)

Public methods grep'd from `src/`:

- `ChunkRenderController:GetBlockAt(chunkKey, flatIndex) -> number`
  - Used by `MiningController` (raycast probe + mining loop) and `HotbarController`
    (placement validation).
- `ChunkRenderController:GetChunkBlocks(chunkKey) -> buffer?`
  - No external callers found, but keep for parity.
- `ChunkRenderController:GetActivePartCount() / GetPoolSize()`
  - Debug only. Keep.

Signals consumed (`WorldService` client side):

- `ChunkData(chunkKey, compressedBuffer)` — new chunk arrives
- `ChunkUnload(chunkKey)` — chunk leaves subscription
- `BlockUpdate(chunkKey, flatIndex, blockTypeId)` — per-block mine/place

None of the callers inspect the `Part` instances themselves (they all go through
`GetBlockAt` via the block buffer). `MiningController` raycasts against the parts
but only uses the hit position and normal — it does not assume one-part-per-block.
That means we are free to emit merged Parts, and the raycast probe will still
resolve to the correct block because it offsets by `BLOCK_SIZE * 0.4` into the
block and reads the block buffer from `ChunkRenderController:GetBlockAt`.

Good: greedy meshing is transparent to callers.

## Greedy sweep algorithm

### Merge criteria

Two blocks `A` and `B` can merge into one run if ALL of the following hold:

1. Same `blockTypeId` (both non-air, same registry entry).
2. Both are "exposed" (have at least one transparent neighbor — same predicate as
   today).
3. Same LOD tier (the merged region inherits the chunk's current LOD; LOD is
   per-chunk so this is automatic).
4. Not a bouncy block (`MushroomCap`, `ShelfBracket`) — these keep their per-block
   `.Touched` handler.
5. Not a `WillowVine` (per-block taper factor depends on vertical depth, so each
   vine block has a unique size) — these stay per-block.

Note on the "same exposure pattern" option described in the task: we RELAX it to
"both blocks must be exposed". Rationale: the merged Part is a solid axis-aligned
box, and if both constituent blocks are exposed somewhere, the rendered box is a
correct outer hull. Interior faces of the run would be hidden anyway (by the
mergeable neighbor blocks on either side of the run, which are themselves part
of the run or are occluders). The only case where relaxing this matters is a
block that is exposed on the side the run extends along — but in that case the
neighbor on that side is air, which terminates the run, so this cannot happen.
Relaxing to "all exposed" keeps the mesher simple and fast.

### 2D sweep (X, then Z extension)

We implement a 2D sweep: collapse same-type runs along X, then try to extend the
rectangle along Z. Full 3D (extend along Y as well) is NOT attempted — the Y
extension complicates mining splits (a dug block can leave a non-convex hole
along Y) and the gain is marginal for typical terrain which is laid out in Y
layers with varying materials.

Pseudocode:

```
merged[ly][lz][lx] = false  -- visited bitmap

for ly in 0..CHUNK_SIZE-1:
  for lz in 0..CHUNK_SIZE-1:
    for lx in 0..CHUNK_SIZE-1:
      if merged[ly][lz][lx]: continue
      id = blocks[lx,ly,lz]
      if id == Air or not isExposed(lx,ly,lz) or not isMergeable(id):
        merged[ly][lz][lx] = true
        continue

      -- extend along +X
      xEnd = lx
      while xEnd+1 < CHUNK_SIZE
            and blocks[xEnd+1,ly,lz] == id
            and isExposed(xEnd+1,ly,lz)
            and not merged[ly][lz][xEnd+1]:
        xEnd += 1

      -- try to extend along +Z (whole X-row must match)
      zEnd = lz
      done = false
      while not done and zEnd+1 < CHUNK_SIZE:
        for x in lx..xEnd:
          if blocks[x,ly,zEnd+1] != id
             or not isExposed(x,ly,zEnd+1)
             or merged[ly][zEnd+1][x]:
            done = true; break
        if not done: zEnd += 1

      -- mark merged cells
      for z in lz..zEnd:
        for x in lx..xEnd:
          merged[ly][z][x] = true

      emit region { id, lx, ly, lz, xEnd, ly, zEnd }
```

Complexity: each cell is visited once for the outer triple loop plus once per
row/column scan during extension; overall O(N^3) worst case, O(N^3/regionSize)
typical. For a 16^3 = 4096-block chunk this is a rounding error vs the 4096 iter
scan we already do.

### Bouncy and vine exclusions

`isMergeable(id)` returns false for `MushroomCap`, `ShelfBracket`, `WillowVine`.
These emit single-block regions of size 1x1x1 (`lx..lx`, `lz..lz`). The renderer
keeps per-block code paths for them.

## Output schema

`GreedyMesher.meshChunk(blocks) -> { Region }` where each Region is:

```lua
type Region = {
    blockTypeId: number,
    minLx: number, minLy: number, minLz: number,
    maxLx: number, maxLy: number, maxLz: number,  -- inclusive
}
```

The Region array replaces per-block iteration inside `_renderChunk`.

## Renderer integration

### LOD 1 (far — single Part per region)

Already a straightforward win. For each Region:

1. Compute world-space center and size from min/max corner.
2. Color: base color * size-dependent tint hash (seeded by minLx/minLy/minLz)
   for micro-variation between chunks. For merged regions we use a flat tint
   (no per-block jitter — merged region is inherently a single Part).
3. Material = `BlockRegistry.getMaterial(id)`.
4. `Size = Vector3.new((xExtent)*BLOCK_SIZE, BLOCK_SIZE, (zExtent)*BLOCK_SIZE)`.
5. `CanCollide = true`, `CanQuery = false` (mining reaches LOD 0 only).
6. Register the Part with each `(lx, ly, lz)` in the region inside `chunkParts[chunkKey]`
   so that mining splits can find it.

### LOD 0 (near — paper-crystal)

The current code emits 2 stretched visual layers + 1 collision per block. We
preserve the paper look on **merged runs** by emitting 2 stretched visual layers
spanning the whole region plus 1 collision Part for the region.

Decision: **drop the per-block tilt/offset jitter on merged runs of ≥ 2 cells**.
A stretched rectangle with per-block tilts would have to be implemented as N
tilted tiles (defeating the merge), and the paper-crystal look is visible
enough on single-block edges and natural terrain boundaries (which stay as
small regions anyway — cave walls, overhangs, and mineshafts generate many
1- and 2-cell regions). Large flat surfaces (floors, plains) lose the
per-block tilt but gain smooth flatness that looks intentional.

Single-cell regions (size 1x1x1) still get a single per-block tilt/offset.

The 2 visual layers for LOD 0:

- Layer A: size `(xExtent*BLOCK_SIZE*1.08, LAYER_HEIGHT, zExtent*BLOCK_SIZE*0.92)`.
- Layer B: size `(xExtent*BLOCK_SIZE*0.92, LAYER_HEIGHT, zExtent*BLOCK_SIZE*1.08)`.
- Vertically offset by `LAYER_GAP` (same as current).
- Tint uses the existing `_getLayerTint` cache.

Collision Part: `Size = (xExtent, 1, zExtent) * BLOCK_SIZE`, `Transparency = 1`,
`CanCollide = true`, `CanQuery = true`.

### Paper-crystal for single blocks

For 1x1x1 regions we still call the original per-block tilt/offset path so that
isolated blocks (e.g. a single exposed ore embedded in stone, a 1x1 tower top)
keep the distinctive look. The mesher's output preserves this because every
isolated exposed single block is emitted as a 1x1x1 region.

### Collision strategy

One collision Part per merged region. This means:

- LOD 0: 2 visual layer Parts + 1 collision Part per region (was 3 per block).
- LOD 1: 1 Part per region with CanCollide=true (was 1 per block).

For a merged 10x1x1 run of Paper, LOD 0 drops from 30 Parts to 3 Parts
(10x reduction for that run).

## Block-edit (mining) splits

When a block inside a merged region is mined (`BlockUpdate(chunkKey, flatIndex, Air)`):

1. Find the `Region` containing `(lx, ly, lz)` — lookup via
   `chunkParts[chunkKey][flatIndex]` which maps the flat index of EVERY block in
   the region to the same `{ BasePart }` group (all parts in that region share
   the entry).
2. Return all parts in that region's group to the pool.
3. For each `flatIndex` within the old region, clear `chunkParts[chunkKey][idx]`.
4. Re-mesh the affected volume: iterate only the old region's bounding box
   (`minLx..maxLx, minLy..maxLy, minLz..maxLz`), re-run the greedy sweep locally
   for that box, and emit new regions. Because the sweep is deterministic and
   only considers the current block buffer (which we just updated), the new
   regions correctly exclude the mined block and split the remainder.
5. Update neighbor exposure: six neighbors of the mined block can become newly
   exposed. If a neighbor was interior of another merged region, it is not in
   the remesh box, so we handle it with the existing neighbor-update code:
   for each of the 6 neighbor positions, if the neighbor is non-air and exposed
   and not already rendered, re-mesh the 1x1x1 region covering that neighbor
   (which may break up an adjacent region too if the neighbor was part of a
   merged region from a DIFFERENT angle — but that is unusual since our merge
   criteria require exposure, and neighbor exposure changes are handled by
   steps 1-4 when we re-scan the full region-bounding-box + each neighbor's
   region bounding box).

### Placement splits

Placing a block (`BlockUpdate` with a non-air id) is symmetric:

1. The new block may or may not be adjacent to an existing region of the same
   type. We do NOT attempt to extend an existing region in place (that would
   require recomputing the merge). Instead:
2. Re-mesh the 3x3x3 bounding box around the placed block. This catches all
   cases where the placement creates a new single-block region, merges into
   an adjacent same-type region, or un-exposes an interior block.
3. For each neighbor that is part of some larger merged region, remesh the
   bounding box of that region too so that the newly-hidden or newly-exposed
   interior faces are correct.

### Split diagram

Starting merged region: `10x1x1` run of Paper from `(0,4,0)` to `(9,4,0)`.
User mines block at `(4,4,0)`:

```
Before:
  X: 0 1 2 3 4 5 6 7 8 9
  [=========================]   ← one Part, size 10x1x1

Mine (4,4,0):
  X: 0 1 2 3 _ 5 6 7 8 9
  [=======] . [===========]     ← becomes two Parts, 4x1x1 and 5x1x1

The greedy sweep on the OLD region's bounding box re-emits:
  Region{0..3, 4, 0}  (4 cells)
  Region{5..9, 4, 0}  (5 cells)
```

Part-pool impact: we return 3 Parts (old LOD 0 region: 2 visual + 1 collision),
check out 6 Parts (2 new regions × 3 Parts each). Net +3 Parts.

## Memory footprint (per-chunk merged region tracking)

We need to find the region containing a block in O(1) so mining splits are fast.

**Chosen approach**: `chunkParts[chunkKey]` is indexed by `flatIndex` and returns
the `{ BasePart }` group. For merged regions, EVERY flat index covered by the
region points to the SAME group table. This means:

```lua
-- chunkParts[chunkKey][flatIndex(0,4,0)] === chunkParts[chunkKey][flatIndex(1,4,0)]
-- === chunkParts[chunkKey][flatIndex(9,4,0)]  -- all point to the same {parts} table
```

To know the bounding box for a re-mesh we also store a parallel table
`chunkRegions[chunkKey][flatIndex] = { minLx, minLy, minLz, maxLx, maxLy, maxLz, blockTypeId }`
for each flat index in the region (same object shared across all indices).

Memory cost: two pointers per block × 4096 blocks × ~16 B per entry = ~128 KB
per chunk. With a ~100-chunk subscription window that is ~12 MB on the client.
Acceptable.

An alternative is to store a single-region entry per region and a separate
`flatIndex → region-id` map. That would drop to ~64 KB per chunk. We can
optimize later if needed; for the first cut we pick the simpler shared-reference
scheme.

## Expected part-count reduction

Rough estimates from reading `BlockRegistry`:

- Surface biome: dominant block is 1-2 surface types (e.g. `PaperGrass` + `Paper`
  underneath). A 16x1x16 top layer is ~256 blocks; greedy merges into ~16 rows
  of 16 blocks each (with 2D extension, potentially ~1 big 16x16 patch if all
  exposed).
- Underground: dominant block per tier (Folded Stone, Origami Rock, etc.).
  Exposed surfaces on cave walls form 2-5 cell runs on average.
- Mixed: ore veins, egg nodes, and bouncy blocks stay per-block but are rare.

Estimates:

| Scenario | Blocks | Old Parts (LOD 0) | New Parts (LOD 0) | Reduction |
|----------|--------|-------------------|-------------------|-----------|
| 16x16 flat ground (1 material) | 256 exposed | 768 | ~3 (one 16x16 patch) | 99.6% |
| 16x16 checkerboard (2 materials) | 256 exposed | 768 | ~256 (no merges) | 0% |
| Typical surface chunk | ~400 exposed | ~1200 | ~150 | 87% |
| Typical cave chunk | ~700 exposed | ~2100 | ~400 | 81% |

Average: we expect **~80-90% part reduction on realistic terrain**. Pathological
cases (checkerboard) show zero benefit but are rare.

## Risks

- **Mining split re-emit cost**: re-meshing a region's bounding box can emit up
  to N parts for an N-cell region. In practice region sizes are small (< 10)
  so the cost per split is ~3-30 part checkouts.
- **Paper-crystal visual regression on flat surfaces**: documented tradeoff.
  Single-block regions keep the tilt; larger merges are intentionally flat.
- **Raycast normals on stretched Parts**: a stretched Paper Part has a larger
  top face, but `MiningController` probes at hit position, not hit-center, so
  the offset-into-block walk still converges on the right block.
- **Collision plate shape on stretched Parts**: character walking on a 10x1x1
  Paper Part is indistinguishable from 10 adjacent 1x1x1 plates — good.

## Implementation order

1. Write `GreedyMesher.luau` with `--!native` and unit tests.
2. Rewrite `ChunkRenderController` to call the mesher in `_renderChunk`.
3. Implement split logic in `_handleBlockUpdate` that finds the region, clears
   it, and re-meshes its bounding box (+1 cell in each direction for safety).
4. Add logging at chunk render time.
5. Run selene + stylua.
6. Manual Studio testing (walk around, mine, verify bouncy mushrooms, verify
   paper-crystal look on singletons).

## Out of scope for this PR

- 3D (Y-axis) extension.
- Across-chunk merging (regions stop at chunk boundaries).
- Dynamic re-merging during mining (we split but don't coalesce; coalescing
  would require tracking adjacent regions of the same type, which is complex
  and rarely useful because re-render cycles are cheap).
- LOD transitions (already handled per-chunk by existing `_reevaluateLODs`).
