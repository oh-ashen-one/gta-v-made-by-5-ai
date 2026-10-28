# Source-supported coastline assembly

Administrative territory includes sea. The exact Singapore country polygon is a clipping boundary, **not** a land surface. This stage recovers original `natural=coastline` source ways/nodes and assembles only supported closed directed rings before clipping any land. No country rectangle, territory polygon or open-chain closure is substituted for land.

The builder owns only `game/tools/geodata/extract_coastline.py`, `test_coastline.py` and this notes directory. No earlier canonical dataset/tool, engine/GPU/UI, Git state, account or API was changed. This is data toward the full Singapore goal, not a permanent reduced city or accepted terrain.

## Source and operational method

The same original private PBF is verified by exact SHA256:

`5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd`

The exact canonical country is separately pinned:

`c25cce8de57f280b68bd1436deedc3eaa3eb8bebf50ec334f5d9dbfd826b9c45`

A C++ tag filter retains `natural=coastline` way objects only. A second C++ ID filter retains only their required original node records. No full source-node location cache is built. Original way/node IDs, every ordered reference, source longitude/latitude, tags and available revision/time are retained in a separate attributed source catalog. Header timestamp and uncompressed projection frame must match the canonical source. The raw PBF stays private; no source paths/credentials are copied to outputs.

All actual work runs in Darwin background class/nice10. A task-owned supervisor samples worker RSS every second with2GiB budget; CPU soft limit240s (+15s hard grace), wall limit600s. Additional caps:50,000 coastline ways,1.5million selected nodes,2million node references,128MiB each compiled report/source catalog. A bound failure stops the run as incomplete; no retry or relaxed limit is automatic. Memory supervision is sampled rather than a kernel hard memory limit.

## Assembly contract

- Original node identity and directed segment incidence drive joins. No coordinate snapping, same-XY merging, endpoint reversal or duplicate removal is used to close a chain.
- Open/direction-mismatched components, degree branches/retraces, missing/invalid nodes, duplicate source observations and invalid closed polygons remain explicit unresolved components. No `buffer(0)` or other repair is used.
- OSM coastline has land on its left. Our Godot XZ frame reverses WGS84 east/north handedness: a negative signed XZ ring area is a land interior; a positive area is a water interior.
- Supported strict nesting assigns coastline water holes and nested land islands. Coincident/overlapping rings, ambiguous boundary contact, same-orientation nesting and orphan water rings are excluded and reported. No outside land is invented around an orphan water ring.
- Separate valid source polygons remain separate. They are not XY-unioned. Each is intersected with the exact projected country **after** assembly; only polygonal area fragments are retained. Original source rings/IDs remain intact in the catalog even where derived country clipping creates vertices.
- Geometry is projected directly with current SVY21 EPSG3414 origin E30000/N30000, Godot -X north/-Z east, one metre per unit. No distance compression, simplification or coordinate quantization is added. Output land geometry is explicitly **Godot XZ metres**, not longitude/latitude.

`source-catalog.json` holds original ways/nodes once. `coastline.json` holds binding, source closed rings, unresolved components, assembly issues, country-clipped independent land features and limits. Both are SHA256-bound by the worker receipt. Output directories/files are not overwritten.

## Honest terrain/water limits

A supported coastal enclosure is not an independently verified dryland/elevation model. Ordinary inland `natural=water` ways are not coastlines and are not silently converted into coast rings or terrain holes. Inland water, elevated fountains/reservoirs and their terrain treatment require a separate verified source-supported layer. Every terrain elevation and tide datum remains unknown; source `ele`/tidal tags are strings, not inferred ground heights.

Known-chain envelope disjointness is scope metadata only. It does not prove where land lies on the unclosed side or where unmapped continuation might go. If the Singapore coast belongs to an open mainland component beyond the PBF extent, that is an unresolved coverage gap; administrative sea boundaries will not be used to fake a closed mainland surface. Whole-country land completeness and source survey/mapping completeness remain uncertified regardless of valid ring count.

This output does not build high-quality terrain, buildings/interiors, materials, collisions/navigation or the playable city, and does not prove visual/gameplay/performance acceptance.

## Tests and invocation

```sh
/private/tmp/orchard-geodata/venv/bin/python -m unittest discover -s game/tools/geodata -p test_coastline.py -v
```

**14 tests passed**: native exact tag filtering/coast-versus-water distinction, directed islands and node-identity joins, holes/nested islands, orphan water rings, open/branched chains, sameXY/different IDs, missing/invalid/duplicate nodes, invalid closed polygons without repair, overlapping/nesting conflicts, exact projection/no scale, country clipping without sea fill, exact source/country binding and overwrite safety.

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python game/tools/geodata/extract_coastline.py \
  --pbf <private-exact-input.osm.pbf> \
  --expected-pbf-sha256 5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd \
  --snapshot-manifest game/data/geography/osm-2026-10-27/manifest.json \
  --country game/data/geography/osm-2026-10-27/singapore-boundary.geojson \
  --expected-country-sha256 c25cce8de57f280b68bd1436deedc3eaa3eb8bebf50ec334f5d9dbfd826b9c45 \
  --output-dir <new-private-coastline-directory> \
  --max-rss-mib 2048 --max-cpu-seconds 240 --max-wall-seconds 600
```

## Observed actual result

The source pass completed under its original bounds in `/private/tmp/singapore-fidelity/coastline/coast-r1`:

- 3,477 source coastline ways and252,403 selected original nodes retained.
- 1,200 valid directed closed rings, all land-interior orientation in this actual extract; zero source coastline water-interior rings. Synthetic tests exercise supported water holes/nested islands.
- 64 independent source-supported country-clipped coast-enclosed features.
- Four open source components remain explicitly unresolved. None of their **known source polylines** intersects the exact Singapore multipolygon. One broad component envelope overlaps the country, illustrating why envelope scope alone is conservative; its actual source linework is disjoint. Missing/unmapped continuation is still not invented or certified.
- All331 matched source coastline ways whose known polylines intersect the exact country are present in supported closed rings. No such way is omitted from the closed-ring source assembly.
- No missing/invalid node, branch, polygon/nesting conflict or source-repair exclusion occurred in this actual input.

Source probe points at MBS (103.8608,1.2834), central main island (103.8198,1.3521), Sentosa (103.8285,1.2494) and Jurong Island (103.7045,1.27) fall inside the supported **source** coast-enclosed surfaces. These are point-in-polygon data checks, not game renders or claims that the runtime city has migrated.

Summed country-clipped coast-enclosed area is776,383,088.516m². This is **not a certified Singapore dryland statistic**: ordinary inland water is a separate still-required layer, and terrain/tide/survey completeness is unresolved. Do not label this area as the completed dryland terrain or fill enclosed inland water blindly.

Files:

- `coastline.json`:10,288,724 bytes; SHA256 `77abd458b3ec6a83eab2c2c076dcf078f1fee00d5ee15bb8a41787422050104e`.
- `source-catalog.json`:46,359,554 bytes; SHA256 `d93d15015c16b6985903318e3e0223f140304e96b6f2f81115dfcdbda25b1d20`.
- `worker-receipt.json` / `supervisor.json`: actual completion/resource receipts.

Actual resources:39.321 CPU seconds,34.566 worker wall seconds (37.554 supervisor wall), kernel peak RSS2,086,436,864 bytes (~1.943GiB). This stayed below the2GiB supervised limit but with a modest margin; no limit was increased. No full location cache, engine or GPU process was created. Larger/newer inputs may hit the bound and must stop as incomplete rather than silently increase it.

`verification-r1.json` in this folder and private `/private/tmp/singapore-fidelity/coastline/inspection-r1.json` preserve exact hashes, source/projection bindings, unresolved component endpoint coordinates, known-line/country checks, source point probes and resource receipts. All14 tests passed.

The source-supported coast boundary is ready for independent data critique and later terrain integration. Whole-country mapped/survey completeness, inland water/elevation/tides, detailed terrain, full one-to-one city/architecture/interiors and rendered/gameplay/performance acceptance remain open. No canonical v1 data or earlier source tool was changed.

## Independent integration audit

A fresh critic reran14tests, independently read all3477rawcoastlineways and252403source nodes, reconstructed1200directedrings/nesting and all64countryclippedfeatures, and found zero projected-coordinate difference, zero symmetric-difference area and no duplicate area. All331knownSGintersecting coastlines belong to supportedrings; fourglobalopencomponents stayunresolved. No P1/P2 remained in the exact artifact. Its776.3830885km² is coast enclosure, not certified dryland.

Reviewed runtime coastline and compressed original-source catalog are tracked undergame/data/geography/coastline/osm-2026-10-27 with independent identity hashes. The catalog gzip decompresses to the reviewed rawSHA; canonicalv1manifest remains unchanged. Extractor peakRSS was1.943GiB under its2GiBbound. Independent critic readback separately reached2.165GiB; do not claim everyphase stayedunder2GiB.
