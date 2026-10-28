# National source-data dependency index and runtime loader

This is a source-data streaming foundation. It does **not** migrate the existing compressed playable city, construct streets or buildings, or prove full Singapore/Marina Bay Sands acceptance.

Canonical input: `game/data/geography/osm-2026-10-27`. Its OpenStreetMap geometry is already projected into uncompressed metre-scale Godot `[x,z]` coordinates using SVY21 EPSG:3414, origin E30000/N30000, -X north and -Z east. No second conversion or scale is applied. OSM attribution, ODbL license, source URL/time/hash and explicitly unknown building heights are preserved. Road/path ways include service, foot, construction and proposed ways; the loader does not relabel them all as driveable roads.

## Why the sidecar exists

Canonical owner files use feature centroids. Long crossing roads and multipart buildings can extend far beyond their owner's filename. The index intersects each complete source geometry with exact projected Singapore/cell intersections and references canonical owner files, including owners outside the country when their geometry crosses it. Country holes and separate islands are retained; a rough country rectangle is not substituted. No feature geometry is duplicated into the index. Invalid source geometry would be conservatively bbox-indexed and recorded rather than silently repaired; this actual build found zero invalid geometries.

A dependency cell is not a point-in-country certificate. Whole crossing source shapes remain intact, and a loader query is bbox broadphase. A future renderer must implement precise feature/country clipping and its own geometry interpretation rather than rendering every returned candidate indiscriminately.

## Verified Python results

Command, from the game checkout:

```sh
/private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geodata -p test_spatial_index.py -v
```

Twelve analytic tests pass: far-centroid crossings, country holes, geometry crossing from an outside owner, multipart footprints, same-owner dedup, explicit invalid-geometry handling, unsafe names, compressed/shifted frames, missing owners, hash/count mismatch and symlink refusal.

The actual full build completed at background CPU priority in 236.666 seconds. The output is now tracked as `game/data/geography/osm-2026-10-27/spatial-index.json`, byte-identical to the original private build:

- `/private/tmp/singapore-fidelity/geography-stream/spatial-index-r1.json`
- 73,655 bytes; SHA256 `3ee2381ced3e0836a41d9c73de26bdad14a85d061fafccda2947245a5764e5f7`
- 906 canonical owners, 398,453 processed source features
- 1,798 country-intersecting cells, 950 cells with dependencies
- zero invalid source geometries
- build log: `/private/tmp/singapore-fidelity/geography-stream/index-build-r1.log`

Build tool verifies canonical tile byte lengths, SHA256 values, feature counts and owner coverage before reporting success. It refuses to overwrite an existing output. The 12th test adds exact source-frame/origin validation after the actual build; the existing output already satisfies the same frame.

Example regeneration, with a **new** output filename and normal background task policy:

```sh
taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python game/tools/geodata/build_spatial_index.py game/data/geography/osm-2026-10-27 --output /private/tmp/singapore-fidelity/geography-stream/spatial-index-r2.json
```

## Runtime API

`SingaporeMapData` in `game/src/world/geography/map_data.gd` is a RefCounted read-only loader:

```gdscript
var source := SingaporeMapData.new()
if not source.open_snapshot("res://data/geography/osm-2026-10-27", index_path, 12):
    # Surface source.last_error. Do not treat a failed query as an empty world.
    return
var candidates := source.features_in_region(Rect2(-300, -1800, 1600, 1800), ["building"])
# An empty array can be either no candidates or a failure; inspect last_error.
```

- `open_snapshot(directory, index_path, cache_capacity=12)`: validates metre frame/origin, canonical manifest, safe owner inventory, dependency references, exact snapshot/boundary hashes and a separately tracked full-index SHA256/byte-length identity descriptor. Cell/feature counts and positive-feature owner coverage are reconciled. Capacity is 1..64 files.
- `features_in_region(Rect2, kinds=[])`: maximum 64 cells, finite rectangle ends and safe per-axis/domain limits checked before integer multiplication; gathers referenced owners, validates each first-load tile checksum/schema and finite coordinates, bbox-filters, deduplicates by `kind|id`. Conflicting duplicates or any bad owner fail the entire query instead of accepting partial world data.
- `metadata()`, `spatial_metadata()`, `cached_tile_count()`, `clear_cache()`, `last_error`, `stats` expose source identity and cache/query evidence.
- Full source dictionaries and `height_m: null` remain unchanged. The caller must not mutate returned dictionaries.
- Metadata <=16MiB and individual tiles <=32MiB. LRU bounds the cached owner entries. It does not bound results retained by the caller, nor guarantee a small query cannot depend on multiple large owner files. Stream-out logic must release result references.
- Cached tiles are trusted until eviction or `clear_cache()`; checksum is enforced again on the next load. Runtime file watching is not included.
- No mesh generation, height inference, street/driving semantics, async background runtime loading, GPU work, FPS/performance acceptance or completed-city claim.

## Parent-run engine verification

The child did not launch an engine. Godot compile/runtime status is **UNVERIFIED** pending the parent running the owned engine wrapper. Suggested command:

```sh
bash loop/singapore-fidelity/run_engine.sh geography-data-r1 150 /private/tmp/singapore-fidelity/geography-data-r1 -- --headless res://src/systems/fidelity_tests/geography_data_test.tscn -- --qa-session /private/tmp/singapore-fidelity/geography-data-r1/session --geography-index=/private/tmp/singapore-fidelity/geography-stream/spatial-index-r1.json
```

The scene writes a report under the explicit private QA session. It refuses existing fixture directories, unsafe paths and symlink ancestors. Synthetic tests cover crossings, duplicate semantic roles, unknown heights, bounded LRU, warm-cache hits, outside/oversized queries, corrupt tile/snapshot/boundary and path traversal. With `--geography-index=...`, it queries the real snapshot and checks all three MBS tower IDs (`way/116801004`, `way/172307472`, `way/172307471`) and Shoppes building relation `relation/2298319`. Omitting this argument explicitly reports actual source NOT_RUN.

## Independent critique and hardening

A fresh read-only critic found twoP2 issues: altered dependency-table contents could pass header checks, and extreme finite query spans could overflow signed64-bit multiplication. Root added `spatial-index.identity.json` (full-index hash/bytes, bound manifest/boundary hashes and counts), consistency/positive-owner coverage checks and bounded axis/domain guards before integer conversion/product. The canonical manifest and906tiles remain unchanged, so the hash graph is non-circular. This is source-controlled artifact integrity, not signed-distribution security.

The critic independently approved the fixes by code review and matched the actual73655byte index/SHA256 and950cells/906owners/398453features. Godot compile/runtime remains **UNVERIFIED**. New engine regressions cover removed-cell corruption, a resealed missing owner, a resealed wrong-count empty dependency table, huge finite32-bit-axis spans and finite inputs whose Vector2 end overflows. Malformed path/snapshot cases reseal only labeled synthetic data so they still reach the intended structural validation.

The owner is currently playing a root-owned game. No second task engine is launched for these checks while it is live.
