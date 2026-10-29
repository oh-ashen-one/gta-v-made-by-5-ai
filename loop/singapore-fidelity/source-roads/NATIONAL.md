# Independent national physical expansion

This task leaves the committed R5 compiler/runtime/native fixture and the usable R5 core artifact **unchanged**. National output has a separate identity and remains unapproved until its own audits and later Root native/world validation. No engine, Git, account, API charge or download is performed here.

## Scope and estimate

The streaming estimate found257845 source ways, of which147184 meet the **same exact R5 physical selection policy**:143663 surface,1672 bridge and1849 tunnel records.110478 noncar/restricted/unresolved-access/direction paths and183 indoor-level paths remain in the complete906-owner graph, not claimed physically materialized. This is not a claim that every national footpath/indoor path is finished. Bridge/tunnel construction/datum limitations remain exactly R5's declared reconstruction limits.

The rough bbox estimate was768 separate1km cells/~161000 way-cell candidates, about7million triangles and2–3GB of physical JSON. Actual segment-envelope indexing produced762 candidate cells. It uses original projected segment envelopes plus a conservative two-halfwidth miter margin for **render indexing only**; it creates no navigation adjacency or XY source-node merge. Original whole-way geometry and cross-border retained extensions are preserved without asserting those extensions are Singapore territory, dry land or supported scene.

The source graph/profile is pinned R5:

```text
root: /private/tmp/singapore-fidelity/source-roads/candidate-r5
identity: fc5cb6cbaa19307597e412c779305c72fa373ba18d3e2470811042df3fab9db7
database SHA256: b594e4c9c946820797c527cac2da900a68e81101b28459c1e88a63d0b92618aa
frozen kernel SHA256: c203c52106c1caea2e473512533794259a3bc9d28dd01e80a43f91d6e63b59e5
```

`expand_national.py` imports and verifies that frozen kernel, reads its profile DB read-only, and never recomputes tags, routing, widths, grade policy or source heights. The existing whole-batch exporter collects features and rescans all ways, so this independent wrapper caches a disk-backed spatial index and emits one1km work tile at a time. Parts cap at180000 vertices and32MiB (24MiB target), compatible with the frozen runtime limits. The static `physical_tile_groups` manifest maps each spatial cell to its `.pNNN` resource keys. A future adoption caller must load all parts; no runtime agent generation or9tile country fence is introduced.

## Incremental ownership and bounds

Each tile writes immutable hash/size descriptors and a receipt before a transaction marks its source-way fragment conservation and completion. A same-byte checkpoint is reusable; different bytes, unverified partial indices, active worker locks, changed code/source/kernel provenance, source aliases and symlinks are refused. The original R5 directory cannot be an output. Supervisor tracks only its own worker and retains2GiB RSS/3600CPU/7200wall limits with TERM/grace before any last-resort kill. Jobs run through existing `/usr/sbin/taskpolicy -b nice -n 10`.

`country-r1` stopped safely after26/762 tiles: an additional national face exceeded0.121. The measured case was way465794573 at tile−18_6; plain tile-relative Float32 coordinates yielded0.123752. The same exact frozen geometry/profile with a feature-local XZ anchor yielded0.119649. A Y-only anchor did not solve it. This evidence is in `NATIONAL_R1_SLOPE_FAILURE.json` and the portable codec regression.

The wrapper-only correction constructs feature-local coordinate anchors **only when needed**, recomputes with the unchanged kernel and keeps the unchanged0.121 cutoff. It changes neither canonical source points nor grade policy, masks, normals or an acceptance assertion. Anchor metadata records the codec choice. The frozen runtime already restores canonical anchor+local coordinates in double space before subtracting its active source origin. Actual current-frame native geometry still has its separate runtime check; no native pass follows from the encoding repair.

The separate `country-r2` run reused only the hashed complete index and26 verified completed tile parts of this task's terminal `country-r1`; it did not take over a live/foreign loop or modify prior evidence. All subsequent output is under the new owned prefix.

## Current production command

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python \
  loop/singapore-fidelity/source-roads/expand_national.py \
  --source /private/tmp/singapore-fidelity/source-roads/candidate-r5 \
  --identity fc5cb6cbaa19307597e412c779305c72fa373ba18d3e2470811042df3fab9db7 \
  --database-sha b594e4c9c946820797c527cac2da900a68e81101b28459c1e88a63d0b92618aa \
  --output /private/tmp/singapore-fidelity/source-roads/country-r2 \
  --reuse-country /private/tmp/singapore-fidelity/source-roads/country-r1 \
  --expected-reuse-index-sha 984a42b50a634ff4d3bd5c80a374f7fadf96d1ed5bbf8786f6ce541782dc9678
```

Use a fresh output for a new recipe. `--resume` is only for an identical owned wrapper/kernel/source binding and completed index under a non-active lock. It is not permission to resume another task's process or overwrite different checkpoints.

## Separate bounded validation

`audit_national.py` is independent of the producer. It verifies byte-identical906 graph catalogs, every physical feature's original name/policy/ordered source vertices and canonical R5 height profile, part catalogs/hashes/size/vertices, actual emitted winding/normals/slopes, eligible source-way conservation and source centreline coverage. It reads one part at a time. The seam phase builds a disk-backed source incidence index, assigns each junction to one spatial cell and loads only a3×3 neighborhood of relevant way fragments; it never loads the country triangle corpus into RAM.

```sh
/usr/sbin/taskpolicy -b nice -n 10 /private/tmp/orchard-geodata/venv/bin/python \
  loop/singapore-fidelity/source-roads/audit_national.py \
  --country <completed-country-root> --country-identity <actual-new-identity> \
  --source /private/tmp/singapore-fidelity/source-roads/candidate-r5 \
  --source-identity fc5cb6cbaa19307597e412c779305c72fa373ba18d3e2470811042df3fab9db7 \
  --output <fresh-owned-audit-directory> --phase all
```

Each audit phase has the same2GiB/3600CPU/7200wall supervisor guard. Separate `source`/`seams` phases are available if batching is needed. A source/mesh failure, missing surface, over5mm source-connected near-junction overlap, resource stop or nonzero worker exit remains a failure/review state. Near-junction sampling is not all-area/full-curve/native/production-car/performance acceptance.

Six wrapper and three audit tests passed. Root must retain the usable R5 core, perform separate national validation/adoption, and keep terrain, domain/support, source saves/rebases and the global 48 ambient / 7 physics traffic budgets explicit. Source/DEM attribution and OpenStreetMap/ODbL data licensing remain separate from code licensing.

## Completed country candidate, complete seam review failure

The separate country artifact completed with worker exit 0:

```text
root: /private/tmp/singapore-fidelity/source-roads/country-r2
identity SHA256: 3b0afb19be2c7261e44cc121c804f690bb4bca439fc332e42860f46105812c8a
manifest SHA256: 046666561358b9cd98d198e4588f77613782a90c5c26790a1633e9c46d75098b
```

All 762 candidate cells were processed. Three contained no actual fragment;
759 nonempty parts represent all 147,184 eligible ways with 158,807 fragments,
7,206,586 triangles and 21,619,758 vertices. Physical JSON totals
2,134,459,271 bytes; the 906 copied graph catalogs total 1,047,985,659 bytes.
The producer retained the exact R5 source points, graph, policies and heights.
Seventeen fragments use the documented adaptive coordinate anchor. Producer
wall time was 1,851.7 seconds and sampled peak RSS 270,417,920 bytes.

The separate full source/mesh audit **passed** with worker exit 0: all eligible
ways conserved, 739,002 physical centreline samples covered, every actual face
finite with correct collision winding and surface slope at most
0.12098962984611059, and all 906 graph files byte-identical to R5. The largest
part contains 125,868 vertices. Audit wall time was 320.9 seconds and sampled
peak RSS 401,047,552 bytes. Portable identity-bound receipts are retained under
`country-r2-records/`; the immutable artifact's original pending-validation
manifest is not rewritten after an audit.

**Do not adopt the national candidate.** The full streamed seam audit completed
113,363 source-connected junction groups, 2,532,609 samples and 3,411,827
overlap comparisons. It retained all 42 comparisons above the unchanged 5 mm
review threshold, with no truncated examples. Worker exit 1 is the deliberate
review result, not an engine crash. Audit wall time was 1,463.7 seconds and
sampled peak RSS 526,041,088 bytes. The independent
one-cell diagnostic retained in `country-r2-records/first-outlier-diagnosis.json`
identifies source way `1366486110`: its two endpoints are only about 4.72 m
apart while the carriageway is 9.6 m wide. Their different canonical heights
produce overlapping endpoint plateaus. Adjoining ways `1501294999` and
`639421794` expose the mismatch. This is multi-valued ribbon geometry, not a
reason to relax numerical tolerances or a claim about current native driving.
The other cases are a 5.980 mm Hindoo Road overlapping-apron issue, a
32.949 mm Alexandra Road curved miter/flat-apron overlap, and a protected
4.96822 m parking-ramp level separation. That ramp's ports connect explicit
layer-1 parking and building-passage grades; its two levels must not be
flattened together. The latter also exposes why comparing every triangle on
an entire long way is not by itself a branch-aware junction criterion.
`country-r2-records/classification.json` retains the complete four-class
inventory, original tags, source order/points, hub facts and continuation-grade
signatures. The proposed repair is separately documented and not applied to
this immutable R2 artifact. The diagnostic helper changes no geometry,
source profile or artifact.

No national scene, native collision, production-car traversal, terrain
clearance, country boundary, source-world support, save/rebase integration or
performance acceptance follows from these CPU results. Inferred bridge/tunnel
profiles and unresolved grade/datum constraints remain explicitly declared.
