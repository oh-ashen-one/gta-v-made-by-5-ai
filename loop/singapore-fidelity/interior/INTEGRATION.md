# MBS public L1 stage — continuous-envelope revision R2

This remains an **unfinished stage toward the entire requested MBS interior**. It is not hooked into main or the current city. R1 passed the parent's standalone headless test (reported 25/25, 90.081 seconds, 494.366 m), but that result predates this geometry and does not verify R2. This worker launched no engines or GPU jobs. R2 compile, collision, rendered fidelity, performance and world integration require fresh parent verification.

## Source correction

Arup's original engineering publication, *The Arup Journal 1/2012*, printed pages 21–23, describes a **single connected atrium**, descending northward from about 20 storeys at T1 to six at T3, and approximate widths of 40/20/10 m at T1/T2/T3. Its glazed linking walls follow the towers; the west side is vertical and the east side inclined, with wall/roof trusses and horizontal transoms. Historical intertower vertical wall spans are 47 m maximum (T1–T2) and 27 m minimum (T2–T3).

Primary source: https://www.arup.com/globalassets/downloads/arup-journal/the-arup-journal-2012-issue-1.pdf . Text was verified online. The screenshot tool exposed references without diagram pixels and the public PDF download returned 403; **diagram dimensions were not visually inspected or extracted**. No source PDF/page art was copied into the repository. The 2012 original engineering report does not establish current refurbished room inventory, fit-out or precise entry metrics.

R2 removes the three separate low vaulted rooms and six-metre tunnel connectors. One continuous, tapering shell now passes through the actual uncompressed source tower centroids. Adjacent floor/wall/roof segments share identical cross-section vertices. The side glazing has staged trusses/transoms and one inclined upper side. Broad tower areas and intertower glass roof spans are continuous; these exact roof/material divisions remain provisional.

**The metric roof profile is unresolved.** Defaults T3=27, T2=47, T1=76 m are explicit staging values, not a surveyed conversion of six/twenty storeys. The numerical 27/47 intertower wall spans remain separate historical facts and are not claimed to establish those tower roof elevations. Exact longitudinal extents, centre-to-interior alignment, inclination, structural member spacing, entrance, floor elevation, roof divisions, furniture and lighting are also assumptions. Replace them from licensed current plans; do not label these generated coordinates as an as-built section.

## API and error contract

- `site_reference.gd`: exact OSM source identity/footprints/centroids plus separate historical engineering metadata.
- `public_l1.gd`: add a new instance to the scene tree, then call `build(config={})`.
- `walking_route_world(true)`, `doorway_world()`, `join_probes_local()` and `report()` expose verification data.
- A complete temporary value-only plan is validated **before any transform, array, child or collision mutation**. A failed configuration may be retried on the same instance. A successful instance refuses another build without duplication.
- Source placement is **absolute global placement**, so translated/rotated unit parents are supported. Compressed parents are rejected. One metre remains one world unit.

Config fields: `entrance_tower`, `entrance_side` (`bayward`/`landward`), `entrance_along_offset_m`, `floor_elevation_m`, `entrance_width_m`, `entrance_height_m`, `east_upper_wall_inset_ratio`, and `atrium_dimensions` keyed T3/T2/T1 (`length_m`, `width_m`, `roof_height_m`; older `wall_height_m` is accepted as a provisional-height alias). `corridor_width_m` is a minimum clear-width validation constraint, **not** a command to insert narrow tunnels. Invalid/nonfinite dimensions, incompatible opening widths/heights and non-rising northern-to-southern height profiles are rejected before mutation.

## Parent verification

```sh
bash loop/singapore-fidelity/run_engine.sh mbs-public-l1-r2 300 \
  /private/tmp/singapore-fidelity/mbs-public-l1-r2 -- \
  --headless res://src/systems/fidelity_tests/mbs_interior_public.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/mbs-public-l1-r2/session
```

For a parent-owned rendered run, omit `--headless` and add `--mbs-interior-stills-dir=/private/tmp/singapore-fidelity/mbs-public-l1-r2/stills` after the user separator. The test is explicitly a translated standalone controller fixture after absolute site-placement checks, not a walk from the heritage district. It checks invalid-build retry, finite trillion-metre length/width/height rejection followed by a valid retry, transformed-parent source placement, every join's two side-edge capsule sweeps, sampled edge floor support, clear starting capsules, blocked outward capsule escape and ray slits, whole-capsule entry clearance, continuous high intertower ceilings, then actual production-Player traversal and return without teleports or jumping. Fresh runtime evidence is required.

## Remaining integration and full-goal gaps

1. Replace corresponding old **solid** tower/podium collision with complete hollow floor/wall shells; do not insert this inside solids or indiscriminately remove supporting collision.
2. Migrate the entire complex/source map consistently, with Bayfront Avenue separating hotel and retail. Preserve exterior quality; do not leave a second MBS in the old fictional frame.
3. Update player, aircraft, streaming and saved-position bounds together; current legacy bounds motivate the explicitly translated standalone fixture.
4. Obtain current licensed plans for every guest floor, room/suite, lift/stair/core, service area, Paiza, public north/T3 deck, pool/roof program and retail/basement/underground link. This module builds none of those inventories and always keeps `full_requested_interior_verified=false`.
5. Verify normal city-to-interior walking/driving/flight, save/relaunch, combat, collisions and source-based visual fidelity in the integrated world. This stage is not whole-world acceptance.

Source-first research checked Fab, NVIDIA SimReady, ThreeJS Assets and Poly Haven in `research/mbs/asset-candidates.json`; no suitably licensed/acquired exact MBS interior model was established. R2 reuses original project Kit/Realm/materials. No new asset purchase, download, upload, custom animation or generated image was made by this worker.

## R2 engineering critique corrections

Capsule queries now reuse the **actual production Player capsule resource and local transform**. The Player is added with processing disabled before source-plan setup, hidden, and removed from collision layers until continuous walking starts. A runtime contract assertion verifies radius 0.36 m, total height 1.75 m, local center (0, 0.90, 0), the production collision mask, and a query margin at least as strict as `CharacterBody3D.safe_margin` (minimum existing query margin 0.01 m). Physical checks do not use a smaller proxy. The same Player is then re-enabled for traversal.

The supported configuration domain is explicit: per-zone longitudinal extent ≤1,000 m, width ≤500 m, roof height ≤300 m; combined longitudinal span ≤2,000 m; absolute reference floor elevation ≤1,000 m; structural-member budget ≤16,000. These generous software-construction bounds exceed this source site's scale and are **not** architectural measurements. A float-only member estimate counts the side truss/transom and roof construction loops conservatively before any conversion to integer iteration counts. Invalid or oversized configuration is rejected before state, transform or child mutation. The regression tries finite `1e12` length, width and roof-height inputs on the same unbuilt instance, then a valid build; it checks no failed attempt creates arrays, nodes or duplicate geometry.

These changes are source-only. The new exact-collider/budget tests and revised geometry still await parent compile/runtime/render verification.

## Parent source review checkpoint

A fresh independent critic re-reviewed the continuous envelope and the follow-up fixes. It found no remaining source-level P1/P2 in transactional planning, absolute placement, shared loft joins, exact production-capsule use/lifecycle or bounded construction. This is code-only approval. Parsing, collision behaviour, actual walking and rendered appearance are still pending; the earlier25/25 is only the supersededR1shell. Full room inventory and normal source-coordinate city entry remain incomplete.
