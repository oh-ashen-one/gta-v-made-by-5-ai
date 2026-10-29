# City geometry source credits

Footprints, original road IDs/node references, names/tags, national boundary and horizontal layout are derived from © OpenStreetMap contributors, Open Database License1.0: https://www.openstreetmap.org/copyright . Source snapshot2026-10-27 and exact canonical/PBF hashes are recorded in each completed candidate manifest. The private PBF is not copied into this output.

Building-base samples use the separately versioned Mapzen Skadi derivative. Credit Mapzen, USGS SRTM/GMTED2010 and NOAA ETOPO1, and retain the terrain dataset’s own ATTRIBUTION.md, receipts and underlying provider terms. Source elevation is coarse/historical EGM96, not a current building-ground survey or an automatic architectural-floor datum.

This compiler adds explicitly declared game extrusions, world-Y reference offset, min-level/story-height interpretation, local float32 packing, UVs, source-country/tile partitioning and collision-candidate topology. Missing factual heights are not silently changed into source facts. Flat roofs, fallback dimensions and source-part composition require further architectural/material/visual review. The game code license does not replace data source terms.

The separate qa-fixture-v1 is synthetic compiler/physics QA, not actual Singapore geometry. No source-completeness, current-survey, legal-driving, finished-terrain/city/interior or gameplay acceptance is implied by compiled buffers.
