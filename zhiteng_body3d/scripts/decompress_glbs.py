"""Convert existing Draco GLBs to self-contained GLBs for iOS WebView."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
EXPORT_DIR = ROOT / "export"
manifest_path = EXPORT_DIR / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

for layer in ("skin", "muscle", "bone", "organ"):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    before = set(bpy.data.objects)
    source = EXPORT_DIR / f"{layer}.glb"
    bpy.ops.import_scene.gltf(filepath=str(source))
    objects = [obj for obj in set(bpy.data.objects) - before if obj.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]
    target = EXPORT_DIR / f"{layer}.plain.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(target),
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
    for item in manifest["layers"]:
        if item["id"] == layer:
            item["meshCount"] = len(objects)
            item["bytes"] = target.stat().st_size
            item["compression"] = "none"
    print(f"[zhiteng] converted {layer}: {len(objects)} meshes, {target.stat().st_size} bytes")

manifest_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
