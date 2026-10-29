# Source DEM terrain scene assembly

This stage prepares and **installs actual ArrayMesh/StaticBody terrain geometry**, not another query-only framework. Root keeps one World/Game authority, materials, actors, collision residency/support registration, hydrology, default bootstrap and all rebase/stream decisions. The child changed only new terrain-scene/helper/tests/notes paths and started no engine/GPU/UI/Git/provider/account activity.

## Real inputs and explicit Root masks

Preparation binds independently verified source inputs:

- Canonical OSM snapshot `d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983`.
- Projected territory/coast-domain identity `82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834`.
- Source DEM identity `5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841` (older/coarse EGM96 reference, not current surveyed ground).
- Root-approved masks `game/data/geography/mbs-root-holes.json`, SHA256 `9d91185dab9c936316b1397a7faad778556b28fb29e44f01f03b4fe04d498625`.

The five Root masks comprise the **exact canonical polygons** for three named hotel towers and retail relation, plus Root's explicitly reconstructed public-loft footprint derived from retained profiles/source axes. The reconstructed mask is labeled approximate, not OSM/as-built. No broad country or invented rectangle replaces these shapes. This mask version protects known hollow areas; final basement/core/arrival/foundation geometry may require a new explicit assembled mask version. Root must provide it; no implicit mask update or uncovered-basement acceptance occurs.

An explicit `terrain_root_holes_v1` document is mandatory, even when Root intentionally approves an empty list. Each mask has unique ID, valid actual projected Polygon/MultiPolygon, source feature references and provenance. Snapshot/mask hash are checked. Invalid/unprovenanced masks are rejected, never repaired or buffered.

## What becomes a terrain candidate

`compile_terrain_scene.py` reads only canonical water records from the bounded906 source owners, preserving all1549 water IDs/tags/geometry/checksums with **unknown vertical water columns**. It indexes them with an STRtree. It does not treat DEM values, source territory or a sea plane as water/land truth.

For each requested1km tile:

```text
candidate support footprint = source coast enclosure intersect tile
                            minus canonical water horizontal footprints
                            minus explicit Root hollow/basement masks
```

This is an explicit **conservative game terrain-admission policy**, not a certified dryland/hydrology model. Canonical water may include elevated/indoor fountains; such footprints remain conservatively unsupported until Root supplies their resolved geometry/vertical treatment. No finite water surface/bottom is invented. The separate water registry keeps that uncertainty visible.

Every25m DEM grid cell is clipped to that exact footprint, then passed to the existing verified hole-aware constrained-Delaunay surface compiler. Source heights and central-difference normals come from the exact existing43×43 halo data. Anchor subtraction happens in double before local float32 packing. Source-derived triangles are explicitly clockwise for Godot; the standard geometric cross-Y must be negative. No cull/backface workaround is used.

Only area triangles are generated: no skirts, vertical partition walls, bottom caps or flat fallback close a coastline, water footprint, basement opening or missing DEM cell. Unknown height/normal stencils remain unsupported and reported. Shared source edges/normals use the same global25m samples/halo, and neighboring local anchors remain exact1km values.

The triangulated surface approximates the already resampled DEM; a triangle plane inside a cell is not new measured detail or necessarily identical to a bilinear value away from posts. Elevation is explicitly `EGM96_DEM_game_world_reference_not_current_survey`, offset0.0 for this candidate. It is neither current MBSL1 nor automatically aligned with every architectural floor/dry volume. Root owns final integration.

## Data format and actual neighborhood

Prepared artifacts remain private/local:

`/private/tmp/singapore-fidelity/terrain-scene/mbs-neighborhood-r1`

- Outer terrain identity `f8488742dd93726276b33ca12cda7c6d0a38b967123a0be0d574b9145b7f469c`.
- Inner compatible mesh identity `76fe71d5d7260264d4f9318bfe48b73a6bca564578961f05fdecb2d0bf05058f`.
- Mesh manifest `02678e05b5055daf488ad84ad9b9645fdefc00f0e3237a29410af78e25c8f9ac`.
-9requested/prepared tiles (`x=-1..1,z=-2..0`),15004 vertices,26178 triangles, zero unknown DEM grid cells.
-1549 canonical water records retained separately; Root's five masks preserved with exact version.

`terrain-identity.json` pins terrain semantics, masks, sources and the inner generic mesh identity. The compatible existing mesh encoding keeps per-tile source anchors, per-surface binary hashes, clockwise/local32 buffers and catalog provenance. `water-registry.json` is separately hashed and verified before opening. A compact metadata-only copy in `artifact-records/mbs-neighborhood-r1/` is a receipt, not a complete runtime geometry directory.

## Runtime API and single authority

`SingaporeTerrainScene` composes Root's current verified `city_scene.gd` installer rather than duplicating commit/reap/epoch logic:

```gdscript
var terrain := SingaporeTerrainScene.new()
world.add_child(terrain)
terrain.configure(frame, material_for_surface, root_may_retire, 9, 16)
terrain.open_prepared(PREPARED_DIRECTORY, TRUSTED_TERRAIN_IDENTITY,
    frame.metadata().snapshot_manifest_sha256, EXPECTED_DEM_IDENTITY,
    ROOT_APPROVED_HOLE_MASK_SHA,
    {"mode":SingaporeRuntimeCityTiles.YMODE,"offset_m":0.0}, 2)
var prepared := terrain.prepare_tile(tile_x,tile_z) # bounded I/O/decode off critical path
var result := await terrain.install_tile(prepared) # Root main-thread controlled commit
```

The installer receives Root's required exact identity dictionary `{geometry_identity_sha256:innerSHA,snapshot_manifest_sha256:sourceSHA}`; a matching frame alone is not geometry authorization. Dataset, frame, DEM, Root masks, water policy/registry and world-Y policy are checked independently. Different versions require a new preparation/component, not a silently changed cache.

`install_tile` produces real ArrayMesh/StaticBody collision through the verified installer, checks current epoch/native collision commit, and returns a receipt enriched with terrain/mask/water provenance. It does not register SourceRuntime residency, floor/support/dry records or move actors. `collision_bodies(tile_key)` gives Root the actual bodies for that separate controlled registry/stamping step. Source height is not itself a physics hit; native geometry must actually commit.

`retire_tile` delegates the explicit Root guard. Root must first retire/transfer its collision-region/support leases and ensure actors are safe. The component disables only its owned collision, queues its holder, waits native ticks and reports reaping. It creates no new World/Game singleton, root geometry authority, default map, Y kill plane or automatic actor teleport. Source-frame/rebase coordination remains Root work.

Bounds follow the verified provider/scene contract: LRU cache1..8, active tiles1..25 (candidate9), features per-frame1..64, metadata/binary byte/count/range/hash validation, main-thread construction batches, immutable identities and epoch checks. The offline compiler can prepare any country tile/all1798 DEM cells, not a permanent MBS-only world; batches are bounded to2000 selected unique keys and per-tile250k vertices. Whole-country preprocessing can be split into explicit batches; no unbounded per-frame clipping/decode occurs.

## QA

Python tests:

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geography -p test_compile_terrain_scene.py -v
```

**7 tests passed**: coast-versus-territory, water/Root mask holes, exact footprint area/hole triangulation, source heights/normals/clockwise/80km anchor-before-float, adjacent halo seam identity, unknown DEM/normal no fallback, explicit provenance/snapshot masks, and actual Root five masks/actual DEM reference.

Root-run native command (child started no engine):

```sh
bash loop/singapore-fidelity/run_engine.sh terrain-scene-r1 150 \
  /private/tmp/singapore-fidelity/terrain-scene-r1 -- \
  --headless res://src/systems/fidelity_tests/terrain_scene_test.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/terrain-scene-r1/session
```

The dedicated scene opens this actual dataset, installs all9real terrain meshes/bodies through TerrainScene, tests source height/native ray support, hotel mask/no plug, canonical Rain Oculus/no support, sea outside coastal enclosure/no support, a shared tile seam, real capsule settling, duplicate/unloaded/mask mismatch negatives, Root retirement veto and owned body reaping. Positive/negative source probes and their unchanged provenance are recorded in QA_PROBES.json; a0.6m positive-point selection clearance is **not** a source geometry buffer/repair.

Root actual terrain-scene-r1 completed62/62checks, engine/supervisor0, nofatal, reaped at02:18:06UTC. The child read the actual report and pinned its hash inVERIFICATION.json. These are bounded actual9tile geometry/nativecapsule/support/holes/seam/retirement proofs. This fixture is not current survey, whole-country runtime/bootstrap, MBS foundation completion, hydrology/dry-volume classification, final visual materials or performance acceptance. `VERIFICATION.json` pins current source/data/QA hashes; all future mask/source updates need distinct identities.
