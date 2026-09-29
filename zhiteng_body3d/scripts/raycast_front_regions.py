"""Report which surface meshes occupy the center-front pelvic pixels."""

from __future__ import annotations

import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
skin = bpy.data.collections["ZT_Skin"]
objects = [obj for obj in skin.all_objects if obj.type == "MESH"]
points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
low = Vector(tuple(min(point[index] for point in points) for index in range(3)))
high = Vector(tuple(max(point[index] for point in points) for index in range(3)))
center = (low + high) * 0.5
size = high - low
ortho_scale = max(size.z * 1.08, size.x * 1.75)
aspect = 768 / 1280
origin_y = center.y - max(size.length, 2.0) * 2.2
depsgraph = bpy.context.evaluated_depsgraph_get()

for image_y in (0.48, 0.50, 0.52, 0.54, 0.56, 0.58, 0.60):
    world_z = center.z + (0.5 - image_y) * ortho_scale
    origin = Vector((center.x, origin_y, world_z))
    hit, _, _, _, obj, _ = bpy.context.scene.ray_cast(
        depsgraph,
        origin,
        Vector((0, 1, 0)),
        distance=max(size.length, 2.0) * 5,
    )
    print(
        "RAY",
        image_y,
        world_z,
        hit,
        obj.name if obj else None,
        obj.get("bodyPartId") if obj else None,
        obj.get("zt_source_name") if obj else None,
    )
