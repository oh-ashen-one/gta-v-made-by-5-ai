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

Junction review and independent rendered driving critique pending. No rendered engine launched by this builder. Density counters do not prove visual quality, driving feel, frame rate, or a zero-tow drive. Parent owns the sole serial render lane and must verify integrated behavior after replacing the two obsolete density assertions.
