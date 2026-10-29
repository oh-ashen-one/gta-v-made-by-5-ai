# Optional exact static collision batches — author candidate

Root's measured source-world inventory contained6625native bodies. Query-local complete-inventory reuse removes repeated reference-list visits, but fresh per-body validation still has real work. This optional representation reduces city collision bodies without changing the source mesh geometry. No across-frame readiness cache is introduced. Root must measure the actual-world effect after native proof; no FPS gain is claimed here.

## Configuration and compatibility

CityScene retains its original six arguments and default `per_feature` mode. Optional seventh `options` selects:

```gdscript
{"collision_mode":"static_batches"}
```

Optional bounded integer controls are `faces_per_body` (default32768,8..65536), `faces_per_frame` (default4096,128..16384), and `maximum_collision_faces_per_tile` (default1000000,128..2000000). Unknown keys/types/modes refuse configuration. Batch mode checks the tile's indexed triangle total before allocating scene geometry. Existing default callers, including TerrainScene, remain per-feature.

Visual ArrayMeshes, original feature/fragment metadata, surface arrays, normals/UVs/indices, material callbacks and tile anchor are unchanged. Default per-feature body metadata remains. Batch mode constructs only the new static batches, never first builds all old bodies and duplicates them during play.

## Exact geometry and bounded assembly

The collider uses the same Mesh triangle expansion as trimesh creation, preserving every surface/index triple and winding. Expanded face count must match the indexed source triangle count. Triples concatenate in order into bounded ConcavePolygonShape3D resources, each owned by a plain StaticBody3D. An original feature can span multiple batches without losing its IDs. Collision layer/mask remain0during construction and1/0after the normal guarded native commit; backface collision is not enabled.

Expansion yields after the configured face-work budget, in addition to the original feature budget. Each C++ concave commit is bounded by faces_per_body. Temporary expansion is per feature, and the accumulated pending batch is bounded; tile collision work has an explicit upper bound. The source provider's own byte/topology/cache bounds still apply. These limits do not claim an adversarial total-process RAM guarantee or instant native BVH creation.

Tile identity, source snapshot, current origin epoch, hidden-before-commit visuals, native-space/one-shape checks, retirement callback and retire-before-free behavior are retained. Source-hit ownership maps publish only after successful native insertion. Aborted imports publish no hit map. Retirement disables and removes its owned hit-map entries before queue-free; neighbors remain separate generations.

## Native source lookup

Godot's ray result identifies the collider's shape index and supplies a valid face index for a ConcavePolygonShape3D. The collision object API maps that shape index to its shape owner. [Godot ray query API](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html), [shape-owner API](https://docs.godotengine.org/en/stable/classes/class_collisionobject3d.html).

Concave geometry is represented as consecutive triangle triples. The batch descriptor retains ordered face ranges with original feature/fragment/catalog/source-hash identity. [Godot ConcavePolygonShape3D API](https://docs.godotengine.org/en/stable/classes/class_concavepolygonshape3d.html).

Call `city_scene.resolve_source_hit(hit)` immediately on the fresh native ray dictionary. It checks owned/live body, world/native space, tile epoch, optional native RID, native shape index and current CollisionShape owner/resource. It binary-searches the face ranges and returns the original `feature_id`, `fragment_id`, catalog owner, logical source SHA, geometry SHA, tile/origin, native shape/face indices and fragment-local face index. Invalid/foreign/retired/stale data fails closed. A missing face index resolves only when that entire shape has exactly one unique fragment; an ambiguous batch never guesses a source ID.

Batch bodies advertise a batch descriptor containing the actual member IDs. They are not mislabeled as one original building. RootWorld must use the resolver for semantic/source-hit lookup when opting in, rather than reading a single `source_feature_id` from an aggregate body. Runtime residency can enumerate the smaller body inventory, while any per-body support registry remains explicitly aggregate; it must not invent an original building identity. Geometry is owned immutable until retirement; this API does not authenticate forged same-process hit dictionaries or arbitrary in-place shape mutations.

## Root-owned native fixture

Scene: `res://src/systems/fidelity_tests/source_city_batch_test.tscn`, with a fresh private `--qa-session`;180internal/240outer diagnostic bound. The child ran no engine/GPU/Git operation.

The fixture first checks unchanged default per-feature bodies, then retires them before batch construction. It compares complete concave triangle triples and visual surface/material signatures between representations. Native rays verify source IDs via actual shape/face indices, roof/outer wall/courtyard wall/underside winding, open courtyard, second source in the same shape and source fragments across the canonical tile seam. A native production-dimension capsule must settle on the roof. Retirement guard, neighbor preservation, malformed/foreign/ambiguous face lookup, duplicate fragment discard, forced small-batch feature splitting, committed stale-origin lookup and origin-change-during-build discard are checked.

After all synthetic geometry is retired, it loads one real pinned country tile from the private generated artifact. Actual native body count must fall without losing feature/triangle counts; multiple original source-feature/hash rays must resolve. Overlapping/unhit seed probes are recorded, not silently assigned a fabricated owner. The synthetic input is a labeled80km math/geometry fixture; the real sample retains its actual original source IDs. Neither is normal World/player/mission streaming, whole-city completion, rendered fidelity or performance acceptance.

At author freeze Godot parsing, backend face-order mapping and native results remain pending. Root must run the existing default CityScene regression as well as this optional fixture before wiring SourceWorld opt-in.
