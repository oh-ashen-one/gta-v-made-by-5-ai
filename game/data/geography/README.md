# Geography data and attribution

Geospatial source data is separate from the original game code/art license.

- OpenStreetMap-derived geometry: © OpenStreetMap contributors, ODbL1.0. https://www.openstreetmap.org/copyright
- Download source: https://download.geofabrik.de/asia/malaysia-singapore-brunei.html
- Singapore surveying frame: EPSG3414 (SVY21), WGS84 input EPSG4326. One metre is one world unit; -X north,-Z east,+Y up.

`game/tools/geodata/extract_singapore.py` produces attributed1km data tiles from a country-filtered PBF. The national boundary is required; no rough bbox is presented as complete country coverage. Unknown building heights/names remain unknown. The raw PBF stays outside public source Git. Snapshot manifest records checksum, source timestamp and every tile hash.

This pipeline does not by itself replace the current fictional/compressed city. Runtime migration, source completeness audit, real-world building/road alignment, and visual/gameplay verification remain part of the active goal. Do not call projected source data a completed one-to-one city.
