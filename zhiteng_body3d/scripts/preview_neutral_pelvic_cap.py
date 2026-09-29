"""Render a temporary smooth, featureless pelvic-cap candidate."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import bmesh
import bpy


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
skin = bpy.data.collections["ZT_Skin"]
objects = [obj for obj in skin.all_objects if obj.type == "MESH"]
for obj in list(objects):
    if obj.get("zt_neutralized") or "anal_region" in str(obj.get("bodyPartId", "")):
        skin.objects.unlink(obj)

mesh = bpy.data.meshes.new("Neutral pelvic cap")
cap = bpy.data.objects.new("Neutral pelvic cap", mesh)
skin.objects.link(cap)
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
bm.to_mesh(mesh)
bm.free()
cap.scale = (0.058, 0.030, 0.073)
cap.location = (0.0, -0.049, 0.829)
cap["bodyPartId"] = "neutral_pelvic_surface"
cap["zt_source_name"] = "Neutral pelvic surface"
cap["zt_neutralized"] = True
for polygon in mesh.polygons:
    polygon.use_smooth = True
source = next(obj for obj in objects if "hypogastric_region" in str(obj.get("bodyPartId", "")))
for material in source.data.materials:
    mesh.materials.append(material)

module_path = ROOT / "scripts" / "build_from_zanatomy.py"
spec = importlib.util.spec_from_file_location("zhiteng_build", module_path)
build = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(build)
build.RENDER_DIR = Path("/private/tmp/zhiteng-neutral-cap")
build.RENDER_DIR.mkdir(parents=True, exist_ok=True)
build.render_views([obj for obj in skin.all_objects if obj.type == "MESH"])
