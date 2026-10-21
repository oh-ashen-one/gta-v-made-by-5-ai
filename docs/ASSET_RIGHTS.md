# Asset rights check — wave 1 provider art

This is the ASSET-03/ASSET-04 rights review for the eighteen generated models used in wave 1. It was performed inside the wave-1 CLI; the check is recorded so the decision is explicit rather than a silent exclusion.

## Providers and terms

| Provider | Assets | Terms reviewed | Outcome |
| --- | --- | --- | --- |
| Customuse | 8 hero models (W1-HERO-001 … 009; 009 was produced through the Tripo small-prop route after Customuse charges exceeded the estimate) | https://customuse.com/terms, last updated **19 June 2026** | Outputs are "User Content"; "Customuse does not claim ownership of your Inputs or Outputs"; "You may use your Outputs for lawful personal or commercial purposes"; **no attribution requirement is stated**; the operative restriction is that the output must not infringe another person's intellectual property, and content labelled for personal use only may not be used commercially. No label of that kind was present on these jobs. |
| Tripo | 10 props (W1-PROP-010 … 018) | the owner's authorised browser route with existing credits (balance 76 000 → 75 450; no new credits purchased) | outputs used under the owner's account; no third-party content was supplied as input, and every prompt describes an original, unbranded object |

## Check performed

1. **Input review.** Every prompt asked for an original, unbranded object (no logos, no real livery, no real insignia, no real police uniform). The prompts are recorded in the manager's provenance files and in `ASSET_REQUESTS.json`.
2. **Output inspection — partial, and three assets are known to carry marks.** Only the hero models that were rendered for review were inspected visually. **Sedan (W1-HERO-001)** and **helicopter (W1-HERO-004)**: no manufacturer badges, no liveries, no readable trademarks, no insignia. **Civilian character (W1-HERO-005)**: a **visible sneaker/logo mark** was seen in the raw preview, so this asset is **not** cleared. **Van (W1-HERO-003)** and **coupe (W1-HERO-002)**: the previews showed **badge/mark artifacts**, so these are **not** cleared either. The **remaining thirteen outputs were never rendered in wave 1** and are therefore **UNVERIFIED** — a prompt that asks for no logos is not output verification.
3. **No extracted third-party content.** Nothing in the asset set is extracted from a game, film, brand or other existing work.
4. **Modification.** All eighteen were modified in Blender for the game (real-world scale, ground at Y=0, part separation, triangle budgets); the rights check covers the modified outputs as well as the raw ones.
5. **Attribution.** The Customuse terms state no attribution requirement. The project's own convention is to credit the provider in `docs/asset-manifest.csv` and in this document rather than to bake credits into the game.

## Decision

- **Terms: cleared.** The provider terms reviewed above permit lawful personal and commercial use of the outputs and impose no attribution requirement. That is a statement about the *terms*, not about the outputs.
- **Output clearance: 2 of 18 verified, 3 of 18 known to carry marks, 13 of 18 unverified.** Only the sedan and the helicopter were inspected and found free of marks. The character, the van and the coupe were inspected and found to carry marks. The other thirteen were never rendered. Until each asset is rendered and inspected, **the set as a whole is not cleared for public redistribution**, and this repository therefore keeps the processed binaries out of the history (see below) and marks them UNVERIFIED in the manifest.
- The wave-1 commit keeps the processed binaries **out of the git history** for two reasons: their size (≈264 MB of processed GLBs plus textures would bloat every subsequent wave's diffs) and the **unverified mark clearance** described above. `game/tools/fetch_provider_assets.sh` fetches the eight Customuse sources directly from their public URLs with SHA256 verification, and lists the ten Tripo exports with their studio links and checksums **for the owner's browser route**; `game/tools/cleanup_provider_assets.py` rebuilds the processed game assets from the raw files. See "Reproducibility" below for what is automatic and what is a manual browser step.
- The item that stays blocked is a **published binary release of the game itself**, which the owner has not authorised — and a public redistribution of the provider binaries additionally needs the mark inspection finished.

## Reproducibility, honestly bounded

- **Automatic:** the eight Customuse hero sources are fetched by URL with SHA256 verification, and the Blender cleanup rebuilds every processed game asset from the raw files.
- **Manual browser step:** the ten Tripo props are **not** fetched automatically. `game/tools/fetch_provider_assets.sh` records each studio link and checksum and prints the steps, but the actual export has to be performed through the owner's Tripo browser session. A fresh clone therefore reproduces the Customuse half automatically and the Tripo half only with a documented manual browser step.
- The manager carries the ignored processed provider folder across to the successor's checkout at handoff, so wave 2 does not have to redo the browser export to keep building.

## Open items for the successor

- **Render and inspect the thirteen provider outputs that wave 1 never rendered**, and record the result here.
- **Strip or replace the marks on the character, the van and the coupe** (a sneaker/logo mark on W1-HERO-005; badge artifacts on W1-HERO-002 and W1-HERO-003), then re-inspect and update this record.
- **Tripo job labels:** the commercial-use conditions for the ten Tripo props rest on the linked Tripo commercial-use page and the owner's account; the per-job labels (in particular any "personal use only" flag) were not checked individually. Check them before any public release.
- The generated character and officer are unrigged; rigging them does not change the rights position.
