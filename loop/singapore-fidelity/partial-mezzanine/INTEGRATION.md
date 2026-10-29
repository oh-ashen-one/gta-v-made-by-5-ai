# Partial basement service galleries — source contract and author candidate

This component fills the six hotel B2/B2M low-rise recipes with substantial furnished original geometry. It does not certify the whole MBS building, invent as-built floor plans, fix resort global coordinates, or count a planned factory as runtime/visual acceptance. Root owns all integration, engines/GPU, transport guards and Git. The worker changed only NEW`partial_mezzanine.gd`, NEW`mbs_partial_mezzanine_test.gd/.tscn`and this notes directory.

## Exact inventory gap

`INVENTORY_AUDIT.json`records actual input IDs/programs/heights and inventory hash. T1/T2/T3 each have B2=-10m, B2M=-7.5m and B1=-5m: the six outgoing B2/B2M intervals are2.5m. Their old full-floor recipe requested3.08m clear+.20m slab and therefore correctly returned`pending_root_recipe_change`. Both B2 and B2M preserve ALL eight named programs: service corridor, linen/laundry transfer, engineering store, staff changing, staff pantry, plant, service lifts and stairs. Each new floor has five concretely furnished rooms plus physical corridor/cores, not a labelled one-room fallback.

These elevations, private hotel B2M assignments, dimensions, core axes and room layouts are reconstruction assumptions. Their hotel records have NO per-floor source facts. The operator kiosk reference supports retail L1/B1/B2 and the B2M coach/casino links, but does not prove every hotel's private basement floorplate or metric heights. The public source ledger and links remain in`research/mbs/references.json`and`circulation-contract.json`with their inspected28October2026scope. No third-party plan/image is copied into public source.

The27resort records also lack Root source mappings/explicit geometry: SHOPPES7, EXPO7, CASINO5, THEATRE3, MUSEUM5. Once mapped, SHOPPES-B2→B2M→B1 adds two more2.5m intervals. CASINO-B2M=-7.5→L1=0 is7.5m, outside ProgramFloor's current5.5m maximum; it needs a separate tall/double-height factory, not only a coordinate mapping. Those open gaps remain explicit; this first factory deliberately accepts only the six hotel records rather than silently supplying a generic resort box.

## Chosen geometry

Root selected ordinary.20m slabs,2.30m service clear height,2.10m low receiving/passages and.10m headers. No fictional.10m structural deck or altered level spacing is used. B2 keeps its full central service base but no false ceiling at3.08m. B2M has two10m-deep peripheral furnished service wings plus3m-wide end cross-links. The central rectangle between those wings/links stays OPEN. B1's actual slab supplies the roof above both the open tall hall and the low peripheral galleries. The lower central hall therefore has4.8m clear height; lower edge rooms beneath mezzanine and upper rooms beneath B1 each have2.3m. Original service equipment/carts and a4m continuous lower transfer spine occupy the tall hall.

The end links join both wings without bridging through the principal tall hall. Rooms stop before those links. All actual core X/Z axes remain unchanged; U stairs retain the existing footprint, two1.25m flights/2.7m runs/1.2m landings, now with the REAL2.5m rise. Both half-flight slopes are about24.8degrees. Visible treads, continuous native walk collision, landings, guards, wall piers, low doors and furnishing solids are real. No masks/colliders are disabled, no actor relocation occurs in the factory and no extra floor is invented.

The new class extends ProgramFloor, preserving the complete-body/stable-plain-structure type contract, production SwingDoor adapter, room-door persistence and transition signals. Its one plain structural body remains`ProgramFloorSolidCollision`; moving doors remain real AnimatableBody3Ds without static source support. Existing original Kit/Looks/Palette/furnishing recipes are adapted; no provider generation, new asset download, purchase, account or custom whole-motion animation was used.

## APIs and Root integration

`Partial.partial_plan(record)`validates the complete bounded hotel record before state/node mutation. `build(record)`,`report()`, inherited native E/persistence methods and`geometry_descriptor()`are the instance API. Original input records are copied; the factory does not mutate inventory. Unknown/missing programs, wrong IDs/elevations, nonfinite dimensions, unsupported footprint/core dimensions, insufficient full-size furniture capacity or overheight furnishing fail before construction.

Root should dispatch the existing B2/B2M program records through this class BEFORE the full-floor clear-height rejection; copy their actual adjacent rise and retain floor IDs/source placement. The planned geometry has minimum clear2.3m and a marked partial schema. Do not pass it to the unchanged full ProgramFloor validator, which correctly refuses this low-height domain. Normal guest/program floors, including B1, retain their existing factories.

The descriptor exposes exact local slabs/platforms, open void, actual native floor probes and per-zone dry OBoxes as local centre/half vectors. Root converts these to canonical double arrays using the actual placement's original source anchor/axes. It must use these PRECISE boxes instead of the existing uniform full-wing `_volumes`construction; the upper mezzanine void must never be registered as a dry supported upper floor. Lower tall-hall dry air can span the upper void, but a missing upper floor remains physically unsupported. Never stamp a moving door as floor support.

The descriptor's`required_group_floor_ids`are B2/B2M/B1 for the same tower. A loaded B2 normally asks only B3/B2/B2M through simple±1neighbors; this component additionally needs B1 for its actual ceiling/upper structure. Root must include the explicit group dependency when preparing/readiness/pinning/evicting these zones, still bounded and without recursive fake readiness. B1 itself keeps the normal complete program geometry and receiving approaches.

`core_door_height_m=2.10`,`core_header_height_m=.10`,`service_clear_height_m=2.30`,`slab_thickness_m=.20`. Lift portal IDs/thresholds/cabin-expected centres match the fixed inventory axes. Stair fire-door height belongs to the DESTINATION landing: B3→B2 needs2.10 even though B3 is normal; B2→B2M needs2.10; B2M→B1 uses normal2.35 because B1 has normal headroom. The existing low-rise StairGates lower bound/default headers and Cabin/Hall receiving openings must be adapted by Root to those exact destination contracts. Internal continuous cabin height can remain unchanged, with source/native sweep proof between the2.5m stops. Neither factory nor fixture asserts shaft travel readiness.

## Resort mapping packet still required from Root

For each of the27records, current Stack expects an explicit upright source packet with`source_anchor_xz`double pair, orthonormal`axis_x_xyz`/`axis_z_xyz`, complete local`geometry`and bounded provenance. The geometry must come from the actual Root footprint/source arrangement, not the generic ProgramFloor profile. Preserve source IDs, polygons/buildable local bounds, actual inter-building separation across Bayfront Avenue, known level labels and documented assumption status.

To reuse the partial contract for Shoppes, Root must additionally supply the actual source-local coach/retail/service occupied-platform and vertical-void zones, matching B1 cutouts/receivers, and native door/underpass connection ports with local centre/normal/clear width/height and reference status. A B2M coach area cannot be compressed beneath an uncut B1 slab2.5m above it or silently relabelled as B2. Its tall-volume footprint must be separated horizontally, with real B1 bypass circulation. Current public schematics establish topology, not those metric coordinates or coach headroom. The casino's7.5m interval is a separate tall-space recipe. No global coordinates or source mapping success is invented by this factory.

## Root native fixture

The new scene statically plans all six hotel low recipes, then selects actual T3 by default (narrowest footprint;`--partial-tower=T1|T2|T3`for other actual runtime cases). It builds real source-positioned B2/B2M plus the normal B1 receiver, common actual Frame/Context/Domain/Runtime and full production Player. It registers complete real body lists and precise actual zone volumes, verifies low ceilings/central open void, and uses one initial spawn. It walks furnished rooms on both wings with native E/LOS, crosses the real end galleries, climbs BOTH2.5m U stairs into B1 and descends/returns continuously. Every native door keeps matching2.10m visual/collision dimensions. It does not call forced room interaction or fake transport readiness.

The first fixture does NOT include Root's future low-height StairGates/Hall/Cabin adaptation or SourceStack dispatch; that guarded transport/streaming integration is a separate required gate after Root wiring. It also does not prove all six recipes at runtime from one selected tower, visual fidelity, performance, coach access, resort mappings or whole-building completion.

Root commits the frozen code before running ONLY the current helper, for example:

```sh
bash loop/singapore-fidelity/run_engine.sh mbs-partial-mezzanine-r1 1000 /private/tmp/singapore-fidelity/mbs-partial-mezzanine-r1 -- --headless res://src/systems/fidelity_tests/mbs_partial_mezzanine_test.tscn -- --qa-session /private/tmp/singapore-fidelity/mbs-partial-mezzanine-r1/session --partial-tower=T3 --partial-report=/private/tmp/singapore-fidelity/mbs-partial-mezzanine-r1/report.json
```

The internal fixture cap is900seconds, all evidence/source hashes belong to that run, and earlier failures stay retained. Optional rendered captures/fresh critique still required after native geometry passes. At author freeze compile/native/render are PENDING; worker ran only scalar/lexical audits. No whole-goal completion is claimed.
