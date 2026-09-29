"""Render a temporary preview with the source's genital surface patches hidden."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import bpy


ROOT = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
skin = bpy.data.collections["ZT_Skin"]
objects = [obj for obj in skin.all_objects if obj.type == "MESH"]
for obj in objects:
    if obj.get("zt_neutralized") or "anal_region" in str(obj.get("bodyPartId", "")):
        skin.objects.unlink(obj)

module_path = ROOT / "scripts" / "build_from_zanatomy.py"
spec = importlib.util.spec_from_file_location("zhiteng_build", module_path)
build = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(build)
build.RENDER_DIR = Path("/private/tmp/zhiteng-no-sensitive")
build.RENDER_DIR.mkdir(parents=True, exist_ok=True)
build.render_views([obj for obj in objects if obj.name in skin.objects])
