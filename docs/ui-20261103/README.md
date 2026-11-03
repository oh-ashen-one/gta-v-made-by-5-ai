# Clear streets and Jade UI — 2026-11-03

Owner request: mostly empty streets with curbside parking and only a few moving cars; three generated UI variations, select the best and implement the HUD/settings/notifications and a bottom-right weapon wheel; source better running animations; five varied Suno songs shuffled automatically in cars.

## Selected direction

`01-jade.png` is selected over `02-editorial.png` and `03-night-drive.png`. Its restrained charcoal panels, warm white text, jade accent and amber warnings preserve the center of the screen and remain legible over bright streets. Concepts were generated with the built-in image tool. Their city backgrounds are design illustrations, not game screenshots. The implementation uses native Godot controls and vector weapon silhouettes rather than flattening an image over gameplay.

- Compact objective card, minimap/health, ammunition, notification cards and driving/radio readouts.
- Consistent title/pause/settings treatment. Mouse sensitivity slider; clickable invert-look, reduced-shake, HUD and radio toggles; visible Back button. Existing keyboard shortcuts retained.
- Hold Tab on foot, point at the pistol/SMG half, release to equip. Escape cancels. Q still cycles. Simulation pauses during selection, mouse capture restores, weapon mesh/ammo update together, and switching cancels the previous weapon's reload.
- HUD aspect ratio remains intact on non-16:9 windows.

## Streets

Ambient vehicle pool: 48 → 4. Regular physical AI cars: 7 → 1. Parking retention unchanged (observed 51 road bays plus 20 courtyard cars). Ambient seeding prefers the curb lane, checks 65 m separation across neighbouring lanes/edges, increases lane spacing to 80 m, and retains the existing protection against spawning in the player's driving path. Police/mission traffic is not included in the five civilian moving-car budget. Cars may converge naturally after spawn; no promise of permanently empty intersections.

## Animation source and integration

The restored backup has the original `player_rigged.glb`; newer private `_loco4` files were not present. Quaternius Universal Animation Library Standard v3 was downloaded from the creator's official itch.io page on 2026-11-03:

https://quaternius.itch.io/universal-animation-library

The included CC0 license is preserved beside `UAL1_Standard.glb`. Standard includes Walk, Jog Forward and Sprint. `game/tools/retarget_quaternius.gd` samples these at 30 Hz and aligns body coordinates and source/target rest-pose bone directions, then transfers global rotation deltas onto 21 mapped Orchard rig bones. It preserves source vertical pelvis bob but discards root travel, preserving the owning character's physics and original mesh. `player_locomotion.tres` contains the resulting three motion clips. The player installs these in a `sourced` animation library; combat/aim/reload/jump and NPC clips remain their prior implementation. `--legacy-locomotion` provides a comparison fallback. Animation style/foot sliding/weapon hold still require owner gameplay judgment.

Source pass: Mixamo site requires its interactive account surface; Adobe's FAQ confirms free Adobe-ID access and commercial game use. Fab's search fetch was unavailable; no suitable Fab clip was acquired. NVIDIA SimReady's catalog is predominantly simulation props/USD and provided no verified humanoid running clip. ThreeJS Assets' free page exposed mainly model/environment resources, not a verified matching running pack. Quaternius was selected for explicit CC0 rights, included in-place locomotion and direct Godot GLB support. No paid animation assets or new custom locomotion were purchased/authored.

## Radio

See `../RADIO.md` and `../OWNER_BACKLOG.md`. Raw Suno audio stays local/ignored; the source URLs, file hashes, durations and restoration manifest are versioned.

## Verification

The scripted rendered review `--owner-polish-review --qa-session <private-dir> --review-dir=<output-dir>` exercises UI, weapon selection/cancel, sparse traffic counts, preserved parking, five-track shuffle, actual car entry/audio start, pause, radio toggle, exit fade and preference persistence. It saves game-only captures and `verification.json` in the requested output directory. It disables native desktop input for this fixture to keep unrelated keyboard/mouse activity from changing its state. It never uses the owner's save slot.

Visual evidence is a runtime/interaction check, not acceptance of gameplay feel, music taste or AAA fidelity. The full source-coordinate Singapore city and complete hotel remain unfinished pre-existing work.

Latest validation: **32/32 targeted rendered checks pass**. Full headless regression is **288/294**, with exactly the same six failures under `--legacy-locomotion`: missing older jump/landing/stop/backpedal/skid assets, offline look bakes and the older idle-weight-shift contract. See `regression-comparison.json`. No new script parse/runtime errors occurred in the targeted rendered run; Godot reports its existing texture-RID cleanup warning on exit.

Pre-push source review: custom shared Gitleaks rules scanned 582 ancestor commits / about 454 MB. All 253 reported generic-key candidates were classified: 251 recorded source-file SHA-256 hashes and two local CPU-job UUIDs (generated by `uuid.uuid4().hex`, not service credentials). Staged source scan was clean. Concept PNGs have no embedded metadata; the CC0 source GLB had no detected home-directory path strings. Restricted provider/audio binaries are excluded.
