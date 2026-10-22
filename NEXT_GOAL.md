# No sixth wave — final release report instead

Wave 5 (Opus 5.5 via Claude Code) is the final wave of the relay. Per the README, it ends with a release report, not a goal for another wave. See [`waves/05/RELEASE_REPORT.md`](waves/05/RELEASE_REPORT.md) for what the final candidate is, what is verified, and what is still unmet. See [`HANDOFF.md`](HANDOFF.md) for the exact checkpoint, hashes and evidence paths.

If the owner continues the project later, these are the highest-value open items, taken from the evidence and not from aspiration:

1. Fill the camera-facing world. The fresh-context critic of wave 5's first real renders (`waves/05/evidence/critic_review_5_rendered.md`) scored the concepts on foot 4/10, driving 2/10, helicopter 3/10. Its testable gap: the `06_driving` and `photo_06_aerial_district` cameras should show at least 8 vehicles, at least 10 pedestrians, and canopy over the road.
2. Fix the rendered defects it found that are still open:
   - the white glow beside the helicopter (probably a sun glint on the bay water);
   - water that reads as paving in low shots;
   - Supertrees overlapping MBS;
   - the dark void deck;
   - the Flyer lost from `photo_06_aerial_district`;
   - the 1.06 s render-side hitch on entering the market. One lead, untested: `game/export_presets.cfg` sets no shader-baker option. Since Godot 4.5, exports can precompile shaders, which could remove first-use pipeline compilation in the packaged build.
3. Re-shoot the HUD frames the critic named (`09_aerial_view`, `11_delivery`, and the waterfront and grove gameplay views) to confirm the `98b41b2` minimap and ammo fixes, unless the release report already links them.
4. Measure rendered frame time on an exclusive GPU slot. Wave 5's rendered route (p95 11.65 ms) shared the GPU with a foreign Blender render. Also A/B the batching with `--no-static-batching`.
5. Raise landmark and material fidelity (ART-01..08); the landmarks are original low-poly forms.
6. Run an ordinary OS-input human playtest, a listening pass, and public asset-rights clearance. Check the soak table in the release report for whether a 30-minute soak completed.
