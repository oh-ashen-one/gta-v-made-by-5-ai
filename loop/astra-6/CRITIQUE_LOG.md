# Independent source critiques — Astra-6

Fresh-context inherited Codex subagents; these are source reviews, not human or rendered acceptance.

## Traffic R1
No confirmed production blocker. Three P2 gaps: predicate-only protectedparking test; no actualcamera-cut recycle; singlejunctionsnapshot not sustainedflow. Resolved firsttwo in a50fff4/equivalentparent9f1e1b9 with actualspawned usablevehicles and actual twice-recycled constrainedpool. Sustainedreview and wholeheadlessdrive retained; box/zebra stops remainreported, rendered drivingstillpending.

## Courier/save/ramp R1
No confirmedproductionblocker. Threegaps: helperreset mislabeledNewGame; no death/vehiclehandover test; onlyone rampdirectionfixture. Parent e606e76 nowtests actualmain._new_game and real deathinoutbound/receipt. Game saveinvalidfield rejectatomic andlegacyresetverified. Dedicateddefaultnojump fullcourier routeongoing; actualMBSnorthlipfound/repairedvia297043d. Actualvehiclehandover/reverseallramps remainsboundedgap untiltested.

## SkyPark R1
No confirmedproductionblocker. P2testgaps: testmanuallybootstrapsmissingproductionhook; eachheadingnotactuallyEexited/floorverified; no real rooftopdeath/freshsceneload. Builderassignedstrictintegration,8headings+boundaryanddeath/freshloadtests. Productionguards/range/LOS/arrivalcollision/2.4mrailgeometry reviewedconsistent. Flighttest usesexplicitairbornefixture, notheritage-to-roofproof.

## Visual review
Pending fresh candidate captures. Baseline29actualgame images capturedfromunchangedWeek1main451c8eb, zeroengineerrors, sharedcontaminatedGPU. No fullquality/60fps claim from source/headlesschecks.

## Blind visual R1 — actual Metal stills

A fresh Codex critic inspected six neutral A/B copies before seeing reference images or source notes. View1 A=current attempted granite material, B=Week1 baseline; B was preferred because its rectangular paving, local wear and scattered details were less checkerboard-like. View2 A=baseline/B=current and view3 A=current/B=baseline were ties for fixed environment quality. The more open road in current view2 matches the owner direction, but dynamic positions alone cannot prove traffic behavior.

Decision: remove the optional new granite material and retain the existing paving, avoiding a quality regression. Existing source textures remain untouched and privately stored. The images in city-r1-views preserve the rejected material iteration; they are not final-art proof. Main open visual gaps remain trees, frontage depth and skyline material separation; no AAA acceptance claimed.

SkyPark critic follow-up a553da0/equivalent c947391: strict production main hook, actual E exits at eight headings and eight boundary points, four outside refusals, real rooftop death/ground recovery/lift reuse, fresh-scene save/load all passed (116/116,101.25s,0 errors), headless. No production changes were required. Rendered review remains separate.

## SkyPark actual-render review R1

The 116-check suite also passed under Metal (121.55s, zero engine errors) and produced four actual player-camera frames. Fresh visual critic found: lift lightstrip overlaps secondary sign text; deliberately expected obstruction-test notice remains over successful-arrival still; public terrace needs visitor/wayfinding scale cues. The builder is correcting the sign and test-capture hygiene and adding restrained existing-asset life outside the helicopter/lift clearance. Collision/motion claims remain grounded in the test logs, not inferred from the images. Seven texture RIDs were reported on renderer shutdown after the suite's full-scene teardown/rebuild; warning retained, no memory-leak acceptance claimed.

Full courier route R8 now passes31/31 from normal starting point,3683.21m in603.65s,zerojumps/deaths/teleportsteps. The access lips found by earlier failed routes were physically repaired rather than bypassed by the test.

## Courier integration re-review 20:32 UTC
Fresh read-only critic found no production blocker or QA leak. P3 test weakness: death persistence could pass if damage was a no-op. Added per-stage death_count increment assertion before health/state check; full suite rerun pending. Optional capture only lives in test scene. Physical joins share mesh/collider basis.

## Rendered downtown drive R1, 20:38 UTC
Actual controls route completed376.2s,72.2s waiting,zero tows,one overtake,two controls-based unsticks. Shared GPU/no-exclusive measurement p95~107ms is not performance acceptance. Supervisor exit2 because a queued frame readback resumed after its JSONL file was closed. Preserved failed evidence; added post-await recording/open-file guard and nulls the closed handle. Rendered flight/views will exercise that shutdown path; no production traffic or route gates altered.

## Actual courier UI critique, 21:00 UTC — pending polish
The two actual player-camera dispatch images show readable mission/courier HUD coexistence, but the oversized two-line world billboard dominates the skyline, and the near-target screen marker overlaps it. Fresh critic requests a substantially smaller world label (or compact physical sign) and suppression of near-target screen marker when the E interaction is available. These are new feature polish issues, not movement/performance claims. Queue a small station.gd/status_card.gd fix AFTER current full rendered courier run, preserving that run's exact evidence. Re-render dispatch from actual controller/camera; do not weaken full-route checks. Fixed implementation freeze21:50:57 remains.

## Final visual and clearance reviews
Fresh rendered SkyPark critic confirmed the canopy/sign overlap, stale obstruction toast and empty terrace findings are resolved in R3's positive frames. Only a minor toast contrast issue remains. Fresh courier critic confirmed the compact world title and near-target marker fix in dispatchR3. Final source critic accepted the real2m visitor-clearance increase and unchanged9m test; renderedR4 observed12.008m corpse clearance, with native solver/floor failures retained. Native packaged rooftop Continue/lift down/up/walking was then verified through macOS keyboard input and normal quit.
