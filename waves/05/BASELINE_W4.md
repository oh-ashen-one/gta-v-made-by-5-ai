# Unchanged wave-4 baseline capture (for the manager's milestone graphic)

**Status: CAPTURED (real Metal renders), 2026-10-22 02:49:05–02:49:51 UTC.** The files are in [`evidence/rendered/baseline-w4-photos/`](evidence/rendered/baseline-w4-photos/) (15 fixed views) and [`evidence/rendered/baseline-w4-gameplay/`](evidence/rendered/baseline-w4-gameplay/) (7 gameplay views).

- The owner's requested view is [`baseline-w4-photos/photo_06_aerial_district.png`](evidence/rendered/baseline-w4-photos/photo_06_aerial_district.png): camera (250, 95, 250), look (-40, 0, -60), FOV 62.
- The ordinary wave-4 opening is [`baseline-w4-gameplay/photo_01_gameplay_opening_start.png`](evidence/rendered/baseline-w4-gameplay/photo_01_gameplay_opening_start.png): the player inside the safe room.
- Both runs exited 0. Each `run.log.meta.json` records `checkpoint` `6b51a26afbc3e638d859d9051d423b117ffb3c0a` and the SHA-256 of every source file at launch. The local-modification patch was empty. `identity.json` lists the SHA-256 of each PNG.
- **Not an exclusive GPU:** one foreign Blender render ran during the captures (`gpu-slot.json`: `contaminated: true`). This affects timing only, not the stills.
- The wave-5 candidate's frames from the same cameras are in `evidence/rendered/candidate-*` and must not be labeled wave 4.

This file also records the plan and the exact identity, so that no Opus-modified output can be mislabeled as wave 4.

## Identity

- Baseline source: detached worktree of `6b51a26`, the manager's archive commit. Its tracked `game/` tree is byte-identical to Argon's `a5bf132` (`git diff a5bf132 6b51a26 -- game` is empty). Private provider assets and the Godot import cache are APFS clones of the incoming checkout. No wave-5 edit was ever applied to this worktree.
- Engine: the same Godot 4.7.1.stable.official.a13da4feb, Forward+, rendered with Metal.
- Each capture's `bounded_run` metadata records the checkout HEAD and SHA-256 hashes of every `game/src/*.gd` file at launch. That metadata is the proof that the run used the unchanged checkpoint.

## Incoming state before any wave-5 change (headless, 2026-10-21 23:58–00:01 UTC)

- Import: clean.
- Regressions: 85/85, exit 0.
- Script validation: **FAIL**. `capture_director.gd:857` has a parse error, so the scripted mission route cannot start at all. This is a wave-4 defect; it is fixed only on the wave-5 branch.
- `--photos` and `--gameplay-photos` do not load `capture_director.gd`, so the baseline stills can still be rendered from the unchanged tree.

## Planned rendered views (run only under the shared lease and the render gate)

1. `--photos`: includes `aerial_district` at camera (250, 95, 250), look (-40, 0, -60), FOV 62, the owner's requested view, plus the other fixed views.
2. `--gameplay-photos`: includes `opening_start`, the ordinary wave-4 opening (player inside the safe room, yaw -52°).

## Why it was late

Foreign `veyr-review-fable-20261021` Blender renders held the shared renderer capacity from the start of wave 5:

- Four renders at the start, on 4-hour leases. The oldest was replaced at 01:14 UTC by a new session, which ended at about 01:56.
- Three remain, with leases ending at about 03:35–03:37 UTC (see `BLOCKER_RENDER_CAPACITY.md`).

The mixed cap of 2 forbids launching Godot while two or more renderers run. A gated runner (lease → `render_gate.py` → `bounded_run.py`) waited for capacity. At 02:49 UTC the foreign loop dropped to one render, and the runner captured these views.

## How to reproduce the baseline capture without wave 5 (manager)

The wave-5 builder's scratch worktree is temporary. To capture the unchanged wave-4 views later from any checkout of `6b51a26` or `a5bf132`:

1. Restore the private provider assets into `game/assets/providers` (see `waves/05/PRIVATE_TRANSFER.json`).
2. Run a headless import: `godot --headless --path game --import`.
3. Run both captures under the shared lease, with the render gate inside it:

```sh
GPU_SLOT_DIR=/Users/midir/sm2-n1/_scratch/gpu \
  <claude-code-game-builder>/tools/gpu/gpu_slot.sh capture --label w4-baseline -- \
  python3 game/tools/render_gate.py -- \
  python3 game/tools/bounded_run.py --seconds 120 --log /ABS/w4-photos.log -- \
  godot --log-file /ABS/w4-photos-engine.log --path game -- --photos --capture-dir=/ABS/w4-photos
```

Use the same command with `--gameplay-photos` for the wave-4 opening (`opening_start`).

`photo_06_aerial_district.png` is the owner's requested view: camera (250, 95, 250), look (-40, 0, -60), FOV 62.

