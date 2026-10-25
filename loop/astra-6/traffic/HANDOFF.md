# Traffic builder R1

Owner scope: fewer cars for freer driving, retaining usable parked cars and existing mechanics. Branch `Astra-6/traffic`; integration owner controls `Astra-6-enhancements`. Actual builder: inherited Codex session model; no alternate-model claim. Machine verified as Mac Studio M3 Ultra; brain sync verified approved revision `3338091d3754` on 2026-10-25.

## Change

- Ambient pool 112 → 48 (57.1% reduction); full physics civilian fleet 14 → 7 (50%).
- Apply the existing 26 m per-lane seed occupancy cap during camera cuts as well as continuous streaming. Camera cuts previously bypassed the cap and intentionally packed viewed streets.
- Alternate occupied road parking bays with empty bays. Retain every courtyard car and every car within 45 m of the opening. Actual initial road parking: 97 → 51 (47.4% reduction); courtyard: 20 unchanged. Three opening road cars retained.
- Add traffic regression checks for both upper budgets, empty parking space, protected cars, short-lane seed capacity, overlap rejection, and nonempty near-field traffic with zero stationary zebra/box cars. Existing movement, left-lane, braking and interaction checks remain.

## R1 verification (headless only)

Fresh project import completed in 43.22 s, exit 0, no fatal errors. Full suite completed in 49.67 s: **285/287**, zero engine/script errors. Both failures are old shared-file density requirements explicitly superseded by the owner request:

- `self_test.gd:51`: `traffic.cars.size() >= 8`. Integrator replacement: `traffic.cars.size() == TrafficManager.TRAFFIC_COUNT and traffic.cars.size() > 0` (complete physical spawn).
- `self_test.gd:1288`: `near >= 45`. Integrator replacement: `near >= 8 and near <= 48`, title `camera-centred lane traffic stays present within free-driving budget`.

All six new traffic assertions passed. At the functional flow sample, 24/48 cars moved, 27 were holding; 0 stationary zebra cars and 0 stationary junction-box cars, with 35 cars near the focus. Parked pull-out, occupied-car interactions, driving, pursuit and helicopter checks passed. Preserve these meaningful behavior tests; do not change the old left-lane/movement thresholds without new evidence.

Logs: `/private/tmp/astra6-traffic/import.log` and `/private/tmp/astra6-traffic/test-r1.log`, with bounded-run source hashes, source patch and resource metadata adjacent. These paths are task-owned local evidence, not portable deliverables.

Exact commands, run from this checkout:

```sh
python3 game/tools/bounded_run.py --seconds 240 --log /private/tmp/astra6-traffic/import.log -- godot --headless --path game --editor --import --quit -- --qa-session /private/tmp/astra6-traffic/import-session
python3 game/tools/bounded_run.py --seconds 400 --log /private/tmp/astra6-traffic/test-r1.log -- godot --headless --path game -- --test --qa-session /private/tmp/astra6-traffic/test-r1-session
python3 game/tools/bounded_run.py --seconds 350 --log /private/tmp/astra6-traffic/junctions-r1.log -- godot --headless --path game -- --traffic-review --traffic-census --capture-dir=/private/tmp/astra6-traffic/junctions-r1 --qa-session /private/tmp/astra6-traffic/junctions-r1-session
```

## Remaining gates

Junction review completed; independent rendered driving critique pending. No rendered engine launched by this builder. Density counters do not prove visual quality, driving feel, frame rate, or a zero-tow drive. Parent owns the sole serial render lane and must verify integrated behavior after replacing the two obsolete density assertions.

## Junction census (2026-10-25 R1)

`--traffic-review` finished in 214.87 s, exit 0, no fatal errors. Each corner was sampled for 45 simulated seconds at 0.5 s intervals. These are stopped-car samples, not unique cars or tow counts. Full compact metrics are in `junctions-r1.json` beside this handoff.

| Junction | Cars/min | Mean cars within 30 m | Zebra stop samples | Box stop samples | Max idle s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Collyer Quay / Cecil | 24.0 | 6.4 | 2 | 0 | 15.1 |
| Raffles / Bayfront corner | 14.7 | 9.4 | 4 | 5 | 31.6 |
| Esplanade / Connaught | 21.3 | 10.6 | 0 | 0 | 24.1 |
| Collyer Quay / legacy grid | 12.0 | 10.7 | 3 | 24 | 35.7 |

Traffic remains present and moving. Crossing/box stops still occur, especially at the legacy junction; the single self-test snapshot is not a zero-obstruction result. The unmodified downtown drive is now running with its own session to measure completion, waiting and tows:

```sh
python3 game/tools/bounded_run.py --seconds 1300 --log /private/tmp/astra6-traffic/drive-r1.log -- godot --headless --path game -- --downtown-review --downtown-legs=drive --traffic-census --capture-dir=/private/tmp/astra6-traffic/drive-r1 --qa-session /private/tmp/astra6-traffic/drive-r1-session
```

## Completed downtown drive and independent critique response

R1 unmodified headless downtown drive completed: **314.0 s, 19.2 s waiting, 0 tows**, exit 0 and no fatal errors. It crossed the Esplanade and Bayfront bridges and returned via Marina Boulevard. One scripted unstick maneuver occurred at 26.41 s at the legacy-grid corner (-309.749, -316.6); zero tows does not mean zero assistance. Integrator-reported baseline: 445.4 s, 91.5 s waiting, 0 tows (29.5% less total time and 79.0% less waiting in this candidate run). Both runs are headless; this is one drive each, not an FPS result or soak guarantee. Compact exact evidence is in `drive-r1.json`.

The independent critic requested stronger tests, without production blockers:

1. Protection checks must inspect actual spawned usable cars. Each spawned parked car now records its original parking spot. The test finds the actual `Car` at each protected origin and requires it to be enabled and interactable, instead of recalling the filter predicate.
2. Camera-cut checks must run actual reseeding. An isolated short-lane fixture now calls `_recycle(true)` twice with eight pooled bodies and a capacity of two; it verifies actual activation counts, no overlap, and invisible/noncolliding exhausted pool entries. The fixture is freed immediately without mutating the live traffic graph, focus, RNG or vehicles.
3. The one-frame crossing assertion remains supplemented by the sustained junction census and full downtown drive above; it is not presented as proof of permanent zero obstruction.

R2 verification command:

```sh
python3 game/tools/bounded_run.py --seconds 400 --log /private/tmp/astra6-traffic/test-r2.log -- godot --headless --path game -- --test --qa-session /private/tmp/astra6-traffic/test-r2-session
```

R2b completed **286/288** in 48.78 s, zero engine/script errors; only the two known superseded density assertions in the integrator-owned `self_test.gd` fail in this isolated branch. All seven traffic-specific regression assertions pass, including **23 protected actual cars, 0 missing/unusable**, and **2 then 2 active cars from 8 pooled bodies**, 0 overlaps and 0 inactive colliders. R2 first used `interactables` for cars; source inspection confirmed the player's actual car interaction path is the `vehicles` group, so R2b correctly checks visible/enabled `Car` nodes in `vehicles` with `interact()`.

Final test command: replace both `test-r2` path components in the command above with `test-r2b`. No renderer or Blender launched. The parent must run its integrated suite with the two updated density expectations and arrange rendered review when a shared slot is available.
