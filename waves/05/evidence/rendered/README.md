# Rendered captures (real Metal renders) — wave 5

These folders contain the first and only rendered frames of wave 5. Shared renderer capacity freed at **02:49 UTC on 2026-10-22**, when the foreign `veyr-review-fable-20261021` loop dropped to one Blender render (PID 3909). The gated runner then rendered, one engine at a time, under the shared lease (`GPU_SLOT_DIR=/Users/midir/sm2-n1/_scratch/gpu`), with `render_gate.py` inside the lease and `bounded_run.py` around the engine.

- Engine: Godot 4.7.1.stable.official.a13da4feb, `Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M3 Ultra (Apple9)`, native macOS, 1280×720 captures.
- **Not an exclusive GPU.** One foreign Blender render ran throughout. `gpu-slot.json` marks every run `contaminated: true` (`no-exclusive-lock`), and the performance numbers below are therefore **not acceptance-valid** (`performance_acceptance_valid=false`).

## Identity

| Folder | What ran | Started (UTC) | Exit |
| --- | --- | --- | --- |
| `baseline-w4-photos/` | **Unchanged wave-4** tree: detached worktree of `6b51a26` (its `game/` is byte-identical to Argon's `a5bf132`), source build, `--photos` | 02:49:05 | 0 |
| `baseline-w4-gameplay/` | Same unchanged wave-4 tree, `--gameplay-photos` | 02:49:21 | 0 |
| `candidate-gameplay/` | **Wave-5 release candidate**: signed packaged binary built from `d2a6cad`, `--gameplay-photos` | 02:50:52 | 0 |
| `candidate-photos/` | Same candidate binary, `--photos` | 02:51:32 | 0 |
| `candidate-route/` | Same candidate binary, `--capture` (the scripted mission route) | 02:51:48 | 0 |

- Baseline proof: each baseline `run.log.meta.json` records `checkpoint` `6b51a26afbc3e638d859d9051d423b117ffb3c0a`, plus SHA-256 hashes of every source file at launch. The supervisor's local-modification patch for that worktree was empty (0 bytes).
- Candidate proof: the command in each candidate `run.log.meta.json` is the signed binary `signed/Orchard Reach.app/Contents/MacOS/Orchard Reach`. Its hashes are in `candidate-binary-hashes.txt`: executable `8cbba859…2548`, PCK `233a76c6…fc64`, re-checked unchanged at 02:57 UTC.
  - The `checkpoint` field in those files is the repository HEAD at launch, `43af02c`, which changed only documentation and evidence after `d2a6cad`.
  - The packaged game is the `d2a6cad` build (`candidate-binary-identity.txt`).
- Every folder has an `identity.json` with the SHA-256 of each PNG.

## Rendered route on the candidate binary (`candidate-route/`)

- **13/13 gates passed, 0 deaths, 149.1 s**: on foot to the hawker market, combat, package, car, uninterrupted drive to the aviation compound, helicopter, landing on the waterfront pad, delivery. This is scripted input, not a human run. See `run_excerpt.log`, `capture_log.json` and screenshots `01`–`11`.
- Frame time: process-frame intervals, excluding screenshot readback. The results:

  | p50 | p95 | p99 | max | mean |
  | --- | --- | --- | --- | --- |
  | 7.73 ms | 11.65 ms | 15.30 ms | 1,063 ms | 7.52 ms |

- Contention:
  - The foreign Blender render above.
  - A headless QA route run and a 20-second headless regression run (wave 5's own, 02:52:45–02:55:24 UTC) overlapped the last part of this capture.
- Stalls above 100 ms (`frame_stalls.jsonl`):
  - Start-up: 302 ms and 185 ms.
  - **One 1,063 ms hitch at 19.6–20.7 s**, during the walk into the hawker market, with no screenshot pending. Headless routes show no hitch there, so it is render-side; first-use pipeline or shader compilation is likely but not proven. Not fixed.
  - The other nine stalls (117–237 ms) all overlap screenshot readback.

## What the builder looked at

The builder viewed these six frames itself. Any other frame has not been reviewed by the builder. A fresh-context Opus critic reviewed 21 of these stills, with pixel and luminance probes, in [`../critic_review_5_rendered.md`](../critic_review_5_rendered.md). It found the opening reads as Singapore, scored the concepts 4/10 on foot, 2/10 driving and 3/10 helicopter, and reported the minimap and ammo-contrast defects that `98b41b2` addresses.

- `candidate-gameplay/photo_01_gameplay_opening_start.png`, the opening frame. Visible:
  - The player on a heritage shophouse five-foot way: green shutters and colonnade.
  - Marina Bay Sands: three towers and the SkyPark, clear of the objective card.
  - Supertree crowns and the Singapore Flyer.
  - The Tembusu Food Centre hall, with its sign partly hidden by a tree.
  - A double-yellow kerb line and a van on the left-hand carriageway.
- `baseline-w4-gameplay/photo_01_gameplay_opening_start.png`: the wave-4 opening is an indoor safe room.
- `baseline-w4-photos/photo_06_aerial_district.png` vs `candidate-photos/photo_06_aerial_district.png`: the same camera (250, 95, 250), look (-40, 0, -60), FOV 62.
  - The candidate moves MBS across the water onto the far shore and makes it larger.
  - The Flyer, prominent at the right in the wave-4 frame, **is no longer in this view**, and the Supertrees read smaller. This is a regression for this one camera, caused by the recomposition around the opening sightline.
- `candidate-gameplay/photo_06_gameplay_waterfront_promenade.png`: MBS towers fill the skyline behind the promenade, with the SkyPark cut off by the frame. Also visible: the ArtScience lotus, a railing, and the Merlion's water arc.
- `candidate-route/09_aerial_view.png`, from the helicopter:
  - MBS, the ArtScience lotus and the bay are visible.
  - **Defect:** a large blown-out white glow beside the helicopter.
  - **Defect:** the ammo counter (`3 / 96`) has poor contrast over the bright towers.
