# Orchard Reach — Opus 5.5 enhancement loop (rolling handoff)

- Branch: `Opus-5.5-enhancements` (remote `origin/Opus-5.5-enhancements`). Never merge or push `main`; that needs the owner.
- Run: run 2 is **open-ended** (owner, ~17:27Z): it continues in waves (build → blind critique → integrate) until a blind judge prefers ours to GTA V and is wowed, or the owner stops it. Owner priority since 17:43Z: playable mechanics first (walking/running, shooting, jumping, driving, flying), then the rest of the world.
- Records: [`loop/RUN.md`](loop/RUN.md) (run log), [`loop/PIECES.md`](loop/PIECES.md) (pieces, verdicts, merges), progress page `python3 loop/make_progress.py` → `progress/index.html`.
- Machine: Mac Studio, Godot 4.7.1 Forward+, Metal for renders. Render only through `loop/render.sh` (shared GPU lease, at most one of our renders at a time).
- Last update: wave-P integration, 2026-10-22 ~20:50Z. Last game-code commit `acffbe0`.

## What is merged (wave P, this integration)

| Piece | Merged (merge) | Critic vs GTA V | Better than baseline (critic) | Integrator seam fixes |
| --- | --- | --- | --- | --- |
| locomotion | `2d204a7` (`0ca72da`) | OURS LOSES, P1 + P2 | **yes**, both rounds | `a397d5b` running landings keep the stride |
| combat | `dac7463` (`b44f3c1`) | OURS LOSES, P1 | no (regressions) | `a4fb1b0`, `acffbe0` flash/tracers/sparks/holes, aim holds under fire, HUD toast |
| driving | `7f64ae5` (`f167e2f`) | OURS LOSES, P1 | no, but "no regressions found" | `5ae8ffb` per-kind launch/brake, cam scaled to body, wall sweep |
| helicopter | `1494459` (`d40aa96`) | OURS LOSES, P1 + P2 | no (regressions) | `26cd752`, `a397d5b`, `acffbe0` concrete not turf, workshop floor, lighter rotor veil, no blob decals on water |

What the owner asked for: the walk, jog and sprint are now separately authored gaits at their real speeds (about 1.5 / 3.6 / 6.8 m/s), not a sped-up walk. The stance is narrow (median foot spacing about 0.10-0.13 m, measured). The jump is human-height and has a moving airborne pose. The locomotion critic measured both complaints as fixed (`better_than_baseline=true` in P1 and P2). Its remaining loss to GTA V is character fidelity (face, hair and cloth), not the gait.

Earlier merges on this line (run 1): water, skyline, lighting, materials, on-foot, helicopter (C), driving (C). Not merged: street-life (`opus55/street-life-fix`, 14 commits ahead; unreliable headless route with ambient traffic). The wave-D branches `opus55/{aerial,characters,nearfield}` each hold one WIP commit from the stop at 17:43Z and are not merged.

## Verified (final game code `acffbe0`)

- **Headless:** `--test` 152/152 PASS. `--capture` route 13/13 with 0 deaths after every merge (152.8 / 163.9 / 164.8 / 160.8 s), and on `acffbe0` 157.0 s, exit 0, 0 fatal lines.
- **Rendered** (real Metal frames at 1280x720 through `loop/render.sh`. The lease reported `contaminated=no-exclusive-lock`, so timings are approximate):
  - `--capture` route: **13/13, 0 deaths, 159.4 s, 0 engine errors.** Frame times excluding readback over 11,086 frames: mean 14.1, p50 14.1, p95 19.9, p99 22.8 ms. Stalls occur only in the 3 load frames. Integration C measured 12.8 / 12.7 / 18.5 / 21.4 ms. On `a397d5b` there was one 383 ms stall at 132 s during the helicopter leg, which did not recur on `acffbe0`.
  - `--photos` (18), `--gameplay-photos` (7), `--heli-review` and `--combat-review` all exited 0 with 0 engine errors. Images are in `progress/img/integration/P/`, with the same names as `integration/C/`.
  - Checked by eye in rendered frames:
    - The workshop interior and forecourt are concrete again, matching C (`photo_13`/`14`).
    - The airfield apron is concrete, not lawn (`photo_09`).
    - The rotor reads as a light veil, and the airframe is visible under it (`route_09`).
    - The muzzle flash is a small burst at the muzzle. Spark streaks are short. Bullet holes are dark.
    - The van/route drive and the helicopter route views are coherent with C.
  - Not every frame was inspected at 100%.
- **Gait check:** at `--fixed-fps 30`, headless `--locomotion-review --loco-metrics-only` gives the same clip use and planted-slip metrics on the integrated line as on `opus55/locomotion`. The one difference is the running jump, which no longer plays the planted `land` clip; that change is intentional.

## Honest status against GTA V

Every blind round in run 2 so far has returned **OURS LOSES**: locomotion 2, combat 1, driving 1, helicopter 2. No judge was wowed, and no piece is preferred to GTA V. The latest critics' biggest gaps:

1. **Character fidelity at medium and close range** (locomotion-P2, combat-P1): the face lacks skin micro-detail, the hair is a shell, the shirt has no weave, seams or folds, and the fingers do not articulate on the grip. The gait is no longer the problem.
2. **Combat presentation:** the close aim pose has the head and torso about 60° off the barrel, so he looks at the camera instead of down the sights. Over-the-shoulder framing hides the gun under the minimap. Corpses freeze in odd poses. Reload is a static hold.
3. **Driving:** the road surface reads as speckled noise at 80 km/h (critic check A). Traffic is almost absent. Crash damage is faceted.
4. **Helicopter/aerial:** the city looks like a miniature from 100-150 m: bare lots, repeated blocks, few cars, flat haze.
5. **Collision and camera:** the player passes through pedestrians and street props (scooters, bikes, planters). The aim camera jams behind arcade pillars.

## Open issues (not fixed by this integration)

- A soft dark shadow follows the helicopter on the bay at about 30 m in banks (`--heli-review` h05c). The rotor-disc shadow and contact decal are now off over water, so this is the airframe's own shadow, and the water shader darkens it too much.
- Locomotion:
  - Backpedalling while aiming plays `aim_walk` reversed.
  - The 180° turn has no plant or skid.
  - Aimed strafe slip is about 0.65 m/s.
- Toy-like scooter and kick-scooter props.
- A dark patch on the player's neck texture.
- "[E] Take the package" shows mid-firefight at the combat gate.
- Performance is about 1.4 ms slower at p95 than integration C; combat FX and the helicopter are the likely cost. Not profiled.
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

- **Review modes:** `--photos`, `--gameplay-photos`, `--heli-review`, `--combat-review`, `--drive-showcase`, `--locomotion-review`. For the locomotion review, pass the engine arg `--fixed-fps 30`; `--loco-metrics-only` gives headless metrics.
- **Other modes:** `--perf-probe`, `--sightline-probe`, and `--soak` together with `--capture`.
- **Frame times:** `<capture-dir>/capture_log.json` (`frame_times`, which excludes readback) and `frame_stalls.jsonl`.

**Worktrees and branches:**
- Merged piece worktrees (locomotion, combat, driving-p, helicopter-p) were removed after the push. Their branches are kept.
- Still present: `.worktrees/{street-life,street-life-fix,aerial,characters,nearfield}`, all unmerged.

## Previous

- **Run 1 final integration C** (~11:45Z, game code `32e08ba`): water, skyline, lighting, materials, on-foot, helicopter and driving were merged. Results: 140/140 regressions; route 13/13 headless and rendered; rendered p95 18.5 ms. All 23 blind rounds returned OURS LOSES. Images: `progress/img/integration/C/` (also A and B).
- **Wave 5** (branch `feature/wave-05-opus`): final candidate `98b41b2`, rendered-verified fallback `d2a6cad`. Both are private native macOS packages, not cleared for public redistribution of provider assets. Details: [`waves/05/RELEASE_REPORT.md`](waves/05/RELEASE_REPORT.md).
