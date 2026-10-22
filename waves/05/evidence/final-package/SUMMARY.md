### Final private candidate (native macOS, Godot 4.7.1 export)

- Identity: `head=d2a6cad1c948c5e32e0ee45924e7d5e325e73e5c dirty_game_files=0 start=2026-10-22T02:39:53Z`
- Signing: local ad-hoc signature only (strict verify exit 0); no Developer ID, notarization or public redistribution clearance.
- SHA-256:
  - `OrchardReach.zip` 04f2182845dba94326eabf43a8d43f55144db6861fe4e36f3d4e459fd695f6b6
  - `OrchardReach-wave-05-final-signed.zip` 36c5132f3948ad465b4860ae9d9c166dd7eedfee99ade6120e578e988eb2198d
  - `app/Orchard Reach.app/Contents/MacOS/Orchard Reach` 233633697eb0f31f0d26344eba344fb53c5700b2c308c7e84d0877ddd82271e2
  - `signed/Orchard Reach.app/Contents/MacOS/Orchard Reach` 8cbba859c0de59f8f7169822aa05073676a6b92e3fb01e5dd463352873116548
  - `app/Orchard Reach.app/Contents/Resources/Orchard Reach.pck` 233a76c68f3ca83207e9575790bb0c51ff674eeba6ed596fb07b9ee7036ffc64
  - `signed/Orchard Reach.app/Contents/Resources/Orchard Reach.pck` 233a76c68f3ca83207e9575790bb0c51ff674eeba6ed596fb07b9ee7036ffc64
- Packaged regressions (signed binary, headless): **97/97**, supervisor {'pid': 59489, 'exit_code': 0, 'timeout': False, 'elapsed_sec': 22.17, 'fatal_error_count': 0, 'rss_samples': 5}
- Packaged two-process save/relaunch (headless): PASS player walked with ordinary input before saving 4.78335857391357; PASS save written through Game.save_game ; PASS fresh process found the expected record ; PASS continue restored player position (-170.3357, 0.13584, -26.72658) vs (-170.3357, 0.13584, -26.72658); PASS continue restored health 73.0; PASS continue restored carried weapon smg; PASS game is running after continue 
- Packaged scripted route (headless): [capture] terminal success=true deaths=0 seconds=147.6; supervisor {'pid': 60027, 'exit_code': 0, 'timeout': False, 'elapsed_sec': 153.96, 'fatal_error_count': 0, 'rss_samples': 31}
