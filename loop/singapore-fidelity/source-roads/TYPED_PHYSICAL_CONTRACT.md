# Typed source surfaces — proposed native contract

Root owns `source_roads.gd` and SourceWorld. This producer changes no engine,
actor, permission, source node, source direction or existing car threshold.
The immutable input is endpoint-v3 identity
`efa0e6bb33e1835af3aa09af242dfd522d14408eee912cef13b522d75edd9619`.

Each feature adds `physical_contract.schema = source_surface_types_v1` and
one fixed `surface_class`. The native loader must derive its own limits from
the class and corroborating source policy/tags; a file-supplied numeric limit
must never authorize a wider threshold.

| Class | Required source evidence | Emitted/native maximum slope | Geometry |
|---|---|---|---|
| `car_ribbon` | Nonzero source car direction bits | 0.121 / existing 0.122 | Same visible and physical top mesh |
| `foot_ribbon` | Zero car bits, nonzero foot bits, not steps | 0.251 / 0.252 | Same visible and physical top mesh |
| `foot_steps` | Zero car bits, nonzero foot bits, `highway=steps` | 0.701 / 0.702 for walking collision | Continuous inclined walking collision plus separately declared visible treads/risers, as in current MBS stairs |

Mode bits preserve navigation/access evidence; they do not imply a different
physical reality or permission to remove collisions for a player vehicle.
All original way IDs, ordered source vertex IDs, canonical XZ, names, tags and
solved v3 Y accompany every physical fragment. Graph descriptors and Y must
come from this same immutable profile. No old R5 mesh is mixed with v3 graph Y.

Steps preserve an explicit source `step_count`. Missing counts may use an
explicit game reconstruction; existing counts are never rewritten to fit.
Reliable `incline=up/down` is checked against original node order. Conflicting
signs, zero rise, unsupported count syntax and implausible per-step rise are
recorded as unresolved metric/source cases, not completed stair geometry.
Game plausibility bounds are 0.08–0.24m rise and at least0.18m horizontal tread;
these are not building-code or surveyed-architecture claims. A next metric
recipe must reconcile those source constraints; the omissions are temporary
incomplete work, not a reduced final scope.

`area=yes` pedestrian polygons require actual area/hole/source-membership
validation. A boundary way must not silently become a filled polygon or a
walkable ring presented as the complete plaza. Indoor `level` records remain
the floor-registry integration's responsibility. Every nonemitted case stays
in an exact original-ID coverage ledger.

Batch bounds are `[-2000,-2500,2000,2000]` source XZ, an explicit20-cell work
batch rather than a city boundary. Parts use `<x>_<z>.pNNN`, with a separate
`spatial_tile_key`; Root must load every part of a requested cell before
declaring it resident. Each part stays below180,000 vertices (collision plus
separate visual geometry) and24MiB serialized JSON, within the native200,000
vertex/32MiB loader budgets. Original-way provenance survives collision batching.

The first output is capped at8GiB with12GiB direct free-space reserve and uses
APFS-cloned immutable graph files. Generation stays CPU background/nice10.
No country expansion is launched merely because this batch finishes.

Before adoption, require original-node/source-mode conservation; actual Float32
winding/grade checks by class; source-connected seam checks without snapping
unrelated crossings; graph-to-physical Y equality; native production Player
tests on a source footbridge and steps; and actual terrain intersection,
cut/fill, portal enclosure, deck underside/edge protection and visual review.
Profile equations alone prove none of those physical/quality gates.

Source interpretation checked against primary OSM documentation on2026-10-29:
[`step_count`](https://wiki.openstreetmap.org/wiki/Key:step_count) records the
individual steps in a stair or stair portion;
[`incline`](https://wiki.openstreetmap.org/wiki/Key:incline) uses the original
way direction for up/down and distinguishes percentages from degrees. This
first producer enforces reliable up/down; other syntax remains explicitly
unresolved until the metric recipe supports it. It interprets N steps as N
visible height changes, preserving the count without claiming surveyed tread
dimensions or verified character foot-contact animation.
