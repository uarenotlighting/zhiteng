"""Bake Z-Anatomy surface-region provenance onto the neutral mannequin.

The published skin is deliberately one continuous remeshed shell, so its
original 236 ``Regions of human body`` object IDs are lost.  This tool brings
them back without changing the visible skin:

1. import the final ``export/skin.glb``;
2. classify each final-shell triangle from the nearest transformed source
   region in ``ZT_Skin``;
3. render the four lossless ID masks and ``regions.json`` from that exact
   classified shell; and
4. export a decimated, invisible ``region.glb`` raycast proxy for 3D picks.

Run after ``preview_full_neutral_shell.py --final`` and
``export_internal_layers.py``::

    blender -b blender/zhiteng_body.blend \
      -P scripts/bake_surface_regions.py -- "$PWD" --sync-app

The mother blend is never saved.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
from collections import Counter, defaultdict
from pathlib import Path

import bpy
from mathutils import Vector, kdtree


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
ARGS = sys.argv[sys.argv.index("--") + 2 :]
SYNC_APP = "--sync-app" in ARGS
APP_MODELS = ROOT.parent / "zhiteng_app" / "assets" / "models"
EXPORT_DIR = ROOT / "export"
TARGET_PROXY_FACES = 48_000
ANATOMICAL_MAPPING_VERSION = "zanatomy_surface_regions_v2"

sys.path.insert(0, str(ROOT / "scripts"))
from zt_leg_stretch import is_lower_limb_object, straddle_x, stretch_z  # noqa: E402


def identity(obj: bpy.types.Object) -> str:
    return " ".join(
        (obj.name, str(obj.get("bodyPartId", "")), str(obj.get("zt_source_name", "")))
    ).lower()


def excluded_source(obj: bpy.types.Object) -> bool:
    text = identity(obj)
    return "urogenital" in text or "anal_region" in text


def morph_source_point(point: Vector, lower_limb: bool) -> Vector:
    """Apply the same large-form transforms used by the final neutral shell."""
    point = point.copy()
    x, y, z = point
    if 1.30 <= z <= 1.62:
        shoulder_weight = max(0.0, 1.0 - abs(z - 1.46) / 0.16)
        point.x *= 1.0 - 0.075 * shoulder_weight
    if 0.74 <= z <= 1.08:
        hip_weight = max(0.0, 1.0 - abs(z - 0.90) / 0.18)
        point.x *= 1.0 + 0.055 * hip_weight
    if 0.70 <= z <= 0.99 and abs(x) <= 0.115 and y < 0.0:
        vertical = max(0.0, min(1.0, (z - 0.70) / 0.29))
        target_y = -0.082 - 0.008 * vertical
        lateral = max(0.0, min(1.0, (0.115 - abs(x)) / 0.060))
        if y < target_y:
            point.y = y + (target_y - y) * lateral
    if 1.235 <= z <= 1.505 and abs(x) <= 0.145 and y < 0.0:
        target_y = -0.078
        lateral = max(0.0, min(1.0, (0.145 - abs(x)) / 0.045))
        if y < target_y:
            point.y = y + (target_y - y) * lateral
    point.z = stretch_z(point.z)
    if lower_limb:
        point.x = straddle_x(point.x, point.z)
    return point


def load_build_module():
    module_path = ROOT / "scripts" / "build_from_zanatomy.py"
    spec = importlib.util.spec_from_file_location("zhiteng_build", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    manifest = json.loads((EXPORT_DIR / "manifest.json").read_text(encoding="utf-8"))
    module.VERSION = manifest["bodyModelVersion"]
    manifest["anatomicalMappingVersion"] = ANATOMICAL_MAPPING_VERSION
    module.ANATOMICAL_MAPPING_VERSION = ANATOMICAL_MAPPING_VERSION
    module.RENDER_DIR = EXPORT_DIR / "2d"
    return module, manifest


build, manifest = load_build_module()
skin_collection = bpy.data.collections.get("ZT_Skin")
if skin_collection is None:
    raise RuntimeError("Missing ZT_Skin collection")
sources = [
    obj
    for obj in skin_collection.all_objects
    if obj.type == "MESH" and not excluded_source(obj)
]
if not sources:
    raise RuntimeError("ZT_Skin contains no source regions")

# The source was saved before the final leg stretch and silhouette edits. Build
# a labelled nearest-neighbour cloud in the final shell's coordinate space.
source_records: list[tuple[str, str]] = []
point_count = sum(len(obj.data.vertices) for obj in sources)
tree = kdtree.KDTree(point_count)
cursor = 0
for obj in sources:
    region_id = str(obj.get("bodyPartId", build.stable_id(obj.name)))
    source_name = str(obj.get("zt_source_name", obj.name))
    record_index = len(source_records)
    source_records.append((region_id, source_name))
    lower_limb = is_lower_limb_object(obj)
    world = obj.matrix_world
    for vertex in obj.data.vertices:
        tree.insert(morph_source_point(world @ vertex.co, lower_limb), record_index)
        cursor += 1
tree.balance()
print(f"[zhiteng] region source cloud: {len(source_records)} objects, {cursor} vertices")

# Import only the final published shell; it contains the remesh/smoothing that
# the user actually sees and touches.
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(EXPORT_DIR / "skin.glb"))
imported = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
if not imported:
    raise RuntimeError("skin.glb imported no mesh")
shell = max(imported, key=lambda obj: len(obj.data.polygons))
shell_world = shell.matrix_world

# A vertex vote is both faster and more stable than independently classifying
# adjacent triangle centres. Ties fall back to the polygon centre.
vertex_labels: list[int] = []
distances: list[float] = []
for vertex in shell.data.vertices:
    point = shell_world @ vertex.co
    nearest, record_index, distance = tree.find(point)
    if nearest is None:
        raise RuntimeError("surface-region KD tree returned no result")
    vertex_labels.append(record_index)
    distances.append(distance)

faces_by_region: dict[int, list[tuple[int, ...]]] = defaultdict(list)
for polygon in shell.data.polygons:
    votes = Counter(vertex_labels[index] for index in polygon.vertices)
    record_index, count = votes.most_common(1)[0]
    if count * 2 <= len(polygon.vertices):
        center = shell_world @ polygon.center
        _nearest, record_index, _distance = tree.find(center)
    faces_by_region[record_index].append(tuple(polygon.vertices))

ordered_regions = sorted(
    faces_by_region,
    key=lambda index: source_records[index][0],
)
region_collection = bpy.data.collections.new("ZT_SurfaceRegions")
bpy.context.scene.collection.children.link(region_collection)
clinical_material = bpy.data.materials.new("ZT_SurfaceRegion_Clinical")
clinical_material.diffuse_color = (0.76, 0.75, 0.73, 1.0)
clinical_material.use_nodes = True
clinical_bsdf = clinical_material.node_tree.nodes.get("Principled BSDF")
clinical_bsdf.inputs["Base Color"].default_value = (0.76, 0.75, 0.73, 1.0)
clinical_bsdf.inputs["Roughness"].default_value = 0.82

shell_vertices = [shell_world @ vertex.co for vertex in shell.data.vertices]
region_objects: list[bpy.types.Object] = []
for record_index in ordered_regions:
    region_id, source_name = source_records[record_index]
    source_faces = faces_by_region[record_index]
    used = sorted({vertex for face in source_faces for vertex in face})
    remap = {old: new for new, old in enumerate(used)}
    mesh = bpy.data.meshes.new(f"ZT region {region_id}")
    mesh.from_pydata(
        [shell_vertices[index] for index in used],
        [],
        [tuple(remap[index] for index in face) for face in source_faces],
    )
    mesh.materials.append(clinical_material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    obj = bpy.data.objects.new(f"ZT region {region_id}", mesh)
    obj["bodyPartId"] = region_id
    obj["zt_source_name"] = source_name
    obj["zt_layer"] = "region"
    region_collection.objects.link(obj)
    region_objects.append(obj)

for obj in sources + imported:
    obj.hide_render = True
    obj.hide_set(True)

# render_views links ZT_Skin, so temporarily put only the classified final-shell
# pieces in that collection. The mother file is not saved and remains untouched.
for obj in region_objects:
    skin_collection.objects.link(obj)
original_mask_material = build.mask_material


def front_face_mask_material(index: int):
    material, rgb = original_mask_material(index)
    material.use_backface_culling = True
    return material, rgb


build.mask_material = front_face_mask_material
build.render_views(region_objects)

# Export a much lighter copy for 3D hit-testing. Each object keeps the original
# source ID/name in glTF extras, while the visible skin remains the single smooth
# production mesh.
total_faces = sum(len(obj.data.polygons) for obj in region_objects)
ratio = min(1.0, TARGET_PROXY_FACES / max(total_faces, 1))
for obj in region_objects:
    face_count = len(obj.data.polygons)
    if ratio < 0.98 and face_count > 24:
        modifier = obj.modifiers.new("ZT_RegionProxy_Decimate", "DECIMATE")
        modifier.ratio = max(ratio, min(1.0, 12 / face_count))
        modifier.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        obj.hide_set(False)
        try:
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        except RuntimeError:
            obj.modifiers.remove(modifier)

proxy_scene = bpy.data.scenes.new("ZT_SurfaceRegion_Export")
for obj in region_objects:
    if obj.name not in proxy_scene.collection.objects:
        proxy_scene.collection.objects.link(obj)
bpy.context.window.scene = proxy_scene
bpy.ops.object.select_all(action="DESELECT")
for obj in region_objects:
    obj.hide_set(False)
    obj.hide_render = False
    obj.select_set(True)
bpy.context.view_layer.objects.active = region_objects[0]
proxy_path = EXPORT_DIR / "region.glb"
bpy.ops.export_scene.gltf(
    filepath=str(proxy_path),
    export_format="GLB",
    use_selection=True,
    use_active_scene=True,
    export_apply=True,
    export_yup=True,
    export_extras=True,
    export_materials="NONE",
    export_animations=False,
    export_cameras=False,
    export_lights=False,
    export_draco_mesh_compression_enable=False,
)

region_layer = {
    "id": "region",
    "file": "region.glb",
    "required": True,
    "sourceCollection": "9: Regions of human body (transferred to neutral shell)",
    "meshCount": len(region_objects),
    "bytes": proxy_path.stat().st_size,
    "compression": "none",
    "purpose": "invisible surface-region raycast proxy",
}
manifest["layers"] = [item for item in manifest["layers"] if item.get("id") != "region"]
manifest["layers"].append(region_layer)
manifest["regionCount"] = len(region_objects)
manifest["surfaceRegionSourceCount"] = len(source_records)
(EXPORT_DIR / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

if SYNC_APP:
    APP_MODELS.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(proxy_path, APP_MODELS / proxy_path.name)
    shutil.copyfile(EXPORT_DIR / "manifest.json", APP_MODELS / "manifest.json")
    for name in ("regions.json", "front-mask.png", "back-mask.png", "left-mask.png", "right-mask.png"):
        shutil.copyfile(EXPORT_DIR / "2d" / name, APP_MODELS / "2d" / name)

distances.sort()
percentile = lambda p: distances[min(len(distances) - 1, int(len(distances) * p))]
print(
    "[zhiteng] baked surface regions:",
    len(region_objects),
    f"proxy={proxy_path.stat().st_size} bytes",
    f"nearest-distance p50={percentile(0.50):.4f} p95={percentile(0.95):.4f} max={distances[-1]:.4f}",
)
