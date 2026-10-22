# Wave 5 fresh-context critic pass 2 (code review)

- Critic: a second, separate fresh-context Claude Code subagent (`opus-critic`, Opus 5.5). It was read-only and launched no engine. It reviewed `git diff f8218a1 HEAD -- game/src` at about 01:12–01:17 UTC on 2026-10-22, and re-checked the pass-1 fixes.
- Scope: source correctness only. This was not a visual or pixel review.

| # | Finding | Severity | Resolution | Verification |
| --- | --- | --- | --- | --- |
| 1 | Pass-1's committed pursuit parked responders at the goal's junction. A player standing mid-block, more than 45 m from the junction, was never approached, and the search stalled. | Major | At the goal's own junction, the responder now runs down the road through it toward the goal's projection, instead of holding position. | New check: "pursuit closes on a mid-block goal from its junction". |
| 2 | The NPC render-LOD gate reused the far-walk slot, which advances every tick, so most NPCs never ran the check. A walker flagged far could glide while frozen. | Major (render) | Fixed per-NPC phase `(frames + instance_id) % 8`. The check now runs before the DEAD branch. | Regressions; not rendered. |
| 3 | An NPC that died while flagged far stayed an upright statue. | Minor | `play_death()` clears the far flag. The LOD check skips the dead. | Regressions. |
| 4 | Held NPC weapons had no draw range, so guns floated beyond 150 m. | Minor (render) | `attach_weapon` applies the NPC draw range to weapon meshes. | Not rendered. |
| 5 | Pursuit telemetry counted slow responders as "stationary" at the 10 Hz record rate. | Minor | The movement reference refreshes at most once per second of route time. | Route telemetry. |
| 6 | Pooled police cars kept a stale pursuit waypoint. | Minor | Recycling clears the pursuit metadata. | Regressions. |
| 7 | The engine-loop seam check cannot detect a click smaller than the sawtooth reset step (~0.31). | Minor | Documented limitation. The seam metric is objective evidence, not proof of click-free audio, and no listening test was done. | — |

Items the critic confirmed correct: `_loop_seam` bounds and direction, whole tone cycles, signed sample decoding, siren timing, the gunshot peak; the save probe refusing the default slot; `PLAYER_START_PITCH` wiring; the pass-1 car fixes; the batching guards.
