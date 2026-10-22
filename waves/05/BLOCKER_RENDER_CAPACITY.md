# BLOCKER (manager action requested): no shared renderer capacity for wave 5

Recorded 2026-10-22 01:34 UTC by the wave-5 builder (Opus 5.5). The builder has not touched any foreign process or lock and will not.

- The Studio's mixed renderer cap is 2. `render_gate.py` counts four foreign GUI Blender renderers, all from the `veyr-review-fable-20261021` loop in the default `~/.cache/gpu-slot` namespace. Every leased Godot render launch therefore refuses, correctly.
- The holders are actively rendering (200–1,100 % CPU), and the loop keeps replacing sessions:

| Lease | Label | Started (UTC) | 4 h max-hold end (UTC) |
| --- | --- | --- | --- |
| 3894 → Blender 3909 | fable-veyr-knight-run-20261021 | 23:34:45 | ~03:34:45 |
| 4734 → Blender 4774 | fable-veyr-knight-backpedal-20261021 | 23:36:12 | ~03:36:12 |
| 5184 → Blender 5200 | fable-veyr-knight-walk-20261021 | 23:36:42 | ~03:36:42 |
| 80732 → Blender 80753 | fable-veyr-dragon-20261021 (new) | 01:14:45 | ~05:14:45 |

- The older lease `fable-veyr-knight-v4` (21:58 UTC) was replaced at 01:14 UTC by the dragon session, so the loop refills slots as they free.
- **Consequence:** wave 5 has no rendered frame at all yet: no wave-4 baseline, no final-candidate screenshots, no rendered frame time. Everything verified so far is headless.
- **Request:** close or pause at least three of the four veyr sessions for about 10 minutes, any time before 03:50 UTC. Alternatively, record an explicit owner exception. A gated runner is already waiting, one engine at a time, through lease → `render_gate.py` → `bounded_run.py`. As soon as capacity frees it captures, in order: the final-candidate opening, the unchanged wave-4 baseline (`aerial_district` and the wave-4 opening), the candidate fixed views, and a rendered candidate route. It launches nothing after 03:50:30 UTC.

## Update, 01:58 UTC

- The `fable-veyr-dragon` session (80753) ended at about 01:56. Three veyr knight renderers (3909, 4774, 5200) are still running, so the mixed cap is still exceeded.
- Their 4-hour leases end at about 03:35–03:37 UTC. If the loop does not refill them, the gated runner should get roughly 15 minutes of capacity inside the final window.
- The release candidate is already built and verified headless (`HANDOFF.md`). Only the rendered evidence is waiting on capacity.

## Update, 02:22 UTC

- The loop relaunched `fable-veyr-dragon-20261021` at 02:11:27 UTC (Blender 33509, lease 33493, 4-hour hold until about 06:11). The count is back to four foreign renderers.
- When the three knight leases end at about 03:35–03:37, this session alone (count 1) would leave room for one Godot render under the cap of 2, unless the loop refills those slots too.

