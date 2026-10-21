# Next goal — wave 4: Gemini4 Argon through AGY

Written **2026-10-21T19:00Z** from the actual outgoing state of wave 3, not from wave-2 prose.
Read `HANDOFF.md`, `docs/wave-03/EVIDENCE.md` and `docs/wave-03/REASSESSMENT.md` first, then verify
the remote branch HEAD and the private asset carry-forward before changing anything.

## Inherit the whole candidate

- Engine: **Godot 4.7.1.stable.official.a13da4feb**, Forward+, GDScript, native macOS. **Do not migrate.**
- Branch: `feature/wave-03-deepseek`. Incoming Astra checkpoint `658741b`, implementation `be6a8aa`.
  **Outgoing implementation checkpoint `8ab210952ed330e0dcc7c16d28fda406e2924a04`.**
- Private package: `game/build/mac/OrchardReach-wave03.zip`, **394,286,498 bytes**,
  SHA256 `993ec1a3616048ca19e0b9b71ce936cf7f2f75333c9e842dc728ba3778498bea`,
  PCK `f125bc795f2651a5e58f1d4741f9839c145be36e3c288268c06bba3c40dce83f`.
  The exported executable is byte-identical to wave 2's — only the PCK changes per export.
- Verified: **85/85 source regression exit 0** and **85/85 in the actual exported app exit 0**
  (`docs/wave-03/package-regression.json`, `editor_binary=false`).
- Primary visual target: the three PNGs in `docs/concepts/`. Read them **with a vision-capable
  model**. Do not inherit a score you cannot reproduce.

## Priority 0a — Direct Owner Requirement: Immediate Opening-View & Waterfront Singapore Landmarks (`WORLD-03`)

Per owner direction (`f679bcb` and `d473fb2` on `origin/codex/minimax-wave-01`, incorporated into `END_GOAL.md`):
- **Opening-View & First-Minute Acceptance**: From the normal starting camera and the first minute of walking or driving, the setting must immediately and unmistakably read as Singapore without a title card, HUD label or place name doing the work. The opening views and nearby routes must combine recognizable Singapore landmark sightlines with shophouse five-foot ways, HDB blocks and void decks, an inhabited hawker centre, tropical street canopy and left-hand traffic.
- **Required Landmarks**:
  1. **Marina Bay Sands**: Three distinct splayed/tapered hotel towers supporting the long cantilevered boat-shaped rooftop SkyPark ("three things" + "boat on top").
  2. **Gardens by the Bay — Supertree Grove**: Cluster of tall branching planted structures with flared trumpet/inverted-umbrella canopy crowns ("electric tree forest") and elevated OCBC Skyway walkway, appropriately lit for late-afternoon/dusk.
- **Supporting Iconic Waterfront Landmarks**:
  3. **The Merlion** (statue spouting water into the bay on the waterfront promenade).
  4. **Lotus-shaped ArtScience Museum** (sculpted 10-finger white lotus building on the bayfront).
  5. **Singapore Flyer** (giant spoked observation wheel with viewing capsules on the eastern waterfront).
- **Evidence & Handoff**: Make landmark silhouettes recognizable in actual ground/waterfront, opening-route, and helicopter views (`aerial_district` matching `(250, 95, 250)` -> `(-40, 0, -60)` FOV 62), and explicitly record which landmarks are reachable versus skyline/waterfront scenery for final Wave 05 (Opus 5.5).

## Priority 0 — fix the packaged route regression wave 3 introduced

Wave 3 raised street density and **broke the scripted drive**. `docs/wave-03/packaged-route/`
exits 2 at 263.1 s with `failure_reason = "uninterrupted driving leg reached aviation compound"`.
Foot, combat (3 kills, 0 deaths) and package gates pass; the car is entered and then barely moves
(7 m from the first waypoint at 107 s, ~18 m in the next 35 s).

Most likely cause: the route picks `_nearest_usable_car_position()`, and with ~130 parked cars instead
of ~40 the nearest usable car is now a kerb-parked vehicle at `(-152, -80)` that the scripted driver
cannot get onto the carriageway. Investigate with real evidence before changing anything:

1. Log which car the route selects and its transform, then reproduce the drive in isolation.
2. Check whether the new kerb spots at `z ± (SIDEWALK - 2)` sit inside the driven lane, and whether
   the planted medians (visual-only, no collider) confuse the driver's lane keeping.
3. Prefer fixing the route's car selection and the driver's escape from a kerb bay over thinning the
   city back down — the owner explicitly liked the denser street.
4. Re-run the packaged route and require 13/13 gates before claiming it again.

## Priority 0b — get an independent visual score

Wave 3 produced **no independent visual verdict**. The subagent harness model has no image input; it
correctly refused to invent one. Do not repeat that waste.

1. Confirm whether your own runtime has vision. If it does, score
   `docs/wave-03/photos-final/photo_01..15` against `docs/concepts/*.png` on the same AAA bar of 8
   and record the subscores (identity / density / materials / lighting / composition).
2. If it does not, request a manager-run vision review of exactly those 15 files plus the 3 concepts,
   and in the meantime work from the objective, measurable items below. **Never write a score you
   did not observe.**

## Priority 1 — finish the urban grain that wave 3 started

Wave 3 replaced the empty 144 m paver platforms with planned plots. That fixed the gross defect;
it did not reach the reference density. From direct inspection of `photos-final`:

- **Activity is still sparse.** A street frame shows a handful of pedestrians and no kerbside crowd.
  The concepts show packed hawker seating, people at shopfronts, and moving traffic in frame. Raise
  visible density *near the camera* — focused pedestrian lanes, seated diners, pavement tables — and
  re-check that `peds.size() == PED_COUNT + DINER_COUNT` (the regression asserts this exactly).
- **Road surfaces are still large and uniform.** Add lane-edge double yellow lines, stop-line
  hatching at junctions, patched/aged asphalt variation, drain grates and manhole covers.
- **Tree canopy is present but not layered.** The references have a continuous canopy with dappled
  light. Add a second, taller tree class and understorey planting on the heritage verges.
- **Waterfront and interiors are the weakest precincts.** The promenade is a flat deck; the safe
  room, convenience store and workshop are simple boxes with furniture. These are shown in
  `photos-final/photo_05`, `photo_10..14` and were not touched in wave 3.
- **Verify no z-fighting or floating props.** Wave 3 added ~400 infill buildings; inspect at least
  one aerial and one low street angle per precinct.

## Priority 2 — close the performance question wave 3 opened

Wave 3 **measured** the responder cost (≈145 ms per officer) and **removed it from the combat timer**
by pooling: activation is now **19–32 µs** in both the source build and the packaged app. What wave 3
did **not** do is prove the packaged hitch is gone.

1. Run the packaged 1800 s workload with the same command shape as wave 2 and re-analyse
   `frame_stalls.jsonl`. The six ~735–762 ms combat stalls at mission-relative 87/92 s are the
   specific regression to test.
2. If stalls persist, profile what else runs at that instant — `_update_police` also does per-frame
   `_has_sight` raycasts and `Sfx.set_siren`. Do not assume the officer was the only cost.
3. Keep the aggregate gates too: p95 ≤ 25 ms, p99 ≤ 50 ms at 1080p, and record actual framebuffer
   size, quality settings and hardware.
4. **Do not increase crowd/response density until this is measured.** Priority 1 will tempt you.

## Priority 3 — the still-unfinished systems from wave 2

Untouched in wave 3, still open:

- **Car wheel articulation.** The inherited classifier named thin scraps as wheels and produced
  orbiting shards; wave 2 preserved imported transforms, so real wheel rotation/steering is still
  unfinished. Audit pivots from raw geometry the way the helicopter was rebuilt.
- **Pursuit and navigation.** Officers/pedestrians follow simplified routes and can be blocked by
  buildings. No dedicated active foot → car → air → foot pursuit sequence exists.
- **Traffic blocked-lane reroute** and deadlock recovery.
- **Audio listening quality.** No listening review exists; videos are silent.
- **FV-06** parked coupe penetrating road/kerb at 124.016–125.511 s in
  `docs/wave-02/package-route-final/review-frames/` — verify whether wave 3's kerb geometry changed it.

## Priority 4 — gates that need a clean run

- **Packaged UI save/relaunch: now PASSING.** Wave 3 ran it on the exported app: write **24/24** and
  fresh-process load **23/23**, distinct PIDs, identical save digest
  `94c6c3ce9a48ca32fe753858a1b9755c0b59c7cdb058bbca02012d3fe17a3da0`, captures at 1280×720. Keep it
  passing; note that `main.gd` gates the review on `--ui-review`, so the load phase needs **both**
  `--ui-review` and `--ui-review-load` or the app idles on the title and the supervisor times out.
- **Ordinary OS playtest (QA-001).** Still no human/native-input first-play evidence. The UI phases
  are fixture-assisted.
- **Rights.** Provider source/binary redistribution remains UNVERIFIED per asset
  (`docs/ASSET_RIGHTS.md`, `docs/asset-manifest.csv`). Private implementation only; no blanket MIT.

## Preserve these — they are working and were expensive

- `Game`/`Events` authoritative state, transition table, atomic validated save replacement.
- Frame-safe press buffering, native mouse-button events, SMG cadence, camera/muzzle obstruction.
- Vehicle steering convention (facing -Z, positive yaw turns left), bounded post-impact drivetrain,
  aircraft neutral hover/controlled descent/grounded exit/camera restoration.
- Safe room in the housing courtyard gap; raised hawker table roots and measured stool positions.
- `_reserved` / `_is_free()` occupancy gate in `world_builder.gd`. **Any new infill must go through
  it**, or it will intersect the heritage rows, HDB slabs, mission hall, hawker pavilion or aviation
  buildings exactly as the pre-wave-3 layout did.
- The pooled officer path in `traffic_manager.gd`. Officers are built at load, activated in place and
  recycled; they are **not** in `peds` while pooled (the regression asserts the exact count).
- `run/flush_stdout_on_print=true` in `project.godot` — without it packaged file logs buffer and the
  soak's live-log gate aborts.
- The close-cover fixture's animation freeze in `self_test.gd`. It exists because the fixture is
  frame-rate sensitive; removing it will re-break `muzzle obstruction prevents damage through close
  cover` on a heavier district. Do not weaken the assertion instead.

## Run, test, capture

Machine: verify you are on the Studio. Shared GPU state lives at
`/Users/midir/sm2-n1/_scratch/gpu` (`PAUSED`, `locks/capture.0.lock`, `holders/`, `runs.jsonl`).
Hard global cap **two** renderer-bearing engines.

**Every renderer launch must go through `game/tools/render_gate.py`**, which takes the capture lease
with `flock`, refuses to launch when `PAUSED` exists, refuses when two renderers are already live and
refuses while an engine is stuck exiting. Wave 3 rewrote it to actually hold the lease; its first
successful execution is still owed (see below).

**If a guarded command is rejected by the approval gate, report the exact command and the reason and
leave that check pending. Do not substitute a direct `godot` launch, a different wrapper or any other
route around the guard.** Wave 3 did that once and it was corrected by the manager; do not repeat it.

```sh
# import on a fresh clone
godot --headless --editor --path game --quit

# source regression (expect 85/85, exit 0) — inside the shared lease
python3 game/tools/render_gate.py -- \
  python3 game/tools/bounded_run.py --seconds 90 --log ABS/regression.log -- \
  godot --log-file ABS/engine.log --path game -- --test --qa-session \
  --test-report=ABS/regression.json --save-path=ABS/regression-save.json

# fixed-view stills (15 PNGs, 1920x1080 backing) — inside the shared lease
python3 game/tools/render_gate.py -- \
  python3 game/tools/bounded_run.py --seconds 150 --log ABS/photos.log -- \
  godot --log-file ABS/engine.log --path game -- --photos --qa-session \
  --qa-render-size=1920x1080 --capture-dir=ABSOLUTE_NEW_DIR

# export (headless, no lease needed), then run the actual binary through the lease
godot --headless --path game --export-release "macOS" build/mac/OrchardReach-wave04.zip
python3 game/tools/render_gate.py -- \
  python3 game/tools/bounded_run.py --seconds 120 --log ABS/package.log -- \
  "build/mac/<extracted>/Orchard Reach.app/Contents/MacOS/Orchard Reach" -- \
  --test --qa-session --test-report=ABS/pkg.json --save-path=ABS/pkg-save.json
```

Notes learned the hard way in wave 3:

- Extract the ZIP **inside the workspace**. `python3 -c "import zipfile; zipfile.ZipFile(p).extractall(d)"`
  works when `unzip`/`ditto` are unavailable.
- After extraction the app binary may lack the executable bit: `chmod +x` it before launching.
- The exported binary parses `--test` as Godot's own unit-test flag. **User arguments must follow a
  bare `--`.** Without it the app aborts with "compiled without support for unit tests".
- `--ui-review` requires `--qa-session` plus `--save-path=/tmp/orchard-reach-ui-review-*.json`
  (non-symlink under `/private/tmp`); `--ui-review-load` is the second process.
- A renderer launch is ~7 s to `world_ui_ready_ms`. Budget accordingly.

## Outgoing expectations

Leave: pushed branch, exact checkpoint, current private candidate, fresh stills, honest untested
gates, stopped owned processes, and this file rewritten for wave 5. Do not merge main or publish a
binary without explicit owner authority.
