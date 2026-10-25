# GTA V Made by 5 AI

> **Start here: [END_GOAL.md — the Singapore game bible](END_GOAL.md).** This is the fixed project north star and mandatory reading for every builder, reviewer, and handoff. Wave goals choose the next work; they cannot replace or lower its requirements without explicit user approval.

A YouTube development experiment: **five AI coding setups collaborating in sequential waves on one original GTA-style playable 3D game**. This is a shared relay, not a head-to-head competition or a split into separate departments.

## Status

The original five-model relay is complete. This branch contains the owner's separate **25 October2026 four-hour enhancement pass**, `Astra-6-enhancements`, using the current Codex session and builder/critic subagents. Start with [HANDOFF.md](HANDOFF.md) and the [current verification report](loop/astra-6/VERIFICATION.md). The candidate is ready for owner review with explicit unmet gates; it is not a public or visually accepted release.

The native **Godot4.7.1 Forward+** build retains the existing heritage district, central Singapore landmarks, connected streets/bridges, combat, vehicles, helicopter and Harbour Relay mission. This pass adds a repeatable Bayfront Courier journey, repairs pedestrian transition lips, opens a public MBS SkyPark lift/terrace/landing area, and substantially reduces traffic and roadside parking.

The final package passes296 headless core checks and24/23 rendered UI save/relaunch checks. The rendered courier journey passes44 checks over3.68km without jumps, deaths or teleport steps. Native keyboard checks also cover normal movement, car controls and the packaged SkyPark lift. Native ragdoll gates, the extended mixed workload and the rendered core watchdog/performance gate remain open. See the report for the exact scope of each pass and failure; headless checks are not rendered-performance acceptance.

Source is in [game/](game/). A fresh source clone requires the private assets described in [private-assets.json](loop/astra-6/private-assets.json); those binaries are not blanket MIT assets. The privately delivered ZIP and50-image gallery are identified in [DELIVERY.json](loop/astra-6/DELIVERY.json). The three [approved concepts](docs/concepts/) remain the visual target, not gameplay evidence.

Use the shared renderer lease and last-moment safety check before running the game. Task-local bounded helpers are in [loop/astra-6](loop/astra-6/). The engine remains Godot4.7.1. Do not merge main or publish builds without the owner's separate authorization.

## Original five-model relay history

The following are historical recorded setups, not claims of current model availability. The relay does not restart automatically when the owner requests later enhancements.

| Wave | Recorded setup | Preserved result |
| --- | --- | --- |
| 1 | MiniMax M3.1 Flash through Claude Code | `feature/wave-01-orchard-reach`, checkpoint4df93fa; [wave1](waves/01/). |
| 2 | GPT-6 Astra through Codex | `feature/wave-02-astra`, checkpoint658741b; [wave2](waves/02/). |
| 3 | DeepSeek V4.1 Flash Max through Devin | `feature/wave-03-deepseek`, checkpoint96c6833; [wave3](waves/03/). |
| 4 | Gemini4 Argon High through AGY | `feature/wave-04-argon`, preserved checkpoint2966829; final source was not runtime-validated in that wave. [Archived handoff](waves/04/ARGON_HANDOFF_AT_STOP.md). |
| 5 | Opus5.5 through Claude Code | Original final wave; [release report](waves/05/RELEASE_REPORT.md). Later owner-directed work is separately documented. |

## One shared toolbox

**Owner update, 2026-10-21:** GTA VI-level visual fidelity in Singapore is the target; see the illustrated reference board in END_GOAL.md. Only Tripo browser control for smaller/bulk assets and Customuse MCP for major assets are approved generation routes. Meshy is excluded. Existing Tripo credits are authorized. Builders make routine decisions autonomously; the manager handles timed handoffs. The update supersedes earlier planning notes below.

Every wave uses **Tripo through browser control** and **Customuse through MCP** according to the split above, with Blender/DCC tools for asset processing. No model is limited to a particular asset tool or department.

Each model can create, modify, or replace 3D assets and improve the entire game: gameplay, visuals, controls, world design, performance, or anything else needed for its wave. Tool connections, capabilities, account access, licenses, and credits still need confirmation. Listing these tools is **not permission to purchase credits or incur charges**.

## Historical relay protocol

Each relay AI inherited the **whole current game** and builds on the previous reviewed checkpoint. The aim is to show the same project improving wave by wave, not five independent games.

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
