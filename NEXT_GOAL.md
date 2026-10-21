# Next goal — wave 3: DeepSeek V4.1 Flash through Devin

This is the outgoing Astra handoff for wave3. Read HANDOFF.md, the final remote branch HEAD and the private transfer manifest before starting. The manager owns the timed session switch.

## Inherit the whole candidate

- Engine: **Godot 4.7.1.stable.official.a13da4feb**, Forward+, GDScript, native universal macOS. Do not migrate engines.
- Branch: `feature/wave-02-astra`. Incoming MiniMax source was `4df93fa631d9484fb29e556a97df61a259620248`. Outgoing implementation checkpoint is **`be6a8aa98b47735eb5b043db0860a0946767d1cd`**, pushed to the wave-2 branch. The private artifact is `game/build/mac/OrchardReach-wave02-private.zip`, SHA256 `377447ff855c91da8746c23a67cc4877c22b34e32eadf64c420a6c1b56c006e8` (393884658 bytes), a locally ad-hoc-signed copy with identical game PCK; final evidence-only commits follow on the same branch. Actual package launch, save/relaunch and 85 regression checks have passed. The original raw package completed1800.008636 seconds, 3 missions,0 deaths/errors with clean exit; performance FAIL remains because six735–762 ms combat stalls recur. The signed delivery copy separately passed its UI/save/relaunch and85-regression checks; see exact signed-route evidence for its final mission.
- Primary visual target: inspect the actual three PNGs in `docs/concepts/`. The fixed destination remains END_GOAL.md. The current verdict is **playable experimental build with unmet requirements**, far below GTA VI-level realistic fidelity.
- Read AGENTS/shared brain, END_GOAL.md, HANDOFF.md, docs/EVIDENCE.md, docs/REQUIREMENTS_LEDGER.md, and the independent final visual review. The predecessor goal is archived in `waves/02/INCOMING_GOAL.md`.
- Use the actual available model/tools honestly. Wave 2 used fresh-context Astra critics; no different-model or human acceptance was claimed. The next session must verify its own DeepSeek/Devin access.

## Priorities, reassessed from actual evidence

1. **Replace the large-scale prototype appearance with coherent urban design.** The rigged hero is now integrated, so the highest-value art work has moved outward. The street and aerial captures still contain huge empty tiled lots, repeated detached building rows, uniform tower silhouettes, crude service buildings, and sparse daily activity. Complete one dense, convincingly scaled heritage-to-hawker route, then extend its quality outward. Use varied real frontage, shaded five-foot ways, service alleys, planted courtyards, fine-grained street furniture and believable background blocks. Preserve driving and pedestrian clearances. Compare both moving gameplay and matched stills against all three concepts; a flattering camera is not an art fix.
2. **Review and repair the delivered assets in motion.** The provider player/civilian/officer have 24-bone skinning and 12 clips. Helicopter partition, axes and pivots were rebuilt from raw geometry. Cars still require genuine wheel identification and pivots: the inherited classifier named thin scraps as wheels and caused orbiting shards. Wave 2 contains the animation by preserving their imported transforms; this deliberately leaves real wheel rotation/steering unfinished. Audit car cabins, driver/seat/door transitions, weapon grip/aim, seated foot contact, character deformation and marks. The final signed-route samples show a parked red coupe intersecting the road/pavement at124.016–125.511 s and a lamp apparently placed on the marked carriageway at120.013 s. Preserve the retained `package-route-final/review-frames/` reproductions and fix/recapture them. No new generation of the existing 18 jobs is justified.
3. **Make the city behave as a connected place.** Basic left-hand lane graph, blocker slowdown, phased lights and bounded responders work, but pedestrians/officers follow simplified routes and can be blocked by buildings; traffic has no robust blocked-lane reroute. Add real navigation and queue/recovery behavior, then observe active pursuit across foot → car → aircraft → foot, including search, rediscovery and escape. Existing route evidence often loses wanted before leaving the car and cannot certify that requirement.
4. **Close playable-build and ordinary-player gates.** Run the exact private packaged app, verify first launch, title/Continue/settings/pause, save/quit/relaunch and complete ordinary controls. Wave 2's CUA request for Godot was denied; no native OS human input was fabricated. Engine-injected events and scripted fractional-action routes are useful but distinct. Listen to the spatial procedural audio: current videos are silent and no listening-quality review exists. Make readable, fun controls and a comprehensible first-play mission; the ~4-minute automation is not proof of the provisional 10–15-minute new-player experience.
5. **Profile and optimize with a fixed honest contract.** Preserve populations and visuals while measuring the required combined stress. The completed source workload is 720p/shared-slot evidence. A final packaged 1920×1080 workload is separately recorded; inspect its terminal result and independent review. Neither shared run establishes isolated performance acceptance. Record actual framebuffer dimensions, quality, hardware/OS, startup/warmup, concurrency and captures. Inspect all generic errors, final process exit and resource trends. Target provisional 1080p/60, p95≤25 ms and p99≤50 ms unless the owner accepts a documented calibration; do not silently lower the north star. Use LOD/instancing/culling/pooling with matching visual and population retests. The final packaged run already exposes repeated roughly 735–762 ms combat-associated stalls, twice per mission at approximately87/92 seconds after each route start, with no capture-overlap flag. `traffic_manager.gd::_update_police` synchronously constructs an officer every4.5 seconds; node/resource correlation and profiling are needed to establish the cause. Do not increase crowd/response density until this hotspot is understood. The current timestamps are in `package-soak-r2/frame_stalls.jsonl`; good aggregate percentiles do not erase these spikes.
6. **Complete clearance before public distribution.** The audit covers all18 sources and derivatives but provider source/binary redistribution remains UNVERIFIED. Visible badge/sneaker/emblem findings are per asset. Existing job prompts are not clearance. See docs/ASSET_RIGHTS.md and docs/asset-manifest.csv; private implementation can continue.

## Preserve these corrected systems

- `Game`/`Events` authoritative state and bus, transition table and atomic validated save replacement. Invalid loads must leave current state unchanged; held weapon and settings restore with the state.
- Frame-safe press buffering plus held-state fallback, correct native mouse-button events, automatic SMG cadence and camera/muzzle obstruction checks.
- Shared nearest eligible interaction target and line-of-sight checks. Disabled cars and hidden/taken items must not steal prompts.
- Occupied player position follows the controlled vehicle; passenger collision is disabled before reposition. Car/aircraft platform layers exclude the passenger, fixing the landing-exit pinning bug. Vehicles receive fire instead of the hidden occupant at a stale location.
- Continuous real driving/flight prerequisites; death/respawn cannot bypass the car leg. Real local on-foot delivery is required. Restart clears response actors and restores mission pickup/guards/checkpoints.
- Vehicle steering convention: facing -Z, positive yaw turns left. Car collision uses actual closing speed and a bounded post-impact drivetrain; normal kerbs have clearance. Aircraft neutral assisted hover, controlled descent, grounded exit and owner camera restoration remain tested behavior.
- Safe room is in the housing courtyard gap, outside the provider plinth; raised hawker table roots and measured stool positions must not be reverted from old coordinates.
- Small remaining source-observed UI defect: active-play F6 load-failure toast says it is starting a new game, but rejected loads correctly preserve current state. Correct the message without weakening atomic rejection. F10 is mission restart; F9 returns to title.
- Bounded supervisors and explicit error-log path. Numerical assertion totals are machine-derived; a generic ERROR makes the aggregate fail even if all assertions pass. The headless dummy-renderer material-null issue remains distinct from the clean Metal suite.

## Assets and reproducibility

`game/assets/providers/` and provider-derived editable sources are intentionally ignored. The manager must carry the processed folder and the private `art/source/characters/`, `art/source/helicopter/`, and `art/provider-sources/` inputs, with outgoing SHA256 verification. All original 18 raw provider models remain under the sibling manager staging `relay-manager/assets`; exact jobs are in its parent. Current manifest lists18 base+8 derivative GLBs. Original authored GLBs, textures, scripts and Blender sources are in Git.

The old fetch helper automatically retrieves only the eight Customuse sources. The ten Tripo studio URLs require the authorized browser export route. Do not describe a fresh clone as automatically restored. Prefer the manager's verified carry-forward instead of regenerating or re-downloading.

DCC scripts: `cleanup_provider_assets.py` (checkout-relative paths; OR_RAW_DIR/OR_OUT_DIR/OR_PREVIEW_DIR overrides; rendering opt-in), `rig_characters.py`, `refine_helicopter.py`, and the original build_* authoring scripts. Resolve actual filenames and read each header. CPU Blender4.5.11 was used successfully; the default5.2 sandbox launch crashed during Metal probing. Never auto-relaunch after two crashes.

Customuse balance53: no further paid jobs or purchases. Tripo75450: existing credits allowed only for genuinely new small/bulk/secondary needs through browser control. Major assets use Customuse MCP when authorized and available; Meshy/local inference excluded. Installing a skill does not grant spending/publication authority.

## Run, test, capture and export

First verify machine, task ownership, current shared rules and shared GPU coordinator. The live Studio coordinator used by wave2 is `/Users/midir/sm2-n1/_scratch/gpu`, not an obsolete cache. Preserve foreign reservations/PAUSED and the global mixed-engine cap2. The root used one owned renderer at a time through `gpu_slot.sh` and `game/tools/render_gate.py`. Resolve the GPU script through the current catalog rather than hard-code an old release path.

Use explicit writable log paths. Import first on a clean clone: `godot --headless --log-file /tmp/orchard-import.log --editor --path game --quit`. The default sandbox blocks global editor preferences; do not modify global configuration to hide that diagnostic.

After a slot is obtained, launch `godot --log-file /tmp/orchard-player.log --path game`. Enter starts; F6 continues; WASD/arrows move or drive, Shift sprints, Space jumps/raises helicopter, Shift lowers helicopter, mouse looks, left/right mouse fires/aims, R reloads, Q swaps weapon, E interacts/boards/exits, Escape pauses, F3 settings, F5 saves, F10 restarts the mission, F9 returns to title, F1 diagnostics. Verify current input mappings instead of assuming this list is immutable.

Bounded Metal regression (inside the shared render lease):

```sh
python3 game/tools/render_gate.py -- \
  python3 game/tools/bounded_run.py --seconds 75 --log /tmp/orchard-regression.log -- \
  godot --log-file /tmp/orchard-regression-engine.log --path game -- \
  --test --test-report=/tmp/orchard-regression.json --save-path=/tmp/orchard-regression-save.json
```

Single scripted route: add `--capture --capture-dir=ABSOLUTE_NEW_DIR --save-path=/tmp/unique-save.json`; supervisor limit735 s. Optional `--record-frames=ABSOLUTE_NEW_DIR/frames` writes timestamped JPEG samples with explicit byte/time caps. Encode with `game/tools/encode_capture.py`; inspect delivered timing and last-frame coverage. Photos use `--photos --qa-session --capture-dir=ABSOLUTE_NEW_DIR` and are fixture-assisted free-camera evidence only.

Full soak: `--capture --soak --capture-dir=ABSOLUTE_NEW_DIR --qa-engine-log=ABS_ENGINE_LOG --save-path=/tmp/unique-save.json`, with the same engine `--log-file ABS_ENGINE_LOG` and outer bound1880 s. The QA user argument is required because Godot consumes recognized engine log flags. Preserve `run/flush_stdout_on_print=true` in project.godot: the release default buffers file logs, which caused the first packaged workload to abort correctly at its live-log gate. The acceptance floor is always1800 monotonic seconds plus3actual no-death missions and later transport/final-liveness gates; shortening --soak-seconds can only produce a smoke failure. No continuous30-minute movie is implied. Review final capture_log.json AND supervisor meta/errors/RSS.

Export privately after source validation:

```sh
python3 game/tools/bounded_run.py --seconds 240 --log /tmp/orchard-export.log -- \
  godot --headless --log-file /tmp/orchard-export-engine.log --path game \
  --export-release macOS build/mac/OrchardReach-wave03.zip
```

The output path is relative to game/. Extract to a task-owned directory and run the actual `Orchard Reach.app/Contents/MacOS/Orchard Reach` through the shared slot and bounded wrapper. Export success is not launch proof. No signing/notarization/public distribution is claimed.

## Outgoing evidence and open gates

The final HANDOFF and docs/EVIDENCE record the candidate, soak/resource review, latest captures, package hash and exact residual regressions. The signed delivery copy passed85 regressions,24 + 23 save/relaunch checks and a13-gate zero-death route. Its silent 1080pmovie retains actual sample durations and terminal DONE. Private asset/source/app/movie carry-forward is in `relay-manager/wave-02-private-handoff-be6a8aa/`, listed and hashed in `docs/wave-02/private-transfer.json` (228 asset/source files,26 provider GLBs). `package-soak-r2` has a terminal functional PASS and independent performance FAIL; its exact raw-export identity and the later signed-copy verification are kept separate. Older source hashes/patches are retained per run. Keep all88 requirements and20 QA gates visible; passing a narrow assertion does not pass a whole requirement. The predecessor's33/34 mismatch and orphan processes were not inherited as success.

Finish your own timebox with pushed branch, exact checkpoint, current playable private candidate, evidence, truthful rights, stopped owned processes and a successor goal for the manager's next wave. Do not merge main or publicly release a binary without explicit owner authority.

Final QA-harness correction to carry forward: the requested0.5 s recording completion hold was observed as0.150306 s. DONE is in the final frame after delivery, but use an explicit monotonic deadline if a full half-second observation is required. Do not rewrite historical measured durations.
