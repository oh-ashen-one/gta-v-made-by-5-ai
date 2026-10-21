# GTA V Made by 5 AI

> **Start here: [END_GOAL.md — the Singapore game bible](END_GOAL.md).** This is the fixed project north star and mandatory reading for every builder, reviewer, and handoff. Wave goals choose the next work; they cannot replace or lower its requirements without explicit user approval.

A YouTube development experiment: **five AI coding setups collaborating in sequential waves on one original GTA-style playable 3D game**. This is a shared relay, not a head-to-head competition or a split into separate departments.

## Status

**Relay underway on task branches. Wave 2 delivers a privately packaged experimental candidate with unmet requirements; no visually accepted or public release exists.**

The current build lives in [`game/`](game/): **Godot 4.7.1 stable** (Forward+, GDScript, native macOS export) with an authored Singapore-inspired district, third-person control, two firearms, car theft and arcade driving, left-hand traffic, police response, a flyable helicopter, a roofed hawker hub, a void-deck housing neighbourhood, a waterfront edge and the authored mission "Harbour Relay".

Read [HANDOFF.md](HANDOFF.md) for the current checkpoint, owned-engine/GPU protocol and the private provider-asset transfer. A fresh source clone does not contain those binaries. Godot 4.7.1 is locked.

- Run after obtaining the shared renderer slot: `godot --log-file /tmp/orchard-player.log --path game`
- Export after a project import: `godot --headless --log-file /tmp/orchard-export.log --path game --export-release "macOS" build/mac/OrchardReach.zip` (the export path is relative to `game/`).
- Run bounded regression checks using the commands in [gameplay notes](docs/wave-02/GAMEPLAY_NOTES.md). Headless numerical assertion passes do not certify a clean run: check the supervisor's exit and generic error scan. The latest clean Metal suite has 85 assertions.

The three approved images in [docs/concepts](docs/concepts/) remain the visual target. [Evidence](docs/EVIDENCE.md) separates rendered automation, stills, tests, performance qualifications, packaging and human acceptance.

The required Singapore-inspired playable slice is specified in [END_GOAL.md](END_GOAL.md); the engine is locked to Godot 4.7.1 (rationale in [`waves/01/READINESS.md`](waves/01/READINESS.md)), the development machine is the Mac Studio, and the numerical calibration is in progress. **MiniMax starts; Opus 5.5 through Claude Code must take the final wave.** Where each requirement stands is recorded in [`docs/REQUIREMENTS_LEDGER.md`](docs/REQUIREMENTS_LEDGER.md) — art fidelity, audio depth, traffic behaviour under pressure and every performance measurement are still open, and the generated hero art is integrated but not committed (provider terms, not MIT; see [`docs/asset-manifest.csv`](docs/asset-manifest.csv)). This is a playable experimental build, not a claim of a visually accepted one.

## The five setups and wave order

The owner has authorized the five-wave relay. Each wave must verify its actual model/tool access rather than infer availability from the planned name.

| Wave | Setup | Status / planning note |
| --- | --- | --- |
| 1 | MiniMax | Incoming checkpoint `4df93fa631d9484fb29e556a97df61a259620248`; see waves/01. |
| 2 | GPT-6 Astra through Codex | Completed implementation on `feature/wave-02-astra`; fixed 2026-10-21 11:38:01–15:38:01 UTC window. See HANDOFF.md for final evidence and private archive. |
| 3 | DeepSeek V4.1 Flash through Devin | Owner-designated successor; manager starts the next session. See NEXT_GOAL.md. Actual availability must be verified by that session. |
| 4 | Argon 4 via AGY CLI | Proposed fourth wave; user-reported setup. |
| 5 — final | Opus 5.5 through Claude Code | Required final wave; user-selected model name, not verified availability. |

Model names are planned selections, not claims of verified product availability. Confirm exact versions, access, and configuration before execution. No local AI models are planned for this video.

## One shared toolbox

**Owner update, 2026-10-21:** GTA VI-level visual fidelity in Singapore is the target; see the illustrated reference board in END_GOAL.md. Only Tripo browser control for smaller/bulk assets and Customuse MCP for major assets are approved generation routes. Meshy is excluded. Existing Tripo credits are authorized. Builders make routine decisions autonomously; the manager handles timed handoffs. The update supersedes earlier planning notes below.

Every wave uses **Tripo through browser control** and **Customuse through MCP** according to the split above, with Blender/DCC tools for asset processing. No model is limited to a particular asset tool or department.

Each model can create, modify, or replace 3D assets and improve the entire game: gameplay, visuals, controls, world design, performance, or anything else needed for its wave. Tool connections, capabilities, account access, licenses, and credits still need confirmation. Listing these tools is **not permission to purchase credits or incur charges**.

## How the relay works

Each AI inherits the **whole current game** and builds on the previous reviewed checkpoint. The aim is to show the same project improving wave by wave, not five independent games.

Owner-authorized sequence: **MiniMax → Astra / Codex → DeepSeek / Devin → Argon 4 / AGY CLI → Opus 5.5 / Claude Code**.

**Goal relay:** MiniMax writes its own starting goal from the shared user brief. Each outgoing model then writes the next model's goal, including what needs improvement and why. The incoming model may reassess priorities, but records any deviations. Opus 5.5 ends with a release report, not a sixth-wave goal.

**Owner-authorized timebox:** four hours of wall-clock time per wave, with the final 30 minutes reserved for testing, capture and handoff. The manager enforces each fixed deadline. This repository contains the implementation and observed evidence, not a claim that every planned setup is already running.

Every wave leaves:
- A reviewable commit/checkpoint and clear summary of changes.
- Test results and known issues, including anything not tested.
- Comparable before/after footage once a playable baseline exists.
- Asset provenance, redistribution status, and the predecessor-authored next goal (or final release report).

Later waves should preserve a working baseline while improving it. Use the [relay protocol](docs/RELAY_PROTOCOL.md), [wave handoff template](docs/WAVE_HANDOFF.md), and [contribution workflow](CONTRIBUTING.md). Goals are platform-neutral Markdown files; a literal `/goal` command is not assumed to exist in every CLI.

## Current work

Use the rolling [handoff](HANDOFF.md), the [successor goal](NEXT_GOAL.md), and the complete [requirements ledger](docs/REQUIREMENTS_LEDGER.md). Preserve working systems and the Godot engine lock. The large fidelity gap, human playtest, complex traffic/pursuit, isolated performance and per-asset public redistribution remain explicit gates.

## Original project, not Rockstar source

The title is the video/project title. This is an independent, original game-development experiment, not a release of Grand Theft Auto V source code or a recreation of its proprietary content. It is not affiliated with or endorsed by Rockstar Games or Take-Two Interactive.

Do not commit proprietary game code, extracted game assets, paid asset packs without redistribution rights, credentials, or private project material.

## License and assets

The [MIT License](LICENSE) applies to this repository's original code only. It does **not** blanket-license generated or third-party assets, engine components, music, names, or trademarks.

For every asset, record the provider/source, creation or download date, applicable license or terms, attribution requirements, and whether public redistribution is permitted. A successful generation or export does not by itself establish permission to publish the result. Keep assets out of the public repository until their redistribution rights are confirmed; their respective licenses apply separately.
