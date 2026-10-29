# Query-local complete-inventory reuse — independent read-only review

No introduced source-level correctness blocker found in the current Runtime grouping change. This review changed no production code and ran no engine or Git command. Root reports the revised SourceActor inventory fixture passed80checks, including same-tick disabled/freed shared-body cases; that is a scoped native result, not whole-world performance acceptance.

## Actual reason for the change

WorldR2 was stopped by Root's verified supervisorTERM, exit−15/no fatal/reaped after421seconds. The last durable progress row was at319.908wall seconds: walk_to_car had traveled14.748m in4.383simulation seconds, with3.281m remaining and recent progress. Observed interval throughput was1.278physicsHz. Runtime had2271queries totaling245,668,614µs, approximately108.2ms/query. Nine regions referenced the same6625body inventory. These measurements support repeated residency traversal as an actual cost; they do not prove the selected approach was blocked or that the revised grouping meets FPS.

## Source reasoning

`commit_region` copies each complete body list into new WeakRefs and hashes its ordered native instance-ID strings. The comma-delimited integer sequence is unambiguous; list length/order/membership are represented. Caller-array mutation cannot alter the copied registry inventory. Duplicate or reordered body lists can miss reuse but do not cause incorrect reuse. The SHA is a descriptor, not a liveness verdict or authentication boundary.

`checked_inventories` and `checked_bodies` are newly allocated for each synchronous `_resident_impl` call. The loop has no yield, user callback or scene mutation. A group whose first inspection fails caches false only for that identical inventory in that call. Every other inventory is assessed separately, while already checked individual bodies retain their same-query property result. Origin revision is checked before group reuse. There is no inter-frame native-readiness cache.

Coverage subtraction still runs per live region, and every live token is still collected even after spatial coverage is complete. This preserves a contact stamp leased to a nonintersecting/overlapping neighbor whose complete inventory is shared. Grouping does not replace region bounds, support ownership, generation tokens or Context stamp verification.

The old and new `_resident_impl` validate live scene membership, collision layer and World3D. The stronger native-shape-count/support-stamp checks in `region_status` remain a separate existing path. This optimization does not add or remove that distinction. Normal retirement still must retire leases/disable collision before destruction; descriptor equality is not proof that arbitrary same-process code has not changed shape topology. No adversarial private-registry-mutation guarantee is claimed.

## Recommended negative and counter cases

1. Identical `[A,B]` groups: disable or freeB; every group must fail within the next query, with the false verdict reused. Restore layer within the same tick and query again; the new query must reread and recover.
2. `[A,B]` invalid versus `[A,C]` valid, sharingA: a false complete-inventory group must not poison a distinct valid inventory. This tests full membership, not only a shared first body.
3. `[A,B]`, `[B,A]`, `[A]`, and duplicate-containing lists: different order/length descriptors must not be incorrectly treated as identical. Missed reuse is acceptable; missing validation is not.
4. A floor stamp owned by a spatially nonintersecting neighbor that shares the inventory: its live token must remain available after another region already covers the query. Retire that owner and verify the existing support-lease transfer.
5. A stale-origin region sorted before a current-origin identical inventory must not supply the cached verdict. Retirement/recommit must use the new generation token.
6. In a successful nine-identical-region query, observed inventory reference visits should be6625, with one group scan/eight reuses, while all nine live tokens remain. Query latency and physics throughput must be measured again under the actual source world; the theoretical visit reduction is not FPS evidence.

Artificially forging a private `body_inventory_key` for a different list is outside the constructor/immutable-registry contract and is not a substitute for the real mixed-membership cases above. No spatial filtering or cross-query cache is recommended from this review.
