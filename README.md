# GTA V Made by 5 AI

A YouTube development experiment: **five AI coding setups collaborating in sequential waves on one original GTA-style playable 3D game**. This is a shared relay, not a head-to-head competition or a split into separate departments.

## Status

**Planning / starter repository — no playable build yet.**

The engine, development machine, first playable scope, and initial wave order are still to be finalized. **Opus 5.5 through Claude Code must take the final wave.** No game implementation or asset generation has started in this repository.

## The five setups and wave order

The first four positions below are **proposed**, not finalized. The final Opus 5.5 wave is the project requirement.

| Wave | Setup | Status / planning note |
| --- | --- | --- |
| 1 | MiniMax | Proposed starting setup. |
| 2 | Astra through Codex | Proposed second wave. |
| 3 | DeepSeek through Devin | Proposed third wave. Working assumption: DeepSeek V4.1 Flash through the Devin monthly subscription; availability and exact model tag are not verified. No separate model API billing is planned. |
| 4 | Argon 4 via AGY CLI | Proposed fourth wave; user-reported setup. |
| 5 — final | Opus 5.5 through Claude Code | Required final wave; user-selected model name, not verified availability. |

Model names are planned selections, not claims of verified product availability. Confirm exact versions, access, and configuration before execution. No local AI models are planned for this video.

## One shared toolbox

Every wave may use **Tripo, Customuse ("Custom Muse"), Meshy, and Blender MCP**. No model is limited to a particular asset tool or department.

Each model can create, modify, or replace 3D assets and improve the entire game: gameplay, visuals, controls, world design, performance, or anything else needed for its wave. Tool connections, capabilities, account access, licenses, and credits still need confirmation. Listing these tools is **not permission to purchase credits or incur charges**.

## How the relay works

Each AI inherits the **whole current game** and builds on the previous reviewed checkpoint. The aim is to show the same project improving wave by wave, not five independent games.

Proposed sequence: **MiniMax → Astra / Codex → DeepSeek / Devin → Argon 4 / AGY CLI → Opus 5.5 / Claude Code**. Only Opus 5.5's final position is fixed.

Every wave leaves:
- A reviewable commit/checkpoint and clear summary of changes.
- Test results and known issues, including anything not tested.
- Comparable before/after footage once a playable baseline exists.
- Asset provenance, redistribution status, and notes for the next model.

Later waves should preserve a working baseline while improving it. Use the [wave handoff template](docs/WAVE_HANDOFF.md) and [contribution workflow](CONTRIBUTING.md).

## Next decisions

- Choose the engine and development environment.
- Agree on an ambitious, clearly bounded first playable.
- Confirm the first four waves, wave goals, and handoff criteria.
- Confirm shared tool access, permitted assets, and any approved credit budget.
- Decide how to capture consistent before/after comparisons.

## Original project, not Rockstar source

The title is the video/project title. This is an independent, original game-development experiment, not a release of Grand Theft Auto V source code or a recreation of its proprietary content. It is not affiliated with or endorsed by Rockstar Games or Take-Two Interactive.

Do not commit proprietary game code, extracted game assets, paid asset packs without redistribution rights, credentials, or private project material.

## License and assets

The [MIT License](LICENSE) applies to this repository's original code only. It does **not** blanket-license generated or third-party assets, engine components, music, names, or trademarks.

For every asset, record the provider/source, creation or download date, applicable license or terms, attribution requirements, and whether public redistribution is permitted. A successful generation or export does not by itself establish permission to publish the result. Keep assets out of the public repository until their redistribution rights are confirmed; their respective licenses apply separately.
