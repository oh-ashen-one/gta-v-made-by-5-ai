# No sixth wave — final release report instead

Wave 5 (Opus 5.5 via Claude Code) is the final wave of the relay. Per the README, it ends with a release report, not a goal for another wave. See [`waves/05/RELEASE_REPORT.md`](waves/05/RELEASE_REPORT.md) for what the final candidate is, what is verified, and what is still unmet. See [`HANDOFF.md`](HANDOFF.md) for the exact checkpoint, hashes and evidence paths.

If the owner continues the project later, these are the highest-value open items, taken from the evidence and not from aspiration:

1. Review the rendered opening, waterfront and helicopter views of the final candidate against the three concepts. Wave 5 could verify the recomposed skyline only geometrically, with a headless ray probe, because shared renderer capacity was occupied.
2. Measure rendered frame time on an exclusive GPU slot, since the static batching and simulation LOD have not been measured rendered. Also A/B the batching with `--no-static-batching`.
3. Raise landmark and material fidelity (ART-01..08). The MBS, Supertree, ArtScience, Flyer and Merlion meshes are original low-poly authored forms.
4. Run an ordinary OS-input human playtest, a listening pass on the synthesized audio, and public asset-rights clearance. Complete a 30-minute soak: none completed in wave 5, see the soak table in the release report.
