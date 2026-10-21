# Evidence index — wave 1

Everything in this document was produced by the wave-1 builder on the reference machine (Apple M3 Ultra, 256 GB, macOS 27.0.1) with the build on the wave-1 branch. Where something was **not** tested, it says so.

## 1. Automated checks

```
godot --headless --path game -- --test
```

34 checks, all PASS at the handoff commit: 20 structural (world built, mesh count, junction graph, pedestrian lanes, player + camera, traffic and pedestrian population, mission running, helicopter present, HUD present, save/load round trip, mission package interactable, vehicle counts, NPC counts) and 14 behavioural regression checks added after the independent review:

| Behavioural check | What it proves |
| --- | --- |
| vehicle entry takes control | the mode changes to the car and the player is bound to it |
| player is bound to the vehicle | one control owner, not two |
| death in a vehicle releases control | the wave-1 softlock is fixed |
| death in a vehicle returns to foot | the mode returns to foot |
| gameplay camera returns to the player | exactly one gameplay camera |
| the player can still walk after a vehicle death | no movement freeze |
| a scripted interact press takes the vehicle | scripted and human input share one path |
| no civilian traffic car is wrecked by street contact | the traffic self-destruction is fixed |
| the wanted level falls as heat decays | pursuit can actually be escaped |
| the world is frozen while paused | pause pauses the simulation |
| the mission package can be picked up | the pickup interactable works through the real input path |
| picking up the package advances the mission (stage 2) | the mission stage machine advances on a real pickup, not a scripted flag |
| health regenerates once the player is out of fire | a firefight is survivable and a chase can be broken (COMBAT-04) |
| pressing left steers the vehicle left | the car and the helicopter were steering the wrong way (the yaw sign was inverted), so a scripted drive or flight could not reach a target at all |

## 2. Capture packet — `game/captures/`

| File | What it shows |
| --- | --- |
| `01_safe_room.png` | the mission start inside the safe room |
| `02_hawker_market.png` | the hawker centre precinct |
| `03_combat.png` | the armed guards at the market |
| `04_package_taken.png` | the package objective, picked up |
| `05_car_entered.png` | the stolen vehicle, control taken |
| `06_driving.png` | driving at district speed with the generated coupe and the housing blocks behind it |
| `07_exited_car.png` | back on foot at the aviation compound |
| `08_helicopter_boarding.png` | the helicopter on the pad |
| `09_aerial_view.png` | the same district from the air (QA-010) |
| `10_landed.png` | the landing at the waterfront pad |
| `11_delivery.png` | the on-foot delivery at the end of the mission |
| `capture_log.json` | the state log of the run: health, wanted level, mission stage, mode, live counts, and every step the script took |
| `photo_*.png` | fixed-view frames of the district: heritage street, wide street, hawker interior, void-deck housing, waterfront, two aerials, the airfield |
| `photo_log.json` | the fixed-view log, labelled as fixture-assisted (an authored camera, not proof that a player can reach the view) |

**What the packet is and is not.** The playthrough drives the real systems through the real input actions: it is an automated playtest, not an uncut human run, so QA-018 stays Partial. The fixed-view frames are shot from an authored camera and are labelled as such.

**Outcome of the final run** (`capture_log.json`, 2026-10-21): the mission reached **stage 8 (DONE)** — the package was picked up from the hawker hall after the market firefight, a car was stolen, the helicopter was boarded, flown to the waterfront pad, landed (`landed=true on_floor=true`), the pilot stepped out on foot and the delivery completed. Final state: health 100, wanted level 0, 34 pedestrians and 14 traffic vehicles alive. Two legs are honest caveats: the player was **killed by the police response during the car leg** and respawned at the checkpoint, so the drive to the aviation compound was completed on foot rather than by car; and the scripted player does not use the "marked car" objective.

## 3. Packaged build

```
godot --headless --path game --export-release "macOS" build/mac/OrchardReach.zip
```

A universal macOS `.app`/`.zip` is produced (about 132 MB after the provider textures were reduced to 1K — it was 644 MB before that step, which is a useful number for the successor's budget). The build output is git-ignored; rebuild it locally. Launching the packaged `.app` itself was not exercised in wave 1 — that is a NOT TESTED item for the successor.

## 4. Provenance and rights

- `docs/asset-manifest.csv` — every asset, its provider, the terms, the SHA256 of the raw source, the processed file and what it is used for.
- `docs/ASSET_RIGHTS.md` — the rights check: the Customuse terms (19 June 2026) permit commercial and public use of outputs with no attribution requirement, and the input and output review found no third-party content. Redistribution is therefore permitted; the binaries are kept out of the git history for size, not for rights, and `game/tools/fetch_provider_assets.sh` reproduces all eighteen sources.
- `docs/visual-references.json` and `docs/concepts/` — the owner's reference board. The concepts are the primary art direction; the external Rockstar and Singapore photography is secondary location evidence and nothing from it is copied into the repository or the build.

## 5. Not tested in wave 1 (explicit)

- 30-minute soak, three consecutive mission completions, frame-time percentiles (PERF-02/03/04, QA-020) — no measurement harness existed yet.
- An uncut human golden path, and a packaged `.app` launch (QA-001, TECH-02).
- Audio quality, mix and spatialisation (AUDIO-01/02) — the bank was written and wired, but nobody heard it in wave 1.
- Any visual gate judged by a reviewer from a different model: the wave-1 critics were subagents of the same MiniMax model (this CLI exposes no Opus/Fable), so VERIFY-02 is only partially satisfied and QA-014 is NOT TESTED by an independent party.
- The fifteen provider outputs that were not individually rendered for mark inspection (see `docs/ASSET_RIGHTS.md`).
