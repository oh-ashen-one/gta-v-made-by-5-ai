# Wave 5 (final) release report — Opus 5.5 via Claude Code

**Status: DRAFT, IN PROGRESS.** The report is updated during the wave and becomes final only when this line says FINAL.

- Builder: Opus 5.5 (`claude-opus-5-5`) via Claude Code, branch `feature/wave-05-opus`. No main merge, no public release.
- Fixed window: 2026-10-21T23:56:42Z → 2026-10-22T03:56:42Z (the final 30 minutes are included). There is no sixth wave.
- Machine: Mac Studio M3 Ultra, 256 GB (`Mac15,14`). Engine: Godot 4.7.1.stable.official.a13da4feb, Forward+, native macOS.
- Verdict: **best available experimental build; the north star is not accepted** (GOV-02). Every result below is **headless** (simulation, geometry or CPU) unless a file under `evidence/rendered/` is cited.

## What wave 5 inherited

- Incoming source: `6b51a26`, which carries Argon's `a5bf132` game tree. It imported cleanly and passed 85/85 headless regressions.
- **Its route automation did not parse.** A compile error at `capture_director.gd:857` meant the mission route could not run at all, so Argon's driving fix had never been exercised (`evidence/incoming-validation/`).
- The `veyr-review-fable-20261021` loop held the shared renderer capacity with foreign Blender renders throughout:
  - Four renders at the start, with 4-hour leases. The oldest was replaced at 01:14 UTC by a new session, which ended at about 01:56.
  - Three remained, with leases running to about 03:35–03:37.
  - `render_gate.py` therefore refused every Godot render under the mixed cap of 2. No foreign process was touched; the blocker was escalated in `BLOCKER_RENDER_CAPACITY.md`.

## Delivered and evidence

| Area | Change | Evidence | Status |
| --- | --- | --- | --- |
| Mission integrity | Repaired the route automation. Landing and exit gates wait for the mission's own tick. | `evidence/headless-route*/` | All 11 source-build route runs after the recomposition (route3–route13) and all 3 packaged route runs passed 13/13 gates with 0 deaths, in 147.6–153.0 s. Scripted input, not a human run. |
| **Opening Singapore identity** | The run opens outdoors on a new heritage shophouse five-foot way, facing the inhabited hawker hall across the x=-160 avenue, with HDB slabs behind. Marina Bay Sands (scaled to about 182 m towers and a 196 m SkyPark top), the ArtScience lotus and the Singapore Flyer stand across the bay on the far shore, matching the CONCEPT-03 geography. The Supertree Grove sits in the bayside garden beside the opening sightline. The Merlion stands on the promenade pier facing the bay. Signage: Tembusu Food Centre and street-name blades. | `evidence/sightlines-headless/release-code-2e38d8f/` | **Geometric probe of the release code (not a render).** Opening camera: MBS is 77 % unoccluded (2.1 % of frame, box 22–48 % of frame height); Supertree crowns 36 %, Flyer 39 %. Promenade: MBS 97 %, ArtScience 100 %, Merlion 98 %. Helicopter approach: Flyer 99 %, grove 92 %. That the MBS box clears the HUD objective card is computed from the `hud.gd` layout, not seen. **The rendered look is unverified.** |
| Carjack and pedestrian safety | Soak #1 found a defect: the displaced driver of an occupied car stood frozen in the carriageway. Cars could not hurt pedestrians, so mission 2's car rammed an invulnerable body until wrecked. Now vehicles injure or scatter pedestrians (one impact per person per 0.6 s), and displaced drivers flee and rejoin a pavement. | `evidence/soak1-failed/`, regression checks | Fixed. The soak #4 and #6 rerun missions passed the same leg. |
| Parking and U-turns | Kerbside cars moved off the 16 cm platform edge onto the carriageway. Soak #4 then found cars on opposite kerbs only about 11 m apart, less than the about 13 m a U-turn needs, so a free-roam car wedged for 95 s. Opposite lots are now staggered by 30 m. | `regressions_release_2e38d8f.json`, `evidence/soak4-failed-freeroam/` | **85/91 kerbside cars can pull out and drive 12 m**; 6 exceptions are listed in the check. The soak #4 leg that failed took 63 s in soak #6. |
| Traffic | Lane-corridor perception at about 8 Hz. Stuck recovery checks behind before reversing. | regressions | Busy-junction behaviour not observed by a human. |
| Pursuit | Police follow the junction grid with committed waypoints and close on goals in the middle of a block. Route samples record pursuit telemetry. | regression checks, `headless-route11-pursuit/` | Headless: a responder closed from 167 m to a minimum of 69 m, then fell back to 162 m once the wanted level dropped. In the packaged route, police were stationary near the player in 4 one-second samples. No rendered pursuit was observed. |
| Performance (CPU) | NPC/car simulation LOD, parked-car sleep, 150 m NPC draw range with paused animation. | `perf_probe_release_2e38d8f.json` and `.log` | On a shared, loaded machine: physics tick about 11.3 → 5.1 ms, process time about 2.1 → 1.8 ms, scene nodes 24,226 → 15,545. Headless route CPU frame p95: 18.0 ms before → 13.3 ms (route13), 12.5 ms (packaged). Every route still has one start-up hitch above 100 ms: the first frame, 240–274 ms. Every log reports `performance_acceptance_valid=false`. |
| Draw objects (census) | 10,118 static meshes merged into 1,107 MultiMesh draws. District mesh instances fell from 11,064 to 909 and unique materials from 4,988 to 353. | `batching/census_release_2e38d8f.log` | The counts come from a mesh census, not a renderer. The probe equivalence check (five views, within 0.3 percentage points per category) ran on an earlier 9,921 → 1,193 grouping. **No rendered frame time was measured.** |
| Vehicles | Spinning and steering overlay wheels at the measured baked-tyre positions; seated drivers. | `wheel_probe.log` | Not rendered. The van's baked left wheels sit about 0.24 m inboard of its right wheels; overlay placement follows the measurement but is unverified. |
| Boundaries | The far shore is landable, but on-foot exit there is refused, and a downed pilot is recovered. Helicopter aerial envelope and ditch recovery. | regression checks | Headless only. |
| Audio | The engine and rotor loops are generated past their end and crossfaded into their heads; the siren loops on whole cycles; the gunshot uses soft saturation instead of clipping. | `regressions_94_audio.json` | Objective seam and peak metrics only. The metric cannot detect an engine-loop click below the sawtooth's own about 0.31 step, so a click-free engine loop is unproven. **No listening test was done.** |
| QA tooling | Sightline probe, CPU probe, mesh census, wheel probe, two-process save/relaunch probe. QA entry points fail fast. | `evidence/` | — |
| Independent review | Fresh-context Opus critic subagents: four code passes (21 findings: 7 major or high, 1 medium-high, 1 medium, 12 minor, low or uncertain), plus a documentation-accuracy pass that drove this rewrite. | `evidence/critic_review_1..4.md` | Code and document review only. There was no visual or human acceptance. |

## 30-minute soak attempts (`--capture --soak`: three missions, fixture phase, mixed free roam)

| Soak | Code | Result |
| --- | --- | --- |
| #1 | `2463cd3` | Aborted at 231.9 s, during mission 2's drive: the frozen carjack victim. Fixed. |
| #4 | `86b5405` | Three missions, all fixture checks and the same-car reboard all passed. Aborted at 819.4 s: a free-roam car wedged mid-U-turn. Fixed. |
| #6 | `584fb59` | Three missions, all fixtures, the failed #4 leg (63 s) and three reboard cycles all passed. Aborted at 1266.4 s: in a fourth reboard, at a busy junction, the automation pressed interact while a passing AI car was nearer, and carjacked it. Interaction picking the nearest car is intended; the automation was fixed in `2e38d8f`. |
| #7 | `2e38d8f` | Three missions, all fixtures, four reboard cycles and the old U-turn leg all passed. Aborted at 1590.6 s: an AI car stopped at the central junction's signal stayed nearer than the automation's own car for its whole 6 s wait. Fixed in the automation in `d2a6cad`, which now tries each side of its car. |
| #8 | `d2a6cad` | **Running** (02:40–03:11 UTC). Result recorded below. |

**No 30-minute soak has completed yet.** Soaks #2, #3 and #5 were stopped early because newer fixes superseded them. They are not results.

## Release candidate

- Built from `c42425afd5a2fe568ff822dc3d7391fac62be747`. Its game code is identical to `2e38d8f`, the commit soak #7 runs on.
- Private, git-ignored files in `package-wave05/`, with SHA-256:
  - signed zip `3ae8f8c346720d651fb84f6680f9210eb5c99de4f1726c452fa9de104e493b22`
  - raw zip `5d600330c7b428167a1f4d6168cf2196722205be2fb0fcd3f0ae1c5b3b51548f`
  - PCK `54373c6d736c4328138da91092ceba89de075e0e75499af0ca313f5f23b97c05`
- Packaged checks, run headless with the signed binary:
  - **97/97 regressions**
  - **two-process save → relaunch → Continue**: position, health and weapon restored
  - **scripted route**: 13/13 gates, 0 deaths, 147.5 s
- The signature is a local ad-hoc signature only, with no notarization. Provider asset rights for public redistribution are unverified.
- Evidence: `evidence/final-package/`.

## Not done / failing / untested

- **Rendered captures:** not one rendered frame of the wave-5 game or of the wave-4 baseline exists unless `evidence/rendered/` is populated in the final minutes.
- **Fidelity:** GTA VI-level fidelity (ART-01..08) is not accepted. The landmark meshes are original low-poly forms; the MBS mesh has 4,564 triangles according to `game/assets/authored/landmarks_manifest.json`.
- **Frame rate:** the rendered 60 fps contract (PERF-02 / QA-020) was not measured this wave. The last rendered figure, about 73 ms p95 in wave 3, predates the LOD and batching work.
- Not done: an ordinary OS-input human playtest, a listening test, and public asset-rights clearance.
- **Incident:** at 00:55 UTC a save-probe run without `--qa-session` wrote the default user save slot once. The file was removed, and the probe now refuses to run without a task-owned path.

## Rendered evidence

PENDING. This section will be filled only from actual captures.
