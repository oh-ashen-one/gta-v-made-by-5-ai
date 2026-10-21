#!/usr/bin/env bash
# Re-fetch the wave-1 provider assets for a fresh clone and rebuild the game's
# asset set from them.
#
# Rights: the Customuse terms (last updated 19 June 2026) state that Customuse
# does not claim ownership of user Outputs and that Outputs may be used for
# lawful personal or commercial purposes, with no attribution requirement; the
# only real restriction is that the output must not infringe third-party
# rights. The Tripo exports were produced through the owner's authorised browser
# route with existing credits. See docs/ASSET_RIGHTS.md for the full check and
# docs/asset-manifest.csv for per-asset provenance.
#
# Usage:
#   bash game/tools/fetch_provider_assets.sh [target_dir]
#
# After this, rebuild the processed assets:
#   blender --background --python game/tools/cleanup_provider_assets.py
# and import them into the engine once:
#   godot --headless --editor --path game --quit

set -euo pipefail

TARGET="${1:-game/assets/providers/raw}"
mkdir -p "$TARGET"

verify() {
  local file="$1" expected="$2"
  [ -z "$expected" ] && return 0
  local got
  got="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [ "$got" != "$expected" ]; then
    echo "SHA256 mismatch for $file: expected $expected got $got" >&2
    return 1
  fi
}

echo "== Customuse hero sources (public direct download) =="
if [ ! -f "$TARGET/W1-HERO-001.glb" ]; then
  echo "fetching W1-HERO-001 ..."
  curl -fsSL "https://public.customuse.com/custom-models/3fcfdbb8-9b4c-46c3-8138-4ee27352cb88/model-1696b9a2fd403987948984a78643b37127b9036f2d8e8fe3a3a794519773f384.glb" -o "$TARGET/W1-HERO-001.glb"
fi
verify "$TARGET/W1-HERO-001.glb" "1696b9a2fd403987948984a78643b37127b9036f2d8e8fe3a3a794519773f384" && echo "ok       W1-HERO-001"
if [ ! -f "$TARGET/W1-HERO-004.glb" ]; then
  echo "fetching W1-HERO-004 ..."
  curl -fsSL "https://public.customuse.com/custom-models/d2fbd1a2-7a30-4540-a207-716d9e915590/model-a7a9d56a2a8feb41b94098830aefb830820a48c4914c1ed1d55febd6902eff58.glb" -o "$TARGET/W1-HERO-004.glb"
fi
verify "$TARGET/W1-HERO-004.glb" "a7a9d56a2a8feb41b94098830aefb830820a48c4914c1ed1d55febd6902eff58" && echo "ok       W1-HERO-004"
if [ ! -f "$TARGET/W1-HERO-005.glb" ]; then
  echo "fetching W1-HERO-005 ..."
  curl -fsSL "https://public.customuse.com/custom-models/2f841639-b0ce-43f5-8042-994bd9d60fb7/model-00fd4131ba072a753cfb365b98a54168ca5779dff7d9204d2cc035a61405efce.glb" -o "$TARGET/W1-HERO-005.glb"
fi
verify "$TARGET/W1-HERO-005.glb" "00fd4131ba072a753cfb365b98a54168ca5779dff7d9204d2cc035a61405efce" && echo "ok       W1-HERO-005"
if [ ! -f "$TARGET/W1-HERO-007.glb" ]; then
  echo "fetching W1-HERO-007 ..."
  curl -fsSL "https://public.customuse.com/custom-models/ed60d5c7-0445-4731-add2-591e047f66db/model-73411d75d932bae105b5f259b5778d4ad300a3cfbd05ec8d470b22c12fe1cf5b.glb" -o "$TARGET/W1-HERO-007.glb"
fi
verify "$TARGET/W1-HERO-007.glb" "73411d75d932bae105b5f259b5778d4ad300a3cfbd05ec8d470b22c12fe1cf5b" && echo "ok       W1-HERO-007"
if [ ! -f "$TARGET/W1-HERO-002.glb" ]; then
  echo "fetching W1-HERO-002 ..."
  curl -fsSL "https://public.customuse.com/custom-models/773e5387-5eb1-4672-b537-36f38440996f/model-4beb149bc2e0a3e201dadc3eef2bb40dbab77dacf3848a48136dff3667901880.glb" -o "$TARGET/W1-HERO-002.glb"
fi
verify "$TARGET/W1-HERO-002.glb" "4beb149bc2e0a3e201dadc3eef2bb40dbab77dacf3848a48136dff3667901880" && echo "ok       W1-HERO-002"
if [ ! -f "$TARGET/W1-HERO-003.glb" ]; then
  echo "fetching W1-HERO-003 ..."
  curl -fsSL "https://public.customuse.com/custom-models/db6a1ce4-d164-4117-af3f-0527496204f8/model-4ebdf5db789518796d6f3d2cfd2bf8ba33913256969f0cd55eca05add18be766.glb" -o "$TARGET/W1-HERO-003.glb"
fi
verify "$TARGET/W1-HERO-003.glb" "4ebdf5db789518796d6f3d2cfd2bf8ba33913256969f0cd55eca05add18be766" && echo "ok       W1-HERO-003"
if [ ! -f "$TARGET/W1-HERO-006.glb" ]; then
  echo "fetching W1-HERO-006 ..."
  curl -fsSL "https://public.customuse.com/custom-models/e9007b01-5ad1-4b2f-bae0-1dcca45a4fc6/model-99b77df9c760b0f0bb7cc5df4ac0a54f8819748f56733c968ff1b9b0502365a4.glb" -o "$TARGET/W1-HERO-006.glb"
fi
verify "$TARGET/W1-HERO-006.glb" "99b77df9c760b0f0bb7cc5df4ac0a54f8819748f56733c968ff1b9b0502365a4" && echo "ok       W1-HERO-006"
if [ ! -f "$TARGET/W1-HERO-008.glb" ]; then
  echo "fetching W1-HERO-008 ..."
  curl -fsSL "https://public.customuse.com/custom-models/7119b83f-d869-4667-b448-26c899ba4b1a/model-1504b9325b49eb86c35b6e964049269b28b71668db10c7131ff782ed42134200.glb" -o "$TARGET/W1-HERO-008.glb"
fi
verify "$TARGET/W1-HERO-008.glb" "1504b9325b49eb86c35b6e964049269b28b71668db10c7131ff782ed42134200" && echo "ok       W1-HERO-008"

echo
echo "== Tripo props (exported through the owner's authorised browser route) =="
# The public Tripo links below are workspace pages, not direct file downloads:
# export them from the Tripo studio in the browser and drop the .glb files into
# the target directory. The script verifies the checksum of whatever is there.
if [ -f "$TARGET/W1-PROP-010.glb" ]; then
  verify "$TARGET/W1-PROP-010.glb" "f96cdade9cd57b1288121544fbb401b399a8028e1a6d171f48fe83bb38b5faba" && echo "ok       W1-PROP-010"
else
  echo "MISSING  W1-PROP-010 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/f8d83e38-b2ff-45bc-b601-8c7619401307)"
fi
if [ -f "$TARGET/W1-PROP-011.glb" ]; then
  verify "$TARGET/W1-PROP-011.glb" "0430b3b2d130bebcd8e0a511f403b1fcf81ef58d2682aa37f6d99aac9f871550" && echo "ok       W1-PROP-011"
else
  echo "MISSING  W1-PROP-011 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/ff562798-6d69-4a1e-a9b2-035e93354ab8)"
fi
if [ -f "$TARGET/W1-PROP-012.glb" ]; then
  verify "$TARGET/W1-PROP-012.glb" "48ed24f8712cee4ec76c46629100bd0fdea89c0239bbcd6afd5377075fe20beb" && echo "ok       W1-PROP-012"
else
  echo "MISSING  W1-PROP-012 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/b043bcbf-bb53-44eb-adcc-96e73d40297a)"
fi
if [ -f "$TARGET/W1-PROP-013.glb" ]; then
  verify "$TARGET/W1-PROP-013.glb" "741f66e44049b90c35ccf73fc051e49dffd5c90a475c36eac50b8e9291e00181" && echo "ok       W1-PROP-013"
else
  echo "MISSING  W1-PROP-013 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/426618c4-b6c2-48c3-8bf3-f79c4ec6bbdf)"
fi
if [ -f "$TARGET/W1-PROP-014.glb" ]; then
  verify "$TARGET/W1-PROP-014.glb" "de78e068ca28a92557b63345887f25d4f1c5849d78ee4b12aaabce702eb18151" && echo "ok       W1-PROP-014"
else
  echo "MISSING  W1-PROP-014 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/1130d29b-973d-4c61-a303-8f241077d793)"
fi
if [ -f "$TARGET/W1-PROP-015.glb" ]; then
  verify "$TARGET/W1-PROP-015.glb" "9980992607a925f9cdaca308a8b85e6f50c7b1eafd3d759a089db7e74eaa6024" && echo "ok       W1-PROP-015"
else
  echo "MISSING  W1-PROP-015 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/528645ed-0b74-4043-9a67-d3abf9138517)"
fi
if [ -f "$TARGET/W1-PROP-016.glb" ]; then
  verify "$TARGET/W1-PROP-016.glb" "af85f92dbf094b64cf8b4da74394f7e736ac0b5c6a6fe85204a0594fd51e5c81" && echo "ok       W1-PROP-016"
else
  echo "MISSING  W1-PROP-016 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/2fe71809-0e7e-4f1e-a50c-f110dd27b93a)"
fi
if [ -f "$TARGET/W1-PROP-017.glb" ]; then
  verify "$TARGET/W1-PROP-017.glb" "56399ccc758e9628736ace84b0c2aaaf84b86ff49fae410af68beac53fd3843d" && echo "ok       W1-PROP-017"
else
  echo "MISSING  W1-PROP-017 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/0e3c0714-f669-40e0-9a8a-16dc591aee84)"
fi
if [ -f "$TARGET/W1-PROP-018.glb" ]; then
  verify "$TARGET/W1-PROP-018.glb" "c28c90e0095e79cb345eced62196e9461bf329a8e7b6be11bce9220b19ebd647" && echo "ok       W1-PROP-018"
else
  echo "MISSING  W1-PROP-018 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/36b117e3-b74a-4366-874d-23497c3b5e1c)"
fi
if [ -f "$TARGET/W1-HERO-009.glb" ]; then
  verify "$TARGET/W1-HERO-009.glb" "a0d03df0cea7485d709e597e9a14f0feb3bdbc831d8f5b2c698f94116982bb52" && echo "ok       W1-HERO-009"
else
  echo "MISSING  W1-HERO-009 (export via Tripo studio: https://studio.tripo3d.ai/workspace/generate/9ea109ef-2c58-495c-9e48-fc7d863146de)"
fi

echo
echo "Next:"
echo "  blender --background --python game/tools/cleanup_provider_assets.py"
echo "  godot --headless --editor --path game --quit"
