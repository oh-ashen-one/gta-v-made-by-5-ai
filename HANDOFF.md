# Orchard Reach — Opus 5.5 enhancement loop (rolling handoff)

- Branch: `Opus-5.5-enhancements` (remote `origin/Opus-5.5-enhancements`). Never merge or push `main`; that needs the owner.
- Run: run 2 is **open-ended** (owner, 2026-10-22 ~17:27Z): waves of build -> blind critique -> integrate until a blind
  judge prefers ours to GTA V and is wowed, or the owner stops it. Owner direction since 2026-10-23 04:40Z: play IN central
  Singapore (Marina Bay core), keep everything already made (`GOAL.md`).
- Records: [`loop/RUN.md`](loop/RUN.md) (run log), [`loop/PIECES.md`](loop/PIECES.md) (pieces, verdicts, merges), progress
  page `progress/index.html` (rebuild with `python3 loop/make_progress.py`).
- Machine: Mac Studio, Godot 4.7.1 Forward+, Metal for renders. Render only through `loop/render.sh` (shared GPU lease).
- Last update: **wave-M integration**, 2026-10-23 ~11:45Z. Game code **`996e35c`**.

## What is merged now (wave M, 2026-10-23)

| Piece | Merged commit (merge) | Critic vs GTA V | Better than baseline (critic) | Notes |
| --- | --- | --- | --- | --- |
| downtown-map | `9cccdda` (`83d3af2`) | OURS LOSES M1, M2 | no (towers removed, empty land) | merged by the downtown pre-integrator; seams `85d359e` `926bed2` `c430037` `5c30e70` |
| downtown-landmarks | `266842a` (`bf99f7f`) | OURS LOSES M1, M2 | no | same |
| downtown-blocks | `eeaf5a4` (`a6085a6`) | OURS LOSES M1 | no (judged without map) | same |
| street-life | `c8ec055` (`d6b8a46`) | OURS LOSES M1, M2 | no (perf x2, ped hit, grove view, clone trousers) | seams `57c878a` `f862c02` `996e35c` |
| nearfield | R1 `d379434` (`d32e195`) + R2b `606b6df` (`2419e38`) | OURS LOSES R1 | **yes** (R1); R2b unreviewed | R2b judged by the integrator on rendered views |
| characters | R2 `f4a1430` (`c7f4d4d`) | OURS LOSES R1 | no (R1); R2 unreviewed | look mesh on the **player only**; civilians use the street-life crowd |

Still parked: `opus55/aerial` (`572317a`, rR1 OURS LOSES; not part of this wave's merge list).

### What the integrated game has
- **Downtown Marina Bay is playable.** Drive the loop over the Esplanade and Bayfront bridges; walk the promenade into
  Merlion Park, over the Jubilee footbridge to the Esplanade and over the Helix to the MBS Event Plaza; fly and land at NS
  Square, the Lawn, Esplanade Park or Gardens East. Full-scale MBS, ArtScience, Helix, Esplanade, Flyer, Supertrees,
  Fullerton/Merlion Park; CBD, Boat Quay, Cecil St, Shenton Way, MBFC and Marina Centre blocks. The heritage district is
  the adjoining Chinatown / Tanjong Pagar side.
- **Street life:** 112 lane cars on the district and downtown road graph with junction signals, queues and turns; 281
  people (men, women, elders, children; hair, skirts, phones, cups, umbrellas, bags; talking groups, couples, parent and
  child), crossings on the walk phase, avenue rain trees and kerb clutter. Every street view is far busier than Q.
- **Near field:** median noses with keep-left signs, granite kerbs, planted medians, props, aggregate asphalt with tyre
  polish/oil/kerb silt, worn encaustic tiles.
- **Player character:** baked look mesh (plaid shirt, jeans, face/brow/fold detail), jointed hands whose grip frames feed
  the combat aim layer (support hand closes on the pistol).

### Seam fixes in this integration
- Combat self-test target held on the aim line (street-life randomised flee headings broke 3 checks); suite watchdog
  40 -> 90 s; freed-instance check order in `ambient_traffic.gd`.
- Stills keep lane cars off the lens (photo capture only): photo_01 no longer opens on a bus roof, dt_bayfront_drive on
  door panels, the grove vista on a sedan roof. The avenue tree on the grove-vista sightline is skipped (Supertree crowns
  visible again in gameplay_07).
- Crowd trousers: the street-life "bottoms" tint went to the shoes (the trousers live in the skin atlas), so everyone wore
  the same grey camo cargo. Per-person trouser dye in the crowd skin shader; bare legs/tights under skirts.
- Perf: people beyond 45 m stop casting sun shadows; people drawn to 160 m (was 240), lane cars to 380 m (was 520), small
  car parts to 120 m; people 35-160 m animate every 3rd frame. Max route draw calls 16.6k -> 12.5k.
- `car_damage.gd`: instance uniforms only on meshes with no material-less surface (headless "material is null" made
  `--test` exit 2 intermittently).
- New QA mode `--render-budget` (rendered draw calls and frame time per street-life family; hide/freeze one at a time).

## Verified (game code `996e35c`)

### Headless
- `--import` clean; `--test` **234/234**, exit 0 (run several times; one earlier run on `f862c02` failed the timing-
  sensitive "ambient traffic flows and queues" check 37/112 moved vs 39 needed, then passed 45/112 on rerun).
- `--capture` route **13/13**, 0 deaths after every merge (174.6 / 158.6 / 187.5 s) and **156.1 s** on the final code.

### Rendered (1280x720 Metal through `loop/render.sh`; lease `contaminated=no-exclusive-lock`; other work had the GPU 43-81 % busy before each run)
- `--capture` route **13/13, 0 deaths, 163.8 s, 0 engine errors**. Drive leg: moving traffic within 80 m in 100 % of
  samples, min car health 94.
- Frame times excl. readback over 5,198 frames: mean **30.8** / p50 **30.4** / p95 **47.7** / p99 **60.1** ms; max draw
  calls 12,475. Load (`world_ui_ready`) **13.6 s**.
  - For comparison: downtown pre-integration (no street-life) p50 17.7 / p95 27.0 (GPU 60-72 % busy); Q 14.5 / 20.5.
    The street-life critic measured p50 14.5 -> 29.3 for its piece alone. **This is still a real regression.**
  - `--render-budget` attribution (rendered, street views): people ~3.5-5 ms (mostly their per-frame animation/physics),
    lane-car sim ~1.5-2 ms, avenue dressing + signals ~1-3 ms; the aerial view (11.6k draws, ~32 ms) is dominated by the
    downtown world, not street life.
- `--photos` 29 views, `--gameplay-photos` 7 views, `--character-review` 18 stills: all exit 0, 0 engine errors.
- Checked by eye (side-by-side with the pre-merge set): street views 01/02/05/08/11 and gameplay 01-07 are busier with
  no lens blockers; gameplay_06 promenade now has people; gameplay_07 shows the Supertrees; bay/aerial/downtown views
  unchanged apart from traffic and people; trousers vary.
- JPEGs (quality 70, 1280 wide) in `progress/img/integration/M/` with the same names as `integration/Q/`. The
  `downtown_*` stills there are from the downtown pre-integrator (5c30e70) and were not re-rendered.

## Honest status against GTA V
Every blind round in run 2 returned **OURS LOSES**; no judge was wowed. Latest named gaps:
1. **Life at the lens:** 6+ people in 2+ groups within 3-12 m doing readable things, a car moving in the next lane
   (street-life M2). Crowds still sit mostly at 10-30 m.
2. **Materials and light:** car paint without sharp reflections, median foliage reading as cut-outs, flat tower boxes,
   uniform warm haze; no long crisp tower shadows or aerial depth layers at helicopter range (landmarks, aerial).
3. **Downtown dressing:** varied tree species and layered landscape behind barriers (map M2); bare beige plots; a blank
   grey Flyer-terminal frontage; dark/near-black shaded glass; SkyPark deck.
4. **Hero character** at 1-3 m: skin breakup, eyelids, fold lines (characters R1); R2 not yet critiqued.

## Open issues
- **Performance:** route p50 ~30 ms / p95 ~48 ms on a shared, busy GPU (see above). Next levers: per-NPC physics tick
  (legacy peds keep per-tick `move_and_slide` to 70 m), dressing/signal batching, downtown block/landmark LODs.
- Load time 13.6 s rendered on a contended GPU (11.5 s pre-street-life, 10.0 s Q).
- Downtown streets have little traffic: lane cars adopt the downtown graph but Cecil St / Bayfront views show 0-1 cars.
- Street-life critic findings not re-verified: the pedestrian standing in a live lane hit by the route car (not seen in
  this integration's route frames), pale "ghost" fade-in of figures at 40-60 m.
- `CharacterLook.civilian_outfit` tests still pass but civilians no longer use that path (player-only look mesh).
- Downtown open items from the pre-integrator: scripted downtown driver overshoots tight right turns; Marina Centre
  blocks pale at distance; `--downtown-review` drive/walk legs verified headless on 5c30e70, not re-rendered since.
- Carried over: helicopter airframe shadow on the bay in banks, floating dark cubes above the hawker roof, faceted
  sedan paint, motion-blur doubling of near-edge props at 60-70 km/h, pistol HUD while driving.
- Never use the save slot: always pass `--qa-session <own dir>`.

## How to run

```sh
cd <checkout>                     # this directory
godot --headless --path game --import                                   # fresh worktree only
python3 game/tools/bounded_run.py --seconds 400 --log /private/tmp/opus55/<you>/test.log -- \
  godot --headless --path game -- --test --qa-session /private/tmp/opus55/<you>/t
python3 game/tools/bounded_run.py --seconds 500 --log /private/tmp/opus55/<you>/route.log -- \
  godot --headless --path game -- --capture --capture-dir=/private/tmp/opus55/<you>/cap --qa-session /private/tmp/opus55/<you>/r
bash loop/render.sh <label> 600 /private/tmp/opus55/<you>/route -- -- --capture --capture-dir=/private/tmp/opus55/<you>/route/out \
  --qa-render-size=1280x720 --qa-session /private/tmp/opus55/<you>/route/session
```

- Review modes: `--photos`, `--gameplay-photos`, `--character-review`, `--street-review` (+ `--people-review`),
  `--landmark-review`, `--downtown-review`, `--heli-review`, `--combat-review`, `--drive-showcase`, `--locomotion-review`.
- Probes: `--render-budget` (rendered only), `--perf-probe` (headless CPU), `--sightline-probe`, `--soak` with `--capture`.
- A/B switches: `--street-life=off`, `--landmarks-off`, `--blocks-off`.
- Frame times: `<capture-dir>/capture_log.json` (`frame_times` excludes readback) and `frame_stalls.jsonl`.
- Worktrees: merged piece worktrees are removed after the push (branches kept). Still present: `.worktrees/aerial` and
  `.worktrees/street-life` (older `opus55/street-life`, superseded by street-life-fix).

## Previous
- **Wave-M downtown pre-integration** (2026-10-23 ~10:40Z, game code `5c30e70`): downtown map, landmarks and blocks merged
  with seam fixes; 203/203; route 13/13 headless and rendered; owner asks (drive the loop, walk onto the Marina Bay side,
  land downtown and get out) PASS headless, heli also rendered. Package `/Users/midir/Builds/OrchardReach-5c30e70.zip`.
- **Wave Q integration** (2026-10-23 ~02:50Z, `359fa91`): driving Q2, combat, locomotion merged; 164/164; rendered p95 20.5 ms.
- **Wave P integration** (2026-10-22 ~20:50Z, `acffbe0`): locomotion, combat, driving, helicopter; rendered p95 19.9 ms.
- **Run 1 final integration C** (2026-10-22 ~11:45Z, `32e08ba`): water, skyline, lighting, materials, on-foot, helicopter,
  driving; rendered p95 18.5 ms.
- **Wave 5** (branch `feature/wave-05-opus`): final candidate `98b41b2`, rendered-verified fallback `d2a6cad`; private
  native macOS packages, provider assets not cleared for public redistribution. See `waves/05/RELEASE_REPORT.md`.
