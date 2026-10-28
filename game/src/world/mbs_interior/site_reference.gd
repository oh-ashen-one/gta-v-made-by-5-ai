extends RefCounted
## Generated factual source reference. Data: © OpenStreetMap contributors,
## ODbL1.0; code and new procedural structure are original project code.
## Generated from research/site-audit/mbs-source-components-r1.json.
## Footprints are not an as-built L1 floorplan or a verified entrance survey.
const DATA := {
  "schema": "mbs_public_interior_source_reference_v1",
  "source": {
    "source_url": "https://download.geofabrik.de/asia/malaysia-singapore-brunei.html",
    "pbf_sha256": "5e598c8a82e5decfd0b4cf56ef57b9ff2012409657b373e4bc0abd3d0fc461cd",
    "source_snapshot_utc": "2026-10-27T21:23:59Z",
    "data_license": "ODbL-1.0",
    "license_url": "https://www.openstreetmap.org/copyright",
    "attribution": "© OpenStreetMap contributors",
    "parse_errors": {
      "area_geometry": 3
    }
  },
  "coordinate_frame": {
    "source_crs": "EPSG:4326",
    "survey_crs": "EPSG:3414",
    "origin_easting": 30000.0,
    "origin_northing": 30000.0,
    "world_axes": {
      "x": "south",
      "y": "up",
      "z": "west"
    },
    "metres_per_unit": 1.0,
    "distance_compression": false,
    "legacy_plan_alignment_applied": false
  },
  "origin_world_xz": [
    461.80526720843324,
    -1030.482512158889
  ],
  "axis_south_xz": [
    0.9147652463748762,
    0.4039858215639653
  ],
  "axis_bayward_xz": [
    -0.4039858215639653,
    0.9147652463748762
  ],
  "tower_order_north_to_south": [
    "T3",
    "T2",
    "T1"
  ],
  "towers": [
    {
      "id": "way/172307471",
      "tower": "T3",
      "name": "Marina Bay Sands Tower 3",
      "centroid_world_xz": [
        343.82889930719983,
        -1077.8979211752164
      ],
      "centroid_local_xz": [
        -127.0758342158373,
        4.286811600926107
      ],
      "footprint_rings_world_xz": [
        [
          [
            363.9355,
            -1055.3495
          ],
          [
            372.3499,
            -1085.2648
          ],
          [
            319.893,
            -1100.2107
          ],
          [
            318.9753,
            -1096.9498
          ],
          [
            315.4812,
            -1084.5185
          ],
          [
            323.4979,
            -1082.2371
          ],
          [
            321.187,
            -1074.0126
          ],
          [
            319.5063,
            -1068.0029
          ],
          [
            363.9355,
            -1055.3495
          ]
        ]
      ],
      "source_long_extent_m": 58.41183710181086,
      "source_cross_extent_m": 37.138651366796,
      "source_height_m": 193.0,
      "height_status": "source_tag"
    },
    {
      "id": "way/172307472",
      "tower": "T2",
      "name": "Marina Bay Sands Tower 2",
      "centroid_world_xz": [
        441.6952525684337,
        -1046.407586580947
      ],
      "centroid_local_xz": [
        -24.829446770623942,
        -6.443543841228605
      ],
      "footprint_rings_world_xz": [
        [
          [
            458.5548,
            -1010.4888
          ],
          [
            479.6852,
            -1056.3969
          ],
          [
            424.8619,
            -1082.305
          ],
          [
            418.5151,
            -1068.6939
          ],
          [
            403.7426,
            -1036.3969
          ],
          [
            458.5548,
            -1010.4888
          ]
        ]
      ],
      "source_long_extent_m": 61.389934768069395,
      "source_cross_extent_m": 52.08350999933495,
      "source_height_m": 193.0,
      "height_status": "source_tag"
    },
    {
      "id": "way/116801004",
      "tower": "T1",
      "name": "Marina Bay Sands Tower 1",
      "centroid_world_xz": [
        543.18424816395,
        -989.8570443379905
      ],
      "centroid_local_xz": [
        90.85477655755574,
        4.286811600926114
      ],
      "footprint_rings_world_xz": [
        [
          [
            552.3119,
            -951.7166
          ],
          [
            581.8681,
            -994.5531
          ],
          [
            534.0551,
            -1027.9958
          ],
          [
            530.5168,
            -1022.8652
          ],
          [
            504.4989,
            -985.1593
          ],
          [
            539.7505,
            -960.5085
          ],
          [
            552.3119,
            -951.7166
          ]
        ]
      ],
      "source_long_extent_m": 66.97969328921955,
      "source_cross_extent_m": 62.402072834149415,
      "source_height_m": 193.0,
      "height_status": "source_tag"
    }
  ],
  "retail_reference": {
    "id": "relation/2298319",
    "centroid_world_xz": [
      394.22338107447695,
      -853.1510850333009
    ],
    "built_by_this_module": false
  },
  "topology_sources": [
    "MBS-KIOSK",
    "SAFDIE-HOTEL"
  ],
  "metric_limit": "Tower footprints/centroids are OSM source geometry, not surveyed L1 atrium/door/floor geometry. Stage dimensions are explicit assumptions.",
  "full_requested_interior_verified": false
}

## Primary historical engineering reference, read online 2026-10-28.
## Paraphrased facts only; source PDF/images remain outside the repository.
const ATRIUM_ENGINEERING := {
  "source_id": "ARUP-JOURNAL-2012-1-ATRIUM",
  "source_url": "https://www.arup.com/globalassets/downloads/arup-journal/the-arup-journal-2012-issue-1.pdf",
  "publication": "The Arup Journal 1/2012, printed pages 17-23; atrium pages 21-23",
  "authors": ["Brendon McNiven", "Xiaofeng Wu"],
  "temporal_status": "HISTORICAL_ORIGINAL_ENGINEERING_NOT_2026_FITOUT_SURVEY",
  "continuous_atrium": true,
  "height_storeys_approx": {"T1": 20, "T3": 6},
  "approx_width_m": {"T1": 40.0, "T2": 20.0, "T3": 10.0},
  "link_wall_vertical_span_m": {"T1_T2_max": 47.0, "T2_T3_min": 27.0},
  "form": "One connected atrium with declining northern profile; glass linking walls follow tower surfaces, vertical west and inclined east; steel wall/roof trusses and horizontal transoms.",
  "unresolved": ["current exact atrium roof elevations", "storey-to-metre section conversion", "precise current L1 boundaries", "entrance metrics", "2025-2026 refurbishment fitout", "full private floor and room inventory"],
  "source_pdf_committed": false
}
