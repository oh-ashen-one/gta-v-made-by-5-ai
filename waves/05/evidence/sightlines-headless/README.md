# Headless sightline probes — NOT renders

Every image in this folder is a **geometric ray-probe semantic map**, produced headless by `game/src/systems/sightline_probe.gd` (`--sightline-probe`). How it works:

- It casts a 256×144 grid of camera rays against temporary trimesh copies of the scene meshes.
- Each cell is coloured by the category of the object it hits.
- It models no lighting, materials, transparency, fog, HUD or leaf alpha. Leaf cards and glass count as opaque.
- It shows framing and occlusion only. It is not evidence of how the game looks.

Colour key: red = Marina Bay Sands, magenta = Supertree Grove, cyan = Singapore Flyer, pink-white = ArtScience Museum, yellow = Merlion, orange = shophouses, light blue = HDB, brown = hawker pavilion, green = trees, dark blue = vehicles, pink = people, grey = background skyline, teal = water, beige = other geometry, sky blue = no hit.

Which run each file comes from:

- **`release-code-2e38d8f/`**: probe of the release code. Its images are stamped "NOT A RENDER".
- **Unstamped files at the top level**: probes of earlier wave-5 builds, kept for history.
  - `sightlines_before_batching.json` / `sightlines_after_batching.json` (in `../batching/`) compare the earlier 9,921 → 1,193 grouping, not the final grouping.
  - `opening_probe_vs_concept01.png` puts the earlier `d771114` opening probe beside CONCEPT-01, which is AI concept art, labelled as such.

"Clear of the HUD objective card" is a computed claim, not a rendered observation: the release-code opening probe puts the Marina Bay Sands bounding box at 22–48 % of frame height, and the objective card in `hud.gd` ends at about 14 % (y ≈ 101 px of 720).
