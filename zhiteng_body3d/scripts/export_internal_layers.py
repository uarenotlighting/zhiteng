"""Export muscle / bone / organ GLBs aligned with the neutral skin shell.

The skin shell exported by `preview_full_neutral_shell.py --final` has its legs
lengthened from the waist. This script applies the identical transform to the
internal layers in memory and exports them, so all four GLBs share one body.

Usage (run after the skin shell export):

    blender -b blender/zhiteng_body.blend \
      -P scripts/export_internal_layers.py -- "$PWD"

The mother .blend is never saved by this script.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
sys.path.insert(0, str(ROOT / "scripts"))

from zt_leg_stretch import (  # noqa: E402
    FOOT_SPREAD,
    HIP_Z,
    LEG_PIVOT,
    LEG_SCALE,
    is_lower_limb_object,
    stretch_object,
)

EXPORT_DIR = ROOT / "export"
LAYERS = ("muscle", "bone", "organ")

manifest_path = EXPORT_DIR / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")


def world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


for layer in LAYERS:
    collection = bpy.data.collections.get(f"ZT_{layer.title()}")
    if collection is None:
        raise RuntimeError(f"Missing ZT_{layer.title()} collection")
    objects = [obj for obj in collection.all_objects if obj.type == "MESH"]
    if not objects:
        raise RuntimeError(f"ZT_{layer.title()} has no meshes")

    # Same approach as the skin exporter: a disposable scene that links only
    # this layer, made active through the (hidden) background window.
    export_scene = bpy.data.scenes.new(f"ZT_{layer.title()}_Export")
    for obj in objects:
        export_scene.collection.objects.link(obj)
    bpy.context.window.scene = export_scene
    bpy.context.view_layer.update()

    before_low, before_high = world_bounds(objects)
    straddled = 0
    for obj in objects:
        lower_limb = is_lower_limb_object(obj)
        straddled += int(lower_limb)
        stretch_object(obj, straddle=lower_limb)
    bpy.context.view_layer.update()
    after_low, after_high = world_bounds(objects)
    print(
        f"[zhiteng] {layer}: height {before_high.z - before_low.z:.3f} -> "
        f"{after_high.z - after_low.z:.3f} m (top {before_high.z:.3f} -> {after_high.z:.3f}), "
        f"straddled {straddled}/{len(objects)} objects"
    )

    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]

    target = EXPORT_DIR / f"{layer}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(target),
        export_format="GLB",
        use_selection=True,
        # The master keeps saved selections in its ortho-render scenes; without
        # this the exporter also writes those (and every previous layer).
        use_active_scene=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
        export_draco_mesh_compression_enable=False,
    )
    for item in manifest["layers"]:
        if item["id"] == layer:
            item["meshCount"] = len(objects)
            item["bytes"] = target.stat().st_size
            item["compression"] = "none"
    print(f"[zhiteng] exported {layer}: {len(objects)} meshes, {target.stat().st_size} bytes")

    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.window.scene = bpy.data.scenes[0]
    bpy.data.scenes.remove(export_scene)


def bump(version: str) -> str:
    match = re.search(r"_v(\d+)$", version)
    if not match:
        return f"{version}_v2"
    return f"{version[: match.start()]}_v{int(match.group(1)) + 1}"


manifest["bodyModelVersion"] = bump(manifest["bodyModelVersion"])
manifest["anatomicalMappingVersion"] = "zanatomy_surface_regions_v2"
manifest["exportedAt"] = datetime.now(timezone.utc).isoformat()
manifest["internalLayersAlignedToSkin"] = {
    "legPivot": LEG_PIVOT,
    "legScale": LEG_SCALE,
    "hipZ": round(HIP_Z, 4),
    "footSpread": FOOT_SPREAD,
    "note": "muscle/bone/organ share the skin shell's waist-down leg stretch and leg straddle",
}
manifest_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

# The four orthographic masks still describe the same skin geometry after the
# internal layers are aligned. Keep their declared model/mapping versions in
# lockstep with the manifest so 2D and 3D records never appear to use different
# bodies merely because this second export stage bumped the version.
regions_path = EXPORT_DIR / "2d" / "regions.json"
if regions_path.exists():
    regions = json.loads(regions_path.read_text(encoding="utf-8"))
    regions["bodyModelVersion"] = manifest["bodyModelVersion"]
    regions["anatomicalMappingVersion"] = manifest["anatomicalMappingVersion"]
    regions_path.write_text(
        json.dumps(regions, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
print(f"[zhiteng] manifest -> {manifest['bodyModelVersion']}")
