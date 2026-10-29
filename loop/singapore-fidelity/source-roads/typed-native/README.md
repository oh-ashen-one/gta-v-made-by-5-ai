# Typed and anchored native road verification

These are source/QA changes only. The reviewer ran **no Godot process**, no GPU probe, no Git operation and no production edit. All new scripts have lexical delimiter checks only; native parsing and execution remain pending Root's normal shared capacity, startup-health and streaming rules.

Production review is pinned to `source_roads.gd`213f854463023815ac7609cc3b259b398eab31c906c29e5d762ec7c4a784404a and `source_world.gd`689da67550d49c34fdc64972e54ae75590cf4bcdc638675c19737350866db934. No remaining blocking source issue was identified within this loader change. SourceWorld still uses recovered R5, not the typed prototype.

## Fixtures and evidence ownership

`native-contract-r1`, identity `db2ba665dc60d9cf3f839f9dc1f8b1191cbf6d13bcb3573b172a9979cdf1477b`, is deliberately synthetic: flat car surface, a6m-high crossing foot deck, a0.15 foot slope, and disconnected up/down10-step components. The visible treads/risers and continuous walking collision are separate real arrays.

The original `native-anchor-failures-r1` could not pass the new part-schema validation because its `.pNNN` manifest descriptors lacked `spatial_tile_key`. The road worker created **new** `native-anchor-failures-r2`, identity `fdd79d76c995496b1e7acfa7c7d6e64d7b5c48ebf7f1ab7b786f1e8cfec26d75`. Its4geometry payloads and5-case file are byte-identical to R1; only manifest cell metadata changed, with a new identity. The original fixture remains untouched. This is not permission to weaken part validation or stamp an old hash onto a changed file.

## Native checks to run

| Scene | Purpose | Outer bound |
|---|---|---|
| `source_road_batch_test.tscn` | Retains the same-anchor five-body→one-body reduction, source hit lookup and mutation/retirement checks. Compares actual server faces per original way/face together with native body+shape transforms. A separate five-anchor synthetic encoding proves distinct anchors remain separate and default/batched visual arrays and native geometry agree exactly. |150s|
| `source_road_typed_contract_test.tscn` | Fixed car/foot/step caps; fake higher numeric caps, car-foot relabeling, mode/type disagreement, absent/reversed visible steps and invalid/mixed/gapped part ordinals. Actual crossing rays, fixed native-normal slope caps, original source/class lookup and40vertical visible riser triangles across two10-step components. |150s|
| `source_road_anchor_test.tscn` | All five retained actual-source failures. Reads the installed PhysicsServer face data, native body/shape transforms and exact encoded worst triangle. Requires an actual native ray hit on the recorded source face with its unchanged class cap and expected normal. |150s|
| `source_road_step_player_test.tscn` with `--typed-step-direction up` | One initial production Player spawn, then continuous ordinary input from first to last visible tread interval and back. |300s|
| Same step scene with `--typed-step-direction down` | Fresh separate run of the differently oriented descending fixture, again out and back with one spawn. |300s|

Use a fresh private `--qa-session /private/tmp/singapore-fidelity/<distinct-run>/session` for each run and Root's durable owned log output. Put engine `--headless` **before** the standalone `--` that introduces game arguments. No alternate launch path or concurrent task engine is authorized. Preserve native reports and supervisor metadata before disposable session folders are cleared.

The batch snapshot reads [`PhysicsServer3D.shape_get_data`](https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html#class-physicsserver3d-method-shape-get-data), `body_get_state` and `body_get_shape_transform`. It compares actual local face bytes, their transformed bytes and the native transforms keyed by original source face. It does not compare an order-dependent concatenation across unrelated anchors. The five-anchor setup explicitly re-encodes the synthetic fixture while preserving canonical coordinates; it does not modify a production dataset.

The precision cases record transformed world vertices and a1mm maximum source-position encoding bound. Native local shape normals and **actual ray normals** must satisfy the fixed class cap. Re-flattening transformed world vertices and crossing those rounded values would recreate the original precision error; that number is recorded as a diagnostic only. Four predeclared interior barycentric probes target the same recorded worst face. No easier face is substituted when the exact source face cannot be hit.

The two stair components are disconnected. The tests do not create a connecting platform, move an actor between them or force a support result. Each run has one setup spawn, visits all10visible tread intervals through actual Player input, turns and returns, and checks native support, source identity, death count and maximum movement step. Production physics updates velocity normally; the fixture performs no later direct pose/velocity/reparent assignment. These are scripted game actions, not human/OS-input or animation-foot-contact acceptance.

Manifest-negative cases are deliberately isolated private metadata fixtures. The positive contiguous accessor case still has unavailable payloads, which must fail preparation. It proves naming/accessor behavior only; it is not a pretend complete SourceWorld cell. The production World code separately collects every physical part before creating one road group and registering the cell.

All of this remains separate from full national coverage, terrain cut/fill, deck undersides/edge protection, portal enclosure, rendered quality, representative performance, human play and the complete Singapore/MBS goal.
