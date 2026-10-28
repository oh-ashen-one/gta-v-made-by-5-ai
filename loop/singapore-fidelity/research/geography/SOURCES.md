# Real geography sources and access results

## Selected reusable source

- https://download.geofabrik.de/asia/malaysia-singapore-brunei.html : OSM PBF downloaded28October2026,252467256bytes, SHA2565e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd. Header data timestamp2026-10-27T21:23:59Z.
- https://www.openstreetmap.org/copyright : attributed ODbL database, separate from original-code MIT license. Country admin2 geometry filters the snapshot, preserving crossing features; it is not a rough Singapore bbox.906tile JSON files copied/verified against their hashes.
- WGS84 input is projected to official Singapore SVY21 EPSG3414, then mapped at one metre/unit with-Xnorth/-Zeast. Projection tests include invertibility across island controls and a centimetre-level numeric control. This coordinate frame is not the old compressed DowntownPlan.

## Other primary sources investigated

- https://www.onemap.gov.sg/apidocs/ : official SLA search/roads/geocoding APIs. The single public search request returned an authentication error along with partial results. No authenticated account/token or complete API access has been verified. Do not claim it works without credentials.
- https://www.sla.gov.sg/geospatial/digitised-land-information/ : official street directory, road-centreline/kerb and building-outline datasets are available through licensing. No paid licence acquired.
- https://data.gov.sg/datasets/d_95a29fbb10cf94a3c263d33861d7b6c6/view : open-data2019indicative road kerb/divider GeoJSON obtained through the documented public download API.5.6MB, SHA2567bbaa7a2897ac71bbbd2382ba46383030ce5efbf792d8ba9a51a9966266cd053. It is dated planning geometry without street names, not the current full street network. Signed download URLs remain private/transient, not source credentials.
- https://developers.google.com/maps/documentation/tile/policies : Google tiles investigated but not extracted/traced into offline game geometry; policy restricts extraction/offline use. No API billing enabled.
- https://wiki.openstreetmap.org/wiki/Overpass_API : two bounded source-research queries supplement MBS site/indoor coverage, with source timestamps recorded. Neither proves all private rooms or every height.

## Current limits

The source has257845road/path ways (including service/foot/cycle/construction/proposed ways), not that many named streets. There are5541distinct name strings and81680namedways.131259of135415building records lack explicit source heights. Three area geometry parse errors remain unresolved. OSM source coverage is not an as-built survey guarantee. Runtime terrain, roads, structures, signage, mission placement and fullMBSinterior still need migration and verification.
