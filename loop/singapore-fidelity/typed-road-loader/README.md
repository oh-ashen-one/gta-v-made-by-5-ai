# Typed road loader and exact local anchors — candidate

The old loader flattened source anchor plus local vertex into native world arrays. The typed physical audit found five slope-cap failures caused by the second Float32 quantization. The candidate keeps the encoded local vertices in collision and visual meshes and translates their bodies/instances by the projected source anchor. It still validates every canonical vertex against the active frame. Only exactly identical source anchors may share a collision/visual batch.

The v1 typed contract derives fixed limits from an enumerated surface class, corroborated by original source mode/type evidence. Car geometry retains0.122; explicit foot-only ribbons use0.252; explicit source steps use0.702. File-supplied caps cannot widen these values. This is the qualified v3-profile prototype contract, not the future physical-access-independent v4 contract. Unknown contracts refuse. Existing untyped car fixtures remain supported.

Step walking collision and visible treads/risers are distinct arrays. The native loader validates walking normals/grade and visual normal/winding separately, retaining the shared input work bounds. It never substitutes visible step geometry for collision or certifies character animation from triangle counts.

Physical parts carry explicit cell identities and contiguous three-digit ordinals. SourceWorld loads every part before creating one road support group for that cell. It retains the recoveredR5 data pin; the new v3 typed prototype has not been silently adopted as complete city geometry. Partial dataset coverage, omitted cases, terrain interaction, private roads and foot-area support still need their explicit later proofs.

The old batch fixture's expectation that five differently anchored features collapse into one world-coordinate body is obsolete. Native verification must compare per-source face geometry together with actual body/shape transforms, retain a positive same-anchor batching test, and exercise the exact five failed projection cases. World-space re-flattened cross-products are diagnostics, not a substitute for querying the actual transformed physics shapes and ray normals.

No native parse, physics or performance result is claimed for this candidate yet. Independent review and new QA are being prepared. Keep the prior failures and exact source fixtures; do not loosen slopes, remove collision or move actors to manufacture a pass.
