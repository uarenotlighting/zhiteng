"""
知疼 · Blender 分层导出脚本

用法：
  blender -b blender/zhiteng_body.blend -P scripts/export_layers.py

约定：按 Collection 名导出（ZT_Skin / ZT_Muscle / ZT_Bone / ZT_Organ）。
空 Collection 跳过。只导出该 Collection 内的 mesh。
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
EXPORT_DIR = ROOT / "export"
LAYERS = (
    ("ZT_Skin", "skin.glb", "skin"),
    ("ZT_Muscle", "muscle.glb", "muscle"),
    ("ZT_Bone", "bone.glb", "bone"),
    ("ZT_Organ", "organ.glb", "organ"),
)


def _collection_meshes(name: str) -> list:
    col = bpy.data.collections.get(name)
    if col is None:
        return []
    objs = []

    def walk(c):
        for obj in c.objects:
            if obj.type == "MESH":
                objs.append(obj)
        for child in c.children:
            walk(child)

    walk(col)
    return objs


def export_layer(collection_name: str, filename: str) -> bool:
    meshes = _collection_meshes(collection_name)
    if not meshes:
        print(f"[zhiteng] skip empty/missing collection: {collection_name}")
        return False

    # Deselect all, select only this layer's meshes
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    out = EXPORT_DIR / filename

    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"[zhiteng] wrote {out} ({len(meshes)} meshes)")
    return True


def write_manifest(exported: list[dict]) -> None:
    manifest_path = EXPORT_DIR / "manifest.json"
    version = f"zhiteng_blender_{datetime.now(timezone.utc).strftime('%Y%m%d')}"
    payload = {
        "bodyModelVersion": version,
        "coordinateSystemVersion": "normalized_v1",
        "pipeline": "blender",
        "status": "exported",
        "exportedAt": datetime.now(timezone.utc).isoformat(),
        "layers": exported,
        "license": "TBD",
        "attribution": "TBD — see ATTRIBUTION.md",
    }
    manifest_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"[zhiteng] manifest -> {manifest_path}")


def main() -> None:
    # Ensure Object mode
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    exported = []
    for collection_name, filename, layer_id in LAYERS:
        ok = export_layer(collection_name, filename)
        if ok:
            exported.append(
                {
                    "id": layer_id,
                    "file": filename,
                    "required": layer_id == "skin",
                    "collection": collection_name,
                }
            )
    if not exported:
        raise SystemExit(
            "[zhiteng] no collections exported. Create ZT_Skin (etc.) in the .blend file."
        )
    write_manifest(exported)


if __name__ == "__main__":
    main()
