#!/usr/bin/env bash
# Regenerate the whole environment kit (textures, materials, buildings, props) and import it.
#   tools/blender/build_all.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 tools/blender/gen_textures.py
python3 tools/blender/gen_materials.py
blender -b --factory-startup --python tools/blender/buildings.py 2>&1 | grep -E "^module|wrote|Error|Traceback" || true
blender -b --factory-startup --python tools/blender/props.py 2>&1 | grep -E "^prop|wrote|Error|Traceback" || true
godot --headless --path . --import >/dev/null 2>&1 || true
python3 tools/blender/configure_imports.py
# second pass picks up the import script for newly created .import files
godot --headless --path . --import >/dev/null 2>&1 || true
echo "kit rebuilt"
