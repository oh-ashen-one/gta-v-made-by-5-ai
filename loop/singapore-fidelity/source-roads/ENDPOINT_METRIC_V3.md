# Endpoint-aware road metric inference v3

This is a new reconstructed vertical-profile experiment. Original source IDs,
ordered nodes, XZ, names/tags, access/direction, navigation edges and numeric
grade limits remain unchanged. It is not a road-elevation survey, physical
terrain-cover certificate, native collision result or whole Singapore result.

## Why v2 was rejected

The first global v2 attempt preserved all source facts but incorrectly treated
the overlapping caps of a straight 6.2956m, 6.4m-wide connector as two stacked
decks. The corrected classifier requires a source path that actually leaves
the endpoint neighborhoods and returns. Its second global run preserves the
one genuine source-supported multi-level ramp, then rejects 5,328 metric
constraints before writing any solved Y. Both attempts and their complete
source-conservation proofs are retained in `semantic-v2-records/`.

Ten direct witnesses join a bridge to a tunnel/covered continuation through
the same original OSM node. The former constant offsets demand that one point
be simultaneously at least DEM+6m and at most DEM−5m. The source topology is
not changed to accommodate this contradictory game inference.

## Explicit metric model

`endpoint_profiles_v3.py` groups source-connected bridge/tunnel runs by
compatible structure and level. Artificial OSM way splits do not become new
portals. Existing same-original-node grade transitions are retained; layer
ordinals are never multiplied into metric elevation. Unconnected crossings
remain separate even when their projected coordinates coincide.

A true portal is an existing original-node transition to a different
structure/level. Its actual zero-height flat geometry component shares a
continuous solver-owned height. No opposed absolute structure caps are
applied to that component. Transition distance is computed through original
network adjacency and the unchanged height-only geometry constraints; those
constraints never become navigation connections.

The transition consumes one half of the available unchanged grade budget,
up to nominal 6m for a bridge or 5m for a tunnel. At a 12% car grade this means
100m/83.33m after the flat component to attain the nominal offset. Near the
portal, offsets are relative to its **solved continuous height**, because
separate coarse DEM samples can themselves differ too much to serve as hard
road-height anchors. Far interiors retain the declared DEM-based nominal
bounds as well as relative structure constraints. Unsupported short features
explicitly report subnominal transition offsets; components with no identified
portal explicitly report an unanchored nominal game estimate. Neither is
silently presented as achieved terrain clearance or measured road elevation.

The source-supported parking ramp's 5m reconstructed separation remains a
distinct hard relative order. The old 4,096 sparse ramp-relation guard remains.
Structured profile relations use a separate explicit 100,000-relation budget
and 64-round closure budget. A budget refusal is unresolved computation,
not proof that source geometry is impossible. Invalid/infeasible profiles
never overwrite current heights or emit a complete graph identity.

## Source and resource evidence

`semantic_endpoint_baseline.py` clones the **source-only** v2 database after
checking its exact hash and terminal failure. It re-runs full original-source
conservation, rejects any predecessor-mutated Y, and takes matching before/
after streaming signatures over original nodes/ways/occurrences/edges,
geometry constraints and protected ramp orders. Only declared metric bounds,
inference records and solved Y may change. Previous solver diagnostic rows
remain in the old immutable attempt and are named explicitly when removed
from the fresh clone.

The global run uses an APFS clone, an 8GiB logical-output budget, a 12GiB
minimum direct-free-space reserve, 2GiB RSS, 3,600 CPU seconds and 7,200 wall
seconds. It runs at background/nice10 priority with no engine or renderer.
The supervisor observes its own child, reaps it on an owned signal, and checks
disk limits again even when the worker finishes between samples.

Targeted v3 tests cover the ten actual source portal witnesses (including
pedestrian bridge-to-covered-arcade cases), arbitrary source way splits,
short-feature disclosure, the real multi-level parking ramp and refusal
without height mutation. These are bounded CPU tests. Consult the current
`ENDPOINT_METRIC_V3_RUN.json` and actual process/supervisor state for global
progress; a saved RUN state is not proof of a live process or completed result.

## Physical integration remains separate

The existing physical road producer selects car-permitted ribbons only and
audits actual emitted slope at ≤0.121; the native loader's ≤0.122 limit allows
small Float32 re-quantization. Foot-only graph slopes up to0.25 and steps up
to0.7 must not be silently emitted into that car contract. Full Singapore also
requires a separate type-aware producer/native contract for pedestrian-only
bridges, decks, paths and steps, especially crossings over water. Car-only
ribbons plus a foot graph do not make those routes physically walkable.
