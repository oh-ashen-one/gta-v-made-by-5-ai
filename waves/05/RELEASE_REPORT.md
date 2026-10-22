# Wave 5 (final) release report — Opus 5.5 via Claude Code

**Status: DRAFT, IN PROGRESS.** This report is updated during the wave. It becomes final only when this line says FINAL.

- Builder: Opus 5.5 (`claude-opus-5-5`) through Claude Code, on branch `feature/wave-05-opus`. There is no main merge and no public release.
- Fixed window: 2026-10-21T23:56:42Z to 2026-10-22T03:56:42Z. The final 30 minutes are included. There is no sixth wave.
- Machine: Mac Studio M3 Ultra, 256 GB (`Mac15,14`). Engine: Godot 4.7.1.stable.official.a13da4feb, Forward+, native macOS.
- Verdict: **best available experimental build, not north-star accepted** (GOV-02). The required capabilities are present and the scripted mission passes headless. Rendered visual fidelity and rendered performance remain unverified or below target.

## What wave 5 inherited

- Incoming source was `6b51a26`, the Argon `a5bf132` game tree. It imports cleanly and passes 85/85 headless regressions.
- **Its route automation did not parse.** `capture_director.gd:857` failed to compile, so the mission route could not run at all. Argon's driving fix had never been exercised.
- For the whole wave, shared renderer capacity was held by four foreign Blender renders (`veyr-review-fable-20261021`). Their leases record a 4-hour maximum hold, ending about 01:58 UTC for one and 03:35–03:37 UTC for the other three. The mixed cap of 2 therefore blocked every Godot render until the final minutes. Rendered evidence is listed separately below.

## Delivered (all pushed)

| Area | Change | Evidence | Verified? |
| --- | --- | --- | --- |
| Mission integrity | Repaired route automation. Landing and exit gates now wait for the mission's own tick. | `evidence/headless-route*/` | Headless scripted route: 13/13 gates, 0 deaths, about 149–153 s on every build since the recomposition |
| Carjack / pedestrian safety | A 30-minute headless soak found that mission 2 wrecked its car. The displaced driver of an occupied car stood frozen in the carriageway, and cars could not hurt pedestrians, so the car rammed an invulnerable body. Vehicles now injure or scatter pedestrians; displaced drivers flee and rejoin a pavement. | `evidence/soak1-failed/`, `regressions_97.json` | Soak rerun pending (see below) |
| Driving / parking | Kerbside cars moved onto the carriageway; they had straddled the 16 cm platform edge in the pedestrian lane. Traffic perception is a lane corridor, with stuck recovery that checks behind. | `regressions_95*.json` | 87/91 kerbside cars pull out and drive 12 m unobstructed. Driving leg passes. |
| **Opening Singapore identity** | The run opens outdoors on a new heritage shophouse five-foot way facing the inhabited hawker hall across the x=-160 avenue, with HDB slabs behind. Marina Bay Sands (real proportions, about 196 m), the lotus ArtScience Museum and the Singapore Flyer stand across the bay on the far shore (CONCEPT-03 geography). The Supertree Grove sits in the bayside garden beside the opening sightline. The Merlion is on the promenade pier facing the bay. | `evidence/sightlines-headless/` | Headless geometric probe of the real opening camera: all three MBS towers and the SkyPark visible (75–77 % of the silhouette), clear of the HUD card and the player; Supertree crowns and Flyer above the hawker roof. **The rendered look is pending capacity.** |
| Performance | NPC/car simulation LOD and parked-car sleep. 10,161 static meshes merged into 1,107 MultiMesh draws (district mesh instances 11,064 → 909; unique materials 4,988 → 353). Ambient figures and their weapons are drawn within 150 m, with animation paused beyond that. | `perf_probe_*.json`, `batching/` | Headless CPU physics tick about 11.3 → about 4.5–4.9 ms; route CPU frame p95 18.0 → 12.0 ms. Batching is geometry-equivalent in five probe views. **No rendered frame-time measurement yet.** |
| Vehicles | Spinning and steering overlay wheels at measured baked-tyre positions; seated drivers. | `wheel_probe.log` | Not rendered |
| Pursuit | Police follow the junction grid with committed waypoints and close on mid-block goals. Pursuit telemetry added to route samples. | regression checks; route telemetry | Headless: a responder closed from 166 m with zero stationary samples. Live rendered pursuit not observed. |
| Boundaries | Landable far shore, with no on-foot exit there (out of bounds); helicopter aerial envelope; ditch recovery. | regression checks | Headless |
| Streetscape | Double yellow lines that stop at junctions; white kerbside lots; five-foot-way pedestrians; Tembusu Food Centre signboard and street-name blades. | probe | Not rendered |
| Audio | Click-free engine and rotor loop seams, a whole-cycle siren, a soft-saturated gunshot. | `regressions_94_audio.json` | Objective metrics only. **Nobody has listened.** |
| QA tooling | Sightline probe, perf probe, mesh census, wheel probe, two-process save/relaunch probe; QA entry points fail fast. | `evidence/` | — |
| Independent review | Three fresh-context Opus critic subagent passes over the source diff. 6 major/high and 11 minor/low findings were fixed or documented. | `evidence/critic_review_1.md`, `_2.md`, `_3.md` | Code review only, not a visual review |

## Not done / failing / untested (carry-forward for the owner)

- Rendered captures of the final candidate and the wave-4 baseline depend on capacity freeing in the final window; see the section below.
- GTA VI-level fidelity (ART-01..08): not accepted. Landmark meshes are original low-poly authored forms, with about 4.5k triangles for MBS.
- Rendered 60 fps contract (PERF-02 / QA-020): not measured this wave. The wave-3 rendered p95 of about 73 ms is the last rendered figure, and it predates the batching and LOD work.
- Ordinary OS-input human playtest, audio listening, the 30-minute soak and public asset rights clearance: not done.
- One stray write: a save-probe run without `--qa-session` wrote the default user save slot once at 00:55 UTC. The probe file was removed and the probe now refuses to run without a task-owned path.

## Rendered evidence

PENDING — filled from actual captures only.
