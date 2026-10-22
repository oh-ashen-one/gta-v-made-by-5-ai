# Singapore relay — wave 5 (final, Opus 5.5) — IN PROGRESS (final phase)

- Builder: Opus 5.5 (`claude-opus-5-5`) through Claude Code, branch `feature/wave-05-opus`. No main merge, no public release. No sixth wave: [`NEXT_GOAL.md`](NEXT_GOAL.md) points to the release report.
- Fixed window: 2026-10-21T23:56:42Z → 2026-10-22T03:56:42Z (final 30 min included).
- Machine: Mac Studio M3 Ultra 256 GB (`Mac15,14`, verified). Engine: Godot 4.7.1.stable.official.a13da4feb, Forward+, native macOS (Metal 4.0 for renders).
- Incoming: `6b51a26` (manager archive) over the Argon game tree `a5bf132`.
- Read first: [`waves/05/RELEASE_REPORT.md`](waves/05/RELEASE_REPORT.md) (what was delivered, what is verified, what is not), then [`waves/05/evidence/rendered/README.md`](waves/05/evidence/rendered/README.md) (the real renders).

## Release candidates (private, native macOS, git-ignored `package-wave05/`)

1. **Final candidate `98b41b2`**: `d2a6cad` plus HUD fixes (ammo backing plate; the minimap draws the bay and far shore) and route automation fixes.
   - SHA-256: signed zip `129ecc4f15a6526dab241b231aad90bf18c977626acc248b4761cf1748fbb550`, raw zip `131aa64b2b3815bd3714129b7a6455e14def70a34d4ba862810ef668b716cd88`, PCK `5cb6c167ae883d9b4c242b184dfb49d9f7ad2608f054a840320103d3e095bd0a`, signed executable `8d071ddf0a9c358c0e4bc6e2a3b8ad16255c63eb8ea2378312a8196270f33000`.
   - Packaged headless results (`waves/05/evidence/final-package-98b41b2/`): 97/97 regressions; save → relaunch → Continue PASS (position, health, weapon); route 13/13 with 0 deaths in 147.6 s.
   - It is in `package-wave05/`, and the zip hashes were re-checked after persisting.
   - Rendered: only if capacity frees before about 03:50 (the gated runner `scratchpad/bin/auto_render5.sh` is waiting).
2. **`d2a6cad`**: the rendered-verified fallback, in `package-wave05/d2a6cad/` (`waves/05/evidence/final-package/`). Its game code differs from `98b41b2` only in `hud.gd` and the QA automation.
   - SHA-256: signed zip `36c5132f3948ad465b4860ae9d9c166dd7eedfee99ade6120e578e988eb2198d`, raw zip `04f2182845dba94326eabf43a8d43f55144db6861fe4e36f3d4e459fd695f6b6`, PCK `233a76c68f3ca83207e9575790bb0c51ff674eeba6ed596fb07b9ee7036ffc64`, signed executable `8cbba859c0de59f8f7169822aa05073676a6b92e3fb01e5dd463352873116548`.
   - Packaged headless results: 97/97 regressions, save/relaunch PASS, route 13/13 in 147.6 s.
   - **Packaged rendered (Metal): route 13/13, 0 deaths, 149.1 s**, plus the opening, gameplay and fixed views.

Both signatures are local ad-hoc signatures only: no Developer ID, no notarization, and no clearance for public redistribution of provider assets.

## Verified this wave

- **Real renders** (02:49–02:54 UTC, shared GPU, `evidence/rendered/`):
  - The unchanged wave-4 baseline: 15 fixed views, including the owner's aerial camera, and 7 gameplay views.
  - The `d2a6cad` candidate: 16 fixed views, 7 gameplay views and an 11-shot rendered route.
  - Rendered route frame time: p50 7.73 ms, p95 11.65 ms, p99 15.30 ms, max 1,063 ms. Not acceptance-valid because of contamination.
- Fresh-context critic of the renders (`evidence/critic_review_5_rendered.md`):
  - The opening frame now reads as Singapore.
  - Concept scores: on foot 4/10, driving 2/10, helicopter 3/10.
  - Worst defects: the minimap and ammo contrast (fixed in `98b41b2`, rendered re-check pending); an empty world, a white glow by the helicopter, and water reading as paving (open).
- Mission route: every source and packaged route after the recomposition passed 13/13 gates with 0 deaths, in 147.6–153.0 s headless and 149.1 s rendered.
- 30-minute soak attempts: #1, #4, #6, #7, #8 and #9 all aborted; the reasons and fixes are in the release report. #10 is running on `98b41b2` (03:02–03:34 UTC).
- CPU (shared machine): physics tick ~11.3 → ~5.1 ms. Mesh census: district mesh instances 11,064 → 909.
- Critic code passes 1–4 (21 findings) were fixed or documented.

## Not verified / failing / open

- Visual fidelity (ART-01..08) is far from the concepts, and the world is sparse.
- The 1.06 s render-side hitch on entering the market.
- `photo_06_aerial_district` lost the Flyer compared with wave 4.
- Not done: an exclusive-GPU frame-time measurement, an ordinary OS-input human playtest, an audio listening test, and public asset-rights clearance.

## Known incidents

- At 00:55 UTC a save-probe run without `--qa-session` wrote the default user save slot (`~/Library/Application Support/Godot/app_userdata/Orchard Reach/orchard_reach_save.json`). The probe file was removed and the probe now refuses to run without a task-owned path. A pre-existing player save, if there was one, was overwritten at 00:55 and cannot be restored.
- The `a53cd19` automation fix introduced a regression, soak #9's market-walk timeout. It was corrected in `98b41b2`.

## Safety

Shared coordinator `GPU_SLOT_DIR=/Users/midir/sm2-n1/_scratch/gpu`, with `render_gate.py` inside the lease and `bounded_run.py` around every engine run. One rendered engine ran at a time, and only while the foreign renderer count was below the mixed cap of 2. No foreign process or lock was touched. No provider credits were spent and nothing was generated externally. No main merge.
