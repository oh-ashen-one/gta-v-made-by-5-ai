# Wave 3 reassessment — DeepSeek V4.1 Flash Max through Devin

Reassessed **2026-10-21T16:05Z** from the actual incoming tree, rendered stills, packaged evidence and
source, before changing any priority. Incoming Astra checkpoint `658741b`, implementation
`be6a8aa`. Engine kept at **Godot 4.7.1.stable.official.a13da4feb**, Forward+, Metal, native macOS.

## What the inherited evidence actually shows

I did not inherit the outgoing prose as a pass. I inspected the images and the source myself.

| Claim | What I actually saw |
| --- | --- |
| "Giant empty paved lots" | **Confirmed, and worse than described.** Each of the 16 blocks was one 144 × 144 m `pavers` platform with buildings only on its edge. The wave-2 `street_wide` camera at `(-20, 3.2, -12)` was standing *inside* a block interior looking across it, so the "street" evidence was a photograph of an empty car park. |
| "Repetitive detached buildings" | **Confirmed.** Every block used the same `shophouse` module repeated 13× per row, plus four identical HDB slabs. Nothing occupied the middle of a block. |
| "Prototype urban massing" | **Confirmed.** All buildings were untextured `BoxMesh` with flat `StandardMaterial3D` albedo. No window grids, no parapets, no back-of-house. |
| "Washed-out midday" | **Confirmed.** Sun at 28° elevation, ambient energy 0.42 at a cool blue, fog density 0.00025. The approved concepts are low golden-hour light with strong directional modelling. |
| Six ~735–762 ms combat stalls | **Cause measured, not assumed.** See below. |
| Lamp on the carriageway (FV-07) | **Found in source and fixed.** `_scatter_props()` offset the second lamp only in Z, leaving it on the north-south road centreline at every junction. |
| F6 toast says "starting a new game" | **Found in source and fixed.** Rejected loads already preserved state; only the message lied. |

## The stall: measured before changing density

`traffic_manager.gd::_update_police` constructed a fresh `NPC` inside the 4.5 s responder timer.
`NPC._ready()` → `CharacterVisual.configure("officer")` loads and instantiates the skinned
`officer_rigged.glb` (24-bone skeleton, 12 clips) plus a held pistol.

The pool warm-up print is a direct measurement, not an estimate:

```
[profile] officer_pool_build_us=715249 size=5     # run 3, regression
[profile] officer_pool_build_us=718986 size=5     # run 1
[profile] officer_pool_build_us=749104 size=5     # photos-r2
```

**≈145 ms per officer**, and the first officer in a cold process carries pipeline compilation on
top. Two responders are spawned per escalation 4.5 s apart, which is exactly the two-stall-per-mission
pattern Astra recorded. The fix pools five officers at load and activates them in place:

```
[profile] officer_activation_us=32 pooled=true live=0    # run 3
[profile] officer_activation_us=19 pooled=true live=0    # run 2
[profile] officer_activation_us=20 pooled=true live=0    # run 1
```

Activation is **19–32 µs** instead of ~145 ms of construction. This moves the cost; it does not by
itself prove the packaged stall is gone. A packaged timing run is still required (see gaps).

## Priority decision

The manager's verdict was **REWORK 3.7/10** with performance failing. I chose to spend the window on
the visual target first, because the visual gap is the largest and the stall cause was cheap to
remove. Concretely:

1. Environment and colour separation — one global change that lifts every frame.
2. Block interior grain — the literal "giant empty paved lot" defect.
3. Built-mass density and facade texture — the "prototype" read.
4. The measured responder stall, the two known source defects, and the bad photo vantage points.
5. Regression, export, honest evidence.

I explicitly did **not** attempt: new provider asset generation (none needed; all 18 jobs already
exist), engine migration, a full navigation rewrite, or a 30-minute packaged soak (does not fit the
remaining window; see NEXT_GOAL).
