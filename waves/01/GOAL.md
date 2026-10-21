# Wave 1 goal — "Orchard Reach" (MiniMax M3.1 Flash)

- **Authoring model / wave:** MiniMax M3.1 Flash (via Claude Code CLI, MiniMax subscription), wave 1 of the five-model relay.
- **Incoming model / wave:** none — MiniMax starts the relay and authors its own first goal from the shared user brief (END_GOAL.md).
- **Starting commit:** `a243701` (planning repository, no playable build).
- **Engine and version (locked by me under owner delegation):** Godot **4.7.1.stable** (official build), Forward+ renderer, native **macOS** export.
- **Target platform contract:** desktop macOS (Apple silicon), packaged `.app` / `.zip` build, keyboard + mouse, 1080p, 60 FPS target on the reference machine (Apple M3 Ultra, 256 GB RAM, macOS 27.0.1).
- **Timebox:** four hours. **Start 2026-10-21 07:35:00 UTC. Handoff preparation from 11:05:00 UTC. HARD END 11:35:00 UTC.** No reset, no extension.

## Owner directives carried into this wave

1. The owner delegated technical decisions to the builder/manager; no further engine or contract approval is required for routine choices.
2. Visual target raised to **GTA VI in Singapore, highest attainable fidelity** — GTA V is no longer the bar. Primitives are development placeholders, not final art.
3. Asset generation routes: **Tripo (browser control) for small/bulk/secondary props**, **Customuse (MCP) for major/hero assets**. **Meshy excluded.** No local AI inference. Consuming existing Tripo credits is authorized; buying new credits is not.
4. Neither Tripo browser control nor the Customuse MCP is exposed in this Claude Code CLI (verified by tool search — no browser-control or asset-generation tool is present). Per the directive I therefore publish **`ASSET_REQUESTS.json`** for the manager to execute through the connected surfaces, and continue independent game work.
5. Reference board: `docs/concepts/*.png` (generated concepts of *our* game) are the **primary** art direction; `docs/visual-references.json` entries are secondary fidelity/location evidence only. A reference board is not evidence that our build matches it.
6. Boundaries unchanged: no secrets in outputs, no touching other sessions, no public release or `main` merge, no unapproved charges, normal permission controls.

## What I want to improve (this wave's plan, in order)

1. **Get a genuinely playable native 3D slice running** — connected district, third-person control, shooting, car theft + driving, police response, helicopter board/fly/land/exit, one authored mission that links them.
   - Observable success: a packaged macOS build launches, and an automated playthrough reaches the mission's end state with captures as evidence.
2. **Make the district read as Singapore, not as Manhattan with different signs.**
   - Observable success: shophouse arcades and five-foot ways, void-deck public housing, a roofed hawker hall, a waterfront edge and an aviation compound are present, walkable and distinct.
3. **Establish the evidence spine** (VERIFY-01/02/03): requirement ledger, headless checks, capture packet, honest NOT TESTED marks, and an independent critic pass with blind comparisons.
4. **Leave a clean, reproducible checkpoint** for Astra through Codex: run instructions, known gaps, asset requests, and a successor goal.

## Preserve

- END_GOAL.md requirements (it outranks this goal).
- The relay protocol: one shared source tree, this branch only, no `main` merge.
- Other sessions' files, processes and GPU slots.

## Known gaps at goal-writing time

- No generated/imported hero assets yet (provider surfaces unavailable in this CLI) — buildings, vehicles and characters are procedural placeholder geometry, tracked as a gap, not as finished art.
- No packaged build yet; no runtime captures yet.
- Independent critics: this profile can spawn subagents, but they are **the same MiniMax-class model** wearing a Claude alias. They are useful as an independent-context reviewer, and are **not** a different vendor's model. This is recorded honestly rather than presented as Opus critique.

## Verification

- `godot --headless --path game -- --test` → automated requirement checks (PASS/FAIL output).
- `godot --headless --path game --export-release "macOS" ...` → packaged build.
- Automated playthrough capture (`--capture`) → PNG packet + JSON state log for review.

## Handoff

- Waves 1 evidence in `waves/01/`, `docs/REQUIREMENTS_LEDGER.md`, `docs/asset-manifest.csv`, `NEXT_GOAL.md` (successor: Astra through Codex), and `HANDOFF.md`.
