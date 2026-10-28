# Upright oriented source floor volumes

This extension is frozen for parent-run parsing/QA. It has not been run by the builder. The parent-run pre-extension `source-context-r3` remains a separate **478/478**, clean engine/supervisor exit0, reaped fixture result. It does not certify this oriented-volume source, the actual source MBS site assembly, source-world actor integration, rendered quality or whole-city completion.

Only `source_world_context.gd`, its owned QA scene, this new document and `VERIFICATION.json` are changed for this extension. No `source_runtime`, actor, main, bootstrap, save or RUNTIME document is edited. The parent owns the actual source-site assembly.

## Exact input alternatives

The existing axis-aligned definition and its validation/containment are unchanged:

```text
{volume_id:String, min_xyz:[double x,y,z], max_xyz:[double x,y,z], dry:bool}
```

The new alternative has these **seven exact keys**:

```text
{
  schema: "singapore_upright_obox_v1",
  volume_id: String,
  center_xyz: [double x,y,z],
  half_extents_xyz: [positive double x,y,z],
  axis_x_xyz: [double x,0,z],
  axis_z_xyz: [double x,0,z],
  dry: bool
}
```

The volume remains a source-space architectural envelope inside the existing floor registration. Its schema is available as `Context.OBOX_SCHEMA`. `Context.OBOX_KEYS` declares the exact field set. The floor record keys, provider contracts, collider stamp, source-pose schemas, restore preflight and rebase APIs remain unchanged.

Y is implicitly `[0,+1,0]`. X/Z must be finite unit vectors with zero Y, be orthogonal and have positive unit XZ determinant:

```text
axis_x.x² + axis_x.z² == 1
axis_z.x² + axis_z.z² == 1
axis_x.x * axis_z.x + axis_x.z * axis_z.z == 0
axis_x.x * axis_z.z - axis_x.z * axis_z.x == +1
```

Squared length, orthogonality and determinant checks allow only `1e-12` double-roundoff tolerance; the Y components must be exactly zero. Inputs are not rescaled or silently corrected. Tilt, shear, mirroring, zero axes and arbitrary scale reject the whole floor registration. Every center/extent/axis must be an Array or PackedFloat64Array of three finite numeric components. Bool components, Vector3, PackedFloat32Array and nonfinite values are rejected. All half-extents must be strictly positive. The enclosing canonical bounds must stay within the frame's supported finite coordinate domain.

Construct these axes from the original source doubles. Do not create a float32 Godot `Basis` and extract its axes before registration. The MBS source reference already supplies suitable double axes:

```text
axis_x_xyz = [axis_south_xz[0], 0.0, axis_south_xz[1]]
axis_z_xyz = [axis_bayward_xz[0], 0.0, axis_bayward_xz[1]]
```

For example, the source reference currently contains XZ axes `[0.9147652463748762,0.4039858215639653]` and `[-0.4039858215639653,0.9147652463748762]`. Those numbers specify orientation only; this extension does not supply verified floor centers, dimensions, fit-out or dry/flood state. Parent site assembly must choose its source-supported/reconstructed corridor/wing unions and preserve their provenance.

## Containment and numeric limits

Containment uses scalar double arithmetic:

```text
d = canonical_point - center_xyz
box_x = d.x * axis_x.x + d.z * axis_x.z
box_y = d.y
box_z = d.x * axis_z.x + d.z * axis_z.z
inside iff abs(box_i) <= half_extent_i, inclusively
```

The canonical center is subtracted before projection. No absolute Vector3, native Basis, actor transform or expanded AABB participates in dry classification. The enclosing AABB is calculated solely to reject bounds outside the finite source coordinate domain. Its corners are never declared dry by the oriented volume.

Inclusive faces receive a scalar numerical allowance:

```text
epsilon = 8 * double_machine_epsilon * max(1, abs(point), abs(center))
        + 1e-12 * (half_extent_x + half_extent_z)
```

For the 10×1.3×2m half-extent fixture near80km, this is about `1.54e-10m`, far below a millimetre. It covers rounding when constructing source corner points from rotated axes; it is not a gameplay margin, capsule erosion, safety clearance or additional dry corridor. The explicit `1mm` inside/outside cases must remain distinct. At the module's much larger finite-coordinate limit the allowance grows accordingly; this is not a millimetre guarantee for arbitrary external coordinate magnitudes.

Floor registration validates all volumes before storing any record or incrementing the registry revision. A schema-bearing dictionary always selects the oriented validator: unknown schemas, missing/extra fields and AABB/OBox hybrids cannot fall back to a broader AABB. Mixed unions containing an invalid box reject as a transaction. Valid AABBs and valid oriented boxes may coexist in one floor's union. That union must follow actual architectural space; it is not permission to mark the entire building/site bounding box dry.

Architectural containment remains separate from physical support/residency, capsule clearance, territory, land and hydrology. A rotated dry envelope alone cannot make restore ready. A `dry:false` oriented volume can bound a floor without excluding water. Shared boundaries and multiple floor identities retain the existing ambiguity/support-disambiguation policy.

## Prepared QA

The existing source-context scene keeps all earlier AABB, identity, stale-contact, cold-restore and native basement tests. New pure tests cover:

- Rotated interior points, all eight inclusive corners and points1mm beyond each face.
- A point inside the enclosing AABB but outside the true oriented box; the legacy AABB intentionally classifies it dry while the oriented box must not.
- Millimetre distinction near canonicalZ−80km, using double arrays throughout.
- Unchanged canonical containment/floor records across three explicit bounded, non-grid origin commits.
- Non-dry oriented volumes, PackedFloat64Array input and detached registry copies.
- Invalid schema/fields/types, positive extent checks, finite source bounds, zero/scaled/parallel/sheared/mirrored/tilted/nonfinite axes, premature float32/native vectors and whole-floor transaction rejection.

The native extension creates its own flat slab rotated in yaw to match the canonical basis, lets an actual .36-radius/1.75-height capsule settle on it below−20m, and obtains a fresh ray hit and capsule-clearance query. Restore must become ready without moving the actor. A second query at the enclosing-AABB-only corner must miss that physical slab, remain exterior water, lack support, and fail floor-bound source-pose creation. No actual Player, MBS architecture, source terrain or owner save is used by this fixture.

Use a **fresh** evidence/session path and the parent's existing sequential driver:

```sh
bash loop/singapore-fidelity/run_engine.sh source-context-oriented-r1 75 \
  /private/tmp/singapore-fidelity/source-context-oriented-r1 -- \
  --headless res://src/systems/fidelity_tests/source_context_test.tscn -- \
  --qa-session /private/tmp/singapore-fidelity/source-context-oriented-r1/session
```

The scene retains the45-second internal watchdog and fresh private report-path guards. Require a clean supervisor, clean engine log, complete report and every unchanged/new assertion. No engine/GPU/Git operation was performed by the builder; the parent remains responsible for running this scene and integrating/validating the actual source-site geometry and player route.
