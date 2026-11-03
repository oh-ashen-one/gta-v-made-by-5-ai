# Native human replacement — 2026-11-03

The owner rejected the earlier Quaternius-to-custom-rig result in `3e9356f`: the runner looked non-human and melted. Earlier sampled captures and numerical checks did not establish acceptable motion. That retarget is no longer installed automatically.

## Replacement

Downloaded Adobe Mixamo's **Josh** character with **Unarmed Run Forward**, plus the matching **Locomotion Pack**, **Pistol/Handgun Locomotion Pack**, **Basic Shooter Pack** and **Sitting Idle**. Josh is the selected dark-haired adult male; the catalog did not provide an ethnicity label. No ethnicity claim or new character generation is made.

The player uses the original 65-bone Mixamo skeleton, authored skin weights, source mesh and texture images. The old `CharacterLook` mesh reconstruction, custom idle/head changes, body-motion layer, foot lock, procedural hands, aim IK and skeleton recoil layer are bypassed for this native player. Camera recoil remains. NPC paths are not changed.

The Blender conversion preserves segment lengths and checks them before merging motion. Skinless FBX exports can carry a different reference pose despite the same bones/proportions; Blender's world-space COPY_TRANSFORMS visual bake resolves that onto the original skinned character. This is not the rejected manual quaternion transfer onto the 24-bone custom rig. Bone names are aliased only for existing gameplay sockets. Horizontal travel is removed for in-place control while vertical hip motion is retained. Legacy FBX metal/specular conversion is corrected to nonmetal, rough cloth/hair; source albedo/normal images are retained. No new motion is hand-authored.

The native model is converted to Godot GLB at `game/assets/providers/mixamo_josh/player_native.glb`. Attachment scale is compensated for the retained FBX centimetre armature transform; the model/skeleton animation is not arbitrarily rescaled. Missing licensed media requires restoration; the rejected retarget is not an automatic fallback.

## Rights and restoration

Sources: https://www.mixamo.com/ and https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html . Adobe permits characters and animation in commercial games; that is not a license to redistribute raw assets. FBXs, editable Blender file and the derived GLB remain in the ignored provider directory, outside public Git.

On the owner's authorized Mixamo account, choose **Josh**. Download **Unarmed Run Forward** with Skin, In Place checked, FBX Binary, 30 fps, no key reduction. Save it as `source/run.fbx`. Download the named packs without character and extract their FBXs into `source/`, `source/pistol/` and `source/shooter/`. Download Sitting Idle (chair, hands on thighs) Without Skin into `source/Sitting Idle.fbx`. Keep `.gdignore` in `source/` to prevent the engine importing authoring FBXs/Blender files.

Run `game/tools/import_mixamo_human.py` in Blender 5.2 background mode with `--source-dir` and `--output` as documented in its header, then Godot's headless editor import. The conversion writes an editable `.blend`, a bounds/source-hash report and the native GLB. Use the asset manifest in this directory for the verified identity.

## Verification boundary

No new playable game instance was launched during this repair, as the owner requested. CPU-only Blender conversion, Godot headless import, and the isolated `tools/native_human_check.tscn` asset scene are distinct from opening `main.tscn`. The actual exported GLB was played and inspected from front, side and rear in the local asset viewer. Screenshots show native run phases, not an imagined replacement or a generated concept.

The asset checker exercises actual CharacterVisual selection, 65-bone skin, absence of the old deformation layers, required clips, finite poses, run/sprint selection and weapon attachment scale. This is not a new full-game regression result, gameplay-feel acceptance or proof of every weapon grip. The previous full-city/character-bake regression gaps remain historical; the prior UI/radio test report does not certify this replacement's complete gameplay integration.

Start the optional asset-only viewer with `npm ci --prefix tools/native-human-viewer` and `python3 tools/native-human-viewer/serve.py`. It binds to loopback only. The game remains closed until the owner asks to play.

Final asset-only result: 102/102 checks passed; 13 native clips loaded. The full game remains unopened under the latest owner instruction.

Native clips use their own start timing and ordinary crossfades; the old custom gait phase offsets are not applied. The asset check also verifies that firing does not reattach the old skeleton recoil modifier.


### Afternoon jump correction

The owner accepted the runner but rejected the jump. Downloaded **Unarmed Jump / Jumping And Landing In Place** from Adobe Mixamo on the same Josh rig, FBX Binary, Without Skin, 30 fps, no keyframe reduction. The previous locomotion-pack jump is retained only as historical raw source. The importer now selects `Unarmed Jump.fbx`. Runtime slices the authored 71-frame clip into anticipation (frames 20–26), airborne motion (26–46), and landing absorption (46–64), so vertical-velocity seeking only traverses the flight phase, never the preparation and recovery. Standing takeoff waits 0.20 seconds for the sourced anticipation; running jumps retain immediate input response. Original native skin weights and accepted run clips remain in use. Restricted FBX/GLB/Blender media remain ignored; current hashes and acquisition details are in the asset manifest.
