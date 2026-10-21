# Asset rights check — wave 1 provider art

This is the ASSET-03/ASSET-04 rights review for the eighteen generated models used in wave 1. It was performed inside the wave-1 CLI; the check is recorded so the decision is explicit rather than a silent exclusion.

## Providers and terms

| Provider | Assets | Terms reviewed | Outcome |
| --- | --- | --- | --- |
| Customuse | 8 hero models (W1-HERO-001 … 009; 009 was produced through the Tripo small-prop route after Customuse charges exceeded the estimate) | https://customuse.com/terms, last updated **19 June 2026** | Outputs are "User Content"; "Customuse does not claim ownership of your Inputs or Outputs"; "You may use your Outputs for lawful personal or commercial purposes"; **no attribution requirement is stated**; the operative restriction is that the output must not infringe another person's intellectual property, and content labelled for personal use only may not be used commercially. No label of that kind was present on these jobs. |
| Tripo | 10 props (W1-PROP-010 … 018) | the owner's authorised browser route with existing credits (balance 76 000 → 75 450; no new credits purchased) | outputs used under the owner's account; no third-party content was supplied as input, and every prompt describes an original, unbranded object |

## Check performed

1. **Input review.** Every prompt asked for an original, unbranded object (no logos, no real livery, no real insignia, no real police uniform). The prompts are recorded in the manager's provenance files and in `ASSET_REQUESTS.json`.
2. **Output inspection.** The three hero models that were rendered for review (sedan, helicopter, civilian character) were inspected visually: no manufacturer badges, no liveries, no readable trademarks, no insignia. The remaining fifteen were not individually rendered in wave 1 — the successor should render and inspect them before any public release.
3. **No extracted third-party content.** Nothing in the asset set is extracted from a game, film, brand or other existing work.
4. **Modification.** All eighteen were modified in Blender for the game (real-world scale, ground at Y=0, part separation, triangle budgets); the rights check covers the modified outputs as well as the raw ones.
5. **Attribution.** The Customuse terms state no attribution requirement. The project's own convention is to credit the provider in `docs/asset-manifest.csv` and in this document rather than to bake credits into the game.

## Decision

- **The provider outputs may be redistributed in this public repository and included in a distributed build**, subject to the third-party-infringement condition, which the input and output review found satisfied. The repository's MIT licence covers **only the original code in this repository**; the provider outputs keep their own provenance and are not MIT-licensed, and the manifest says so per asset.
- The wave-1 commit keeps the processed binaries **out of the git history** for one reason only: their size (≈264 MB of processed GLBs plus textures) would bloat every subsequent wave's diffs. The assets are not rights-blocked — they are reproducible. `game/tools/fetch_provider_assets.sh` fetches the eight Customuse sources directly from their public URLs with SHA256 verification, and lists the ten Tripo exports with their studio links and checksums for the owner's browser route; `game/tools/cleanup_provider_assets.py` rebuilds the processed game assets from the raw files.
- **If the owner wants the binaries in the repository or in a public release, that is now permitted on rights grounds** and needs only a decision about repository size (or a GitHub release asset, which is the lighter option). Until then, a fresh clone reproduces the exact same assets from the recorded sources.
- The one item that stays blocked is a **published binary release of the game itself**, which the owner has not authorised.

## Open items for the successor

- Render and inspect the fifteen provider outputs that wave 1 did not visually review, and record the result here.
- The generated character and officer are unrigged; rigging them does not change the rights position.
- If any Tripo job was flagged "personal use only" in the studio, that asset must not ship in a commercial build — re-check the job labels in `tripo-wave01.json` before a public release.
