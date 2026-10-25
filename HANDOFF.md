# Astra-6 enhancements — IN PROGRESS

Owner: current Codex session with explicitly authorized builder/critic subagents. Branch `Astra-6-enhancements`, baseline main451c8eb. Fixed 2026-10-25 18:20:57–22:20:57 UTC; final30min21:50:57. No main merge or extension. Scope/clock in loop/astra-6/TASK.md and RUN.json.

## Implemented and verified so far (20:30 UTC)
- Traffic: ambient112→48, physics14→7, roadside parking97→51; all20courtyard+3opening cars preserved. Actual spawned-car and camera-cut recycling tests. Same unmodified headless drive: baseline445.4s/91.5waiting/0tows versus candidate314.0s/19.2waiting/0tows, with one controls-based unstick. Single-run comparison; not human-feel or graphics/performance acceptance. Sustained junction review still observed box/zebra stops.
- Bayfront Courier: repeatable physical E activity between heritage waterfront and MBS Event Plaza, independent of Harbour Relay. Own HUD/card and marker; atomic optional save schema, legacy reset, actual New Game and death checks. Normal-spawn full controls-based outward/return route31/31:3683.21m,603.65s,zero jumps/deaths/teleport steps. Final save idle/completed_runs1; original story stage/checkpoint unchanged. Optional real screenshot support now integrated; rendered full route queued, no fake headless images.
- Physical walking seams: five heritage avenue→promenade ramps; MBS north promenade ramp; Jubilee→Fullerton and Fullerton→heritage joins. Visible surfaces and matching collision ramps repair actual controller failures; traversal tests did not bypass lips.
- MBS SkyPark: explicit public lift transition, guarded roof terrace, dedicated2.5m helicopter exit zone, return lift and ground death recovery. Production setup hook required. Headless and actual Metal rendered suites116/116, including8center headings+8boundary exits,4outside refusals, saved rooftop fresh-scene restore, actual death/recovery, controls-based flight from an explicit airborne fixture/landing/Eexit/return. This is not a continuous heritage-to-roof flight claim.
- Core integrated suite296/296 headless; original Harbour Relay13gates/0deaths/158.8s. Final combined suite and packaged checks still pending latest polish.

## Actual visual evidence and critique
- Baseline29fixed views in loop/astra-6/evidence/baseline-views. CityR1 views are an intermediate iteration: optional granite paving was rejected after blind A/B preferred baseline, then removed in ebb036a. Do not label those intermediate materials final.
- SkyPark actual four PNGs and rendered116-check log in evidence/skypark-rendered-r1. Critic found sign/lightstrip overlap, deliberate negative-test toast lingering in positive-arrival still, and empty terrace scale cues. Builder is correcting these with readable signage, normal toast expiry and bounded existing-NPC visitors/wayfinding; rerun pending.
- Seven Texture RID warnings occurred only at rendered test shutdown after full scene teardown/rebuild; preserve this limitation. No fatal error, no memory-leak acceptance claim.
- Shared GPU occupied by other owners; all our captures use shared lease and are contaminated for performance. No60fps/exclusive GPU claim. Only actual rendered gameplay images are progress evidence.

## Ownership and pending work
- traffic_builder / siblingastra6-traffic, branchAstra-6/traffic: completed and integrateda50fff4.
- downtown_builder / siblingastra6-activities, branchAstra-6/downtown-activities: fullroute5d7a309 and optional screenshot9289e57 integrated. No production source changes pending.
- landmark_access_builder / siblingastra6-landmark-access, branchAstra-6/landmark-access:953d3ce+a553da0 integrated; small visual-critic polish underway. Parent owns renderer.
- Parent owns main/coreGame/player/HUD/sharedworld hooks and integration; new read-only courier critic checking final integration. Do not duplicate live agents.
- Current root rendered drive exec95844 (/private/tmp/astra6/render-drive-r1); courier exec32507 waiting on private one-at-a-time lock (/private/tmp/astra6/render-courier-r1). Inspect identity/state before interacting.

## Finish within fixed window
Finish current rendered traffic/courier evidence, integrate and revalidate SkyPark polish, fresh visual critique, full regression and package/save/load/captures. Freeze implementation21:50:57; hard end22:20:57. Preserve/push all task source, actual evidence and private build; report remaining failures/untested gates honestly. No new paid generation.

## Resource safety
Use loop/astra-6/render.sh: private one-at-a-time lock, shared GPU_SLOT_DIR=/Users/midir/.cache/gpu-slot, native shared lease, render_gate, fixed-deadline guard and bounded_run. One task renderer; globalmixedcap2. Do not touch foreign Invincible/Bully/Veyr instances/locks. All QA uses explicit isolated --qa-session. Stop own drivers before engines, TERM/up to60s grace. Remove only task temporary worktrees after preserving pushed work/private assets; keep main authoring checkout.

## 20:58 UTC verification update
All builder changes integrated, parent source aa3277b plus orchestration/docs. Packaged R2 core296/296 passed, strict ad-hoc signature valid, zero fatalerrors. GPU-only checks explicitly not exercised. Dedicated packaged scene override refused by stock template; no bypass, vehicle38checks remain source-only. Stronger SkyPark combat140/142 exposes preexisting native ragdoll solver fallback; live NPCdamage and aircraft clearance pass. Bone-node/physics and visible skeleton differ afterfallback; no unverified visible-mesh penetration claim. Preserve detailed combat-verification.json.

Veyr editor2904 + ownerInvincible93277 occupy GPU cap2. No ownengine currentlyrendering. Failed courier attempt launched noengine; remaining ownqueuedSkyPark/flight driversstopped. Bounded waiter36806/session45112 waits normalcapacity until21:50:57 then uses unchanged lease/gate/deadline helper for courierR2. State /private/tmp/astra6/courier-waiter.json. Do notduplicate; inspectbeforelaunchinganyadditionalrenderer. Corrected headless30minute workload session32774 running /private/tmp/astra6/soak-r2; pending. Firstinvocation lackedrequiredqa-engine-log andaborted30seconds, preserved. Taskdeadlineunchanged22:20:57.
