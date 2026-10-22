# Unchanged wave-4 baseline capture (for the manager's milestone graphic)

**Status: PENDING — no capture made yet.** This file records the plan and the exact identity, so that no Opus-modified output can be mislabeled as wave 4.

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

## Why it is late

Shared renderer capacity was held by four foreign Blender renders from the start of wave 5. Their leases record a 4-hour maximum hold: one until about 01:58 UTC, three until about 03:35–03:37 UTC. The mixed cap of 2 forbids launching Godot while two or more renderers run. A gated runner (lease → `render_gate.py` → `bounded_run.py`) captures these views the moment capacity frees, interleaved with the final-candidate captures, and launches nothing after 03:50:30 UTC.
