# Critic review 5 — rendered captures (fresh-context Opus)

**Scope: this is a review of still renders only.** I did not play the build or watch motion, so popping, animation, frame pacing, traffic behaviour and audio are **unproven**. Paths are relative to `waves/05/evidence/rendered/` (concepts are in `docs/concepts/`). I looked at 21 images and ran pixel diffs and luminance probes (PIL) for the numbers below.

## 1. Opening frame and first minute: does it read as Singapore?
Yes, at a glance. `candidate-gameplay/photo_01_gameplay_opening_start.png` is a big improvement: the baseline started inside a beige safe room. Now you get a green shophouse row, a hawker shed signed "…EMBUSU FOOD CENTRE", MBS, Supertrees and the Flyer all in one frame. It still looks like a sparse low-poly diorama, not a city.
| Element | Verdict | Evidence |
|---|---|---|
| Marina Bay Sands (3 towers + SkyPark) | **Recognizable.** Towers are straight extruded slabs with sparse white window dots, no curved profile, and the SkyPark is a flat plank | photo_01 opening, `candidate-photos/photo_05_waterfront.png`, `photo_16_bay_skyline_aerial.png` |
| Supertree Grove | **Recognizable but wrong.** Magenta and white wireframe "cocktail glasses" with no canopy mass and no rust or purple steel | `candidate-photos/photo_07_aerial_waterfront.png`, `candidate-gameplay/photo_07_gameplay_supertree_grove_vista.png` |
| Singapore Flyer | **Recognizable.** White wire ring, though there is no capsule detail | photo_01 opening (top right), photo_16 (right edge), `candidate-route/08_helicopter_boarding.png` |
| ArtScience Museum | **Weakly recognizable.** A small white lotus on the far shore | photo_16, `candidate-route/09_aerial_view.png` |
| Merlion | **Not recognizable.** At aerial range it is a white blob a few pixels wide (photo_16 at about x640,y540). Up close it is a faceted white mass cropped at the frame edge, with an opaque white ribbon for the water jet | `candidate-gameplay/photo_06_gameplay_waterfront_promenade.png` |
| Shophouse five-foot ways | **Present.** Colonnades, shutters and pastel fronts, the best asset in the game | photo_01 opening, `candidate-gameplay/photo_02_gameplay_heritage_arcade.png`, `candidate-route/05_car_entered.png` |
| HDB slabs / void decks | **Present.** Slabs read as HDB. The void deck works as geometry but is an unlit cave | `candidate-route/05_car_entered.png`, `candidate-photos/photo_04_housing_void_deck.png` |
| Hawker centre | **Present and good.** Red timber roof, yellow stools, stalls with signage | `candidate-route/02_hawker_market.png` |
| Tree canopy | **Partial.** Rain trees line the avenues, but there is no overhanging canopy and nothing shades the street the way the concepts do | photo_02 heritage_arcade, photo_07 vista |
| Left-hand traffic cues | **Weak.** Double-yellow kerb lines sit on the left side, and the car drives the left carriageway (`candidate-route/06_driving.png`). There is almost no other traffic, so it is not proven | 05_car_entered, 06_driving |

## 2. Candidate vs wave-4 baseline (same fixed cameras)
- **Better:**
  - The opening frame (`*/photo_01_gameplay_opening_start.png`, 82% of pixels changed by more than 30) goes from an interior room to a landmark street. This is the single biggest win.
  - The Supertree vista (`*/photo_07_gameplay_supertree_grove_vista.png`): the baseline was a blurry wall in an alley, and the candidate actually shows the grove.
  - MBS in `photo_06_aerial_district` is larger and has correct three-tower proportions.
- **Worse or regressed:**
  - `candidate-photos/photo_06_aerial_district.png` has lost the Singapore Flyer and the right-hand Supertree cluster that the baseline showed. The skyline is now emptier on the right, apart from two dark generic towers.
  - The waterfront (`photo_05_waterfront`, 77% changed) now faces MBS across the bay, but the foreground is an empty paved plaza. The baseline at least had a car, pedestrians, trees and the Supertrees in frame.
- **Unchanged:**
  - `photo_04_housing_void_deck` (mean diff 0.57), `photo_10`, `photo_12` and `photo_14` are effectively identical. The void deck is still about 70% unreadable (the lower third has mean luminance 14/255).

## 3. Visual defects (worst first)
1. **Broken minimap.** In `09_aerial_view`, `11_delivery`, `06_gameplay_waterfront_promenade` and `07_gameplay_supertree_grove_vista`, the top half of the minimap is solid black or teal and the player arrow is pinned to that edge, so there is no map data near the bay. In every frame it is also an empty grid with no roads or landmarks.
2. **Ammo HUD unreadable on bright backgrounds.** The text is white over pixels with median luminance 217 in `09_aerial_view` and 235 in `11_delivery`. "PISTOL" vanishes into the tree in photo_01 opening. In `06_driving`, `05_car_entered` and `08_helicopter_boarding` the first digit of "3 / 96" is clipped or ghosted. There is no backing panel, unlike the objective box.
3. **Empty world.**
   - In `06_driving` the boulevard has zero traffic, bare plazas and flat generic towers. This is the driving showcase frame and it reads as a test map.
   - In `08_helicopter_boarding` a vast blank plaza surrounds the pad.
   - The aerial shots (`photo_06`, `photo_07`) are dominated by untextured beige box roofs.
4. **Blown-out sprite.** `09_aerial_view` has a pure-white glow beside the helicopter: 13% of the 90x100 region is at 255. It looks like a bugged light or a lens artefact.
5. **Water does not read as water.**
   - In `photo_05_waterfront` and `06_gameplay_waterfront_promenade` the bay is a flat beige or grey band, the same tone as the paving.
   - The Merlion's water jet is an opaque white solid.
6. **Scale and composition errors.**
   - The Supertrees stand directly in front of MBS and visually intersect it (`photo_07_gameplay_supertree_grove_vista`).
   - In `09_aerial_view` the MBS towers lean and splay outward like a fisheye.
   - The landmarks are packed together like a theme park instead of Marina Bay geography.
7. **Text and sign issues.**
   - The hawker sign is cropped to "EMBUSU" in photo_01 opening.
   - "ALERT!! · SPOTTED" is orange on a pastel facade in `05_car_entered`, which is low contrast.
   - "Vehicle entered. [E] to exit." duplicates the "[E] Exit vehicle" prompt.
8. **Flat lighting.** The sky is a uniform grey-pink haze. There is no golden-hour sun, no bloom on lamps and no ambient occlusion in the five-foot ways, and every shadow is the same hard blue-black.
9. **Pickup readability.** The delivery packages in `11_delivery` are small glowing green cubes clipping into a translucent slab beside the player.

## 4. Distance from the concepts (1 = nothing alike, 10 = match)
- **On foot (`singapore-on-foot.png`): 4/10.** The ingredients are right (shophouses on the left, hawker on the right, MBS at the vanishing point; `photo_01_gameplay_opening_start.png`). But there are no crowds, no canopy, no lanterns or plants, no material richness and no warm light.
- **Driving (`singapore-driving.png`): 2/10.** `06_driving.png` is an empty divided road between featureless towers. `05_car_entered.png` is closer (around 4), but the concept's river, bridge, traffic, palms and dense frontage are absent.
- **Helicopter (`singapore-helicopter.png`): 3/10.** `09_aerial_view.png` and `photo_16_bay_skyline_aerial.png` show the landmark set, but there are no dense canopy streets, no boats and no layered skyline, and the roofs are flat beige boxes. It reads as a SimCity prototype.

## Single biggest gap (testable)
**Fill the camera-facing streets and make the HUD readable.**
- The 06_driving and photo_06_aerial_district cameras must each show at least 8 moving or parked vehicles, at least 10 pedestrians, and street trees whose canopy overlaps the road.
- The ammo readout needs a backing plate so that text-to-background contrast is at least 4.5:1 in `09_aerial_view` and `11_delivery`.
- The minimap must render roads around the bay with no black half (re-shoot those same 4 frames).

## Verdict
Wave 5 is a real improvement on the wave-4 opening and landmark legibility, and the icon set now says "Singapore" in the first frame. The world is still sparse and flat-lit, the HUD has minimap and contrast bugs, and the driving and helicopter shots are far from the concepts. **Pass as an incremental wave; fail against the concept bar.**
