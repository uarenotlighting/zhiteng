"""Print bounds for sensitive surface regions in an exported skin GLB."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
bpy.ops.import_scene.gltf(filepath=str(ROOT / "export" / "skin.glb"))
objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return (
        Vector(tuple(min(point[index] for point in points) for index in range(3))),
        Vector(tuple(max(point[index] for point in points) for index in range(3))),
    )


all_points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
print("OVERALL", *(min(point[index] for point in all_points) for index in range(3)), *(max(point[index] for point in all_points) for index in range(3)))
for obj in objects:
    identity = " ".join((obj.name, str(obj.get("bodyPartId", "")), str(obj.get("zt_source_name", ""))))
    if re.search(r"urogen|pubic|perine|anal|genital|penis|scrot|inguinal|hypogastric|femoral|thigh|gluteal", identity, re.I):
        low, high = world_bounds(obj)
        vertices = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
        print(
            "REGION",
            obj.name,
            obj.get("bodyPartId"),
            "COUNT",
            len(vertices),
            "LOW",
            *low,
            "HIGH",
            *high,
            "MEAN",
            *(sum(vertex[index] for vertex in vertices) / len(vertices) for index in range(3)),
        )
