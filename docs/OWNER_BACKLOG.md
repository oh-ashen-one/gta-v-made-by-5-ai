# Owner backlog

## 2026-11-03 — Clear streets, movement and interface

- Implemented; targeted rendered checks passed: mostly empty driving lanes (four ambient cars plus one regular AI car), preserve parked vehicles.
- Implemented; targeted rendered checks passed: Jade HUD/settings/notifications, selected from three generated concepts; bottom-right selectable weapon wheel.
- Rejected by owner: the Quaternius/custom-rig runner looked distorted. Replaced by Mixamo Josh with native skin and motion; asset-only verification is documented in `native-human-20261103/README.md`. No new game opened during repair. Full-game movement feel and weapon grips await the next owner playtest.
- Implemented; targeted rendered checks passed: generate/download five varied Suno tracks and cycle them randomly while driving, with no immediate repeats; pause with the game, stop on exit, enable/disable in Settings. Track names and restoration instructions: [RADIO.md](RADIO.md).

Owner playtest: judge running transitions and foot contact, weapon alignment, road freedom, UI readability, and subjective music balance/taste. Full source-coordinate city and complete hotel are pre-existing unfinished scope, not part of this pass.

## Current playtest follow-up — 2026-11-03

- Owner reports the native Mixamo runner looks much better; retain it.
- HUD artwork: replace code-drawn weapon silhouettes and plain panels with built-in image-generated production textures based on the selected Jade reference; detailed live minimap from actual roads/building footprints/landmarks. Implemented and verified in the current update.
- Driving camera: initially backlogged, then explicitly authorized for this update. Mouse yaw/pitch orbit, sensitivity/invert support, camera collision and C recenter. Implemented and verified in the current update.
- Vehicle/pedestrian impacts: register damage once per contact cooldown while retaining vehicle momentum; pedestrians must not be solid walls for the player's car. Keep walls and other cars solid. Implemented and verified in the current update.
- Generic combat audit did not detect explicit weapon hit-stop; defer weapon-only evaluation. Do not introduce vehicle hit-stop against the owner's requested uninterrupted driving.
