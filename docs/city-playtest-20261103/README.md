# November 3 afternoon playtest fixes

Owner's latest instruction: **keep the game closed while the GPU is heavily loaded**. No Orchard game or queued launch remained when checked; the point-in-time GPU reading was 83%, with three unrelated capture jobs. Do not resume graphical testing or launch for play without a later owner instruction. Other sessions were not stopped.

## Implemented

- Adobe Mixamo Unarmed Jump on the accepted native Josh skin, split into anticipation, flight and landing; standing takeoff synchronized to the sourced anticipation. Source/provenance in the native-human manifest.
- Compact HUD: one objective at top right (active courier takes priority), small current-weapon card, 1/2 selection, small E-to-drive hint, 176px live light GPS minimap at logical 1280x720. Large green wheel and duplicate courier card removed. Existing generated gun raster reused.
- M opens a full-screen map with ten named destinations, including hotel entrance, Event Plaza, major landmarks and both helicopters. Blue street graph route and separate final walking segment; Event Plaza approach goes around the podium through the promenade. Map pauses the simulation and consumes modal input; selecting a waypoint cannot fire the weapon on close.
- Image-generated visual controls manual replaces the old prose pause help. Its oversize TextureRect defect found in the rendered pass was corrected afterward; headless layout bounds pass.
- Chase camera detached from the old SpringArm so only CarFX controls its position; exponential damping replaces frame-sensitive longitudinal/lateral camera springs. Mouse orbit and C recenter retained.
- Shift plus turning engages the existing slip/handbrake drivetrain, smoke and skid effects; Space remains the brake.
- RMB opens the driver window with one glass burst and persistent shader opening. RMB+LMB uses the chase-camera aim, a window muzzle, ammo, cooldown, reload, impact/damage and police heat; own vehicle excluded from the shot, world cover retained.
- Boats restricted to basin routes whose complete hull bounds remain over water for every sampled heading.
- Six MBS public entrance approaches, signage and entry stations. Physical walk-through loads the existing lobby; exit returns to the entry used. This remains streamed existing interior content, not a complete continuous hotel reconstruction.
- Second usable helicopter on the existing waterfront helipad, preserving the airfield aircraft.
- Ten radio tracks: original five instrumentals plus five original vocal genres. All ten MP3 files decode, are imported, and shuffle without replacement. Restricted audio remains outside public Git; source URLs and hashes travel in the manifest.

## Evidence and limits

`verification.json` preserves both the partial rendered run and later headless checks. The rendered run verifies radio start/pause/exit, compact HUD/map, window-break trigger, drive-by ammo, camera ownership/orbit, monotonic straight driving and Shift drift. It stopped before its final result. Its MBS walking gate failed with a stale scripted aiming state and a short walk budget; resetting that fixture and using a three-second walking window passes actual lobby entry headlessly. Direct lobby entry and six physical approach-ray checks also pass.

Native character checks cover all original clips plus both jump transition clips with finite native bone poses. They do not prove animation quality. The saved jump image is poorly framed and is not visual acceptance. Final continuous jump review, the corrected pause manual/label layout, visible window opening and subjective driving/music feel remain for a later GPU-safe owner playtest. No new graphical run was launched after the owner's stop instruction. Existing larger source-city/hotel scope is not declared complete.

## Owner test order for a later launch

1. Walk, run and jump while standing and moving; check takeoff, apex and landing.
2. Confirm the small HUD and one mission line; select weapons with 1/2.
3. Open M, select Waterfront Helicopter, and follow the blue route; clear/change destination.
4. Drive straight, orbit the camera with the mouse, recenter with C, then hold Shift through a turn.
5. Hold RMB to break the driver window; fire with LMB and reload with R while driving.
6. Listen for the ten-song shuffle in a car; confirm the original instrumental tracks remain.
7. Visit the northeast waterfront and check boats remain in water.
8. Select MBS Hotel Entrance, approach the marked door, walk in or press E, then exit. Event Plaza is a separate exterior courier destination.
9. Visit the waterfront helipad and board with E; Space climbs and Shift descends.
10. Escape opens the illustrated controls guide; F3 opens settings.
