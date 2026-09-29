"""Regenerate 2D orthographic assets from the lightweight derived blend."""

from __future__ import annotations

import sys
from pathlib import Path

import bpy


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
sys.path.insert(0, str(ROOT / "scripts"))

import build_from_zanatomy as pipeline  # noqa: E402


skin = bpy.data.collections["ZT_Skin"]
regions = pipeline.render_views(list(skin.objects))

active_scene = bpy.context.window.scene
keep_collections = {"ZT_Skin", "ZT_Muscle", "ZT_Bone", "ZT_Organ"}
linked = {collection.name for collection in active_scene.collection.children}
for name in keep_collections - linked:
    collection = bpy.data.collections.get(name)
    if collection is not None:
        active_scene.collection.children.link(collection)
for scene in list(bpy.data.scenes):
    if scene != active_scene:
        bpy.data.scenes.remove(scene)

for collection in list(bpy.data.collections):
    if collection.name not in keep_collections:
        bpy.data.collections.remove(collection)
for image in list(bpy.data.images):
    bpy.data.images.remove(image)
for _ in range(3):
    bpy.ops.outliner.orphans_purge(do_recursive=True)

bpy.ops.wm.save_as_mainfile(
    filepath=str(ROOT / "blender" / "zhiteng_body.blend"),
    compress=True,
)
print(f"[zhiteng] rendered {len(regions)} regions from derived blend")
