# Destination-height stair and lift receiving interfaces — author candidate

Worker owns only`stair_gates.gd`,`cabins.gd`,`hotel.gd`, NEW`mbs_low_transport_test.gd/.tscn`and this notes directory. Root owns FloorStack/Partial/World/Runtime and ALL engines/Git. No worker engine/GPU/UI/Git/provider/purchase action occurred. Source is frozen only after the complete author receipt; native/visual results remain pending.

## Receiving contract and compatibility

Low service floors B2/B2M preserve their actual2.5m intervals, ordinary.20m slabs and2.30m minimum clear height. Receivers use2.10m openings and.10m headers; normal receiving floors retain2.35m openings/.20m headers. Door height belongs to the DESTINATION landing: B3→B2 low2.10, B2→B2M low2.10, B2M→B1 normal2.35. B1 outgoing geometry remains normal.

Hotel obtains Root's transformed`FloorStack.planned_floor_record(id)`before construction. It adds optional`receiving_door_height_m`and`receiving_clear_height_m`to each stop; exact existing six-key stop descriptors remain accepted and normalize to normal2.35/unspecified legacy ceiling. Unknown fields, malformed numeric values, unsupported heights or insufficient declared headroom reject before nodes. The current schema remains backward-compatible; normalized descriptors include the explicit additions. Legacy all-normal geometry retains the original gate setback/dimensions and sensor shape. Mixed-height shafts retain2.70m internal cabin and2.35m cabin-side leaves, but recess those leaves.24m inside the shaft instead of.10m, geometrically separating them from a valid low lobby header.

Mixed-height receiving grilles have a documented20mm mechanical top gap below EACH receiving opening: mesh and collider2.08m under2.10m, or2.33m under2.35m at normal stops on that mixed shaft. Normal six-key/all-normal shafts keep their original2.35m grilles. Full Player capsule/profile and doorway widths are unchanged. This is reconstructed game geometry, not a surveyed lift engineering model; horizontal slider pocket detailing is inherited and still needs rendered critique, not an engineering clearance claim.

Cabin binding and every readiness observation validate actual completed receiver ID/world, declared headroom and the real hall-door BoxShape height against the planned stop. When source support metadata exists, callback collision generation must match its actual floor/residency token; low receivers REQUIRE that actual source stamp. Legacy normal isolated fixtures without source stamps remain supported. Exact external cabin callback remains the same four keys `{ready,floor_id,collision_generation,travel_ready}`.

## Stair guard changes

`StairGates.bind_floor(module,id,upper_id,provider,receiving_record={})`adds an optional fifth planned-receiver argument; old normal calls remain valid. Low2.5m rise requires the explicit partial factory schema and matching inventory interval. Frame/leaf/header/collision geometry follows the destination record. Optional actual receiving geometry fields from Hotel's readiness callback are mandatory for low landings and checked against the planned receiver; both lower CURRENT COMPLETE GROUP ready and upper COMPLETE GROUP ready are required. Local lower collision generation alone never authorizes opening.

On a lower-group refusal, the gate defers a request for the exact LOWER owner as well as the usual upper destination. This prepares B2M's missing B2 dependency when a cold B1 request has only locally committed B2M; loading stays outside physics and no fake ready result is supplied. Default normal local fixtures whose lower is already ready retain their usual upper-only request.

All actor opening occupancy, closing holds, generation checks, floor pins and retirement handshakes remain. Occupancy sensor height follows the actual leaf; normal values are unchanged, while low queries no longer overlap the next floor's unrelated actor merely because of the old normal sensor height. Per-increment angular native Box probes now retain actual frame/ceiling/header bodies and exclude ONLY that leaf RID. A2mm mechanical edge contact inset permits authored hinge/frame flush contact; it does not change Player, doorway or floor margins. Adaptive<=.04radian samples and a bounded physics step cover the actual commanded rotation. Unexpected real static geometry holds opening/closing and retains support instead of clipping through it.

## Separate cabin-side and receiver obstruction observations

A tall merged doorway box cannot represent a2.35m cabin-side leaf and a2.10m receiving opening at different Z planes. Mixed shafts query them separately: a tall cabin-side clearance inside the shaft and a receiving-side volume below its actual mechanical grille top. Both include real actor/static collision. Fixed ShaftEnclosure/Header RID is NOT excluded. Only controlled moving cabin/grille bodies and exact bound hall leaves are filtered. The same controlled-moving-only exclusion policy also applies to cabin body sweeps, so an unexpected fixed same-enclosure ceiling is not silently ignored. Normal threshold sensor dimensions remain the previous dimensions, with explicit5mm native query margin below their20mm side-frame clearance.

No real floor/header/ceiling body is excluded to make a query pass. Native diagnostic segments identify collider and shape; a valid nominal low header lies outside the receiver's lower clearance region, while an actual intrusion remains a positive hit. Current new fixture deliberately adds temporary blocker shapes to the EXISTING fixed ShaftEnclosure and real floor structure, proving that whole-body exclusion does not hide them.

## Coupled factory direction correction owned by Root

During review the worker found`Partial._low_lifts`passed`-side`into`_low_door`, although that helper already computes`-side*PI/2`. That reversed the normal lift-leaf direction toward the waiting actor. Root was notified and made the single caller correction to pass`side`AFTER the then-running standalone partial scene terminated, preserving that run's loaded-source identity. Worker did not edit frozen Partial. The new transport fixture requires waiting-actor displacement<.02m across the COMPLETE landing opening, not merely the initial E press.

## Native Root fixture and required regressions

`mbs_low_transport_test.tscn`uses actual Frame/Domain/Context/Runtime, real Root FloorStack+Hotel+Partial factories and a full production Player. It starts with a real cold B1 request: B2M is locally committed with a generation but its complete group is unready. ONE initial Player spawn at that real gate uses native E; it must hold, request actual lower dependencies, then become ready. Player descends both guarded2.5m U stairs through native receiving entries, including lower dependencies that require real B3/B4 preparation. No later actor position/velocity/reparent write occurs.

At a real low stair door, an unexpected same-floor-body header must hold actual leaf rotation; removing only that owned temporary shape resumes it. Real low hall actions must not push the waiting actor. Player boards the actual cabin, uses the real E destination panel and a focused GUI button activated through native Enter events, rides B2→B2M, walks through the2.10m receiver, then rides B2M→normal B1. Temporary same-enclosure cabin-side and receiving-header intrusions must appear in the appropriate native query segments and hold an aligned safe landing; no altered callback declares them safe. The fixture also verifies actual receiver-shape mismatch refusal, grille mesh/collider dimensions, native platform carry, exact floor support, occupied-floor unload refusal and withdrawn real shaft lease holding stationary/closed once the actor is fully clear.

This first selected T3 fixture does not establish all towers/shafts, visual fidelity, performance or whole-MBS completion. Normal legacy native cabin/stair/hotel suites must also be rerun unchanged after this production change; passing descriptor normalization alone is not their runtime proof. The existing standalone partial room/gallery/U-stair scene remains separate from guarded transport acceptance.

Root commits all frozen source before ONLY the current helper, sequentially, for example:

```sh
bash loop/singapore-fidelity/run_engine.sh mbs-low-transport-r1 1200 /private/tmp/singapore-fidelity/mbs-low-transport-r1 -- --headless res://src/systems/fidelity_tests/mbs_low_transport_test.tscn -- --qa-session /private/tmp/singapore-fidelity/mbs-low-transport-r1/session --profile-source-runtime
```

Internal bound1100seconds. Evidence is stdout RESULT plus supervisor loaded-source metadata. Existing failed runs remain honest; no old4hour clock is reset. Shared-runtime counters/headless success are not rendered performance or owner playtest acceptance. Source hashes are in`AUTHOR_FREEZE_R1.json`; lexical scan is not a compiler. Worker will leave production/test bytes untouched after freeze until terminal/new authorization.
