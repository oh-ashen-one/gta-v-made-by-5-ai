# Wave 02, R2 — isolated visual critique

**Reviewer:** fresh-context GPT-6 Astra, same model as the builder; no implementation authorship in this review. **Date:** 2026-10-21. **Visual result: REWORK.** This is a still-image critique, not owner acceptance, a different-model review, or verification of gameplay, motion, performance, or a runnable candidate.

The R2 images clearly improve on the baseline. The pavilion has actual roof construction, trees have branches and leaves, paving has readable detail, and the residential blocks have more contrast. The result still reads as a sparse game prototype rather than a convincing inhabited Singapore district. It remains far below the requested contemporary AAA target. Replacing a flat surface with many repeated tiles is progress, but it does not supply the missing human-scale spaces and activity.

## Evidence and scope

I used `view_image` on all nine images below. I read END_GOAL's world, art and verification requirements; I did not read builder LOOP files, implementation notes, or source code. The external VI/SG reference board was not visually inspected in this bounded review; the three local concepts are the directly inspected visual targets. Their visual richness does not establish any candidate runtime behavior.

| Target images actually viewed | Candidate and baseline images actually viewed |
| --- | --- |
| `docs/concepts/singapore-on-foot.png` | `docs/wave-02/r2/photo_01_street_heritage.png`, `game/captures/photo_01_street_heritage.png` |
| `docs/concepts/singapore-driving.png` | Street and hawker comparisons; this concept provides an additional street/material/foliage target, not a matched driving test |
| `docs/concepts/singapore-helicopter.png` | `docs/wave-02/r2/photo_06_aerial_district.png`, `game/captures/photo_06_aerial_district.png` |
| On-foot concept's open-sided hawker area | `docs/wave-02/r2/photo_03_hawker_interior.png`, `game/captures/photo_03_hawker_interior.png` |

The baseline and R2 use comparable fixed viewpoints. The concept cameras and layouts differ, so ratios and composition are compared qualitatively; no exact world dimensions are claimed from pixels. Repository HEAD during review was `66127eef1edd6531466d9892fe5ae2bbf9f92bb0`, with uncommitted concurrent builder changes. HEAD does not identify the rendered R2 build. Image hashes below identify the reviewed artifacts.

## Scores

Scale requested for this review: **0–10, with 8 representing the AAA threshold**. Scores judge visible fidelity against the target, not effort or improvement. They are not acceptance gates and should not be averaged to hide weak categories.

| Category | Baseline | R2 | Visible reason |
| --- | ---: | ---: | --- |
| Geometry | 3.0 | 4.0 | Trusses, roofing and dimensional tree branching improve silhouettes. Far stalls remain closed rectangular boxes, background towers are plain slabs, and repeated buildings lack the target's varied close-detail hierarchy. |
| Materials | 1.5 | 3.0 | Stretched gray ground is replaced with paving/grass. Repeated dark grout dominates large areas; near tabletops look crumpled and mirror-like, stools are highly glossy, tree trunks lack bark detail, and many distant surfaces remain flat. |
| Lighting | 2.0 | 3.5 | Tree shade and stronger contact/roof shadows create depth. Aerial distance is still washed out, the sky/horizon transition is abrupt, and the hawker lacks the warm, inhabited stall-light contrast visible in the concepts. |
| Density / composition | 1.5 | 2.5 | More trees and tables help. Huge unoccupied foreground/plaza areas, sparse dining activity and long identical rows still dominate. The street shot frames a grass field and distant facades rather than a close, inhabited street corridor. |
| Singapore identity | 3.0 | 4.0 | HDB-like slabs, contiguous pitched-roof frontage, a red open pavilion and broad tree branching are recognizable cues. The combination is still diagrammatic; useful sheltered walking edges, active hawker stalls and layered tropical planting are weak. |

## Largest gap — inhabited space at believable scale

**Observed:** the street frame spends much of its lower half on an empty lawn. The hawker has isolated table sets separated by expanses of exposed paving, with a distant row of opaque boxes labeled “Bakery,” “Repair Shop,” etc. There is no visible queue or occupied dining cluster comparable to the target. The aerial frame repeats isolated slabs and thin shophouse rows around broad, largely empty paved zones. These are three views of the same spatial weakness, not three independent asset defects.

**Inference:** layout spacing and lack of adjacent activity, rather than a shortage of polygon detail alone, are the strongest causes of the prototype impression. The pixels cannot establish whether unseen crowds exist elsewhere or whether dimensions in code are correct.

**Bounded correction:** finish one contiguous 40–60 m heritage-to-hawker frontage before spreading additional detail across the map. Bring modeled stall fronts, dining and the sheltered pedestrian edge into direct adjacency. Proposed authoring checks: table height about 0.72–0.78 m; 1.8–2.4 m clear local aisles; one 3 m main aisle; a reference adult around 1.7 m. These are proposed validation dimensions, not measurements extracted from the PNGs. Place at least 8 visually distinct open stall fronts and a credible mix of seated diners, a short queue and passers-by in this segment. Target 12–20 visible adults distributed through the matched hawker/street review views, without filling circulation routes. Show counters, display cases, serving openings and practical stall lighting rather than signs over sealed boxes. Retain the original fixed shots and add a close street-facing reverse angle; a camera change alone cannot close this finding.

**Retest:** both fixed ground shots must show a continuous occupied middle ground and a clear path through it; the aerial shot must show the same finished segment. Review should identify a dining area, stall edge and walking corridor without relying on labels. This addresses WORLD-02/03/07 and ART-01/03/08; motion and density persistence still need separate runtime evidence.

## Three secondary gaps

1. **Foliage needs denser crowns before smoother trunks.** In the concepts, overlapping broad crowns form shaded street rooms; foliage is clustered at several scales, with irregular, fine silhouettes. R2's foreground tree exposes many long straight branches through large gaps, and its broad individual leaf/card shapes read as scattered flat shards. The aerial trees repeat similarly thin crowns. The R2 trunk already looks comparatively smooth and plastic; smoothing alone would emphasize that appearance. First build layered, asymmetric crown masses with several branch-tip clusters, reduce visible sky gaps inside a mature crown to roughly 15–30% at the matched ground camera, and ensure neighboring crowns overlap in selected street stretches. Use smaller leaves within denser clusters, with orientation/color variation, not uniformly scaled giant leaves. Aim for a few pixels per medium-distance leaf cluster and subpixel individual leaves, judged at the actual 1280×720 output; nearby leaves can resolve larger. Then improve branch taper, junction shape and restrained bark roughness. Add silhouette segments only where corners visibly kink. Keep some gaps, trunk visibility and species variation; an opaque green ball would fail too. Recheck close ground and aerial views together. Crown occupancy and screen-space leaf size are proposed visual checks, not a claim about the current mesh counts.

2. **Surface scale and response remain conspicuous.** R2's paving is a strong repeating grid through nearly every open space; nearby metal tables produce highly distorted, almost liquid reflections. Break the large paved field into plausible paths, planter edges and service strips, with coherent curb/drain transitions. Use at least three restrained paving variations while preserving a consistent physical scale, and tune the table surface so its flat shape is legible under the existing lighting. Inspect one table at close range and one 15–20 m ground patch under the same camera/exposure; grout should not become the dominant distant pattern. Do not substitute random high-frequency noise for wear. ART-04 remains visibly unresolved.

3. **The aerial composition exposes the unfinished envelope.** A ring of plain pale towers sits against a broad, light void and a hard horizon band. The concepts instead layer complete low roofs, foliage, waterways and a materially differentiated skyline. Finish the most visible background silhouettes with varied heights, roof forms and believable facade shading; use a continuous terrain/water boundary and restrained distance haze. At the same aerial camera, require no blank unbounded strip directly behind the built district and no obvious plain-box skyline silhouette in the central review area. Keep the foreground readable while tuning exposure; extra fog cannot count as completing the envelope. This is ART-07/08 and WORLD-06, with aerial traversal still NOT TESTED.

## Limits and artifact identity

Still images do not verify walking/driving/flight, crowd behavior, animation, collisions, frame rate, or the continuity of the district. I saw visible NPC shapes but cannot establish their adult proportions, rig quality or behavior at this screen size. I did not inspect asset source files, so foliage and material causes are hypotheses for the builder to test. The shared-brain doctor reported `not-recently-checked`; this review used the supplied cached policy and did not publish, spend, alter infrastructure, or launch engines.

SHA-256 of the reviewed R2 images:

```text
d2c3c98f0df7a51a1da45c63c20b20ac13014e471d172f9f94ba7a305d4cdfbd  photo_01_street_heritage.png
4714eda15827429c979fd73f52b511d7bc83b9ff9ca64f536fcc933c6c153f2a  photo_03_hawker_interior.png
49eb8a059de15f6f61933afff5646ff4083e761e74cbcec06a408c382159121b  photo_06_aerial_district.png
```

**Handoff:** measurable progress over baseline; visible fidelity remains approximately 3–4/10 depending on category. Correct the occupied street/hawker composition first, crown density second. No full visual, independent-model, or owner-acceptance claim is supported by this review.
