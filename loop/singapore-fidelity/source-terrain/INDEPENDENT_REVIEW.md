# Source-terrain independent review

Reviewed UTC: 2026-10-29T00:22:15.358397+00:00

**Final bounded code/data approval. Both P2 findings below are resolved; no remaining P1/P2 was found in the reviewed repairs or exact artifact.** This is an independent review of the coarse DEM component, not physical terrain, current Singapore survey, MBS floor alignment, gameplay or rendered acceptance.

## Scope and source identity

The original implementation was frozen at parent checkpoint `aa78fca`; the compiler's pre-enumeration guard was then repaired during this review. The existing data were not regenerated or relabeled as produced by the repaired compiler. Only this new review file was written by the critic. No engine, GPU, UI, Git operation, external data acquisition, source edit or provider/account change was performed. Tests used their own disposable fixtures; the independent data check read the already acquired local files.

| Artifact | SHA256 |
| --- | --- |
| Terrain identity | `5498b502dd7955095d4cb28adf58c43b46a55223a7ece95140c72e0097347841` |
| Terrain manifest | `d3146cef6532abe6e6fe71a2122ae5189810a8e302c8de7e9bb25d2fa61a48c6` |
| Canonical snapshot | `d4c74b3968f07af6558192aa7831ed66eacfde861fae9b33ec14865aabbfc983` |
| Exact country | `c25cce8de57f280b68bd1436deedc3eaa3eb8bebf50ec334f5d9dbfd826b9c45` |
| N01E103 decoded HGT | `1624bdbddd68b01304d4092c05725e84b973a0148914be1c33118199d4201839` |
| N01E104 decoded HGT | `e6ff90a6db7d946a59acd3efabd2fb7de6d66d86e07daba6b362d66a397e1a80` |

## Findings

### P2: grid work guard — repaired and independently rechecked

The original `compile_chunks` enumerated its entire bounding-box grid before testing the 5,000 selected-chunk limit. A finite huge or misprojected polygon could therefore consume unbounded work before reaching that limit. A bounded in-memory interception confirmed the enumeration path without iterating a huge grid or writing files.

Root added finite/positive/domain checks and a candidate-grid budget before enumeration, plus an immediate selected-count guard. I inspected the revised control flow and independently ran the revised **14/14 Python tests**, including huge/in-domain oversized bounds with no enumeration and selected-count rejection before output/sampling. This finding is closed for the reviewed repair.

### P2: partial-file cleanup — initial finding, resolved by final follow-up

`bounded_gunzip` creates a fixed `.hgt.part` with `open('xb')`, but its exception handler unconditionally unlinks that path. If a part already belongs to another writer, exclusive open correctly raises and the cleanup then deletes the other writer's file. The download branch has the same pattern for `.hgt.gz.part`.

Independent safe reproduction used an eight-byte gzip and a pre-existing 30-byte sentinel part in an isolated temporary directory. The function raised `FileExistsError`, created no final output, but removed the sentinel. This contradicts the stated fail-without-overwrite ownership contract. Track whether the current invocation created a part, or use unique owned parts; remove only owned files. Exclusive failure-receipt publication should also preserve existing files. Add pre-existing-part sentinel regressions; network mocking can cover the download branch without another HTTP GET.

This finding does not invalidate the actual two source downloads or derived chunks, whose bytes and receipts passed the independent checks below.

## Independent data checks

- Verified identity/manifest hashes, inventory count, every chunk's filename, size and SHA256, exact canonical frame/snapshot/country bindings and projection-helper hash.
- Rehashed both compressed and decoded local HGT files. Independent gzip decompression and CRC validation reproduced the exact raw bytes. Direct `struct` decoding confirmed big-endian signed int16 and north-to-south source-row orientation. No new HGT request was made.
- All **1,798 chunks / 13,298,008 binary bytes** match their inventory. All **3,435 complete three-post halo overlaps** are byte-identical. Valid stored posts including duplicate halos total **3,324,502**, with zero void posts in this particular artifact. Synthetic void handling remains separately tested.
- Independently sampled nine positions per chunk, **16,182 derived posts** total, using a separate direct inverse EPSG conversion and raw-HGT bilinear implementation, followed by float32 quantization. Every selected value matched the stored little-endian float32 bits; maximum discrepancy was **0 m**.
- Independently rebuilt the exact administrative-country-intersecting chunk set; it matches the inventory. Administrative selection and whole-chunk halos do not imply land, dryness or physical support.
- Reproduced the derivative reference **5.989349365234375 m EGM96** at source `[500,0,-1000]`. This is a data query, not MBS L1 or a surveyed floor. Central-difference normal direction and interpolation were also independently checked at representative actual points.
- Confirmed the native R1 record is **31/31**, exit 0, no fatal errors, child reaped. Its recorded sampler/test source hashes match the files reviewed. I did not run Godot; the native result remains a data-only parent run.

Independent raw/chunk check: **1.578 seconds**, peak RSS **218,595,328 bytes**. No extractor-wide terrain regeneration was performed.

## Runtime/code assessment

The provider requires explicit trusted identity and snapshot hashes, validates the fixed metre frame/grid and bounded inventory, checks binary size/hash on cache load, and retains a bounded LRU. Scalar source arithmetic remains double precision; input Y is not used to invent a datum alignment. Returned metadata/grids are detached. Unknown coverage, voids and failed normal stencils stay unknown rather than zero ground or an invented up normal. The normal is a derived DEM central difference, not a collision/contact normal.

The two-stage interpolation and 25 m grid do not add measurement resolution to the approximately one-arcsecond native postings or any coarser composite contribution. Cache/query timing is not render/gameplay performance. Packaging, terrain meshes, physical collision, residency/rebasing, hydrology and actor/floor integration remain outside this approval.

## Primary source / attribution review

The live [AWS registry](https://registry.opendata.aws/terrain-tiles/) documents anonymous access. Tilezen's [format documentation](https://raw.githubusercontent.com/tilezen/joerd/master/docs/formats.md) supports the HGT encoding and EGM96 interpretation. Its [source notes](https://raw.githubusercontent.com/tilezen/joerd/master/docs/data-sources.md) and [attribution requirements](https://raw.githubusercontent.com/tilezen/joerd/master/docs/attribution.md) support retaining provider credits and modification/quality limits. I found no source/rights overclaim in the current manifest or attribution note. Exact per-pixel contributors and acquisition dates are not established by the 2016 HTTP modification times. Source data terms remain separate from the game code license.

## Initial review code hashes during the repair

| File | SHA256 |
| --- | --- |
| `game/tools/geography/compile_terrain.py` | `e63886204d4b85d5b5292b5e26d025873269ec4c87848845d47c71e759321fc3` |
| `game/tools/geography/test_compile_terrain.py` | `72fcd52e275c0e9bf0f7c41c300acc21cb59661f344dd4b872b4233bac1bc97e` |
| `game/src/world/geography/source_terrain.gd` | `606afc9bf3bf1be355e8df7b16f4cbfcb4079b22b37f258e18b29ad0df0d94ad` |
| `game/src/systems/fidelity_tests/source_terrain_test.gd` | `773cfa517c774b0b15a144654acc59b0aeefe6227cb77ab9a4a5f98e911643ac` |

Shared-brain cache: injected/pinned revision `a67557283f99`; doctor reported `not-recently-checked`. This read-only review did not perform fresh GitHub policy verification or change the cache.

## Final post-critique follow-up

Reviewed UTC: 2026-10-29T00:27:23.094268+00:00

Root froze the repaired compiler and regression tests. I independently ran the full revised **17/17 tests**, exit 0, in 0.352 seconds. Source checksum checks after the run match the final table below. No Godot/engine run or source-data regeneration was performed by this critic.

The cleanup finding is closed: each partial file is associated with the device/inode actually obtained by the current exclusive creation. Cleanup does nothing without that ownership record, and only unlinks a matching inode. Gzip, compressed-download and receipt parts preserve pre-existing files, including dangling links; failure receipts use exclusive creation. I independently repeated the original sentinel and mocked-download reproductions: the existing HGT part, compressed part and failure receipt remained unchanged, with no final source created and zero real HTTP calls. The durable suite additionally covers a foreign receipt part after successful owned source publication.

The earlier grid-enumeration finding also remains closed: finite/domain and candidate-work bounds run before enumeration; selected count is checked immediately after append and before any output/sampling. The actual 1,798-chunk dataset is unchanged and still passes the independent raw/grid/seam checks above. Historic compile receipts were not rewritten to pretend the later guard already existed.

This final approval is for the reviewed source-provider/compiler repairs and exact source DEM artifact only. Current ground/survey accuracy, physical terrain support, architectural-floor alignment, hydrology, packaging and rendered/gameplay acceptance remain unproven.

| Final reviewed file | SHA256 |
| --- | --- |
| `game/tools/geography/compile_terrain.py` | `e63886204d4b85d5b5292b5e26d025873269ec4c87848845d47c71e759321fc3` |
| `game/tools/geography/test_compile_terrain.py` | `c3dc6fc310109946e7c24572bb70df6222a17f10c08fe99fd481f6c040e37f36` |
| `game/src/world/geography/source_terrain.gd` | `606afc9bf3bf1be355e8df7b16f4cbfcb4079b22b37f258e18b29ad0df0d94ad` |
| `game/src/systems/fidelity_tests/source_terrain_test.gd` | `773cfa517c774b0b15a144654acc59b0aeefe6227cb77ab9a4a5f98e911643ac` |
