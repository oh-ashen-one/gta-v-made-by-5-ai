# Wave 2 — active Gauntlet record

Owner: GPT-6 Astra through Codex. Shared branch feature/wave-02-astra, incoming 4df93fa631d9484fb29e556a97df61a259620248. Fixed UTC window 2026-10-21 11:38:01–15:38:01; final validation starts by 15:08:01. Current session model and inherited settings are used; no different-model/effort access is claimed. Shared rules revision ba35669bd13c was injected as refreshed before launch.

## Ownership

- Root: integration, world/materials/lighting, player, HUD, provenance/ledger, engine scheduling, commits/push.
- mission_integrity (Astra): mission/core state, capture/self-test, NPC/vehicle gameplay, traffic manager.
- character_rig (Astra): character rigging source and new CharacterVisual controller; no shared actor integration until root.
- baseline_critic (fresh-context Astra): baseline review completed. Subsequently reassigned as foliage/pavilion builder, and must not independently approve its own work.

All workers share this checkout with exclusive file/function ownership. No worker starts a Godot renderer; root owns shared GPU scheduling. CPU-only Blender 4.5.11 operations are bounded and task-owned. Default Blender 5.2 under sandbox crashed before Python while probing Metal; one controlled 4.5.11 escalated run succeeded. No local inference, new paid jobs, main merge or public release.

## Priorities reassessment

The predecessor's art-first priority is retained, with a parallel integrity lane because a death/respawn bypass is not a mission completion. Baseline critic identifies materials/lighting, sparse urban density, then actor integration as the biggest gaps. Unverified rights remain unverified.

## Iterations

- Baseline: inherited wave-one PNGs compared by a fresh-context same-model critic against the three actual concepts; scores in critic-baseline.md. REWORK, not north-star acceptance.
- R1: real Godot 4.7.1 Forward+ Metal capture at 1280×720; eight fixed cameras, original filenames; process exited 0 after 6.43s. PBR world-space mapping removes stretched ground bands; lower sun/ambient exposure recovers material separation. Empty ground and placeholder foliage remain major defects. See r1/ and r1-render.log. Capture uses shared slot; no performance claim from this run.

## Safety and reproducibility

Verified machine Apple M3 Ultra. Live shared coordinator /Users/midir/sm2-n1/_scratch/gpu; no foreign renderer at first launch. One owned renderer per capture, native quit, slot release observed. Bounded helper sends SIGTERM on timeout then waits up to 60s before force kill. Imports/headless tests need explicit writable --log-file under sandbox. Provider binaries remain ignored and manager-carried; original DCC scripts and owned texture sources are committed.

R2/R3: authored foliage and terracotta pavilion integrated and captured in real Godot. R2 fresh-context critic scores geometry4/material3/light3.5/density2.5/identity4, all below AAA8. R3 rotates measured +X shophouse facades toward the street, adds perimeter fronts and simplified envelope collision, replaces featureless sky with original static cloud shader and reduces haze. Nine captures completed, exit0/6.69s. Random inherited trees on carriageways were removed after truthful headless route failure at a newly collidable trunk; this is a regression fixed for retest, not a passed route. The first route failure is retained by the mission lane.

R6: skinned player/NPC integration, updated original foliage, pitched pavilion, populated hall, skyline and interiors captured. Fresh context critic gives3.8/10 overall, Singapore identity5.0, density2.5, REWORK. Moved hall to the road edge, denser tables and shop reposition follow its specific density/blank-wall findings; next capture pending. Gameplay critic native-event probes closed title movement/F9 restart/save-mutation/interaction-wall findings, then exposed pause→settings state loss and disabled-car prompt eligibility; fixes are implemented for retest. Exact waterfront exit regression identified vehicle inheriting passenger as moving-platform velocity; world-only vehicle platform layers and immediate passenger collision disable pass75checks. Current full renderer route records10Hz requested JPEG samples with real timestamps; initial interval until12:45:03UTC overlaps one bounded headless route and is not isolated performance evidence. Godot computer-use surface was denied; no OS UI automation is claimed.

Validation correction:85/85 assertions in an earlier headless report did not mean an error-free run. The genericERROR-aware supervisor found freed HUD toast lambda captures; those are fixed with WeakRef. Metal regression first84/85 exposed title-overlay consumption of the quick-click fixture; test mode now enters active gameplay before injecting input. The unchanged quick-click assertion and allother85 checks pass in regressions-rendered-r2, nativeexit0/reaped20.98s, no errors. Dummy-only material diagnostic remains explicit. Soak source independently re-reviewed: fixed1800s acceptance floor,3true mission completions, final healthy/livefoot control and reboard/landing gates; no30mincontinuousmovie claim.
