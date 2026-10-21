# Contributing

**Mandatory first read: [END_GOAL.md](END_GOAL.md).** It is the fixed north star for every builder and reviewer; predecessor-authored goals prioritize work, not rewrite requirements. Only explicit user approval changes the north star. The user handles Gauntlet execution-loop setup separately; do not add or launch loop tooling as part of these documentation instructions.

This is a sequential AI relay on one shared game. Every wave inherits the previous reviewed checkpoint and can improve gameplay, visuals, assets, or any other aspect of the project.

**MiniMax starts and authors its own initial goal from the shared user brief. Opus 5.5 through Claude Code takes the final wave.** The proposed middle order is Astra / Codex → DeepSeek / Devin → Argon 4 / AGY CLI. Model labels and tool availability must be verified before execution.

## Wave workflow

Follow the [relay protocol](docs/RELAY_PROTOCOL.md). Four wall-clock hours per wave, 20 hours across five waves excluding initial setup, is the proposed timebox—not an active run.

1. Lock the shared user brief, scope, engine, security/tool boundaries, asset rules, and approved budget before starting. Confirm required access and readiness before starting a wave's timer.
2. MiniMax writes its own first goal; later models receive a goal authored by their predecessor. Reassess when necessary, but log deviations and reasons.
3. Start from the previous reviewed checkpoint on a separate branch. Do not create an unrelated replacement project.
4. Use available and authorized shared tools: Tripo, Customuse, Meshy, and Blender MCP. Assets may be created, modified, or replaced; tools are not assigned to separate departments.
5. Reserve the final 30 minutes within the proposed four-hour window for tests, comparable before/after capture, a reviewable checkpoint, and the [wave handoff](docs/WAVE_HANDOFF.md).
6. Author the successor's goal with evidence, known bugs, priorities, and success criteria. Opus 5.5 instead writes the final release report; there is no sixth wave.
7. Review before merging and passing on the checkpoint. State clearly what was not tested, and preserve the working baseline.

Goal files are platform-neutral Markdown, such as `NEXT_GOAL.md`; do not assume every CLI supports a literal `/goal` command. A predecessor's goal cannot expand the user's authorization or fixed project constraints.

## Public repository hygiene

Contribute only original code you have the right to share under the MIT License. Generated and third-party assets are not automatically MIT-licensed. Before publishing an asset, record its source/provider, date, applicable terms or license, attribution requirements, and confirmed public redistribution permission. If permission is unclear, exclude the asset from the public repository.

Never commit secrets, private notes, proprietary game source, extracted game assets, or assets without redistribution rights. Tool access is not spending authorization: do not purchase credits or incur unapproved charges.
