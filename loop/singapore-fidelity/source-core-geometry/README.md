# Actual source-core native fixture

This fixture exercises Root's current source_core_geometry and source_stair_gates, retaining the complete source_core_layout poses. It is a bounded physical core test, not a new room/exterior factory or a claim that the hotel is complete.

Run the same scene separately with `--source-core-variant normal` and `--source-core-variant low`. Normal uses original T3 L47/L48/L49 records; low uses original T3 B2/B2M/B1 records with the existing Partial height recipe. All modules use actual individual T3 source axes and the same SourceFrame, Context and Runtime. The third module supplies actual receiver support/ceiling and explicitly has no outgoing construction beyond this fixture. Every module retains its incoming aperture; there is no proxy slab inserted beneath a stair or lift shaft.

The helper's original rear-well cut ended at5.00m while the actual midlanding reaches5.10m. A full capsule at rear position4.67m entered that upper slab's footprint. Root corrected the cut to5.10m and removed coincident lower/upper landing and slab faces. The QA probes all actual holes and asserts the arrival landing belongs to exactly one receiving-floor collider. It also requires an actual full-size Player to reach the rear landing through ordinary input and remain natively supported/clear.

The receiver callback only reports ready after actual native ray support and committed region liveness. Before that, gates stay closed. Complete region inventories include all three structures and all moving gate bodies; architecture dry volumes follow actual slab cells and stairwell air, never lift holes. A disabled actual receiver is a negative readiness test, restored before the single player setup spawn.

After one initial setup spawn the test never assigns player position, velocity or parent. It follows the lower shared hall, rotated east U-stair, actual E-selected top gate, receiving shared hall, actual E-selected west gate, west U descent and original hall. Rear midlanding detours use the real capsule bottom offset for their precise target height, without moving the actor directly. Test input is released and normal native braking settles before turns/interactions.

Use Root's normal single-engine helper, after shared capacity and STREAMING permit it. Example arguments after `--`:

```text
--headless res://src/systems/fidelity_tests/mbs_source_core_geometry_test.tscn -- --qa-session /private/tmp/singapore-fidelity/source-core-normal-r1/session --source-core-variant normal
```

Internal wall bound720seconds; recommended outer780seconds. The fixture writes `source-core-geometry.json` within its private QA session and prints native check/movement evidence. Exact frozen hashes are in FIXTURE_FREEZE_R1.json. Only lexical delimiter checking has occurred so far. Root owns native parser/physics runs, repairs, captures and Git.
