### Final private candidate (native macOS, Godot 4.7.1 export)

- Identity: `head=584fb590e34466d6103c22196381a686d1bf44d2 dirty_game_files=0 start=2026-10-22T01:51:08Z`
- Signing: local ad-hoc signature only (strict verify exit 0); no Developer ID, notarization or public redistribution clearance.
- SHA-256:
  - `OrchardReach.zip` 5025c0b34f3f895e08ddad77553d79ad12cab235ffd585e21a870326e355a786
  - `OrchardReach-wave-05-final-signed.zip` a493083299b1f592c0f7e113be94fe9d49399a3672d81eb61dbd6d654f2a2079
  - `app/Orchard Reach.app/Contents/MacOS/Orchard Reach` 233633697eb0f31f0d26344eba344fb53c5700b2c308c7e84d0877ddd82271e2
  - `signed/Orchard Reach.app/Contents/MacOS/Orchard Reach` 8bcab7662ccc07941d9c89be7b7a6bf9eaa3469f38e80ed3c3f0b0b97c2dde03
  - `app/Orchard Reach.app/Contents/Resources/Orchard Reach.pck` ab713a8d8a7a0687022648a7eb78d16e5d2d5982efa32d9a328db4853d8b4ca6
  - `signed/Orchard Reach.app/Contents/Resources/Orchard Reach.pck` ab713a8d8a7a0687022648a7eb78d16e5d2d5982efa32d9a328db4853d8b4ca6
- Packaged regressions (signed binary, headless): **97/97**, supervisor {'pid': 15684, 'exit_code': 0, 'timeout': False, 'elapsed_sec': 22.17, 'fatal_error_count': 0, 'rss_samples': 5}
- Packaged two-process save/relaunch (headless): PASS player walked with ordinary input before saving 4.78335857391357; PASS save written through Game.save_game ; PASS fresh process found the expected record ; PASS continue restored player position (-170.3357, 0.13584, -26.72658) vs (-170.3357, 0.13584, -26.72658); PASS continue restored health 73.0; PASS continue restored carried weapon smg; PASS game is running after continue 
- Packaged scripted route (headless): [capture] terminal success=true deaths=0 seconds=147.6; supervisor {'pid': 16408, 'exit_code': 0, 'timeout': False, 'elapsed_sec': 154.34, 'fatal_error_count': 0, 'rss_samples': 31}
