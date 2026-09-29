"""Turn the source model's external male anatomy into a neutral pelvic surface.

Run against the lightweight derived Blender mother file. The two urogenital
surface patches are flattened with a smooth lateral falloff, then the skin GLB
and all four orthographic 2D views/masks are regenerated from that same mesh.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
VERSION = "zhiteng_zanatomy_neutral_20260922_v2"
skin_collection = bpy.data.collections.get("ZT_Skin")
if skin_collection is None:
    raise RuntimeError("Missing ZT_Skin collection")

skin_objects = [obj for obj in skin_collection.all_objects if obj.type == "MESH"]
sensitive = [
    obj
    for obj in skin_objects
    if obj.get("zt_neutralized")
    or "urogenital" in " ".join(
        (obj.name, str(obj.get("bodyPartId", "")), str(obj.get("zt_source_name", "")))
    ).lower()
]
if len(sensitive) != 2:
    raise RuntimeError(f"Expected two urogenital surface patches, found {len(sensitive)}")


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


for obj in sensitive:
    inverse = obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        world = obj.matrix_world @ vertex.co
        # The source faces -Y. Keep the seam attached at |X| ~= 0.034 while
        # collapsing the central projection into a softly curved pelvic plane.
        lateral = 1.0 - smoothstep(abs(world.x) / 0.0345)
        vertical = max(0.0, min(1.0, (world.z - 0.724) / 0.114))
        target_y = -0.050 - 0.022 * vertical - 0.006 * (abs(world.x) / 0.0345) ** 2
        strength = 0.96 * lateral
        world.y = world.y * (1.0 - strength) + target_y * strength
        # Remove the recognisable hanging silhouette as well as its depth.
        # The small V-shaped floor follows the natural meeting point of the
        # thighs and leaves a closed, non-anatomical pelvic patch.
        pelvic_floor = 0.790 + 0.014 * lateral
        world.z = max(world.z, pelvic_floor)
        vertex.co = inverse @ world
    side = "left" if ".l" in obj.name.lower() else "right"
    side_suffix = "l" if side == "left" else "r"
    obj.name = f"Neutral pelvic surface.{side_suffix}"
    obj.data.name = f"Neutral pelvic surface.{side_suffix}"
    obj["bodyPartId"] = f"neutral_pelvic_surface_{side}"
    obj["zt_source_name"] = f"Neutral pelvic surface.{side_suffix}"
    obj["zt_neutralized"] = True
    obj.data.update()

bpy.context.window.scene = next(
    scene for scene in bpy.data.scenes if skin_collection in scene.collection.children[:]
)
bpy.ops.object.select_all(action="DESELECT")
for obj in skin_objects:
    obj.hide_set(False)
    obj.hide_viewport = False
    obj.hide_render = False
    obj.select_set(True)
bpy.context.view_layer.objects.active = skin_objects[0]
skin_path = ROOT / "export" / "skin.glb"
bpy.ops.export_scene.gltf(
    filepath=str(skin_path),
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_extras=True,
    export_materials="EXPORT",
    export_animations=False,
    export_cameras=False,
    export_lights=False,
    export_draco_mesh_compression_enable=False,
)

module_path = ROOT / "scripts" / "build_from_zanatomy.py"
spec = importlib.util.spec_from_file_location("zhiteng_build", module_path)
build = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(build)
build.VERSION = VERSION
build.ROOT = ROOT
build.EXPORT_DIR = ROOT / "export"
build.RENDER_DIR = build.EXPORT_DIR / "2d"
build.render_views(skin_objects)

manifest_path = ROOT / "export" / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["bodyModelVersion"] = VERSION
manifest["exportedAt"] = datetime.now(timezone.utc).isoformat()
manifest["geometryProfile"] = "gender-neutral-pelvic-surface-v1"
manifest["reviewSafe"] = True
for layer in manifest["layers"]:
    if layer["id"] == "skin":
        layer["bytes"] = skin_path.stat().st_size
        layer["meshCount"] = len(skin_objects)
        layer["compression"] = "none"
manifest_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

bpy.ops.wm.save_as_mainfile(
    filepath=str(ROOT / "blender" / "zhiteng_body.blend"),
    compress=True,
)
print(f"[zhiteng] neutralized {len(sensitive)} pelvic patches and rebuilt 2D/3D skin")
