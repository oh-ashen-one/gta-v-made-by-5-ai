# Wave 3 evidence — DeepSeek V4.1 Flash Max through Devin

**Last reconciled: 2026-10-21T17:48Z** from actual terminal output, rendered PNGs, the packaged
executable and source. (An earlier revision of this file carried a timestamp of 18:50Z, which was a
clock error on my part and was in the future; it has been replaced with observed times only.)

**Checkpoint:** `f2dad16` plus later commits on `feature/wave-03-deepseek`.
**Engine:** Godot **4.7.1.stable.official.a13da4feb**, Forward+, Metal, native macOS,
Apple M3 Ultra / macOS 27.0.1. Incoming: Astra `658741b`, implementation `be6a8aa`.

**Verdict: playable experimental build with unmet requirements.** The owner reviewed the latest
third-person street gameplay and said it "looks pretty good". That is encouragement on progress, not
acceptance of the concept target. **The approved GTA VI-level Singapore concepts remain the bar and
have not been lowered.** No independent numeric score exists for this wave (see "Critic capability").

## Status — completed vs pending

### Completed and verified in this window

| ID | Check | Result | Artefact |
| --- | --- | --- | --- |
| R5 | Source regression, rendered, Metal | **85/85, exit 0**, 14.0 s | `regression-r5.json`, `regression-r5.log`, `regression-r5-gpu.json` |
| PR5 | Same suite in the **actual exported app** | **85/85, exit 0**, `editor_binary=false` | `packaged-final.json`, `packaged-final.log`, `packaged-final-gpu.json` |
| G2 | Third-person gameplay capture, avatar + HUD + live traffic | 5 frames, 1920×1080 backing | `gameplay-final/` |
| P10 | Fixed-view stills, 1920×1080 backing | 15 frames | `photos-ship/` |
| X5 | Private export | exit 0 | `game/build/mac/OrchardReach-wave03-final.zip`, **394,290,107 bytes**, SHA256 `733c40b106c05830f0d2778b5e5196706885a88b9e6273a2c4eb50e47651fe64`; PCK `504e7d05085558c5834368347fd67d0cb4c92d85de6895982fdb9baa565d03a5` |
| GPU | Shared coordinator namespace | `GPU_SLOT_DIR=/Users/midir/sm2-n1/_scratch/gpu` explicit on every render; `shared_root` echoed by the last-moment gate; slots `0/2`; `exclusive=false`, `perf_valid=false`, `contaminated=true` | `*-gpu.json`, `gpu-smoke.json` |

Every renderer launch went through
`gpu_slot.sh capture --label … --json … -- python3 game/tools/render_gate.py -- …`.
The coordinator's own log at `/Users/midir/sm2-n1/_scratch/gpu/gpu_slot.log` records each
acquire/run/release. **Shared capture slots are not exclusive and no performance claim is made from
them**; the coordinator itself stamps `perf_valid: false`.

### Pending / not tested

| Gate | State |
| --- | --- |
| Packaged 1800 s workload + stall analysis | **NOT TESTED.** The responder cost is measured and moved, not proven absent from the packaged hitch profile. |
| Packaged `--ui-review` save/relaunch (24/24 + 23/23) | **NOT TESTED.** The packaged 85/85 covers save roundtrip and nine atomic rejections, which is not the same check. |
| Independent visual score | **NOT PRODUCED.** The subagent harness model has no image input and returned no judgement rather than inventing one. |
| Car wheel articulation, pursuit/navigation recovery, blocked-lane reroute, audio listening | Unchanged from wave 2. |
| Ordinary OS-input playtest (QA-001) | Still absent. |
| Rights clearance | Provider redistribution UNVERIFIED per asset. Private implementation only. |

## What changed in this window

### Environment
Low western sun `(-16.3, 62)` at energy 2.35, warm ground-bounce directional, neutral warm haze at
density 0.00024, exposure **0.92**, ambient **0.44**, glow 0.28, contrast 1.10, saturation 1.04.
The manager's aerial review called the previous frame "washed-out whites/pinks"; exposure, ambient and
glow were all stacking into the highlight shoulder on pale facades, so all three were pulled back.
The sky shader got a gold horizon, deeper zenith and a **planar cloud deck** — the first pass sampled
cloud noise from `EYEDIR` and streaked vertically at the horizon. A shader compile error
(`vec3 + vec2`) was caught by an actual render, not by reading the code.

### Block interior grain
Each 144 × 144 m block had been one paver platform with buildings only on its edge. Now every block
has a cross of 6 m service lanes and four 46 m plots with real uses: courtyard, garden, workshop yard,
parking court (painted bays plus real parked cars registered in `parked_spots`), and mid-block
building. `_reserved: Array[Rect2]` records every structure footprint taller than 2.5 m as it is
built, and `_is_free()` gates new infill against it, so plots never intersect the heritage rows, HDB
slabs, mission hall, hawker pavilion or aviation buildings.

### Planted central medians
The manager called the street "an almost-empty endless road". Every road now carries a planted
median with a kerb, turf and clipped shrubs, segmented clear of all 25 junction mouths. Medians are
**visual only** (no collider) because a median collider on the road centreline would obstruct the
mission avenue; traffic runs at ±4 m lane offsets and turns only at junction gaps.

### Shopfronts
The previous full-width emissive panel read as a "solid glowing storefront". Replaced with a recessed
interior: dark back wall at 2.55 m depth, a lit ceiling strip, three mullions and a counter on
alternating bays. The arcade now reads as depth with a warm source.

### Density and variety
- Traffic 14 → **26**, with two in five seeded on edges within 230 m of the heritage/market blocks so
  the street the player walks is actually occupied.
- Pedestrians 116 → **140**, focused lanes 42 → **58**.
- Parked cars along both kerb families plus interior parking courts.
- Per-block HDB variation: height offset, and one of six paint schemes via `AssetLibrary.tint`, to
  break the "clone HDB grid".
- Far shoreline treed and given low roofs, so the bay no longer meets a flat plane.
- Roof decks darkened below the wall colour; from above, bright parapets had read as flat pale parcels.

### Measured responder stall
```
[profile] officer_pool_build_us=715249 size=5     # regression r5
[profile] officer_pool_build_us=715398 size=5     # packaged final
[profile] officer_activation_us=32 pooled=true    # pooled activation
```
≈145 ms per officer at load, **19–32 µs** to activate in combat. The wave-2 pattern was two ~735–762 ms
stalls per mission at 4.5 s responder spacing, which matches two constructions. The cost is now in
the load path. **This removes the hypothesised cause; it does not by itself prove the packaged hitch
is gone.**

### Correctness fixes
- **FV-07**: street lamps stood on the north-south carriageway centreline at all 25 junctions; both
  now sit on opposite junction corners.
- **F6**: the rejected-load toast no longer claims a new game started.
- **Mission progression moved from `_process` to `_physics_process`.** Objective state was advancing
  on the render tick, so a slow frame could delay a stage change. The heavier district made this
  observable as two regression failures (`taking car starts the authored driving leg`,
  `on-foot arrival cannot bypass driving leg`); moving to the physics tick is the correct fix and
  gameplay state no longer depends on render rate.
- **Close-cover fixture** now freezes the character animation for its own check only. The fixture
  measured the muzzle and then waited frames; longer frames drifted the aim pose off the 0.18 m
  cover. The assertion itself was not weakened — the blocked and cleared shots both still run.

## Rejected neighbours preserved
- `regression-r4.json`: **82/85** — median tree collider on the mission-avenue ray, plus the two
  mission-timing failures. Kept, not overwritten.
- Earlier still passes `photos-r1`…`photos-r8`, `gameplay-r1` kept as the iteration record.
- `docs/wave-03/gpu-smoke.json` records a first smoke run that used the wrapper's **default**
  `~/.cache/gpu-slot` namespace. That namespace is stale and separate from the shared one; the
  manager caught it, and every later run sets `GPU_SLOT_DIR` explicitly and shows
  `shared_root: /Users/midir/sm2-n1/_scratch/gpu`.

## Critic capability — recorded, not fabricated
A fresh-context blind critic was attempted through the subagent harness with the concepts and both
before/after sets. **The subagent model has no image input**, so it returned no judgement rather than
inventing one. The visual verdict for this wave is therefore builder self-assessment plus the
manager's own review, not an independent score.

From direct inspection of `gameplay-final` and `photos-ship`:
- The street reads as Singapore: arcade columns, varied pastel shophouse frontages with awnings,
  signage and lit recessed openings, kerbs, lane dashes, crosswalks, planted medians, layered tree
  canopy, HDB slabs with window bands and curtain-wall towers behind.
- Gameplay frames show the real avatar, HUD, moving traffic and pedestrians.
- **Still short of the concepts:** pavement and road surfaces remain broad and uniform, activity
  thins quickly away from the seeded street, the waterfront promenade and interiors are the weakest
  precincts, and the sky's upper band is still pale.

## Safety and process
- One renderer at a time; `PAUSED` checked; cap of two never approached; no foreign process touched.
- Shared capture slots only — **no exclusive/performance claim**.
- No provider asset generated, downloaded or regenerated; no credits spent.
- No bypass flags, no global config changes, no model substitution.
- The earlier direct-`godot` fallback used before the manager resumed has been **removed** and is
  documented as a process correction in `HANDOFF.md` and `NEXT_GOAL.md`.
