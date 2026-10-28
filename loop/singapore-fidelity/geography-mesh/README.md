# Source-metre regional geometry compiler

This is source geometry preparation for the full one-to-one Singapore goal. It does not replace the playable world, establish terrain or produce visually accepted architecture/interiors. The existing quality target remains unchanged. A flat reference-plane render of these buffers must not be presented as the finished game.

Only new compiler/test files and this note were edited. No engine, GPU work, Git mutations, canonical snapshot changes, asset generation or account/API activity was performed by this builder. Current shared-brain revision was refreshed successfully to `6e4bcb21855ec88c0513ff4de9ee0e835046c938` before work. The owner’s installed play session was not touched.

## Input and source authority

Input is the pinned `game/data/geography/osm-2026-10-27` snapshot plus its spatial dependency index. OpenStreetMap attribution/ODbL1.0, source timestamp, PBF hash, snapshot manifest hash, boundary hash, dependency-index hash and every loaded canonical owner checksum are carried into the compiled manifest. Source attributes are observations, not independent certification of architectural accuracy.

The source is already SVY21 EPSG:3414 projected metre geometry, origin E30000/N30000, Godot -X north/-Z east/+Y up. No reprojection, simplification or distance compression is applied. The canonical geometry copied once into the feature catalog is unchanged. Source geometry itself was rounded to four decimal metres by the predecessor extraction; this compiler introduces no new coordinate quantization.

No stock mesh is substituted for mapped footprints. The licensed OSM source supplies this narrow data-conversion stage. Source-first art/animation routing remains necessary when adding actual facade assets, fit-out, materials or motion later; the compiler creates none of those assets.

## Functional API and outputs

`game/tools/geodata/compile_geometry.py` exposes:

- `region_source(snapshot, index_path, bounds)`: verify snapshot/index/country identity and exact frame; read only dependency owner files for a <=64-cell region; verify their bytes/hashes/counts; deduplicate by `kind|id`; intersect requested bounds with the exact country geometry. No 906-file sweep is needed for a regional patch.
- `compile_patch(manifest, records, region, chunk_metres=250, provenance=...)`: return a deterministic source catalog, chunk documents and integrity report. Maximum256 chunks; no silent partial truncation.
- `write_patch(output, compiled)`: write a new directory, refusing to overwrite prior evidence, with per-file SHA256 manifest entries.

`features.json` contains each semantic feature once, preserving its canonical world `[x,z]` geometry, source ID, kind, available name/tags, source-record checksum, owner references and explicit measurement status. Road/path ways are not all driveable streets. Construction/proposed/access semantics must be respected once full source metadata is available.

Each chunk stores only `world_offset_xyz` plus local fragments referencing the catalog's `feature_key` and source checksum. Region/cell clipping can insert derived seam vertices; exact original polygon rings/holes and centreline points remain in the catalog. A crossing feature can have fragments in several chunks without becoming duplicate logical features.

Polygon surfaces use GEOS constrained Delaunay triangulation, preserve holes, and verify union/area identity. Triangle winding gives a positive-Y cross product; normals are `[0,1,0]`. Collision topology points at the **same** vertex/index buffers and hash, avoiding separately fabricated collision outlines. Collision activation is deliberately deferred until correct surveyed vertical placement and runtime tests exist.

Path clipping follows ordered canonical source segments. This preserves direction, partial seam-aligned segments and retraced paths rather than dropping/doubling seam length. Exactly seam-aligned paths have one positive-side chunk owner, clamped at the request’s outer edge. Full original centreline order remains in the catalog. This is not yet a road lane/navigation network or vehicle surface.

## Explicit vertical and metadata gaps

All surface vertices have `y=0` as a labeled **reference plane**, not an asserted world/terrain elevation. No road strip width, bridge height, tunnel depth, storey height, arbitrary tower extrusion, generic room or roof shape is invented. Unknown building heights remain null. Explicit source heights/widths/elevation tags are separate from renderer assumptions, which are empty. Numeric layers are not converted to metres.

The pinned v1 extractor's `PRESERVE` set retains bridge/tunnel/layer/access, but omits several useful fields including `ele`, `width:carriageway`, `construction`, `proposed`, `vehicle`, `motorcar` and `bicycle`. Therefore missing attributes are **unassessed**, not evidence those properties do not exist in OSM or reality. The compiled report lists observed semantic tags and tags with no patch records. The parent was notified and owns a separately versioned source enrichment; this task does not silently mutate v1 or recover omitted data.

Terrain/base datum, sloped carriageways, bridge/tunnel profiles, unknown heights, full building volumes, architectural facade quality, roofs, source-backed MBS fit-out/interiors, legal/physical driveability, and runtime/gameplay/performance acceptance remain unresolved. A raw footprint or height-tag extrusion would not satisfy the full goal.

## Verification

```sh
/private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geodata -p test_compile_geometry.py -v
```

**16 analytic tests pass**: courtyard holes, multipart footprints, crossing seams, upward winding/normals, shared collision topology, metre offsets/no scaling, centreline direction and bridge/tunnel/layer/access preservation, seam-aligned outer boundaries, partial seams/retraced paths, full canonical geometry retention, unknown-height/width rules, invalid geometry reporting, deterministic bytes, checksum inventory, duplicate conflicts, regional dependency-only reads/checksum/path safety, missing-tag semantics, frame and chunk-budget guards.

Actual final compile, run under Darwin background CPU policy while the owner played:

```sh
taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python game/tools/geodata/compile_geometry.py game/data/geography/osm-2026-10-27 --index /private/tmp/singapore-fidelity/geography-stream/spatial-index-r1.json --bbox -100 -1500 900 -400 --chunk-metres 250 --output /private/tmp/singapore-fidelity/geography-mesh/mbs-bayfront-r3
```

The final output is `mbs-bayfront-r3`; R1/R2 are preserved earlier attempts. R3 includes the final explicit unassessed-tag reporting; R2 already contains the seam correction. The bounded patch covers source-metre bounds X[-100,900], Z[-1500,-400], using13 dependency owner files. It contains789 source features in25 chunks:215 buildings (197 explicit source-height tags,18 unknown),559 road/path ways,11 water features and4 waterways. All559 selected road/path widths and elevation profiles are unknown in this snapshot; `ele` omission prevents an absence claim. All three actual MBS tower source IDs and the Shoppes relation are present.

Compilation measures matching selected/compiled surface area and path length, with zero source-geometry issues. See `/private/tmp/singapore-fidelity/geography-mesh/compile-r3.log` and `inspection-r3.json` for exact final hashes, byte size, source file identities, retained semantic counts and compile time. No Godot compile/import/runtime or rendered visual result was asserted by this child.

## Root integration after fresh critique

Fresh independent review found twoP2s: index contents were unauthenticated and seam ownership could select a missing positive-side cell at country holes. Root added full identity/hash/bytes/count/owner checks and actual-clip boundary ownership.19/19Python tests pass, including new integrity and hole/partial-neighbor cases. Critic independently reproduced the original cases after the fix and checked15additional hole/island/seam/retrace cases without length loss or duplication.

Post-fix R4 compiled from the tracked index, with27files byte-identical to the fully independently auditedR3artifact. Manifest SHA256c789ae8b66506ed19231b7744b04d781b11e1a828d249eea4955a9d59607441f. The attributed data are now tracked undergame/data/geography/compiled/mbs-bayfront-r1. This is source-metre geometry input only; no runtime renderer, migration or appearance acceptance.
