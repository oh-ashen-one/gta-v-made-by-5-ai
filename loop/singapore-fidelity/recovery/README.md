# Source-world dataset recovery after the 2026-10-29 Studio restart

The previous `/private/tmp/singapore-fidelity` tree and its running handles no longer exist. No missing terminal receipt is a successful run. Preserved source, private provider art, original city candidate R1, canonical OSM source pages, coastline/domain, and DEM tiles remain in the authoring checkout.

This directory owns recovery recipes and receipts. `private/` is locally ignored and contains the generated datasets and the task-local dependency environment. No source dataset is downloaded again, no immutable artifact is overwritten, no production source pin is silently changed, and no engine is launched by this recovery worker.

## Runtime

Create `private/venv` with the bundled Python 3.12 runtime, then install the pinned packages in `requirements.txt`. The local environment is disposable; it is not a global tool configuration. The runtime was rebuilt because the prior `/private/tmp/orchard-geodata/venv` was cleared.

## City

The complete original candidate at `game/data/geography/compiled-country/osm-2026-10-27/candidate-r1` survives. Its SHA-256 identity is `2871b559368ecf5f999d84f82a008788eedfa4d8a03b2cff861d2ffe2a5e95ab`. It is rejected for Godot triangle winding and must not be used as a replacement for R2.

Run the unchanged `game/tools/geography/compile_city.py --repair-winding <R1> <fresh-output> <R1-identity>` under background priority using `private/venv/bin/python`. The compiler already supervises this repair: 600 CPU seconds, 1800 wall seconds, 2 GiB sampled RSS. It hashes all parent metadata/catalogs/buffers, corrects triangle index order only, preserves every position/normal/UV byte and catalog, and refuses existing destinations.

The durable output is `private/city-geometry/candidate-r2`. Recovery is usable only after the identity equals the existing runtime pin and the complete output manifest inventory passes independent hash verification.

## Terrain

Re-run the unchanged `game/tools/geography/compile_terrain_scene.py` against the preserved canonical snapshot, domain, DEM and root masks. The exact command is retained in the private job command receipt. Select the original nine tiles in x-major order: x=-1..1 and z=-2..0; world-Y offset remains 0.0. Bound this task to 600 CPU seconds and 900 wall seconds. No new water, dryland, zero-ground or architecture mask assumptions are permitted.

The durable output is `private/terrain-scene/mbs-neighborhood-r1`. Its outer/inner identities and every prepared mesh/catalog/water-registry hash must match the tracked original receipts. A package-version-dependent difference is a changed artifact, not permission to stamp the old hash onto it.

## Roads and gameplay

The separately assigned road worker owns immutable R5 recovery and the NEW semantic-baseline pipeline. Do not duplicate its process or adopt the new semantic candidate as R5. WorldQA's unchanged waypoint repair SHA is `7a11a9e18fb8e752ec3bbfeb6ac8517daa942ea70b64fef3599ad8f1e4a4dd20`; lexical/source inspection is not native import or successful traversal. Root owns the next actual run, production dataset locations, complete gameplay integration and all Git operations.

## Verified recovery outcome

`CITY_RECOVERED.json` independently hashes all 2,524 pinned files (1,072,753,939 bytes), including all 906 logical catalogs and 808 mesh tiles. The rebuilt city matches the ORIGINAL R2 identity exactly. Its supervised repair completed with exit 0 in 661.452 seconds.

`TERRAIN_RECOVERED.json` independently hashes all 31 pinned files (2,492,224 bytes) and matches the original outer and inner terrain identities exactly. The nine-tile preparation completed with exit 0 in 337.833 seconds. Neither identity was rewritten or substituted. Compiler-environment tests pass 11 city + 7 terrain. This recovers the existing artifacts; it is not a new runtime or visual acceptance.
