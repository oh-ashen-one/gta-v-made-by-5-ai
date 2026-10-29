# Immutable dry-floor reject broadphase — author candidate

The source context previously visited every registered floor volume during every `_dry_matches` call. This change adds a private, registration-derived float64 AABB union for each floor's dry volumes. It rejects floors that cannot match, then runs the unchanged exact `_inside` predicate and original match-record construction on every remaining volume. The box is never accepted as dry geometry.

## Evidence and scope

Inspected actual `mbs-public-core-entry-r5` evidence:184checks, one native-settle QA failure,838.034seconds; the last recorded Runtime profile reported60,230residency calls and211,043,746microseconds. **That211seconds measures `_resident`, not `_dry_matches`.** Context dry matching had no separate timing in that run. Its exhaustive loop is established by source inspection; this change does not claim that the whole remaining elapsed time came from it or that any gameplay-FPS threshold is met.

The implementation is deliberately limited to immutable registered floor geometry. No per-frame query result, native collision readiness or residency result is cached. There is no Runtime/Game/World/Save change. Exact registered floor records, normalized source arrays, metadata keys, registry revisions, query/observation identities, public schemas, water composition and support/restore rules are unchanged.

## Conservative double bounds

For an AABB volume, its exact inclusive min/max are copied into the floor union. Nondry volumes contribute nothing. An all-nondry floor has an empty reject entry. Disjoint volumes can make the union contain gaps, but those gaps still fail the exact volume predicates.

For upright OBoxes, the old predicate projects the source-point-minus-center into the supplied X/Z axes and admits the existing unit/orthogonality/determinant tolerance1e−12. Using `abs(axis)*half` alone would assume an exactly orthonormal basis and can reject a point that the exact existing predicate accepts. The reject bounds therefore use the inverse of that admitted2×2 projection matrix, including its actual determinant.

The existing point-dependent epsilon is conservatively capped over the same finite canonical coordinate domain: `DOUBLE_ROUNDING_FACTOR*MAX_CANONICAL_COMPONENT_M + OBOX_BASIS_TOLERANCE*(halfX+halfZ)`. That cap expands the inverse-projected half extents. A further outward-only allowance derived from the existing double-rounding constant covers bound arithmetic. It is a reject-bound rounding allowance, not a gameplay/capsule margin. The exact original point-dependent epsilon still determines final membership.

All calculation uses GDScript64bit scalar floats and source arrays. No absolute canonical Vector3/Basis/float32 projection is constructed. Derived boxes can conservatively extend a few floating-point units beyond the canonical limit; valid query points remain bounded by existing validation. Source coordinates and volume arrays are never repaired, inflated or rescaled.

The derived index is filled only on successful immutable registration. Duplicate/invalid registration cannot alter it. Late floors appear immediately with the ordinary registry-revision increment. If a derived entry is missing, the method uses the old exhaustive path instead of silently dropping that floor. Canonical bounds survive active-origin changes because they do not contain local vectors or origin-specific results.

## Root-run validation

The existing `source_context_test.tscn` and all571previous checks are retained. Added cases compare exact ordered match dictionaries with a helper containing the original exhaustive algorithm. Cases cover rotated inclusive faces/corners and just-outside points, AABB boundaries, nondry floors, disjoint-volume gaps, late registration/query invalidation, unchanged records/metadata, rejected duplicate registration, missing-derived-entry fallback, existing epsilon near the canonical limit, and an admitted near-unit basis whose million-metre half axis exposes a transpose-only bounding error.

A bounded synthetic189floor×8volume population adds output parity and records broadphase/exhaustive microsecond timings plus exact candidate-volume counts for32queries. It has no timing-ratio acceptance threshold under shared CPU load and is not native city/render performance evidence. It proves reduced candidate work while keeping exact output parity. Root must execute the revised context fixture and the coupled source-save/world tests; the child has run no engine/GPU/Git action.

At author freeze native parsing/parity and end-to-end performance are pending. The whole Singapore/MBS/gameplay goal remains active.
