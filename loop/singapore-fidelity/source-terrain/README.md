# National source DEM input — data component

This stage supplies versioned coarse elevation samples for the full Singapore source-world migration. It does not finish terrain geometry, actor integration, current survey, MBSfloor alignment, water, streaming/rebasing, collision or the city. Root owns native engines and integration. Only the assigned new compiler/test, data directory, source_terrain adapter/QA and this notes directory were changed; no prior canonical/domain/context/runtime/main/actor file or Git state was changed by the child.

## Source-first research and acquisition

Primary documentation was checked live before acquisition:

- AWS registry: public `elevation-tiles-prod` bucket, anonymous access without an AWS account: https://registry.opendata.aws/terrain-tiles/
- Joerd format: gzip SRTMGL1-style3601² WGS84 posts, big-endian signed16-bit, EGM96 geoid metres,−32768 void: https://raw.githubusercontent.com/tilezen/joerd/master/docs/formats.md
- Public S3 endpoint and sources: https://www.mapzen.com/blog/terrain-tile-service/
- Source mixture/age/oversampling and artefacts: https://raw.githubusercontent.com/tilezen/joerd/master/docs/data-sources.md
- Credits/underlying provider terms: https://raw.githubusercontent.com/tilezen/joerd/master/docs/attribution.md

Only the two requested public objects were downloaded, using ordinary GET with no account, key, paid service or endpoint substitution:

| Tile | gzip bytes | decompressed SHA256 | HTTP Last-Modified |
| --- | ---: | --- | --- |
| N01E103 | 5,782,563 | `1624bdbddd68b01304d4092c05725e84b973a0148914be1c33118199d4201839` | 2016-04-23 |
| N01E104 | 2,369,334 | `e6ff90a6db7d946a59acd3efabd2fb7de6d66d86e07daba6b362d66a397e1a80` | 2016-04-26 |

Both returned HTTP200 and exactly25,934,402 decoded bytes (3601×3601×2). Private raw files and atomic acquisition receipts are under `/private/tmp/orchard-geodata/terrain/`. Response ETag, last-modified, length/type/version headers, URL, UTC fetch times and compressed/decompressed hashes are retained. The ETag is not substituted for SHA256. Fresh part files are exclusively published; unexpected redirects, size/CRC/decompression failures and existing unreceipted/mismatched files fail instead of being overwritten or bypassed. No source files are fetched implicitly during runtime/query.

Download code admits exactly the two pinned URLs. The raw PBF/canonical OSM snapshot is not mutated. Attribution is separately recorded in the derived manifest and `game/data/geography/terrain/mapzen-skadi-2026-10-28/ATTRIBUTION.md`, including OSM country-selection credits. The game code license does not replace underlying data terms.

## Derivative grid and seams

The existing SVY21 frame is retained at one metre per unit, origin E30000/N30000, -X north/-Z east. The offline compiler transforms canonical global XZ to WGS84 for source sampling; runtime never converts an absolute engine vector or contacts a map service.

- Global node identity is integer `[indexX,indexZ] *25m`.
- Each1km chunk has40 cells/41core posts, with one additional source post around every edge:43×43 little-endian float32 samples,7396 bytes.
- Core grid nodes and the three overlapping halo columns/rows have identical global indices across neighbors.
- HGT rows run north-to-south; each native shared longitude edge is compared. Any source disagreement becomes a void rather than an average.
- Source bilinear interpolation requires every nonzero-weight posting to be valid. Exact postings do not become unknown merely because a zero-weight neighbor is void.
- Derived voids are canonical float32 NaN. They never become zero ground. Numeric zero is still a legitimate source value.
- Chunk selection intersects the exact projected administrative country; halo/whole-chunk coverage is source reference data, not an assertion of territory/land/dryness.

Actual compile result:1798 chunks,13,298,008 binary bytes; manifest547,700 bytes. All3435 neighboring three-post halo byte comparisons passed. Both native tile shared columns agreed (zero conflicts), and the current compiled coverage has3,324,502 valid stored posts/zero void posts, counting halo duplicates. Synthetic tests retain void behavior independently of this source snapshot.

Current identities:

- `identity.json` SHA256: `5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841`.
- `manifest.json` SHA256: `d3146cef6532abe6e6fe71a2122ae5189810a8e302c8de7e9bb25d2fa61a48c6`.
- Canonical snapshot: `d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983`.
- Exact country: `c25cce8de57f280b68bd1436deedc3eaa3eb8bebf50ec334f5d9dbfd826b9c45`.

A separate trusted identity pins the manifest bytes/hash and expected snapshot; manifest inventory pins every binary chunk. Source receipts, frame and projection-helper checksum are independent bindings, not an OSM-provided height or a surveyed datum certificate.

## Native adapter API

`SingaporeSourceTerrain` is a RefCounted immutable provider:

```gdscript
var terrain := SingaporeSourceTerrain.new()
terrain.configure(DATASET_DIRECTORY, TRUSTED_IDENTITY_SHA256,
    frame.metadata().snapshot_manifest_sha256, 8)
var value := terrain.sample(source_xyz) # observe(...) is an alias
var grid := terrain.chunk_grid(chunk_x, chunk_z)
```

Configuration is explicit/once; no default world map or silently changed version exists. Cache capacity is1..64 (default8), binary chunks7396 bytes each, manifest<=4MiB, at most5000 descriptors. A new provider is required for a changed dataset. Paths, frame, schema, grid, snapshot, byte counts and hashes are checked. Each chunk is hash-checked/decoded on cache load, then uses bounded LRU retention; repeated cached queries perform no disk reads. Returned grid/metadata are detached.

`sample` accepts canonical double Array/PackedFloat64Array XYZ, validates all components, and uses scalar XZ math. Vector3/PackedFloat32Array, nonfinite and malformed input are rejected. The input Y is not treated as a sea plane or elevation correction. Runtime bilinear sampling uses the compiled25m posts; normals use central differences at query±25m from the exact halo. A missing normal stencil returns normal unknown, not a default up vector.

A known result is tagged `state:sampled_dem`, `height_m_egm96`, optional `normal_state:derived_dem` with a double-array normal and provenance hashes/resolution. A missing/void/source-version/checksum failure stays unknown with null height. An inventory miss is not outside-city or zero ground. This is **not** one of the source-context territory/land/water observations: consumers must separately use the exact domain and real physical/residency/hydrology providers. `chunk_grid` returns the declared integer grid indices, copied height samples and NaN void semantics for root's bounded mesh streamer.

## Datum, age and interpretation limits

EGM96 geoid elevation is not ellipsoid altitude and is not automatically the game’s existing architectural/sourceY datum. Datum/frame alignment remains explicitly unverified. The2016 server modification time does not establish a pixel measurement date. Underlying SRTM/radar sources can be older; building/canopy/coastal merge/reclamation artefacts and coarser GMTED/ETOPO contributions remain possible. Native1arcsecond posting is approximately31m here; effective data can be coarser. The25m grid and repeated bilinear interpolation create no new resolution or imaginary fine LOD detail.

A sample near the source MBS location `[500,0,-1000]` is5.989349365234375mEGM96 in this derivative. This is a binary/interpolation reference, **not current MBSL1, hotel ground or a verified surveyed construction level**. It never authorizes a terrain collision, dry ground, navigation, tide/sea surface/bottom, or3D water column by itself.

## Verification

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geography -p test_compile_terrain.py -v
```

**12 Python tests passed**: independent big-endian struct decoding and actual source postings; known bilinear plane/north-row orientation; native seam equality/conflict-to-void; nonzero-weight void semantics; outside/nonfinite coverage; negative global indices; exact gzip/byte/overwrite bounds; tiny compiled halo/grid/hash seams; canonical NaN bits; exact two-URL allowlist. Actual national compilation separately checked3435 seams.

The child ran **no engine**. Native parsing/runtime are pending root. Dedicated QA:

```sh
bash loop/singapore-fidelity/run_engine.sh source-terrain-r1 90 \
  /private/tmp/singapore-fidelity/source-terrain-r1 -- \
  --headless res://src/systems/fidelity_tests/source_terrain_test.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/source-terrain-r1/session
```

The scene tests explicit actual identities and the recorded binary reference, synthetic plane heights/normals/seams, halo identity, bounded cache/no rereads, detached returned grids, void/unknown normals, invalid inputs, stale identity/snapshot, corruption, typed frame and path traversal. It writes only fresh isolated private fixtures/report, has45s watchdog and creates no terrain, actors, owner-save writes or rendered game. A query timing is not render/gameplay performance proof. Full source-world/terrain/MBS integration remains root work.
