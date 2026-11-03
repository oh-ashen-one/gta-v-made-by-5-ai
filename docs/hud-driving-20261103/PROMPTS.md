# Production image-generation brief

Tool: built-in image_gen. Date: 2026-11-03. All three calls used `transparent_background=true` and the original `01-jade.png` concept as a visual reference. Outputs are implementation atlases with no text; runtime text/data stay native.

1. Weapons: a 2:1 atlas with a detailed compact black pistol on the left and compact black SMG on the right. Right-facing side profiles, actual shaded inventory artwork, matte charcoal surfaces, warm silver edge highlights and restrained jade reflected light. Transparent background and margins; no words, numbers, frames or flat vector symbols.
2. Wheel: two equal square cells in a 2:1 atlas, each with an identical circular two-slot smoked-glass/gunmetal wheel. Left image selects the upper semicircle in jade; right image selects the lower semicircle. Thin divider and center ring, fine bevels and restrained glow. No baked-in weapons, labels or numbers; transparent outside the circle.
3. Frames: a 2×2 atlas of mission, ammunition, notification and minimap plates. Smoked charcoal glass, fine dark bevels, jade accents for mission/ammo and amber for notifications; hollow square minimap frame. Transparent separation and no text/map/characters. The requested wide plate proportions differ from the square minimap bezel; actual alpha bounds are recorded for runtime atlas use.

`art-manifest.json` records the output identities. All original generated PNG pixels are retained; `regions.json` contains measured atlas coordinates rather than edited derivative bitmaps.
