# Gameplay critic R3 — R2 fixes verified; one new P2

Independent GPT-6 Astra critic; same model as builders. Base commit `cf211e6d23bb18c4e5ffe03830a8d9d64606780c`, plus live changes captured by hashes below. Injected native key events into real headless gameplay; fixture repositioning is disclosed. No renderer/gameplay-source edits or owner-save writes. QA default save was verified as `/tmp/critic-wave2-save.json` before proceeding.

Observed checks:

- **PASS — pause/settings ownership.** Esc → F3 → F3 ended paused, pause panel visible, Settings closed, cursor visible. W moved **0.000 m**.
- **PASS — disabled-car eligibility.** Disabled sedan produced no target and an empty prompt. Re-enabling it restored selection and `[E] Take Sedan`.
- **PASS — isolated native F5/F6.** F5 saved health 73, SMG inventory, and all four modified settings. Replacement saved health 67 with changed bytes and no remaining temporary file. F9 → F6 restored health 67/settings/HUD visibility, hid title, unpaused control; W moved **1.056 m**.
- **PASS — failure preserves prior save.** Invalid live health rejected a write without changing previous bytes. An intentionally blocked temporary-file path also returned false and preserved previous bytes. Malformed settings were rejected without changing checked live state. Source uses same-directory temporary write/flush/rename (`game_state.gd:249–272`). Sudden-power-loss durability was **NOT TESTED**.
- **PASS — fresh-process persistence.** A second process started with defaults, then native title F6 restored sensitivity **1.1**, invert/shake **true**, HUD **false**, health **67**, and active gameplay.

**New P2 — saved weapon appearance does not restore.** Both runs reproduced: save while holding `smg_held.glb`, switch to pistol (or relaunch), then Continue. `Game.carried_weapon` becomes `smg`, but `player._weapon_model.scene_file_path` remains `pistol_held.glb`. Load restores weapon data (`game_state.gd:303`) without refreshing the held model/animation attachment. Add one shared inventory-restored visual refresh and retest both weapon directions. Subsequent source edits after these launches are not certified by this report. No new P1 was found within this bounded scope.

Reviewed the rendered route's raw `capture_log.json` and `qualification.json`: **13/13 gates, 639.15 m driving, 722.18 m flight, intact landing/exit/delivery, zero deaths, 217.92 seconds**. This strengthens scripted rendered mission evidence. It does not close native human acceptance, aircraft reboarding/return, or active cross-mode pursuit (wanted was already zero before car exit). The qualification correctly excludes performance acceptance despite the raw `rendered_performance_valid` flag. Moving footage was not visually reviewed here.

Evidence: [main probe/results/log/hashes](tests/critic-r3/probe.meta.json), [results](tests/critic-r3/probe.json), [reproduction](tests/critic-r3/probe.gd), [fresh-process results](tests/critic-r3/relaunch.json), [relaunch hashes](tests/critic-r3/relaunch.meta.json). Both processes exited **0**, reaped in **7.33 s / 4.66 s**, without script errors.

| Source | Main-probe SHA256 |
| --- | --- |
| `main.gd` | `edf64a83568a93436a83d6802fb19b8dc0f5a10daede8efe0cd5ef1d78c6fdaa` |
| `game_state.gd` | `f618f3a0daf2caaabe6498b706905d634d271b720a1663c888c8cd6ac8820448` |
| `player.gd` | `140d319e94e36ae9e337bc6445b69eb01f49a0fc1202ee1502fde466ba66608b` |
| `car.gd` | `8d4461c9ca375e8534716440d8cb684c765f47b3939645f00357bcf6113dd490` |
| `hud.gd` | `b6f6a3d9147b8dd8d4f41356f19e85884a0de81d432d3834773d10fbfdd9afe8` |

Relaunch changed player/world/capture source hashes; main/Game/car/HUD were unchanged. Relaunch player SHA256: `bdd92ed8d9f1cdea6a29b5b7b0c2aa25fd9193042564ae397ffdabddcc4b4b8e`. Full per-run inventories are preserved above.
