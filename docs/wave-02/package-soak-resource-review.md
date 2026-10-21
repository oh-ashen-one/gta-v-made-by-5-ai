# Packaged 1080p soak — independent resource and timing review

**Attempt 1 verdict: FAILED at 30.003 seconds because the required in-game runtime log was empty or unreadable at its first scan. This is not a completed 1800-second packaged soak.** Root was notified immediately at 14:37 UTC. A retry, if performed, must retain separate evidence and identity.

The terminal [capture](package-soak/capture_log.json), [supervisor metadata](package-soak-process.log.meta.json), [resource series](package-soak-process.log.resources.jsonl), and [stall events](package-soak/frame_stalls.jsonl) were independently read. Exact extracted values and evidence hashes are preserved in [package-soak-resource-review.json](package-soak-resource-review.json).

The executable is the actual private macOS bundle identified by [private-build-r1.json](private-build-r1.json), checkpoint `df911c6b146a772174bcb838d42cffe18fd6d19f`. All six bundle-file hashes matched that manifest at review time. The failed attempt used archive SHA256 `a54307ade3ecb08f41e55857d6f89aa29c6845a9273363f826f02ebdd0358012`, executable SHA256 `233633697eb0f31f0d26344eba344fb53c5700b2c308c7e84d0877ddd82271e2`, and PCK SHA256 `30ffa64d4c732e49ccdc04827cf9279978dbef11800adc26dacdf855a32f0f0d`. These identify this attempt even if a successor manifest changes.

PID **24941** exited with native/wrapper code **2**, no timeout, and was reaped after **36.44 s** process time. The game ran **30.002667 s**, completed **zero missions**, and produced one screenshot. The terminal wrapper contains zero error lines; that does not override the failed live error-log availability gate.

The engine and process logs both contain 1401 bytes after exit, including startup through the gate abort. This is consistent with output buffering until shutdown, but is not proof of a particular logger implementation. The gate must remain enforced; a successor must show a nonempty readable log while running. No game defect or clean long-workload result follows from this instrumentation failure.

Actual snapshots report **1920×1080**, MSAA enum **2**, TAA enabled, and Metal Forward+ on Apple M3 Ultra. The OS window argument remained 1280×720 while the explicit QA backing target set the actual measured raster. Runtime static-memory and static-peak counters are **zero throughout this release run** despite substantial RSS; treat those two counters as unavailable for memory assessment, not as a zero-allocation or flat-memory result. Node/object/resource/rendering counters are populated. Eight RSS samples span startup only, with sampled peak **869.84 MiB**; no steady-state or leak inference is justified.

The short readback-excluded timing summary is **12.0300 ms mean / 19.185 ms p95 / 19.617 ms p99**, maximum **362.729 ms**. Inclusive values are **12.0975 / 19.185 / 19.622 ms**, same maximum. These startup-only observations do not certify representative performance.

All three >100 ms intervals were captured without overflow: **362.729 ms at 0.000–0.363 s**, **202.601 ms at 0.363–0.565 s**, and **179.465 ms at 0.990–1.170 s**. The final interval carries a capture-overlap flag; the first two do not. Flags identify overlap, not proven causation. No later gameplay is covered by this failed attempt.

This independent GPT-6 Astra lane performed only evidence/source reads and wrote its assigned report/JSON. No engine, process, source, asset, account, or publication operations were performed. The completed 720p review remains separately valid for its own candidate and is not relabeled as packaged 1080p acceptance.
