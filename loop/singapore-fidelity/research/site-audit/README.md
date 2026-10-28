# MBS site geometry audit

This is a measured source-data input for the ongoing full Singapore/MBS request. It is not a completed city, hotel interior, or architectural as-built certificate.

## Current outputs

- `real-source-r5.json`: current audit; earlier r1–r4 files preserve the audit's development and disambiguation history.
- `mbs-source-components-r1.json`: exact selected projected source polygons/lines with OSM IDs, tags, height status, source timestamp, attribution and missing-geometry notes. Coordinates are `[world X south, world Z west]` in uncompressed metres; this custom game format is not WGS84 RFC7946 GeoJSON.
- `verification.json`: source/script identities and test scope.

## Source-established findings

The national snapshot is dated2026-10-27T21:23:59Z. Every input tile checksum and feature count was checked.

| Component | Actual source identity |
| --- | --- |
| Hotel Tower1 | `way/116801004` |
| Hotel Tower2 | `way/172307472` |
| Hotel Tower3 | `way/172307471` |
| Shoppes | `relation/2298319` |

All three hotel tower names are explicit source tags. The audit groups those three **disjoint tower footprints**; it does not fill in the shared hotel atrium or invent its footprint. Their source labels sort north-to-south as **T3,T2,T1**, matching the separately recorded operator circulation reference.

- The grouped tower envelope measures **281.578×61.194m**, with an undirected major-axis bearing **26.54211° from SVY21 grid north**. This is an envelope, not a measured façade/core/door bearing or the SkyPark outline.
- The Shoppes envelope is **584.210×173.252m**, bearing **32.50998°**.
- Minimum separation between the tagged tower footprints and Shoppes is **42.0224m**. Named Bayfront Avenue motor-road segments `way/479284867` and `way/667468498` cross the gap connector. This supports separate massing with the road between, not an attached hotel/retail box. It does not locate real doors, underpasses or lift landings.
- The three towers each carry a source height tag **193m**. That is retained as source data, not treated as independent architectural survey or floor-elevation proof.
- A separately dated Overpass site response,2026-10-28T17:02:44Z, agrees with each tower boundary within0.0001m after projection/rounding. Its Shoppes relation contains bounds/tags but no boundary members/geometry, so latest-query retail consistency is **unavailable**, not a pass.
- The old model's public terrace uses positive-x/south coordinates; the operator reference places public observation access at Tower3/north. The audit flags that directional intent conflict without inventing an exact public-deck polygon/elevation.
- The old Fullerton–MBS anchor distance is579.131m; the corresponding source-footprint-centroid distance is890.442m. These are different reference-point definitions and cannot be used as a runtime warp. The legacy plan itself explicitly declares0.45EW/0.65NS distance compression.

## Retained gaps

ArtScience and Merlion are not found in the extractor's **building-only feature selection**. This is not proof that the physical landmarks are absent or that OSM has no corresponding POI. Singapore Flyer has two different named building footprints with zero/unknown height; neither is silently chosen as the wheel. Esplanade's source footprint covers a named complex while legacy anchors split theatre and concert hall, so the tool does not pretend those are the same reference point.

The three-tower union cannot establish the shared ground-level hotel spine, upper floors, every room, hotel entrances, vertical circulation, underpasses, complete roof programs or interior fit-out. Current official kiosk/brochure/FAQ references and their age/coverage limits remain in `../mbs/`. The full requested one-to-one interior and runtime world migration remain open.

## Reproduce

Use the integrator's private geodata virtual environment (or install `game/tools/geodata/requirements.txt`) and a completed attributed snapshot. Do not restart or duplicate a live extractor just because a manifest is not yet present.

```sh
python -m unittest discover -s game/tools/geodata -p 'test_site_audit.py' -v
python game/tools/geodata/site_audit.py SNAPSHOT_DIR \
  --output NEW_AUDIT.json --components-output NEW_COMPONENTS.json \
  --legacy-plan game/src/world/downtown/plan.gd \
  --circulation-contract loop/singapore-fidelity/research/mbs/circulation-contract.json \
  --legacy-access game/src/world/downtown/skypark_access.gd \
  --site-overpass PRIVATE_SITE_QUERY.json \
  --expected-pbf-sha256 5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd \
  --expected-overpass-sha256 9555879ce9b203fd20e499372dcc3b172c03d2de6bdca1d6f9d1557486c08cb5
```

Synthetic tests explicitly use fixture data; no engine or visual acceptance is inferred. Data is ©OpenStreetMap contributors, ODbL1.0: https://www.openstreetmap.org/copyright . The original audit code does not change the data license. No reference imagery, credentials, signed download URLs, raw PBF, engine launch or Git mutation is part of this subtask.
