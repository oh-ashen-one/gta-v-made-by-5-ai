# Singapore fidelity and owner playtest fixes — active goal

The owner requested the full following end state; incremental fixes do not redefine completion:

1. The two officers near the helicopter must stand on valid floor, react to shooting and take damage correctly.
2. Helicopter mouse look must be a stable free camera with full left/right/up/down control, without the rapid vertical glitch or forced restricted chase direction.
3. Landing and disembarking on ordinary supported roofs must work; remove the street/helipad-only restriction. Retain physical support/clearance and avoid water/unsafe exits.
4. Shift descent must be substantially faster and controllable.
5. Walk up to Marina Bay Sands, enter through a real doorway, and explore its entire built-out interior matching the real building and exterior quality. Public plans/references and gaps must be documented; unverified invented rooms are not proof of a real one-to-one interior.
6. Research map APIs/data and correct Singapore buildings, roads, names and layout to a one-to-one real-world match. Preserve this full target; an initial Marina Bay dataset or conversion is progress, not whole-Singapore completion.
7. Use independent builders and critics, real rendered/runtime verification and a complete requirement-by-requirement audit.

This is a new ongoing goal, not a restart or extension of the completed four-hour pass. No new timebox was requested. Keep it active until the full requested end state is verified or the goal's actual blocked-audit condition is met. Do not claim the prior fictional grid is geospatially accurate.

Base76c9483, integration branchAstra-6-singapore-fidelity. Current model gpt-6.1-sol; inherited-model subagents, no alternate-provider/model claim. Root owns integration, map coordinate/data pipeline and shared main/world/plan changes. Helicopter worker owns helicopter.gd/player.gd and dedicated flight tests. Police worker owns NPC/police systems and dedicated police tests; request coupled Player changes from integrator. MBS researcher owns only loop/singapore-fidelity/research/mbs/ until a source-backed interior contract exists.

Keep the owner's live installed R3 play session intact. Renderers: one task renderer maximum; shared globalcap2, normal GPU lease + last-moment render_gate. Headless tests may proceed independently. No unapproved API billing, credit purchase, account creation/upload or security bypass. Existing project art/provider constraints and source-first asset/animation policy remain. Preserve private art outside public Git; no global settings or main merge.
