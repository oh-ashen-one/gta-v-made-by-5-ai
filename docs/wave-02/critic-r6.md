# Wave 02, r6 independent visual critique

Date: 2026-10-21. Reviewer: GPT-6 Astra in fresh context, the same model family as the builder, with no builder notes, LOOP, or implementation source read. This is an independently performed screenshot review, **not a different-model review, runtime certification, or owner acceptance**.

**Verdict: REWORK. Overall visual assessment: 3.8/10, with 8/10 representing the requested AAA fidelity bar.** The candidate has recognizable Singapore architectural ingredients and visible progress over r2. It remains far below END_GOAL's GTA VI-level target: empty space, repeated layout, thin vegetation, simple materials and uninhabited interiors still dominate the image.

## Evidence and limits

Read END_GOAL's world, visual and verification requirements. Opened and visually inspected all three local concept PNGs: `singapore-on-foot.png`, `singapore-driving.png`, and `singapore-helicopter.png`. They establish the warm, planted, layered, inhabited Singapore visual target. These are concept references, not game captures.

Opened each requested r6 image through `view_image`: `photo_01_street_heritage.png`, `photo_03_hawker_interior.png`, `photo_06_aerial_district.png`, `photo_08_street_arcade.png`, `photo_12_convenience_interior.png`, and `photo_14_workshop_interior.png`. Opened the matching r2 heritage, hawker and aerial images for before/after comparison. r2 contains no matching street-arcade, convenience-interior or workshop-interior shot; its `photo_08` is an airfield and is not a valid same-view comparison.

All six reviewed r6 captures are 1280 × 720. No engine was opened. Animation, traversal, contact over time, traffic flow, interior accessibility, performance and exact captured-build identity are **NOT TESTED**. External END_GOAL reference IDs VI-01 through VI-03 and SG-01 through SG-03 were read as specification anchors but their remote image binaries were not independently reopened in this bounded review; no new direct parity claim is made from them. The supplied local concepts were actually viewed. Shared-brain policy came from installed revision `ba35669bd13c`; its doctor reported `not-recently-checked`, so live cloud freshness is unverified.

## Scores

Scores are subjective visual judgments, not instrument precision or acceptance thresholds negotiated with the owner.

| Dimension | r6 score | Pixel-visible basis |
| --- | ---: | --- |
| Geometry | 4.5/10 | Shophouse relief, columns, shutters, pitched roofs, hawker trusses and housing balconies provide real depth. Background towers now have façades. Trees still expose sparse, regular forked limbs; interiors rely heavily on box/cylinder forms; large blank wall faces remain prominent. |
| Materials | 3.0/10 | Roof tiles and paving have surface information, and the worst r2 table shine is reduced. Plaster, retail products, workshop floor and fixtures are too uniform. Paving repeats at a very conspicuous scale. Tree trunks remain dark and smooth in the street capture. |
| Lighting | 4.0/10 | Direct shadows and readable interior illumination exist; skyline contrast is improved from the r2 haze. The new sky is more dimensional but its very large soft cloud has little convincing scale. The exterior lacks the concepts' warm bounce, local contrast and layered atmospheric depth. Interior fixtures illuminate rooms evenly with weak material separation. |
| Density and composition | 2.5/10 | Huge clear paving areas, wide empty roads, detached skyline objects and regular repeated blocks make the district look assembled on a grid. The hawker hall is substantially empty. The arcade has a readable vanishing point but little activity or frontage variation. |
| Actor integration | 3.5/10 | Adults are now visible in the hawker and arcade captures; clothing silhouettes and contact shadows help establish scale. The foreground arcade actor is much more credible than a primitive mannequin, but static standing poses, sparse distribution and no visible occupied dining groups undermine a living city. Motion quality is untested. |
| Singapore identity | 5.0/10 | The combination of shophouse arcades, housing blocks, roofed communal dining, rain-tree-like forms and food names is identifiable. It needs the tighter street grain, richer planting, useful street furniture, varied shop thresholds and everyday activity shown by the concepts. Names alone cannot carry the setting. |

## Largest current gap

**The world lacks convincing human-scale density and occupied use.** Adding authored objects has improved individual assets, but the spatial relationships still resemble a broad layout prototype. The concepts layer foreground plants and street fixtures, occupied storefronts/dining, traffic, mid-rise housing and distant skyline. r6 repeatedly presents large unbroken ground areas between isolated functions. This weakens both realism and Singapore identity before fine surface detail can help.

The aerial view is the clearest diagnostic: a huge paving field surrounds three central housing blocks; identical buildings repeat in separated groups; background towers stand on isolated rectangular patches with broad voids between them. The hawker roof covers many tables, but the scene lacks seated customers, working stallholders and clustered dining objects. A filled shelf in an otherwise generic room does not yet create a credible convenience shop.

## Concrete observation

In r6 `photo_01_street_heritage.png`, the rectangle **x=[850,1280), y=[330,480)** is entirely inside the blank right-hand exterior wall. Its measured area is **64,500 pixels, exactly 7.0% of the 1280 × 720 frame**. The full wall occupies more than this rectangle. No aperture, signage, service fixture or material breakup appears within it. This is a deliberately conservative screen-area observation, not a guessed world-space building size.

In the workshop capture, **six matching outlined tools** hang at even intervals on one board, beneath **three visible ceiling light bars**. This visible repetition, uniform pristine floor and otherwise empty service bay make the room read as a schematic furnishing pass.

## Progress and regressions against r2

- **Aerial progress:** r2's distant plain rectangular slabs now have window rhythms, roof profiles and stronger contrast. The foreground district is more legible because the heavy pale haze is reduced. This is a substantial improvement in completed massing, although the detached towers and repetitive spacing still expose the background layout.
- **Hawker progress:** generic solid stall boxes are replaced by counters/canopies with distinct food labels. People are visible. Tables and seats no longer have the same extreme reflective appearance as r2. Roof tiles are more legible. The sparse hall arrangement is still unresolved.
- **Heritage regression:** the new large white service-building face blocks the right-side frontage/tree corridor that was visible in r2. The evidence frame now reads primarily as a blank side wall opposite a distant pavilion; it is a poor representative heritage street composition. This is a real before/after obstruction, regardless of whether the building itself serves a useful gameplay function.
- **Heritage tonal regression:** the foreground tree and grass patch are markedly darker in r6 than r2, reducing trunk/ground surface readability. The improved sky and reduced aerial haze do not compensate for this local loss.
- **New capture artifact:** the convenience-shop image contains pale ragged horizontal fringes along the lower-left edge beneath/around the minimap and health region. The screenshot proves the artifact exists; its cause and persistence are untested. Do not attribute it to a specific renderer or geometry bug without a follow-up capture.
- **Comparison limit:** the arcade and two enclosed interiors expand the evidence set, but their improvement relative to r2 cannot be scored from equivalent absent views.

## Three actionable corrections, in priority order

1. **Finish one compact, inhabited street-to-hawker segment at the actual gameplay camera scale.** Reduce excessive separation between the usable edges: add a coherent curb/drain/planting strip, occupied shop thresholds, trays and table settings, stall operators, seated pairs/groups and a small queue. Keep a clear circulation aisle. Populate the near/middle/far bands with varied poses and clothing; verify feet, seats and shadows in moving footage. Retake heritage and hawker images from the same cameras. Acceptance for this iteration: the hall visibly has dining and selling activity, and the street has layered human-scale detail without relying on a UI title.

2. **Repair the heritage obstruction and large empty surfaces before extending the map.** Move or redesign the new service block so the heritage evidence view and playable approach retain a useful sightline; give any visible service face a plausible door, vents/condensers, drainpipe and grounded material variation. Break aerial paving fields into believable housing courts, planted shade, sheltered connections, service access and restrained parking. Group background towers into convincing blocks on continuous ground; avoid isolated plinths floating in broad gaps. Retake the exact heritage/aerial comparisons and demonstrate the new structure's street-facing and reverse views.

3. **Run a focused material/lighting pass on the closest surfaces, foliage and two interiors.** Establish human-scale paving/roughness variation; distinguish tile, asphalt, painted metal, concrete and glass. Give tree trunks bark relief and less regular branching with fuller layered crowns. In the shop, replace repeated colored product blocks with several authored packaging silhouettes/labels and a believable counter/refrigeration zone. In the workshop, use varied tools, a credible working vehicle/service assembly, task clutter and localized wear. Preserve readable shadow detail under the trees and add plausible local light/bounce inside. Recapture the convenience view at the same angle and one shifted angle to isolate and eliminate the torn fringe.

The next critique should inspect these corrected views plus an uncut walking route through them. A better still-image score cannot close END_GOAL's gameplay, performance, provenance or owner-acceptance gates.
