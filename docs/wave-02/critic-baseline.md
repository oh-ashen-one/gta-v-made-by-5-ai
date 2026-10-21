# Wave 2 visual baseline — REWORK

Reviewer: GPT-6 Astra, inherited builder settings, fresh context; same-model review, not cross-model independence or Opus acceptance. Date: 2026-10-21. Scale: 0–10, **8 = AAA**. Target: END_GOAL.md's realistic GTA VI fidelity in Singapore.

Viewed using `view_image`:

- `docs/concepts/singapore-on-foot.png`
- `docs/concepts/singapore-driving.png`
- `docs/concepts/singapore-helicopter.png`
- `game/captures/photo_01_street_heritage.png`
- `game/captures/photo_02_street_wide.png`
- `game/captures/photo_03_hawker_interior.png`
- `game/captures/photo_06_aerial_district.png`
- `game/captures/06_driving.png`
- `game/captures/09_aerial_view.png`

Only END_GOAL and these images informed this baseline. Rockstar images not inspected separately. Build identity, motion, gameplay, performance: **NOT TESTED**.

| Criterion | Score | Visible evidence |
|---|---:|---|
| Geometry/detail | 3 | Shophouse relief and balcony repetition exist; trees are tiny polygon blobs, skyline towers blank boxes, hawker ceiling an enormous featureless slab. |
| Materials | 1 | Ground becomes kilometer-scale streaks; plaster, roofs and paving are bleached; barely any credible surface wear or glass separation. |
| Lighting | 1.5 | Weak contact grounding, near-white exteriors and muddy indoor ceiling; neither convincing sun/shade hierarchy nor the concepts' rich reflected light. |
| Composition/density | 1 | Streets border vast empty ground; repeated isolated housing blocks and sparse furniture read as a test layout. |
| Character integration | 1 | Visible people are rigid block figures; no believable clothing, anatomy or crowd. `06_driving.png` shows a person indoors, not driving. |
| Singapore identity | 3 | Shophouse rows and housing balconies provide cues; missing canopy, inhabited arcades and convincing hawker activity leave a generic schematic district. |

Three independent gaps; retest with comparable captures:

1. **Surface/lighting foundation.** Remove visible stretched ground bands in all six views. At 1080p, show distinct asphalt aggregate, paving joints, plaster, glass and foliage; preserve detail in sunlit walls and shaded arcades. Three fixed sun/shade views must show grounded contact shadows without crushed interiors.
2. **One complete inhabited street.** Author a continuous 100 m route with recessed shop thresholds, sheltered walking space, drains, kerbs and broad-canopy trees. Fixed street view: ≥12 visible people, ≥4 vehicles, canopy across ≥25% of street width; no unexplained empty ground patch larger than a carriageway. Hawker view: ≥6 furnished stalls and ≥12 occupied seats.
3. **Near-camera actors.** Replace block people and placeholder hero vehicles. Demonstrate original clothed human proportions, modeled hands/hair/shoes, grounded feet; car glazing, cabin, wheels and driver. Supply actual comparable on-foot/driving/flight views with the controlled actor visible; no filename-based claims.

These are next-pass gates, not sufficient AAA acceptance. Current result is an obvious unfinished prototype.
