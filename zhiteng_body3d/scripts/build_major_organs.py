"""Build the curated, non-reproductive organ layer used by the app.

The existing Z-Anatomy export has good mobile-ready whole meshes for several
organs, but its name-substring allowlist also captured lymph nodes and all
liver segments on top of the whole liver.  It is also missing the heart,
kidneys, ureters, oesophagus and most of the intestines.

This script keeps only explicitly named meshes from the existing organ GLB and
fills the missing structures from the official BodyParts3D 4.0 PART-OF OBJ
archive.  BodyParts3D objects are selected by FMA/file ID, never by a fuzzy
name search.  The output is one mesh per user-facing organ, with source and
group metadata embedded in glTF extras.

Install the build-only dependency and run from ``zhiteng_body3d``::

    python3 -m pip install trimesh
    python3 scripts/build_major_organs.py \
      --bodyparts-root /path/to/partof_BP3D_4.0_obj_99 \
      --element-parts /path/to/partof_element_parts.txt \
      --sync-app

The raw BodyParts3D archive is intentionally not vendored.  Download it from:
https://dbarchive.biosciencedbc.jp/en/bodyparts3d/download.html
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import trimesh


ROOT = Path(__file__).resolve().parents[1]
EXPORT_DIR = ROOT / "export"
APP_MODELS = ROOT.parent / "zhiteng_app" / "assets" / "models"
BASE_ORGAN_PATH = EXPORT_DIR / "organ.zanatomy-base.glb"

# Least-squares fit from seven structures present in both the current
# Z-Anatomy mobile export and BodyParts3D (stomach, spleen, pancreas,
# gallbladder, duodenum, trachea and bladder).  Source OBJ axes are
# X=left/right, Y=front/back, Z=height in millimetres; app glTF is Y-up metres.
BODY_PARTS_TO_APP = np.array(
    [
        [0.000999781647, 0.0, 0.0, 0.000449869508],
        [0.0, 0.0, 0.0010877718, 0.18287272],
        [0.0, -0.00093385659, 0.0, -0.09011054],
        [0.0, 0.0, 0.0, 1.0],
    ]
)

SENSITIVE_TOKENS = (
    "genital",
    "reproductive",
    "uterus",
    "uterine",
    "ovary",
    "ovarian",
    "fallopian",
    "vagina",
    "vulva",
    "clitoris",
    "prostate",
    "seminal",
    "vas deferens",
    "ductus deferens",
    "testis",
    "testicle",
    "epididym",
    "penis",
    "scrot",
    "gonad",
)

GROUP_COLORS = {
    "heart": "#C98585",
    "lung": "#C7A8A5",
    "hepatobiliary": "#B9A477",
    "digestive": "#C8AA86",
    "urinary": "#9FAFC0",
}


@dataclass(frozen=True)
class Organ:
    organ_id: str
    name_zh: str
    group_id: str
    source: str
    current_names: tuple[str, ...] = ()
    file_ids: tuple[str, ...] = ()
    concept_id: str | None = None


ORGANS = (
    Organ(
        "heart",
        "心脏",
        "heart",
        "BodyParts3D",
        # Four chambers plus the short ascending aorta, aortic arch and
        # pulmonary trunk make a recognisable but still lightweight heart.
        file_ids=("FJ2422", "FJ2423", "FJ2438", "FJ2439", "FJ3413", "FJ3411", "FJ2966"),
        concept_id="FMA7088",
    ),
    Organ(
        "right_lung",
        "右肺",
        "lung",
        "Z-Anatomy",
        current_names=(
            "Superior lobe of right lung",
            "Middle lobe of right lung",
            "Inferior lobe of right lung",
        ),
        concept_id="FMA7309",
    ),
    Organ(
        "left_lung",
        "左肺",
        "lung",
        "Z-Anatomy",
        current_names=("Superior lobe of left lung", "Inferior lobe of left lung"),
        concept_id="FMA7310",
    ),
    Organ("trachea", "气管", "lung", "Z-Anatomy", current_names=("Trachea",), concept_id="FMA7394"),
    Organ("esophagus", "食管", "digestive", "BodyParts3D", file_ids=("FJ2563",), concept_id="FMA7131"),
    Organ("liver", "肝脏", "hepatobiliary", "Z-Anatomy", current_names=("Liver",), concept_id="FMA7197"),
    Organ("gallbladder", "胆囊", "hepatobiliary", "Z-Anatomy", current_names=("Gallbladder",), concept_id="FMA7202"),
    Organ("stomach", "胃", "digestive", "Z-Anatomy", current_names=("Stomach",), concept_id="FMA7148"),
    Organ("pancreas", "胰腺", "digestive", "Z-Anatomy", current_names=("Pancreas",), concept_id="FMA7198"),
    Organ("spleen", "脾脏", "digestive", "Z-Anatomy", current_names=("Spleen",), concept_id="FMA7196"),
    Organ("small_intestine", "小肠", "digestive", "BodyParts3D", concept_id="FMA7200"),
    Organ("large_intestine", "大肠", "digestive", "BodyParts3D", concept_id="FMA7201"),
    Organ("right_kidney", "右肾", "urinary", "BodyParts3D", file_ids=("FJ3147",), concept_id="FMA7204"),
    Organ("left_kidney", "左肾", "urinary", "BodyParts3D", file_ids=("FJ3145",), concept_id="FMA7205"),
    Organ("right_ureter", "右输尿管", "urinary", "BodyParts3D", file_ids=("FJ3146",), concept_id="FMA15571"),
    Organ("left_ureter", "左输尿管", "urinary", "BodyParts3D", file_ids=("FJ3144",), concept_id="FMA15572"),
    Organ("urinary_bladder", "膀胱", "urinary", "Z-Anatomy", current_names=("Urinary bladder",), concept_id="FMA15900"),
)


def canonical_node_name(value: str) -> str:
    return re.sub(r"\.\d{3}$", "", value).strip()


def read_element_parts(path: Path) -> dict[str, list[str]]:
    concepts: dict[str, list[str]] = {}
    with path.open(encoding="utf-8") as source:
        next(source)
        for raw in source:
            concept_id, _name, file_id = raw.rstrip("\n").split("\t")
            concepts.setdefault(concept_id, []).append(file_id)
    return concepts


def world_meshes(scene: trimesh.Scene) -> dict[str, trimesh.Trimesh]:
    meshes: dict[str, trimesh.Trimesh] = {}
    for node_name in scene.graph.nodes_geometry:
        transform, geometry_name = scene.graph[node_name]
        mesh = scene.geometry[geometry_name].copy()
        mesh.apply_transform(transform)
        meshes[canonical_node_name(node_name)] = mesh
    return meshes


def combine(meshes: list[trimesh.Trimesh]) -> trimesh.Trimesh:
    if not meshes:
        raise RuntimeError("Cannot build an organ from zero meshes")
    result = trimesh.util.concatenate(meshes)
    result.remove_unreferenced_vertices()
    # Trimesh only writes NORMAL accessors when vertex normals are already in
    # its cache. MeshStandardMaterial otherwise renders the mobile GLB black.
    _ = result.vertex_normals
    return result


def from_current(organ: Organ, current: dict[str, trimesh.Trimesh]) -> trimesh.Trimesh:
    missing = [name for name in organ.current_names if name not in current]
    if missing:
        raise RuntimeError(f"Missing current meshes for {organ.organ_id}: {missing}")
    return combine([current[name].copy() for name in organ.current_names])


def obj_english_name(path: Path) -> str:
    with path.open(encoding="utf-8", errors="replace") as source:
        for line in source:
            if line.startswith("# English name :"):
                return line.split(":", 1)[1].strip()
            if line.startswith("v "):
                break
    return path.stem


def from_bodyparts(
    organ: Organ,
    bodyparts_root: Path,
    element_parts: dict[str, list[str]],
) -> tuple[trimesh.Trimesh, tuple[str, ...]]:
    file_ids = list(organ.file_ids)
    if not file_ids and organ.concept_id:
        file_ids = sorted(set(element_parts.get(organ.concept_id, ())))
    # FJ2599 (ileocecal junction) belongs to both compound definitions.  Keep
    # it with the large intestine so the exported geometry appears once.
    if organ.organ_id == "small_intestine":
        file_ids = [file_id for file_id in file_ids if file_id != "FJ2599"]
    if not file_ids:
        raise RuntimeError(f"No BodyParts3D files resolved for {organ.organ_id}")

    meshes = []
    names = []
    for file_id in file_ids:
        path = bodyparts_root / f"{file_id}.obj"
        if not path.exists():
            raise FileNotFoundError(path)
        name = obj_english_name(path)
        lowered = name.lower()
        if any(token in lowered for token in SENSITIVE_TOKENS):
            raise RuntimeError(f"Sensitive structure entered allowlist: {file_id} {name}")
        mesh = trimesh.load(path, force="mesh", process=False)
        mesh.apply_transform(BODY_PARTS_TO_APP)
        meshes.append(mesh)
        names.append(name)
    return combine(meshes), tuple(file_ids)


def color_rgba(hex_color: str) -> list[int]:
    value = hex_color.removeprefix("#")
    return [int(value[i : i + 2], 16) for i in (0, 2, 4)] + [255]


def bump(version: str) -> str:
    match = re.search(r"_v(\d+)$", version)
    if not match:
        return f"{version}_v2"
    return f"{version[:match.start()]}_v{int(match.group(1)) + 1}"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bodyparts-root", type=Path, required=True)
    parser.add_argument("--element-parts", type=Path, required=True)
    parser.add_argument(
        "--base-organ",
        type=Path,
        default=BASE_ORGAN_PATH,
        help="aligned Z-Anatomy base organ GLB (kept separate for repeatable builds)",
    )
    parser.add_argument("--sync-app", action="store_true")
    args = parser.parse_args()

    current_scene = trimesh.load(args.base_organ, force="scene", process=False)
    current = world_meshes(current_scene)
    element_parts = read_element_parts(args.element_parts)
    output = trimesh.Scene(
        metadata={
            "layer": "organ",
            "source": "Z-Anatomy + BodyParts3D 4.0 curated allowlist",
            "excludesReproductiveSystem": True,
        }
    )
    catalog = []

    for organ in ORGANS:
        if organ.source == "Z-Anatomy":
            mesh = from_current(organ, current)
            source_file_ids: tuple[str, ...] = ()
        else:
            mesh, source_file_ids = from_bodyparts(
                organ, args.bodyparts_root, element_parts
            )

        lowered_audit = " ".join(
            (organ.organ_id, organ.name_zh, organ.group_id, *organ.current_names)
        ).lower()
        if any(token in lowered_audit for token in SENSITIVE_TOKENS):
            raise RuntimeError(f"Sensitive output name: {organ.organ_id}")

        rgba = color_rgba(GROUP_COLORS[organ.group_id])
        material = trimesh.visual.material.PBRMaterial(
            name=f"ZT_{organ.group_id}",
            baseColorFactor=rgba,
            metallicFactor=0.0,
            roughnessFactor=0.84,
        )
        mesh.visual = trimesh.visual.TextureVisuals(material=material)
        mesh.metadata.update(
            {
                "name": organ.organ_id,
                "zt_layer": "organ",
                "bodyPartId": organ.organ_id,
                "organId": organ.organ_id,
                "organGroupId": organ.group_id,
                "displayNameZh": organ.name_zh,
                "sourceDataset": organ.source,
                "sourceConceptId": organ.concept_id,
                "sourceFileIds": list(source_file_ids),
            }
        )
        output.add_geometry(mesh, node_name=organ.organ_id, geom_name=organ.organ_id)
        catalog.append(
            {
                "id": organ.organ_id,
                "nameZh": organ.name_zh,
                "groupId": organ.group_id,
                "source": organ.source,
                "sourceConceptId": organ.concept_id,
                "sourceFileIds": list(source_file_ids),
                "vertices": int(len(mesh.vertices)),
                "triangles": int(len(mesh.faces)),
            }
        )
        print(
            f"[zhiteng] {organ.organ_id}: {len(mesh.vertices)} vertices, "
            f"{len(mesh.faces)} triangles ({organ.source})"
        )

    target = EXPORT_DIR / "organ.glb"
    # Trimesh's GLB exporter includes scene/mesh metadata by default.
    target.write_bytes(output.export(file_type="glb"))

    # Re-open the generated GLB and audit what will actually ship, not only the
    # Python catalog.  This turns accidental reproductive structures into a
    # build failure rather than a UI visibility choice.
    shipped = trimesh.load(target, force="scene", process=False)
    shipped_text = json.dumps(
        {
            "nodes": list(shipped.graph.nodes_geometry),
            "metadata": [mesh.metadata for mesh in shipped.geometry.values()],
        },
        ensure_ascii=False,
    ).lower()
    offending = [token for token in SENSITIVE_TOKENS if token in shipped_text]
    if offending:
        raise RuntimeError(f"Sensitive terms found in exported GLB: {offending}")
    if len(shipped.geometry) != len(ORGANS):
        raise RuntimeError(
            f"Expected {len(ORGANS)} organ meshes, exported {len(shipped.geometry)}"
        )

    manifest_path = EXPORT_DIR / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["bodyModelVersion"] = bump(manifest["bodyModelVersion"])
    manifest["exportedAt"] = datetime.now(timezone.utc).isoformat()
    manifest["pipeline"] = "official-z-anatomy-plus-bodyparts3d"
    manifest["excludedForLicense"] = [
        "Z-Anatomy bundled kidney (replaced by BodyParts3D FMA7204/FMA7205)",
        "inner ear",
        "Brainder / white-matter reference structures",
    ]
    manifest["organLayer"] = {
        "strategy": "explicit-stable-id-allowlist",
        "meshCount": len(ORGANS),
        "groups": ["heart", "lung", "hepatobiliary", "digestive", "urinary"],
        "excludesReproductiveSystem": True,
        "sensitiveNameAudit": "passed",
        "bodyParts3dVersion": "4.0",
        "bodyParts3dTree": "PART-OF, polygon reduction rate 99%",
        "bodyPartsToAppTransform": BODY_PARTS_TO_APP.tolist(),
        "catalog": catalog,
    }
    for layer in manifest["layers"]:
        if layer["id"] == "organ":
            layer.update(
                {
                    "meshCount": len(ORGANS),
                    "bytes": target.stat().st_size,
                    "compression": "none",
                    "sha256": sha256(target),
                    "sourceCollection": "explicit-major-organ-allowlist",
                }
            )
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    # 2D geometry did not change, but records use one body-model version for
    # both modes.  Keep the mapping declaration in lockstep with the manifest.
    regions_path = EXPORT_DIR / "2d" / "regions.json"
    if regions_path.exists():
        regions = json.loads(regions_path.read_text(encoding="utf-8"))
        regions["bodyModelVersion"] = manifest["bodyModelVersion"]
        regions_path.write_text(
            json.dumps(regions, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    if args.sync_app:
        APP_MODELS.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, APP_MODELS / target.name)
        shutil.copy2(manifest_path, APP_MODELS / manifest_path.name)
        if regions_path.exists():
            (APP_MODELS / "2d").mkdir(parents=True, exist_ok=True)
            shutil.copy2(regions_path, APP_MODELS / "2d" / regions_path.name)

    print(
        f"[zhiteng] exported {target}: {len(ORGANS)} meshes, "
        f"{target.stat().st_size} bytes, version {manifest['bodyModelVersion']}"
    )


if __name__ == "__main__":
    main()
