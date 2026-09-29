"""Preview a continuous neutral skin shell derived from the source body.

The sensitive source patches are excluded before voxel remeshing.  Voxel
remeshing closes the resulting openings from neighbouring body surfaces and
removes small anatomical details without inventing a protruding local cap.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import bmesh
import bpy


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
skin = bpy.data.collections["ZT_Skin"]
source_objects = [obj for obj in skin.all_objects if obj.type == "MESH"]


def identity(obj: bpy.types.Object) -> str:
    return " ".join(
        (
            obj.name,
            str(obj.get("bodyPartId", "")),
            str(obj.get("zt_source_name", "")),
        )
    ).lower()


def is_sensitive(obj: bpy.types.Object) -> bool:
    text = identity(obj)
    return (
        bool(obj.get("zt_neutralized"))
        or "urogenital" in text
        or "anal_region" in text
        or "mammary_region" in text
        or "inframammary_region" in text
    )


# Sensitive source pieces must not participate in the derived surface and are
# not shown in the preview.
for obj in source_objects:
    if is_sensitive(obj):
        obj.hide_render = True

preview_collection = bpy.data.collections.new("ZT_NeutralPreview")
bpy.context.scene.collection.children.link(preview_collection)
depsgraph = bpy.context.evaluated_depsgraph_get()
duplicates: list[bpy.types.Object] = []
for source in source_objects:
    if is_sensitive(source):
        continue
    mesh = bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph))
    duplicate = bpy.data.objects.new(f"preview_{source.name}", mesh)
    duplicate.matrix_world = source.matrix_world.copy()
    preview_collection.objects.link(duplicate)
    duplicates.append(duplicate)

bpy.ops.object.select_all(action="DESELECT")
for duplicate in duplicates:
    duplicate.select_set(True)
bpy.context.view_layer.objects.active = duplicates[0]
bpy.ops.object.join()
shell = bpy.context.view_layer.objects.active
shell.name = "Neutral continuous surface"
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
shell.data.remesh_voxel_size = 0.005
bpy.ops.object.voxel_remesh()

# Smooth the voxel result but retain recognisable human proportions.
smooth = shell.modifiers.new("Clinical surface smoothing", "SMOOTH")
smooth.factor = 1.35
smooth.iterations = 5
bpy.context.view_layer.objects.active = shell
bpy.ops.object.modifier_apply(modifier=smooth.name)

# Keep only the two modesty bands that need a featureless surface. The pelvis
# band also bridges the front and rear openings left by the removed patches.
mesh = shell.data
bm = bmesh.new()
bm.from_mesh(mesh)
delete_vertices = [
    vertex
    for vertex in bm.verts
    if not (0.705 <= vertex.co.z <= 0.985 or 1.245 <= vertex.co.z <= 1.500)
]
bmesh.ops.delete(bm, geom=delete_vertices, context="VERTS")
bm.to_mesh(mesh)
bm.free()
mesh.update()

# Put the smooth shell just outside the segmented source surface to avoid
# flicker while keeping the real body silhouette.
shell.scale.x = 1.006
shell.scale.y = 1.006
shell["bodyPartId"] = "neutral_clinical_surface"
shell["zt_source_name"] = "Project-authored neutral clinical surface"
shell["zt_neutralized"] = True
for polygon in mesh.polygons:
    polygon.use_smooth = True
material_source = next(
    obj for obj in source_objects if "hypogastric_region" in identity(obj)
)
for material in material_source.data.materials:
    mesh.materials.append(material)

module_path = ROOT / "scripts" / "build_from_zanatomy.py"
spec = importlib.util.spec_from_file_location("zhiteng_build", module_path)
build = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(build)
build.RENDER_DIR = Path("/private/tmp/zhiteng-neutral-shell")
build.RENDER_DIR.mkdir(parents=True, exist_ok=True)
visible = [obj for obj in source_objects if not is_sensitive(obj)] + [shell]
build.render_views(visible)
