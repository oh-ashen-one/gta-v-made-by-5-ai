# Public programme integration contract v2

Frozen at the owner-requested milestone cutoff. This is a source/data integration contract, not a completed or furnished floor. No legacy inventory, factories, Stack, Hotel, source-city pin or production scene was modified.

Use `PUBLIC_PROGRAMME_CONTRACT_V2.json` together with `SOURCE_BUILDING_BINDINGS.json`. These are the complete runtime-facing data closure; neither needs a PDF, a network request, or a machine-local private path. The contract uses builder V14 as the only floor registry and preserves its216 historical records plus new Museum L4. Hotel room targets/axes/core assignments are unaffected.

## Exact source buildings

- **EXPO:** OSM relation12633420, version2, timestamp2022-05-03T11:16:47Z, names Marina Bay Sands MICE Building. It binds outline way172014440 and18parts, including bodypart1056849313. Frozen outline area22843.63m². It is not the whole Shoppes relation2298319.
- **MUSEUM:** OSM relation14314416, version3, timestamp2023-09-17T08:24:34Z, names ArtScience Museum. It binds63members including outline way261191086 (4346.00m²) and lower roof outline827855854 (856.78m²).

All82 member polygons are copied exactly from the retained2026-10-27 source tile. Relations were independently read on29October only to recover name/member/version metadata; current network geometry was not substituted. Each polygon carries source tags, hashes, role, world bounds and current city status. Coordinates remain EPSG3414-derived world X south/Z west, in metres, origin easting/northing30000. They have not been fitted to old game rectangles.

## Required programme coverage

- **EXPO-L3:** five named main ballroom groups, five named junior groups, five meeting-room requirements, fitness, public foyers, service corridor/kitchen, Business and Mail Centre, and restrooms. The July2025 operator diagram places fitness beside the guest-lift lobby at the short end, main groups across the main foyer from juniors, service access on the other side, and Shoppes/Bayview glazing outside the juniors. Published hall clear height is6.1m; this does not establish floor elevation.
- **MUSEUM-B2:** the two named current Future World programme realms, ticketing, the320m² ArtScience Laboratory, circulation/Oculus approach and public/service support. The realms are programmes, not an assertion of exactly two enclosed rooms.
- **MUSEUM-L4:** ArtScience Cinema236m², lift lobby166m² and VR Gallery184m², plus support/remaining sectors. Diagram codes are A.04.06.00, A.04.05.00 and A.04.02.00. The lobby contains lift labels L-A01/02. Curved source schematic boundaries are retained separately; they are not registered world polygons.
- **MUSEUM-B1:** preserved for coherent exploration, with current programme explicitly unresolved; neither the old parking-only recipe nor undated education reference is promoted to a current floor fact.

## Collision replacement before opening the interiors

`GENERIC_COLLISION_REPLACEMENT.json` lists all82 member keys and the11 still emitted as generic city collision. The other71 are already root-excluded in the recoveredR2 catalogue. The current emitted keys are:

- `building|way/827847264` (EXPO). 
- `building|way/827847265` (EXPO). 
- `building|way/827855864` (MUSEUM). 
- `building|way/827855865` (MUSEUM). 
- `building|way/827855866` (MUSEUM). 
- `building|way/827855867` (MUSEUM). 
- `building|way/827855868` (MUSEUM). 
- `building|way/827855869` (MUSEUM). 
- `building|way/827855863` (MUSEUM). 
- `building|way/827855921` (MUSEUM). 
- `building|way/827855922` (MUSEUM). 

Remove or replace only these exact building identities after the real shell/interior support is installed and native readiness has passed. Do not delete everything inside an axis-aligned region: Shoppes, roads, roof components and adjacent features share/overlap this site. Basements require proven terrain/shell openings and stable slab ownership; the building outline does not authorize a terrain hole. Keep saved IDs and source-face provenance bound through replacement.

## Explicit integration limits

World slab/zone polygons and surveyed floor Y are null. Expo outline and upper Museum lotus/roof projections do not prove every internal floor envelope; the larger underground Museum footprint remains unknown. Current B2 circulation sources disagree (dedicated venue830m² versus comparison525m²), so neither is silently selected. The three current L4 venue areas sum586m², whereas the brochure rounds the group to600m²; use individual published areas as references, not an entire slab extent.

The current venue page requires five meeting rooms but only names Angsana/Angsana Junior/Saraca as groups. The July2025 map retains five junior groups while its older heading/table says six and draws the former southern blocks as Business/Mail. Five durable meeting requirements therefore remain without fabricated per-room names or an invented one-to-one map. Preserve all named references and solve that assignment explicitly in a reconstruction before claiming full source fidelity.

Root can adopt the semantic/programme contract immediately. A native floor factory must still make an explicit source-conforming metric reconstruction and validate enclosure/doors/circulation/support. The contract deliberately reports `native_build_ready=false`; do not feed it into an old generic rectangle fallback or advertise public floors as finished from this artifact. This does not reduce coverage: all31 programme/support requirements and four levels remain tracked.

## Verification and reproducibility

One bounded CPU closure check passed342/342 predicates: exact82 source member polygons, valid source polygons, complete relation membership/replacement sets, registry hash and levels,31 unique programme/support requirements, required group counts, B1 uncertainty and no native/physical overclaim. No engine was run.

`build_contract.py` regenerates the contract from the frozen source tile, recovered city catalogue, V14 registry, `RELATION_MEMBER_EVIDENCE.json`, `PROGRAMME_SEEDS.json` and `OPERATOR_PLAN_OBSERVATIONS.json`. The optional PDF extraction helper uses the ignored private operator PDF only to reproduce the already-frozen schematic observations. It uses bundled pdfplumber; the raw PDF and rendered references remain private and are not required by consumers. Source URLs, exact hashes and missing acquisition rights remain in `REFERENCE_ACCESS.json`.

No further research or audit cycle is scheduled by this worker. Root owns integration, any engine checks and packaging.
