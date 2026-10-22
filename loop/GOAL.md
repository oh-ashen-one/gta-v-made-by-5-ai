# /loop goal — Singapore Open World: "Opus 5.5 enhancements"

## Baseline: continue, never restart
Do NOT start a new project. Enhance the existing Godot game ("Orchard Reach") in this repository.
- Working folder (Mac Studio `studio`, Mac15,14 M3 Ultra 256 GB):
  `/Users/midir/Documents/Codex/2026-10-21/https-github-com-oh-ashen-one/work/wave-05-opus`
  It holds the full game, including the git-ignored private provider assets (`game/assets/providers/`,
  `art/source/characters/`, `art/source/helicopter/`, `art/provider-sources/`). Never delete or overwrite them.
- Branch `Opus-5.5-enhancements`, cut from `main` @ `2c66caa` (all five relay waves). Commit often; push
  `origin Opus-5.5-enhancements` after every accepted piece and at every wave. Never commit to, merge into
  or push `main`.
- Engine: stay in Godot 4.7.1 (`/opt/homebrew/bin/godot`, Forward+, Metal). No engine change.
- Read before planning: `END_GOAL.md` (north star for requirements and scope), `HANDOFF.md`,
  `waves/05/RELEASE_REPORT.md`, `waves/05/evidence/critic_review_5_rendered.md`, `waves/05/evidence/rendered/`,
  `docs/REQUIREMENTS_LEDGER.md`, `docs/LOOK_DEV.md`, `docs/ASSET_RIGHTS.md`.
- Owner direction, 2026-10-22: the quality bar for this loop is **Grand Theft Auto V**. END_GOAL's GTA VI
  imagery is a stretch reference, not the pass condition. All other END_GOAL requirements still apply.
- Inherited state: final candidate `98b41b2` code. Baseline re-verified on the Studio 2026-10-22:
  **97/97 headless regressions PASS**. Wave 5: 13/13 mission route, one 30-min headless soak.
  Last critic: on foot 4/10, driving 2/10, helicopter 3/10. Known gaps: near-empty streets and traffic,
  flat haze lighting, water that reads as paving, poor Supertrees/Merlion, a 70 %-dark void deck, blank beige
  aerial roofs, a 1.06 s market hitch, HUD fixes in `98b41b2` never rendered. Starting evidence, not the plan.

## The ask
Build a fully playable, customized open-world action game set in Singapore at the level of Grand Theft Auto V.
It should be utterly perfect, alive and cinematic, with every single thing done at that quality: driving,
movement, interactive characters, the city, sky, missions, and anything else you can think of.

## Run window and model
- **Owner update 2026-10-22 ~17:27Z (supersedes the hard 6-hour limit below):** keep going until the critiques and blind judgements meet the north star (a blind judge prefers ours to GTA V, or cannot tell, and is genuinely wowed) or until the owner stops the run. Work in rolling waves; integrate and push after each wave. All guardrails still apply. Current run state: `loop/RUN.md`.
- One unattended overnight run with a **hard 6-hour wall-clock limit**. First action: write START and
  DEADLINE = START + 6 h (UTC, from `date -u`) to `loop/RUN.md`. Check `date -u` before every new build or
  critique round.
- Hours 0–0.5: read, decompose, capture baseline renders, build the GTA V reference set.
- Hours 0.5–5.25: build/critique rounds, biggest critic-named gap first, in parallel.
- Hours 5.25–6: feature freeze. Integration playthrough, regressions, rendered route, final captures, progress
  page, `HANDOFF.md`, push. Start nothing new after DEADLINE − 45 min. Stop at DEADLINE.
- Every agent runs on Claude Opus 5.5: the session is `claude-opus-5-5-max`; builders and the integrator use
  `subagent_general` (inherits the session model); critics use the `critic` profile (pinned
  `claude-opus-5-5-max`). Do not use `subagent_explore`: its model is router-selected.
- Concurrency: at most 4 builders and 4 critics at a time.

## References
Record reference IDs in every critique and handoff. A blocked image is NOT TESTED.
- **Art direction (END_GOAL §3), what our game should look like:** CONCEPT-01 on foot
  `docs/concepts/singapore-on-foot.png`, CONCEPT-02 driving `docs/concepts/singapore-driving.png`, CONCEPT-03
  helicopter `docs/concepts/singapore-helicopter.png`; place evidence SG-01 Joo Chiat street, SG-02 hawker
  interior, SG-03 waterfront skyline (URLs in END_GOAL §3.2).
- **Quality bar, GTA V:** build a matched GTA V reference set from Rockstar's official GTA V screenshots and
  videos (find them on rockstargames.com; record exact URLs), one or more per piece at comparable camera scale
  and situation: on-foot street, driving chase cam, aerial helicopter, close character, traffic, police,
  interiors, lighting. IDs GTAV-01, GTAV-02, … with source URLs in `loop/REFERENCES.md`. Store the images in
  `loop/references/` (git-ignored). Never commit or ship them.
- **Stretch:** END_GOAL VI-01 to VI-03 (GTA VI).
- Capture our side at matching camera scale, height and lighting.

## Method
1. **Decompose.** Break the game into the smallest pieces that can be improved and judged on their own. You
   decide the pieces. Record them in `loop/PIECES.md`: piece, matched reference IDs, capture spec or play
   scenario, current verdict, open biggest gap.
2. **Build.** Fan out one builder sub-agent per piece in parallel, each in its own git worktree created with
   `bash loop/new_worktree.sh <piece>` (under `.worktrees/`, private assets linked in), so no two agents edit
   the same files. Builders commit on their own `opus55/<piece>` branch; merge accepted pieces into
   `Opus-5.5-enhancements` and re-run the regressions after every merge. /loop on each piece.
3. **Critique the running game.** For every piece, spawn a `critic` sub-agent with fresh context. It launches
   and plays the actual running Godot build: rendered runs, the game's scripted-input capture modes
   (`--capture`, `--photos`, `--gameplay-photos`, or new scenarios it adds to the harness) and encoded
   footage. It inspects the frames and footage itself and never reads the builder's summary or diff. It is a
   harsh critic.
   - Blind side-by-side: our capture versus the matched GTA V reference, labelled A/B in random order. The
     critic picks the better one and explains why. It also checks against the piece's CONCEPT/SG targets for
     Singapore identity.
   - When ours loses, the critic names the single biggest testable gap, and the builder goes back in.
   - No fixed number of rounds within the window. A piece is done only when the critic, blind, prefers ours or
     cannot tell them apart, and is genuinely wowed. Never lower the bar. Never pass something because the
     code exists or the builder says so.
4. **Integrate.** Between major waves, spawn one fresh `subagent_general` to play the whole game end to end
   and smooth everything into one coherent experience. It fixes seams and regressions, re-runs the 97+
   regressions, the 13-gate mission route and a rendered route, and re-captures the standard view set against
   wave 5's renders.
5. **Live progress page.** Keep `progress/index.html` (relative links, compressed JPEG captures under
   `progress/img/`) updated every round with pieces, verdicts, the latest A/B pairs next to their reference
   IDs, open gaps, commits, before/after captures and time remaining. Never put GTA V reference images in
   `progress/`; show their IDs and links. The owner views it through
   `python3 -m http.server 8767 --bind 127.0.0.1 --directory progress` (start it headless at loop start; 8765
   belongs to another project; never bind 0.0.0.0).
6. **Effort.** Maximum thoroughness on every piece ("ultracode").

## How to run the engine on this machine
- Headless (no GPU slot needed): `python3 game/tools/bounded_run.py --seconds N --log ABS.log -- godot
  --headless --path game -- --test --qa-session ABS_DIR`. A fresh worktree first needs
  `godot --headless --path game --import`.
- Rendered (anything that draws frames): always `bash loop/render.sh <label> <seconds> <abs-out-dir> --
  <engine args…>`. It wraps the shared GPU lease (`gpu_slot.sh capture`), `render_gate.py` (refuses when 2
  renderers already run) and `bounded_run.py`. If it refuses, wait and retry later; log the wait in
  `loop/RUN.md`.
- Every QA run passes `--qa-session <task-owned dir>` and never writes the player's real save slot.

## Originality
No Rockstar code, assets, UI, audio, maps or missions (END_GOAL GOV-03). The references set the bar only.
Everything shipped is original.

## Guardrails (house rules; these override "don't stop")
- At most 2 rendering engines on the whole machine (Godot, Blender, `Orchard Reach`), counting other
  sessions'. Never raise the cap, and never touch, signal or wait on other sessions' processes, files or locks.
- After two crashes of the same run, do not auto-relaunch it; record and move on. To stop an engine,
  SIGTERM it and wait up to 60 s; SIGKILL only as a last resort.
- Nothing may open a GUI app, OS dialog or new terminal window (`open`, `osascript` are denied). Background
  jobs stay headless.
- No paid generation (Tripo, Meshy, Customuse, Higgsfield, etc.): there is no owner online to approve spend.
  Use Blender (headless, through `loop/render.sh` if it renders), procedural Godot work and existing assets.
- No package installs. Keep the asset provenance ledger (`docs/asset-manifest.csv`, `docs/ASSET_RIGHTS.md`)
  current for every new or changed asset. No public release or deployment.
- Keep a rolling `HANDOFF.md`. "Don't stop" means never stop because quality is lacking. On a real blocker,
  record it in `loop/RUN.md`, push work in progress and continue with another piece.
- Report honestly (GOV-02). Separate "best build so far" from "north star accepted".
- Clean up `.worktrees/` that have been merged, and `/tmp` scratch you created, before DEADLINE.

## Done
DEADLINE reached with everything committed and pushed to `Opus-5.5-enhancements`; `HANDOFF.md` and
`progress/index.html` report honestly what improved, which pieces the critics now prefer over GTA V, which they
still lose and the next biggest gaps; regressions and rendered and headless routes pass on the final commit.
