### Final private candidate (native macOS, Godot 4.7.1 export)

- Identity: `head=98b41b2328c96d9b7338826de0c498452f8a95ab dirty_game_files=0 start=2026-10-22T03:03:05Z`
- Signing: local ad-hoc signature only (strict verify exit 0); no Developer ID, notarization or public redistribution clearance.
- SHA-256:
  - `OrchardReach.zip` 131aa64b2b3815bd3714129b7a6455e14def70a34d4ba862810ef668b716cd88
  - `OrchardReach-wave-05-final-signed.zip` 129ecc4f15a6526dab241b231aad90bf18c977626acc248b4761cf1748fbb550
  - `app/Orchard Reach.app/Contents/MacOS/Orchard Reach` 233633697eb0f31f0d26344eba344fb53c5700b2c308c7e84d0877ddd82271e2
  - `signed/Orchard Reach.app/Contents/MacOS/Orchard Reach` 8d071ddf0a9c358c0e4bc6e2a3b8ad16255c63eb8ea2378312a8196270f33000
  - `app/Orchard Reach.app/Contents/Resources/Orchard Reach.pck` 5cb6c167ae883d9b4c242b184dfb49d9f7ad2608f054a840320103d3e095bd0a
  - `signed/Orchard Reach.app/Contents/Resources/Orchard Reach.pck` 5cb6c167ae883d9b4c242b184dfb49d9f7ad2608f054a840320103d3e095bd0a
- Packaged regressions (signed binary, headless): **97/97**, supervisor {'pid': 81074, 'exit_code': 0, 'timeout': False, 'elapsed_sec': 21.24, 'fatal_error_count': 0, 'rss_samples': 5}
- Packaged two-process save/relaunch (headless): PASS player walked with ordinary input before saving 4.78335857391357; PASS save written through Game.save_game ; PASS fresh process found the expected record ; PASS continue restored player position (-170.3357, 0.13584, -26.72658) vs (-170.3357, 0.13584, -26.72658); PASS continue restored health 73.0; PASS continue restored carried weapon smg; PASS game is running after continue 
- Packaged scripted route (headless): [capture] terminal success=true deaths=0 seconds=147.6; supervisor {'pid': 81427, 'exit_code': 0, 'timeout': False, 'elapsed_sec': 154.2, 'fatal_error_count': 0, 'rss_samples': 31}
