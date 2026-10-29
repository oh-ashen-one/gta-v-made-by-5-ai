# Root query-local residency deduplication — read-only review

Reviewed `source_runtime.gd` commit `aad6631` against prior `5e7593d`. No introduced synchronous-query semantic blocker found by code inspection. This is code-only review, not a native or performance pass.

The checked-body dictionary is created inside each `_resident_impl` call. The loop yields nowhere, invokes no user callback and performs no scene/origin mutation. `is_instance_valid` precedes instance-ID access. A false cached body state invalidates every region that shares it, and a new call rereads current tree membership, collision layer and World3D. There is no inter-frame readiness cache.

Origin revision and current World3D are hoisted within that same synchronous main-thread routine. Region order and bounded box-union subtraction are unchanged. Every live region token remains collected even after spatial coverage is complete; this preserves a support stamp leased from an overlapping/nonintersecting adjacent region. The4096fragment work cap is unchanged. Early exit within an invalid region changes redundant work, not its acceptance. Profiling now counts unique liveness checks instead of nominal shared region references.

Both the old and new `_resident_impl` check scene-node lifetime/tree/layer/world properties. Neither performs the stronger PhysicsServer shape-count or support-stamp checks present in `region_status`. The optimization preserves that previous scope; it must not be described as adding or removing full native-server shape validation. A last-shape-removal case can expose this existing distinction. Normal Root retirement disables layers and retires leases before native destruction.

Recommended native regression gates: immediate layer0 without waiting a frame; freed body; live body moved to another World3D; a body shared by several regions; overlapping region coverage where the support stamp belongs to a nonintersecting adjacent region; and unchanged original actor hold/restore/lease-transfer cases. Actual profiling and test evidence remain Root-owned. Child changed no Runtime source and launched no engine/GPU/Git action.
