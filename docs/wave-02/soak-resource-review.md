# Wave 2 rendered soak — independent resource and timing review

**Verdict: the 1800-second scripted workload completed cleanly. The resource series shows bounded node/resource counts and small continuing memory growth; it does not establish leak-free operation. This is a 1280×720 timing baseline, not isolated or 1080p performance acceptance.** A 763.326 ms process-frame interval remains unexplained by timestamped evidence.

Reviewed 2026-10-21 at approximately 14:28–14:33 UTC by an independent GPT-6 Astra review lane. No engine, renderer, Blender, gameplay edits, or process control were performed. Root retains integration, slot scheduling, publication, and final owner acceptance.

## Evidence and candidate identity

- Final game evidence: [capture_log.json](soak-1800-r2/capture_log.json), SHA256 `3749bfca0f2d3811cc71b4955579c792d3d31698f641a5d9ff5a8c71ede3396a`.
- Terminal supervisor evidence: [process metadata](soak-1800-r2-process.log.meta.json), SHA256 `6c1bdbac71750bf25baa34fe3023cf00653304637bbc2854e48a94690c94d237`; [PID-specific resource series](soak-1800-r2-process.log.resources.jsonl), SHA256 `78c8184f752c2f421621a9ab4baf7868f8a718b86a4116cb0ef49205f8061063`.
- Quantitative extraction, window statistics, matched gates, and source checks: [soak-resource-analysis.json](soak-resource-analysis.json).
- Launch checkpoint `03d9b8700bab986ed191a0bcd39ee8a13cde7ac0` plus the recorded [source patch](soak-1800-r2-process.log.source.patch) and startup source/GLB hashes. All recorded source and asset hashes still matched at 14:28:18 UTC. Planned later source changes are separate candidates and are not certified by this run.
- Tested `capture_director.gd` SHA256: `ada822ea62b711139d4956f97cc6efc411198054cfc56f103283d0aeef0d3d37`. Inspected wrapper SHA256: `9ff8b25905d93666dd782e51182a81749bba184c6e715e1449e5bff42390b7fb`; the wrapper does not record its own source hash at launch.

The project handoff/ownership ledger and shared-brain routes were read. Injected policy revision `ba35669bd13c` was reported refreshed before launch; this reviewer does not claim an independent GitHub network refresh. The review follows the task's explicit same-model arrangement and writes only its assigned report/analysis files.

## Terminal workload and coverage

Godot 4.7.1 official, actual rendered Metal run, PID **14160**, supervisor PID **14155**. Game elapsed **1800.007973 s**; supervisor elapsed **1806.76 s**. Native engine and wrapper exit codes are **0**, timeout is **false**, and the child was **reaped**. Final wrapper error scan contains **zero error lines**, including shutdown, and RSS collection contains no sampling errors.

Three completed input-driven missions took **226.981 s**, **224.323 s**, and **247.360 s**. Each record is uninterrupted and contains three combatant kills, a real driving leg, flight/landing, and delivery. The second and third runs followed actual mission restarts at approximately **226.98 s** and **451.32 s**. These are three missions with **two intervening restarts**. Node/resource trends support repeatability, but do not replace the missing full post-restart camera/occupancy/actor-type invariant inventory.

The explicitly assisted fixture phase ran approximately **698.69–699.11 s**, after all three completion records were sealed. Its four checks passed. It deliberately uses stage changes and relocation and is excluded from mission completion counts. This subsecond phase, and the short restart transitions, have no dedicated one-second phase sample; their event/gate records supply the boundaries.

Free roam followed until final recovery/observation began at **1620.02 s**. Final observation lasted **179.985 s**. Terminal state was healthy, alive, unpaused, on foot, and using the player's camera, with both car reboard and aircraft cycle flags true. The final 60 seconds contain **256.21 m** of foot movement and the last motion was **0.0017 s** earlier. Recorded mixed distances after the fixture were **4325.19 m foot**, **3100.04 m car**, and **2181.62 m aircraft**. There were **zero deaths** in the full run.

There are **1801 engine samples**, covering every integer second from 0 through 1800, and **361 RSS samples** of the same PID. Engine samples range **0.40–1800.00 s**. Two inter-sample gaps exceed 1.5 s: **91.00→92.70** and **542.01→543.61**; no integer-second bucket is missing. External sample intervals are at most **5.018 s**. This is sampled coverage, not continuous state observation. The artifact has **39 screenshots** and no JPEG sequence or continuous thirty-minute movie.

All 1801 snapshots report actual viewport **1280×720**, MSAA enum **2**, and **TAA enabled**. Shared capture scheduling does not establish exclusive CPU/GPU conditions. No first/warm application-launch, packaged-build, native human playtest, or valid save/load round-trip acceptance follows from this run.

## Recorded process-frame timing

| Recorded interval set | Count | Mean, ms | p50, ms | p95, ms | p99, ms | Maximum, ms |
|---|---:|---:|---:|---:|---:|---:|
| Excluding intervals flagged as touched by capture readback | 136,556 | 13.1228 | 12.716 | 19.129 | 25.436 | 763.326 |
| Including capture overhead | 136,605 | 13.1767 | 12.719 | 19.134 | 25.490 | 763.326 |

These are monotonic intervals between `CaptureDirector._process` calls. Means are arithmetic, percentiles use nearest rank, and the equivalent mean process cadences are approximately **76.20** and **75.89 per second**. They are not independent GPU timings or a guarantee of 60 FPS. The instrument clock begins after world/player/traffic/mission/HUD/aircraft construction, so initialization before director setup is excluded. The early measured interval still includes initial rendering and active mission work; it is not a separately calibrated warm-up run.

**The 763.326 ms maximum also appears in the readback-excluded set. It cannot be dismissed as screenshot overhead.** The final artifact retains aggregate frame summaries without raw per-frame timestamps, so the maximum's location, cause, cold/warm status, and repeatability cannot be established. The one-second sample delays above are timing observations, not proof that either is the maximum frame. Per-phase frame percentiles and the proposed absence of repeatable warmed >100 ms stalls remain unverified. The proposed 1080p contract in `END_GOAL.md` is not tested by a 720p shared-capture run.

## Resource definitions and phase trends

The wrapper samples `ps -p PID -o rss=,pcpu=` every five seconds. RSS KiB is converted to MiB by dividing by 1024. Its time axis begins before source hashing and engine startup. Engine byte counters are divided by 1048576. Engine phases and RSS are aligned using the game's second-resolution finish UTC and monotonic duration: approximate uncertainty is ±0.5 s plus up to one snapshot interval at phase boundaries. Descriptive ordinary least-squares slopes use every sample in each window; they are not leak estimates or statistical confidence claims.

The first process sample is only **0.625 MiB**, before loading. RSS reaches about **1196 MiB by 120 process seconds**. That initial ramp is separated from later phases, not treated as a leak baseline. The entire process peak among five-second samples is **1231.34 MiB**. The wrapper's separate `RUSAGE_CHILDREN` high-water value includes waited-for support children, so it is not substituted for the PID-specific trend.

| Sampled phase | RSS first → last, MiB | RSS slope, MiB/min | Godot static first → last, MiB | Static slope, MiB/min | Node range | Resource range |
|---|---:|---:|---:|---:|---:|---:|
| Mission 1 (startup included) | 900.77 → 1200.03 | +106.638 | 228.05 → 294.06 | +7.909 | 17,833–17,967 | 475–495 |
| Mission 2 | 1200.33 → 1213.55 | +4.467 | 294.08 → 297.76 | +1.331 | 17,833–17,993 | 475–495 |
| Mission 3 | 1213.62 → 1217.48 | +1.274 | 297.79 → 299.52 | +0.515 | 17,833–17,910 | 475–495 |
| Free roam | 1217.58 → 1229.25 | +0.740 | 299.67 → 306.69 | +0.483 | 17,833–17,867 | 475–475 |
| Final observation | 1229.27 → 1231.34 | +0.334 | 306.75 → 307.34 | +0.180 | 17,835–17,835 | 475–475 |

All **1801 orphan-node samples are zero**. This excludes sampled orphan accumulation, not brief intermediate orphans or non-node leaks. Whole-run node range is **17,833–17,993** and object range **32,320–32,707**. At matched delivery gates, the node and resource counts return to exactly **17,833 nodes / 475 resources** on all three runs. Objects are **32,347 → 32,360 → 32,371**, and static memory is **294.06 → 297.77 → 299.51 MiB**. Thus repeat completion does not leave an accumulating sampled node/resource population, while memory and object totals are not literally flat.

Longer windows make the late trend visible rather than relying on start/end comparisons:

| Capture time, s | RSS median, MiB | RSS min–max, MiB | Godot static median, MiB |
|---|---:|---:|---:|
| 120–300 | 1200.03 | 1196.52–1203.53 | 294.05 |
| 300–600 | 1213.56 | 1203.56–1216.20 | 297.77 |
| 600–900 | 1217.73 | 1217.22–1220.25 | 299.85 |
| 900–1200 | 1226.95 | 1226.47–1227.33 | 302.77 |
| 1200–1500 | 1227.70 | 1227.02–1228.42 | 305.79 |
| 1500–1800 | 1230.66 | 1228.47–1231.34 | 306.82 |

The 600–900 s window crosses mission 3, fixtures, and free roam; the 1500–1800 s window crosses free roam and final observation. During free roam alone, RSS increases **11.67 MiB** and static memory **7.02 MiB** over approximately 15.35 minutes. The final three-minute walking observation has exactly **17,835 nodes**, **475 resources**, object range **32,397–32,400**, and zero orphans, while static memory increases about **0.59 MiB** and sampled RSS about **2.08 MiB**. These are bounded populations with modest continuing byte growth, not proof of a zero-growth plateau.

Godot's render-video counter ranges **2198.41–2199.47 MiB** during free roam and is exactly **2199.47 MiB** throughout the sampled final observation. Render-buffer memory ranges **262.75–263.77 MiB** during free roam, then is **263.74 MiB** throughout final observation. Render-texture memory is exactly **153.61 MiB** throughout both phases. Draw calls remain workload-dependent: **245–8380** during free roam and **746–7814** during final observation.

The earlier texture counter has a downward step of approximately **512.06 MiB** in each mission, at approximately **130.01, 405.00, and 559.01 s**, while total render-video changes by about **261–264 MiB** at those points. Its terminal value is not the total render-video value minus buffers. Preserve these as distinct backend counters; do not add them into a physical-memory total or interpret the texture decline as independently proven VRAM reclamation. Initial renderer counters are zero before becoming populated. Enumerated monitor availability is not calibrated backend accuracy.

## What the resource result supports

This run supplies clean terminal execution, repeated mission cleanup evidence, useful sampled RSS/counter histories, no sampled orphan growth, and bounded node/resource populations during the measured workload. The full windows show no sustained node/resource accumulation beyond their bounded activity ranges. They also record gradual RSS/static-memory growth that is not eliminated by stable endpoints or clean exit.

The harness deliberately retains two per-frame interval arrays, all one-second snapshot dictionaries, gate records, and log lines. Its own allocations grow during the test. The available counters cannot separate retained instrumentation, gameplay allocations, allocator behavior, and other process memory. A causal leak verdict requires controlled follow-up with bounded/streamed instrumentation and repeated comparable windows or allocation attribution. Both `memory_leak_acceptance_valid` and `performance_acceptance_valid` therefore remain **false** in this review; the clean workload result is not promoted into either acceptance claim.

The next performance candidate should retain actual resolution/quality identity and timestamp long intervals, then measure the packaged 1080p workload separately. Its results must not replace or relabel this completed 720p candidate's evidence.
