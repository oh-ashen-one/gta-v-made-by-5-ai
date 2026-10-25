# Bayfront Courier worker handoff

Updated 2026-10-25 20:01 UTC. Branch `Astra-6/downtown-activities`.

## Implemented

- Optional heritage waterfront → MBS Event Plaza parcel → heritage receipt loop, repeatable; outbound cancellation at dispatch.
- Existing E interaction contract with 4.5 m range, line of sight, actor identity, on-foot, alive, unpaused and non-busy guards.
- Independent card/destination badge; no Harbour Relay stage/objective/marker mutation.
- Versioned validated snapshot, New Game reset hook, completion count. Parent commit `35ba160` integrates Game atomic saves, legacy restore and bootstrap; cherry-picked here as `ddaa6fc` (do not cherry-pick that duplicate back).
- Save failure reports session-only progress explicitly.

## Latest functional evidence: r7, not yet a complete pass

Headless real Player movement and E from normal spawn. `24/25` checks passed; only the return traversal failed. Zero jump inputs, travel 3270.55 m, maximum per-physics-step displacement 0.2009 m, elapsed 550.80 s. Both repaired entrances and both bridges pass outbound. Actual MBS E delivery, duplicate rejection, unchanged story objective and receipt snapshot restore pass. The return crossed Helix and passed the Esplanade approach.

Open physical blocker: Jubilee's east landing into Fullerton peninsula on the return. Player stops at x=-530.338, y≈0.10, z≈-400. Ray-probed ground (same z): x=-534 → y=.2121; -532 → .1609; -530.5 → .1285; -529.5 and -528 → .36. The outward direction drops over this edge; the return cannot climb it. Parent owns the physical repair. Evidence: `/private/tmp/astra6-activities/route-r7-integrated.log` and `/private/tmp/astra6-activities/jubilee-local-r1.log` (plus bounded metadata).

The MBS ramp from `297043d` is present here as `5ae259f` (parent duplicate; do not cherry-pick back). Local MBS ingress/egress passed 5/5 checks, 446.82 m, max step .1424 m, 78.98 s, zero jumps/deaths, exit 0 and zero fatal errors. Evidence: `/private/tmp/astra6-activities/mbs-local-r1.log`. Full r7 confirms that entrance in the continuous journey too.

`jubilee_return.tscn` is an explicit local fixture spawn on the bridge's east approach. After repair it checks the remaining return through Merlion Park to Heritage Waterfront. It does not establish full courier completion. Full `courier_route.tscn` still starts at the normal heritage spawn. No jump flag was used in r5/r6/r7.

## Next

After the parent repairs Jubilee, run the localized return fixture first and then the complete default route. Completion, repeat and final zero-death/continuity checks remain open. Command and API contract: INTEGRATION.md. Full-route completion, final return/repeat and rendered UI/asset quality remain unaccepted; destination interaction passed in r7. No renderer has been launched by this worker; root owns the serial rendered lane and fresh critique.

Private asset/reference symlinks remain untracked and untouched by Git. Only the owned activity directory is staged by this worker.
