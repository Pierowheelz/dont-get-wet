#!/usr/bin/env python3
"""Point every kit .glb import at the shared post-import script (material remap + lights).

    python3 tools/blender/configure_imports.py

Run after Godot has created the .glb.import files once (godot --headless --path . --import), then
import again. Returns exit code 0; prints how many files were changed.
"""
import glob
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SCRIPT = "res://assets/buildings/kit_import.gd"
# folder -> its post-import script (vehicles add their lights on top of the kit's material swap)
FOLDERS = {"assets/buildings": SCRIPT, "assets/props": SCRIPT, "assets/vehicles": "res://assets/vehicles/vehicle_import.gd",
           # the country models are painted in vertex colours: their script makes every material show them
           "assets/country": "res://assets/country/country_import.gd"}


def main():
    changed = 0
    for folder, script in FOLDERS.items():
        for path in sorted(glob.glob(os.path.join(ROOT, folder, "**", "*.glb.import"), recursive=True)):
            s = open(path).read()
            new = re.sub(r'^import_script/path=.*$', 'import_script/path="%s"' % script, s, flags=re.M)
            # generated LODs fight with our hand-tuned bevels at street distance; keep them, but
            # meshes are small. Shadow meshes are fine.
            if new != s:
                open(path, "w").write(new)
                changed += 1
    print("configure_imports: updated %d .import files" % changed)


if __name__ == "__main__":
    main()
