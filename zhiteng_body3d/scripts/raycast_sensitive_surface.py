"""Report source surface pieces around chest and pelvic feature locations."""

from __future__ import annotations

import bpy

skin = bpy.data.collections["ZT_Skin"]
depsgraph = bpy.context.evaluated_depsgraph_get()

for x, z in (
    (-0.06, 1.39),
    (0.06, 1.39),
    (-0.04, 1.34),
    (0.04, 1.34),
    (0.0, 0.90),
    (0.0, 0.85),
    (0.0, 0.80),
    (0.0, 0.76),
):
    hit, location, _normal, _index, obj, _matrix = bpy.context.scene.ray_cast(
        depsgraph,
        (x, -2.0, z),
        (0.0, 1.0, 0.0),
        distance=4.0,
    )
    print(
        "RAY",
        x,
        z,
        hit,
        tuple(round(value, 5) for value in location) if hit else None,
        obj.name if obj else None,
        obj.get("bodyPartId") if obj else None,
        obj.get("zt_source_name") if obj else None,
    )
