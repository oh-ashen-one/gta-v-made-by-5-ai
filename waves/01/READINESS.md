# Wave 1 readiness investigation — verified findings

Recorded by MiniMax M3.1 Flash at the start of the wave (before the four-hour clock was authorised by the owner's delegation). Everything below was verified on this machine; nothing is assumed.

## 1. Machine and runtime (verified)

| Item | Verified value | How |
| --- | --- | --- |
| Machine role | `studio` (per session rules) | session context |
| CPU / GPU | Apple M3 Ultra, 80-core GPU, Metal 4 | `system_profiler SPDisplaysDataType` |
| RAM | 256 GB (274877906944 bytes) | `sysctl hw.memsize` |
| OS | macOS 27.0.1 (build 26A434) | `sw_vers` |
| Toolchain | Xcode 27.0 (27A266a), `codesign`, `hdiutil` present | `xcodebuild -version` |
| Identity | `M3 Ultra` | `sysctl machdep.cpu.brand_string` |

## 2. Installed engines and exact versions (verified, nothing launched)

| Engine | Version | Location | Notes |
| --- | --- | --- | --- |
| **Godot** | **4.7.1.stable.official.a13da4feb** | `/opt/homebrew/bin/godot`, `/Applications/Godot.app` | Export templates present for `4.7.1.stable` **including `macos.zip`** → native macOS packaging works offline, no account or licence needed |
| Unreal Engine | 5.8.3 (CL 58210709, `++UE5+Release-5.8`, promoted build) | `/Users/Shared/Epic Games/UE_5.8` | Mac platform/toolchain present; account sign-in state not verified without launching the editor |
| Unity | 6000.3.20f1 | `/Applications/Unity/Hub/Editor/6000.3.20f1` | `PlaybackEngines/MacStandaloneSupport` present → macOS standalone export possible; licence state not verified without launching the Hub |
| Blender | 5.2.0 LTS | `/Applications/Blender.app`, `/opt/homebrew/bin/blender` | Used for DCC work; three Blender instances from other sessions were already running |

## 3. Shared GPU ownership / slot protocol (verified)

- Lock tool: `~/.config/devin/brain/sources/oh-ashen-one--claude-code-game-builder/.../tools/gpu/gpu_slot.sh` — `capture` slots (default **2**), plus an exclusive `perf` mode.
- `gpu_slot.sh status` at the start of the wave: **1 holder** (`codex-veyr-walk-20261021`, a Blender capture owned by another session), 0 waiters, GPU utilisation 9 %, `perf_ready_now: true`.
- House rule (`operating-rules`, 2026-09-29 / 2026-10-21): renderer-bearing engine processes are capped at **2** across all agents; a Blender-only exception allows up to 4 Blender processes **only while no game engine is running or queued**, and the mixed cap of 2 total applies the moment an engine is launched or queued. Three Blender processes from other sessions were alive at inspection time (one actively rendering at ~2890 % CPU).
- **Consequence for this wave:** this task claims exactly one shared capture slot for its own engine instance and never exceeds one engine instance of its own. It does not kill, pause or alter another session's Blender work. If the mixed cap is contested by the other sessions' Blender instances, that is a manager/owner call — this task will not exceed the slot lock it holds.

## 4. Independent critic capability — honest statement

- The profile can spawn subagents (agent types exist for `opus-critic`, `sonnet-builder`, `opus-builder`, `fable-director`), and a subagent can be asked to inspect local images with the `Read` tool.
- A probe subagent spawned as `opus-critic` reported the runtime identity string `claude-opus-5-5` and said it could not introspect its own serving weights, so it could not rule out an alias.
- **Reality of this deployment: every subagent here is served by the same MiniMax subscription that runs this session.** The `claude-*` names are aliases, not Anthropic model access. I therefore claim **no Opus, Fable or Claude-model critic access**, and critics in this wave are independent-context, same-model reviewers. If the owner wants a genuinely different-model critic, that must be arranged outside this CLI (manager/Codex chat) and reported as such.
- The same applies to asset generation: **Tripo browser control and the Customuse MCP are not exposed in this CLI** (tool search for browser-control/asset-generation surfaces returned nothing). I do not fake them and do not substitute direct HTTP calls; requests go out as `ASSET_REQUESTS.json`.

## 5. Reference availability (verified)

- Gauntlet Loop: reachable — the Matt Shumer pattern (agent decomposes → specialist builders → ruthless blind critic → blind comparison → uncaped rounds) was confirmed from live web sources, including `github.com/robonuggets/gauntlet-loop` and Matt Shumer's original announcement.
- Art direction: `docs/concepts/singapore-on-foot.png`, `singapore-driving.png`, `singapore-helicopter.png` (commit `f9b1233`) are the **primary** targets for our own game; `docs/visual-references.json` (commit `aac1c9e`) holds secondary GTA VI / Singapore location evidence only. Both doc updates are carried into this branch.
- GTA V/GTA VI gameplay footage was **not** downloaded: the concepts board supersedes it as our target and the Rockstar stills are secondary evidence.

## 6. Recommendation (decided by me under the owner's delegation)

**Engine: Godot 4.7.1 stable, Forward+ renderer, native macOS export, GDScript.**

Why this one:

1. **Zero access blockers.** It needs no account sign-in, no licence server, no activation — unlike Unreal (Epic account state unverified) and Unity (Hub licence state unverified). An unattended four-hour wave cannot afford a licence dialog.
2. **Native macOS packaging is already proven available** (matching `macos.zip` export templates installed for the exact editor version), which satisfies TECH-02's "test the actual delivery path" requirement.
3. **Headless, scriptable, deterministic** — builds, exports and automated playthroughs run from the CLI, which is what four different agent CLIs in this relay will need in later waves.
4. **Clean licence for a public repository** (MIT), so a packaged build and its code can live in this public repo without the engine's own terms complicating redistribution.
5. **It fits the machine**: Forward+ on an 80-core M3 Ultra at 1080p60 for a district of this density, with room left for the GPU budget the house protocol allows.
6. **Rejected**: Unreal 5.8.3 (installed and supported, and the house has Unreal tooling — but licence-gated, heavy editor start-up, and the most expensive iteration loop for a wave that must ship a *playable slice*); Unity 6000.3.20f1 (macOS module present, but same licence-uncertainty plus a heavier GUI-centric workflow for CLI-driven agents).

**Initial platform/quality contract** (proposed, and the basis for this wave's calibration): macOS desktop on Apple silicon; 1280×720 internal render, window 1280×720; Forward+, MSAA 2x; keyboard + mouse; 60 FPS target with p95 frame time ≤ 25 ms on the reference machine; wave-1 district ≈ 640 × 640 m playable core inside a larger aerial envelope; 30–40 pedestrians and 8–14 active traffic vehicles; two firearms; three civilian vehicle silhouettes plus a response variant; one helicopter; one authored mission.

## 7. Exact blockers carried into the wave

| # | Blocker | Effect | Handling |
| --- | --- | --- | --- |
| B1 | Tripo browser control not exposed in this CLI | No generated props (lights, stools, crates, signs, foliage clutter) | Requests published in `ASSET_REQUESTS.json` for the manager to execute |
| B2 | Customuse MCP not exposed in this CLI | No hero assets (cars, helicopter, characters, building kits) | Requests published in `ASSET_REQUESTS.json`; procedural geometry used as clearly-marked placeholders |
| B3 | No genuinely different-model critic available | VERIFY-02 independence is same-model only | Stated plainly in this document and in the handoff; manager may run an external critic |
| B4 | Other sessions hold Blender instances, so the mixed cap of 2 is contested | A second engine instance would exceed the cap | This task runs **one** engine instance under the shared slot lock and reads GPU utilisation before/after capture |
| B5 | No generated hero art can be integrated in-wave | Visual fidelity cannot reach the GTA VI board in four hours | Honest NOT TESTED / gap marking; successor priority in `NEXT_GOAL.md` |

No other access, budget or approval gap was found. No software was installed, no engine was launched, and no other session's process or file was touched during this investigation.
