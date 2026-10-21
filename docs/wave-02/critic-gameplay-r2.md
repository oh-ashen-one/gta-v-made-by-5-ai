# Gameplay critic R2 — targeted fixes verified; remaining defects

Fresh-context GPT-6 Astra critic, same model as builders; no whole-game or cross-model acceptance. Independently executed native-event and disclosed floating-fixture probes against working tree base `9937fc99a45c845b6c7a24d1a55b1f1fa3b3af04`. No gameplay source edits or renderer. The bounded headless Godot 4.7.1 process exited **0**, reaped after **7.50 seconds**, without script errors. Relevant source hashes stayed unchanged during the run.

Verified results:

- **PASS — original title pause/restart failures.** W behind title moved **0.000 m**; Enter → W moved **1.365 m**. F9 → Enter produced `started=true, paused=false`; W moved **1.363 m**.
- **PASS — title F6 dispatch/failure recovery.** Native F6 now reaches the loader and reports “No compatible save. Start a new game to begin.” Title remains paused. Successful native Continue is **NOT TESTED** because no compatible default save existed; owner save files were never written.
- **PASS — malformed-save rejection before mutation.** Separate `/tmp` valid save restored health **51 → 73**. Empty position, unknown weapon, negative health, excessive magazine ammunition, and inconsistent mission/checkpoint variants all returned false with tested health/ammo/stage/weapon/position/mode unchanged. No script errors.
- **PASS — tested interaction obstruction/selection.** A fixture wall blocked target selection and native E entry. Removing it selected the car and permitted native E entry. A nearer package won selection; hiding it selected the car. The LOS ray excludes self and the target body while checking world/other-vehicle layers (`player.gd:433–440`).

Remaining findings:

1. **P1, reproduced — pause lost through Settings.** Native Esc → F3 → F3 leaves `pause_panel.visible=true`, `settings.visible=false`, but `simulation_paused=false`. `main.gd:188–191` derives pause only from settings/title, discarding the preceding pause-menu state. Preserve/restore that state or centralize modal ownership. PLAYER-05 remains incomplete.
2. **P2, reproduced — disabled-car prompt is actionable-looking but inert.** Target selection returned the disabled sedan and emitted `[E] Take Sedan`; E was rejected. `player.gd:419` filters via `is_disabled()`, which `Car` does not implement, although `car.gd:369` rejects disabled entry. Add shared vehicle eligibility. This partially reopens the R1 eligibility finding; wall rejection itself passes.
3. **Source-only remaining SAVE gaps.** `game_state.gd:222–245` still writes directly to the destination, without temporary-file replacement, and omits settings. Pre-mutation load validation does not establish crash-safe writes or settings persistence. SAVE-01/02 remain incomplete.

Full native route, rendered camera/input feel, aircraft reboard/return, and active cross-mode pursuit were not rerun and remain **NOT TESTED** here.

Reproduction and raw results: [probe](tests/critic-r2/probe.gd), [result](tests/critic-r2/probe.json), [log](tests/critic-r2/probe.stdout.log), [complete exact source hashes/process metadata](tests/critic-r2/probe.meta.json).

| Tested source | SHA256 |
| --- | --- |
| `main.gd` | `f2dbd93229ada878b119b6fba9b3509e143b3f6038ee0f4cecc68eca06bc405e` |
| `game_state.gd` | `d16e8347388607d465b6c90fa812bc1eb57c006d4ac48e3550f3018f00fd8475` |
| `player.gd` | `227994355a89170ed4268f5f621fca2b382cab3934f7b013e97af79c8652a93d` |
| `car.gd` | `a7e798e8f6e079a5f311600bec8b46e30207b29c8db3aea7d722c8311a638bc6` |
| `hud.gd` | `88809b27c2e2a75d50a22cf04f66e5cad1f2ba21c24c94132db4c43907538f9d` |
