# Wave 1 handoff — "Orchard Reach" (MiniMax M3.1 Flash)

Copy of the [wave handoff template](../../../docs/WAVE_HANDOFF.md), filled with the actual wave-1 results.

## Checkpoint and timebox

- **Wave number and AI setup / exact model:** wave 1, MiniMax M3.1 Flash through the Claude Code CLI on the owner's MiniMax subscription (session `adb1f608-eafc-413b-b218-4cbe9d13a426`).
- **Starting commit:** `a243701` (planning repository, no playable build).
- **Resulting commit or pull request:** `feature/wave-01-orchard-reach` pushed to `origin/feature/wave-01-orchard-reach` (the manager branch `codex/minimax-wave-01` is left at its own state).
- **Engine and version:** **Godot 4.7.1.stable** (official build), Forward+ renderer, GDScript, native macOS export. Chosen by the builder under owner delegation; rationale and rejected alternatives in `waves/01/READINESS.md`.
- **Runnable build or exact open/run/play instructions:**
  - From source: `godot --path game` (opens the game; press ENTER on the title screen).
  - Packaged build: `godot --headless --path game --export-release "macOS" build/mac/OrchardReach.zip` (the export path is relative to the project folder; the `.zip` is git-ignored, so rebuild locally).
  - Automated checks: `godot --headless --path game -- --test` → prints PASS/FAIL per check and exits non-zero on failure.
  - A fresh clone must first run `godot --headless --editor --path game --quit` once to build the `class_name` cache, and `bash game/tools/fetch_provider_assets.sh` + `blender --background --python game/tools/cleanup_provider_assets.py` to restore the provider art.
- **Readiness checks completed:** engine inventory and versions, macOS export templates, Xcode/Metal availability, shared GPU slot state, critic capability, reference availability, provider-surface availability — all recorded in `waves/01/READINESS.md`.
- **Start time / four-hour deadline / actual finish:** start **2026-10-21 07:35:00 UTC**, hard end **11:35:00 UTC**, handoff preparation from **11:05:00 UTC** (see `HANDOFF.md` for the final state).
- **Interruptions or overruns:** none of the clock. The wave spent time on: fixing GDScript type-inference errors, making the automated playthrough navigate the street grid, and a Blender cleanup pipeline for eight provider hero models and nine Tripo props (including a 1.87 M-triangle prop that had to be reduced to 4 000).
- **Tools used and approved credits consumed:** Godot 4.7.1 (local), Blender 5.2.0 LTS (local), `curl`-free asset staging via the manager. **No local AI inference. No purchases by the builder.** The manager spent existing Customuse credits on eight hero models and existing Tripo credits on nine props; the builder bought nothing.

## Goal and changes

- **End-goal requirement IDs addressed, evidence status, and remaining gaps:** see `docs/REQUIREMENTS_LEDGER.md` for the full table. In summary: WORLD-02/03 (precincts and Singapore form), PLAYER-01/02/03, COMBAT-01/03, NPC-01/02, CAR-01/02, TRAFFIC-01, AIR-01/02/04, LAW-01/02, MISSION-01/02, UI-01/02, SAVE-01, SYSTEM-01/03, TECH-01/02, ASSET-03/05 are implemented and exercised; ART-05, ART-08, AUDIO-01, TRAFFIC-02, LAW-04, MISSION-03/04 and the performance gates are partial or open.
- **Incoming goal path and author:** none — MiniMax authored its own first goal, `waves/01/GOAL.md`.
- **Accepted priorities:** as written in `waves/01/GOAL.md`: playable connected slice first, then Singapore identity, then the evidence spine, then a clean checkpoint.
- **Reassessed priorities / deviations and evidence-based reasons:** the visual bar was raised by the owner mid-wave from GTA V to **GTA VI in Singapore**, with generated concept art as the primary target; the wave therefore spent its second half on a Blender asset-cleanup pipeline and on integrating the generated hero art. Recorded in `waves/01/GOAL.md` and `HANDOFF.md`.
- **Gameplay / controls changes:** third-person over-the-shoulder camera with collision, settings panel (sensitivity, invert-Y, reduced shake), two firearms with reload and ammo pools, car theft with driver displacement, arcade driving, helicopter board/fly/land/exit, "Harbour Relay" mission with checkpoints and a clean restart.
- **World / visual / asset changes:** an authored district of five precincts (heritage shophouse street, void-deck public housing, roofed hawker hall, waterfront edge, aviation compound), procedural materials and surface noise, crosswalks and signal heads, street furniture, cables, bus shelters, a procedural audio bank, and the integration of the generated sedan, coupe, van, helicopter, shophouse module, HDB slab, hawker table, character, officer, lamps, AC units, planters, clutter, airfield crates and both weapons.
- **Technical or performance changes:** 33 automated headless checks; triangle budgets enforced on every provider import (the raw Tripo table was 1.87 M triangles, reduced to 4 000); provider assets are kept out of the public repository with fetch instructions and SHA256 provenance.
- **Working behavior preserved:** the whole game is original; the north star in END_GOAL.md is untouched; the manager documentation branch is not modified.

## Verification and comparison

- **Tests run and results:** `godot --headless --path game -- --test` → **33/33 PASS** at the handoff commit: 20 structural checks plus 13 behavioural regression checks added after the independent review (control ownership on vehicle entry, death-in-vehicle release, camera restoration, walking after a vehicle death, the scripted-input path, traffic longevity, wanted decay, pause semantics, the mission package pickup advancing the stage, and health regeneration). The automated playthrough capture (`--capture`) drives the real systems through the real input actions and writes `game/captures/capture_log.json`; fixed-view captures are written by `--photos`.
- **Independent review:** a subagent critic reviewed the wave-1 code with six headless runtime probes. It is the **same MiniMax model** as the builder (this CLI has no Opus/Fable access), so VERIFY-02 is only partially satisfied. Its findings and the wave's fixes are listed in `docs/REQUIREMENTS_LEDGER.md` under "Wave-1 independent review and what it changed"; the transition table it asked for is `docs/TRANSITION_TABLE.md`.
- **Not tested:** 30-minute soak, three consecutive mission completions, frame-time percentiles (PERF-02/03/04), an uncut human golden path (QA-018), audio quality review, and any independent-vendor review (see the critic note below).
- **Known issues or regressions, with reproduction steps:** traffic can still deadlock at a junction; police pursuit state does not survive a controller change as designed (QA-012); the generated character and officer are unrigged and are therefore used only as static figures; the player avatar is still the procedural figure.
- **Before footage / screenshots:** the starting point had no build at all (planning repository only).
- **After footage / screenshots:** `game/captures/` — automated playthrough frames and fixed-view district frames.
- **Agreed repeatable test route:** safe room → hawker centre (package) → car theft → drive to the aviation compound → helicopter → waterfront landing → on-foot delivery.
- **Comparison conditions:** same machine (Apple M3 Ultra), same 1280×720 Forward+ preset, same seed (`20261021`), HUD on for gameplay frames.

## Asset rights record

Full table in `docs/asset-manifest.csv`. Summary: all original code is MIT (this repository). The eight Customuse models and ten Tripo props are **provider terms, not MIT**; they are staged in `game/assets/providers/` (git-ignored), their public URLs and SHA256 values are recorded, and the eight Customuse sources are re-fetchable automatically with `game/tools/fetch_provider_assets.sh` (the ten Tripo exports need a **manual browser step**, which the script documents). The rights check in `docs/ASSET_RIGHTS.md` found that the Customuse terms (19 June 2026) permit lawful personal and commercial use of the outputs with no attribution requirement — but **the output review is partial**: only the sedan and the helicopter were rendered and found free of marks, the character shows a sneaker mark, the van and the coupe show badge artifacts, and thirteen outputs were never rendered. **The provider binaries are therefore not cleared for public redistribution yet**, and they stay out of the history for that reason as well as for size. The generated concept board in `docs/concepts/` is project-owned art committed by the manager. No GTA asset, no third-party model and no credential is in the tree.

| Asset / path | Provider or source | Date | License / terms reference | Attribution required | Public redistribution confirmed? | Included or excluded |
| --- | --- | --- | --- | --- | --- | --- |
| `W1-HERO-001` sedan, `002` coupe, `003` delivery van, `004` helicopter, `005` player figure, `006` officer, `007` shophouse module, `008` housing slab (raw GLB + cleaned game asset) | Customuse MCP (8 jobs, 1 400 credits of existing balance) | 2026-10-21 | <https://customuse.com/terms> (19 June 2026) | no | **terms: yes** (lawful personal and commercial use, no attribution). **Output clearance: 2 of 8 verified** — the sedan and the helicopter were rendered and are free of marks; the character shows a sneaker mark and the van and the coupe show badge artifacts; the rest were never rendered | **excluded from git** for repository size and unverified mark clearance; source IDs, URLs and SHA256 in `docs/asset-manifest.csv`, re-fetchable with `game/tools/fetch_provider_assets.sh` |
| `W1-PROP-010`…`018` hawker table, food trolley, street lamp, air-con unit, planter, service clutter, airfield clutter, hawker counter (raw GLB + cleaned game asset) | Tripo browser (10 props, 550 credits of existing balance) | 2026-10-21 | <https://www.tripo3d.ai/help/privacy-policy/how-to-use-tripo-models-commercially> | no | **terms: yes** for the owner's account, **but the per-job labels (in particular any "personal use only" flag) were not checked individually**. **Output clearance: UNVERIFIED** — none of the ten was rendered for mark inspection | **excluded from git**; the fetch script records the studio links and checksums, but the export itself is a **manual browser step**, not an automatic download |
| `docs/concepts/*.png` (3) and `docs/concepts/prompts.json` | generated concept board for this project, produced by the manager | 2026-10-21 | project-owned art | not applicable | yes | **included** (committed on the task branch) |
| `docs/asset-deliveries/wave-01.json` | manager's delivery record (source IDs, hashes, actual credit spend) | 2026-10-21 | internal record | not applicable | yes (contains no credentials) | **included** |
| All original code, procedural geometry, materials and the procedural audio bank | this repository | 2026-10-21 | MIT (this repository) | not applicable | yes | **included** |

## Verdict (END_GOAL VERIFY-08)

**Playable experimental build with unmet requirements.** Not "north star accepted", and not "not yet reliably playable".

What the wave-1 build demonstrably does: launches as a native 3D game, presents an authored Singapore-inspired district with five distinct precincts, moves a third-person character with a working camera, fires two firearms that damage and kill NPCs, lets the player steal an occupied car and drive it through left-hand traffic, escalates a wanted level that now rises and falls, spawns police that pursue and stand down, flies a helicopter that can be boarded, landed and exited, and runs the "Harbour Relay" mission spine end to end in an automated playthrough. The engine is locked, the requirement ledger is honest, and every provider asset is documented, rights-checked and reproducible.

What it is not: the GTA VI visual bar (the art is a mix of generated hero assets and procedural geometry, and the character is still unrigged), a spatial soundscape, a traffic system with signals, a pursuit model with search and concealment, a measured performance result, or a build with an independent-vendor critic. Those gaps are named, owned and prioritised in `NEXT_GOAL.md`.

## Next goal

- **Successor and next goal file:** `NEXT_GOAL.md`, addressed to **Astra through Codex**.
- **"I want you to improve...":** see `NEXT_GOAL.md` — rig the generated character, finish the prop set, close the audio/traffic/pursuit gaps, and turn the automated playthrough into a measured evidence pipeline with an independent critic.
- **Why this matters:** the art gap is the largest remaining distance to the GTA VI bar, and the evidence gaps are what currently prevent an honest verdict.
- **What I could not finish:** rigging and animating the generated character, spatial audio, traffic rerouting, the search phase's concealment mechanic, mission replay cleanliness, and every performance measurement.
- **Suggested approach and observable success criteria:** as written in `NEXT_GOAL.md`.
- **Important behavior to preserve:** the `Game`/`Events` authority split, the left-hand lane graph, the arcade vehicle model, the "Harbour Relay" spine, the look-dev sheet, and the triangle-budget discipline on every provider import.
- **Known bugs, reproduction steps, and relevant files:** as listed above.
- **Unresolved access, license, or budget decisions:** the provider art may be published (the rights check permits redistribution) — the owner decides whether to commit the binaries or attach them as a release asset; Customuse's balance is down to 53 and must not be spent further without new authorisation (Tripo is at 75 450); the character rigging pipeline is unproven; the fifteen provider outputs that were not individually rendered for mark inspection remain an open item for the rights record.
