# Singapore relay — wave 5 (final, Opus 5.5) — IN PROGRESS (release candidate built)

> **BLOCKER — manager action requested:** wave 5 has had no shared renderer capacity for any render. The foreign `veyr-review-fable-20261021` loop holds the Blender renderers and refills its slots. See [`waves/05/BLOCKER_RENDER_CAPACITY.md`](waves/05/BLOCKER_RENDER_CAPACITY.md).

- Builder: Opus 5.5 (`claude-opus-5-5`) through Claude Code, branch `feature/wave-05-opus`. No main merge, no public release. No sixth wave: [`NEXT_GOAL.md`](NEXT_GOAL.md) points to the release report.
- Fixed window: 2026-10-21T23:56:42Z → 2026-10-22T03:56:42Z (final 30 min included).
- Machine: Mac Studio M3 Ultra 256 GB (`Mac15,14`, verified). Engine: Godot 4.7.1.stable.official.a13da4feb, Forward+, native macOS.
- Incoming: `6b51a26` (manager archive) over the Argon game tree `a5bf132`.
- Read first: [`waves/05/RELEASE_REPORT.md`](waves/05/RELEASE_REPORT.md) (what was delivered, what is verified, what is not).

## Release candidate (private, native macOS)

- Built from **`584fb590e34466d6103c22196381a686d1bf44d2`** with a clean `game/` tree. Later commits change documentation and evidence only; check with `git diff 584fb59 HEAD -- game`.
- Files, git-ignored and local only: `package-wave05/OrchardReach-wave-05-final-signed.zip` (ad-hoc signed private copy), `package-wave05/OrchardReach.zip` (raw export), plus `hashes.txt`, `identity.txt` and `sign-report.json`.
- SHA-256: signed zip `a493083299b1f592c0f7e113be94fe9d49399a3672d81eb61dbd6d654f2a2079`; raw zip `5025c0b34f3f895e08ddad77553d79ad12cab235ffd585e21a870326e355a786`; PCK `ab713a8d8a7a0687022648a7eb78d16e5d2d5982efa32d9a328db4853d8b4ca6`; signed executable `8bcab7662ccc07941d9c89be7b7a6bf9eaa3469f38e80ed3c3f0b0b97c2dde03`.
- Packaged verification, run headless with the signed binary (`waves/05/evidence/final-package/`):
  - 97/97 regressions, clean exit.
  - Two-process save/relaunch: write in one PID, Continue in a fresh PID; position, health and weapon restored.
  - Scripted route: 13/13 gates, 0 deaths, 147.6 s.
- The signature is a local ad-hoc signature only: no Developer ID, no notarization, and no clearance for public redistribution of provider assets.

## Verified this wave (headless unless a rendered file is linked)

- Incoming checkpoint: import clean and 85/85 regressions, but `capture_director.gd:857` had a parse error, so the route could not run at all (`evidence/incoming-validation/`).
- Mission route: 13/13 gates, 0 deaths, on every build since the recomposition (`evidence/headless-route*/`).
- 30-minute soaks (`--capture --soak`, three missions, fixture phase, mixed free roam):
  - soak #1 (`soak1-failed`) found a carjack-victim defect.
  - soak #4 (`soak4-failed-freeroam`) found a U-turn wedge between opposite parked cars.
  - Both defects are fixed. Soak #6 on the fixed code: SEE FINAL UPDATE BELOW.
- Opening identity: headless ray probe of the real opening camera (`evidence/sightlines-headless/`, including `opening_probe_vs_concept01.png`). All three MBS towers and the SkyPark are visible, clear of the HUD card and the player, with Supertree crowns, the Flyer, the hawker hall, the heritage row and HDB.
- CPU (shared machine): physics tick ~11.3 → ~4.9 ms; process ~2.1 → ~1.7 ms; nodes 24,226 → 15,545.
- Draw objects: district mesh instances 11,064 → 909, static meshes merged into 1,107 MultiMesh draws, geometry-equivalent in probe views.
- Four fresh-context Opus critic passes (code review only): `evidence/critic_review_1..4.md`.

## Not verified / failing / open

- **No rendered frame of the wave-5 game or of the wave-4 baseline exists yet** (capacity). The rendered look, rendered frame time and rendered route are all unmeasured.
- The gated runner `scratchpad/bin/auto_render3.sh` is waiting. When capacity frees it captures, one engine at a time: the candidate opening, the unchanged wave-4 baseline, candidate fixed views, then a rendered candidate route. It launches nothing after 03:53 UTC. See `waves/05/BASELINE_W4.md`.
- Visual fidelity (ART-01..08), ordinary OS-input human playtest, audio listening, public asset-rights clearance.

## Known incidents

- At 00:55 UTC a save-probe run without `--qa-session` wrote the default user save slot (`~/Library/Application Support/Godot/app_userdata/Orchard Reach/orchard_reach_save.json`). The probe file was removed and the probe now refuses to run without a task-owned path. A pre-existing player save, if there was one, was overwritten at 00:55 and cannot be restored.

## Safety

Shared coordinator `GPU_SLOT_DIR=/Users/midir/sm2-n1/_scratch/gpu`, with `render_gate.py` inside the lease and `bounded_run.py` around every engine run. No foreign process or lock was touched. No provider credits were spent and nothing was generated externally. No main merge.
