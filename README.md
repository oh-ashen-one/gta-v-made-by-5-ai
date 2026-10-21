# GTA V Made by 5 AI

> **Start here: [END_GOAL.md — the Singapore game bible](END_GOAL.md).** This is the fixed project north star and mandatory reading for every builder, reviewer, and handoff. Wave goals choose the next work; they cannot replace or lower its requirements without explicit user approval.

A YouTube development experiment: **five AI coding setups collaborating in sequential waves on one original GTA-style playable 3D game**. This is a shared relay, not a head-to-head competition or a split into separate departments.

## Status

**Relay underway on task branches — no accepted playable build yet.**

The required Singapore-inspired playable slice is specified in [END_GOAL.md](END_GOAL.md). Engine, development machine, numerical calibration, and middle-wave order still need confirmation. **MiniMax starts; Opus 5.5 through Claude Code must take the final wave.** Implementation has started on the MiniMax wave branch. This is not a claim of a verified playable or visually accepted build.

## The five setups and wave order

MiniMax is the starting model and Opus 5.5 is the final model. The three middle positions below are **proposed**, not finalized.

| Wave | Setup | Status / planning note |
| --- | --- | --- |
| 1 | MiniMax | Starts the relay and writes its own initial goal from the shared user brief. |
| 2 | Astra through Codex | Proposed second wave. |
| 3 | DeepSeek through Devin | Proposed third wave. Working assumption: DeepSeek V4.1 Flash through the Devin monthly subscription; availability and exact model tag are not verified. No separate model API billing is planned. |
| 4 | Argon 4 via AGY CLI | Proposed fourth wave; user-reported setup. |
| 5 — final | Opus 5.5 through Claude Code | Required final wave; user-selected model name, not verified availability. |

Model names are planned selections, not claims of verified product availability. Confirm exact versions, access, and configuration before execution. No local AI models are planned for this video.

## One shared toolbox

**Owner update, 2026-10-21:** GTA VI-level visual fidelity in Singapore is the target; see the illustrated reference board in END_GOAL.md. Only Tripo browser control for smaller/bulk assets and Customuse MCP for major assets are approved generation routes. Meshy is excluded. Existing Tripo credits are authorized. Builders make routine decisions autonomously; the manager handles timed handoffs. The update supersedes earlier planning notes below.

Every wave uses **Tripo through browser control** and **Customuse through MCP** according to the split above, with Blender/DCC tools for asset processing. No model is limited to a particular asset tool or department.

Each model can create, modify, or replace 3D assets and improve the entire game: gameplay, visuals, controls, world design, performance, or anything else needed for its wave. Tool connections, capabilities, account access, licenses, and credits still need confirmation. Listing these tools is **not permission to purchase credits or incur charges**.

## How the relay works

Each AI inherits the **whole current game** and builds on the previous reviewed checkpoint. The aim is to show the same project improving wave by wave, not five independent games.

Proposed sequence: **MiniMax → Astra / Codex → DeepSeek / Devin → Argon 4 / AGY CLI → Opus 5.5 / Claude Code**. MiniMax's starting position and Opus 5.5's final position are fixed; the middle order remains proposed.

**Goal relay:** MiniMax writes its own starting goal from the shared user brief. Each outgoing model then writes the next model's goal, including what needs improvement and why. The incoming model may reassess priorities, but records any deviations. Opus 5.5 ends with a release report, not a sixth-wave goal.

**Proposed timebox:** four hours of wall-clock time per wave, or 20 hours across five waves, excluding initial setup. Start a wave only when its prerequisites are ready; reserve the final 30 minutes within its four hours for testing, capture, and handoff. No timers or runs have been launched. The user handles Gauntlet execution-loop setup separately; these documents do not implement or launch it.

Every wave leaves:
- A reviewable commit/checkpoint and clear summary of changes.
- Test results and known issues, including anything not tested.
- Comparable before/after footage once a playable baseline exists.
- Asset provenance, redistribution status, and the predecessor-authored next goal (or final release report).

Later waves should preserve a working baseline while improving it. Use the [relay protocol](docs/RELAY_PROTOCOL.md), [wave handoff template](docs/WAVE_HANDOFF.md), and [contribution workflow](CONTRIBUTING.md). Goals are platform-neutral Markdown files; a literal `/goal` command is not assumed to exist in every CLI.

## Next decisions

- Choose the engine and development environment.
- Lock the implementation/calibration contract against the required [end goal](END_GOAL.md); do not silently reduce it.
- Confirm the middle-wave order, proposed four-hour timebox, and handoff criteria.
- Confirm shared tool access, permitted assets, and any approved credit budget.
- Decide how to capture consistent before/after comparisons.

## Original project, not Rockstar source

The title is the video/project title. This is an independent, original game-development experiment, not a release of Grand Theft Auto V source code or a recreation of its proprietary content. It is not affiliated with or endorsed by Rockstar Games or Take-Two Interactive.

Do not commit proprietary game code, extracted game assets, paid asset packs without redistribution rights, credentials, or private project material.

## License and assets

The [MIT License](LICENSE) applies to this repository's original code only. It does **not** blanket-license generated or third-party assets, engine components, music, names, or trademarks.

For every asset, record the provider/source, creation or download date, applicable license or terms, attribution requirements, and whether public redistribution is permitted. A successful generation or export does not by itself establish permission to publish the result. Keep assets out of the public repository until their redistribution rights are confirmed; their respective licenses apply separately.
