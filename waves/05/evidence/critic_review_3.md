# Wave 5 fresh-context critic pass 3 (code review)

- Critic: a third, separate fresh-context Claude Code subagent (`opus-critic`, Opus 5.5). It was read-only and launched no engine. It reviewed `git diff 2463cd3 HEAD -- game/src` at about 01:30–01:32 UTC. That diff covers the soak-driven vehicle–pedestrian fix (`107ecda`).
- Scope: source correctness only. This was not a visual review.

| # | Finding | Severity | Resolution | Verification |
| --- | --- | --- | --- | --- |
| 1 | Lane adoption also caught mission guards, which are created in WALK state with no lane, so they would have walked off their posts. | High | The builder had already fixed this in `ae4b6b8`, before the report arrived: only civilians adopt a lane. Seated diners now keep their seat when their idle timer lapses. | 97/97 regressions; soak rerun. |
| 2 | Vehicle–pedestrian contact persists across ticks while the commanded speed stays high. Damage, heat and the "Civilian fleeing!" toast therefore repeated every tick, giving a wanted level within 3 ticks from a brush. | High | One impact per person per 0.6 s. The toast fires only on the change into fleeing. | 97/97; soak rerun. |
| 3 | Skipping pedestrian contacts also skipped the drivetrain clamp, so a blocked car built speed and lurched when the person moved. | Medium | The clamp counts every contact. Only the car's self-damage ignores soft bodies. | 97/97; soak rerun. |
| 4 | Seated diners would stand up and slide away after a 3,600 s idle. | Low | Diners keep their seat until startled. | — |
| 5 | The self-test civilian borrow could dereference null. | Minor | Guarded. | 97/97. |

The critic also confirmed: the lane scan runs once per transition, pooled officers are unaffected, the typing is legal, and the parked-car early return is harmless.
