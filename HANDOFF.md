# Orchard Reach — Opus 5.5 enhancement loop (rolling handoff)

- Branch: `Opus-5.5-enhancements` (remote `origin/Opus-5.5-enhancements`). Never merge or push `main`; that needs the owner.
- Run: run 2 is **open-ended** (owner, ~17:27Z on 2026-10-22). It continues in waves (build, then blind critique, then integrate) until a blind judge prefers ours to GTA V and is wowed, or until the owner stops it. Owner priority since 17:43Z: playable mechanics first (walking/running, shooting, jumping, driving, flying), then the rest of the world.
- Records: [`loop/RUN.md`](loop/RUN.md) (run log), [`loop/PIECES.md`](loop/PIECES.md) (pieces, verdicts, merges), and the progress page, built with `python3 loop/make_progress.py` into `progress/index.html`.
- Machine: Mac Studio, Godot 4.7.1 Forward+, Metal for renders. Render only through `loop/render.sh` (shared GPU lease; at most one of our renders at a time).
- Last update: wave-M downtown pre-integration, 2026-10-23 ~10:40Z. Game code `5c30e70`. Owner build: `/Users/midir/Builds/OrchardReach-5c30e70.zip` (private macOS package; packaged headless `--test` 203/203).

## Downtown Marina Bay is playable (wave M pre-integration, 2026-10-23)

The owner's direction (play IN central Singapore around Marina Bay) is now on `Opus-5.5-enhancements`. Merged `--no-ff`:
downtown-map `9cccdda` (`83d3af2`), downtown-landmarks `266842a` (`bf99f7f`), downtown-blocks `eeaf5a4` (`a6085a6`), plus
seam fixes `85d359e`, `926bed2`, `c430037`, `5c30e70`. All blind critic rounds for these pieces were OURS LOSES (not wowed).

### What you can do downtown and how to get there
- **Drive the Marina Bay loop:** from the opening street (Telok Ayer side) go north up the avenue, left onto Collyer Quay,
  Fullerton Road, over the **Esplanade Bridge**, Esplanade Drive, Raffles Avenue, Bayfront Avenue North, over the
  **Bayfront Bridge**, Bayfront Avenue past MBS and the Gardens, Marina Boulevard, back to Collyer Quay (left-hand lanes).
- **Walk onto the Marina Bay side:** along the west shore promenade, up the new steps into **Merlion Park**, across the
  peninsula past One Fullerton, over the **Jubilee footbridge** to the **Esplanade** waterfront, then on along the
  Marina Promenade and over the walkable **Helix Bridge** to the MBS Event Plaza.
- **Fly:** take the helicopter from the aviation pad; downtown pads at NS Square (the old Float), the Lawn, Esplanade Park
  and Gardens East. Land and get out anywhere `DowntownPlan.heli_exit_allowed` permits.
- Full-scale landmarks: MBS (three towers, SkyPark cantilevered north, Shoppes, Event Plaza), ArtScience, Helix,
  Esplanade domes, Flyer + terminal, Supertree grove + domes, Fullerton Hotel / One Fullerton / Merlion Park. Built
  blocks: Raffles Place CBD towers and plaza, Boat Quay row, Cecil St, Shenton Way, MBFC, Marina South, civic north
  bank, Marina Centre. The existing heritage district is the adjoining Chinatown / Tanjong Pagar side.

### Owner asks, checked in real play (scripted player input, `--downtown-review`, no teleports inside a leg)
| Ask | Final code 5c30e70 (headless physics) | Rendered (Metal) |
| --- | --- | --- |
| Drive from the opening street over a bridge around the Marina Bay loop | **PASS**: loop completed in 309 s, deck height 3.89 m on the bridges | PASS on the deck/bridges in run 1 (`r_dtreview`, 926bed2) until the scripted driver overshot the Raffles Ave right turn into the new Flyer-site edge; not re-rendered on the final code |
| Walk from the promenade onto the Marina Bay side | **PASS**: 10/10 waypoints, promenade -> Merlion Park terrace (y 1.24) -> Jubilee Bridge (y 2.64) -> Esplanade waterfront | failed in both rendered runs on earlier code (0.3 m lips at the landmark decks, pavilion in front of the Jubilee landing): both fixed after; not re-rendered on the final code |
| Land the helicopter downtown and get out | **PASS**: landed at NS Square, exit allowed, walked away | **PASS** in both rendered runs |

The rendered review takes ~10 min of shared GPU; the orchestrator asked to stop iterating, so the drive/walk legs on the
final code are verified with the same scripted input headless only. Next wave: one rendered `--downtown-review` on 5c30e70+.

### Seam fixes (integration)
- Helix ramps were blocked by the map's channel seawall railing (rail gap at the plan ends, 20 m from the real crossing).
- Opaque black "crystal pavilion" pyramid in the bay removed; MBS curtain glass shows a fine per-floor grid again (new
  `refuge_bands` uniform in `skyline_facade.gdshader`, 0 for MBS only; default unchanged elsewhere).
- Skyline: downtown-blocks now fills every non-landmark, non-park plot; the bay views lost their skyline beside and behind
  MBS (old far-shore layers stood on today's Bayfront/Gardens), so three distant background rows were added beyond the
  east playable edge (z -1125/-1205/-1295). Rendered `--photos` vs `integration/Q`: CBD-facing views (02, 06, 07, 08, 09,
  11) are denser than Q; bay views (05, 15, 16, 17, 18) have skyline right and behind MBS again; the north (Marina Centre)
  side reads pale/hazy; heritage interiors unchanged.
- Walkability: landmark site decks (0.34-0.36 m) vs map ground (0-0.10 m) left lips the capsule could not climb; 1.6 m
  granite edge ramps on every land side; steps from the promenade into Merlion Park; One Fullerton pavilions narrowed so
  the Jubilee landing has an 11 m plaza.

### Verified (game code 5c30e70 unless noted)
- Headless: `--import` clean; `--test` **203/203**; `--capture` route **13/13**, 0 deaths, 157.8 s.
- Rendered (1280x720, `loop/render.sh`, lease `contaminated=no-exclusive-lock`, another session had the GPU at 60-72 %):
  `--capture` route **13/13**, 0 deaths, 164.0 s, 0 engine errors on `926bed2` (world changes after it are walk ramps and
  pavilion sizes only). `world_ui_ready_ms` **11,516** rendered (Q: 9,960), 8,193 headless editor, **7,108 packaged**.
  Route frame times excl. readback over 8,459 frames: mean **19.0** / p50 **17.7** / p95 **27.0** / p99 **35.2** ms
  (Q: 14.5/14.5/20.5/23.4 — a real regression from the downtown geometry plus a busy GPU). Downtown perf sweep without
  readback (900 frames, 6 views): p50 16.3 / p95 21.0 / p99 25.1 ms; worst Shenton Way street p95 25.1 ms.
- Rendered `--photos` (29 views, 0 errors) and `--gameplay-photos` (7) on 5c30e70; JPEGs in `progress/img/integration/M/`
  (same names as Q, plus `photos_photo_19..29_dt_*` downtown views and `downtown_*` helicopter / street stills).
- Packaged build `OrchardReach-5c30e70.zip` (826 MB): unzipped with `ditto`, packaged binary headless `--test` 203/203.

### Open issues (downtown)
- Frame time p95 27 ms vs 20.5 ms in Q; load 11.5 s vs 10.0 s. Draw-call/LOD work on blocks + landmarks is needed.
- Downtown streets are empty of traffic and pedestrians (street-life M2 is still building; blocks-M1 gap).
- Marina Centre (north) blocks read pale and flat at distance; behind MBS the legacy SkyPark wedge caps towers at 70 m.
- The scripted downtown driver overshoots right-angle right turns at speed (it is a QA driver, but the Raffles Ave /
  Bayfront Ave North corners are tight against the Flyer and Marina Centre plots).
- Landmark critics' gaps stand: no crisp long tower shadows / aerial depth layering, helicopter hero framing.
- `--downtown-review` stills, views and perf sweep only run rendered (headless skips them).

## What is merged (wave Q integration, 2026-10-23 ~02:50Z)

| Piece | Merged (merge) | Critic vs GTA V | Better than baseline (critic) | Integrator seam fixes |
| --- | --- | --- | --- | --- |
| driving | Q2 head `ccb87f0` (`8ab2a28`) | OURS LOSES, Q1–Q3 | **yes** in Q1 and Q2. Q3 judged no, so it was not merged | none needed |
| combat | `a5e1367` (`2548105`) | OURS LOSES, Q1 + Q2 | no (2 regressions) | `b79c3e3`: both regressions fixed |
| locomotion | `425951c` (`a14a9c2`) | OURS LOSES, Q1 + Q2 | no | `a14a9c2` camera-frame merge, `cdef3a4` head probe; orchestrator gates measured OK |
| characters | **not merged** | OURS LOSES, Q1 + Q2 | no | branch `opus55/characters` and its worktree kept |

What each merge brings:

- **Driving:** per-pixel chase-cam motion blur (gated by depth and height, with no ghosted pedestrians), de-speckled asphalt, 4x anisotropy, detailed tyres and alloys, and an even paint base coat.
- **Combat:**
  - an eye-level two-hand stance with physical ragdoll deaths
  - a magazine-drop reload
  - hostiles that fire back
  - no interaction prompts during a firefight
  - one "Officer down." toast per burst
- **Locomotion:**
  - planted-foot lock with leg IK: planted-foot slip falls from 0.15–0.64 m/s to at most 0.0006 m/s
  - an authored backpedal and weighted starts
  - a continuous sprint-180
  - pedestrian and prop avoidance and collision
  - a shoulder-safe aim camera that swaps to the left shoulder in colonnades

### Seam fixes on the integration branch

- **`b79c3e3`, combat:**
  - **Aim pose.** The pistol is now at shoulder height on the centreline. Before the fix, the rig's `.r` side appears on the left of the screen from the right-shoulder camera, so the gun sat exactly behind the head. A camera-frame probe measured head and gun both at x/z = -0.52, and the raised arm read as "a phone to the ear". The aim camera is also 0.10 m higher.
  - **Bullet holes.** Bullet-hole decals now project 0.5 m deep instead of 0.22 m, so they render as crisp dark holes again instead of ghost circles.
  - **Self-test.** The aim test now checks shoulder height (1.28–1.55 m).
- **`a14a9c2`, merge resolution:** combat's aim framing offset now rides locomotion's camera-yaw shoulder frame, so it follows a swapped shoulder.
- **`359fa91`, route driver:** the scripted route driver backs out after 3 s without 0.5 m of progress. The first rendered route failed gate 6 because two pursuing police cars boxed the car in at the (-156,156) corner for 140 s. The combat-Q1 critic had hit the same failure once.

### Why characters was not merged

- Skin-coloured shards poke through the clothes in most close and medium frames.
- The support hand no longer grips the pistol, and the idle fingers pass through the gun.
- Loading takes 80 s instead of 10 s, because `character_look.gd` rebuilds a 55k-vertex mesh in GDScript on the main thread.
- Its `CharacterHands` IK competes with combat's `AimIkLayer` for the hands.
- What is worth salvaging later: the varied crowd wardrobe, skin without facets, and better hair. The mesh rebuild would need caching to disk, and the hand IK has to be unified with `AimIkLayer` first.

## Verified (final game code `359fa91`)

### Headless

- `--test`: 164/164 PASS.
- `--capture` route: 13/13 with 0 deaths after every merge (160.3, 157.8, 157.7 and 160.7 s), and 163.8 s on the final code.

### Rendered

Real Metal frames at 1280x720 through `loop/render.sh`. The lease reported `contaminated=no-exclusive-lock`, so timings are approximate.

- **`--capture` route:** **13/13, 0 deaths, 160.9 s, 0 engine errors.**
  - Frame times excluding readback, over 10,920 frames: mean 14.5, p50 14.5, p95 20.5, p99 23.4 ms. Integration P measured 14.1 / 14.1 / 19.9 / 22.8.
  - Stalls happen only in the load frames.
  - `world_ui_ready` is 9.96 s.
- **Other runs:** `--photos` (18), `--gameplay-photos` (7), `--combat-review` and `--drive-showcase` all exited 0 with 0 engine errors. These ran on `cdef3a4`; `359fa91` changes only the route driver.
- **Photos against P:** PSNR is 25.7–44.2 dB, and only the water-animation views (photo_17, photo_18) are below 30 dB.
- **Gameplay photos against P:** the same views, with cleaner asphalt in photo_03.
- Images are in `progress/img/integration/Q/`, with the same names as `integration/P/`.

### Checked by eye in rendered frames

- In route 03 and 04, both arms extend at shoulder height toward the target over the shoulder; it no longer reads as a phone held to the ear.
- The close aim views show an isosceles two-hand stance.
- Bullet holes are crisp and dark.
- The drive showcase shows speed blur only near the road, plus a handbrake slide and damage.
- The 18 beauty views are unchanged.

### Locomotion gates (headless, `--fixed-fps 30`, `--locomotion-review --loco-metrics-only`)

| Measure | Merged line | Integration P |
| --- | --- | --- |
| Head bone yaw off the line of travel (median, walk/run phases) | 0.2–0.6° | — |
| Stance knee, minimum | 8.3° | 14.5° |
| Pelvis height | 0.900 m | 0.900 m |
| Ankle gap, walk / run / sprint | 0.13 / 0.11 / 0.10 m | — |
| Speed, walk / run / sprint | 1.50 / 3.60 / 6.80 m/s | — |

## Honest status against GTA V

Every blind round in run 2 has returned **OURS LOSES**. That includes wave Q: characters 2 rounds, locomotion 2, combat 2 and driving 3. No judge was wowed, and no piece is preferred to GTA V. The biggest named gaps from the latest critics:

1. **Hero character fidelity at 1–3 m.** No cloth folds; the face is waxy with no micro-detail; the hands are mittens; the pistol is a black lump.
2. **City life.** Junctions are empty in normal play. The crowd uses one body and face template and walks in lockstep knots. There are blockout props: salmon and mint blocks, toy scooters with ring wheels, flat bikes, a floating black box sign.
3. **Street surfaces and dressing.** Chase-cam pavements, kerbs and street furniture (driving-Q3 check A). The paving shows repeating grime blotches.
4. **Combat staging.** There is no police car, lightbar or cover in the police firefight. From the gameplay camera the pistol is still small and dark.
5. **Locomotion feel.** Stops are instant. The running jump is a tuck hop. The sprint-180 has a brief lunge. The aim camera still meets walls in the arcade during strafe and backpedal.

## Open issues (not fixed by this integration)

- **Walker's face:** in front walks it reads as turned about 35° to his left and up. The head bone faces the line of travel (measured), skeleton rest equals skin bind, and the same read shows in baseline `idle_front`. The cause is probably the face, eye or hair texture or the mesh. Not fixed.
- **Motion blur:** near-edge props (yellow share bikes, a parked coupe) still double at about 60–70 km/h in route 06.
- **HUD:** the pistol ammo panel still shows while driving. Q3 hid it, but Q3 was not merged.
- **Route corner:** the scripted route always needs one back-out at the (-156,156) corner (logged as `drive no progress`). This is fine for QA, but the corner is tight.
- **Driving Q3 extras** that could be cherry-picked separately: signal heads facing every approach, and the hero cobalt clear-coat. Do not take `drive_life.gd`; it is showcase staging and causes the drive-leg stall and the pull-away hitch.
- **Carried over from P:**
  - a dark airframe shadow on the bay under the helicopter in banks
  - two floating dark cubes above the hawker-centre roof
  - faceted sedan paint
  - a neck texture patch
- Do not use the save slot: always pass `--qa-session <own dir>`.

## How to run

```sh
cd <checkout>                     # this directory
godot --headless --path game --import                                   # fresh worktree only
python3 game/tools/bounded_run.py --seconds 300 --log /private/tmp/opus55/<you>/test.log -- \
  godot --headless --path game -- --test --qa-session /private/tmp/opus55/<you>
python3 game/tools/bounded_run.py --seconds 420 --log /private/tmp/opus55/<you>/route.log -- \
  godot --headless --path game -- --capture --capture-dir=/private/tmp/opus55/<you>/cap --qa-session /private/tmp/opus55/<you>
bash loop/render.sh <label> 480 /private/tmp/opus55/<you>/route -- -- --capture --capture-dir=/private/tmp/opus55/<you>/route/out \
  --qa-render-size=1280x720 --qa-session /private/tmp/opus55/<you>/route/session
```

- **Review modes:** `--photos`, `--gameplay-photos`, `--heli-review`, `--combat-review`, `--drive-showcase`, `--locomotion-review`.
  - `--locomotion-review` takes the engine arg `--fixed-fps 30`. `--loco-metrics-only` gives headless metrics; `frames.jsonl` now carries `head_yaw_rel`, `head_pitch` and `look_yaw`.
  - `--combat-review` logs the aim bones in the camera frame. It needs a rendered run; run headless, it stalls at the first still.
- **Other modes:** `--perf-probe`, `--sightline-probe`, and `--soak` together with `--capture`.
- **Frame times:** `<capture-dir>/capture_log.json` (`frame_times`, which excludes readback) and `frame_stalls.jsonl`.

**Worktrees and branches:**
- The merged piece worktrees (driving-q, combat-q, locomotion-q) were removed after the push. Their branches are kept.
- Still present and unmerged: `.worktrees/{characters,street-life,street-life-fix,aerial,nearfield}`.

## Previous

- **Wave P integration** (2026-10-22 ~20:50Z, game code `acffbe0`): locomotion, combat, driving and helicopter were merged with seam fixes. Results: 152/152 regressions; route 13/13 headless and rendered; rendered p95 19.9 ms. Images: `progress/img/integration/P/`.
- **Run 1 final integration C** (~11:45Z, game code `32e08ba`): water, skyline, lighting, materials, on-foot, helicopter and driving were merged. Results: 140/140 regressions; rendered p95 18.5 ms. Images: `progress/img/integration/C/` (also A and B).
- **Wave 5** (branch `feature/wave-05-opus`): final candidate `98b41b2`, rendered-verified fallback `d2a6cad`. Both are private native macOS packages, not cleared for public redistribution of provider assets. Details: [`waves/05/RELEASE_REPORT.md`](waves/05/RELEASE_REPORT.md).
