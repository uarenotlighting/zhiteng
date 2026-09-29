"""Shared lower-body transforms for the neutral mannequin pipeline.

`preview_full_neutral_shell.py` lengthens the legs of the skin shell from the
waist and then angles them slightly outward (a straddle). Every internal layer
(muscle / bone / organ) must go through exactly the same world-space
transforms, otherwise the skeleton sits ~22 cm lower than the skin, or the
femurs poke through the inner thighs, and the "marker covered by skin" effect
breaks. Keep the constants here so both exporters cannot drift apart.

World Z is height in the Blender master (glTF export converts to +Y up).
"""

from __future__ import annotations

import bmesh
import bpy

LEG_PIVOT = 0.98
LEG_SCALE = 1.22

# Straddle, applied AFTER the stretch (heights below are post-stretch).
# Legs pivot at the hip line and each foot ends FOOT_SPREAD farther out. The
# shift fades to zero within MIDLINE_FADE of the midline so the crotch fill is
# not torn into a furrow.
HIP_Z = 1.10 / 1.36 * LEG_SCALE  # historical "tuned(1.10)" of the skin script
FOOT_SPREAD = 0.10
MIDLINE_FADE = 0.03
# Below the hip line, every lower-limb object keeps some vertex within this
# distance of the midline (widest measured: outer thigh 0.181, toes 0.146).
# Hands and forearms hanging beside the thighs never come closer than 0.225.
ARM_MIN_ABS_X = 0.19


def stretch_z(z: float) -> float:
    """Map a world-space height onto the stretched mannequin."""
    if z <= LEG_PIVOT:
        return z * LEG_SCALE
    return z + LEG_PIVOT * (LEG_SCALE - 1.0)


def straddle_x(x: float, z: float) -> float:
    """Angle a leg vertex outward. `z` must already be post-stretch."""
    if z >= HIP_Z or abs(x) < 1e-4:
        return x
    amount = FOOT_SPREAD * (HIP_Z - z) / HIP_Z
    amount *= min(1.0, abs(x) / MIDLINE_FADE)
    return x + amount if x > 0.0 else x - amount


def _world_points(obj: bpy.types.Object):
    world = obj.matrix_world
    return [world @ vertex.co for vertex in obj.data.vertices]


def is_lower_limb_object(obj: bpy.types.Object) -> bool:
    """True when the object belongs to the pelvis / legs rather than the arms.

    Decided on the source (pre-stretch) geometry: among vertices below the
    hip line, arm and hand objects stay far out to the side, leg objects reach
    close to the midline. Objects entirely above the hip line return False;
    the straddle would not move them anyway.
    """
    if obj.type != "MESH":
        return False
    hip_pre = HIP_Z / LEG_SCALE
    below = [abs(point.x) for point in _world_points(obj) if point.z < hip_pre]
    if not below:
        return False
    return min(below) < ARM_MIN_ABS_X


def stretch_object(obj: bpy.types.Object, straddle: bool | None = None) -> None:
    """Apply `stretch_z` (and the leg straddle) to a mesh object, in place.

    Works in world space so objects with different transforms end up on the
    same body. Shared mesh datablocks are made single-user first because the
    same local coordinates would otherwise be stretched twice.

    `straddle` defaults to `is_lower_limb_object(obj)`, so bones and muscles
    of the legs follow the skin while the arms stay where they are.
    """
    if obj.type != "MESH":
        return
    if straddle is None:
        straddle = is_lower_limb_object(obj)
    if obj.data.users > 1:
        obj.data = obj.data.copy()

    world = obj.matrix_world.copy()
    inv_world = world.inverted()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for vertex in bm.verts:
        point = world @ vertex.co
        point.z = stretch_z(point.z)
        if straddle:
            point.x = straddle_x(point.x, point.z)
        vertex.co = inv_world @ point
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
