# Independent floor-stack code review

Reviewed 2026-10-29 against frozen `floor_stack.gd` SHA256 `c1d484dd61be229d37476b7aee4c2359b87250cbd6fa7941d509e2b013a0e526`. Actual current inherited model; no alternate-model claim. Read-only inspection and CPU receipt reading only; this review is the only file owned in this folder. No engines/GPU/UI/Git or implementation edits were performed.

**Decision: no new concrete P1/P2 found in the frozen floor-stack implementation under its stated root integration contract. Native validation is still pending.** Do not promote the static audit, code review, previous public-entry30/core298/context571/actor56 or individual Guest/Program fixtures into a pass for this new streamed stack.

## Identities and evidence

| Input | SHA256 |
| --- | --- |
| `game/src/world/mbs_interior/floor_stack.gd` | `c1d484dd61be229d37476b7aee4c2359b87250cbd6fa7941d509e2b013a0e526` |
| `game/src/systems/fidelity_tests/mbs_floor_stack_test.gd` | `ca87e108e4204c769c107d3483f88bbd816997a7dc1ba7b4ae1470c60b56d0a1` |
| `game/data/mbs-interior/inventory.json` | `80791f76fd2a2b50e6cd9f87dcba13666594ff12bfe906edd56b53b059675819` |

`FROZEN_SOURCE.json` and `STATIC_SOURCE_GEOMETRY.json` correctly label their results as source/inventory arithmetic and explicitly deny engine/native completion. The audit contains189 hotel records,27 resort records requiring explicit root mappings, actual T1/T2/T3 source IDs/axes and immediate-neighbor sets. The source module matches the frozen hash. Root-owned native jobs were queued/waiting for shared renderer capacity during review; no native run was launched or presumed successful here.

## Source correctness assessed

- `configure` checks actual Frame/Context/Runtime relationships, common native World3D, explicit finite base/datum, bounded limits and a single floor-stack geometry authority per context before construction. Options and inventory are copied; factory records are not mutated globally.
- Hotel canonical anchors use actual source tower centroids plus explicit relative inventory elevations. Source coordinates/axes remain scalar-double arrays until `frame.to_local` produces the local transform. Global placement is assigned before factory build. The projected origin revision is checked before construction and across awaited native commit; stale retained floors remain non-ready rather than being moved or overwritten.
- Adjacency is sorted by actual inventory elevation, not a fixed3.45m assumption. The copied lower recipe's stair rise becomes the actual next-floor difference. Incompatible full-height mezzanine recipes are refused before construction with an explicit pending-root-recipe state. Terminal program records use receiving-only interfaces; no nonexistent next storey is advertised.
- `ensure_floor` preflights the requested floor and its actual immediate neighbors, serializes bounded lifecycle requests, loads actual factory nodes, waits for server-world/static/door-pose checks and native corridor-floor probes, registers stable static support IDs and commits Runtime generation stamps before local readiness. Final readiness requires the requested floor and both actual immediate neighbors. A local floor commit is not promoted into shaft/cabin travel readiness; callback `travel_ready` stays false here.
- Immutable architectural floor registrations survive unload. Reload checks the same recipe/placement/volume/datum/explicit geometry-manifest digest and static path IDs. This avoids using stripped readable `.gd` source as production PCK identity. Cold generation IDs change independently of architectural identity.
- Dry OBoxes follow wing/core/stair geometry in canonical doubles. Program-pool rectangles are subtracted from wing dry coverage; the whole atrium/site AABB is not declared dry. The U-stairwell volume follows its actual bounded footprint, extends to the receiving-height band, and is separate from broad collision residency. Outdoor hydrology and pool swimming are not implicitly solved.
- Occupancy, manual actor claims, pins and immediate neighbors are checked before any retirement. Invalid explicit unload callbacks fail closed. Transition doors must not remain live. Runtime region/stamps retire before node destruction, and events expose that ordering. Failed protected geometry is retained instead of being freed under an actor.
- Door persistence is pure versioned source-ID data, bounded and inventory-bound; exact guest-unit/bath/suite bedroom namespaces are retained. Landing transition state is not revived as a private room-door save. Root still owns owner-save bytes, poses and disk I/O.

## Required native gates before accepting this component

The prepared scene addresses relevant behavior but has not passed merely by existing. Require supervisor/engine0, no fatal errors, no timeout, reaped child and source hashes for the actual run. Preserve any failure rather than weakening gates or editing actor poses.

1. Real source-basis T2-L24/L25 native commitment and continuous production-Player room/door/U-stair ascent, complete receiving floor and descent, with actual neighboring elevations and no relocation/reparent/teleport during tracked travel.
2. Actual source-ID room-door interaction and cold reload/generation change, including source/package identity where export changes script representation. Source-only plan arithmetic is insufficient.
3. Spa atrium and roof-pool dry exclusion using the actual registered OBoxes and actual program furnishings. Roof-pool lower-storey ceiling penetration, 3D water and swimming remain separate root work.
4. Occupied/current-neighbor, explicit pin/actor claim, open transition, refusing/missing unload guard and bounded-LRU cases. Verify current native support stamps disappear before physical owned bodies are freed.
5. Source-origin changes must invalidate old local readiness until the root actually migrates/restamps every affected actor/floor/cache. This component must not become an implicit rebase coordinator.

## Explicit root obligations, not newly discovered implementation defects

The separate active stair-gate worker/root must hold unavailable **outer** stair routes. Immediate-neighbor readiness is not transitive readiness for every next floor. This review does not duplicate that worker or waive the composition gate.

The root must compose cabin and stair unload guards, choose a bounded capacity sufficient for actual occupied/parked-aircraft/current/destination neighborhoods, retain cabin destination leases and provide unavailable-capacity handling. A protected-capacity result correctly refuses eviction; it is not proof the complete hotel transport UX can finish with every configuration.

Full source public-envelope door cuts/hollow assembly, six low-rise mezzanine reconstructions, explicit resort mappings, actual source terrain/city, cabin motion, whole-building source save/recovery/rebase, rendered quality, performance and ordinary owner play remain pending. Reconstructed private geometry/elevations are not as-built survey evidence. Do not certify the full1850-unit or entire Singapore goal from this component.

Shared routing used cached published revision `a67557283f99`; no fresh cloud-policy verification or publication claim was made. Root owns source checkpoint/push and the queued native tests.
