# Next goal — wave 2 for **Astra through Codex**

- **Authoring model / wave:** MiniMax M3.1 Flash (wave 1, outgoing).
- **Incoming model / wave:** Astra through Codex (wave 2).
- **Incoming checkpoint:** the wave-1 commit pushed to `origin/codex/minimax-wave-01` (branch `codex/minimax-wave-01`); wave-1 source tree lives in `game/` (Godot 4.7.1).
- **How to run:**
  - `godot --path game` (editor/play from source), or
  - `godot --headless --path game --export-release "macOS" game/build/mac/OrchardReach.zip` (packaged build), or
  - `godot --headless --path game -- --test` (20 automated checks; expect `20/20 checks passed`).
- **Shared brief and fixed constraints:** END_GOAL.md is the destination and outranks this goal. The engine is **locked**: Godot 4.7.1 stable, Forward+, native macOS export — do not migrate engines. No local AI inference. No secrets in the repository. No `main` merge without the owner. Tripo (browser) for small/bulk/secondary props, Customuse (MCP) for hero assets, **Meshy excluded**; existing Tripo credits are authorised, new purchases are not.
- **Visual bar:** GTA VI in Singapore, highest attainable fidelity. The primary art direction is the generated concept board in `docs/concepts/` (on-foot, driving, helicopter). `docs/visual-references.json` is secondary location/fidelity evidence only. A concept board is **not** evidence that our build matches it — runtime pixels are.

## What I want you to improve, in priority order

1. **Replace the placeholder art with real assets — the single biggest gap.**
   - Evidence: every mesh in wave 1 is procedural placeholder geometry (`game/src/world/world_builder.gd`, `game/src/actors/*.gd`); `docs/REQUIREMENTS_LEDGER.md` marks ART-02, ART-05, ART-06 and ART-08 as **Fail/Partial**.
   - The wave-1 builder had **no** Tripo browser control and **no** Customuse MCP inside its CLI. Requests are published in **`ASSET_REQUESTS.json`** (18 entries: hero vehicles, helicopter, characters, building kits, hawker stall, and bulk props). If you have those surfaces, execute the requests and bring the results back; if not, keep the requests accurate and route them to the manager.
   - Observable success: the sedan, coupe, van, helicopter, player character and shophouse module exist as imported GLBs with real materials, correct scale, collision and (for characters) a usable skeleton; the district stops reading as an untextured greybox.

2. **Raise the visual fidelity of the district itself.**
   - Evidence: capture packet `game/captures/` shows flat, low-detail surfaces; materials are noise-textured but unmapped; no detail props, decals, signage graphics or surface variation per unit.
   - Suggested approach: signage text and shop graphics as real textures (original wording only), roof-tile and shutter repetition, balcony and AC-unit variation, kerb and drain detailing, wet/dry surface variation, real foliage cards inside dimensional canopies, improved sun/exposure pass.
   - Observable success: an independent reviewer comparing our street capture with `docs/concepts/singapore-on-foot.png` can no longer call it a placeholder.

3. **Close the gameplay gaps that the wave-1 ledger marks as Fail/Partial.**
   - `AUDIO-01` — **no audio at all.** Footsteps with surface variation, engines and tyres, rotor sound, gunfire, police response, street ambience and a distinct hawker interior. This is the loudest hole in the experience.
   - `TRAFFIC-02` — traffic does not react to blockers; congestion can deadlock a junction. Needs stop/queue/reroute behaviour and pedestrian-crossing response.
   - `LAW-04` — escape is heat decay only; no search phase, no concealment, no readable "search has ended" feedback.
   - `QA-012` / `MISSION-04` — pursuit and mission state do not yet survive controller changes and replay cleanly.
   - `MISSION-03` — a second meaningful checkpoint and explicit restart/abandon controls.
   - Observable success: the ledger rows for AUDIO-01, TRAFFIC-02, LAW-04, QA-012 and MISSION-04 move off Fail/Partial with evidence links.

4. **Turn the automated playthrough into a real evidence pipeline.**
   - Evidence: `game/src/systems/capture_director.gd` drives the game with real input actions and writes `game/captures/*.png` + `capture_log.json`; it is a scripted playtest, not an uncut human run (QA-018 is therefore only Partial).
   - Suggested approach: add frame-time/percentile capture during the same route, a repeated-run soak (three mission completions), and per-gate screenshot sets for QA-002 … QA-020.
   - Observable success: `PERF-02`/`PERF-03`/`PERF-04` can be marked with measured numbers instead of "Not started".

5. **Get a genuinely independent critic onto the loop.**
   - Evidence: wave 1's critic pass was performed by subagents of the *same* MiniMax model (this CLI's profile exposes no Opus/Fable despite the alias names). VERIFY-02 independence is therefore only Partial.
   - Suggested approach: run the wave-2 review from the Codex chat with a genuinely different model, blind A/B on our captures versus the concept board, and record the reviewer identity honestly.

## Preserve

- `game/src/core/game_state.gd` as the single authority for health, mode, wanted level, mission stage and save/load; `game/src/core/events.gd` as the only cross-system bus (SYSTEM-01).
- The `Game` / `Events` autoload contract and the existing `Assets` request schema.
- The left-hand-traffic lane graph (`traffic_manager.gd`, 25 junctions, left-lane offset) and the arcade vehicle model — both work and are cheap to keep.
- The mission "Harbour Relay" spine: safe room → hawker package → theft → drive → police → helicopter → landing → delivery, and its checkpoint semantics.
- Existing capture packet, ledger and asset manifest formats.
- The reference board as the *primary* art target and the concept-first comparison method.

## Known bugs / blockers

- **Provider surfaces (blocker for task 1):** wave 1 had neither Tripo browser control nor the Customuse MCP. Keep `ASSET_REQUESTS.json` current; do not fabricate assets or substitute direct HTTP calls to Tripo.
- **No real-time physics:** vehicles and the helicopter use a hand-written kinematic arcade model rather than a physics engine. It is reliable at district speeds but has no suspension, no real collision impulse and no deformation.
- **Traffic can deadlock** at junctions and AI cars can damage parked cars (wave 1 patched parked-car damage so it no longer disables them, but AI/AI contact still applies damage).
- **Populated city is light:** ~34 pedestrians and 14 traffic vehicles for a 640 × 640 m district — density is far below END_GOAL WORLD-07 targets and must be profiled before raising the numbers.
- **Interior coverage:** only the safe room, hawker hall and delivery point are modelled interiors; the shop/workshop/mission-room set required by WORLD-05 does not exist yet.
- **Camera/settings:** no sensitivity/invert/reduced-shake options UI (PLAYER-02/UI-03 are Partial).
- **Missing engine cache:** a fresh clone must run one editor import (`godot --headless --editor --path game --quit`) before the class-name cache exists, otherwise `class_name` types fail to resolve.

## Verification

- Repeatable route: the automated playthrough (`--capture`) plus a human golden path (foot → armed encounter → theft/driving → police → helicopter → landing → on-foot conclusion).
- Comparison conditions: same route, same camera, same time-of-day preset, same machine; capture at 1280×720 with the HUD visible for gameplay shots and HUD-hidden for beauty shots.
- Required before/after evidence: capture sets from both checkpoints, a requirements-ledger diff, and the perf numbers from the stress route.

## Handoff

- Update `docs/REQUIREMENTS_LEDGER.md`, `docs/asset-manifest.csv` (provenance for every imported asset) and `HANDOFF.md`; push the task branch; write the next goal for DeepSeek / Devin.
- If the wave-2 result is still short of the north star, say so plainly: the verdict is "playable experimental build with unmet requirements" until the hard gates in VERIFY-05 and the major blockers in VERIFY-06 are cleared.

## Incoming model's reassessment

- Accepted priorities: all five, in the order given — art first, then the Fail/Partial gameplay rows, then the evidence pipeline and an independent critic.
- Deviations: none yet. If you reorder, log the reason and the evidence for it here.
