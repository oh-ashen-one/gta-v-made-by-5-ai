# Wave 5 (final) release report — Opus 5.5 via Claude Code

**Status: DRAFT, IN PROGRESS.** The report is updated during the wave and becomes final only when this line says FINAL.

- Builder: Opus 5.5 (`claude-opus-5-5`) via Claude Code, branch `feature/wave-05-opus`. No main merge, no public release.
- Fixed window: 2026-10-21T23:56:42Z → 2026-10-22T03:56:42Z (the final 30 minutes are included). There is no sixth wave.
- Machine: Mac Studio M3 Ultra, 256 GB (`Mac15,14`). Engine: Godot 4.7.1.stable.official.a13da4feb, Forward+, native macOS (Metal 4.0 for rendered runs).
- Verdict: **best available experimental build; the north star is not accepted** (GOV-02).
  - A fresh-context critic of the first real renders judged it a pass as an incremental wave and a fail against the concept bar. Its concept scores: on foot 4/10, driving 2/10, helicopter 3/10 (`evidence/critic_review_5_rendered.md`).
  - Results are **headless** (simulation, geometry or CPU) unless a file under `evidence/rendered/` is cited.

## What wave 5 inherited

- Incoming source: `6b51a26`, which carries Argon's `a5bf132` game tree. It imported cleanly and passed 85/85 headless regressions.
- **Its route automation did not parse.** A compile error at `capture_director.gd:857` meant the mission route could not run at all, so Argon's driving fix had never been exercised (`evidence/incoming-validation/`).
- The `veyr-review-fable-20261021` loop held the shared renderer capacity with foreign Blender renders from the start of the wave until **02:49 UTC**. At that point it dropped to one render, and the gated runner produced the only rendered frames of the wave (see "Rendered evidence"). No foreign process was touched; the blocker is recorded in `BLOCKER_RENDER_CAPACITY.md`.

## Delivered and evidence

| Area | Change | Evidence | Status |
| --- | --- | --- | --- |
| Mission integrity | Repaired the route automation. Landing and exit gates wait for the mission's own tick. | `evidence/headless-route*/`, `evidence/rendered/candidate-route/` | **Rendered (Metal) route on the signed `d2a6cad` binary: 13/13 gates, 0 deaths, 149.1 s.** Headless: all 11 source-build routes after the recomposition and every packaged route passed 13/13 with 0 deaths, in 147.6–153.0 s. Scripted input, not a human run. |
| **Opening Singapore identity** | The run opens outdoors on a new heritage shophouse five-foot way, facing the Tembusu Food Centre hawker hall across the x=-160 avenue, with HDB slabs behind. Marina Bay Sands (about 182 m towers, a 196 m SkyPark top), the ArtScience lotus and the Singapore Flyer stand across the bay. The Supertree Grove sits in the bayside garden beside the opening sightline. The Merlion stands on the promenade pier. | `evidence/rendered/candidate-gameplay/photo_01_gameplay_opening_start.png`, `evidence/sightlines-headless/release-code-2e38d8f/` | **Rendered.** The opening frame shows the five-foot way, MBS (three towers and SkyPark, clear of the objective card), Supertree crowns, the Flyer, the hawker hall and a double-yellow left-hand kerb. The wave-4 opening (`rendered/baseline-w4-gameplay/`) was an indoor safe room. Critic: Supertrees read as magenta wireframe "cocktail glasses"; the Merlion is not recognizable; the sign is cropped to "EMBUSU" by a tree. |
| HUD | Ammo readout on a backing plate. The minimap draws the whole bay, the far shore, the MBS footprint and the promenade deck. Before, it drew a 30 m water strip, leaving the bay as bare background. | `859df8e`, critic review 5 | Fixes the two worst rendered defects the critic found. Rendered re-check: PENDING, see below. |
| Carjack and pedestrian safety | Soak #1 found a defect: the displaced driver of an occupied car stood frozen in the carriageway. Cars could not hurt pedestrians, so mission 2's car rammed an invulnerable body until wrecked. Now vehicles injure or scatter pedestrians (one impact per person per 0.6 s), and displaced drivers flee and rejoin a pavement. | `evidence/soak1-failed/`, regression checks | Fixed. Later soaks passed the same leg. |
| Parking and U-turns | Kerbside cars moved off the 16 cm platform edge onto the carriageway. Opposite lots are now staggered by 30 m, after soak #4 found an 11 m U-turn wedge. | `regressions_release_2e38d8f.json`, `evidence/soak4-failed-freeroam/` | **85/91 kerbside cars can pull out and drive 12 m**; 6 exceptions are listed in the check. |
| Traffic | Lane-corridor perception at about 8 Hz. Stuck recovery checks behind before reversing. | regressions | Critic: the rendered driving frame shows almost no traffic (`rendered/candidate-route/06_driving.png`). |
| Pursuit | Police follow the junction grid with committed waypoints and close on goals in the middle of a block. | regression checks, `headless-route11-pursuit/` | Headless: a responder closed from 167 m to a minimum of 69 m. No rendered pursuit was observed. |
| Performance | NPC/car simulation LOD, parked-car sleep, 150 m NPC draw range, static batching into MultiMesh (10,118 meshes → 1,107 draws by census). | `rendered/candidate-route/capture_log.json`, `perf_probe_release_2e38d8f.*`, `batching/census_release_2e38d8f.log` | **Rendered route (Metal, signed `d2a6cad`): p50 7.73 ms, p95 11.65 ms, p99 15.30 ms, max 1,063 ms.** The GPU was shared with one foreign Blender render and the CPU with this wave's headless runs, so the result is **not acceptance-valid**. There is one 1.06 s render-side hitch at 19.6 s (walking into the market; headless has none), not fixed. Headless CPU: physics about 11.3 → 5.1 ms. |
| Vehicles | Spinning and steering overlay wheels at the measured baked-tyre positions; seated drivers. | `wheel_probe.log`, rendered route `05`–`06` | Visible in the rendered car frames; not reviewed in motion. |
| Boundaries | The far shore is landable, but on-foot exit there is refused, and a downed pilot is recovered. Helicopter aerial envelope and ditch recovery. | regression checks | Headless only. |
| Audio | The engine and rotor loops are crossfaded at their seams; the siren loops on whole cycles; the gunshot uses soft saturation. | `regressions_94_audio.json` | Objective metrics only. **No listening test was done.** |
| QA tooling | Sightline probe, CPU probe, mesh census, wheel probe, two-process save/relaunch probe, gated render runner. The route automation backs out of long stalls and never presses interact far from the requested vehicle. | `evidence/`, `a53cd19`, `98b41b2` | — |
| Independent review | Fresh-context Opus critics: four code passes (21 findings), a documentation-accuracy pass, and **one review of the real renders** (21 images, pixel and luminance probes). | `evidence/critic_review_1..5*.md` | Still renders only; there was no human playtest. |

## Rendered evidence

All files are in `evidence/rendered/`; `evidence/rendered/README.md` gives identities, hashes and the builder's notes. They were captured at 02:49–02:54 UTC under the shared lease, with the render gate inside it. They are **not on an exclusive GPU** (one foreign Blender render ran throughout).

- **Unchanged wave-4 baseline** from a detached `6b51a26` worktree (byte-identical `game/` to `a5bf132`): 15 fixed views, including `photo_06_aerial_district.png`, the owner's requested camera (250, 95, 250), look (-40, 0, -60), FOV 62. Also 7 gameplay views, including the wave-4 opening.
- **Wave-5 candidate** (signed `d2a6cad` binary, executable `8cbba859…`, PCK `233a76c6…`): the same 16 fixed views and 7 gameplay views, plus the 11 screenshots of the rendered route.
- What the renders show:
  - Better than wave 4: the opening frame, the Supertree vista, and MBS proportions.
  - Worse than wave 4:
    - `photo_06_aerial_district` lost the Flyer and one Supertree cluster.
    - `photo_05_waterfront` is now an empty plaza.
  - Unchanged: the void deck, which is still about 70 % dark.
- Defects found in the renders:
  - Fixed in `859df8e`, with the rendered re-check PENDING:
    - The minimap was half black at the bay.
    - The ammo text was unreadable on bright backgrounds.
  - Open:
    - An empty world: almost no traffic.
    - A blown-out white glow beside the helicopter in the aerial frame. It is probably a sun glint on the bay water, which has roughness 0.4, but that is unproven.
    - Water that reads as paving in low waterfront shots.
    - Supertrees overlapping MBS.
    - Flat haze lighting.

## 30-minute soak attempts (`--capture --soak`: three missions, fixture phase, mixed free roam)

| Soak | Code | Result |
| --- | --- | --- |
| #1 | `2463cd3` | Aborted at 231.9 s, during mission 2's drive: the frozen carjack victim. Fixed. |
| #4 | `86b5405` | Three missions, all fixture checks and the same-car reboard all passed. Aborted at 819.4 s: a free-roam car wedged mid-U-turn. Fixed. |
| #6 | `584fb59` | Aborted at 1266.4 s: during a reboard, the automation carjacked a nearer passing AI car. Automation fixed. |
| #7 | `2e38d8f` | Aborted at 1590.6 s: an AI car waiting at a signal stayed nearer than the automation's own car. Automation fixed in `d2a6cad`. |
| #8 | `d2a6cad` | Missions 1 and 2 passed. **Aborted at 438.3 s** in mission 3: the scripted walk from the car to the helicopter stalled for 40 s against a car body. The per-frame stuck test never fired while sliding. The automation then pressed interact 55 m from the helicopter and took a nearby car instead. Automation fixed in `a53cd19` (`evidence/soak8-failed/`). |
| #9 | `a53cd19` | Missions 1 and 2 passed. **Aborted at 452.4 s**, a regression caused by the `a53cd19` fix. Its 2.5 s no-progress watchdog kept backing the player out of the hawker-hall edge at (-119, -52.7), a spot the old sidesteps clear in about 4 s, so mission 3's market walk timed out after 10 backouts. The trigger was changed to 12 s in `98b41b2` (`evidence/soak9-failed/`). |
| #10 | `98b41b2` | PENDING (running 03:02–03:34 UTC). |

Soaks #2, #3 and #5 were stopped early because newer fixes superseded them; they are not results.

## Release candidate

PENDING: the `98b41b2` package (HUD fixes plus automation) is being exported and verified. If it fails verification, the candidate stays `d2a6cad`.

- `d2a6cad1c948c5e32e0ee45924e7d5e325e73e5c`: verified fallback, kept in `package-wave05/d2a6cad/`.
  - SHA-256: signed zip `36c5132f…98eb2198d`, raw zip `04f21828…ff6b6`, PCK `233a76c6…ffc64`, signed executable `8cbba859…16548`.
  - Packaged, headless: 97/97 regressions, two-process save → relaunch → Continue, route 13/13 in 147.6 s.
  - Packaged, rendered (Metal): route 13/13 with 0 deaths in 149.1 s, opening and fixed views (`evidence/rendered/`).
- The signature is a local ad-hoc signature only, with no notarization. Provider asset rights for public redistribution are unverified.

## Not done / failing / untested

- **Fidelity:** GTA VI-level fidelity (ART-01..08) is not accepted. The landmark meshes are original low-poly forms; the MBS mesh has 4,564 triangles according to `game/assets/authored/landmarks_manifest.json`. Critic concept scores: 4/10 on foot, 2/10 driving, 3/10 helicopter.
- **Frame rate:** the rendered route p95 of 11.65 ms was measured on a shared GPU and CPU, so it is not an acceptance measurement (PERF-02 / QA-020). The 1.06 s hitch on entering the market is open.
- **Soak:** no 30-minute soak had completed at the time of writing (see the table).
- Not done: an ordinary OS-input human playtest, a listening test, a motion review, and public asset-rights clearance.
- **Incident:** at 00:55 UTC a save-probe run without `--qa-session` wrote the default user save slot once. The file was removed, and the probe now refuses to run without a task-owned path.
