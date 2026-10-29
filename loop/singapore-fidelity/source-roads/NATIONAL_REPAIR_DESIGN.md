# Profile repair: targeted CPU prototype only, no national adoption

The first full-country outlier is **not** a short source segment. Mandai Lake
Road `way/1366486110` is a 457.305 m, 12-node tunnel loop with `layer=-1`,
`lanes=3` and the fallback width 9.6 m. Its two endpoints are approximately
4.72 m apart. Each endpoint has a physical flat hub apron of radius 4.8 m,
so their actual 16-gon apron footprints overlap. Their inferred canonical
heights differ by 60.9945 mm (60.9932 mm in emitted Float32 geometry).
The connecting surface approaches use explicit original endpoint grade
transitions. Flattening the entire 457 m loop would destroy its underground
profile and is not the proposed fix.

The full national seam audit has now finished; all 42 examples are retained
in `country-r2-records/classification.json`. It has revealed two additional
classes, so the initial apron-only proposal below is **insufficient alone**.
The existing R5 core, frozen compiler/runtime/fixture and failed national R2
remain immutable. No tolerance increase, hidden triangle rejection, culling
change or source-identity relabeling is appropriate.

## Smallest general first-class rule for this observed class

Add **height-only equality constraints between overlapping flat hub aprons on
the same original source way and exact grade key, with matching source
continuation-grade signatures and no evidence of protected level separation**.
Enumerate the actual
16-gon footprint used by the renderer, not an enlarged bounding box. Require
positive overlap area above geometric numerical noise. This also catches a
closed hairpin/loop with several hubs; solve all equality groups together.
Use bounded per-way spatial bins instead of an all-country all-pairs search.

This rule changes inferred profile heights only. Original OSM node IDs, way
IDs/order, tags, width evidence/fallback labels, adjacency, one-way bits,
source path lengths and turn/access restrictions remain identical. It adds
no navigation edge or equal-XY merge. It does not equate unrelated nearby
roads, arbitrary intersecting ribbons, different grade keys or a bridge and
tunnel simply because their projected geometry intersects. Source grade
transitions remain only the explicit original endpoint transitions already
recorded by the kernel.

The full audit found a vital negative case: the 57.464 m service ramp
`1453057758` has ports only 0.718 m apart, but its ports join explicit
layer-1 parking and building-passage grades. Its 4.968 m inferred separation
must be preserved. A same-way/grade-key test alone would incorrectly flatten
this ramp; compare the explicit original endpoint continuation-grade sets,
and refuse an equality when they differ or are unresolved. Source node IDs
are still not merged. Full source-height/bound contradictions remain blockers.

The new equality must enter the global profile solver before graph export,
not just move a visible apron. On this loop it makes the two portal aprons
coherent while allowing the interior source nodes to retain a sloped lower
tunnel profile subject to the same grade bounds. DEM samples and existing
bridge/tunnel lower/upper constraints stay separate and unchanged. Any newly
incompatible clearance constraints must be reported and block the new recipe;
do not silently waive them under the old conflict count. This remains an
explicit game reconstruction from fallback widths and coarse DEM, not a
surveyed road elevation claim.

## Implementation and artifact impact

The smallest isolated implementation can live in a new bounded profile
preprocessor. Copy R5's SQLite DB into a fresh owned prefix, add the new
height-only constraints plus per-pair provenance, call the existing exact
profile solver, then regenerate **both** graph catalogs and physical meshes.
No existing R5 code or data needs to be overwritten for an experiment.
Alternatively Root can authorize an explicit new kernel recipe after review.

Either choice creates a new profile/database/artifact identity. Some graph
catalog hashes will change because `source_xyz.y` is explicitly the inferred
game profile. It would be false to promise byte-identical R5 graph files
while changing only physical mesh Y. The topological graph audit must instead
prove unchanged original vertices, raw source/DEM evidence, ordered ways,
edge identities/directions/access/grade and source XZ; graph and physical
profile Y must agree with the new DB at every source vertex. New profile and
policy provenance must be pinned in the manifest and runtime binding.

The present national producer is explicitly pinned to R5 profile lineage, so
it must not simply accept edited graph files. A reviewed R3 producer must bind
the new profile identity and its audit must compare against that identity.

## Targeted tests required before a country rebuild

1. Reproduce the exact measured Mandai tunnel loop with original IDs, widths,
   endpoint positions, DEM bounds and original ordered interior source nodes.
   Demonstrate the existing multi-valued apron heights, then equal overlapping
   portal apron heights after the new constraint, while retaining a lower
   tunnel interior and grade/surface slope bounds.
2. Three or more overlapping hubs on one same-grade hairpin form one coherent
   inferred height group, independent of input traversal order. Non-overlapping
   hubs remain independently sloped.
3. Different-way equal-XY crossings, parallel unconnected roads and distinct
   bridge/surface/tunnel grade keys receive **no** new constraints. No navigation
   edge, source ID, direction bit, XZ, width or source tag changes.
4. Contradictory explicit bridge/tunnel bounds in an overlap group reject the
   new result before graph/mesh publication. Do not flatten a legitimate
   grade-separated crossing to make a seam statistic pass.
5. Every affected graph vertex Y matches the new DB and every physical source
   point Y. Re-run complete source conservation, finite/winding/slope,
   centreline coverage and streamed seam audits, then Root's native actual
   current-frame collision/car traversal validation.

## Additional observed class: curved local approach cells

Hindoo Road is also a same-way apron-pair case: source hubs are 5.60 m apart
at 3.2 m apron radii, while an approximately 5 cm source-arc gap leaves a
5.980 mm mismatch. The apron-pair equality addresses that class without
changing routing or snapping source XZ.

Alexandra Road is different. A curved driveway's mitered sloped cell reaches
inside a flat shared-node apron even though its along-source station lies
outside the existing flat radius. It produces a 32.949 mm mismatch. The
repair needs a geometry-aware local cell/apron constraint in addition to
apron-pair constraints; merely increasing a tolerance or flattening every
projected crossing is not valid.

The bounded tested rule compares actual structured-cell footprints against
the coherent apron footprint union, then extends the **local flat approach
radius** only to the actual overlap boundary. Assign each overlap region to
the exact nearest hub by ordered source-arc station, rather than closest XZ
or a merged height group. An overlap on the far end of a looping ramp belongs
to that far portal and must not be drawn into the near portal's source
approach. The existing 128 m plateau cap remains; ambiguous/protected cases
are retained for review. The explicit 1 mm construction guard is a geometric
margin, not a relaxation of the 5 mm validation gate.

Propagate the maximum proposed radius through existing original endpoint
grade-transition groups so all incident ways use the same physical plateau.
Recompute existing structured-section height equalities and per-segment
grade allowances. Allowances only tighten; do not equate both endpoints of
an entire long sloped source cell. Original source segments and node IDs
remain present, and the transition outside the plateau stays sloped.

The rejected first prototype treated merged height groups as interchangeable
local branches and lowered Mandai's portals by about 3.7 m. Its source and
receipt are retained in `prototype-r1-source` and the explicit R1 review.
The second prototype avoided that overreach but retained a 7.798 mm measured
seam; its 9/10 failure is retained in `prototype-r2-source` and its failure
receipt. Neither produced a national artifact. Whole-source-cell equality
is therefore rejected in favor of footprint-derived approach radii.

The final prototype changes only three original hub radii in the targeted
fixture and converges in two rounds. Mandai's last tunnel radius grows from
4.8 m to 5.957519876 m; its matching surface endpoint receives the same radius.
Alexandra's shared radius grows from 5.226971381 m to 7.340229908 m. Ten CPU
tests pass, including the stricter measured portal-displacement regression:
all 26 genuine comparisons are within 0.0846 mm; the protected ramp's 16
multilevel comparisons retain 4.96822 m separation. Mandai's maximum source
height shift is 60.995 mm, Hindoo's 5.980 mm and Alexandra's 39.538 mm, while
Mandai's lower tunnel interior remains unchanged. Original navigation IDs,
directions, lengths, XZ and source tags remain unchanged; profile allowances
only tighten. The contradictory-bound test rejects before height writes.

These are exact-source **miniature starting-profile** tests, not a complete
global DEM/profile solve, country artifact or native traversal result.
`NATIONAL_TARGETED_R3_RADIUS_PROTOTYPE.json` records detailed metrics;
`NATIONAL_TARGETED_R3_FINAL.json` binds the final strict-test source hashes.
The full copied-DB/profile/catalog/mesh run and independent country/native
validation remain outstanding.

The seam audit also needs to retain branch provenance. At each ramp portal,
the physically matching local branch must agree; the far portal's separately
supported level must stay separate. Extra surfaces may be classified as a
protected different level only with explicit original endpoint/grade/profile
evidence. Unexplained multiple surfaces remain review failures. Do not
silently choose the nearest height and thereby hide Mandai/Hindoo defects.
