# Emitted area-factory exception audit

**Observed result: all three recorded factory failures have complete valid original-source node envelopes outside the exact Singapore country multipolygon.** This resolves the geographic scope of those three logged exceptions; it does not certify total source completeness.

This narrow audit asks whether the three recorded `area_geometry` exceptions could omit Singapore objects. The original extractor calls the multipolygon factory for selected areas across the Malaysia/Singapore/Brunei PBF **before** checking country intersection. Therefore a factory exception is not automatically a missing Singapore feature.

The builder owns only `game/tools/geodata/audit_area_failures.py`, `test_area_audit.py` and this notes directory. No canonical dataset, geometry/metadata/topology/compiler/index/loader/extractor files, engines, GPU sessions, Git state, accounts or APIs were changed. The raw PBF stays private.

## Exact scope

The audit reproduces the original `Extract.area` predicate and factory/JSON parsing behavior:

- Country: `ISO3166-1=SG`, or admin2 with the same Singapore name fallback.
- Building: presence of `building` or `building:part`, including the predecessor's key-presence behavior.
- Water: `natural=water` or presence of `water`.
- Factory call and JSON parsing happen before spatial filtering, as in the original.

Successful non-country geometries are discarded immediately rather than retained/exported for every object in the regional PBF. Successful country factory geometry is compared against the exact pinned country multipolygon. Every emitted factory failure records typed original way/relation identity, relevant source tags, failure exception type, complete raw ring/node validity counts, complete valid-node bounds, ordered node/position hashes, closure flags and bounded first/last ring samples. Large rings are not dumped wholesale.

Classification is deliberately conservative:

- `outside_country`: every raw coordinate was accessible/valid, and the complete valid-node envelope is disjoint from the **exact country geometry**, including holes/islands.
- `potentially_missing`: that envelope touches/intersects the exact country. No invalid polygon repair or presence claim is made.
- `UNKNOWN`: coordinates/rings are invalid, missing or inaccessible, or the exact comparison cannot be evaluated. A known outside-looking partial envelope is insufficient.

The envelope belongs to the failed object; it never substitutes for Singapore's boundary. No `buffer(0)` repair, invented polygon, inferred missing tower, or canonical mutation is performed.

**Native assembly remains a separate gap.** Pyosmium/libosmium may reject source objects before emitting an area callback. This tool cannot count those from factory events and always records `native_assembler_suppressed_objects_audited=false` and `source_completeness_certified=false`. A native test includes an unclosed building that is not emitted, demonstrating why even zero in-country factory exceptions is not proof of complete OSM coverage.

## Identity and resource bounds

The exact PBF checksum is required:

`5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd`

The country SHA256 is separately pinned to the current canonical boundary and matches the predecessor spatial index:

`c25cce8de57f280b68bd1436deedc3eaa3eb8bebf50ec334f5d9dbfd826b9c45`

PBF header time must match the canonical snapshot. The report binds those checksums, the canonical manifest, available header metadata and original extractor source hash. Separate OSM attribution/ODbL1.0 is preserved; no input paths, credentials or full source payload are emitted.

Area assembly requires source locations. It uses `sparse_file_array` disk backing rather than the predecessor's unconstrained `flex_mem`, and a task-owned supervisor enforces bounded work:

- 2GiB worker RSS, sampled every second; supervised rather than a kernel hard memory limit.
- 2GiB location-index logical size; safe disk-headroom check before starting.
- 240 CPU seconds soft limit, plus15 seconds hard-limit grace.
- 480 wall seconds; only the owned worker is terminated if a budget is exceeded.
- Darwin background class and nice10 launch; no render/GPU/UI work.
- Maximum32 failure records,32 detailed rings per failure and8MiB report. All failure-ring coordinates still contribute validity/bounds even when sample records are omitted.
- Regenerable location index removed only after the owned worker has exited; source PBF and audit receipts preserved.

If the run cannot finish safely it reports incomplete/pending rather than silently relaxing limits or claiming a result. No automatic retry loop is created.

## Tests and invocation

```sh
/private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geodata -p test_area_audit.py -v
```

**14 tests passed** (the original12 plus bounded raw-source recovery and conservative missing/empty/nested relation-member cases): disjoint/potential/unknown classifications, exact holes/islands, degenerate envelopes, original key-presence predicates, bounded samples with complete bounds, inaccessible rings, explicit assembler coverage limits, bounded/no-overwrite output, native disk-backed area events, suppressed unclosed source way, and exact PBF/country/header binding failures.

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python game/tools/geodata/audit_area_failures.py \
  --pbf <private-exact-input.osm.pbf> \
  --expected-pbf-sha256 5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd \
  --snapshot-manifest game/data/geography/osm-2026-10-27/manifest.json \
  --country game/data/geography/osm-2026-10-27/singapore-boundary.geojson \
  --expected-country-sha256 c25cce8de57f280b68bd1436deedc3eaa3eb8bebf50ec334f5d9dbfd826b9c45 \
  --output-dir <new-private-audit-directory> \
  --max-rss-mib 2048 --max-index-mib 2048 --max-cpu-seconds 240 --max-wall-seconds 480
```

## Observed exact factory pass

The complete original factory pass is preserved in `/private/tmp/singapore-fidelity/geography-area-audit/area-r1/audit.json`, SHA256 `8176880070422ac90aa7637b33fa61dd050c3d707b064c17333d8e04e5970081`.

- 1,983,323 emitted area events;1,771,396 eligible factory attempts.
- 1,744,371 building attempts,27,024 water attempts,1 country attempt.
- Exactly3 factory exceptions, reproducing the canonical manifest count.
- Country relation536780 factory geometry matches the exact pinned country.
- Each failed assembled area had zero rings/node references. Therefore the first-pass classification correctly remained `UNKNOWN`; an empty area event alone cannot prove outside-country status.
- 138.644 CPU seconds,153.557 worker wall seconds,154.974 supervisor wall seconds.
- Kernel peak RSS770,310,144 bytes (~735MiB), below the2GiB budget; sampled disk index486,539,712 bytes (~464MiB), below2GiB. The owned index was removed after the worker exited.

## Bounded original-source follow-up and final result

Because the failed assembled events had no ring coordinates, an additional metadata-only fallback recovered only the three original source IDs, the one relation's member ways and their required original nodes. It did **not** replay the heavy whole-PBF area assembly or construct a location cache.

The fallback requires the exact first-pass audit hash and all original PBF/country/canonical bindings. C++ ID filters retain only those source records. Complete source-way reference lists are inspected (bounded hashes/samples are emitted), relation members/roles remain factual, and all required original-node coordinates must be present/valid. Missing/empty ways, missing/invalid nodes, nested unresolved relations, source-tag conflicts or duplicate objects keep classification `UNKNOWN` regardless of any partial outside-looking bounds. No rings are repaired/stitched into fabricated geometry.

To run this mode, add the following flags to the same pinned input command and use a **new** output directory:

```sh
--raw-source-audit <immutable-area-r1-audit.json> \
--expected-prior-audit-sha256 8176880070422ac90aa7637b33fa61dd050c3d707b064c17333d8e04e5970081 \
--output-dir <new-private-raw-source-audit-directory>
```

Current final artifact: `/private/tmp/singapore-fidelity/geography-area-audit/area-r3/audit.json`

SHA256: `bda48e5adc1ced9074ad141d507b2bef30d0b607c7814b176dc51f65e4d245b6`

The original event classifications and evidence remain in the final report alongside separate `raw_source_evidence`:

| Original source object | Tags | Complete source-node bounds (lon min, lat min, lon max, lat max) | Valid distinct nodes | Result |
| --- | --- | --- | ---: | --- |
| way/1113415118 | building=yes | [101.6995717,3.1621339,101.6997774,3.1623306] | 11 | outside_country |
| way/1215622359 | building=university; name=B03 | [103.635362,1.5592842,103.6355665,1.5595091] | 9 | outside_country |
| relation/19881155 | building=house | [102.1952724,6.1676826,102.195435,6.1679245] | 18 | outside_country |

The relation has outer way1453563194 and inner way1453563195. All four required source ways, one relation and38/38 distinct source nodes were recovered. There were zero missing/invalid coordinates, unresolved/nested members or source conflicts. Each complete raw-source coordinate envelope is disjoint from the **exact** Singapore multipolygon. These three logged factory exceptions therefore do not represent omitted Singapore objects under the pinned country-intersection criterion.

Final targeted fallback used11.238 CPU seconds,2.959 worker wall seconds (4.196 supervisor wall), kernel peak RSS184,795,136 bytes (~176MiB), with no location index. It retains source facts only. R2 is an earlier fallback artifact; R3 includes the final conservative empty-member guard and correct metadata-only resource labeling.

`verification-r3.json` in this folder and private `inspection-r3.json` preserve final source/test hashes, bindings, bounds and actual resource receipts. All14 tests passed. The full one-to-one Singapore source/runtime/visual target remains open, especially source objects the native assembler suppresses before area emission, unmapped real-world features and later geometry/height/interior/runtime acceptance. No blanket source-completeness guarantee follows from resolving these three recorded errors.

## Independent review

A separate critic reran all14tests, rehashed inputs and used independent raw-PBF handlers to recover fourways, onerelation and all38requirednodes. It reconstructed temporary nativePBF fixtures reproducing allthree zero-ring factory errors, and confirmed each complete source envelope is disjoint from the exact pinned country polygon. No source-levelP1/P2 remained. This resolves only the three logged exceptions; native-assembler suppressions and unmapped real features remain unaudited. The canonical manifest is unchanged.
