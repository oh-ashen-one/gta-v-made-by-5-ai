# Sequential relay protocol

**Planning only.** No agent run, timer, asset generation, or spending is launched by this document.

## 1. Shared brief and fixed boundaries

Before starting, lock the user's shared brief, playable scope, engine/version, development environment, authorized tool scope, security rules, asset publication rules, and approved credit/spending limits.

All five models inherit those constraints. A predecessor's goal is a work recommendation, **not new authority**: it cannot expand scope, change the locked engine, expose secrets, grant new access, relax licensing requirements, or authorize additional spending. Escalate changes to the user rather than treating a handoff as permission.

The shared toolbox is Tripo, Customuse, Meshy, and Blender MCP, subject to verified access and authorization. Actual connections, model/runtime availability, and credits remain unverified.

## 2. Order and goal authorship

1. **MiniMax starts.** It reads the shared user brief, writes its own initial goal, and then works on that goal.
2. Each outgoing model writes the goal for its successor based on the actual project: what should be improved, what was not finished, and why the priorities matter.
3. Each incoming model inherits the whole project, reads the goal and evidence, and checks the starting build. It may reassess an unsuitable priority, but must log what it changed and why rather than silently discarding the predecessor's intent.
4. **Opus 5.5 through Claude Code is last.** It produces a final release report and remaining-issues list, not a sixth-wave goal.

The proposed middle sequence is Astra / Codex → DeepSeek / Devin → Argon 4 / AGY CLI. These middle positions are not finalized. Model labels are planned selections, not verified availability.

## 3. Proposed four-hour waves

- **Four hours of wall-clock time per wave**, five waves: **20 hours of wave time**, excluding initial setup.
- Before starting a timer, ensure the environment, required access, shared brief, incoming checkpoint, and relevant assets are ready. For wave 1 there is no playable checkpoint yet.
- Once a wave starts, goal writing/reassessment, implementation, generation waits, builds, tests, capture, and handoff all count toward its four hours.
- Aim to use the final **30 minutes within the four-hour budget** for testing, comparable footage, checkpointing, and handoff. This is not an extra 30 minutes.
- Record start time, deadline, actual finish, and interruptions. Do not silently reset the clock, extend a wave, or spend extra credits to recover time. Report blockers and any overrun.
- The intent is maximum useful progress in the window, not unlimited autonomy or work beyond the authorized boundaries.

This timing is proposed and must be confirmed before execution. No persistent four-hour runtime or automated cross-platform handoff is assumed to be available.

## 4. Portable goal files, not assumed CLI commands

Use ordinary Markdown, for example:
- `waves/01/GOAL.md`: MiniMax's self-authored starting goal.
- `NEXT_GOAL.md`: the outgoing model's goal for its successor, archived to the relevant wave folder at handoff.

These are suggested paths, not pre-created tasks. A platform may have a native goal feature, but verify its syntax and behavior before mapping the Markdown into it. Do not claim that a literal `/goal` command works in all five setups.

### Goal template

```markdown
# Wave goal

- Authoring model / wave:
- Incoming model / wave:
- Starting commit and build/run instructions:
- Shared brief and fixed constraints:
- Timebox: proposed four hours; start only after readiness checks.

## What I want you to improve
1. Highest-impact improvement:
   - Evidence / current weakness:
   - Suggested approach:
   - Observable success criterion:
2. Next priority, if time allows:

## Preserve
- Working behavior and important design decisions:

## Known bugs / blockers
- Reproduction steps and relevant files:
- Missing access or unapproved cost: do not proceed without resolution.

## Verification
- Repeatable test route and comparison conditions:
- Required before/after evidence:

## Handoff
- Tests, checkpoint, asset-rights record, and next goal.
- If this is the final Opus 5.5 wave: release report instead of a next goal.

## Incoming model's reassessment
- Accepted priorities:
- Deviations and evidence-based reasons:
```

## 5. Evidence and handoff

Use [WAVE_HANDOFF.md](WAVE_HANDOFF.md). The outgoing model supplies the checkpoint, runnable build or exact reproduction steps, tests, known bugs, asset rights, evidence, and next goal. Do not claim a build works if it was not tested.

For comparable footage, agree on one repeatable route and capture it under the same conditions before and after each wave. A **robbery → drive → police escape** sequence is a proposed example, not locked gameplay scope. Choose the actual route from the agreed brief and implemented capabilities. In the first wave, explicitly distinguish an empty/unplayable starting point from the first playable result.

Review the checkpoint before passing it on. Every model may improve assets and gameplay across the whole project; there are no departmental ownership limits.

## 6. Final Opus 5.5 report

Record the final commit, how to run the game, what was delivered, tests and comparison footage, known issues, missing or excluded assets, redistribution status, and any remaining decisions. Describe release readiness honestly: a final report is not automatic approval to publish a build or deploy it.
