"""Reassemble the lightweight Blender mother file from exported GLB layers."""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
scene = bpy.context.scene

for layer in ("muscle", "bone", "organ"):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / "export" / f"{layer}.glb"))
    imported = set(bpy.data.objects) - before
    target_name = f"ZT_{layer.title()}"
    target = bpy.data.collections.get(target_name) or bpy.data.collections.new(target_name)
    if target.name not in {collection.name for collection in scene.collection.children}:
        scene.collection.children.link(target)
    for obj in imported:
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        target.objects.link(obj)

for collection in list(bpy.data.collections):
    if not collection.name.startswith("ZT_"):
        bpy.data.collections.remove(collection)
for _ in range(3):
    bpy.ops.outliner.orphans_purge(do_recursive=True)

bpy.ops.wm.save_as_mainfile(
    filepath=str(ROOT / "blender" / "zhiteng_body.blend"),
    compress=True,
)
print("[zhiteng] assembled skin, muscle, bone and organ collections")
