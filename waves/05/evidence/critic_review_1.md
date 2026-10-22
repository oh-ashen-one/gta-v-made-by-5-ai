# Wave 5 fresh-context critic pass 1 (code review)

- Critic: a separate fresh-context Claude Code subagent (`opus-critic`, Opus 5.5), read-only, no engine or renderer launched. It reviewed `git diff 6b51a26 -- game/src` plus the uncommitted tree at about 00:50–00:58 UTC on 2026-10-22.
- Scope: source correctness only. This was **not** a visual or pixel review, because no rendered capture existed at review time. It is not independent human acceptance.

| # | Critic finding | Severity | Resolution (builder) | Verification |
| --- | --- | --- | --- | --- |
| 1 | `_pursuit_waypoint` re-chose the nearest junction every frame, so a responder that left a junction turned straight back to it and circled. | Major | The responder now commits to one junction waypoint (car metadata) until it reaches it or the goal's junction changes, then takes one grid step (`_grid_step`). At the goal's own junction, with no clear line to the goal, it holds the junction instead of driving through the block. | New regression check: "pursuit commits to its next junction after leaving one" PASS (95/95). |
| 2 | `force_exit()` (reached on respawn, restart and load) never cleared the seated-driver figure, and a sleeping car never refreshed it. | Major (visual) | `force_exit()` and the parked-sleep path both call `_update_driver_bust()`. | 95/95 regressions. Not rendered. |
| 3 | MultiMesh normals use the instance basis without an inverse-transpose, so strongly non-uniform scale on curved meshes would shade wrongly. | Minor (likely) | Non-box meshes whose scale anisotropy exceeds 10 % stay unbatched (9,871 → 1,188 draws). Unit boxes are exact. | Census plus probe equivalence. |
| 4 | Batching checked `visible` rather than `is_visible_in_tree()`. | Minor | Changed to `is_visible_in_tree()`. | Census. |
| 5 | Stuck recovery reversed blindly. | Minor | A mirrored corridor test behind the car now cancels the reverse. | 95/95 regressions. |
| 6 | Distant LOD traffic integrates without collision or gravity and keeps its spawn height, about 4 cm above the road. | Minor | Accepted and documented. It applies only beyond 110 m from the player and resolves when the car comes near. Fixed photo views placed far from the player see these cars in the low-detail mode. | — |
| 7 | The overlay tyre radius equalled the baked tyre radius, which risks z-fighting. | Uncertain | The overlay is now 1.5 % larger and 4 % wider. | Not rendered. |

Items the critic checked and found no problem with: unit-box batching keeps the same materials, UVs and world-triplanar mapping; nothing references the freed meshes after `build()`; signal lamps are excluded from batching; the kerb-marking maths; parked-car wake paths; NPC LOD; the helicopter envelope and ditch recovery; the player-start wiring.
