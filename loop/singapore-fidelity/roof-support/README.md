# Ordinary-roof structural support repair

This piece repairs collision mismatches in the existing compressed district. It does not certify real Singapore placement, as-built MBS architecture, every visible background tower, human input or performance. No external model, texture, animation, provider job or purchase was needed: the correct source is each existing original rendered structural primitive. The source-first catalog was consulted; replacing these exact shapes with an unrelated licensed mesh would not repair the mismatch.

## Changes

- MBS SkyPark now derives a closed structural hull/deck collision shell from the same 45 rendered rings and caps. The old rectangular collider is removed, including its support outside the tapered hull. The pool's stone base is structural; liquid, planting, leaves and decorative members are not solidified.
- The three pavilion bodies and roof slabs have matching boxes at the unchanged visible dimensions/transforms. Their roof top is 204.4 m.
- Shoppes canopy support matches its rendered box. The wave roof/glazed front support uses its existing tessellated arc points; the sampled high-bay crest is 24.786058 m, not the old 16 m body top.
- The airfield hangar roof uses its PrismMesh's own convex geometry at the same transform. The earlier box body remains; officer anchors and the rest of aviation construction are unchanged.
- RoofKit emits membrane, parapet, housing and substantial solid roof-plant collision from its existing instance transforms. Box dimensions carry scale rather than nonuniform collision-node scaling; polygonal tanks/cooling units reuse their rendered mesh vertices. Thin fan grilles/solar panels, narrow masts/vents, doors and foliage do not become landing platforms.
- One Fullerton dining roof slabs match their visible roof/eaves. The main hotel no longer uses a full-footprint collider all the way to the smaller upper roof: lower and upper rendered masses are split. Matching plinth, column, cornice, entrance and lantern structures preserve those visible barriers/supports. No rendered primitive/material was changed.

## Fullerton stepped bounds

For the current 80 × 85 m hotel plan, the former 33.36 m-high box covered relative X[-40,40],Z[-42.5,42.5]. The actual lower main mass is X[-37,40],Z[-39.5,42.5], top27.36; upper mass is X[-35,38],Z[-37.5,40.5], top33.36. Facade plinth/cornice/portico supports match their separately rendered boxes. A probe at relative(38.7,30) must find the lower terrace, with empty air fromY34.36 down to28.36; it must not find the old upper box.

## Parent-owned verification

No engine, GPU, UI or Git action was performed by the builder. `SOURCE_REPAIR.json` binds the source hashes and static arithmetic; it is not a runtime pass.

```sh
bash loop/singapore-fidelity/run_engine.sh roof-support-headless-r1 420 \
  /private/tmp/singapore-fidelity/roof-support-r1 -- \
  --headless res://src/systems/fidelity_tests/roof_support_review.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/roof-support-r1/session \
  --roof-support-output=/private/tmp/singapore-fidelity/roof-support-r1/review
```

The dedicated scene instantiates the actual production main world once, validates known positive roof heights and negative hull/upper-terrace air, checks actual RoofKit membrane/housing instance support, and chooses a clear real membrane fixture. It reuses the actual Player and Helicopter collision resources. Each landing case begins with explicitly disclosed unoccupied actor placements; descent, touchdown, E exit and walking then use normal production physics/input. A landing on a lower floor, death/respawn, or walking off to ground cannot pass. There is no arrival-threshold reduction or collider disabling. It is not an end-to-end flown route.

For a rendered run, omit `--headless`, use a fresh run prefix, retain the shared coordinator/gate/cap, and optionally position the window offscreen as the root's normal capture protocol requires. Actual landed/walking frames are saved for each case; they remain fixture-assisted real-game evidence, not user-facing finished-city images. R1 parsed and ran without fatal errors: 74 checks, exit 1, seven named native actor landing/exit/walk cases passed. RoofKit checks failed (0/247 deck and 0/247 housing centres, so no membrane actor case). R1 did not record per-instance readback/ray detail. R2 preserves CPU render-submission receipts because the headless dummy renderer cannot provide useful MultiMesh buffer readback; it adds strict native collider-vs-render transform checks, complete ray/shape diagnostics and fixture-search rejection details. Rendered runs must additionally compare the actual renderer buffer with the CPU receipt. No actor/height/clearance tolerances were loosened and no collision geometry changed for R2. R2 physics and actual rendered roof contacts/performance remain pending.

Known scope gap: far/background SkylineCity geometry uses visual MultiMeshes. Reachable-area support/streaming must be audited before claiming every visible roof is landable. The corrected cases do not replace that larger world-migration work.


## Separate downtown roof family extension

Independent review found a second reachable family in `game/src/world/downtown/roofs.gd`: `DowntownRoof_*` MMIs. The earlier RoofKit proof does not cover this family. The actual earlier R2 was85/85 headless and R3 was103/103 rendered, with247 membrane and247 housing support probes and zero rendered transform error. Their reports/hashes remain separately bound in `SOURCE_REPAIR.json`.

The downtown extension now pairs each existing render submission with an explicit structural role. Membranes retain their exact0.12m slab; penthouses retain the exact5–8m by4–6m body and0.3m roof cap; substantial plant, tanks/cooling, solid duct/skylight and planter bases match their unchanged primitive dimensions. A material alone does not select collision: thin fan discs share `plant_dark` with penthouse caps and intentionally remain non-solid, as do solar panels and foliage. Existing RNG calls/order, materials, render grouping, per-cell instance order, shadow/visibility settings and shrub emission are preserved.

Each batch retains the CPU transforms submitted to its MMI; its identity child static body carries exact box dimensions or a hull of the visible12-sided cylinder vertices. The extended actual-world scene checks every structural top with native rays, height/normal/shape-owner identity, collider-vs-render corner or vertex agreement, complete role/transform receipts, and no collider for excluded thin dressing. Rendered runs additionally require real MMI buffer agreement. Negative probes remain above the legitimate lower body and just outside selected membrane/cap edges. Two more actor cases select clear production membrane and penthouse-cap spots with the actual helicopter/capsule resources, then use the unchanged native descent, E-exit, supported>2m walking, health and height gates. Fixture placements are explicit; the cap heading changes to fit its actual roof, without enlarging it.

This extension is SOURCE-FROZEN, NOT RUNTIME-VERIFIED. Root must run the scene using fresh prefixes, for example `roof-support-downtown-r1` (same command above with all run/output paths changed), then a normal rendered run and independent frame review. Previous103 checks cannot be relabeled as this extension's result. Background-only SkylineCity surfaces and whole-city/source-geography remain outside this roof-family repair.

DowntownR1 failed parsing before tests at review line425: a compound predicate containing dynamic `Dictionary.get("collider")` could not infer `ok`. The local now has explicit `bool` typing; the other newly introduced inferred locals were checked for untyped Variant sources. No production geometry, identity predicate, tolerance or actor criterion changed. The failed run remains under `/private/tmp/singapore-fidelity/roof-support-downtown-r1`; root must use a fresh prefix. This correction itself is not a parser/runtime pass.

## Root downtown extension runtime

Headless downtownR2 passed107checks. RenderedR3 exposed an eight-second wall-clock cutoff during gentle hangar descent, stopping healthy0.6mabove contact; it remains retained. Root changed the QA wait to8actual physics-simulationseconds with a separate24secondwallguard, preserving actual landed/height/health/E/walk gates and recording both clocks. RenderedR4 passed130/130, exit0/noengineerrors, childreaped. NewdowntownMMI buffers agree withCPUreceipts at0cornererror. This still doesnotcertifyfarbackground/wholecity/humaninput/performance.
