# Independent downtown rooftop support review — R4

Verdict: **bounded source-and-frame acceptance for the patched `DowntownRoof_*` structural family and the ten recorded actor fixtures. No concrete P1/P2 remains in this reviewed patch.** This closes the earlier distinct downtown membrane/penthouse support finding; it does not certify every world roof, a continuous city flight, animation quality, performance, geographic fidelity or human play acceptance.

The reviewer used read-only source/evidence inspection and wrote only this new review. No engine, GPU, UI or Git operation was performed. The parent supplied publication identifier `744cd92`; publication was not independently queried because Git was excluded from this assignment. Current roof/test identity was instead checked against the recorded run by SHA-256.

## Evidence identity and actual result

The actual evidence directory, confirmed by listing `/private/tmp/singapore-fidelity/*roof*`, is `/private/tmp/singapore-fidelity/roof-support-downtown-r4` (not the initially abbreviated `roof-downtown-rendered-r4` name).

Inspected:

- `review/report.json`: 130 results, all 130 passed, failures empty, `rendered=true`, elapsed fixture time 73.502 s.
- `run.log.meta.json`: start `2026-10-28T22:44:20.345654+00:00`, finish `2026-10-28T22:46:15.250194+00:00`, engine/supervisor exit 0, no timeout, child reaped, `fatal_errors=[]`, `all_error_lines=[]`, `classified_nonfatal_errors=[]`.
- All twenty real landed/walking PNGs, opened individually, and their binary PNG headers: every image is 1280×720 and marked successfully saved in the report.
- R3's retained report and source patch, including its two failures and the R4 test-only timing adjustment.

Artifact hashes:

| Artifact | SHA-256 |
| --- | --- |
| R4 `review/report.json` | `cdc56ececd5165aba2e1bfc37c986bbb5a58c9706144ae73fca9beb0d2f418b0` |
| R4 `run.log.meta.json` | `c32778284d35d7e5d5961ed778324e43bbf35aa64f8bd9716996f29f4a92fea6` |
| `game/src/world/downtown/roofs.gd` | `35baa05a86eb48d3e983e1dd21d2f5c088950da561545894fb6623e86c81278e` |
| `game/src/systems/fidelity_tests/roof_support_review.gd` | `e6c41db0ba1d94c3f40e223911964fd56ae5ecfd4f1d788f5c95ac5a9fa8e565` |

The current two files above and `roof_kit.gd`, `landmarks/mbs.gd`, `landmarks/fullerton.gd`, and `world_builder.gd` all matched R4's recorded source hashes at review. R4 metadata identifies pre-run checkpoint `9942666bd61b85e495d6c221d733e44ff20453fe` plus the recorded per-file hashes/source patch, so the checkpoint alone must not be mistaken for the exact tested source identity.

**Actor identity boundary:** R3 and R4 recorded the same production `helicopter.gd` hash `f5710f7875bd7970bfee4acc6ead8897984390af1a3157f946198ecf17eb9751`. The live file had since changed to `ae61a11e70a2fe4e4e9130c87e2f509bb807b6bea652edcc678dc7bb150e5c73` during active root integration. Therefore the actor results below apply to the recorded R4 version; this review does not transfer them automatically to the later actor revision. The parent was notified.

## Structural correction

`game/src/world/downtown/roofs.gd:102-170` now gives explicit structural roles to membranes, penthouse bodies/caps, condensers, cooling bodies/caps, tanks, planter bases, ducts and skylights. This is role-based rather than a material-name sweep: the thin fan discs at line 125 share `plant_dark` with penthouse caps but receive no support role; tilted solar panels at line 150 also remain decorative. Shrub MMIs go through the separate canopy emitter at lines 211-212, not the structural emitter.

At lines 190-209 the exact transform/role entries used for each production MultiMesh are retained as receipts and passed to `_emit_structural_support`. At lines 225-261 the emitter:

- Derives each box's dimensions and normalized orientation from that same instance transform, avoiding a larger generic enclosing footprint or unsupported nonuniform collider scaling.
- Derives cylindrical collision from the actual twelve-sided mesh vertices, rather than substituting an oversized smooth cylinder or rectangular box.
- Skips empty roles, identifies each collider with its instance index and structural kind, and places the native layer-1 body under the corresponding MMI, preserving its parent transform.

The R4 production world contains thirteen downtown batches, **96 structural instances** and **144 excluded decorative instances**. Every structural instance matched its shape and its native top ray with the correct body, kind and instance identity. The breakdown is 6 membranes, 3 penthouse bodies, 3 penthouse caps, 72 condensers, 4 cooling bodies, 2 tanks, 1 planter, 3 ducts and 2 skylights. Renderer-buffer versus independent CPU-submission maximum corner error is 0. No unexpected collider was found on the 144 excluded visual instances.

The test does not merely check its own metadata: `roof_support_review.gd:340-352` compares actual native box/cylinder geometry in global coordinates to authored receipts; lines 395-448 compare those receipts to renderer instance buffers and verify actual native ray owner/index. The count assertion rejects extra structural children. Selected outside-edge rays are clear for both the downtown membrane and penthouse cap. That edge probe is a sampled guard (it returns after the first clear edge), not an exhaustive perimeter survey; full primitive/transform agreement is the stronger source and runtime evidence against phantom extension here.

Earlier RoofKit coverage remains separate: 247 membranes and 247 housing roofs have matching native support and 0 renderer-receipt corner error. Existing named MBS, Fullerton and hangar positive/negative probes still pass, including tapered-bow exterior air and the Fullerton lower-terrace air gap. The downtown extension adds no water geometry or broad foliage collider generation. The existing MBS pool-liquid negative ray passes; pool stone support remains distinct from the water surface.

## R3 timing failure and false-positive assessment

R3 was **123 checks with two failures**, not a clean run: the hangar descent fixture and the final all-cases count failed. Its actual ridge ray matched the expected surface. At the wall-clock cutoff the aircraft was healthy (100), moving down at 0.9 m/s, and its collision bottom remained about 0.605 m above the roof. The test had stopped before contact; it had not demonstrated a missing roof collider.

R4 changes the descent wait from eight wall seconds to **eight simulated physics seconds with a separate 24-second monotonic wall guard** (`roof_support_review.gd:533-546`). This is appropriate for a physics/control fixture whose rendered rate varies. Comparing the recorded R3/R4 source patches confirms that the landing, health, height, gentle-touchdown, E-ownership, foot-support and walking thresholds were not weakened, and recorded production helicopter source was unchanged.

R4 still requires actual `is_on_floor()` and `is_landed()`, aircraft not disabled, health above 99.9, and the production collision bottom within 0.12 m of the selected visible roof (`:549`). It then requires touchdown speed below 1.6 m/s, a production-supported capsule exit, normal E ownership transfer, a real supported living Player, more than 2 m walking, maximum per-tick movement below 0.5 m, and the original roof-height envelope (`:552-575`). A hover, lower floor, disabled aircraft, failed exit or falling player cannot pass those gates merely because the wait is longer.

The R4 hangar actually landed after 1.7667 simulated seconds / 3.154 wall seconds, 101 driver ticks, at health 100 and zero final velocity; recorded gentle touchdown speed was 0.9 m/s. All ten cases landed in 1.7667-1.8 simulated seconds and 2.328-5.409 wall seconds. This is not a performance acceptance claim, nor proof that every machine will meet the wall guard.

## Actual actor frames inspected

For each row, both `review/landed_<case>.png` and `review/walking_<case>.png` were viewed directly. The sampled images agree with a helicopter resting on the visible selected roof and the player walking on its surface, without the prior sink-through or obvious invisible raised-floor symptom at those positions.

| Recorded case | Walk distance | Maximum foot step |
| --- | ---: | ---: |
| `mbs_pavilion_north` | 2.7927 m | 0.0601 m |
| `mbs_visible_bow` | 2.7929 m | 0.0603 m |
| `mbs_landward_edge` | 2.7927 m | 0.0600 m |
| `shoppes_wave_crest` | 2.7969 m | 0.0601 m |
| `hangar_prism_ridge` | 2.7943 m | 0.0606 m |
| `one_fullerton_eave` | 2.7927 m | 0.0600 m |
| `fullerton_upper_roof` | 2.7927 m | 0.0600 m |
| `ordinary_membrane_77` | 2.7928 m | 0.0600 m |
| `downtown_membrane_0` | 2.7936 m | 0.0600 m |
| `downtown_penthouse_roof_1` | 2.7927 m | 0.0600 m |

The two new downtown samples are a clear membrane at approximately `(-362.6154,58.50162,363.845)` and a penthouse cap at `(240.4361,31.19074,-734.6119)`. Their landing/exit/walking frames show the intended elevated surfaces. The narrow cap sample has limited surrounding room; its pass is clearance at the selected orientation/path, not a claim that every orientation or occupied roof patch is a safe helipad.

The fixture explicitly reports **20 initial actor position assignments for ten cases**, zero in-flight assignments, ten of ten cases exercised, no player deaths, and no native human input. Source confirms initial placements precede boarding and no actor teleport occurs during each descent/E/walk phase. Clear sample selection deliberately avoids existing roof obstructions using production aircraft/capsule collision and a walking sweep; obstructed spots are not claimed clear. Stills and these short physics phases do not certify animation transitions, continuous travel, takeoff/re-entry, long play, every other rooftop, far background towers, or whole-city completion. `all_visible_roofs_verified=false` and `whole_city_verified=false` correctly remain in the report.

Policy context: read-only review used the pinned shared-brain revision `a67557283f99cabd1d33a9caeb4d3ce3f1fe8ecd`; `brain doctor` reported `not-recently-checked`. No fresh GitHub-policy verification, publication, spending or infrastructure mutation is claimed.
