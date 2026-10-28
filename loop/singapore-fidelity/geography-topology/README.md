# Original OSM node-identity topology — regional foundation

Current final artifact is **R2 / schema v2**, with original source-node longitude/latitude independently projected and checked against every ordered canonical coordinate. R1 remains immutable as the first-pass predecessor.

This stage recovers original node identities/order for the559 road/path ways selected by the existing Marina Bay Sands/Bayfront catalog. It supplies factual source incidence for later one-to-one road migration. It does **not** establish a legal/physical vehicle-route network, build real-width/elevation roads, replace the playable city, or meet the full Singapore visual/gameplay target.

Only new `extract_road_topology.py`, `test_road_topology.py` and this note/receipt were authored. No prior metadata/compiler/index/loader/extractor files, canonical dataset, engines, GPU instances, Git state, accounts or APIs were changed. The raw PBF stayed private; no source file was uploaded.

## Source and binding

The actual pass verifies the exact original PBF SHA256:

`5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd`

It binds the raw regional catalog bytes, geometry-patch manifest, canonical snapshot manifest, selected semantic kinds/counts and source snapshot time. It reuses the metadata stage's read-only `input_binding` checks and records that helper's checksum in the verification receipt. Per-feature original record checksums remain unchanged.

One metadata-only WAY pass follows checksum verification, under `/usr/sbin/taskpolicy -b nice -n 10`. No source nodes, location cache, geometry assembly or XY-intersection routine are requested. Only selected way references/tags/available source metadata are retained. Full multilingual names and bridge/tunnel/layer/direction/access/construction/proposed strings are read directly from those same source way objects; no loosely matched or later live source overlay is used. Every tag already retained in canonical v1 must match exactly.

Original OSM way node references are copied verbatim and paired by index with unchanged canonical LineString positions. Node count mismatch, canonical-tag conflict, missing/duplicate source way, invalid coordinate schema or header snapshot-time conflict yields an unresolved, non-consumable audit; no truncation, reversed path or fabricated node identity is substituted.

## Sidecar representation

`ways[source_id]` retains the complete ordered node list, semantic feature keys/hashes, source tags/checksum, source version/time when available, closed-way identity and explicit unassessed routing/vertical policy. Repeated IDs and retraces are retained.

`nodes[node_id]` contains every `(source_way, feature_key, node_index, canonical_position)` association, start/end flags, endpoint associations, incident original segments/ways and structural neighbor IDs. Same-node positions are checked pairwise using the min/max extent of all associations against the canonical rounding allowance: **0.0001 metre per axis**. Original coordinate values are preserved, never averaged or compressed.

`source_segments[way_id@index]` references consecutive original node indices/IDs. Each segment exists once per source way/index even when a way has multiple logical roles. Closed and retraced segments remain distinct. Structural neighbor incidence is undirected and expresses source connection only; it is not an oneway/access-aware travel graph.

Connections are never created merely because lines cross or coordinates coincide. Different node IDs at equal XY remain separate, including grade-separated crossings. Conversely a shared source node establishes mapped incidence, not independently surveyed grade or legal manoeuvre permission.

## Critical limits

- **The isolated-way coordinate-order gap is closed in R2.** R1 intentionally lacked original node locations. The owner-authorized second bounded pass reads only the1992 selected original node records through a C++ ID filter, preserves source longitude/latitude/tags, projects with the current georeference, and checks all2794 ordered canonical associations within0.0001m per axis. Missing/invalid/duplicate nodes, reversed/shifted coordinates or conflicting source headers fail readiness. No country-wide node-location cache is created. Original source survey/positional accuracy still is not independently certified.
- Whole selected source ways extend beyond the clipping patch. Their original references stay whole, matching the unchanged catalog geometry. Other ways outside the regional target set can be missing from incidence at those outside nodes; this is not a country-complete junction network.
- `oneway=-1`, roundabout, bridge/tunnel/layer and access strings remain source metadata. No legal travel arcs, road widths, speeds, elevation profiles, inferred access rules, lane geometry or vehicle classification are assigned.
- Most selected records are paths or secondary semantics, not car roads:283 footways,87 service ways,26 cycleways,40 pedestrian ways,20 steps and24 corridors occur in this target set, alongside primary/secondary/etc. The one proposed way is not a completed road by default.
- No terrain, facade/roof/interior quality, physics, ordinary-input gameplay, rendered appearance or runtime performance acceptance is implied.

## Verification

```sh
/private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geodata -p test_road_topology.py -v
```

**First-pass suite:16 tests passed**; the final R2 suite has **21 passing tests**, adding native isolated-reversal, missing-node, source-projection consistency, node-tag preservation, shifted coordinates, invalid/duplicate nodes and node-header conflict checks. First-pass cases cover: at-grade shared identity/index associations; grade-separated XY crossings; equal-coordinate distinct IDs; negative oneway/roundabout strings without inferred driving arcs; same source way with multiple semantic roles; closed/retraced lists; count mismatch; shared-coordinate mismatch; pairwise rounding extent; missing/duplicate ways; source-tag/time conflicts; source/LineString typing; native PBF reference extraction with no source-node objects; exact binding failures; deterministic output/no overwrite.

Actual run used only559 selected original ways from the verified PBF:

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python game/tools/geodata/extract_road_topology.py \
  --pbf <private-exact-input.osm.pbf> \
  --expected-pbf-sha256 5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd \
  --catalog <bound-mbs-bayfront-r3-features.json> \
  --patch-manifest <bound-mbs-bayfront-r3-manifest.json> \
  --snapshot-manifest game/data/geography/osm-2026-10-27/manifest.json \
  --output <new-regional-topology.json>
```

Immutable first-pass artifact: `/private/tmp/singapore-fidelity/geography-topology/mbs-bayfront-topology-r1.json`

SHA256: `5b5672fbcf77117ec8a47b868e7472fd286bb261345b3d92bf5ab83b19216ca2`

- 2,830,042 bytes;19.676 seconds including checksum verification/one WAY metadata scan, at background/nice10 priority.
- 559/559 ways found,2794 ordered associations,1992 unique source nodes,2235 original segments.
- 607 nodes shared between source ways,28 closed ways,3 ways with retraces beyond closure.
- Zero count/tag/coordinate/duplicate/missing/time issues; maximum shared-node coordinate difference0.0m.
- Available source tags include47 bridge ways,14 tunnel ways,144 `oneway=yes`,4 `access=private`, and1 proposed tertiary way; these are preserved observations, not automatic driving classification.
- Header generator `osmium/1.16.0`, replication sequence4952, source snapshot2026-10-27T21:23:59Z.

The R1 JSON audit was ready only for **source-identity topology** and explicitly kept `source_node_locations_independently_projected=false`. R2 below supersedes that projection limit. Both stages keep `routable_vehicle_classification=unassessed`. A future consumer must verify every bound checksum/schema and require the audit status before using source incidence, then implement/test separate grade/access/direction/vehicle policies.

The private `inspection-r1.json` and extraction log beside the artifact contain precise counts, tag values and code hashes. The compact project `verification-r1.json` contains a non-sensitive receipt. No source paths/credentials are copied into the emitted topology or CLI receipt. Source attribution remains separately © OpenStreetMap contributors / ODbL1.0.


## Final R2: independently checked original node coordinates/order

One additional owner-authorized metadata-only NODE pass verifies the exact pinned PBF, C++-filters to the known1992 original node IDs, and retains their actual WGS84 longitude/latitude, tags and available source revision/time. It reconstructs no full node cache and does not rescan ways. R1's exact checksum is required; the same catalog/canonical/PBF binding and current projection-frame agreement are checked first.

Add these flags to the same CLI/input command, using a new output path:

```sh
--verify-topology <immutable-mbs-bayfront-topology-r1.json> \
--expected-topology-sha256 5b5672fbcf77117ec8a47b868e7472fd286bb261345b3d92bf5ab83b19216ca2 \
--output <new-mbs-bayfront-topology-r2.json>
```

Current final artifact: `/private/tmp/singapore-fidelity/geography-topology/mbs-bayfront-topology-r2.json`

- Schema `singapore_original_way_topology_v2`.
- SHA256 `2ffe21d198a2da653eee2b0f4ed35bf9993baf31d4d3e893551c3a60facd0c87`;3,864,803 bytes.
- All1992 source nodes found and independently projected; all2794 ordered associations checked.
- Maximum error per axis **0.00004999677810246794m**, below the declared0.0001m canonical rounding allowance.
- Zero missing, invalid, duplicate, reordered, shifted-coordinate or header conflicts; readiness true and `source_node_locations_independently_projected=true`.
- Additional source verification completed in1.893seconds under background/nice10 priority.
- R1's byte checksum remains exactly `5b5672fbcf77117ec8a47b868e7472fd286bb261345b3d92bf5ab83b19216ca2`.

Original node tag facts include10 `highway=traffic_signals`,37 `highway=crossing`,6 `highway=elevator`,22 explicit `crossing` values,5 `crossing:signals=yes`, and source barrier/gate distinctions. These are tag facts rather than implemented signals/elevator/vehicle policies. No selected node supplies an `ele`, `ele:datum` or `kerb` tag; missing values stay unknown/unassessed. Synthetic tests verify such tags are preserved when supplied. No node `ele` string is converted into world elevation.

Each R2 node now contains `source_node.source_wgs84_lon_lat`, independently `projected_world_xz`, source tags/checksum/revision, status and maximum association error. `node_coordinate_validation` records every mismatch or missing/invalid/duplicate observation, projection-frame/implementation checksum and original source header. The original R1 limitations are retained separately as `predecessor_limitations`; current R2 limitations correctly state that the selected2D association check is closed.

A consumer must require schema v2, exact R2/catalog/PBF/canonical bindings, `ready_for_source_identity_topology=true` **and** `source_node_coordinate_order_validation_passed=true` before treating the selected node/position pairing as checked. This still does not authorize an inferred vehicle route graph or supply surveyed terrain/elevation, bridge/tunnel profiles, lane widths, access/direction policy, outside-region incident ways, architectural/interior detail or rendered/gameplay/performance acceptance.

`verification-r2.json` is the current receipt. Private `inspection-r2.json` and `node-verification-r2.log` beside the artifact preserve exact final source/test/helper hashes, original node tag counts and projection evidence. No engine/GPU or Git actions were performed by this builder.

## Independent integration audit

A fresh critic independently reran all 21 tests, rehashed all bound inputs, read the 559 selected ways and 1,992 original nodes from the exact raw PBF with separate filters, and projected every ordered association using a separate EPSG conversion. All 2,794 associations, 2,235 segments, incidence lists, closures, retraces and source tags matched. Maximum per-axis error was 0.0000499967781 m within the declared 0.0001 m rounding tolerance. No P1/P2 remained in this exact artifact.

The byte-identical reviewed R2 data are tracked as `game/data/geography/compiled/mbs-bayfront-r1/source-topology.json`. Its hash and the tag-overlay hash are pinned in the separately tracked `supplements.identity.json`, bound to the unmodified geometry manifest/catalog and canonical snapshot. This is artifact integrity and original-source incidence, not proof of survey accuracy, vehicle policy, real elevations, runtime migration or visual acceptance.
