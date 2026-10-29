# Stair fire-door interlock — isolated R1, verification pending

This is a separate safety component. GuestFloor, ProgramFloor, Player, source context, FloorStack and Hotel were not edited by this worker. It reuses GuestFloor.SwingDoor's production interactable adapter and complete-transform AnimatableBody motion. Visible leaves, frames and colliders have matching dimensions. There is no human animation, model generation, purchase, new art, actor relocation, actor reparent, actor velocity write or substitute floor.

## Concrete root integration

Instantiate stair_gates.gd under the same live world as the floors. On a real FloorStack floor_committed, call:

    bind_floor(floor_node, exact_lower_id, exact_upper_id, readiness_callable)

The pure synchronous Callable accepts ONE exact inventory floor ID and returns:

    {"floor_id": exact_id, "ready": bool, "collision_generation": nonempty_string}

A bound lower floor must have a real current nonempty generation. Its own ready can still be false while neighbors load, but its generation must continue matching the bind. For the receiving upper floor, ready=true MUST mean FloorStack's actual native/context support AND all its required adjacent floors are ready. The component deliberately uses FloorStack as the authority rather than fabricating stamps or inferring transitive readiness from the current floor. Exact ID/type/generation is checked. New IDs, empty generations, invalid Callables, stale bound generations, invalid source transforms and changed opened-generation tokens prevent opening.

Connect floor_requested(floor_id) to the existing Hotel request queue / ensure_floor. Requests are deferred outside the physics callback; readiness queries must never themselves load or yield. Loading does NOT auto-open a stair door. The user presses native E again. Prompt text is only [E] Open stair door / [E] Close stair door.

Connect protection_changed(floor_id, protected) to task-owned FloorStack pins, or query protected_floor_ids(). The signal is synchronous so root can update pin data in the same frame; its handler must not synchronously retire/re-enter the component. Both the lower and receiving floor are retained while any gate is open, moving, or has a real actor in its threshold/leaf-sweep volume.

Before ANY floor collision/context generation is retired, root MUST call:

    prepare_floor_retirement(exact_id) -> bool

This closes all affected incoming and outgoing gates. A false result requires retaining actual supporting collision and retrying after the player clears and the native leaves close. It rejects open, moving, or occupied thresholds. Gate readiness is committed across both wings in a non-yielding snapshot pass. refresh_now() forces an immediate current-frame refresh; normal per-physics refreshes are cached for the same physics/process pair. Native E always forces a fresh query.

After root's own actor/aircraft/cabin/pin checks, region retirement and a true gate retirement preflight, notify:

    floor_retired(exact_lower_id)

The optional second argument accepts FloorStack's retired region ID, so its two-argument floor_retired signal can connect directly. A prior successful retirement preflight must match the bound generation, and the readiness provider must already show that generation retired. A stale event cannot remove newly rebound gates. Only this component's gate holder under that exact lower-floor module is removed. Upper-floor retirement alone closes incoming gates and never deletes another floor's assembly. The component does not own or delete floors, foreign colliders, root regions, actors, contexts or external nodes. Its lifetime must cover all its bound floor assemblies.

### Occupied revocation is a retained-support transaction

A door cannot safely materialize closed through an occupied capsule. If readiness or a receiving collision-generation token changes while the threshold/swing volume is occupied, the component pauses closing and keeps both supporting floors protected. It denies new opening, then closes with the existing native mechanical door motion after the actor clears. Root must honor the retirement guard BEFORE support removal. This component does not claim to rescue an actor after a caller illegally frees an occupied floor or ignores pins.

## Root-owned collision registration

After native server insertion, root can obtain ONLY the component's bodies:

    owned_collision_bodies(lower_id) -> Array[CollisionObject3D]
    geometry_descriptor(lower_id) -> Dictionary
    report() -> Dictionary

The descriptor includes geometry version, exact lower/upper IDs, bound generation, hinges, landing/door dimensions and local edge coordinates. Root hashes/version-registers/stamps the new bodies with the appropriate shared source context/region. The component performs NO source context registration or metadata stamp itself. A node/reference/descriptor is not native insertion or context proof.

## Actual landing placement

The factory's U stair is 3.2 m wide, with a 1.2 m upper landing. Its portal.upper is already 0.6 m PAST the edge and is too late for a safety door. The new wall/leaf plane is at local core_z + side * 0.45, y equal to the actual stair rise. The 1.30 m clear opening is centered on the upper flight x (-length/2 + 1.80 + 0.78). The remaining piers close the whole 3.2 m span; tall side returns overlap the existing guards so the player cannot walk around the leaf. All new closure geometry starts at the upper-floor elevation, above lower-flight headroom.

The gate opens toward the receiving approach; its leaf and handle reuse existing metal/materials. All geometry is attached in local metres to the actual floor module; translated/yaw-rotated upright unit source parents are supported. Tilted, scaled/sheared, changed landing topology, mismatched stair rise and unsupported domain are rejected before mutation. Maximum 32 simultaneous streamed-floor bindings is a geometry/member safety budget, not a claim that only 32 building floors exist. Retirement permits subsequent floors to bind.

Metric private stairs and fire-door positions are reconstruction of this game's documented factory geometry, not source-certified MBS as-built details.

## Native fixture, not global acceptance

Parent command after committing this frozen source:

    bash loop/singapore-fidelity/run_engine.sh mbs-stair-gate-r1 350 \
      /private/tmp/singapore-fidelity/mbs-stair-gate-r1 -- \
      --headless res://src/systems/fidelity_tests/mbs_stair_gate_test.tscn -- \
      --qa-session /private/tmp/singapore-fidelity/mbs-stair-gate-r1/session

The fixture uses the real production Player/capsule, native E exact target + LOS, a translated/rotated unit parent, and the actual full lower guest floor. There is ONE declared setup spawn before walking. It ascends both physical U flights without jumps, proves closed full-capsule landing sweeps across both wings, attempts real walking against the unready closed door, requests delayed actual receiving-floor AND its required upper-neighbor full factory construction, waits for native support rays, then presses E and crosses real receiving support. It tests occupied generation/readiness revocation, retained support / refusal of retirement, physical closure once clear, wrong ID/empty-generation fail-closed behavior, native E reopening, physical U-stair descent, and removal of only owned gates.

After the final safe preflight, the fixture retires its declared lower generation token while leaving the actual support/factory nodes intact, then verifies that only the gate holder disappears. The fixture's generation strings are explicitly local test tokens; its native ray-backed readiness is not a source-context stamp or a global FloorStack test. Current source has not been parsed/run/rendered by this worker. No all-floor-pair, original-MBS fitout, full-building or city acceptance is claimed. Root must commit, run, inspect raw evidence and independently critique before integration acceptance.


## Retained R1 failure and R2 repair

R1 at checkpoint90e91a1a9fc01689bebf26a9e5ae427cd85b42a9 parsed and ran without engine errors, but ended67checks/1failure. Actual native E selected the exact door and opened it correctly. The fourth action, from the receiving side, physically pushed the stationary Player0.371920m, violating the unchanged0.02m action-motion bound. The prior local actor position was(-25.62590,-11.73163), hinge(-26.27592,-12.91933); at measured angle-1.12rad the leaf tip was about0.085m from that prior actor centre, within its0.36m capsule radius. Closing had an occupancy guard; opening did not. Full raw evidence remains at/private/tmp/singapore-fidelity/mbs-stair-gate-r1.

R2 adds an actual actor-overlap query for the conservative receiving-side quarter-sweep envelope. Native E cannot start opening into an occupied sweep, and an actor entering during opening pauses further leaf motion. This does not replace native E, disable physical collision, relocate the actor, or loosen the action-motion bound. The fixture now explicitly revisits the problematic receiving-side standing point, presses real E, requires the door to remain closed/stationary and identify the Player's actual instance as its blocker, then physically walks back beyond the sweep before pressing E again. The original2cm bound, exact native target, LOS, full capsule, door width and physical return traversal remain. Current revision is source-only pending the parent's next committed run.
