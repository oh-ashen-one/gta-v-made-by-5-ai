# Packaged 1080p soak — independent resource and timing review

**Final PS2 verdict: the 1800-second packaged scripted workload PASSED its duration, mission, fixture, liveness, error, and clean-exit gates. Performance FAIL against the proposed target of no repeatable warmed stalls above 100 ms: six unflagged combat intervals of 735.564–762.244 ms recur across all three missions. Leak-free acceptance remains unproven.** The clean workload result does not override those qualifications.

Reviewed at approximately 15:16–15:21 UTC on 2026-10-21 by an independent GPT-6 Astra lane. No engine/process operations or source/asset changes were performed. Root owns final integration and signed-delivery validation.

## Exact candidate and evidence

This run used the original `game/build/mac/final-r3/Orchard Reach.app`, checkpoint **`be6a8aa98b47735eb5b043db0860a0946767d1cd`**, PID **27400**. The reviewed manifest was pinned while it still matched the launched executable, preventing later signed-copy metadata from silently changing this run's identity.

- Original tested archive SHA256: `e5288cf6ea786456e66e2403aef4bccd27aa0d4c38ad47894ae7a9f842e6cbb7`.
- Original tested executable SHA256: `233633697eb0f31f0d26344eba344fb53c5700b2c308c7e84d0877ddd82271e2`.
- Tested PCK SHA256: `80b8920a83d124d63e30539decfc05103c9dcaaf9c58af3bb342d381bcb82b7b`.
- Final [capture_log.json](package-soak-r2/capture_log.json) SHA256: `1403b6ed7db451012234ce1b92f6a8a23b2e6464059077fa56ee7a3220c3f719`.
- [Supervisor metadata](package-soak-r2-process.log.meta.json), [PID RSS series](package-soak-r2-process.log.resources.jsonl), and [timestamped >100 ms events](package-soak-r2/frame_stalls.jsonl) supply independent terminal and timing evidence. Exact hashes, statistics, surrounding snapshots, and the retained failed-attempt record are in [package-soak-resource-review.json](package-soak-resource-review.json).

All six bundle-file hashes and the original archive hash matched at final review. Startup source, GLB, and complete recorded runtime-art hashes also matched. The later ad-hoc-signed delivery copy has its own identity and launch validation; this review does not relabel the original executable's thirty-minute run as an exact signed-copy run. The pinned original manifest records the upstream-template signature limitation.

## Completed workload and coverage

Godot **4.7.1 official**, **Metal Forward+**, Apple **M3 Ultra**. All **1801** snapshots report actual **1920×1080**, MSAA enum **2**, and **TAA enabled**. The OS-window argument was 1280×720, while the explicit QA backing target produced the measured 1080p raster.

Game elapsed **1800.008636 s**; supervisor elapsed **1806.61 s**. Native and wrapper exits are **0**, timeout is **false**, and the task-owned child is **reaped**. The final wrapper records **zero error lines**, including shutdown, and zero RSS-sampling errors. The retry's live runtime-log gate was independently observed passing at 60 s and subsequent milestones; its final scan also passed.

Three uninterrupted missions lasted **231.085 / 221.802 / 253.231 s**, with three combatant kills each and two actual intervening restarts. All four separately labeled assisted fixtures passed after the third mission. The fixture phase is approximately **706.14–706.56 s**, followed by mixed free roam until final recovery/observation at **1620.02 s**. One fixture snapshot exists; it is not a steady resource window. Short restart phases are represented by event/gate records rather than dedicated one-second samples.

There were **zero deaths**. Final observation lasted **179.982 s** and ended healthy, unpaused, alive, on foot, with the player's camera, both car reboard and aircraft-cycle flags true, **296.12 m** foot movement in the final 60 seconds, and motion **0.106 s** before termination. Mixed distances after the fixtures were **4367.44 m foot / 3108.33 m car / 2181.62 m aircraft**.

The engine series covers every integer second **0–1800**, without a missing bucket or an inter-sample gap above 1.5 s. The **361** PID-specific RSS samples have maximum spacing **5.025 s**. These are samples, not continuous observation. There are **39 screenshots**, no JPEG sequence, and no continuous thirty-minute movie. Successful missions and counts do not substitute for a full post-restart actor/camera/occupancy inventory or human gameplay acceptance.

## Timing result and repeated stalls

| Interval set | Count | Mean, ms | p50, ms | p95, ms | p99, ms | Maximum, ms |
|---|---:|---:|---:|---:|---:|---:|
| Excluding intervals flagged as capture overlap | 138,072 | 12.9326 | 12.287 | 18.804 | 24.318 | 762.244 |
| Including capture overhead | 138,121 | 13.0321 | 12.290 | 18.808 | 24.569 | 762.244 |

These are monotonic process-frame intervals, with arithmetic means and nearest-rank percentiles; equivalent mean cadences are **77.32 / 76.73 per second**, not a guarantee of steady 60 FPS. Initial world construction before director setup is excluded. The early measured interval still includes first rendering and real mission activity, not a dedicated warm-up profile. Full raw frame traces are not retained, so per-phase frame percentiles cannot be reconstructed from these aggregates.

The stall JSONL exactly matches the capture's **52 events above 100 ms**, with **zero overflow**: **39 capture-flagged** and **13 unflagged**. Flags indicate overlap, not proven causation. The six dominant unflagged intervals are:

| Mission | Absolute start, s | Mission-relative start, s | Interval, ms |
|---|---:|---:|---:|
| 1 | 87.038786 | 87.039 | 747.034 |
| 1 | 92.139559 | 92.140 | 747.869 |
| 2 | 318.076722 | 86.981 | 744.664 |
| 2 | 323.196355 | 92.100 | 762.244 |
| 3 | 539.629678 | 86.721 | 745.187 |
| 3 | 544.749923 | 91.841 | 735.564 |

The events fall inside each mission's combat segment and repeat after prior full mission completions. They are not confined to first startup and carry no screenshot/JPEG-overlap flag. Aggregate mean/p95/p99 values do not erase this repeatable defect. **Performance acceptance fails the proposed no-repeatable-warmed-stall target.**

The other unflagged events are two initial intervals (**345.036 / 205.204 ms**), two mission-3 intervals (**109.520 ms at 506.785 s; 110.940 ms at 583.076 s**), two free-roam intervals (**110.852 ms at 1009.671 s; 117.132 ms at 1569.539 s**), and one final-observation interval (**116.816 ms at 1763.286 s**). Nine unflagged events begin after 120 s. No cause is assigned from the event flag alone.

### Narrow profiling lead, not causal proof

Surrounding one-second snapshots show **+25/+26/+25 nodes and +20 resources** across the second combat hitch in missions 1/2/3. The first mission-3 hitch also has **+26 nodes / +20 resources** in the immediate rounded sample, followed by rapid return to the prior resource count. Other first-hitch brackets show little retained node/resource change but roughly **256 MiB downward texture-counter steps**. At the second hitches, render counters can update on the following snapshot, so a simplistic same-sample GPU allocation claim would be unreliable.

This is consistent with transient responder/resource activity but does not prove the bottleneck. Current source [`TrafficManager._update_police`](../../game/src/systems/traffic_manager.gd) synchronously calls `NPC.new()` / `add_child()` under a **4.5 s** on-foot responder timer; [`NPC`](../../game/src/actors/npc.gd) then calls [`CharacterVisual.configure`](../../game/src/actors/character_visual.gd), which loads/instantiates a provider skeleton, animation setup, and weapon attachment. The measured hitch starts are approximately 5.1 s apart. Profile these construction and first-use paths, resource destruction, and main-thread versus Metal work under the same route before selecting a preload/pool fix. Sampling can miss short-lived objects; correlation is not attribution. The JSON extraction tolerates the snapshots' ±0.005 s rounding so it does not accidentally discard an event-end snapshot.

## Resource trends and limitations

Release `static_memory_bytes` and `static_memory_peak_bytes` are **zero throughout**, despite substantial PID RSS. They are **unavailable for this review**, not proof of zero memory or a flat heap. Other engine counters are populated; all **1801 orphan samples are zero**. That is sampled orphan evidence, not proof against transient or non-node leaks.

RSS comes from the wrapper's identified PID through `ps` every five seconds; KiB are divided by 1024. Engine bytes are divided by 1048576. The first process sample, **0.469 MiB**, precedes loading and is not a leak baseline. RSS rises to approximately **1150 MiB** in the early workload. Game/RSS phase alignment uses second-resolution game finish UTC and monotonic duration, with about ±0.5 s uncertainty plus snapshot boundary uncertainty. Slopes below are descriptive ordinary least-squares values, not causal leak estimates.

| Sampled phase | Game sample span, s | RSS first → last, MiB | RSS min–max, MiB | RSS slope, MiB/min | Node range | Resources |
|---|---:|---:|---:|---:|---:|---:|
| mission_1 | 0.35–230.00 | 868.19 → 1157.44 | 868.19–1157.44 | +98.263 | 17,697–17,833 | 474–494 |
| mission_2 | 231.14–452.01 | 1157.72 → 1186.64 | 1156.97–1186.67 | +10.920 | 17,697–17,859 | 474–494 |
| mission_3 | 453.00–705.02 | 1186.70 → 1201.25 | 1186.70–1201.27 | +4.027 | 17,697–17,775 | 474–494 |
| fixture_assisted | 706.14–706.14 | 1201.27 → 1201.27 | 1201.27–1201.27 | n/a | 17,698–17,698 | 474–474 |
| free_roam | 707.01–1620.01 | 1201.34 → 1203.17 | 1199.83–1203.17 | +0.058 | 17,697–17,730 | 474–474 |
| final_observation | 1621.00–1800.00 | 1203.31 → 1207.42 | 1203.31–1207.42 | +0.510 | 17,699–17,702 | 474–474 |

The three matched delivery gates each return to **17,697 nodes / 474 resources / zero orphans**, with object counts **32,147 → 32,157 → 32,169**. Free roam is bounded at **17,697–17,730 nodes / 474 resources**, and final observation settles at **17,699 nodes** after its first transient samples. Final-observation objects range **32,197–32,212** and end at **32,199**. These full windows do not show sustained accumulating node/resource populations.

| Game time window, s | RSS median, MiB | RSS min–max, MiB | RSS slope, MiB/min |
|---|---:|---:|---:|
| 120–300 | 1155.42 | 1150.53–1158.38 | +2.884 |
| 300–600 | 1186.66 | 1156.97–1187.45 | +2.531 |
| 600–900 | 1201.53 | 1187.44–1202.62 | +2.061 |
| 900–1200 | 1200.30 | 1199.83–1202.81 | -0.504 |
| 1200–1500 | 1201.35 | 1200.47–1202.31 | +0.397 |
| 1500–1800 | 1206.60 | 1202.36–1207.42 | +1.305 |

Free-roam RSS varies **1199.83–1203.17 MiB**, with descriptive slope **+0.058 MiB/min**; it is not monotonically increasing. Final observation rises from **1203.31 to 1207.42 MiB** with slope **+0.510 MiB/min**. The latter is also the whole-run sampled RSS peak. A flat earlier window or stable nodes cannot explain away the late byte growth.

Free-roam rendering counters are bounded at **2371.67–2372.73 MiB video**, **275.12–276.14 MiB buffers**, and **299.56 MiB textures**. Final observation is constant at **2372.73 / 276.11 / 299.56 MiB** respectively. Draw calls span **230–8438** in free roam and **356–7918** in final observation. Treat these as distinct Godot backend counters, not additive physical/unified-memory totals. The texture counter's large earlier decreases are not independently proven VRAM reclamation.

The harness retains both frame-interval arrays, one-second dictionaries, gates, and logs. RSS includes those allocations and cannot separate them from gameplay or allocator behavior; release static-memory support is absent. No runaway sampled population was observed, but **leak-free acceptance is unproven**, and `memory_leak_acceptance_valid=false` is retained. The earlier 720p/editor-binary run has different code/build/raster conditions and is not a controlled before/after optimization comparison.

## Concurrent work and delivery scope

Root reported copy/ad-hoc-sign/ZIP work on separate copies from approximately **15:01:45 to 15:03:45.114110 UTC**, plus ZIP extraction/strict signature verification at **15:11:50–15:11:51 UTC** (~0.95 s). No extra engine/renderer was added and the running original app/PCK was unchanged. The **110.852 ms** event at game **1009.671 s** falls around **15:02:35 UTC**, inside the first interval; overlap is not a causal finding. The six repeated combat hitches occurred earlier. These CPU/disk activities, capture work, and unasserted machine exclusivity prevent isolated performance acceptance independently of the repeated stalls.

The signed-copy PCK identity and launch/relaunch evidence belong to the separate delivery audit. This report establishes the exact original packaged workload above, not Finder/Gatekeeper/notarization acceptance or public-release authority.

## Preserved failed first packaged attempt

`package-soak` (PID **24941**, checkpoint **df911c6b146a772174bcb838d42cffe18fd6d19f**) failed its first live log-availability check at **30.002667 s**, with zero mission completions. Native/wrapper exit **2**, no timeout, reaped after **36.44 s**. Logs became populated after exit, consistent with buffering; the rebuild enabled live flush without weakening the gate. The failed attempt remains in [its capture](package-soak/capture_log.json), [metadata](package-soak-process.log.meta.json), [original manifest](private-build-r1.json), and this analysis JSON's `prior_attempts`.

Its actual raster was 1920×1080, eight RSS samples covered startup only, and all three >100 ms events ended before 1.17 s. It is neither a long-soak pass nor a steady-state resource baseline. The successful retry above is independently identified and does not erase that failure.
