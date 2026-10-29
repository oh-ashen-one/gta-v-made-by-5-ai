# Singapore fidelity: active continuation

The full owner goal remains active. Make routine decisions autonomously; do not ask more implementation questions. Work on `Astra-6-singapore-fidelity`, never merge main. Root alone owns Git and engine launches. Preserve other sessions.

## Current process and safety state

One **headless** core test is queued: exec **79779**, shared launcher **PID95471**, start **2026-10-29 12:21:06 EDT**. Its identity was positively verified at12:23:40. The launcher is waiting for capacity and reported three ML clients plus Blender; no Godot child or engine log existed at that observation. Do not duplicate it. Its durable output is `work/fidelity-runtime/runs/source-core-normal-r1`; QA output uses `/private/tmp/singapore-fidelity/source-core-normal-r1/session`.

The latest observed STREAMING and PAUSED flags were absent, but utilization was98% and the new shared launcher correctly held the job. Keep its normal cap/headroom/cooldown checks. Never remove flags or change ignore patterns to get a slot.

Rules revision67f806f269f6 is verified. The installed shared coordinator now includes broader GPU-client detection, utilization below85% for10seconds, and20seconds between cold launches. **Before any rendered run**, Root still needs a first-real-frame health marker and timeout that pauses launches machine-wide on a wedge, with no SIGKILL. Account for simulators, encoders and other Metal clients as well as recognized engines/trainers. Respect the single-renderer/no-training first clean recovery hour. CPU source work continues independently.

## Data ready for integration

CityR2 and the nine-tile MBS terrain neighborhood were recovered with every original payload hash matched, in durable ignored `recovery/private` directories.

RecoveredR5 has new metadata identity `4e80cfc7f2d7ea898dc9479a7e91fb7670757522e6b09e03919187574bcf0802`. Every906 graph chunk and20 physical tile matches the old archived payload byte for byte. Root explicitly adopted this new generation and durable path in SourceWorld at e2d2915. The historical diagnostic-count difference is documented; the old identity was never forged.

Endpoint metricv3 identity `efa0e6bb33e1835af3aa09af242dfd522d14408eee912cef13b522d75edd9619` has passed full source/profile/graph audits and independent code critique. It contains **zero physical tiles**. Do not combine its new heights with oldR5 meshes. The road worker is building a bounded typed physical producer, including pedestrian-only structures, and correcting source incline/step-count mismatches. Profile feasibility is not terrain cover, physical traversal or surveyed elevation proof.

## MBS source and native work

Existing bounded proofs remain distinct: low transport119 checks/99m continuous travel; normal stairs147 checks; exact road batching39 checks; source controller98 checks; packed source cores29 CPU and33 native cabin-fit checks.

New `source_core_geometry.gd` and `source_stair_gates.gd` (c10d6cf) provide source-axis bank slabs, explicit full-sized rotated stairs and the guarded pose adapter. They leave complete5.10m incoming stair headroom, and the receiving floor owns its landing. Their new continuous walking fixtures are committed at ecb2ebc but have **not passed natively yet**. Run normal and low variants separately;720seconds internal,780seconds outer.

The minimum room allocationR2 at ec49dbb preserves1850 IDs,775 suites and all159 guest floors, with27,350 CPU checks. Its113,390.76m2 area is **not final luxury acceptance** and it is not installed game data. The separate area-first luxury planner is moving toward published category areas and adequate furnishings. Latest v3 had24 lower-T2 corridor overlaps, caught by its independent audit; correction is in progress. Keep failed candidates and area deficits explicit.

All57 program-floor geometry plans,27 resort mappings, roof programs and the coupled FloorStack/Hotel/SourceWorld installation remain incomplete. The default game has not been replaced with a fully integrated source city.

## Native work after capacity and safeguards permit

1. Inspect the existing queued normal source-core test before any new launch. Run the low variant only after the normal result is understood.
2. Run `mbs_source_floor_plan_test.tscn` with the exact frozen allocation path. This proves parsing/plan invariants only, not furnished-room quality.
3. Run `source_stack_capacity_test.tscn` with a fresh `/private/tmp/singapore-fidelity/.../session` and960second outer bound. PriorR1 exited2 because Root supplied an unsupported persistent QA path; it performed zero assertions. Keep the ownership guard intact and store the supervisor output durably.
4. Run the updated `mbs_floor_stack_test` partial-floor dependency fixture.
5. Run actual SourceWorld walking, driving, exit, parked-car detour and helicopter checks against recoveredR5 and the city/road batches, then rendered critique and performance measurements.

## Art and source fidelity

The art ledger is research only; no new assets were downloaded or generated. The official Marina PDF visually labels an8-foot pool table with1500x2620; the earlier1800x900 OCR was wrong. Bed versus outer cabinet is not explicit. A9-foot table was our reconstruction assumption, not an owner requirement. Verified suite-specific references take precedence. Licensed table/balls/sofa candidates still need acquisition, dimensions, marks, import and native visual review.

## Exclusive worker scopes

- `mbs_conformance_builder`: separate luxury-area planner/helper/tests; do not overwrite its in-flight files.
- `road_semantic_recovery`: bounded typed physical producer and source-step/profile corrections; CPU only.
- `source_dataset_recovery`: completed independent reviews, currently idle.

Root owns coupled production integration, launcher safety and Git. Full source-world streaming/rebase, AI/traffic/missions, complete saves/doors, actual rendered acceptance and final private package remain. No completion or blocked status is justified while this work is progressing.
