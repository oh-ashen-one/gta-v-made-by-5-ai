# Wave 5 (final) release report — Opus 5.5 via Claude Code

**Status: DRAFT, IN PROGRESS.** This report is updated during the wave. It becomes final only when this line says FINAL.

- Builder: Opus 5.5 (`claude-opus-5-5`) through Claude Code, on branch `feature/wave-05-opus`. There is no main merge and no public release.
- Fixed window: 2026-10-21T23:56:42Z to 2026-10-22T03:56:42Z. The final 30 minutes are included. There is no sixth wave.
- Machine: Mac Studio M3 Ultra, 256 GB (`Mac15,14`). Engine: Godot 4.7.1.stable.official.a13da4feb, Forward+, native macOS.
- Verdict: **best available experimental build, not north-star accepted** (GOV-02). The required capabilities are present and the scripted mission passes headless. Rendered visual fidelity and rendered performance remain unverified or below target.

## What wave 5 inherited

- Incoming source was `6b51a26`, the Argon `a5bf132` game tree. It imports cleanly and passes 85/85 headless regressions.
- **Its route automation did not parse.** `capture_director.gd:857` failed to compile, so the mission route could not run at all. Argon's driving fix had never been exercised.
- For the whole wave, shared renderer capacity was held by foreign Blender renders from the `veyr-review-fable-20261021` loop. There were four, with 4-hour leases. One was replaced at 01:14 UTC by a new session, which ended about 01:56 UTC; three hold leases until about 03:35–03:37 UTC. Under the mixed cap of 2, `render_gate.py` refused every Godot render. The builder escalated to the manager (`waves/05/BLOCKER_RENDER_CAPACITY.md`) and touched no foreign process. Rendered evidence is listed separately below.

## Delivered (all pushed)

| Area | Change | Evidence | Verified? |
| --- | --- | --- | --- |
| Mission integrity | Repaired route automation. Landing and exit gates now wait for the mission's own tick. | `evidence/headless-route*/` | Headless scripted route: 13/13 gates, 0 deaths, about 149–153 s on every build since the recomposition |
| Carjack / pedestrian safety | A 30-minute headless soak found that mission 2 wrecked its car. The displaced driver of an occupied car stood frozen in the carriageway, and cars could not hurt pedestrians, so the car rammed an invulnerable body. Vehicles now injure or scatter pedestrians; displaced drivers flee and rejoin a pavement. | `evidence/soak1-failed/`, `regressions_97.json` | Soak rerun pending (see below) |
| Parking layout / U-turns | Soak #4 passed three missions, every fixture check and the same-car reboard cycle. In free roam, a car taken from a lot directly opposite another wedged mid-U-turn for 95 s: opposite parked bodies leave about 11 m, and a car needs about 13 m. Lots on the two kerbs are now staggered by 30 m, and the automation alternates its reverse steering. | `evidence/soak4-failed-freeroam/` | Soak rerun pending |
| Driving / parking | Kerbside cars moved onto the carriageway; they had straddled the 16 cm platform edge in the pedestrian lane. Opposite lots are staggered 30 m apart. Traffic perception is a lane corridor, with stuck recovery that checks behind. | `regressions_97.json` | 85/91 kerbside cars pull out and drive 12 m unobstructed. Driving leg passes. |
| **Opening Singapore identity** | The run opens outdoors on a new heritage shophouse five-foot way facing the inhabited hawker hall across the x=-160 avenue, with HDB slabs behind. Marina Bay Sands (real proportions, about 196 m), the lotus ArtScience Museum and the Singapore Flyer stand across the bay on the far shore (CONCEPT-03 geography). The Supertree Grove sits in the bayside garden beside the opening sightline. The Merlion is on the promenade pier facing the bay. | `evidence/sightlines-headless/` | Headless geometric probe of the real opening camera: all three MBS towers and the SkyPark visible (75–77 % of the silhouette), clear of the HUD card and the player; Supertree crowns and Flyer above the hawker roof. **The rendered look is pending capacity.** |
| Performance | NPC/car simulation LOD and parked-car sleep. 10,118 static meshes merged into 1,107 MultiMesh draws (district mesh instances 11,064 → 909; unique materials 4,988 → 353). Ambient figures and their weapons are drawn within 150 m, with animation paused beyond that. | `perf_probe_release.json`, `batching/` | Headless CPU: physics tick about 11.3 → 4.9 ms, process about 2.1 → 1.7 ms, nodes 24,226 → 15,545; route CPU frame p95 18.0 → 12.0 ms. Batching is geometry-equivalent in five probe views. **No rendered frame-time measurement yet.** |
| Vehicles | Spinning and steering overlay wheels at measured baked-tyre positions; seated drivers. | `wheel_probe.log` | Not rendered |
| Pursuit | Police follow the junction grid with committed waypoints and close on mid-block goals. Pursuit telemetry added to route samples. | regression checks; route telemetry | Headless: a responder closed from 166 m with zero stationary samples. Live rendered pursuit not observed. |
| Boundaries | Landable far shore, with no on-foot exit there (out of bounds); helicopter aerial envelope; ditch recovery. | regression checks | Headless |
| Streetscape | Double yellow lines that stop at junctions; white kerbside lots; five-foot-way pedestrians; Tembusu Food Centre signboard and street-name blades. | probe | Not rendered |
| Audio | Click-free engine and rotor loop seams, a whole-cycle siren, a soft-saturated gunshot. | `regressions_94_audio.json` | Objective metrics only. **Nobody has listened.** |
| QA tooling | Sightline probe, perf probe, mesh census, wheel probe, two-process save/relaunch probe; QA entry points fail fast. | `evidence/` | — |
| Independent review | Four fresh-context Opus critic subagent passes over the source diff, the last a whole-diff release review. 8 major/high and 11 minor/low findings were fixed or documented. | `evidence/critic_review_1.md` … `_4.md` | Code review only, not a visual review |

## Release candidate

- Built from `584fb590e34466d6103c22196381a686d1bf44d2` (clean `game/` tree). Private, git-ignored files in `package-wave05/`:
  - signed zip `a493083299b1f592c0f7e113be94fe9d49399a3672d81eb61dbd6d654f2a2079`
  - raw export zip `5025c0b34f3f895e08ddad77553d79ad12cab235ffd585e21a870326e355a786`
  - PCK `ab713a8d8a7a0687022648a7eb78d16e5d2d5982efa32d9a328db4853d8b4ca6`
- Packaged and headless, with the signed binary:
  - **97/97 regressions**.
  - **Two-process save → relaunch → Continue** restores position, health and weapon.
  - **Scripted route 13/13 gates, 0 deaths, 147.6 s**.
- The signature is local and ad-hoc only, with no notarization. Provider asset rights for public redistribution remain unverified.
- Full evidence: `evidence/final-package/`.

## Not done / failing / untested (carry-forward for the owner)

- Rendered captures of the final candidate and the wave-4 baseline depend on capacity freeing in the final window; see the section below.
- GTA VI-level fidelity (ART-01..08): not accepted. Landmark meshes are original low-poly authored forms, with about 4.5k triangles for MBS.
- Rendered 60 fps contract (PERF-02 / QA-020): not measured this wave. The wave-3 rendered p95 of about 73 ms is the last rendered figure, and it predates the batching and LOD work.
- Ordinary OS-input human playtest, audio listening, the 30-minute soak and public asset rights clearance: not done.
- One stray write: a save-probe run without `--qa-session` wrote the default user save slot once at 00:55 UTC. The probe file was removed and the probe now refuses to run without a task-owned path.

## Rendered evidence

PENDING — filled from actual captures only.
