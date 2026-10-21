# Singapore relay — wave 2, GPT-6 Astra through Codex

**Live final-validation handoff, 2026-10-21 14:47 UTC. The wave is still active.** The verdict is **playable experimental build with unmet requirements**, not north-star acceptance. Latest independent visual review is **REWORK, 3.7/10** against the three actual owner-approved concepts. All88 requirements and20 QA gates remain visible in docs/REQUIREMENTS_LEDGER.md.

## Ownership, clock and checkpoint

- Owned checkout: `/Users/midir/Documents/Codex/2026-10-21/https-github-com-oh-ashen-one/work/wave-02-astra`.
- Owned/pushed branch: `feature/wave-02-astra`; no main merge or public release.
- Incoming MiniMax checkpoint: `4df93fa631d9484fb29e556a97df61a259620248`.
- Exact outgoing **implementation checkpoint: `be6a8aa98b47735eb5b043db0860a0946767d1cd`**. Later evidence/handoff-only commits may follow on the same branch; inspect remote HEAD for the complete packet.
- Fixed window: **2026-10-21 11:38:01–15:38:01 UTC**. Final-candidate testing/checkpoint/handoff phase began by14:32UTC, before the required15:08:01 cutoff. Actual stop/cleanup evidence is still pending below; no future finish is claimed.
- Engine remains **Godot4.7.1.stable.official.a13da4feb**, Forward+, native universal macOS, on verified AppleM3Ultra Studio. Current session model and inherited settings only; critics are fresh-context same-model Astra, not a claimed different vendor/model or human acceptance.
- Shared rules pinned revision `ba35669bd13c6d1d514b3c1b77d1ed4dfbc7ca53` was injected as refreshed before launch. The live shared GPU coordinator is `/Users/midir/sm2-n1/_scratch/gpu`. Root uses one renderer at a time and preserves the mixed-engine cap2, foreign ownership and PAUSED state.

## Current private playable artifact

`game/build/mac/OrchardReach-wave02-final-r3.zip` is the current private universal macOS export, **394370169bytes**, SHA256 **e5288cf6ea786456e66e2403aef4bccd27aa0d4c38ad47894ae7a9f842e6cbb7**. It is intentionally ignored and not publicly uploaded. Extracted executable:

`game/build/mac/final-r3/Orchard Reach.app/Contents/MacOS/Orchard Reach`

The actual app has launched twice and passed24 writer/shell checks plus23 fresh-process Continue checks. Its exact archive/executable/PCK hashes and source checkpoint are in `docs/wave-02/private-build.json`. The actual packaged85-case Metal regression also passes, native/wrapperexit0,20.97s,reaped. Export finished with native/wrapperexit0 and classified sandbox CA/global-editor-preferences diagnostics; no global preferences/security controls were changed to hide them. The app is unsigned/unnotarized and private; public source/binary asset redistribution remains UNVERIFIED.

**Currently running:** package-soak-r2, actual app PID27400, bounded supervisor/session66313, from14:45:37UTC. It targets1800 real seconds with3genuine mission completions, then mixed free-roam cycles and final liveness. Source/assets are frozen. Evidence: `docs/wave-02/package-soak-r2/` and `package-soak-r2-process.log.*`. Actual1920×1080 is measured; release log flushing is now live. Terminal result/independent resource review are pending. A progress file is not a PASS.

## Implemented and preserved

Incoming art-first priorities were retained with a parallel mission-integrity lane because the predecessor's death/respawn bypass did not prove the car leg. Main changes:

- Replaced the block player/NPC representation with private skinned provider derivatives: player, civilian and officer,24bones/12clips, held pistol/SMG alignment and corrected shoe materials. Character blending/contact/complete rig quality remains unfinished.
- Corrected world-space PBR mapping, exposure and original sky; authored dimensional foliage, pitched hawker pavilion, four skyline modules, furnished safe room/shop/workshop, original packaging atlas, railings and meals. Rotated actual provider shophouse facades, populated the hawker hall, measured seats/floor heights, corrected safe-room placement outside the HDB plinth, and added physical boundaries/continuous far shore. Last pass adds instanced far-shore building depth and smaller pavers; large empty paved areas and repeated architecture remain.
- Rebuilt helicopter body/rotor partition, forward axis and pivots from the retained raw model; preserved source textures/geometry. Corrected camera framing, landing/exit handling and quieter mission markers. Misclassified car wheel fragments now retain their imported transforms to stop orbiting scraps; **proper wheel partition, spin and steering remain unmet**, not falsely repaired.
- Corrected player/vehicle ownership and passenger collision ordering, world-only vehicle platform layers, car closing-speed damage/kerb behavior, vehicle-body shooting, helicopter assisted hover/landing and blocked-exit invariants. Exact waterfront post-exit movement regression is fixed.
- Mission requires continuous real driving/flight, zero death bypass, grounded exit and local on-foot delivery. Restart resets pickup/guards/response/ownership. Three completed missions are independently recorded in the earlier720p soak.
- Repaired mouse-button mappings, frame-safe quick presses, automatic SMG, muzzle obstruction, nearest eligible/visible interaction targets, pause/title/settings transitions, atomic validated saves and held-weapon restoration. HUD scales to actual1080p and gameplay notices no longer overlap modal controls.
- Added basic signal phases/visible lamps, corrected graph endpoints, bounded responders, distributed walkers/reactive diners and spatial procedural audio. Navigation, traffic rerouting, pursuit causality and audible quality remain major open work.
- Bounded test/capture supervisors record source/runtime-art hashes, errors, RSS and actual exit/reaping. Capture reports distinguish fixtures, scripted actions/direct camera look, real travel and human acceptance. Timestamped>100ms stall events and a final recorded-DONE hold were added after critic findings.

## Verified evidence and limits

- **Source Metal suite:** `final-regressions.json`,85/85,21.13s,native/wrapper0,reaped, no generic errors. **Packaged suite:** `package-regressions.json`,85/85,20.97s,native/wrapper0,reaped, no generic errors.
- **Actual package UI/save/relaunch:** `package-ui-r2/ui-review-write.json`24/24 and `ui-review-load.json`23/23, different native process IDs, same executable and save digest. Restores deterministic fixture health/settings/SMG/ammo/position. First title capture15.669s from process ticks; fresh relaunch timing is recorded. This invokes real application handlers through an in-engine fixture, not human OS input.
- **Earlier complete720p soak:** `soak-1800-r2/capture_log.json`,1800.007973s,3uninterrupted missions,0deaths, all fixture checks, car exit/reboard and aircraft flight/landing/exit, healthy moving terminal foot state; native/wrapper0,reaped1806.76s. Independent `soak-resource-review.md` reports p95 19.129ms/p99 25.436ms/max763.326ms, bounded node/resource samples but continuing RSS/static-byte growth. No isolated1080p or leak acceptance follows. Raw screenshot-count39vs40 race is retained and documented; its deferred terminal screenshot race is fixed in current code.
- **Historical scripted route/video:** `route-render-r1/`, one no-death mission and silent timestamp-preserving MP4. Its last movie sample precedes the final delivery gate by a fraction of a second; final screenshot/log supply the last event. It is older source and not a human run. Current movie capture/review remains pending.
- **Comparable stills:** r1/r2/r3/r6/r8/r9/r10 retained. r10 renders1920×1080 and saves1280×720 comparison PNGs with camera records. Independent critic closes bad waterfront/airfield fixtures; visualbar remains3.7/10REWORK. Moving car-fragment closure is still pending current route pixels.
- **Real failures retained:** initial route/exit failures; headless generic-error runs despite numerical assertion passes; first source soak's unavailable log path; first packaged soak's release-buffered log (aborted30s, native/wrapper2). Current explicit QA log path and release flushing fix these distinct instrumentation issues without weakening the error gate.
- Godot computer-use access was denied. No workaround bypassed that denial. Native OS-input/human gameplay, subjective feel/fun, audio listening review, active cross-mode pursuit, full traffic/navigation/disruption, every broad QA procedure, public rights and north-star art acceptance remain open.

## Run and reproduce

Preserve the shared slot/ownership protocol before launch; never reuse another session's engine. Resolve `gpu_slot.sh` from the current shared-brain catalog and use `game/tools/render_gate.py` inside its capture lease. Do not use a stale cache coordinator. Keep one task-owned renderer at a time, stop drivers first, then SIGTERM/wait up to60s if native quit fails; no launch while any engine is stuck exiting.

For source on a fresh checkout, restore the private assets, then import with an explicit writable log:

`godot --headless --log-file /tmp/orchard-import.log --editor --path game --quit`

After obtaining the shared renderer slot, run `godot --log-file /tmp/orchard-player.log --path game`, or run the extracted app executable above without `--path game` to prove the package itself. Enter starts, F6 continues, WASD/arrows move/drive, Shift sprints or lowers helicopter, Space jumps/brakes/raises helicopter, mouse looks, left/right mouse fire/aim, R reloads, Q swaps, E interacts/boards/exits, Escape pauses, F3 settings, F5 saves, F9 restarts. See NEXT_GOAL.md for exact bounded regression/route/soak/export forms. QA-only saves use explicit `/tmp/` paths. `--qa-render-size=1920x1080` fixes the backing raster for evidence; recorded dimensions are authoritative.

The soak must receive both engine `--log-file ABS_ENGINE_LOG` and user `--qa-engine-log=ABS_ENGINE_LOG`, plus `--capture --soak`, a new evidence directory, unique task save and1880s outer bound. `run/flush_stdout_on_print=true` is required for release live-log verification. The fixed acceptance floor is1800monotonicseconds; a shorter smoke cannot pass. Static-memory monitors are zero/unavailable in release; use external PID RSS and other supported counters. Shared-slot timing remains a qualified baseline.

## Private asset carry-forward and rights

All18 raw provider jobs remain in the sibling `relay-manager/assets`, with exact job metadata in its parent. **Do not regenerate them.** Current processed folder has18base+8derivativeGLBs. Carry `game/assets/providers/` plus ignored provider-derived sources under `art/source/characters/`, `art/source/helicopter/`, `art/provider-sources/` and their checksums to wave3. The final transfer manifest/archive is still pending. Original authored assets/scripts/Blender sources are committed.

All18 raw hashes were reverified against delivery. The82-row/26-column manifest records72individual file hashes and separate source/binary redistribution fields. Per-asset marks, current terms/job labels, all-angle review and generated-atlas dependencies remain unresolved. The old sedan blanket clearance was withdrawn. Eight Customuse source links can be fetched by the helper; ten Tripo workspace links require authorized browser export or verified staging, not automatic downloads.

No new Customuse/Tripo jobs or credit purchases occurred. Customuse53 remains unavailable for new paid work; Tripo75450 existing credits are authorized only through browser control for new small/bulk/secondary needs. No Meshy or local inference. Blender4.5.11 CPU cleanup was used; default5.2 sandbox startup crashed once before authoring. One built-in image-generation request produced the original packaging atlas, with metadata retained.

## Successor and final stop gate

Successor: **DeepSeekV4.1Flash through Devin**, manager-started. NEXT_GOAL.md prioritizes coherent dense urban design, true car articulation/character polish, real navigation/traffic/pursuit, ordinary-player/audio acceptance, fixed-contract profiling and rights clearance. It preserves corrected state/ownership/save/input mechanisms and exact source/build instructions. The predecessor goal is archived in waves/02/INCOMING_GOAL.md.

**Pending at this live snapshot:** packaged-r2 soak terminal and independent trend review; current continuous sampled route/movie; private asset carry-forward manifest; final evidence/ledger reconciliation and branch push; task driver/engine/slot shutdown confirmation. Final cleanup/stop timestamp will replace this paragraph before the hard15:38:01UTC deadline. No success is inferred from the timebox.
