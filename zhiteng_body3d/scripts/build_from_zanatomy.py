"""Build app-ready 2D and 3D body assets from the official Z-Anatomy blend.

Run:
  blender -b /path/to/Z-Anatomy/Startup.blend \
    -P scripts/build_from_zanatomy.py -- /path/to/zhiteng_body3d

The source contains a few third-party non-commercial structures. This script
exports only the body surface, musculoskeletal systems, and a conservative
major-organ allowlist.
"""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
EXPORT_DIR = ROOT / "export"
RENDER_DIR = EXPORT_DIR / "2d"
VERSION = "zhiteng_zanatomy_neutral_20260922_v2"
ANATOMICAL_MAPPING_VERSION = "zanatomy_surface_regions_v2"
SOURCE_OBJECTS = list(bpy.data.objects)

SYSTEM_COLLECTIONS = {
    "skin": "9: Regions of human body",
    "muscle": "4: Muscular system",
    "bone": "1: Skeletal system",
}
TARGET_POLYGONS = {
    "skin": 60_000,
    "muscle": 80_000,
    "bone": 70_000,
    "organ": 20_000,
}
LAYER_COLORS = {
    "skin": (0.72, 0.72, 0.70, 1.0),
    "muscle": (0.56, 0.25, 0.24, 1.0),
    "bone": (0.82, 0.79, 0.69, 1.0),
    "organ": (0.48, 0.28, 0.34, 1.0),
}
SKIN_EXCLUDES = ("hair", "eyelash", "eyebrow", "nail", "perionyx")

# This is only the clean Z-Anatomy base used by build_major_organs.py.  Exact
# names prevent a token such as "trachea" from accidentally pulling in
# pretracheal/paratracheal lymph nodes, and prevent whole liver + liver segment
# duplicates. Missing structures are added later from licensed BodyParts3D
# stable IDs.
BASE_ORGAN_SOURCE_NAMES = {
    "liver",
    "superior lobe of right lung",
    "middle lobe of right lung",
    "inferior lobe of right lung",
    "superior lobe of left lung",
    "inferior lobe of left lung",
    "stomach",
    "pancreas",
    "spleen",
    "gallbladder",
    "duodenum",
    "ascending colon",
    "transverse colon",
    "descending colon",
    "sigmoid colon",
    "urinary bladder",
    "trachea",
}

SENSITIVE_ORGAN_TOKENS = (
    "genital", "reproductive", "uterus", "uterine", "ovary", "ovarian",
    "fallopian", "vagina", "vulva", "clitoris", "prostate", "seminal",
    "vas deferens", "ductus deferens", "testis", "testicle", "epididym",
    "penis", "scrot", "gonad",
)


def stable_id(name: str) -> str:
    value = name.strip().lower()
    value = re.sub(r"\.l$", "_left", value)
    value = re.sub(r"\.r$", "_right", value)
    return re.sub(r"[^a-z0-9]+", "_", value).strip("_") or "unknown"


def is_geometry(obj: bpy.types.Object) -> bool:
    return (
        obj.type == "MESH"
        and len(obj.data.polygons) > 3
        and not obj.name.lower().endswith((".g", ".j", ".i"))
    )


def source_objects(layer: str) -> list[bpy.types.Object]:
    if layer in SYSTEM_COLLECTIONS:
        name = SYSTEM_COLLECTIONS[layer]
        collection = bpy.data.collections.get(name)
        if collection is None:
            raise RuntimeError(f"Missing Z-Anatomy collection: {name}")
        objects = [obj for obj in collection.objects if is_geometry(obj)]
        if layer == "skin":
            objects = [
                obj
                for obj in objects
                if not any(token in obj.name.lower() for token in SKIN_EXCLUDES)
            ]
        return objects

    if layer == "organ":
        return [
            obj
            for obj in SOURCE_OBJECTS
            if is_geometry(obj)
            and re.sub(r"\.\d{3}$", "", obj.name.lower()) in BASE_ORGAN_SOURCE_NAMES
            and not any(token in obj.name.lower() for token in SENSITIVE_ORGAN_TOKENS)
        ]
    raise ValueError(layer)


def material_for(layer: str) -> bpy.types.Material:
    name = f"ZT_{layer.title()}_Clinical"
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.diffuse_color = LAYER_COLORS[layer]
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = LAYER_COLORS[layer]
    bsdf.inputs["Roughness"].default_value = 0.72
    bsdf.inputs["Metallic"].default_value = 0.0
    return material


def prepare_layer(layer: str) -> list[bpy.types.Object]:
    sources = source_objects(layer)
    collection = bpy.data.collections.new(f"ZT_{layer.title()}")
    bpy.context.scene.collection.children.link(collection)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    objects = []
    for source in sources:
        evaluated = source.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(
            evaluated,
            preserve_all_data_layers=False,
            depsgraph=depsgraph,
        )
        obj = bpy.data.objects.new(source.name, mesh)
        obj.matrix_world = source.matrix_world.copy()
        obj["zt_layer"] = layer
        obj["zt_source_name"] = source.name
        obj["bodyPartId"] = stable_id(source.name)
        collection.objects.link(obj)
        objects.append(obj)

    total = sum(len(obj.data.polygons) for obj in objects)
    ratio = min(1.0, TARGET_POLYGONS[layer] / max(total, 1))
    material = material_for(layer)
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.data.materials.clear()
        obj.data.materials.append(material)
        obj.data.uv_layers.clear()
        while obj.data.color_attributes:
            obj.data.color_attributes.remove(obj.data.color_attributes[0])
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
            polygon.material_index = 0
        if ratio < 0.98 and len(obj.data.polygons) > 160:
            modifier = obj.modifiers.new(name="ZT_App_Decimate", type="DECIMATE")
            modifier.ratio = max(ratio, 0.008)
            modifier.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            try:
                bpy.ops.object.modifier_apply(modifier=modifier.name)
            except RuntimeError:
                obj.modifiers.remove(modifier)
            obj.select_set(False)
    print(
        f"[zhiteng] {layer}: {len(objects)} meshes, "
        f"{total} source polygons, ratio {ratio:.4f}"
    )
    return objects


def select_only(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.select_set(True)
    if objects:
        bpy.context.view_layer.objects.active = objects[0]


def export_layer(layer: str, objects: list[bpy.types.Object]) -> dict:
    select_only(objects)
    path = EXPORT_DIR / f"{layer}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path),
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
    return {
        "id": layer,
        "file": path.name,
        "required": layer == "skin",
        "sourceCollection": SYSTEM_COLLECTIONS.get(layer, "major-organ-allowlist"),
        "meshCount": len(objects),
        "bytes": path.stat().st_size,
    }


def bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    low = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    high = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return low, high


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def mask_material(index: int) -> tuple[bpy.types.Material, tuple[int, int, int]]:
    value = index + 1
    rgb = (
        48 + (value % 4) * 56,
        40 + ((value // 4) % 8) * 26,
        40 + ((value // 32) % 8) * 26,
    )
    # Shader sockets are scene-linear while PNG stores sRGB. Convert first so
    # the written interior pixels equal the IDs in regions.json byte-for-byte.
    def srgb_to_linear(channel: int) -> float:
        value = channel / 255
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    color = tuple(srgb_to_linear(channel) for channel in rgb) + (1.0,)
    material = bpy.data.materials.new(f"ZT_Mask_{value:06x}")
    material.diffuse_color = color
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = color
    emission.inputs["Strength"].default_value = 1.0
    material.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return material, rgb


def render_views(skin_objects: list[bpy.types.Object]) -> list[dict]:
    scene = bpy.data.scenes.new("ZT_Ortho_Render")
    skin_collection = bpy.data.collections.get("ZT_Skin")
    scene.collection.children.link(skin_collection)
    bpy.context.window.scene = scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 1280
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.use_freestyle = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.file_format = "WEBP"
    scene.render.image_settings.quality = 92
    low, high = bounds(skin_objects)
    center = (low + high) * 0.5
    size = high - low
    camera_data = bpy.data.cameras.new("ZT_Ortho_Camera")
    camera = bpy.data.objects.new("ZT_Ortho_Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(size.z * 1.08, size.x * 1.75)
    world = scene.world or bpy.data.worlds.new("ZT_World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (
        0.94,
        0.94,
        0.94,
        1,
    )
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    light_data = bpy.data.lights.new("ZT_Key", type="AREA")
    light_data.energy = 650
    light_data.size = 3.0
    light = bpy.data.objects.new("ZT_Key", light_data)
    scene.collection.objects.link(light)
    light.location = center + Vector((-2.5, -3.0, 3.5))
    look_at(light, center)
    # Anatomical sides: the body faces -Y and its own left (`.l` structures)
    # is at +X, so the "left" view puts the camera on +X. The 3D viewer
    # (body3d.html VIEW_DIRECTIONS) uses the same convention.
    views = {
        "front": Vector((0, -1, 0)),
        "back": Vector((0, 1, 0)),
        "left": Vector((1, 0, 0)),
        "right": Vector((-1, 0, 0)),
    }
    distance = max(size.length, 2.0) * 2.2
    for name, direction in views.items():
        camera.location = center + direction * distance
        look_at(camera, center)
        scene.render.filepath = str(RENDER_DIR / f"{name}.webp")
        bpy.ops.render.render(write_still=True)

    mappings = []
    originals = {obj.name: list(obj.data.materials) for obj in skin_objects}
    for index, obj in enumerate(sorted(skin_objects, key=lambda item: stable_id(item.name))):
        material, rgb = mask_material(index)
        obj.data.materials.clear()
        obj.data.materials.append(material)
        mappings.append(
            {
                "id": obj.get("bodyPartId", stable_id(obj.name)),
                "sourceName": obj.get("zt_source_name", obj.name),
                "rgb": list(rgb),
            }
        )
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.view_settings.use_curve_mapping = False
    # ID buffers are sampled by nearest colour, so avoid blending adjacent
    # IDs across the unusually dense facial/hand region boundaries.
    scene.render.filter_size = 0.01
    for name, direction in views.items():
        camera.location = center + direction * distance
        look_at(camera, center)
        scene.render.filepath = str(RENDER_DIR / f"{name}-mask.png")
        bpy.ops.render.render(write_still=True)
    for obj in skin_objects:
        obj.data.materials.clear()
        for material in originals[obj.name]:
            obj.data.materials.append(material)
    for material in list(bpy.data.materials):
        if material.name.startswith("ZT_Mask_"):
            bpy.data.materials.remove(material)
    (RENDER_DIR / "regions.json").write_text(
        json.dumps(
            {
                "bodyModelVersion": VERSION,
                "coordinateSystemVersion": "zanatomy_ortho_v1",
                "anatomicalMappingVersion": ANATOMICAL_MAPPING_VERSION,
                "imageWidth": scene.render.resolution_x,
                "imageHeight": scene.render.resolution_y,
                "views": list(views),
                "regions": mappings,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return mappings


def write_manifest(layers: list[dict], region_count: int) -> None:
    payload = {
        "bodyModelVersion": VERSION,
        "coordinateSystemVersion": "zanatomy_ortho_v1",
        "anatomicalMappingVersion": ANATOMICAL_MAPPING_VERSION,
        "pipeline": "official-z-anatomy-blender",
        "status": "generated",
        "exportedAt": datetime.now(timezone.utc).isoformat(),
        "layers": layers,
        "views2d": ["front", "back", "left", "right"],
        "regionCount": region_count,
        "license": "CC BY-SA 4.0",
        "attribution": "Z-Anatomy; BodyParts3D / DBCLS; see ATTRIBUTION.md",
        "excludedForLicense": [
            "kidney",
            "inner ear",
            "Brainder / white-matter reference structures",
        ],
    }
    (EXPORT_DIR / "manifest.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    layers = {}
    exported = []
    for layer in ("skin", "muscle", "bone", "organ"):
        layers[layer] = prepare_layer(layer)
        exported.append(export_layer(layer, layers[layer]))
    mappings = render_views(layers["skin"])
    write_manifest(exported, len(mappings))
    generated = {obj for objects in layers.values() for obj in objects}
    for obj in list(bpy.data.objects):
        if obj not in generated and obj.type not in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(obj, do_unlink=True)
    for _ in range(3):
        bpy.ops.outliner.orphans_purge(do_recursive=True)
    keep_collections = {f"ZT_{layer.title()}" for layer in layers}
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
    print(f"[zhiteng] built {len(exported)} layers and {len(mappings)} body regions")


if __name__ == "__main__":
    main()
