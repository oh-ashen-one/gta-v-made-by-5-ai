# Future work after the Astra-6 enhancement pass

This is a handoff for a future owner-authorized task, not permission to start another wave or extend the fixed four-hour window. The original relay ended after wave5. The prior outgoing document is archived at `loop/astra-6/INCOMING_NEXT_GOAL.md`.

Start from the reviewed `Astra-6-enhancements` candidate and [verification report](loop/astra-6/VERIFICATION.md). The owner's current density direction takes precedence over the old wave5 demand for minimum camera car counts: preserve the lighter traffic, usable bridges, continuous courier walk and public SkyPark access.

1. **Owner playtest:** gather actual feedback on movement/animations, driving, flight, handovers, audio and city identity. Native-input automation has been performed; it is not the owner's acceptance.
2. **Extended workload failure:** reproduce `loop/astra-6/evidence/soak-r2` at the same seed. Three missions finish with zero deaths, then the free-driving controller misses its destination at657.61s. Determine whether route planning/input recovery or world collision causes it. Preserve the destination gate and130s driving limit while investigating; do not hide the failure with teleportation or an arbitrary timeout increase.
3. **Native ragdolls:** investigate the solver/physical-bone support failures while keeping ordinary damage and fallback behavior. Record the first active-simulation penetration, body contacts/velocities, simulator state and visible skeleton separately. The visitor area now has14m separation from the pad, and the unchanged9m clearance criterion passed at12.008m in rendered R4. That single result is not a universal corpse constraint.
4. **Rendered verification/performance:** the packaged core suite timed out after97 passing checks at its90s watchdog under shared GPU load. Obtain appropriate shared-coordinator capacity for a clean rendered run and performance measurement. Do not kill foreign engines, raise the cap or turn headless timings into graphics acceptance.
5. **Visual/audio quality:** improve repeated flat office glazing and overly bright canopy materials, then compare actual runtime pixels. Keep the existing Singapore landmarks, connected gameplay and approved direction. No concept image substitutes for rendered evidence. A listening pass and human animation/handling judgement remain open.

No engine rewrite, new paid asset service, public release or main merge is authorized by this document. Preserve needed private art and exact evidence. Continue only on a new owner-authorized scope and branch.
