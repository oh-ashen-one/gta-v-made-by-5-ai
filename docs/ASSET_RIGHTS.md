# Asset provenance and rights — wave 2

Private implementation is authorized for the existing eighteen provider models and their local derivatives. **Public source redistribution and packaged-binary redistribution of those assets remain `UNVERIFIED`. No public game release or merge to `main` is authorized.** Asset provenance, visible-mark review, applicable terms, and permission to publish are separate questions.

This record supersedes the wave-1 blanket clearance claims. It is a local evidence audit dated 2026-10-21, not a current legal-terms certification. No provider terms page, account plan, or individual job page was fetched during this review. The historical terms discussion below remains explicitly unrefreshed.

## Authoritative records and actual inventory

- [Wave-1 delivery record](asset-deliveries/wave-01.json): authoritative request IDs, provider task/job IDs, Customuse set IDs, source hashes, recorded source URLs, prompts and routing history.
- [Asset manifest](asset-manifest.csv): current per-asset source identity, local GLB hash, private-use status, independent public-source and packaged-binary fields, and bounded visual observations. Its new 26-column CSV schema uses proper quoting; the old file had 9-, 11-, and 12-column rows.
- [Wave-2 review](wave-02/provenance-review.md): coverage, specific observed marks, validation, and remaining gates.

There are **8 successful Customuse outputs** (`W1-HERO-001` through `008`) and **10 successful Tripo outputs** (`W1-HERO-009` plus `W1-PROP-010` through `018`). The attempted Customuse `W1-HERO-009` failed before producing a model; its set ID and zero-charge failure remain recorded separately. It does not add a nineteenth model. The successful counter is a Tripo output.

All eighteen staged raw GLBs were read locally and their SHA256 hashes matched the delivery record. The current ignored provider directory contains eighteen cleaned GLBs and eight additional private derivatives. A source hash match establishes file identity, not rights or visual acceptance. CSV `source_sha256` means the delivered raw file; `local_sha256` means the particular current file named by that row. The two hashes normally differ after editing.

## Historical terms review — not refreshed

| Provider | Historical source and claim | Current audit status |
| --- | --- | --- |
| Customuse | Wave 1 recorded [Customuse terms](https://customuse.com/terms) with a stated revision date of 19 June 2026 and summarized them as allowing lawful personal/commercial output use, subject to third-party rights and personal-use restrictions, with no stated attribution obligation. | This audit did not verify that page, revision, account entitlement, or each job's labels. Current terms, applicable plan, per-job restrictions, attribution, and separate source/binary redistribution rights remain `UNVERIFIED`. |
| Tripo | The delivery record links [Tripo commercial-use guidance](https://www.tripo3d.ai/help/privacy-policy/how-to-use-tripo-models-commercially) and records owner-authorized browser generation using existing credits. | Account ownership, credit consumption and private job visibility do not establish distribution rights. Applicable plan, per-job labels, attribution and separate source/binary redistribution rights remain `UNVERIFIED`. |

The old sentence declaring “Terms: cleared” is withdrawn. The historical note's suggestion that absence of personal-use labels had been checked on all jobs is not backed here by retained per-job evidence. A prompt asking for an original or unbranded object is not output clearance. In fact, the recorded coupe and van prompts explicitly requested fictional badges/courier markings; the earlier claim that every prompt prohibited all markings was inaccurate.

The eighteen delivery records describe generated outputs rather than extracted game assets. That is the recorded input provenance; this audit does not establish a forensic guarantee about the providers' training data, every visual similarity, or every hidden surface.

## Visible-output inspection

All **36 supplied 1280×720 images**, two views for each of the eighteen cleaned models, were inspected with `view_image`. Diagnostic contact sheets were followed by inspection of every original image, including the suspect details. These are the existing images in [wave-02/assets](wave-02/assets); no engine or new provider generation was used for this review.

Six cleaned assets have visible marks or unresolved emblem-like details:

| Asset | Observed evidence |
| --- | --- |
| `sedan_clean.glb` — `W1-HERO-001` | Oval/ring badge-like shapes on front grille and trunk. The wave-1 “free of marks” conclusion is withdrawn. |
| `coupe_clean.glb` — `W1-HERO-002` | Yellow/gold nose and rear badge-like shapes; plate-like lettering too small to resolve. |
| `van_clean.glb` — `W1-HERO-003` | Large red/blue emblems, repeated cab/front/rear motifs and pseudo-lettering. |
| `player_clean.glb` — `W1-HERO-005` | N-like contrasting side marks on the sneakers. |
| `officer_clean.glb` — `W1-HERO-006` | Cap crest, chest badge/name-strip and shoulder/collar insignia. |
| `pistol_clean.glb` — `W1-PROP-016` | Small circular/emblem-like grip details; unclear whether fasteners, ornament or branding. |

These descriptions do not identify the marks as any particular trademark or official force. Their origin and disposition remain unresolved. They need focused output/texture inspection and either a supported clearance decision or authorized removal/replacement followed by inspection of the exact final export.

Eleven other models have **no obvious mark identified in the inspected views**, which is a limited observation rather than clearance. The helicopter falls into this category; it is no longer described as globally verified. Small rectangular plate/label-like features on the airfield crates remain unreadable. Several props have severe triangular surface/shading artifacts that obscure small details. `smg_clean.glb` is a separate **insufficient-view** case: both images are dark and nearly edge-on, leaving its broad sides unreviewed. No provider asset has complete output clearance from this two-view audit.

## Wave-2 derivatives and authored additions

The following eight GLBs retain their provider-source restrictions, along with their extracted companion textures and editable `.blend` sources:

- `player_rigged.glb` and `civilian_rigged.glb`: derivatives of `W1-HERO-005`, with reports in `game/assets/providers/*_rig_report.json` and ignored editable sources in `art/source/characters/`. The author reports replacement of the sneaker surfaces with original textile/rubber. That report is useful provenance; it is not a complete inspection of each final export, nor does it clear the original `player_clean.glb`. Later cloth/shoe changes have only limited newer runtime views; they do not establish complete final-derivative clearance or alter the raw/cleaned source mark finding.
- `officer_rigged.glb`: derivative of `W1-HERO-006`; source uniform insignia remains unresolved.
- `pistol_held.glb` and `smg_held.glb`: held-orientation derivatives of `W1-PROP-016` and `017`; changing orientation does not change source rights.
- `hawker_counter_refined.glb` and `hawker_table_refined.glb`: derivatives rebuilt from `W1-HERO-009` and `W1-PROP-010`, recorded in `refined_props_manifest.json`, with ignored editable sources in `art/provider-sources/`.
- `helicopter_refined.glb`: private derivative of raw `W1-HERO-004`, reproduced by `game/tools/refine_helicopter.py`, with ignored editable source `art/source/helicopter/helicopter_refined.blend`. Its report records preserved source triangles, UVs, normals and materials with body/main/tail rotor partitioning and corrected orientation/pivots. Source and output hashes match that report. This metadata check does not certify the final derivative visually or clear its rights.

- Helicopter piece (opus55, 2026-10-22): `game/src/actors/heli_fx.gd` (rotor-disc, rotor-shadow and downwash shaders, generated radial textures, nav lights) and `game/src/world/helipad_dressing.gd` (pad markings, lights, masts, windsock, ground equipment) are original procedural code with no new external assets. The parked second aircraft on the primary pad reuses the existing private provider mesh `helicopter_clean.glb` (W1-HERO-004) and inherits its UNVERIFIED status.

Original project code, deterministic PBR surface maps, foliage, pavilion, skyline geometry, boundary railing, hawker meal, plain English signage and procedural sky/audio are distinguished in the CSV from provider content. Their authoring scripts and editable original sources remain recorded. The repository MIT notice applies to original project contributions; it does not automatically relicense embedded or referenced third-party/provider content. Preserve the MIT copyright and permission notice when redistributing applicable original contributions.

The new [packaging atlas metadata](wave-02/packaging-atlas.json) records one built-in `image_gen` request, its full prompt, no external reference images, and the output hash. The atlas was also inspected in this audit: sixteen generic English product labels are visible, with no obvious existing brand identified. Small generated lettering and fictional nutrition panels are decorative. This is generated original-intent artwork, not a certified rights-cleared output. Its current provider/account terms and public redistribution status remain `UNVERIFIED`.

`boundary_railing.glb` and `hawker_meal.glb` are original geometry authored by `game/tools/build_urban_kit.py` using `build_interiors.py` helpers. Their GLB JSON contains no image textures. The boundary manifest names the shared save helper, so the actual entrypoint is explicitly retained in the CSV; the meal has an editable source and script but no standalone manifest. The saved railing, meal and safe-furnishing Blender sources contain packaging-atlas reference text from shared setup, even though their GLBs have no image textures. Their full saved datablock/dependency state has not been audited; original geometry remains distinct from any generated-art dependency, and whole-source public redistribution is `UNVERIFIED`.

The convenience-shop and workshop GLBs, their companion atlas PNGs, and their editable sources contain this packaging artwork. Their original geometry does not eliminate the atlas dependency: whole-file redistribution remains `UNVERIFIED`. The atlas original and both companion PNGs have their own rows/hashes. Existing generated concept images likewise retain their generation metadata without a blanket MIT clearance claim. Screenshots depicting unresolved provider content are composite evidence, not automatically cleared original images.

### Opus 5.5 lighting piece (2026-10-22)

`game/assets/authored/shaders/golden_hour_sky.gdshader` (procedural HDR sky) and `game/src/world/lighting.gd` (environment, sun, fog, a runtime-generated 3D colour-grade LUT and procedural practical-light fixtures built from engine box meshes and emissive materials) are original project code written for this loop. No image, HDRI, LUT file, third-party shader or Rockstar material was used; GTA V reference stills set the quality bar only and are not in the repository. Both files have CSV rows with hashes. Round 3 adds `game/assets/authored/shaders/street_weathering.gdshader` (procedural screen-space surface wear) and `game/src/world/street_dressing.gd` (street clutter from engine primitives, median ferns reusing the existing original `fern.glb`); both are original code with CSV rows and hashes, and no new imported, generated or third-party asset was added.

## Reproducibility and storage boundaries

`game/assets/providers/`, `art/source/characters/`, `art/source/helicopter/`, and `art/provider-sources/` are ignored. The processed provider meshes and derivatives are excluded from public Git history because rights review is incomplete and the files are large. A file being ignored is a storage decision; it does not make an exported game package safe to publish.

- **Customuse:** `fetch_provider_assets.sh` contains eight recorded direct GLB URLs and SHA256 checks. Their availability was not retested in this audit. The local staged copies were verified; there was no repeat download or generation.
- **Tripo:** the ten source URLs are owner-authenticated workspace pages, **not automatic GLB downloads**. The script reports missing exports and validates local files when present. Reproduction requires the authorized owner browser export or the verified manager-carried files; a successful script exit is not proof that all ten missing files were fetched.
- **Cleanup (root follow-up after this audit):** `cleanup_provider_assets.py` now resolves its output inside the current checkout. Set `OR_RAW_DIR` to the staged original source folder; optional `OR_OUT_DIR` and `OR_PREVIEW_DIR` are explicit overrides. Existing cleaned files are preserved unless `OR_FORCE=1`. GPU previews are opt-in with `OR_RENDER_PREVIEWS=1` and require the shared slot. This path correction does not eliminate the manual Tripo export prerequisite or certify a fresh-clone rebuild.
- **Private derivatives:** `rig_characters.py`, `refine_props.py`, and `refine_helicopter.py` plus the verified private inputs are required. The two refinement scripts default to the sibling manager staging directory; `refine_helicopter.py` also accepts an explicit `--source` path. Scripts alone do not supply those ignored inputs or grant distribution rights. Keep the verified private carry-forward bundle available to the successor; no new provider generation is required.

## Remaining gates before any public distribution

1. Verify the terms actually applicable to each provider job/account and the permitted forms of distribution. Record source-file and packaged-binary rights separately, including labels and attribution obligations.
2. Inspect the exact final meshes and textures with adequate coverage. Resolve the six marked/ambiguous cleaned assets, the SMG side surfaces, unreadable small labels, and all eight final derivatives. A shoe modification does not clear an untouched source mesh used elsewhere.
3. Resolve generated-atlas and concept-art terms and inspect any final embedded/exported use. Include fonts, engine notices and other runtime dependencies in a release-wide audit; this asset review is not a complete software-license bill of materials.
4. Audit the actual final package and its included assets against the manifest. No packaged-binary inventory or release clearance was established here.
5. Obtain the owner's explicit authorization for the particular public release or `main` merge. Private-build authority, a successful test, a branch push, or this provenance document does not grant it.

## Final metadata refresh

At 2026-10-21T14:01:29Z, the frozen source/assets were rehashed without launching engines or inspecting new rendered views. The CSV now contains **82 data rows with 26 columns**, including all **26 provider GLBs**, all **13 authored GLBs**, and individual entries for all **13 original editable Blender sources**. There are **72 individually hashed files**; grouped source/texture entries intentionally have no single-file hash. All 18 raw sources still match the delivery record. Nine existing single-file hashes changed since the initial snapshot (six code files and three interior GLBs); foliage and other recorded assets were rechecked and retained matching hashes. No required listed file is missing. Existing visual observations and unresolved rights are preserved. `reviewed_utc` in the CSV now denotes this metadata snapshot; the two-angle visual review remains the earlier review.

At the post-soak visual checkpoint, four original-code hashes (world builder, palette, car controller, HUD) were refreshed. No provider/source asset changed and no rights or visual clearance was inferred. Vehicle wheel animation is contained because the inherited wheel labels include body fragments; genuine wheel partitioning remains unfinished.

## Wave B "materials" additions (2026-10-22, Opus 5.5 loop)

All new material work is original and procedural; no downloaded, provider-generated or reference imagery was used, and no GTA V reference image was copied. New rows in `docs/asset-manifest.csv`: `weather_masks.png` (generated by `game/tools/build_surfaces.py`, appended section with its own seed so the 21 earlier maps stay byte-identical), five world-space shaders plus a shared include under `game/assets/authored/shaders/`, and `game/src/world/surface_dressing.gd` (condenser, pipe, cable, tank and roof-plant meshes are generated in code). The `.import` settings of the existing authored surface maps now generate mipmaps; pixel data is unchanged. Facade sheets in `palette.gd` gain baked rain streaks and mottling at runtime (code only).

Materials round B2 (code only, no new image files): `road_asphalt.gdshader` adds procedural footprint-faded aggregate (value noise, stone chips, binder pits, mid-range mottling) and replaces rectangular patch quads with noise-warped blended reinstatements; `road_paint.gdshader` keeps markings crisp (faded/grainy wear only); `grime_overlay.gdshader` gains per-family weights so conservation shophouses get only a light splash band; `surface_dressing.gd` details the generated condenser mesh (fan guard bars, louvres, feet), lays a generated vinyl-tile floor slab in the convenience-store kit, and since wave-A integration dresses only the walls of RoofKit infill blocks (RoofKit owns their roofs).
Also new in B2 (original code, no textures): `corrugated_metal.gdshader` (hangar cladding and roof), `encaustic_tiles.gdshader` (three original geometric tile motifs for the five-foot ways; not copied from any tile catalogue or reference image); `weathered_wall.gdshader` turf mode now reads as kept grass verge, and the base ground plane uses it.
## Opus 5.5 loop — water piece (2026-10-22)

All additions are original code written for this project (MIT); no imported meshes, textures or audio, and no paid or external generation.

- `game/assets/authored/shaders/bay_water.gdshader`, `water_jet.gdshader`, `bay_boat.gdshader` — new shaders (bay_water rewritten in round 2: procedural noise wave field, whitecaps, sparkle; still fully original code).
- `game/assets/authored/shaders/timber_deck.gdshader` — new in round 3: procedural weathered-hardwood boardwalk for the bay jetties and pontoon (world-space planks, gaps, grain, bleaching, wet staining). Original code; no textures, no third-party or Rockstar material. bay_water round 3 adds event-driven foam (Kelvin wakes, stern trails, quay surges, jet boil) — also original code.
- `game/src/world/bay.gd`, `game/src/world/boat_meshes.gd` — runtime-generated sea plane, seawalls, pier base, pontoon, boats (bumboat, river cruiser, launch), Merlion jet tube and splash particles.
- Round 4: `game/assets/authored/shaders/boat_spray.gdshader` (raised bow spray sheets and churned stern mound, world-space cellular foam) and `boat_droplets.gdshader` (ballistic spray droplets evaluated in the vertex shader) plus `game/src/world/boat_wash.gd` (generated sheet/mound/droplet meshes on MultiMeshes). `boat_meshes.gd` gains a detailed sport runabout (two-tone deep-V hull, windshield frame, bow rail, spotlights, outboard) and low-poly crew/passenger figures built from boxes, tubes and ellipsoids in code; `bay_boat.gdshader` adds clear-coat gel-coat, polished steel and waterline grime. `bay_water.gdshader` renders all wake and quay foam as lacy cellular coverage and shows a procedural rock-armour toe through the shallows along the quays. All original code; no imported meshes or textures, no third-party or Rockstar material.
- `merlion_landmark.glb` is unchanged on disk; its opaque `merlion_water_spray` mesh is hidden at runtime and replaced by the translucent jet above.
- GTA V reference images (`loop/references/`, git-ignored) were used only to judge quality; nothing from them is in the game or the repository.
## Wave A (Opus 5.5) — skyline piece

`game/tools/build_landmarks.py` (Blender 5.2, `-b --factory-startup`) rebuilt three of the five landmark GLBs as original procedural geometry: `marina_bay_sands.glb` (true-scale curved-leg towers and a boat-hull SkyPark), `supertree_grove.glb` (planted trunks, rust-purple steel exoskeletons, planted funnel throats under open perforated steel-lattice crowns since skyline round 2) and `merlion_landmark.glb` (a metaball sculpt). `artscience_museum.glb` and `singapore_flyer.glb` are unchanged wave-4 authoring; all five GLBs and their `art/source/*.blend` sources now have individual hashed rows in `docs/asset-manifest.csv` (they were previously unlisted). They evoke real public landmarks through generic geometry only: no scans, photogrammetry, logos, downloaded models or reference images. GTA V reference images were used only to judge quality and are not in the repository or the build.

New runtime code adds no external assets: `skyline_facade.gdshader`, `roof_deck.gdshader` and `vertical_garden.gdshader` and (skyline round 3) `skyline_ground_shadow.gdshader` are original procedural shaders (no textures); `landmark_looks.gd` swaps named landmark materials for those shaders; `skyline_city.gd` generates the layered background towers in code (replacing the far-shore skyline GLB grid; since skyline round 2 the existing authored `skyline_0..3.glb` towers are used again only for the inner east flank row behind the aviation compound, and the facade shader carries seven procedural cladding systems, a lobby base, a plant-screen crown and its own aerial-perspective fog term, still with no textures); `roof_kit.gd` generates roof decks, parapets and roof plant and tints copies of the existing procedural facade sheets. Only existing, already-listed project surface textures are reused.

Skyline round 4 (still no external assets, no textures, no reference imagery): `skyline_horizon.gd` generates the hinterland in code (procedural city-carpet ground, a few thousand low-rise blocks, a third tower layer and HDB-style estates through `skyline_city.gd`, low wooded ridges, a camera-following horizon skirt and tower cranes) and batches the existing project `rain_tree.glb` along the far-shore promenade. New original shaders: `skyline_haze.gdshaderinc` (shared aerial perspective), `city_carpet.gdshader`, `skyline_hills.gdshader`, `skyline_horizon_skirt.gdshader`, `skyline_crane.gdshader`. `landmark_looks.gd` now also gives the authored `skyline_0..3.glb` glass a satin (less mirror-like) duplicate of its existing material at runtime; the GLBs themselves are unchanged.

opus55 driving (2026-10-22): `game/src/actors/car_fx.gd` and `game/src/systems/drive_showcase.gd` are original code; every texture (light coronas, smoke puff), mesh (skid strips, spark streaks) and shader (radial speed blur) they use is generated at runtime. The clear-coat pass duplicates the existing provider car materials in memory only; no provider file was changed and no rights status was altered. The tyre-squeal loop in `audio.gd` is synthesised in code.

opus55 driving-p (2026-10-22): new original code `game/src/actors/car_damage.gd` and shader `game/assets/authored/shaders/car_body.gdshader`. The shader replaces the provider car materials in memory only (it samples the provider's existing albedo/ORM textures; no provider file is changed and no rights status is altered). It paints out the boot-lid badge-like ring on the generated sedan (the ring already flagged in the manifest; the front-grille ring is not masked and stays flagged). Dents, scrapes, cracked glass, debris fragments (box meshes), the glass glitter decal texture and the crash/glass sounds are generated at runtime; no external assets, references or samples are used.
