# Versioned regional full-source-tag enrichment

This metadata sidecar recovers factual tags omitted by the pinned v1 extractor. It does not mutate v1 geometry/tags, revise the geometry compiler, infer dimensions, or complete the one-to-one city goal. No engines, GPU work, stock art, accounts, APIs, credentials or uploads are involved.

## Source binding

The pass uses the exact same privately held Geofabrik PBF as canonical v1, verified by streaming SHA256 before the metadata scan:

`5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd`

Only requested way/relation IDs are retained. Pyosmium reads WAY|RELATION entities with no node-location cache or geometry assembly. The regional request contains789 logical features but788 distinct source IDs: Rain Oculus is one source way represented as both water and waterway. Source IDs retain their type, so `way/1` and `relation/1` are distinct.

The sidecar binds all of:

- Exact PBF checksum and source snapshot UTC.
- Exact canonical snapshot manifest checksum.
- Exact compiled geometry-patch manifest checksum.
- Exact regional `features.json` byte checksum.
- Each semantic feature’s original source-record checksum and its typed OSM source identity.

The raw PBF remains private and is not copied into this repository or the sidecar. Private input paths, environment values, tracebacks and credential values are excluded from the tool’s output documents and CLI reports. Public OSM source metadata includes version/timestamp/changeset when available. Separate © OpenStreetMap contributors / ODbL1.0 attribution and public source/license URLs are retained. Missing source version/time stays null rather than an invented revision.

## Interface

New files:

- `game/tools/geodata/enrich_source_tags.py`
- `game/tools/geodata/test_enrich_source_tags.py`

`input_binding(...)` checks the catalog/patch/canonical snapshot/PBF chain. `catalog_targets(...)` deduplicates typed source IDs while retaining all semantic feature keys. `scan_pbf(...)` verifies exact PBF bytes, collects full source tag dictionaries and checks input file identity did not change during scanning. `enrich(...)` performs exact comparisons against **every** tag already present on every bound canonical feature. Conflicts, missing source objects, duplicate source objects and conflicting header snapshot time are explicit unresolved audit results. `write_sidecar(...)` refuses to overwrite previous evidence.

No numerical conversions are performed. Original string values for all tags are preserved, including conditional access, lane/sidewalk widths, elevation/datum, construction/proposed distinctions, multilingual names, addresses and roof/building variants where actually supplied. A tag missing from this exact source object is not converted to false, no, zero, or proof of real-world absence.

Run with the existing geodata venv, under normal background CPU policy:

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python game/tools/geodata/enrich_source_tags.py \
  --pbf <private-exact-input.osm.pbf> \
  --expected-pbf-sha256 5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd \
  --catalog <bound-mbs-bayfront-r3-features.json> \
  --patch-manifest <bound-mbs-bayfront-r3-manifest.json> \
  --snapshot-manifest game/data/geography/osm-2026-10-27/manifest.json \
  --output <new-regional-sidecar.json>
```

The tool exits0 only when the audit is ready for an exact-bound overlay; unresolved audit results are preserved with exit1. Input/identity failures exit2 with sanitized diagnostics. No background loop or national output sweep is created.

## Later loader merge contract

A future loader must first verify the sidecar checksum/schema and **all** binding hashes against the intended catalog and snapshot. Do not merge by numeric ID alone, a loosely matching filename, a later live OSM query, or a new source timestamp.

Require `audit.ready_for_exact_bound_tag_overlay == true`, then require each requested record’s status `exact_canonical_tags_match`. Check its semantic feature key and original feature checksum. Only then expose its full dictionary as a new read-only source-tag view for each listed semantic role. Keep canonical geometry, source-record hashes and canonical v1 dictionaries unchanged. Sidecar values do not overwrite parsed `height_m` or add estimated metrics. If source or catalog changes, generate a separately versioned sidecar and re-audit rather than silently mixing snapshots.

The complete tag dictionary may be useful for rendering or navigation decisions, but those consumers still need explicit semantic interpretation and verification. For example `layer=1` is not a metric elevation, `building:levels=55` is not a surveyed height, and a path with no motorcar tag is not automatically a public road.

## Verified actual result

Final output: `/private/tmp/singapore-fidelity/geography-metadata/mbs-bayfront-tags-r1.json`

SHA256: `d796187792548156803a7b03a04861120b1492b80ed289152379c0286e899ed4`

- 622,148 bytes;19.46 seconds including exact PBF verification and one metadata scan, at background/nice10 priority.
- All788 requested typed source IDs found; all canonical v1 tag comparisons match.
- Zero conflicts, missing IDs, duplicate source objects or header-time conflicts.
- Header generator `osmium/1.16.0`, replication sequence4952, snapshot2026-10-27T21:23:59Z.
- 4,642 source tag entries across those IDs;2,105 entries additional to canonical v1.
- Recovered47 bicycle tags,163 roof:material tags,1 proposed-road classification and additional multilingual/address variants.

The exact original PBF supplies **no general carriageway-width, elevation or elevation-datum measurements for this regional target set; one `cycleway:width=5` tag is preserved with its narrower cycleway meaning**. Therefore road width and vertical-profile/terrain gaps remain unresolved after enrichment; their absence cannot be blamed solely on the old extractor or filled with arbitrary estimates. This statement is limited to the selected source objects/snapshot, not every object or data source in Singapore.

`inspection-r1.json` beside the private sidecar has complete binding, code hashes, tag-family counts and shared source-identity roles. `verification-r1.json` in this folder stores a compact non-sensitive receipt.

## Tests

```sh
/private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geodata -p test_enrich_source_tags.py -v
```

**13 tests passed**, including a native synthetic PBF scan, typed/semantic identities, same-way/two-role mapping, full string retention, exact existing-tag conflicts, missing/duplicate IDs, header-time conflicts, catalog/snapshot/PBF binding, deterministic output/no overwrite, and no accidental private input paths or environment sentinel output.

This verifies data identity and tag preservation. It is not survey, access-law, architectural, mesh, rendered quality, runtime/gameplay or performance acceptance.

## Independent integration review

Fresh read-only critic independently reran13/13 tests, rehashed the exact originalPBF and all bound manifests/catalogs, verified every788record (covering789semanticfeatures), and approved this exact sidecar's code/data integrity. The actual source supplies onecycleway:width tag; it is not a general roadway width. All missing measures remain unknown. No Godot overlay consumer, rendered city or gameplay acceptance is implied.

The byte-identical reviewed sidecar is tracked atgame/data/geography/compiled/mbs-bayfront-r1/source-tags.json, SHA256d796187792548156803a7b03a04861120b1492b80ed289152379c0286e899ed4. The geometry patch manifest remains unchanged; the metadata file binds independently to that exact catalog/manifest.
