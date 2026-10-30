# MBS city doorway connection — 2026-10-29

Owner reauthorized this narrow integration after the prior cutoff: connect the existing interiors to normal gameplay, remove the separate preview menu, and do everything possible without opening the game or using the GPU. No new broad city/hotel expansion or agent loop.

## Implemented candidate behavior

- Main always installs `CityHotelAccess` after building the existing city. The title-menu preview button and standalone preview scene are removed.
- A signed HOTEL LOBBY doorway is placed below Tower1 on the Bayfront Avenue side: current-city position(-20,.12,-752), with a10m approach keep-out shared by plaza props, road dressing and kerb planting. The crossing sits before the existing eastern tower facade. No driving lane or bridge is rebuilt.
- Normal foot crossing (or E at the doorway) initiates an in-game doorway transition. It retains the same main scene/player/city/vehicle/mission objects, suspends city simulation and hides the city geometry while the interior is active. This is not a continuously connected exterior/interior coordinate mesh.
- Existing public lobby, T3-L24 guest floor and T2-L5 spa factories are reused at separate streaming-region elevations. New arrival collision/support checks run in the game before moving the player. Failed construction/landing retains the current location and does not manufacture a successful test.
- Lobby lift doors lead to the guest floor/spa. Their existing lift doors return to the lobby. Lobby exit returns to a support-checked exterior landing; blocked exit candidates are refused. Unbuilt stair connections stay visibly closed.
- Normal city save data is preserved. The optional validated hotel_visit tag contains only version and selected space. Saving inside writes a valid exterior recovery pose, not streaming-region coordinates. Load validates first, restores city state, then defers loading the selected interior. A legacy save without the tag stays compatible. It resumes at the interior landing, not the exact room position; no new vehicle-position or room-door persistence is claimed.
- Death/checkpoint, mission restart, title return and load restore the city. Character health/ammunition, mission state and the parked car are not recreated on ordinary doorway/lift travel. Vehicle use cannot trigger a doorway. No default save was read or written by this implementation task.

## Evidence and limits

`OFFLINE_CHECKS.json` records15 passing CPU-only numeric/configuration and static source-contract checks. gdtoolkit4.5 grammar parsing passes the8 edited/new GDScripts; Python packaging modules compile. These are not native GDScript semantic, collision, visual, animation, performance or gameplay passes.

The owner prohibits all engine/game/GPU launches. None were made or queued. Later native QA must use a private --qa-session and the shared GPU/first-frame safety workflow after owner authorization. Exercise: bridge drive/park/exit, walk and E doorway entry, lobby lift both destinations, room doors, lift return, exterior/car continuity, failed-arrival/vehicle/paused guards, save/load from each space, invalid-save rejection, death/checkpoint/restart, repeated visits, held-E behavior, ordinary camera/render/animation checks. Do not substitute static results for these tests.

Full geographic Singapore and the complete hotel/resort remain unfinished. Preserve the frozen research work and existing provider rights/private assets. No main merge or public build release.
