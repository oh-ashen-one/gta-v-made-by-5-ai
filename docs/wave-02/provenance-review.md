# Wave-2 provenance review

Recorded UTC: 2026-10-21T12:44:12Z

Scope: local evidence audit by the delegated GPT-6 Astra provenance lane. Owned files: `docs/asset-manifest.csv`, `docs/ASSET_RIGHTS.md`, and this review. No models regenerated; no engine launched; no legal pages browsed; no account action, publication, commit, or merge performed by this lane. Root remains responsible for integration and branch publication.

## Evidence coverage

All eighteen pairs in `docs/wave-02/assets/*_0.png` / `*_1.png` were inspected through `view_image`: contact sheets for triage, then all 36 original 1280×720 files. The generated packaging atlas was also inspected directly. This review concerns the supplied captures of cleaned meshes, not full texture sheets, all hidden faces, or comprehensive views of the seven final derivatives. Current file hashes bind the inventory snapshot; the captures were not cryptographically bound to the GLBs at rendering time.

| Source ID | Cleaned asset | Limited observation | Evidence |
| --- | --- | --- | --- |
| W1-HERO-001 | `sedan_clean.glb` | **Observed/ambiguous mark.** Oval/ring badge-like shapes on front grille and trunk; earlier wave-1 no-marks claim withdrawn. Identity unresolved. | [0](assets/sedan_clean_0.png) / [1](assets/sedan_clean_1.png) |
| W1-HERO-002 | `coupe_clean.glb` | **Observed/ambiguous mark.** Small yellow/gold nose and rear badge-like marks; plate-like lettering too small to resolve. Identity unresolved. | [0](assets/coupe_clean_0.png) / [1](assets/coupe_clean_1.png) |
| W1-HERO-003 | `van_clean.glb` | **Observed/ambiguous mark.** Large red/blue emblems, repeated cab/front/rear motifs and pseudo-lettering across body. Identity unresolved. | [0](assets/van_clean_0.png) / [1](assets/van_clean_1.png) |
| W1-HERO-004 | `helicopter_clean.glb` | **No obvious mark in limited views.** No obvious logo or text identified in these two views; small fittings and hidden faces remain unreviewed. | [0](assets/helicopter_clean_0.png) / [1](assets/helicopter_clean_1.png) |
| W1-HERO-005 | `player_clean.glb` | **Observed/ambiguous mark.** N-like contrasting side marks visible on sneakers; no trademark identity determination. Clean mesh remains marked. | [0](assets/player_clean_0.png) / [1](assets/player_clean_1.png) |
| W1-HERO-006 | `officer_clean.glb` | **Observed/ambiguous mark.** Visible cap crest, chest badge/name-strip and shoulder/collar insignia. Identity and any real-force resemblance unresolved. | [0](assets/officer_clean_0.png) / [1](assets/officer_clean_1.png) |
| W1-HERO-007 | `shophouse_clean.glb` | **No obvious mark in limited views.** No obvious logo or readable commercial sign identified; unobserved interior/underside surfaces remain unreviewed. | [0](assets/shophouse_clean_0.png) / [1](assets/shophouse_clean_1.png) |
| W1-HERO-008 | `hdb_slab_clean.glb` | **No obvious mark in limited views.** No obvious logo or readable text identified; small facade details and hidden surfaces remain unreviewed. | [0](assets/hdb_slab_clean_0.png) / [1](assets/hdb_slab_clean_1.png) |
| W1-HERO-009 | `hawker_counter_clean.glb` | **No obvious mark in limited views.** Blank-looking sign panel and striped canopy; no obvious mark identified. Shading/geometry artifacts obscure small surfaces. | [0](assets/hawker_counter_clean_0.png) / [1](assets/hawker_counter_clean_1.png) |
| W1-PROP-010 | `hawker_table_clean.glb` | **No obvious mark in limited views.** No obvious logo or text identified on visible table/stools; underside hidden and substantial surface artifacts present. | [0](assets/hawker_table_clean_0.png) / [1](assets/hawker_table_clean_1.png) |
| W1-PROP-011 | `food_trolley_clean.glb` | **No obvious mark in limited views.** No obvious logo or text identified; very dark broken-looking material/geometry limits small-detail review. | [0](assets/food_trolley_clean_0.png) / [1](assets/food_trolley_clean_1.png) |
| W1-PROP-012 | `ac_unit_clean.glb` | **No obvious mark in limited views.** No obvious readable brand identified; severe triangular surface artifacts and bright panels limit review. | [0](assets/ac_unit_clean_0.png) / [1](assets/ac_unit_clean_1.png) |
| W1-PROP-013 | `street_lamp_clean.glb` | **No obvious mark in limited views.** No obvious logo or text identified; small dark surface details and undersides remain unreviewed. | [0](assets/street_lamp_clean_0.png) / [1](assets/street_lamp_clean_1.png) |
| W1-PROP-014 | `service_clutter_clean.glb` | **No obvious mark in limited views.** No obvious readable logo or text identified on bins; broken-looking surfaces limit review. | [0](assets/service_clutter_clean_0.png) / [1](assets/service_clutter_clean_1.png) |
| W1-PROP-015 | `planter_clean.glb` | **No obvious mark in limited views.** No obvious logo or text identified; dark pot streaks appear as surface artifacts at these views, not identified as marks. | [0](assets/planter_clean_0.png) / [1](assets/planter_clean_1.png) |
| W1-PROP-016 | `pistol_clean.glb` | **Observed/ambiguous mark.** Small circular/emblem-like grip details visible; unclear whether fasteners, ornament or branding. Unresolved. | [0](assets/pistol_clean_0.png) / [1](assets/pistol_clean_1.png) |
| W1-PROP-017 | `smg_clean.glb` | **Insufficient views.** Both views are dark and nearly edge-on along the weapon; broad side surfaces are not usefully visible. Additional side views required. | [0](assets/smg_clean_0.png) / [1](assets/smg_clean_1.png) |
| W1-PROP-018 | `airfield_clutter_clean.glb` | **No obvious mark in limited views.** Small plate/label-like rectangles on crates are unresolved; no readable brand identified in these views. | [0](assets/airfield_clutter_clean_0.png) / [1](assets/airfield_clutter_clean_1.png) |

Six assets have observed marks or unresolved emblem-like details; eleven have no obvious mark identified in limited views; one has insufficient views. **Zero of eighteen is certified clear for public redistribution.** No specific trademark identity is asserted. The sedan contradicts the earlier no-marks finding; the officer and pistol add previously unrecorded review concerns.

## Identity and CSV validation

- Authoritative source: `docs/asset-deliveries/wave-01.json`. Eighteen successful records: Customuse 8, Tripo 10. The failed Customuse counter request remains a metadata-only row; its successful output is the separate Tripo record.
- All 18 raw staged GLBs under the sibling manager asset directory matched their authoritative SHA256 values. Source URLs and provider task/job/set IDs were preserved; source hashes were not replaced by derivative hashes.
- All 25 current provider GLBs have individual rows and local SHA256 values: 18 cleaned files plus 7 private derivatives. Derivative parents, scripts, reports, and editable-source locations are recorded.
- The previous CSV parsed as 35 data rows with inconsistent 9/11/12 column counts. The rebuilt CSV parses as **64 data rows with exactly 26 columns in every row**, including the header.
- Every provider mesh row has separate `UNVERIFIED` public-source and packaged-binary redistribution fields, unresolved current terms/account conditions, and unresolved per-job labels. Private task authorization is not recorded as legal clearance.
- The atlas SHA256 agrees with its generation metadata. Both exporter companion PNGs were hashed separately and are byte-identical to the original atlas at this snapshot.
- Original geometry and code retain MIT notice obligations; mixed files containing the generated atlas inherit its unresolved redistribution status. Prior concept/reference/code provenance groups remain represented; obsolete pending-generation claims are removed.

## Reproduction limits and open gates

The eight Customuse records contain direct GLB URLs, but availability was not retested. The ten Tripo URLs are authenticated workspace pages and cannot be treated as automatic downloads. `fetch_provider_assets.sh` can validate locally staged Tripo exports and print manual-export instructions; it does not retrieve them. The old cleanup script hardcoded predecessor output and preview paths at review time; root subsequently replaced those with checkout-relative defaults and explicit `OR_RAW_DIR`/`OR_OUT_DIR`/`OR_PREVIEW_DIR` overrides, with rendering opt-in. Fresh-clone recovery still requires staged sources and the manual Tripo exports. See [ASSET_RIGHTS](../ASSET_RIGHTS.md) for the bounded procedure.

Remaining work is review of applicable provider/job/account terms; adequate all-surface and texture review of the final exports (especially marked assets and SMG sides); final-derivative inspection after any mark replacement; generated-atlas/concept terms; actual package inventory and dependencies; and explicit owner release/merge permission. No public release or main merge is authorized.

Historical wave-1 terms statements remain in ASSET_RIGHTS as unrefreshed history. The shared-brain startup doctor reported cached revision `ba35669bd13c` as `not-recently-checked` in this lane; no claim of a live policy refresh is made here. The local reversible audit used the injected task constraints, with no infrastructure or policy publication.
