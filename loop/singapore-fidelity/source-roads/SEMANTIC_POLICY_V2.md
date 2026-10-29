# Versioned source semantics correction — targeted stage only

Root authorized a new inference recipe after identifying a source-semantic
error in frozen R5. R5, country R2, rejected copied-DB attempts and geometry
proofs remain immutable. The geometry workaround is stopped. Those rejection
proofs describe the old inferred profile, not an impossibility in Singapore's
real roads.

## Primary source meaning

OpenStreetMap documents `tunnel=building_passage` as a covered passage through
a building, commonly at ground level; it does not imply a missing layer of
−1. A passage normally shares the building's layer. [Building passage](https://wiki.openstreetmap.org/wiki/Tag:tunnel%3Dbuilding_passage)

`layer` describes vertical ordering at crossings/overlaps, not a metric
storey height. Negative layer values do not by themselves establish an
underground location. [Layer](https://wiki.openstreetmap.org/wiki/Key:layer)

Ordinary tunnels remain a distinct subsurface structure; building passages
are an explicit exception to the usual negative-layer tunnel convention.
Bridge ordering likewise does not provide a measured deck elevation.
[Tunnel](https://wiki.openstreetmap.org/wiki/Key:tunnel), [bridge](https://wiki.openstreetmap.org/wiki/Key:bridge)

These sources were read on 2026-10-29. No OSM object is edited or uploaded.

## Measured immutable source impact

The exact R5 source snapshot contains 257,845 road/path ways. It has 1,355
`building_passage` records, of which 1,145 lack a layer tag. There are 812
with permitted car-direction bits, 804 eligible under the old physical policy
after level exclusions. Explicit passage layers: −1 on 151 ways, −2 on 40,
0 on 14, +1 on four and +2 on one. Four covered-bridge passage records were
incorrectly labeled conflicting structures. The raw data also includes 2,416
ordinary `tunnel=yes`, 61 `tunnel=covered`, two `corridor`, one `culvert` and
one `flooded` value. Raw tags, original node order and coordinates remain
unchanged. Exact input records are retained in `semantic-v2-records/`.

The five worsened old-profile bounds were not all building passages: vertices
792152–792155 are a covered building passage; 792265 belongs to an ordinary
`tunnel=yes` way and was affected indirectly. The latter must not lose its
subsurface role merely to make a profile pass.

## Pure policy contract and targeted proof

`road_semantics_v2.py` and 13 CPU tests establish:

- Covered passages default to order 0 with no fabricated depth cap. Explicit
  layer/level text remains exact. Negative order alone imposes no metre depth.
- Explicit underground/underwater location evidence and ordinary tunnel
  structures retain distinct subsurface semantics.
- A bridge passing through a building remains a covered bridge; an ordinary
  bridge+tunnel contradiction remains unresolved.
- Ground-compatible covered passages share the surface connection-grade key
  only at the same original source node and compatible layer/level. The future
  ingester must never merge distinct node IDs by XY.
- A fixed 6 m bridge clearance and 5 m ordinary-tunnel cover are explicit
  **game reconstruction assumptions**, independent of ordinal magnitude. They
  are not surveyed elevations or a conversion of layer numbers to storeys.
- Unknown tunnel values retain explicit uncertainty and do not automatically
  acquire a negative layer/depth claim. Raw elevation text/datum is preserved.
- A source-proven connected parking-ramp site can propose a relative 5 m game
  separation between overlapping differently ordered portals. The gap does
  not grow with the numeric layer difference. This is a proposed reconstructed
  clearance, not a measured replacement for R2's old 4.968 m game gap. The
  future global solver must actually enforce and verify that relative order.

The actual old parking-ramp source records, endpoint-node sharing and 57.464 m
source path are part of the targeted test. Invalid/unconnected/too-short
requests are refused. These pure tests do not prove a newly ingested graph,
global profile, physical road mesh, native car traversal or rendered city.

## Required next implementation and audits

Build a new versioned inference kernel/baseline from the unchanged full source
catalogs and DEM reference. Do not patch the old R5 database in place.
Generated grade vertices/keys may change; original OSM IDs, ordered segment
adjacency, direction/access bits, raw tags, source hashes and XY association
must be independently compared to original source facts. A generated-vertex
identity change is not permission to join different original nodes.

Relative source-proven grade ordering must stay separate from metric game
clearance assumptions. Preserve ordinary tunnels and the parking ramp's two
levels; do not flatten a source-proven multi-level site. Reject genuine
infeasibility rather than alter source facts, source bounds or grade guards
without an explicit versioned policy decision. Recompute matched graph Y and
physical meshes with fresh identities, then run complete source, topology,
profile, grade/winding/coverage and branch-aware seam audits. Root alone
reviews adoption and runs native checks. No new global candidate exists yet.
