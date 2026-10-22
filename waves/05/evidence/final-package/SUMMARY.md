### Final private candidate (native macOS, Godot 4.7.1 export)

- Identity: `head=c42425afd5a2fe568ff822dc3d7391fac62be747 dirty_game_files=0 start=2026-10-22T02:17:07Z`
- Signing: local ad-hoc signature only (strict verify exit 0); no Developer ID, notarization or public redistribution clearance.
- SHA-256:
  - `OrchardReach.zip` 5d600330c7b428167a1f4d6168cf2196722205be2fb0fcd3f0ae1c5b3b51548f
  - `OrchardReach-wave-05-final-signed.zip` 3ae8f8c346720d651fb84f6680f9210eb5c99de4f1726c452fa9de104e493b22
  - `app/Orchard Reach.app/Contents/MacOS/Orchard Reach` 233633697eb0f31f0d26344eba344fb53c5700b2c308c7e84d0877ddd82271e2
  - `signed/Orchard Reach.app/Contents/MacOS/Orchard Reach` 80bb3701b04ddeca53c88e91afa25b7708d246885bd64e18d9e2ed498fe54d68
  - `app/Orchard Reach.app/Contents/Resources/Orchard Reach.pck` 54373c6d736c4328138da91092ceba89de075e0e75499af0ca313f5f23b97c05
  - `signed/Orchard Reach.app/Contents/Resources/Orchard Reach.pck` 54373c6d736c4328138da91092ceba89de075e0e75499af0ca313f5f23b97c05
- Packaged regressions (signed binary, headless): **97/97**, supervisor {'pid': 38946, 'exit_code': 0, 'timeout': False, 'elapsed_sec': 22.35, 'fatal_error_count': 0, 'rss_samples': 5}
- Packaged two-process save/relaunch (headless): PASS player walked with ordinary input before saving 4.78335857391357; PASS save written through Game.save_game ; PASS fresh process found the expected record ; PASS continue restored player position (-170.3357, 0.13584, -26.72658) vs (-170.3357, 0.13584, -26.72658); PASS continue restored health 73.0; PASS continue restored carried weapon smg; PASS game is running after continue 
- Packaged scripted route (headless): [capture] terminal success=true deaths=0 seconds=147.5; supervisor {'pid': 39476, 'exit_code': 0, 'timeout': False, 'elapsed_sec': 154.0, 'fatal_error_count': 0, 'rss_samples': 31}
