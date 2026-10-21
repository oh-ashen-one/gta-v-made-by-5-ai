# Evidence index — Wave 2

Reconciled **2026-10-21T14:01:26+00:00** by GPT-6 Astra documentation reviewer against stored JSON, logs, metadata, source patches and critic reports. No engine, exporter or playtest was launched by this documentation pass. The same-model independent critics are identified below; they are not different-model or human reviewers.

**Current verdict: playable experimental build with unmet requirements.** The latest clean Metal fixture suite passes **85/85**; one older rendered scripted mission completes with **zero deaths**. Neither establishes the GTA VI visual target, an ordinary-player golden path, public rights clearance, current packaged launch, isolated performance or the required 30-minute workload. The [complete ledger](REQUIREMENTS_LEDGER.md) retains 88 requirements and 20 QA gates. [test-index.json](wave-02/test-index.json) maps every current assertion to narrow requirement support and exact candidate identity.

## Candidate identity and environment

| Evidence ID | Base checkpoint | Exact candidate identity and execution |
| --- | --- | --- |
| **R — clean Metal regression** | `cf211e6d23bb18c4e5ffe03830a8d9d64606780c` | [startup source/asset SHA256s, command and terminal state](wave-02/regressions-rendered-r2.log.meta.json), [source patch](wave-02/regressions-rendered-r2.log.source.patch), [log](wave-02/regressions-rendered-r2.log) |
| **P — one rendered mission** | `9937fc99a45c845b6c7a24d1a55b1f1fa3b3af04` | [startup hashes/command/terminal state](wave-02/route-render-r1.log.meta.json), [source patch](wave-02/route-render-r1.log.source.patch), [log](wave-02/route-render-r1.log), [qualification](wave-02/route-render-r1/qualification.json) |
| **S — first long-workload attempt** | `03d9b8700bab986ed191a0bcd39ee8a13cde7ac0` | [startup hashes/command/terminal state](wave-02/soak-1800-r1-process.log.meta.json), [source patch](wave-02/soak-1800-r1-process.log.source.patch), [engine log](wave-02/soak-1800-r1/engine.log), [process log](wave-02/soak-1800-r1-process.log) |
| **X — preliminary private export** | `cf211e6d23bb18c4e5ffe03830a8d9d64606780c` | [export metadata](wave-02/export-candidate1.log.meta.json), [export log](wave-02/export-candidate1.log) |

Each run's base HEAD **plus recorded per-file hashes and patch** identifies its working-tree source. Do not label dirty-tree evidence as the pristine base commit. Ignored asset hashes are recorded separately; a matching source commit alone cannot recover those private inputs. Later source/art edits do not inherit previous passes. The source branch is `feature/wave-02-astra`; root owns commits/push and the final outgoing checkpoint.

The recorded reference environment is **Apple M3 Ultra, 256 GB RAM, macOS 27.0.1**, Godot **4.7.1.stable.official.a13da4feb**, Forward+ with Metal for rendered runs. [Wave 1 readiness](../waves/01/READINESS.md) records the inherited hardware/engine decision; per-run logs identify actual engine/renderer. Power mode is not recorded. Seed is 20261021 for P/S. Window request, viewport backing size, capture overhead and build configuration must remain separate: R/P requested 1280×720; S requested 1920×1080 but telemetry observed **2880×1620** backing pixels. No certified 1080p benchmark follows from those command arguments.

## R — bounded rendered regression: PASS within fixture scope

[Report](wave-02/regressions-rendered-r2.json): **85 total, 85 passed, 0 failed**, in-engine suite 14.440 s; external process 20.98 s, native exit 0, wrapper exit 0, no timeout, child reaped. [Metadata](wave-02/regressions-rendered-r2.log.meta.json) records zero fatal errors, zero classified errors, zero error lines, and five RSS samples. [GPU lease](wave-02/regressions-rendered-r2-gpu.json) and [resource samples](wave-02/regressions-rendered-r2.log.resources.jsonl) accompany it. This short run is not a leak or performance test.

The 85 assertions include structural presence/population, lane/signal logic, actual engine mouse-button events, rapid press/release, muzzle obstruction, vehicle ownership and occupant follow, blocked exits, vehicle death recovery, hover/pause/landing, exact waterfront post-exit walking, mission prerequisites, restart guard count, atomic checkpoint replacement, malformed-state rejection, settings and held-weapon restoration. The [machine-readable case list](wave-02/test-index.json) preserves the exact names, observed details and requirement mappings. It also records **fixture repositioning=true, ordinary_player_run=false, whole_requirement_acceptance=false**.

Reproduction is the startup command in R metadata and the exact [self-test source](../game/src/systems/self_test.gd) identified by its SHA256. This is an engine fixture, not OS-level mouse/keyboard or full human gameplay. Broad requirement status must be read from the ledger.

**Failed/rejected neighbors retained:** [first Metal report](wave-02/regressions-rendered.json) is **84/85**, native/wrapper exit 1 in 20.06 s; quick-click was consumed while the test fixture left the title overlay active. R2 enters gameplay before exercising the same event assertion. The [rejected headless R9 report](wave-02/tests/regressions-r9-headless-rejected.json) has 85 numerical passes but its [console log](wave-02/tests/regressions-r9-headless-rejected.log) contains generic errors. Root reports strict overall exit 2; no standalone R9 process-metadata file is retained beside that report, so its exact bounded terminal record is less complete than R.

## P — rendered scripted mission: PASS for one older route

[Route report](wave-02/route-render-r1/capture_log.json) and [qualification](wave-02/route-render-r1/qualification.json) record **13/13 gates**, **3 combatant kills**, **0 deaths**, **639.150880 m driving**, **722.181376 m flight**, actual intact destination landing, exit, on-foot delivery and mission stage 8. Gameplay elapsed **217.919123 s**; external process **223.57 s**, native/wrapper exit 0, no timeout, reaped. This corrects the predecessor's death/respawn drive bypass for this identified run.

| Gate / observation | Monotonic route time | Video time, approximately |
| --- | ---: | ---: |
| Market reached on foot | 81.49 s | 73.23 s |
| Combatant damage/death gate | 88.57 s | 80.31 s |
| Package interaction | 89.68 s | 81.42 s |
| Car entered | 98.90 s | 90.64 s |
| Driving leg reaches aviation compound | 141.35 s | 133.09 s |
| Car exit restores walking | 142.70 s | 134.44 s |
| Helicopter boarded | 153.66 s | 145.40 s |
| Destination airspace | 183.41 s | 175.15 s |
| Intact landing | 203.25 s | 194.99 s |
| Landing exit restores walking | 203.58 s | 195.32 s |
| Delivery completes mission | 217.77 s | 209.51 s; final sampled video ends just before this gate timestamp |

Video time subtracts the first sample's 8.256928 s offset. Sampling gaps mean timestamps locate nearby images, not every exact simulation instant. The last video source sample is 217.719363 s; the final delivery screenshot/log at 217.92 s is separate evidence, so the movie alone must not be said to show every final event.

[Silent MP4](wave-02/route-render-r1/scripted-route-r1.mp4), [encoding metadata/hash](wave-02/route-render-r1/scripted-route-r1.json), [original timestamp list](wave-02/route-render-r1/frames/frames.jsonl), and [recording metadata](wave-02/route-render-r1/frames/recording.json). The file is 209.464 s, 1280×720, one H.264 video stream and no audio; SHA256 `a052edbaf035f428314e19b67f379609046799eecbc0db63de5525948cde6d21`. It uses 2,073 viewport samples, preserving capture intervals without action cuts; 105 requested sample times were missed. Original frame files are local evidence and can be large/ignored; availability must be verified when preparing a fresh handoff.

**Limits:** `Input.action_press/release`, fractional strengths and direct camera yaw/pitch drive the script. No teleports/state bypasses are reported for this single route, but it is not a native human run. Wanted is already 0 before the car exit, so active cross-mode pursuit is unproved. Its 3.63-minute scripted timing is not a 10–15 minute first-play result. Aircraft reboarding/return, all failure cases, audio and later changes remain separate gates. Godot computer-use access was denied in this wave; engine-event injection is a different capability.

Performance is **NOT TESTED for acceptance**: requested 1280×720; shared capture lease; initial overlap with a headless route until 12:45:03 UTC; viewport JPEG readback/encoding. Raw `rendered_performance_valid=true` only means rendered intervals exist and is superseded by `qualification.performance_acceptance_valid=false`. Capture-excluded p95/p99/max are 18.246/22.231/**755.583 ms**; inclusive values are 27.19/37.802/**8177.098 ms**. These are route baselines requiring load/capture/phase analysis, not proof of hitch-free 60 FPS or repeatable warmed stalls.

## S — first 1800-second workload: FAIL, cleanly bounded

The [terminal report](wave-02/soak-1800-r1/capture_log.json) is **success=false**, elapsed **30.001585 s**, **0 completed missions of 3**. The [supervisor](wave-02/soak-1800-r1-process.log.meta.json) records native/wrapper exit 2 after **36.54 s**, no timeout, child reaped, eight RSS samples and no runtime error lines. Failure: “Soak runtime error-log gate is unavailable or contains unhandled errors”; scan detail: “Explicit --log-file is required for soak error verification.” The command did supply that engine option; root identified argument consumption before user-argument inspection and is preparing a separately named retry. This is a harness acceptance-gate failure, not evidence of a gameplay crash.

The [exclusive-performance lease attempt](wave-02/soak-1800-r1-gpu.json) timed out before launch after 60.4 s. The [actual shared capture lease](wave-02/soak-1800-r1-gpu-capture.json) records `exclusive=false`, `contaminated=true`, `perf_valid=false`. [PID resource samples](wave-02/soak-1800-r1-process.log.resources.jsonl) exist, but 30 s is no 30-minute/leak verdict. Telemetry recorded TAA=true, MSAA enum 2 and 2880×1620 backing pixels; preserve those exact observations rather than silently call it 1080p.

The [independent source review and re-review](wave-02/critic-soak-harness.md) closed the fixed-duration and final-liveness predicate defects before launch. That review did not execute the workload. A future PASS requires its own actual ≥1800 s, exactly 3 completed mission records, all fixture/cycle/liveness gates, final log scan, native/wrapper exit 0, no timeout and a reaped process. Memory trend, isolated frame-rate and human/visual/audio coverage remain separate judgments. Per-gate/five-minute stills and one-second telemetry are not a continuous 30-minute movie.

## Independent criticism and visual evidence

| Reviewer/artifact | Observed result | Scope and remaining limit |
| --- | --- | --- |
| [Baseline critic](wave-02/critic-baseline.md), [r2 critic](wave-02/critic-r2.md) | REWORK | Fresh-context same-model screenshot comparison; historical candidates. |
| [R6 visual critic](wave-02/critic-r6.md) | **REWORK 3.8/10**, stated AAA bar 8; identity 5.0, density 2.5, materials 3.0 | Actually inspected local concepts and six r6 screenshots plus matching r2 views. External VI/SG images were not reopened; no animation/runtime/rights/performance acceptance. |
| [R8 fixed-view log](wave-02/r8/photo_log.json), [capture identity](wave-02/r8-render.log.meta.json) | Capture process exits 0, 13.04 s | Later fixture-assisted stills show further changes; there is no independent R8 score or moving traversal acceptance. |
| [Gameplay critic R1](wave-02/critic-gameplay-r1.md), [R2](wave-02/critic-gameplay-r2.md), [R3](wave-02/critic-gameplay-r3.md) | Targeted PASSes plus recorded defects | Same-model independent author, headless engine-event/fixture probes. R3 reproduces saved-SMG data with pistol appearance; R later passes held-model restoration. No human OS-input/feel acceptance. |
| [Soak critic/re-review](wave-02/critic-soak-harness.md) | Initial REWORK; source blockers closed after fixes | Source and non-engine wrapper review only; runtime terminal result still required. |
| [Provenance reviewer](wave-02/provenance-review.md) | Blanket clearance withdrawn; per-asset uncertainty retained | 36 existing two-view images inspected, not all final hidden surfaces/derivatives or applicable provider/account terms. |

Additional bounded views: [character review documentation](wave-02/characters/README.md), [character runtime captures](wave-02/character-render/), [character capture metadata](wave-02/character-render-r2.log.meta.json), [title/start/pause/settings images](wave-02/ui-review/), [UI capture metadata](wave-02/ui-render.log.meta.json). Still-image poses do not demonstrate animation quality over time. The [three local concepts](concepts/) are references, not gameplay captures.

## Export and reproducibility: incomplete delivery verification

Preliminary private file: `game/build/mac/OrchardReach-wave02-candidate1.zip`, approximately 376 MB, ignored build output. [X metadata](wave-02/export-candidate1.log.meta.json) records native exporter exit 0 but strict wrapper exit 2: Godot could not write global `editor_settings-4.7.tres` under sandbox. The preserved known macOS CA diagnostic was separately classified. The ZIP's existence does not erase those errors. **Packaged app launch is NOT TESTED**, and this archive predates latest fixes. It must not be advertised as the final tested candidate or a public release.

Read [README](../README.md), [transition/save policy](TRANSITION_TABLE.md), [asset rights/reproduction boundaries](ASSET_RIGHTS.md) and the current [handoff](../HANDOFF.md). A clean-clone rebuild has not been demonstrated. Original authoring scripts travel in source, but ignored provider GLBs/textures/derivatives need the verified private carry-forward bundle. Ten Tripo URLs are authenticated studio pages requiring authorized browser export/staging, not automatic downloads. No new generation is needed to preserve the existing 18 outputs.

## Rights and distribution gates

[Asset manifest](asset-manifest.csv), [rights report](ASSET_RIGHTS.md), [provenance review](wave-02/provenance-review.md), [Wave 1 deliveries](asset-deliveries/wave-01.json) and [packaging atlas metadata](wave-02/packaging-atlas.json) are the sources of truth. The prior blanket statements “redistribution permitted,” “no third-party content” and “only size prevents committing binaries” are withdrawn.

There are 8 successful Customuse and 10 successful Tripo outputs. Current provider/account/job terms and **public source versus packaged-binary redistribution** remain separately UNVERIFIED. Six cleaned outputs have unresolved emblem/mark details; SMG broad-side coverage is insufficient. Rigging, orientation and source hashes do not clear rights. Original geometry with generated packaging textures inherits that texture dependency. Final derivative/aircraft/meal inventory must follow the latest manifest, not a hardcoded count in this evidence summary. Fonts/runtime notices, exact final-package inventory and owner release authority also remain gates. A private archive can contain assets that are still blocked from public distribution.

## Historical evidence retained without inherited acceptance

- Wave 1 [handoff](../waves/01/HANDOFF.md) and captures in `game/captures/` remain historical. The reported 33/34 check count is inconsistent; old test processes outlived that builder. Its stage 8 route included death/respawn and bypassed driving. It is not a continuous no-death golden path. Its exported package was not launched.
- Headless regression reports [R1](wave-02/tests/regressions-r1.json) through [R8](wave-02/tests/regressions-r8.json) contain 49, 57, 61, 68, 73, 75, 83, 85 passing assertions respectively. Their logs contain generic errors: early reports have CA/material diagnostics; R5–R9 additionally contain freed-lambda errors. They are **not clean aggregate passes**. The precise per-file counts/logs are retained in [test-index.json](wave-02/test-index.json). Root fixed freed HUD-label captures with WeakRef; dummy-renderer material-null remains explicit, while R's actual Metal log is clean.
- [Route R1 failure](wave-02/tests/route-r1-failed/capture_log.json), [R3 failure](wave-02/tests/route-r3-failed/capture_log.json) and [R4 failure](wave-02/tests/route-r4-failed/capture_log.json) preserve road/collision, LOS and post-landing passenger-platform defects. Do not delete them to make a clean history. [Headless route R2](wave-02/tests/route-r2-headless-pass/capture_log.json) is an older numerical mission success, not rendered-performance or human evidence.
- [Thirty-second negative soak](wave-02/tests/soak-bound-negative/capture_log.json) returns failure with zero missions. It tests bounded negative completion under an older harness; it does not dynamically validate the later 1800-second/final-liveness predicate.

## Still required before acceptance

Actual current packaged-app first launch, second-reviewer reproduction and OS-input play; ordinary-player uncut golden path and restart/load; active cross-mode police/search/rediscovery; full both-pad reboard/return; all recovery/traffic/NPC persistence cases; accepted current visual/motion/audio review; complete asset/software/output rights and package inventory; dated calibrated quality/performance contract; isolated representative performance; terminal 1800-second/three-mission workload with memory/stability review. These are visible in the ledger and do not become passes when the wave clock expires.
