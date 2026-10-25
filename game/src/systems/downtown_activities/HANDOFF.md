# Bayfront Courier worker handoff

Updated 2026-10-25 19:44 UTC. Branch `Astra-6/downtown-activities`.

## Implemented

- Optional heritage waterfront → MBS Event Plaza parcel → heritage receipt loop, repeatable; outbound cancellation at dispatch.
- Existing E interaction contract with 4.5 m range, line of sight, actor identity, on-foot, alive, unpaused and non-busy guards.
- Independent card/destination badge; no Harbour Relay stage/objective/marker mutation.
- Versioned validated snapshot, New Game reset hook, completion count. Parent commit `35ba160` integrates Game atomic saves, legacy restore and bootstrap; cherry-picked here as `ddaa6fc` (do not cherry-pick that duplicate back).
- Save failure reports session-only progress explicitly.

## Latest functional evidence: r6, not yet a complete pass

Headless real Player movement and E from normal spawn. `18/19` checks passed; only unfinished destination traversal failed. No teleports, deaths not yet checked at end, zero jump inputs. Travel 1832.71 m, maximum per-physics-step displacement 0.2103 m, elapsed 344.40 s. The parent-owned heritage promenade ramp passed without jumping. Both Jubilee and Helix bridges were crossed, including the explicit Helix east landing exit.

Passing checks include actual pickup/cancel/restart, foreign actor/range/pause/busy/vehicle-mode rejection, occluding-wall rejection, JSON roundtrip, and invalid/fractional payload rejection. The live isolated save contains courier OUTBOUND while story remains stage 0/checkpoint 0.

Open physical blocker: north side of MBS Event Plaza promenade. Player stops at x=-317.346, y≈0.075, z=-632..-639; outside quay is ~0.10 high and promenade ~0.36, a ~0.26 m vertical lip. Destination ring is (-118,0.36,-632). Parent assigned the physical ramp to `landmark_access_builder`, owner of mbs.gd. Do not use a jump to claim this seam is fixed.

Evidence: `/private/tmp/astra6-activities/route-r6-integrated.log` and its `.meta.json`; earlier r4/r5 logs preserve the baseline curb and test-driver routing findings. The dedicated test default is jump-free. `--courier-baseline-curb-jump` is an explicitly labelled old-baseline diagnostic and was not used in r5/r6.

## Next

After receiving the MBS ramp commit, cherry-pick it without editing shared geometry and rerun the complete default route (outbound, MBS E handover, physical return, completion, repeat, zero-death/continuity checks). Command and API contract: INTEGRATION.md. Full route, destination interaction, return and rendered UI/asset quality remain unaccepted. No renderer has been launched by this worker; root owns the serial rendered lane and fresh critique.

Private asset/reference symlinks remain untracked and untouched by Git. Only the owned activity directory is staged by this worker.
