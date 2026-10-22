# Wave 5 fresh-context critic pass 4 (release-candidate code review)

- Critic: a fourth, separate fresh-context Claude Code subagent (`opus-critic`, Opus 5.5). It was read-only and launched no engine. It reviewed the whole wave-5 diff (`6b51a26..HEAD`, `game/src` and `game/tools`) at about 01:37–01:44 UTC, with emphasis on the paths earlier passes covered least.
- Verdict: no crash, parse, save or mission-flow break. It raised two release issues.

| # | Finding | Severity | Resolution | Verification |
| --- | --- | --- | --- | --- |
| 1 | The pre-existing far-shore tree rows (and one wave-5 row) grew through the relocated ArtScience lotus and the Flyer terminal. A 13 m low-roof box sat under the Marina Bay Sands SkyPark cantilever. | High (visual) | Far-shore trees skip 34 m around the ArtScience Museum and 42 m around the Flyer. The duplicate wave-5 tree row was removed. Low roofs skip the MBS footprint and overhang. | Headless probe: ArtScience 100 % visible from the promenade (was 95 %); Flyer 99 % in the helicopter approach view. |
| 2 | A disabled helicopter brought down on the out-of-bounds far shore trapped the pilot: there is no exit, and it cannot fly back. | Medium-high | A downed aircraft out of bounds recovers the pilot to the last safe point. A flyable aircraft is still told to fly back. | 97/97 regressions |

The critic also confirmed: the opening row orientation and clearances, the start point, signage facing, kerb-marking gaps, the RNG-preserving skyline skip, platform heights, the batching exclusions (lamps, skinned, transparent, ranged), that the self-test fixtures run last and are restored, that the save-probe and `_qa_system` changes are QA-only, and the restart start point.
