# Source-road graph and physical ribbon plan

## Restart recovery, 2026-10-29

The historical `/private/tmp/singapore-fidelity/` datasets and Python
environment were absent after the Studio restart. Old metadata receipts remain
evidence of their dated runs, not proof of a current complete dataset or a live
worker. The full source city R1 and original DEM remain in the authoring
checkout; the dataset-recovery worker regenerates the exact index-winding R2.

New road CPU outputs use this directory's ignored `generated/` subtree, which
survives a temporary-directory cleanup. They retain the same bounded
supervisors and immutable per-run output discipline. `RECOVERY_2026_10_29.json`
records current recovery status and the authoritative source hashes. The
shared task-local Python runtime is `../recovery/private/venv/bin/python`.

The frozen R5 compiler is unchanged. Fresh timings and ingest-cache provenance
can legitimately change its top-level identity; `audit_recovery.py` checks the
new manifest against the archived original and hashes every graph and physical
payload before accepting exact payload reproduction. It permits only those
two metadata fields to differ. Never copy old timings or claim a new run had
the old identity. Semantic-v2 remains a separate new inference version, and
recovered R5 content is not semantic-v2 acceptance. `audit_artifact.py --source`
now takes the complete durable city dataset and verifies its exact lineage.

The full owner goal remains whole Singapore at source placement plus a coherent explorable MBS. This component does not declare the source world playable or complete. It changes only new road compiler/tests, new source-road loader/QA, source-roads data and this directory. Root owns world/main/actor/traffic/terrain/support/save integration. This builder ran **no engine, GPU or Git**.

## Artifact and verification scope

Frozen CPU-verified candidate is `/private/tmp/singapore-fidelity/source-roads/candidate-r5`, pinned identity **`fc5cb6cbaa19307597e412c779305c72fa373ba18d3e2470811042df3fab9db7`**. Its full graph contains all906 pinned source owners and257845 road/path records. The20 physical work tiles cover sourceXZ bounds[-2000,−2500,2000,2000],6880 car-permitted ways/7281 fragments; that is an explicit compiler work batch, **not a national scene boundary or permanent Bayfront-only world**. The same compiler accepts other bounds.

Current results:19 CPU tests passed; all257845 source ways/911877 original nonzero segments audited; maximum source-axis delta1.14e−13m;327872 emitted triangles/winding audited. Actual emitted face max gradient0.120748 (12.0748%, below0.121 numeric limit). Near-junction source-connected overlap audit passed5441 groups,135444 samples,179821 comparisons; maximum measured mismatch2.39e−6m. This is explicitly **not all-area/full-curve/native/vehicle acceptance**. Nice10 worker exited0 in318s, about779MiB kernel peak (`817037312` bytes; supervisor sampled`800440320`), under2GiB. Native/Godot parsing remains unrun by this builder.

The country graph is disk-backed during compilation. Original PBF node IDs/order, exact full tags, source versions/names/multilingual names and geometry/feature hashes remain associated with the cityR2 catalogs. No line-intersection, equal-coordinate merge,1.5m snap, Manhattan route or undirected expansion is used. Original nodes of incompatible interior grade remain distinct; source endpoints can make an explicitly labeled grade transition only through their common original node identity. Turn-restriction relations and current legal orders are not included or certified.

Country source audit compares every emitted way against the actual pinned city catalogs: original node sequence, full tags, names/hashes, source positions and original segment order/Euclidean length. It checks every emitted native-clockwise triangle and retained holes. This is a source/geometry audit, not an independent fresh PBF node projection, semantic-review or native driving proof.

R1 preserved all source input but failed inferred bridge/tunnel constraints before a complete artifact. R2 graph identity/winding audited, but nearest-centerline lifting caused actual surface slopes up to35.9 despite12% centerline bounds: **its physical surfaces are rejected**. R3 fixed face gradients; the unequal-width seam review prompted R4 common plateau propagation. R4's emitted seam audit then exposed an overhanging-apron bug: disks at covered interior nodes added a second height. R5 draws disks only at true explicit hubs and preserves interior miter sections. These artifacts/receipts remain separate; no earlier partial pass is relabeled as R5 runtime proof.

## Direction, mode and width policies

The planner parses explicit `oneway` yes/−1/no and mode overrides. Roundabout/motorway defaults are separately labeled; `motorway_link` is not silently given a general one-way implication. An absent direction uses a labeled OSM-documented/default application interpretation, not proof of the current traffic order. Ambiguous pedestrian-path generic one-way tags and conditional direction stay unresolved. Foot does not inherit a street's vehicle-only one-way restriction.

Access uses mode specificity (motorcar→motor_vehicle→vehicle→access, bicycle/foot equivalents), including forward/backward keys. Conditional, unknown and restricted access are not expanded into ordinary allowed arcs. Highway-based mode defaults are explicit **game/default policies**, not a Singapore legal-access audit. Lane-specific restrictions and relation turn restrictions remain unresolved. Full tags survive for later refinement. Root's global48 ambient/7 physics vehicle budget remains caller-owned and is never multiplied per tile.

Width priority is numeric `width:carriageway`, then `width`, then source lane count×3.2m. Unsupported/missing width uses an explicitly labeled highway-class reconstruction: default3.2m lane,2m path. A numeric source tag is not survey certification. Rendering keeps actual centerlines; lateral stroke/join/apron shape is a declared game reconstruction, not an as-built curb boundary.

Sources checked for interpretation: [OSM oneway](https://wiki.openstreetmap.org/wiki/Key:oneway), [OSM access](https://wiki.openstreetmap.org/wiki/Key:access), [OSM width](https://wiki.openstreetmap.org/wiki/Key:width), [OSM layer](https://wiki.openstreetmap.org/wiki/Key:layer). Layer is an ordinal, never a metric height by itself.

## Vertical reconstruction and physical surfaces

The preferred terrain input is the existing pinned EGM96 DEM, identity`5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841`. It is separate from source road survey/elevation. Source `ele`/datum tags are retained, not silently blended as verified EGM96 road heights. Missing DEM receives a flagged zero-reference game fallback, never a dryland/support assertion.

The explicit reconstruction raises bridge constraints6m/layer and lowers tunnel targets5m/layer, with source-layer/default-layer provenance retained. A weighted Lipschitz model caps source-edge height variation; car policy12%, ordinary foot25%, steps70%. The default strict solver rejects inconsistent inferred bridge/tunnel constraints. This candidate deliberately selects `bridge-priority`: every conflicting tunnel-depth constraint remains counted/unresolved instead of silently flattening structures or claiming a surveyed profile. **Tunnel walls, cuttings, portals, real deck thickness/piers and terrain cut/fill are not supplied by a top-surface ribbon.** Parent integration must resolve them before calling those routes playable.

Road cross sections, not arbitrary nearest-line lifting, define the emitted mesh. Physical grade allowances use actual triangle altitudes. Explicit original-node junctions use a common incident-width/angle flat approach length, propagated across every covered original segment. These additional constraints affect **height modeling only**; no navigation shortcuts or XY-derived connections are created. Acute merge plateau lengths are bounded128m and capped cases remain recorded for review. Drawn aprons keep each road's own half-width. This avoids a wide flat cap overhanging a narrower descending approach. Clipped triangles preserve their affine height plane.

The compiler rejects a car surface above0.121 actual Float32 gradient; the runtime separately checks actual current-frame geometry against0.122 to allow small re-quantization. These are numeric limits around the nominal0.12, not assurances of vehicle feel or source survey accuracy. Top render and collision use the same vertex/index topology with Godot-clockwise top faces, positive-Y shader normals and no backface/culling bypass. Empty loop interiors remain holes.

## Runtime API

`game/src/world/geography/source_roads.gd` is a RefCounted data/commit component:

```text
configure(complete_artifact_root, pinned_identity_sha256, configured_source_frame) -> bool
prepare_graph(owner_key) -> {ok,plan}                 # bounded read/hash/decode
commit_graph(plan) -> {ok,...}                       # owner-thread cache commit
successors(original_node_grade_key, car|foot|bicycle) -> {ok,source_xyz,edges,...}
way_record(original_way_id) -> {ok,way}              # original names/tags/policies
release_graph(owner_key) -> bool
prepare_physical(tile_key) -> {ok,plan}              # bounded read/hash/decode
build_physical(plan, identity_global_world_parent, optional_material) -> {ok,node,...}
```

Prepare I/O runs on root's worker/setup path, never directly in a render or physics tick. Immutable configuration/descriptors must be established before worker use; graph/scene commits are single-owner/main-thread work. The graph cache is bounded16 owners/200000 vertices/400000 edges. Missing owners/vertices mean request data, never outside-world/void. Returned neighbors include target canonical position/key. A partial cache does not certify full incidence or a real dead end; caller loads neighboring/source owners before planning beyond it.

All graph points remain canonical double arrays. Physical positions reconstruct canonical anchor+local mesh coordinates and subtract the **current frame origin before Vector3 creation**. Parent must have identity global transform; do not place the road world under a rotated MBS site and apply the source transform twice. Tile-local UVs plus canonical anchor phase preserve the4m game texture period without huge absolute float UVs. Root supplies its existing asphalt material; the default gray material is a prototype, not visual acceptance.

Build validates the whole plan before adding scene nodes. It produces one material batch per tile and separate StaticBody3D collision per original way fragment. Each body has `source_way` metadata; the root group has `source_roads_binding` with artifact/snapshot/origin revision. Root can choose feature`way/id`, floor`road_surface`, support`way/id@tile`, then register/stamp only after actual physics commit. The component installs **no** SourceWorldContext dry/land/water/residency assertion. Do not use a broad road AABB as dryland. Source points, width/grade policy and original vertex IDs remain in the prepared feature data for root's precise support/domain integration.

Rebases, occupied collision residency, actor canonical state, traffic lanes/turns, missions/signage/minimap, terrain carving, source save migration and ordinary owner play remain root responsibilities. Existing built geometry must be moved/registered atomically with every other source consumer or rebuilt; no hidden automatic road/actor shift occurs here.

## Reproduction and resources

City input is the completed repaired country artifact `/private/tmp/singapore-fidelity/city-geometry/candidate-r2`, pinned identity`8b84896f8c9134b5933b2f6c3b036d025a1120d526ab12668e32181d4f148963`. It already contains all original references and tags; no new PBF scan, account, API, purchase or download was used by this task.

From scratch, under the existing environment:

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python \
  game/tools/geography/compile_roads.py \
  --city /private/tmp/singapore-fidelity/city-geometry/candidate-r2 \
  --expected-city-identity 8b84896f8c9134b5933b2f6c3b036d025a1120d526ab12668e32181d4f148963 \
  --terrain game/data/geography/terrain/mapzen-skadi-2026-10-28 \
  --output /private/tmp/singapore-fidelity/source-roads/new-fresh-candidate \
  --bounds -2000 -2500 2000 2000 --grade-conflict-policy bridge-priority
```

The optional `--reuse-ingest <terminal-owned-candidate> --expected-ingest-sha <exactDBSHA>` copies only this task's completed, hashed ingest cache, checks all906 source descriptors/counts, recomputes policy/arcs/heights with the current compiler and explicitly records that raw geometry was not reparsed in that reuse. The original source pass verified every catalog and original-node association. An active/foreign/unpinned cache is not a handoff. Every output/log/evidence prefix must be new; existing results are refused.

Supervisor samples only its owned worker, enforces2GiB RSS/3600 CPU/7200 wall, TERM/grace then kill only if necessary. These are resource guards, not an owner clock. Full data/SQLite caches stay private/local; metadata-only artifact records/reproduction facts in Git are not a complete runtime dataset and must not be configured as one. OpenStreetMap/ODbL and DEM attribution remain separate from game-code licensing.

## Parent-run native gate

```sh
bash loop/singapore-fidelity/source-roads/run_native.sh source-roads-fixture-r1
```

No engine has been run by this builder. The fixture is explicitly **synthetic**, uses the actual source-frame definition only, and tests cache/direction/grade separation, above/below-bridge rays, actual collision hole, winding rejection, an unequal12.8m bridge/3.2m approach, and a capsule stand-in physically walking up/down both seams. It does not instantiate production Player/Car or drive the real Singapore route. Its report/driver must finish cleanly; a partial count or denied launch is not a runtime pass.

`ACTUAL_PRIMARY_ROUTE_R5.json` separately identifies the5.267km original South Bridge Road junction→Esplanade Drive bridge `way/763010995`→Bayfront Avenue near MBS, using only directed original-node arcs. All107 original ways occur in the physical work batch. Reproduce using `extract_primary_route.py --artifact <complete candidate> --output <fresh receipt>`. That graph/candidate route still requires **actual SourceWorld production car/foot traversal**, collision/terrain/support/restore checks and real ground/aerial visual critique before playability or fidelity acceptance. No sixth relay wave, new four-hour clock or owner implementation question is introduced.
