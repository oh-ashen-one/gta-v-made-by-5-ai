# Transition table — foot → car → flight → death → restart → load

END_GOAL SYSTEM-01 requires an explicit transition table defining which fields are preserved and which are reset. This is the wave-1 version; later waves must extend it rather than replace it.

| Transition | Preserved | Reset / recomputed | Owner |
| --- | --- | --- | --- |
| **foot → car** | health, ammo pools, wanted level + heat, mission stage, carried weapon, settings | player node hidden and re-parented logically to the car (`player.current_vehicle`), camera switched to the vehicle camera, interaction prompt re-targeted | `Car.interact` |
| **car → foot** | health, ammo, wanted, mission stage | control returns to the player, a clear exit position is chosen (both sides tested; refused if both blocked), vehicle camera released, `player.current_vehicle = null` | `Car.exit_vehicle` |
| **foot → helicopter** | health, ammo, wanted, mission stage | rotor spin, rotor audio, flight camera, `Game.mode = MODE_HELI` | `Helicopter.interact` |
| **helicopter → foot** | health, ammo, wanted, mission stage | only allowed when grounded (`is_on_floor()` and `is_landed()`), rotor audio stopped, flight camera released | `Helicopter.exit_vehicle` |
| **death (any mode)** | mission stage, checkpoint index, ammo | health restored to 100, wanted level and heat cleared, the controlled vehicle is released (`force_exit` clears `player.current_vehicle`), player returned to the last safe position and rotation, gameplay camera restored, `busy` cleared | `Player.respawn_at` |
| **mission restart (F10)** | settings, health | stage reset to the first objective, package restored and visible, hostiles respawned, objective text re-published | `Mission.restart` |
| **save (F5)** | — | version, health, wanted level and heat, mission stage, checkpoint index, seed, elapsed time, player position and rotation, ammo pools, carried weapon, last safe position and rotation written to `user://orchard_reach_save.json` | `Game.save_game` |
| **load (F6)** | settings | the stored values are **applied to the world** (player moved to the stored position, mission stage restored, checkpoint position re-marked) and the health/ammo/wanted signals are re-emitted; an unreadable or incompatible file reports a message and leaves the session running | `Game.load_game` |
| **pause (Esc)** | everything | simulation frozen: player, NPCs, traffic and the mission stop advancing; the mouse is released for the menu | `Game.simulation_paused` |
| **respawn from checkpoint (F7)** | same as death | same as death | `Player.respawn_at` |

## Invariants that must hold at every moment

1. Exactly one control owner: `player.current_vehicle == null` **iff** `Game.mode == MODE_FOOT`; otherwise the vehicle's `driver_is_player` / `pilot_is_player` is true and points at the same player.
2. Exactly one gameplay camera is current: the player's camera on foot, the vehicle's camera while driving or flying.
3. `player.busy` is true only during a transition and is cleared on every path, including the failure paths.
4. The wanted level, heat, mission stage and health live in `Game` only; no other system keeps a second copy.
5. The player's authoritative world position is `player.controlled_actor().global_position` — never the raw node position while a vehicle is held.

These invariants are exercised by the automated checks in `game/src/systems/self_test.gd` ("vehicle entry takes control", "death in a vehicle releases control", "gameplay camera returns to the player", "a scripted interact press takes the vehicle").
