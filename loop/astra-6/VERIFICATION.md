# Astra-6 enhancement verification

Candidate prepared on **25 October 2026** for the fixed **18:20:57–22:20:57 UTC** task. Implementation freezes at21:50:57 UTC. This document records completed checks, not a future completion claim. Branch: `Astra-6-enhancements`; baseline: `451c8eb17917452261b5262da96b8374ef060557`. Final game-code checkpoint: `e84bbc7`; later commits preserve documentation and evidence.

## What changed

The existing central Singapore district, bridges, landmark models and art direction are retained. This pass extends what the player can do there:

- Ambient traffic pool112→48, physical traffic14→7, and roadside parking97→51. All20 courtyard vehicles and3 starting road vehicles remain.
- Repeatable **Bayfront Courier** errand between Heritage Waterfront and MBS Event Plaza, with physical on-foot E handovers, cancellation, completion/repeat, a separate HUD marker/card and save/load persistence. It does not replace Harbour Relay.
- Visible, collidable pedestrian ramps repair the heritage promenade curb, MBS north promenade, Jubilee-to-Fullerton landing and Fullerton-to-heritage join. The tested roundtrip needs no jump.
- A signed public MBS lift, accessible SkyPark terrace, return lift, safety screens, seating/wayfinding, three existing NPC visitors and a small helicopter landing/exit zone. Visitor movement is separated from the aircraft area; damage and native ragdolls remain enabled.
- Fresh critiques drove smaller courier labels, removal of redundant near-target markers, readable lift signs and better terrace scale cues. An optional paving change was rejected after blind comparison and removed.

## Delivered build identity

- Native universal macOS Godot4.7.1 Forward+ package; no engine migration.
- Archive: `OrchardReach-Astra-6-enhancements.zip`.
- Bytes: **881,511,448**.
- SHA256: `36dfc8d695acdaabed69ddaaad3df1c23eed0b41b17ed07e926be3d168c55bc7`.
- Local ad-hoc signing passed strict verification. Signing did not change the PCK. This is not Developer ID notarization or a public release.
- Existing private art is retained in the authoring checkout. `private-assets.json` records276 files /1,447,115,773 bytes. No new paid generation or credit purchase was made.

## Completed functional evidence

| Check | Result | Scope and limitations |
|---|---|---|
| Final packaged core suite | **296/296, exit0, zero fatal errors** | Headless behavioral/fixture checks. GPU-only output/shader-sharing checks explicitly not exercised. `evidence/package-r3/headless-report.json` |
| Packaged UI save/relaunch | **24 write +23 load checks, both exit0** | Two different rendered package processes, title/New Game/pause/settings/save/Continue. Fixture-assisted, not human acceptance. `evidence/package-r3/ui/` |
| Full new courier journey | **44/44 rendered, exit0, zero fatal errors** | Normal spawn,3679.09m,602.90s, zero jumps/deaths/teleport steps. Six real player-camera images. This preceded the final label-size change; the final label/marker change passed a separate25-check rendered dispatch review. `evidence/rendered-courier-r2/` |
| Final dispatch presentation | **25/25 rendered, exit0** | Explicit local8m start fixture, actual walk/E input and two images; `journey_completed=false`. This is not a second full journey. `evidence/rendered-dispatch-r3/` |
| Car/helicopter courier handovers | **38/38 source headless** | Actual E boarding/exits, short native car motion, native helicopter set-down, seated handover rejection and save/load. Initial placements/relocations are explicit fixtures. The stock release template disallows direct scene overrides; no bypass was used. |
| Downtown driving | Route completed in**376.2s**, zero tows | Actual controls,72.2s waiting, one overtake and two controls-based unsticks. Overall runner exit2 due a capture-index shutdown race; preserved as a failed run, not relabeled clean. The QA writer was corrected and later flight/views shut down cleanly. `evidence/rendered-drive-r1/` |
| Downtown flight | **Landed, exited and walked; exit0** | Actual controls from aviation pad to NS Square; initial pilot boarding position is a fixture. Later fixed viewpoints are appearance evidence. `evidence/rendered-flight-views-r2/` |
| SkyPark access/flight | Most checks pass; **140/142 overall, exit1** | Lift, supported exits at8 headings/8 boundary points, outside-zone refusal, actual local flight/landing/E exit, death recovery, fresh-scene rooftop save/load and live NPC reactions passed. Two native ragdoll gates remain failed; see below. `evidence/rendered-skypark-r4/` |
| Native keyboard smoke | New Game, walking, F5, sedan entry/drive/brake/exit observed | Final packaged app through macOS input, isolated QA save. Ground-level walking after exit is saved. Sprint engagement/animation feel was not established by the CUA modifier chord. First480s bounded session ended by supervisor, not a clean user quit. |
| Native packaged SkyPark | Continue, E down/up, walking/railing, F5/F12, normal quit | Started from an explicitly copied rooftop QA save. Native F12 screenshots record roof199.98m, ground1.47m, roof again and movement along terrace. Normal Command-Q produced exit0, zero fatal errors. Not a full native journey from heritage. |

The single-run headless driving comparison was445.4s/91.5s waiting before, versus314.0s/19.2s waiting after, with zero tows in both and one candidate unstick. This is a controlled automation comparison, not a human-feel or graphics-performance benchmark.

## Failed and unresolved gates

1. **Native ragdoll solver stability and bone-floor support remain failed.** This fallback also occurred in the preexisting ground-level tests. A rendered rooftop run additionally crossed the9m aircraft-clearance criterion at8.760m. The actual visitor area was moved2m farther from the pad; the unchanged criterion subsequently passed at12.008m in rendered R4. The two solver/floor gates still fail. Post-fallback bone nodes and the visible skeletal pose can differ; bone data alone is not proof of visible-mesh penetration. No global ragdoll rewrite or relaxed threshold was used.
2. **The30-minute mixed workload did not pass.** It completed three Harbour Relay missions with zero deaths and passed its pause/save/malformed-save/route-bypass fixtures, then missed the free-driving destination at657.7s. Runtime error scanning was active and found no fatal errors. The original gates and130s driving limit were retained. `evidence/soak-r2/` preserves the failure. An earlier invocation stopped at30s because the manager omitted the required QA-log argument; that operator error is separately preserved.
3. **Rendered core-suite completion/performance remains open.** The R2 packaged rendered suite hit its90-second watchdog after97 passing checks and one watchdog failure. The final headless296-check pass does not replace that failed rendered result. All renders shared the Studio with another owner's engine, so timing is contaminated and no exclusive60fps claim is made.
4. **Seven Texture RID shutdown warnings** recur after scene teardown, including normally quitting native gameplay. They are preserved. No crash was observed, but this is not a memory-leak clearance.
5. Human judgement of animation quality, handling, difficulty, sound and overall fidelity remains open. The game is not certified as a one-to-one GTA-quality recreation. Repetitive office glazing and some overbright canopy materials are still visible.

## Images and provenance

Only real engine renders are used. The gallery distinguishes native packaged input, controls-based gameplay validation, and final-build fixed-camera views. The29 fixed views render at1920×1080 then use the existing capture routine's1280×720 save size. They hide HUD and nearby camera-obstructing traffic, so they are appearance evidence, not traffic-density or traversal proof. No geometric diagnostic or generated concept image is presented as gameplay. Casualty diagnostics remain in explicitly named evidence subfolders and are excluded from the gallery.

## Operational notes

All rendered jobs used the shared GPU lease, last-moment cap check and a private one-at-a-time lock. No foreign engine was stopped. The first native-input session's CUA binding relaunched the task app after its bounded stop; the unexpected owned process was identified and terminated, and the binding reset. The normal user save's modification time remained22 October, before this task; no default-save write was observed. The later native rooftop session quit normally before its bound.

Four temporary task worktrees were removed after clean pushed branches and integration were verified. The main authoring checkout and needed private assets remain. No main merge, public build release or extra wave is authorized by this task.

### Delivery filesystem check

The delivered ZIP was extracted into task-local temporary storage and its enclosed app passed strict code-signature verification; its PCK matched the tested package. Delivery is ZIP-only. A direct app copy in the cloud-managed Documents folder repeatedly acquired FinderInfo metadata from File Provider, so that disposable copy was removed after verifying its file bytes matched the signing inventory. No quarantine/provenance/security attributes or File Provider settings were changed.
