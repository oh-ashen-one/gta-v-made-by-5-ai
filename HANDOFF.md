# Orchard Reach — Opus 5.5 enhancement loop (rolling handoff)

- Branch: `Opus-5.5-enhancements` (remote `origin/Opus-5.5-enhancements`). Never merge or push `main`; that needs the owner.
- Run window: START 2026-10-22T06:28:30Z, FEATURE FREEZE 11:43:30Z, DEADLINE 12:28:30Z. Run record: [`loop/RUN.md`](loop/RUN.md); pieces and verdicts: [`loop/PIECES.md`](loop/PIECES.md); progress page: `python3 loop/make_progress.py` → `progress/index.html`.
- Machine: Mac Studio (`midirstudio.local`), Godot 4.7.1 Forward+, Metal for renders.
- Last update: wave-B pre-integration, 2026-10-22 ~11:30Z (before that: wave-A integration ~10:40Z). Last game-code commit `d3133d1`; the branch head after it only adds loop/progress records.

## What is merged (wave A)

| Piece | Merged commit | Critic verdict vs GTA V | Better than baseline (critic) |
| --- | --- | --- | --- |
| water | `e3eef3e` (merge `ca6591d`) | OURS LOSES (4/4 rounds) | yes, every round |
| skyline | `5e58313` (merge `9d849b4`) | OURS LOSES (4/4 rounds) | yes in A3 and A4 |
| lighting | `301a7c9` (merge `ffc3b01`) | OURS LOSES (4/4 rounds) | no (regressions); merged per the orchestrator's 08:39Z guidance, regressions fixed in `4d9af26` |
| street-life | not merged | OURS LOSES (2 rounds) | no; branch `opus55/street-life` and its worktree kept |

Integration seam fixes: `4d9af26` (Merlion jet/pier follow the moved statue, skyline haze reads the lighting sky, lighting fixes for sepia shade / milky aerials / sun bias, QA save guard, render gate counts `godot`), `0c36d4b` (water foam and spray), `d3133d1` (added Merlion view re-aimed).

Wave B/C pre-integration (Opus 5.5 pre-integrator, 2026-10-22 ~11:05-11:30Z): merged on-foot `35c1ba4` (merge `bf7929a`), helicopter `ceb507a` (`96920d1`), materials `24634e2` (`e83385b`) and its r3 head `98490b9` (`e4ab271`). Headless on `e83385b`: --test 136/136, route 13/13. Street-life is still NOT merged: blocker fixes live on pushed branch `opus55/street-life-fix` (worktree `.worktrees/street-life-fix`); its rendered route passed 13/13 but headless routes failed 2 of 4 (player-car/ambient deadlock; player car disabled by ambient collisions). Driving not merged by the pre-integrator. Details in `loop/RUN.md` (11:05Z-11:30Z lines).

## Verified

- **Headless** on `d3133d1`: `--test` 131/131 PASS; `--capture` route 13/13, 0 deaths, 149.9 s.
- **Rendered** on `d3133d1` (real Metal frames, 1280x720, `loop/render.sh`, GPU lease shared with other sessions, so timing is contaminated):
  - `--photos`: 18 views. `--gameplay-photos`: 7 views. `--capture` route: 13/13, 0 deaths, 151.9 s. 0 engine errors.
  - Route frame times (excluding readback): mean 15.0, p50 14.7, p95 22.4, p99 26.9, max 398 ms. The baseline was 11.8 / 11.7 / 17.1 / 18.7 / 328 ms. Water planar reflection about 2.5x the draw calls over the bay (critic water-A4). The 1.06 s market hitch did not recur.
  - Images: `progress/img/integration/A/` (same names as `progress/img/baseline/`).
- What the integrator saw in the frames, compared with the baseline: blue sky with cumulus and a warm low sun replace the lavender haze. The bay reads as water, with reflections, boats and wakes. There is a layered far city with aerial perspective. The rebuilt Supertrees and Merlion look much better. The streets now have parked cars, bins, bikes and a planted median. The void deck is legible. Lighting, water and skyline read as one place, with no seam between pieces in the standard views.

## Honest status against GTA V

Every wave-A critic verdict is **OURS LOSES**, and no critic was wowed. The integration has improved a lot on the inherited wave-5 baseline, but it is not near GTA V. The main gaps:

- **Sparse life:** few pedestrians and clone crowds (street-life was not merged).
- **Placeholder props:** the boat outboard is a ball; mannequin crews; box buses on the street-life branch.
- **Surface wear:** surfaces are still too clean (the wave-B materials piece is in progress).
- **Popcorn clouds:** small, uniform cloud sprites.
- **Aerials:** still beige and milky.
- **Character shading:** blotchy shading on the player's clothes.

## Open issues

- **Player self-shadow and camo blotches** on the shirt and trousers under the low sun. The trousers look grey with blotches; the baseline showed smooth denim. Real renders ruled out SSIL, SSAO, PCSS and the grade LUT (`--lighting-off=` diagnostics in `/private/tmp/opus55/integ-A/t-*`). Sun normal bias 2.0 did not remove it. Next suspects: shadow-map settings in `project.godot` (8192 atlas, soft filter quality 3) or a character-material interaction.
- **Scripted drive runs along the planted median.** Agave plants pass through the car body (route `06_driving`). The planter has no collision.
- **Workshop facade (photo 13):** lost its crisp dappled leaf light.
- **Water:** boat models are low detail; the foam is softer now but has not been re-judged by a critic.
- **Merlion jet:** the arc is placed from the GLB's jet bounds (mouth at about local (0, 8.25, -2.8)). Re-check it if `build_landmarks.py` changes the statue.
- **Save-slot hazard:** other sessions' route runs rewrote the player's real save slot (`~/Library/Application Support/Godot/app_userdata/Orchard Reach/orchard_reach_save.json`) at 09:08:33Z, 10:14:49Z and 10:32:07Z. Their branches do not have the `4d9af26` save guard yet. Always pass `--save-path=` until every branch carries it.
- **Render gate:** `render_gate.py` now counts Homebrew `godot` renderers. Before this fix, the cap of 2 relied on the lease alone. Expect more refusals when other sessions render; retry later.

## How to run

```sh
cd <checkout>                     # this directory
godot --headless --path game --import                                   # fresh worktree only
python3 game/tools/bounded_run.py --seconds 300 --log /private/tmp/opus55/<you>/test.log -- \
  godot --headless --path game -- --test --qa-session /private/tmp/opus55/<you> --save-path=/private/tmp/opus55/<you>/save.json
bash loop/render.sh <label> 600 /private/tmp/opus55/<you>/route -- -- --capture --qa-session /private/tmp/opus55/<you>/route \
  --capture-dir=/private/tmp/opus55/<you>/route/frames --qa-render-size=1280x720 --save-path=/private/tmp/opus55/<you>/route/save.json
```

Other game modes: `--photos`, `--gameplay-photos`, `--perf-probe`, `--sightline-probe`, and `--soak` together with `--capture`. Lighting diagnostics: `--lighting-off=ssil,ssao,pcss,lut,fog,vfog,glow,skyamb`.

## Previous: wave 5 (Opus 5.5, 2026-10-21/22)

- Ran on branch `feature/wave-05-opus`. The final candidate was `98b41b2`, with `d2a6cad` as the rendered-verified fallback. Both are private native macOS packages in the git-ignored `package-wave05/`, ad-hoc signed only. Not cleared for public redistribution of provider assets.
- Results: 97/97 regressions; route 13/13 (147.6 s headless, 149.1 s rendered); a 30-minute headless soak completed.
- Details are in [`waves/05/RELEASE_REPORT.md`](waves/05/RELEASE_REPORT.md) and [`waves/05/evidence/rendered/README.md`](waves/05/evidence/rendered/README.md).
- Known incident: a save-probe run at 00:55Z overwrote the player save slot.
