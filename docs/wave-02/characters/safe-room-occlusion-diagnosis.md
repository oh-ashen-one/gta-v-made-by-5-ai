# Safe-room leg occlusion diagnosis

Inspected at 2026-10-21 12:48–12:54 UTC using the actual route frames, source transforms and GLB triangle intersections. No renderer was launched and no player/world/character asset was edited for this diagnosis.

The major occluder in `route-render-r1/01_safe_room.png` is the decorative ground plinth of the third provider HDB slab. It is not the character rig or the authored thin rug.

The slab is instantiated at `(-270, 0.16, -40)`, with yaw 90 degrees and scale 46/42. Applying the source GLB's internal quaternion and transform gives a low mesh span of approximately X `[-294.438, -245.626]`, Z `[-62.649, -17.351]`. A vertical triangle intersection at the player's starting X/Z `(-292, -46)` finds the plinth top at Y **0.64488**; at `(-294, -46)` it is **0.63985**. There is no intersection at `(-296, -46)`.

The recorded player origin is Y **0.335325**. Thus the imported plinth visually hides about 0.31 m of lower legs. This matches recorded frame 000005. At frame 000015, X=-296.1027, the player has left the plinth and both feet are visible. Hawker and outdoor route captures also show the complete legs/feet.

The current 12-clip player GLB's idle root translation is exactly zero. Walk/run root compensation is animated, but the evaluated foot minimum remains zero; it is not a global downward displacement. Do not lift the whole rig to conceal the scene overlap.

There is a smaller, separate capsule/art alignment issue: Player's capsule height is 1.75 and center Y=0.9, so its bottom is +0.025 above the actor origin. The visual feet are at origin Y=0. The safe-room floor is Y=0.36; the rug and weave are respectively +0.021/+0.027 above the furnishing base. These produce 2.5 cm floor overlap and up to 5.2 cm rug overlap, much smaller than the imported plinth intrusion. Root owns the world relocation and any explicit visual/capsule alignment adjustment.
