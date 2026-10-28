# Canonical source frame and explicit rebase transactions

This is the first **runtime math contract**, not the completed source world. It does not change the existing bootstrap, actors, physics, traffic, minimap, save slot or default fictional geography. The full Singapore and MBS objective remains open.

## Representation and identity

`game/src/world/geography/source_frame.gd` (`SingaporeSourceFrame`) accepts the exact existing manifest frame: source EPSG:4326, surveying EPSG:3414, origin E30000/N30000, source X south, Y up and Z west, one metre per unit, no distance compression and no legacy-plan alignment.

Canonical points are three-element **double-valued Arrays or PackedFloat64Array**, in `[source_x, elevation, source_z]` order. A `Vector3` or `PackedFloat32Array` is deliberately rejected as canonical input because conversion afterward cannot restore already-lost detail. The active source origin is subtracted in scalar double arithmetic before constructing an engine-local `Vector3`. SVY21 adapters return plain double arrays, not absolute engine vectors.

The snapshot manifest SHA256, exact frame and elevation-reference metadata form an immutable frame fingerprint. The active origin/revision and process-local instance ID are excluded from the fingerprint, allowing a canonical pose to be restored at a different origin for the same data/reference. Configuration can succeed once per object; another dataset/reference needs a new context. Input/output containers are detached from internal state.

Elevation metadata defaults to `status=unknown`, `reference=UNRESOLVED`. The math class never verifies terrain height, datum, floor identity or source survey accuracy. Caller-supplied `source_tag`/`surveyed` status remains a caller assertion, with `elevation_verified_by_module=false` reported. Negative basement coordinates are representable; this does not fix the current Player's legacy Y death plane.

Godot documents scalar `float` as double precision while native vectors normally use single precision. JSON supports full-precision number serialization. These are API/representation references, not evidence this script compiled:

- [Godot float](https://docs.godotengine.org/en/stable/classes/class_float.html)
- [PackedFloat64Array](https://docs.godotengine.org/en/stable/classes/class_packedfloat64array.html)
- [JSON.stringify](https://docs.godotengine.org/en/stable/classes/class_json.html)

## APIs

- `configure(manifest_frame, source_origin_xyz, snapshot_manifest_sha256, elevation_reference={}) -> bool`: validates everything before mutation. `last_error` explains refusal. This checks declared identity, not file authenticity; the root data loader must verify the trusted manifest/supplement hashes first.
- `metadata() -> Dictionary`: detached identity, active origin/revision, limits and explicit vertical uncertainty.
- `to_local(source_xyz) -> {ok, position, origin_revision}`: double subtraction then bounded local vector. Failure outside the window reports `requires_rebase=true`.
- `to_source_current_live(local_vector)`: promotes a CURRENT live physics vector to canonical doubles. A bare vector has no epoch/context proof and must never be used as a retained cache. The old ambiguous `to_source` name was removed before integration.
- `svy21_to_source(E,N,elevation)` / `source_to_svy21(source_xyz)`: fixed affine metre adapters; no WGS84 projection or guessed vertical conversion.
- `prepare_rebase(new_source_origin_xyz) -> {ok, plan}`: pure value-only preparation. The native local translation is **old origin minus new origin**; no rotation or scaling is involved.
- `validate_rebase(plan) -> {ok, error}`: verifies schema/instance/snapshot/fingerprint, exact before/after origins, revision, finite/bounded derived delta and content checksum. This catches stale, double-applied or accidentally mutated plans; it is not adversarial authorization.
- `local_after_rebase_current_live(plan, live_vector)`: low-level precomputation for a CURRENT live physics value only, not an epoch-validated cache. Its result explicitly reports that bare-vector epoch validation is unavailable. Retained positions must use the checked sample/preview workflow below; the old ambiguous method name was removed.
- `commit_rebase(plan) -> bool`: validates again, then mutates only this frame's origin and revision. **It moves no object or cached position.**
- `make_source_pose(source_xyz, heading_rad, feature_id='', floor_id='', room_id='')` / `validate_source_pose(pose)`: versioned source-centric JSON envelope, separate from Game's current save schema. Feature/floor/room strings are labels, not verified registry membership. Snapshot/frame/vertical mismatches and legacy local-save shapes are refused.

Successful query results contain `ok=true`. Invalid queries return `ok=false` plus an error; callers must inspect this before using other fields. `last_error` is used only for mutating `configure`/`commit` bool results. No query or preparation mutates the frame.

The physical-local window is ±2048 m per component, with a recommended rebase near 512 m and a maximum step of 1024 m per component. These are residency/precision work budgets, **not a Singapore world boundary**. Repeated local origins cover the national extent. A very large jump returns `requires_new_context=true`; load the destination world/support in a new context instead of translating a live float scene tens of kilometres. A cache that would leave the local window must be streamed out using canonical state.

Plans, checked local samples and rebase previews are ephemeral process-local objects and should not be persisted or replayed across sessions. Save canonical poses instead. Origin commits are single-owner operations at the root's physics boundary; this class is not a concurrent transaction coordinator.

## Parent integration protocol

1. Verify data identities and snapshot/frame/elevation metadata, then configure an origin near the active source pose.
2. Keep long-lived positions/source IDs canonical. Decode/query source data off thread as appropriate, but form local engine vectors at the controlled commit boundary.
3. Prepare and validate a rebase. Capture actual live values or project canonical source state into checked local samples, then preflight every rebase preview; retain velocity, orientation and relative transforms. Never retag a stale bare vector as current. Evict nonresident data rather than treating it as outside the city.
4. In one controlled physics boundary without an intervening await, commit the validated plan, activate its prevalidated previews, then apply checked current sample positions to all affected local state coherently. The root must handle rollback/failure and physics interpolation/platform-history semantics. Merely translating the world root is insufficient for top-level cameras, NPC/traffic targets, safe/last-seen poses, decals and cached motion.
5. Before accepting source poses, verify the source registry, semantic/floor identity, loaded physical support, indoor/water/void state and all supplementary data versions. A successful numeric pose validation is not permission to spawn into an unloaded or unsupported room.

Missing land/coast/terrain, source heights, road widths/vertical policies, façade/roof detail and MBS plans remain explicit. The administrative country polygon is not a land/support mask. No default geometry authority or fake/real overlay was introduced.

## Prepared verification — no engine run by this worker

The parent-run scene is `game/src/systems/fidelity_tests/source_frame_test.tscn`. It requires an explicit owned private QA path and refuses an existing report. It writes `source-frame-report.json` and its own path-guard scratch sentinels/links inside that fresh QA session; no owner save or world is touched.

```sh
bash loop/singapore-fidelity/run_engine.sh source-frame-r3 60 \
  /private/tmp/singapore-fidelity/source-frame-r3 -- \
  --headless res://src/systems/fidelity_tests/source_frame_test.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/source-frame-r3/session
```

The scene checks actual-manifest identity, invalid/compressed frames, input/output alias isolation, actual engine absolute-versus-local millimetre representation, axis/distance preservation, basements, prepare purity, stale/tampered/double-application rejection, non-grid cache reconstruction, 219 bounded rebases over a 112.128 km **math exercise**, and full-precision JSON source-pose compatibility at a new origin. Stand-ins are not actors, terrain, physical traversal, rendering or performance proof.

`verify_math.py` is a separate standard-library float32/double **design study**, not execution or parsing of GDScript. Its bound source hashes and numerical results are in `equation-study.json`. Godot compilation/runtime, actual actor/camera/FX rebasing and all world/gameplay/visual gates remain **UNVERIFIED** until the parent performs them.

## Typed validation repair after parent R1

The first parent engine invocation produced 71 arithmetic checks with no assertion failures, but the supervisor correctly returned **exit 2** because `_valid_frame` compared an adversarial boolean with a float before checking its type. That is a failed run, not a pass. Original evidence is retained separately; `REPAIR_R1.json` records the fatal error and source identities.

The repaired source validates each top-level frame string/number/bool and nested axis string before equality. Plan and pose identity fields now receive the same type-first treatment. Pose elevation metadata must be explicit and complete, is normalized to string-only fields before comparison, and cannot silently fill omitted unknown metadata. Invalid local-vector argument types now return structured errors rather than relying on engine argument errors. The original negative cases remain, with additional adversarial frame/axis/elevation/plan/pose matrices.

The repaired source has **not** been rerun by this worker. Acceptance requires both a clean arithmetic report and a clean supervisor/engine result: exit 0, no fatal errors and a reaped child. The original design study retains its pre-repair source hashes; it is not a certificate for this new validation code.

## Checked local caches and future previews — R3 source

The parent R2 invocation passed **298/298** arithmetic checks with supervisor exit 0 and no fatal errors. Independent review nevertheless found that bare vectors could not distinguish old caches from current physics. That clean result is retained as arithmetic scope only; it does not approve live integration.

Use these APIs for every retained local coordinate:

1. `capture_current_local(live_vector)` captures an ACTUAL current physics value, or `project_source_sample(canonical_xyz)` projects trusted canonical data. Both return a detached local-sample envelope. A sample binds its process-local frame instance, immutable frame fingerprint, snapshot, origin revision/origin, canonical double point and its local projection. Do not strip/relabel old sample data or mutate its fields.
2. `sample_to_source(sample)` and `sample_to_local(sample)` validate all provenance, current revision, origin, geometry and content checksum before returning values. Old/future/wrong-context samples are rejected without frame mutation. `validate_local_sample` provides the same check without conversion.
3. `sample_after_rebase(plan, current_sample)` produces a **separate preview schema**, not a current sample. `validate_rebase_preview(plan, preview)` preflights the identity, canonical point, future projection and matching plan. Checked current-sample conversions reject preview objects before and after commit.
4. At the root's coordinated physics boundary, commit that exact plan, then call `activate_rebase_preview(preview)`. Activation requires the actual current origin/revision and last committed plan hash to match. Only then does it create a checked current sample. A competing commit cannot activate another plan's preview.

The canonical point is carried in the sample so repeated non-grid rebases do not repeatedly reconstruct logical cache truth from rounded local projections. Dynamic actors must recapture their actual live value after legitimate motion; fixed AI/camera targets can carry the existing sample through each plan/preview/activation cycle. Actual actors/platform histories, physics interpolation and cache-update ordering are still root integration work. These checks detect accidental stale/mixed data, not adversarial code that deliberately forges internal checksums.

The new QA cases reproduce origin 0→512→1024 with a cache at canonical X=10: the stale origin-0 cache is refused by the current plan, while activated caches remain canonical X=10. A separate 219-step non-grid origin-cycle exercise captures once and carries samples forward, never re-fetching a fresh canonical input each iteration. It checks old-epoch rejection, future-preview refusal, canonical drift and bounded native projection error. No actual actor/camera/FX rebase is claimed.

## QA report path guard — R3 source

The supplied session must be a **new** normalized directory under `/private/tmp/singapore-fidelity/`, with an already-existing verified parent and no linked ancestors. Nonrecursive directory creation refuses an existing session. The guard runs before creation, after creation and immediately before report writing. Directory enumeration plus `is_link` refuses every existing report-leaf entry, including a dangling symlink, regular file or directory; it does not rely on `file_exists()` for leaf absence. The output path must still equal the checked session/report name at write time.

Native negative fixtures create only this session's own scratch sentinels and links: a session-directory link, a dangling report leaf, a pre-existing regular report, a report directory, session reuse, and a late leaf insertion that the final recheck must refuse. Targets remain inside the fixture directory; no real user file or external link target is used. This is a single-owner ownership/recheck guard, **not** an OS-level O_EXCL write or a guarantee against an adversarial same-user filesystem swap between the final check and open.

The R3 source/QA changes have not been executed by this worker. Preserve R1's fatal failure and R2's bounded clean arithmetic result; require a fresh clean supervisor/engine run before accepting the new cache/leaf guards.

## Parent R3 proof and independent re-review

Actual Godot run passed456/456 with engine/supervisor exit0, no fatal errors and a reaped child. A separate reviewer matched exact source hashes and closed both originalP2s: the 0→512→1024 stale-cache case is rejected; future previews require commit/activation;219carried non-grid cycles show zero canonical drift. Native writer fixtures preserve sentinels and reject linked/existing leaves. These are component proofs, not live actor rebasing or a finished source city.
