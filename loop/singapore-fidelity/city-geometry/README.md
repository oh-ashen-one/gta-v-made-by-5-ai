# National source-footprint render/collision candidates

> **R1 IS REJECTED FOR NATIVE WINDING. Do not render/commit candidate-r1 as ready.** NativeR1 completed26checks with3physicalfailures: rays hit underside0 instead ofroof12/9.6 andcapsulesettlingfailed. Hash/arithmetic approval did not establishGodotfrontface correctness. FreshfixtureV2 reverses indices to Godotclockwisefrontface convention while retaining outward normals/vertices/UVs. No culling/backface workaround or weakened physical test is used. RootnativeV2run is pending; the large dataset has not been repaired yet. See WINDING_REJECTION.json and retainedr1-rejected snapshots.

This stage produces actual local mesh vertex/normal/UV/index buffers from country-wide mapped building footprints. It is not just another coordinate query. Root owns normal World/Game geometry authority, detailed materials/architecture, scene/physics commits, terrain/water interpretation, road-grade planning, actors/traffic/AI, saves, rebases and full MBS integration. A correct source footprint/game extrusion does not satisfy the GTA-quality/full one-to-one architecture goal.

Only the assigned new `compile_city.py`, dedicated tests, `runtimecity_tiles.gd`, native QA scene, `compiled-country/osm-2026-10-27/` and this notes folder were changed. No existing compiler/canonical/domain/context/runtime/main/actor/floor/cabin file, engine/GPU/UI or Git state was modified by this builder.

## Concrete production format

`candidate-r1/identity.json` independently pins the manifest SHA/bytes, canonical snapshot and DEM identity. `manifest.json` inventories every mesh metadata/binary and logical catalog page, world-Y/height reconstruction policies, source compiler hashes, counts, exclusions and limitations.

- `catalogs/<canonical-owner>.json`: one logical row per original `kind|sourceID`. Original name/tags, height/levels strings, canonical owner/feature/geometry checksums, absolute double source bounds and explicit policy/status remain intact. No invented source name/height replaces missing facts.
- `meshes/<spatial-1km-cell>.json`: canonical double anchor `[tileX*1000,0,tileZ*1000]`, unique logical feature references/catalog owners and local mesh buffer ranges.
- `meshes/<cell>.mesh`: raw little-endian interleaved float32 positionXYZ/normalXYZ/UVXY (stride32), followed by uint32 triangle indices per surface. The provider reads this with FileAccess/StreamPeer, not ResourceLoader. Each surface has its own exact byte/topology hash.
- Roof, underside and exterior/courtyard wall surfaces retain separate material-role names. UV phase is feature-relative and independent of future floating-origin rebases. Collision candidates reference the same vertex/index buffers; no separate bounding box fills courtyard holes.
- `terrain_reference` binds the existing1798-chunk DEM dataset/key. It does not assert dry land, terrain collision, physical support or current surveyed ground.

A logical building can cross multiple mesh cells. Its owner catalog exists once; each spatial fragment has runtime identity `feature_key@cell`, separate from logical identity. Root should track logical features **and** loaded fragments, not drop later fragments after the first logical-ID hit.

## Footprints, holes and seams

The compiler reuses the independently reviewed `game/tools/geodata/compile_geometry.py` `surface_geometry` constrained-Delaunay/hole/area checks. No raw triangulation fills holes. Canonical geometry is intersected with the exact administrative country; source geometry hash/bounds remain unchanged. Non-area boundary contacts do not become building volume.

Roofs and undersides are partitioned by spatial cell. Only the original **country-clipped footprint boundaries** produce walls; source courtyard boundaries point inward toward the courtyard. Tile cuts never create new vertical partition walls or double solid faces. The verified source path ownership helper assigns an exactly shared boundary once, while preserving real source walls when the neighboring clip is absent.

All world XZ anchor subtraction happens in double precision before float32 packing. A feature spanning a cell edge uses the same flat feature base/top in every fragment, and tile anchors remain exact global1km values. Degenerate post-quantization triangles are not expanded/repaired into false geometry; that feature is retained as explicitly unresolved instead.

## Explicit height and world-Y policy

Root directed the first country candidate to use:

```text
mode: EGM96_DEM_game_world_reference_not_current_survey
world-Y offset: 0.0 m
unknown-height game fallback: 9.6 m
source-level game story height: 3.2 m
```

The mode/offset are required inputs, bound into identity/config and explicitly accepted again by the runtime provider. An original positive source `height_m` has priority. Otherwise a usable original `building:levels` string can drive the declared3.2m game conversion; otherwise the9.6m fallback is tagged reconstruction per feature. Original height/levels/min-height/min-level strings remain unchanged, including unresolved/unparsed values. Known heights are not replaced by the fallback.

Each building uses one DEM sample at an interior representative point as a **flat game base**. DEM identity/source sample/value and offset are recorded. This is not a current building-ground survey or an assertion that the existing MBS stage0/L1/saves share that datum. A missing/void DEM base stays unresolved; it never becomes zero ground. Contradictory vertical extents, invalid geometry, excessive work or precision failures remain explicit rows and do not stop the country for missing factual heights.

Roof geometry is a flat game extrusion to the source/estimated top, not verified reconstruction of gables/roof fit-out. Distinct source building outlines/parts can overlap and retain their source roles; their architectural composition is not silently XY-merged. Root must refine this, facades and landmark overrides before visual/as-built acceptance.

## Root special complex exclusions

At minimum the source IDs `way/172307471`, `way/172307472`, `way/116801004`, `relation/2298319` are excluded from solid generic meshes. The first candidate also excludes intersecting building features in `[151.124,-1100.2107,636.9596,-653.2214]`, the combined bounding envelope of the verified site-audit hotel tower/retail footprints, without an invented margin.

Every excluded feature remains in its logical catalog and the manifest exclusion list with original ID/bounds/reason. This reserves root's hollow MBS/site/landmark authority; it is not a permanent missing-site acceptance. Roads are retained through this envelope, including Bayfront Avenue; they are not erased with the generic solids. Root inserts all explicit replacement geometry, preserving hotel/retail separation and preventing duplicate solid MBS masses.

## Roads and water are not false support

The same pinned private PBF is scanned for original highway way references/full tags using a C++ key filter and bounded SQLite staging. No full source-node location cache or memory-heavy country ID bitmap is created. Ordered original node IDs, canonical coordinate counts, full direction/bridge/tunnel/layer/access/construction/proposed/name strings and available source version are retained. Any missing/source-tag/count mismatch remains an issue. Independent source-node projection validation for the earlier559-way Bayfront supplement is separate; the national row does not fabricate such a claim.

Road centerlines stay double-valued relative to their canonical owner anchor. Road width, metric vertical/grade, access/legal travel policy and actual road mesh/collision remain unresolved for root planning. No XY intersection merge, proximity join, source-order reversal, inferred bidirectional graph or automatic car-road classification is made. Inland/sea water/other source rows do not create support planes or dry ground.

## Bounded CPU work and resumability

The real country input remains906 canonical files,135415 building records and257845 highway/path ways, with original snapshot `d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983`. DEM identity is `5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841`.

The supervised child runs background/nice10, <=2GiB sampled RSS,3600 CPU seconds (+30 hard grace),7200 wall seconds. These are job resource guards, **not a new user timebox or relay wave**. Before loops: <=2000 owners/500k source features, each source owner<=32MiB, per-feature candidate-cell/coordinate/fragment budgets. Each catalog<=32MiB and mesh binary<=64MiB. A geometry work failure records unresolved rather than enlarging/replacing source shapes. Staging is disk-backed SQLite with64MiB cache and no mmap; only one canonical page/feature/DEM-cache neighborhood is active.

Only a fresh output or explicit `--resume` for the **exact same** job/config/source/compiler hashes is accepted. Active process locks prevent duplicate live workers. Completed owner pages/SQLite stages are checksum-bound; partial deterministic publication is reused only byte-for-byte. Different existing outputs are never overwritten. The regenerable staging DB/lock is removed after successful identity publication; `.gitignore` excludes unfinished DB/lock/progress/failure/supervisor state from source publication.

## Runtime API and root commit

```gdscript
var tiles := SingaporeRuntimeCityTiles.new()
tiles.configure(DATASET_DIRECTORY, TRUSTED_IDENTITY, FRAME_SNAPSHOT,
    EXPECTED_DEM_IDENTITY,
    {"mode":tiles.YMODE,"offset_m":0.0}, 2)
var data := tiles.tile(tile_x, tile_z)
# data.anchor_source_xyz remains a double Array.
# Root: frame.to_local(anchor) -> node transform, only at controlled commit.
# feature.surfaces[*].arrays are ready for ArrayMesh.add_surface_from_arrays.
var owner := tiles.catalog(feature.catalog_owner)
```

`tile`, `catalog`, `mesh_keys` and `mesh_keys_for_cell` return bounded detached data. The provider verifies manifests, files/hashes, buffer offsets/counts/topology hashes, local coordinates/normals and canonical anchors. Local engine vectors are created only from already anchor-subtracted float32 payloads. It creates no ArrayMesh, material, body, node, World/Game singleton or default map. Root alone commits visual/physical geometry, global logical/fragment registries, complete collision residency and source-frame rebases.

Missing/corrupt cells return unknown, not an empty traversable country slab. Version changes require a new provider/context. LRU mesh/catalog capacities are explicit1..8. Cache bounds do not bound caller-retained meshes/arrays; root must retire its scenes and references.

## Verification and actual status

Python currently passes10 focused tests: source-priority/reconstructed heights and min levels; courtyard roof/underside holes; normal/winding/shared collision bytes;80km anchor-before-float; crossing-cell area with no artificial walls; original edge ownership; byte-offset/hash/no-overwrite; native original road refs/tags and resumability; actual separate DEM base; reproducible native fixture.

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geography -p test_compile_city.py -v
```

The generated `qa-fixture-v1` uses the **production** compiler functions for a hollow courtyard plus a spanning building, explicitly synthetic/not Singapore. Rejected fixtureV1 identity: `055bc31a84c3d919907fce3020c1594e377b639f90dd1981b54f9beb166ba97e`. Fresh corrected fixtureV2 identity: `4e8dcc308c104905c1d2b8c77ee6a37a6f6140d04da2ca9c9bd5ae10186dccc8`. Its generator entrypoint duplicate was caught after producing valid fixture bytes and corrected; the later10-test run validates generated headers/topology/overwrite safety.

Root-run native scene command (the child launched no engine):

```sh
bash loop/singapore-fidelity/run_engine.sh city-tiles-fixture-r1 120 \
  /private/tmp/singapore-fidelity/city-tiles-fixture-r1 -- \
  --headless res://src/systems/fidelity_tests/city_tiles_test.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/city-tiles-fixture-r1/session
```

It creates real ArrayMesh/trimesh bodies at a checked local origin, tests roof support/open courtyard/no internal tile wall/seam support and a real capsule settling, plus cache/identity/catalog behavior. NativeR1 is FAILED; correctedV2 is pending root report/log verification. Mathematical face tests now require the Godot clockwise convention, not the previously incorrect cross-product/outward-normal equivalence. Official primary documentation: https://docs.godotengine.org/en/stable/classes/class_arraymesh.html . An optional explicit `--city-identity=<candidate hash>` (and `--city-dir=...`) enables bounded actual national-tile instantiation after full compilation; omitted identity is explicitly NOT_RUN, not an actual-country pass.

The R1 whole-country data compile completed but its native orientation is REJECTED under `game/data/geography/compiled-country/osm-2026-10-27/candidate-r1`. Do not treat staged catalogs or missing final identity as complete. `progress.json`, `.job.lock`, eventual worker/supervisor receipts and final `VERIFICATION.json` establish actual status/counts. Root's complete game/source bootstrap, materials/architecture, road planning, terrain/hydrology, traffic/AI/saves/rebases and full MBS remain open.
