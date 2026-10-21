# Packaged UI and save/relaunch probe

The `ui_review.gd` fixture runs the actual title New Game and Continue handlers in two fresh app processes. It records deterministic QA state, rendered screenshots, exact save-file digests, process identity, engine version, engine-relative startup/capture ticks, and actual raster dimensions. This is scripted fixture evidence; it does not establish OS-input usability, human acceptance, or isolated performance.

Use the executable inside the freshly exported `.app`. Run the writer to terminal exit and reap it before starting the reader. Root owns the shared GPU lease, bounded wrapper, error-log scan, export identity and actual exit verification. Use the **same absolute capture directory** for both invocations:

```text
<exported-app-executable> -- --qa-session --ui-review --save-path=/tmp/orchard-reach-ui-review-<unique-run>.json --capture-dir=<absolute-evidence-directory>
<exported-app-executable> -- --qa-session --ui-review --ui-review-load --save-path=/tmp/orchard-reach-ui-review-<unique-run>.json --capture-dir=<same-absolute-evidence-directory>
```

Engine flags such as `--log-file` precede `--`; fixture flags follow it. Select a new run filename and evidence directory. The temp parent directory must already exist. Both `/tmp/` and macOS `/private/tmp/` are accepted. Missing `--qa-session`, duplicate/missing save-path flags, paths outside temp, filenames not beginning `orchard-reach-ui-review-` or ending `.json`, symlink components, and a path differing from `Game._save_path` fail before New Game, Continue or save mutation. Ordinary `user://` saves are never selected.

The writer captures title, New Game, pause, settings, return to pause, then the saved QA fixture. Fixture values are health **83**, sensitivity **1.3**, invert Y/reduced shake/HUD **true**, SMG magazine **17** and reserve **123**, with initial mission stage/checkpoint and on-foot control. It calls normal `Game.save_game()`, reads and validates the resulting JSON, captures the held weapon, emits `ui-review-write.json`, and requests native quit.

The reader requires the writer report to pass, its PID to differ, its executable path to match, and its save digest to match. It calls `main._continue_game()` and checks health/settings/ammo/mission/player position and held SMG. It captures the restored game and settings roundtrip, verifies Continue did not rewrite the file, writes `ui-review-load.json`, and requests native quit. Provider weapon attachment is checked when the rig is available; procedural fallback is explicitly labelled.

Each invocation has a 45-second in-engine watchdog, bounded JSON reads (1 MiB), and fixed capture count. The supervisor must separately bound startup and exit because an engine deadlock can prevent the in-engine watchdog from running. A report records **requested** exit; the external wrapper/reaping evidence closes the actual exit gate. `startup_ready_ticks_msec` measures Godot's elapsed clock when scene setup completes, not an external OS launch timestamp. Each screenshot records backing raster dimensions; command-line resolution alone is not proof.

Source was changed only after the freeze ended at 14:27:54 UTC. No engine, renderer, Blender or test process was launched by this worker. Runtime validation is pending root's exported-app runs.
