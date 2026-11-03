# Generated HUD artwork and driving fixes — 2026-11-03

The owner accepted the running-character improvement but rejected the HUD's code-drawn gun silhouettes. This revision uses real generated raster artwork in the game. It also implements the subsequently authorized driving-camera fix and nonblocking pedestrian impacts.

## HUD implementation

Built-in `image_gen` produced three transparent atlases using the selected Jade concept as the visual reference: detailed pistol/SMG artwork, two selected-state wheel plates, and mission/ammo/notification/minimap frames. They are actual runtime textures in `game/assets/ui/generated`, not just design concepts. `hud_art.gd` loads atlas regions from alpha-bound metadata; image pixels are unchanged. Dynamic names, ammunition, objectives and settings remain readable native UI text.

The minimap is 228×228 logical pixels inside the generated bezel. It uses actual playable-world BoxShape3D building footprints, the authoritative downtown road/bridge/shoreline plan, avenue tree positions, vehicles and mission marker. It draws roof outlines/shadows, road widths/arterial centers, promenades, water/parks, nearby landmarks and road names, plus a correct north-up compass and scale. A whole-terrain collider is explicitly excluded, and large footprints draw before smaller details. The map is the playable city, not a claim that the unfinished source-coordinate Singapore replacement is complete.

## Driving camera

Mouse motion is routed to the occupied car instead of changing the hidden on-foot camera. Yaw can orbit all the way around; pitch is bounded. Existing sensitivity and invert-Y settings apply. The chase camera retains its collision sphere and now checks both world and vehicle layers. Press **C** to recenter. Input is ignored while paused, and looking does not steer the car.

## Pedestrian contacts

Player-driven cars exclude the NPC collision layer from their solid movement solver. After movement, the car shape is swept along the distance it actually travelled, including initial overlaps and the final pose, to register NPC contacts. Damage uses the existing NPC take-damage/crime path and per-person cooldown; slow contact makes them scramble. Neither the damage sweep nor pedestrians' bodies zero car velocity or damage the car. Walls, other cars and world geometry retain solid collision. Using actual travel prevents hits through a wall the car could not cross. AI cars keep their prior pedestrian collision/perception behavior.

## Verification

- `rendered-checks.json`: 38/38, actual 1600×900 rendered game, including map data/art loading, weapon selection, settings, five-track radio, actual car entry and camera orbit, native human presence and private save/load.
- `driving-checks.json`: 22/22 native physics/control checks: several NPCs, grazing and misses, initial overlap, high-speed crossing, reverse impact, damage/crime registration, momentum retention, wall exclusion, mouse routing, inversion/pitch bounds, pause, C recenter and camera world/vehicle collision.
- The final targeted logs have no script errors. The existing texture-RID cleanup warning remains on rendered exit. This is not a broad full-game regression result or owner aesthetic/gameplay acceptance.

## Test one by one

1. On foot, inspect the new weapon artwork, mission card and minimap. Move around a block: the player marker, building/road layout and objective should track you.
2. Hold **Tab**, point at pistol/SMG, release; try **Q**, right-click aim, left-click fire and **R** reload. The artwork/name/ammo should agree with the equipped weapon.
3. Enter a parked car with **E**. Move the mouse left/right/up/down, then press **C**. The camera should orbit/recenter without steering the car. Test inverted Y and sensitivity in **F3 Settings** if desired.
4. Drive the clear streets with **WASD**, brake with **Space**. Parked cars remain and normal moving civilian traffic is limited to five; pursuit/mission traffic is separate.
5. Hit an NPC at driving speed, then several in succession. Hits should register and people react, while the car keeps moving. A near miss should not damage someone on the sidewalk. Walls and other cars should still block/deflect the car.
6. Check car radio: music on entry, pause/resume, toggle in Settings, fade on exit. Track completion or re-entry advances the shuffled playlist without an immediate repeat.
7. **F5** save, **F6** load: check settings/selected weapon. Existing vehicle-position persistence limitations are unchanged.

Native running already received positive owner feedback; check turns/jumps if anything feels different, but this update does not replace the character again.
