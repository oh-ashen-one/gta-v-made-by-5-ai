# Terrain data credits and limitations

Mapzen public Terrain Tiles / Tilezen Joerd composite. Credit SRTM and GMTED2010 to the U.S. Geological Survey, and global ETOPO1 to the U.S. National Oceanic and Atmospheric Administration. Country-intersecting coverage selection is derived from © OpenStreetMap contributors, ODbL1.0; DEM height sources and their terms remain separate from OSM and from the game code license.

Primary source references:

- https://registry.opendata.aws/terrain-tiles/
- https://raw.githubusercontent.com/tilezen/joerd/master/docs/attribution.md
- https://raw.githubusercontent.com/tilezen/joerd/master/docs/data-sources.md
- https://raw.githubusercontent.com/tilezen/joerd/master/docs/formats.md
- https://www.mapzen.com/blog/terrain-tile-service/
- https://www.openstreetmap.org/copyright

The public S3 objects were fetched anonymously via ordinary HTTPS GET, without an account or API key. Raw source checksums, HTTP response metadata and exact URLs are recorded in manifest.json. April2016 server modification dates are not measurement dates. Per-pixel source imagery, measurement age and effective resolution are not independently established here. Underlying provider terms/disclaimers apply; this is not a blanket MIT claim for data or a navigation product.

Modifications: the two gzip HGT rasters were decoded as big-endian signed16-bit posts; bilinear values were projected into an uncompressed25m global grid, stored as little-endian float32 in1km chunks with a one-post halo. No missing-value fill, smoothing, building/canopy removal or invented sub-resolution detail was applied. The25m derivative spacing does not improve the native1arcsecond posting or coarser contributing datasets.

Elevation is EGM96 geoid metres. It is not automatically aligned with the game’s worldY or architectural floors and is not current surveyed Singapore ground, current reclaimed land, MBSL1, physical support, dryland, tidal level, sea surface/bottom, or3D hydrology. Source zeros are values; missing/void/error samples remain unknown. No warranties or source endorsement are implied.
