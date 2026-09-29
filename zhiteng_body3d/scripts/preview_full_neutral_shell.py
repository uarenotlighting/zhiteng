"""Build or preview a continuous, gender-neutral clinical mannequin surface."""

from __future__ import annotations

import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import bmesh
import bpy


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
sys.path.insert(0, str(ROOT / "scripts"))
from zt_leg_stretch import HIP_Z, straddle_x, stretch_z  # noqa: E402

FINAL = "--final" in sys.argv[sys.argv.index("--") + 2 :]
VERSION = "zhiteng_zanatomy_neutral_20260922_v21"
skin = bpy.data.collections["ZT_Skin"]
sources = [obj for obj in skin.all_objects if obj.type == "MESH"]
preview_collection = bpy.data.collections.new("ZT_NeutralFullPreview")
bpy.context.scene.collection.children.link(preview_collection)
depsgraph = bpy.context.evaluated_depsgraph_get()
duplicates: list[bpy.types.Object] = []


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
    )


for source in sources:
    if is_sensitive(source):
        continue
    mesh = bpy.data.meshes.new_from_object(source.evaluated_get(depsgraph))
    duplicate = bpy.data.objects.new(f"preview_{source.name}", mesh)
    duplicate.matrix_world = source.matrix_world.copy()
    preview_collection.objects.link(duplicate)
    duplicates.append(duplicate)


def add_bridge(name: str, location: tuple[float, float, float], scale: tuple[float, float, float]) -> None:
    mesh = bpy.data.meshes.new(name)
    bridge = bpy.data.objects.new(name, mesh)
    preview_collection.objects.link(bridge)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    bm.to_mesh(mesh)
    bm.free()
    bridge.location = location
    bridge.scale = scale
    duplicates.append(bridge)


def add_convex_bridge(name: str, points: list[tuple[float, float, float]]) -> None:
    mesh = bpy.data.meshes.new(name)
    bridge = bpy.data.objects.new(name, mesh)
    preview_collection.objects.link(bridge)
    bm = bmesh.new()
    for point in points:
        bm.verts.new(point)
    bmesh.ops.convex_hull(bm, input=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    duplicates.append(bridge)


def add_box_bridge(name: str, location: tuple[float, float, float], scale: tuple[float, float, float]) -> None:
    mesh = bpy.data.meshes.new(name)
    bridge = bpy.data.objects.new(name, mesh)
    preview_collection.objects.link(bridge)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    bm.to_mesh(mesh)
    bm.free()
    bridge.location = location
    bridge.scale = scale
    duplicates.append(bridge)


# These volumes intersect the surrounding neutral source regions. After voxel
# union they become a single continuous surface, never a visible local cap.
# Stay on the lower abdomen. A wider sphere here welds the inner thighs into
# one shape, which no longer reads as two legs.
add_bridge("Neutral pelvis bridge", (0.0, -0.02, 0.91), (0.055, 0.045, 0.04))
# Seal only the posterior cleft. It sits behind the thigh gap, so it does not
# weld the legs together in the front view.
add_bridge("Neutral cleft seal", (0.0, 0.07, 0.86), (0.012, 0.020, 0.016))
# Close the groin the way a display mannequin does. Measured on the source
# (pre-stretch world coordinates): the removed pubic patch spans
# x ±0.034, y -0.073..-0.043, z 0.790..0.838; the removed anal patch spans
# x ±0.016, y 0.013..0.072, z 0.739..0.784; the inner thighs are only ~3 cm
# apart between z 0.72 and 0.80. Three ellipsoids fill exactly those spots,
# so after voxel union and smoothing the crotch reads as two legs meeting in
# a soft inverted V, not as a box, a flat panel or a tunnel.
#  - pubic pad: flush with the lower abdomen, closes the front hole.
#    Its front (y -0.066) stays behind the surrounding pubic skin (~ -0.069)
#    so nothing bulges: a mannequin pubis is a flat plane.
add_bridge("Neutral pubic pad", (0.0, -0.038, 0.816), (0.052, 0.028, 0.042))
#  - perineal fill: welds the upper inner thighs into one crotch. Kept
#    behind the pubic plane for the same reason.
add_bridge("Neutral perineal fill", (0.0, 0.004, 0.784), (0.036, 0.064, 0.040))
#  - posterior fill: closes the anal hole beneath the cleft seal.
add_bridge("Neutral posterior fill", (0.0, 0.044, 0.762), (0.030, 0.046, 0.036))

bpy.ops.object.select_all(action="DESELECT")
for duplicate in duplicates:
    duplicate.select_set(True)
bpy.context.view_layer.objects.active = duplicates[0]
bpy.ops.object.join()
shell = bpy.context.view_layer.objects.active
shell.name = "Neutral clinical mannequin"
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
shell.data.remesh_voxel_size = 0.006
bpy.ops.object.voxel_remesh()

# The source is made of many anatomical surface patches. Voxel remeshing can
# leave tiny disconnected islands near removed sensitive pieces. Keep the
# continuous body shell only; eyes/teeth and other detached details are not
# needed on a clinical localisation mannequin either.
bm = bmesh.new()
bm.from_mesh(shell.data)
unseen = set(bm.verts)
components: list[set[bmesh.types.BMVert]] = []
while unseen:
    seed = unseen.pop()
    component = {seed}
    stack = [seed]
    while stack:
        vertex = stack.pop()
        for edge in vertex.link_edges:
            neighbour = edge.other_vert(vertex)
            if neighbour in unseen:
                unseen.remove(neighbour)
                component.add(neighbour)
                stack.append(neighbour)
    components.append(component)
main_component = max(components, key=len)
for component in components:
    if component is main_component or len(component) < 100:
        continue
    xs = [v.co.x for v in component]
    ys = [v.co.y for v in component]
    zs = [v.co.z for v in component]
    print(
        "[zhiteng] discarded island",
        len(component),
        f"x[{min(xs):+.3f},{max(xs):+.3f}] y[{min(ys):+.3f},{max(ys):+.3f}] z[{min(zs):.3f},{max(zs):.3f}]",
    )
discard = [vertex for component in components if component is not main_component for vertex in component]
if discard:
    bmesh.ops.delete(bm, geom=discard, context="VERTS")
bm.to_mesh(shell.data)
bm.free()
shell.data.update()
print("[zhiteng] voxel components", sorted((len(component) for component in components), reverse=True)[:12])

# Flatten the central pelvic silhouette into a continuous body plane.  The
# source faces -Y; values that are more negative project farther forward.
for vertex in shell.data.vertices:
    x, y, z = vertex.co
    # Balance the source's strongly masculine shoulder-to-hip silhouette into
    # an androgynous clinical mannequin while preserving real human anatomy.
    if 1.30 <= z <= 1.62:
        shoulder_weight = max(0.0, 1.0 - abs(z - 1.46) / 0.16)
        vertex.co.x *= 1.0 - 0.075 * shoulder_weight
    if 0.74 <= z <= 1.08:
        hip_weight = max(0.0, 1.0 - abs(z - 0.90) / 0.18)
        vertex.co.x *= 1.0 + 0.055 * hip_weight
    if 0.70 <= z <= 0.99 and abs(x) <= 0.115 and y < 0.0:
        vertical = max(0.0, min(1.0, (z - 0.70) / 0.29))
        target_y = -0.082 - 0.008 * vertical
        lateral = max(0.0, min(1.0, (0.115 - abs(x)) / 0.060))
        if y < target_y:
            vertex.co.y = y + (target_y - y) * lateral
    if 1.235 <= z <= 1.505 and abs(x) <= 0.145 and y < 0.0:
        # Make the chest a shallow, continuous mannequin plane. This removes
        # nipples and avoids introducing either male or female breast anatomy.
        target_y = -0.078
        lateral = max(0.0, min(1.0, (0.145 - abs(x)) / 0.045))
        if y < target_y:
            vertex.co.y = y + (target_y - y) * lateral

# A moderate global smoothing pass removes nipples and other small surface
# details while retaining the face, joints, hands, feet and real proportions.
smooth = shell.modifiers.new("Featureless clinical smoothing", "SMOOTH")
smooth.factor = 1.15
smooth.iterations = 7
bpy.context.view_layer.objects.active = shell
bpy.ops.object.modifier_apply(modifier=smooth.name)

# Remove the remaining pectoral relief without shrinking the torso outline.
# Smoothing only depth keeps the anatomical height/width used for localisation.
chest_group = shell.vertex_groups.new(name="Neutral chest plane")
chest_indices = [
    vertex.index
    for vertex in shell.data.vertices
    if 1.18 <= vertex.co.z <= 1.52 and abs(vertex.co.x) <= 0.205
]
chest_group.add(chest_indices, 1.0, "REPLACE")
chest_smooth = shell.modifiers.new("Neutral chest depth", "SMOOTH")
chest_smooth.factor = 1.6
chest_smooth.iterations = 14
chest_smooth.vertex_group = chest_group.name
chest_smooth.use_x = False
chest_smooth.use_y = True
chest_smooth.use_z = False
bpy.context.view_layer.objects.active = shell
bpy.ops.object.modifier_apply(modifier=chest_smooth.name)

# Lengthen the legs. Do not cut the groin: a slot there is a hole through
# to the back wall, which reads as a cavity from the front.
# World Z is height; the shell keeps a translation.
world = shell.matrix_world.copy()
inv_world = world.inverted()
bm = bmesh.new()
bm.from_mesh(shell.data)
bm.faces.ensure_lookup_table()
bm.verts.ensure_lookup_table()
bm.normal_update()


def world_of(co):
    return world @ co


# Stretch the legs from the waist so the lower body stays a little longer
# than the torso, without moving the chest or head proportions.
# The constants live in zt_leg_stretch.py because export_internal_layers.py
# must apply the identical transform to muscle / bone / organ.
for vertex in bm.verts:
    point = world_of(vertex.co)
    point.z = stretch_z(point.z)
    vertex.co = inv_world @ point

# The crotch is already closed by the pubic mound and perineal fill added
# before remeshing. Nothing is cut here: a hole would expose the back wall.

# A slight straddle. The groin stays one smooth surface; the legs angle
# outward from the hip so the gap is between two limbs, not a cut hole.
# Constants and formula live in zt_leg_stretch.py: export_internal_layers.py
# applies the same straddle to leg bones / muscles so they stay inside the skin.
hip_z = HIP_Z
spread_count = 0
# Only the legs move. Hands hang beside the thighs, so an x threshold cannot
# separate them from the outer thigh (it used to shear the thigh along
# |x| = 0.15 into a visible ridge). Instead flood-fill from the lowest vertex
# while staying below the hip line: both legs are reached through the crotch,
# the arms are only connected to the torso above the hips.
leg_seed = min(bm.verts, key=lambda v: world_of(v.co).z)
leg_verts = {leg_seed}
stack = [leg_seed]
while stack:
    vertex = stack.pop()
    for edge in vertex.link_edges:
        neighbour = edge.other_vert(vertex)
        if neighbour not in leg_verts and world_of(neighbour.co).z < hip_z:
            leg_verts.add(neighbour)
            stack.append(neighbour)
leg_span = max(abs(world_of(v.co).x) for v in leg_verts)
print("[zhiteng] leg flood", len(leg_verts), f"max|x|={leg_span:.3f}")
for vertex in leg_verts:
    point = world_of(vertex.co)
    new_x = straddle_x(point.x, point.z)
    if new_x == point.x:
        continue
    point.x = new_x
    vertex.co = inv_world @ point
    spread_count += 1
print("[zhiteng] leg straddle", spread_count)

# Round the crotch. The voxel union of the pubic mound, the perineal fill and
# the inner thighs still carries seams; a strong local smooth turns it into
# one soft saddle. The window stays below the lower abdomen and above the
# thigh gap so hips, buttocks and legs keep their measured proportions.
# Window in pre-stretch source heights, mapped through the leg stretch.
crotch_lo = stretch_z(0.715)
crotch_hi = stretch_z(0.880)
crotch = []
for vertex in bm.verts:
    point = world_of(vertex.co)
    if crotch_lo <= point.z <= crotch_hi and abs(point.x) <= 0.085 and -0.13 <= point.y <= 0.12:
        crotch.append(vertex)
for _ in range(18):
    if crotch:
        bmesh.ops.smooth_vert(bm, verts=crotch, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
print("[zhiteng] crotch smooth", len(crotch))

bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.normal_update()
bm.to_mesh(shell.data)
bm.free()
shell.data.update()

for polygon in shell.data.polygons:
    polygon.use_smooth = True
shell["bodyPartId"] = "neutral_body_surface"
shell["zt_source_name"] = "Project-authored gender-neutral clinical mannequin"
shell["zt_neutralized"] = True
shell.data.name = "Neutral clinical mannequin surface"
material_source = next(obj for obj in sources if len(obj.data.materials))
clinical_material = bpy.data.materials.new("ZT_Neutral_Clinical_Surface")
clinical_material.use_nodes = True
clinical_material.use_backface_culling = False
clinical_material.diffuse_color = (0.76, 0.75, 0.73, 1.0)
clinical_bsdf = clinical_material.node_tree.nodes.get("Principled BSDF")
clinical_bsdf.inputs["Base Color"].default_value = (0.76, 0.75, 0.73, 1.0)
clinical_bsdf.inputs["Roughness"].default_value = 0.82
shell.data.materials.clear()
shell.data.materials.append(clinical_material)

# Create a deliberate unisex clinical modesty layer that follows the real hip
# surface. A flat insert is merged into the wrap so there is no genital contour
# or separate codpiece-like object.
garment_mesh = shell.data.copy()
garment = bpy.data.objects.new("Neutral clinical pelvis cover", garment_mesh)
skin.objects.link(garment)
garment_bm = bmesh.new()
garment_bm.from_mesh(garment_mesh)
bmesh.ops.delete(
    garment_bm,
    geom=[vertex for vertex in garment_bm.verts if not (0.735 <= vertex.co.z <= 0.995)],
    context="VERTS",
)
garment_bm.to_mesh(garment_mesh)
garment_bm.free()
garment.scale.x = 1.035
garment.scale.y = 1.035

insert_mesh = bpy.data.meshes.new("Neutral pelvis cover insert")
insert = bpy.data.objects.new("Neutral pelvis cover insert", insert_mesh)
skin.objects.link(insert)
insert_bm = bmesh.new()
bmesh.ops.create_uvsphere(insert_bm, u_segments=32, v_segments=16, radius=1.0)
insert_bm.to_mesh(insert_mesh)
insert_bm.free()
insert.location = (0.0, -0.085, 0.860)
insert.scale = (0.150, 0.030, 0.125)

bpy.ops.object.select_all(action="DESELECT")
garment.select_set(True)
insert.select_set(True)
bpy.context.view_layer.objects.active = garment
bpy.ops.object.join()
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
garment.data.remesh_voxel_size = 0.004
bpy.ops.object.voxel_remesh()
garment_smooth = garment.modifiers.new("Pelvis cover smoothing", "SMOOTH")
garment_smooth.factor = 0.8
garment_smooth.iterations = 3
bpy.context.view_layer.objects.active = garment
bpy.ops.object.modifier_apply(modifier=garment_smooth.name)

cover_material = bpy.data.materials.new("ZT_Neutral_Clinical_Cover")
cover_material.diffuse_color = (0.12, 0.13, 0.14, 1.0)
cover_material.use_nodes = True
cover_bsdf = cover_material.node_tree.nodes.get("Principled BSDF")
cover_bsdf.inputs["Base Color"].default_value = (0.12, 0.13, 0.14, 1.0)
cover_bsdf.inputs["Roughness"].default_value = 0.92
garment.data.materials.clear()
garment.data.materials.append(cover_material)
garment["bodyPartId"] = "neutral_pelvic_cover"
garment["zt_source_name"] = "Project-authored unisex clinical pelvis cover"
garment["zt_neutralized"] = True
for polygon in garment.data.polygons:
    polygon.use_smooth = True
garment.hide_render = True

# render_views creates its own scene from ZT_Skin, so place only the candidate
# there for this disposable preview.
skin.objects.link(shell)
preview_collection.objects.unlink(shell)
for source in sources:
    source.hide_render = True
    source.hide_set(True)
garment.hide_set(True)

bpy.context.view_layer.update()
depsgraph = bpy.context.evaluated_depsgraph_get()
for ray_z in (0.76, 0.78, 0.80, 0.82, 0.84, 0.86, 0.88):
    hit, location, _normal, _index, hit_obj, _matrix = bpy.context.scene.ray_cast(
        depsgraph,
        (0.0, -2.0, ray_z),
        (0.0, 1.0, 0.0),
        distance=4.0,
    )
    print(
        "[zhiteng] neutral-ray",
        ray_z,
        hit,
        tuple(round(value, 5) for value in location) if hit else None,
        hit_obj.name if hit_obj else None,
    )

module_path = ROOT / "scripts" / "build_from_zanatomy.py"
spec = importlib.util.spec_from_file_location("zhiteng_build", module_path)
build = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(build)
build.VERSION = VERSION
build.RENDER_DIR = ROOT / "export" / "2d" if FINAL else Path("/private/tmp/zhiteng-neutral-full-shell")
build.RENDER_DIR.mkdir(parents=True, exist_ok=True)
original_mask_material = build.mask_material


def front_face_mask_material(index: int):
    material, rgb = original_mask_material(index)
    material.use_backface_culling = True
    return material, rgb


build.mask_material = front_face_mask_material
# Match the runtime GLB: only front faces draw, so the rear cap is not
# projected into the front orthographic view.
clinical_material.use_backface_culling = True
build.render_views([shell])

if FINAL:
    # GLB viewers use front-face rendering for this opaque surface, preventing
    # any rear inner wall from being visible through the thigh gap.
    clinical_material.use_backface_culling = True
    # Remove source objects only from this disposable Blender process. The
    # mother .blend is never saved here, so the editable source stays intact.
    for source in sources:
        bpy.data.objects.remove(source, do_unlink=True)
    bpy.data.objects.remove(garment, do_unlink=True)
    export_scene = bpy.data.scenes.new("ZT_Neutral_Export")
    export_scene.collection.objects.link(shell)
    bpy.context.window.scene = export_scene
    bpy.ops.object.select_all(action="DESELECT")
    shell.hide_set(False)
    shell.hide_render = False
    shell.select_set(True)
    bpy.context.view_layer.objects.active = shell
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

    manifest_path = ROOT / "export" / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["bodyModelVersion"] = VERSION
    manifest["exportedAt"] = datetime.now(timezone.utc).isoformat()
    manifest["geometryProfile"] = "gender-neutral-clinical-mannequin-v2"
    manifest["sensitiveAnatomyExcluded"] = True
    manifest["regionCount"] = 1
    manifest["removedSurfaceStructures"] = [
        "urogenital surface patches",
        "anal surface patches",
        "sex-specific chest surface detail",
    ]
    for layer in manifest["layers"]:
        if layer["id"] == "skin":
            layer["bytes"] = skin_path.stat().st_size
            layer["meshCount"] = 1
            layer["compression"] = "none"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print("[zhiteng] exported neutral clinical mannequin")
