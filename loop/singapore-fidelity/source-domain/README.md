# Immutable source-domain adapter

This implements the horizontal source-domain provider required by `source-world-migration/CONTRACT.md` and the source-context schema. It is a component, not a replacement bootstrap, national runtime streamer, completed terrain or MBS integration. Root owns actor/physics/save/normal-world integration.

Only new assigned source-domain adapter/compiler/test files and `game/data/geography/domain/osm-2026-10-27/` were authored. No previous canonical/source tool, main/Player/aircraft, engine/GPU/UI, Git state, service, paid job or provider was changed. Current shared-brain revision `a67557283f99` was refreshed/verified before work.

## Data and authority

`game/tools/geography/project_source_domain.py` validates the actual canonical manifest/frame, WGS84 national boundary and independently verified coast artifact descriptor/checksum. Coast PBF/snapshot/country/projection binding must agree with canonical v1. It projects the national Polygon/MultiPolygon directly through the existing SVY21 helper. Coast enclosure is already projected and is not projected/scaled again. Source geometry is not repaired, simplified or replaced with a rectangle.

The runtime dataset includes only useful country/coast polygons, rather than decoding the full10MB coast audit/global source ring catalog:

- Territory:3 polygons,3 rings,246 vertices.
- Coast enclosure:64 polygons,64 rings,9834 vertices.
- `domain.json`:392,620 bytes; SHA256 `0607712bb5bcca43709cf62b30b50ef152a344d91ee760866098c42065b8cc9d`.
- `identity.json`:1871 bytes; SHA256 `82e7c84c55f8f03ca9e646b2fa6f66e8921f23f072e961c533646ab414d12834`.
- Expected canonical manifest: `d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983`.

Both files live in `game/data/geography/domain/osm-2026-10-27/`. The independent identity pins output bytes/hash, all input hashes, counts and exact versioned provider descriptors without a self-hash cycle. Attribution remains separately © OpenStreetMap contributors / ODbL1.0. This identity authenticates the declared inputs, not survey completeness or real terrain/elevation.

## Native API

`SingaporeSourceDomain` in `game/src/world/geography/source_domain.gd` is a RefCounted, single-owner immutable data adapter:

```gdscript
var domain := SingaporeSourceDomain.new()
var ok := domain.configure(
    "res://data/geography/domain/osm-2026-10-27",
    TRUSTED_DOMAIN_IDENTITY_SHA256,
    frame.metadata().snapshot_manifest_sha256)
# Handle false and domain.last_error. Do not substitute a default map.
for row in domain.provider_descriptors():
    context.register_provider(row.kind, row.provider_id, row.source_reference)
# Root can supply domain.observe as the existing SourceRuntime Callable.
```

Configuration requires all three explicit arguments and succeeds once. It rejects checksum/source/frame/version/registry/inventory mismatches, unsafe file names, leaf symlinks and unsupported semantic claims. A changed dataset needs a new adapter/context. No lazy default map, auto reconfiguration or per-frame file watching is provided.

`observe(source_xyz)` accepts exactly an Array or PackedFloat64Array of three finite numeric components within the source frame's10,000,000m coordinate bound. It rejects Vector3/PackedFloat32Array, booleans, nonfinite or malformed coordinates rather than copying already-lost precision. Source XYZ is never converted to an absolute engine vector.

The returned rows match `SourceWorldContext.bind_observation` payloads:

```text
territory: {state: inside|outside|unknown, payload:{}}
land:      {state: unknown, payload:{}}
water:     {state: unknown, payload:{}}
```

A separate `diagnostics` dictionary reports `territory_relation` and `coast_enclosure_relation` (`inside`, `outside`, `boundary`, or unknown for invalid/unconfigured input), source/identity hashes, unresolved semantics and segment counts. The Y component is validated but does not change horizontal polygon coverage. It does not become a sea plane, height threshold, ground clamp, water bottom, support hit or recovery permission.

**Land and water intentionally stay unknown in this stage.** Country coverage is not land. Coast enclosure can contain reservoirs or other unresolved inland water; it is not proof of dryland or a finite3D water column. Absence from the enclosure also does not establish complete hydrology. Dry architectural volumes and actual collision/support remain separate source-context/physics providers; do not add a broad fake dry default to make restore pass.

Provider registry version is `singapore_source_domain_registry_v1`; result schema is `singapore_source_domain_result_v1`. Descriptors are exact ordered territory/land/water rows tied to the domain payload hash. The context receives fresh rows bound to its own query/epoch; this adapter moves/registers nothing by itself.

## Geometry, boundaries and cache

All arithmetic uses scalar IEEE64 floats and packed64 arrays until root later subtracts the active origin. No absolute Vector2/Vector3 or Geometry2D predicate is used. Point-in-ring translates each edge calculation before ray comparisons. Polygon holes and multiparts are independent; outer/hole boundaries are inclusive territory coverage while hole interiors are excluded. A boundary reported by one polygon is inside the aggregate territory unless another polygon supplies strict interior. There is no artificial epsilon-width boundary band; collinearity uses the double arithmetic result, not arbitrary-precision predicates.

Each source ring is packed once. Bounding boxes reject irrelevant polygons/rings;32 Z stripes index candidate edges for larger rings without changing coordinates. Edge references are bounded to roughly8 per source edge; a pathological ring falls back to one bounded linear bin. All provider descriptions and metadata returned to callers are detached.

Configuration reads/hashes/decodes exactly two bounded files off the frame-critical path. `observe` performs no I/O or JSON decoding. Limits are16MiB data,128KiB identity,4096 polygons,8192 rings and250,000 total vertices; combined inventories are enforced. Counters expose reads, decodes, cached vertices/edge references, query count and segment tests. This is not a background streaming/thread synchronization system and does not prove gameplay60FPS.

## Verification and parent-run native QA

Python command:

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geography -p test_project_source_domain.py -v
```

**9 tests passed**, including1003 independent Shapely `covers` comparisons, holes/multipart/inclusive borders, millimetre-scale regions around80km coordinates, exact projection/no source mutation, coast/territory/unknown-water separation, bad geometry/frame/source binding, separate identity/no overwrite, actual national sources and an administrative-sea point outside coastal enclosure.

Actual data compilation used the same venv/background policy:

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python game/tools/geography/project_source_domain.py \
  --manifest game/data/geography/osm-2026-10-27/manifest.json \
  --country game/data/geography/osm-2026-10-27/singapore-boundary.geojson \
  --coastline game/data/geography/coastline/osm-2026-10-27/coastline.json \
  --coast-identity game/data/geography/coastline/osm-2026-10-27/identity.json \
  --output-dir <new-domain-directory>
```

The prepared output directory already exists and is never overwritten. Use a new output for a deliberately versioned rebuild.

The child ran **no Godot engine**. Root completed the native R1 scene with **43/43 checks passed**, exit0, clean engine/supervisor logs and reaped processes. The child read the actual report and pinned its hash in `VERIFICATION.json`. A native data-only scene is provided at `game/src/systems/fidelity_tests/source_domain_test.tscn`:

```sh
bash loop/singapore-fidelity/run_engine.sh source-domain-r1 90 \
  /private/tmp/singapore-fidelity/source-domain-r1 -- \
  --headless res://src/systems/fidelity_tests/source_domain_test.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/source-domain-r1/session
```

It requires a fresh owned private QA path, uses a45s watchdog and writes only its isolated fixtures/report. It tests actual pinned data, double precision, holes/borders, semantic unknowns acrossY, typed invalid inputs, malformed/resealed fixtures, checksums/path traversal/registry/source mismatch, detached immutable metadata, no decode per1000 repeated queries, and actual context registration/binding/evaluation. It creates no actors, terrain, collision, owner-save writes or synthetic input. Report/log cleanliness, not script intent, determines native acceptance. The current receipt records Python success and the clean native43-check result. Actual200 classification queries took28,953 microseconds in this data-only QA run; this is a query measurement, **not rendered/gameplay performance acceptance**. Actor/source-bootstrap, national streaming, hydrology/terrain and MBS integration remain root work.
