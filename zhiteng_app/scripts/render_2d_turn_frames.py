"""Render lightweight 2D turn frames from the same Three.js scene as 3D.

The runtime 3D viewer moves its camera on a straight chord between canonical
view directions. Flutter replays these orthographic direction frames using
the same eased chord parameter and applies the chord-distance scale itself.
This preserves the formal 2D mode while avoiding a four-image view snap.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

from PIL import Image

APP_ROOT = Path(__file__).resolve().parents[1]
SHARED_SCRIPTS = APP_ROOT.parent / "zhiteng_body3d" / "scripts"
sys.path.insert(0, str(SHARED_SCRIPTS))

import render_2d_from_viewer as renderer  # noqa: E402

FRAME_COUNT = 48
CAPTURE_WIDTH, CAPTURE_HEIGHT = 768, 1280
OUTPUT_WIDTH, OUTPUT_HEIGHT = 384, 640
OUTPUT = APP_ROOT / "assets" / "models" / "2d" / "turn"


def main() -> None:
    chrome = renderer.find_chrome()
    assets = APP_ROOT / "assets"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # Chrome may enforce a minimum viewport width. Capture at the exact source
    # coordinate system first, then downsample, otherwise a 384 px request can
    # crop the right side of a wider internal viewport and shift the body.
    renderer.WIDTH = CAPTURE_WIDTH
    renderer.HEIGHT = CAPTURE_HEIGHT
    server, port = renderer.serve(assets)
    try:
        with tempfile.TemporaryDirectory(prefix="zhiteng-turn2d-") as tmp:
            temp = Path(tmp)
            for index in range(FRAME_COUNT):
                angle = index * 360 / FRAME_COUNT
                png = temp / f"frame_{index:02d}.png"
                url = (
                    f"http://127.0.0.1:{port}/web/body3d.html"
                    f"?render2d=turn&render2dAngle={angle}"
                    f"&render2dLayers=skin"
                    f"&hold={renderer.HOLD_PATH}&ready={renderer.READY_PATH}"
                )
                renderer.screenshot(
                    chrome,
                    url,
                    png,
                    temp / f"profile-{index:02d}",
                )
                image = Image.open(png).convert("RGBA")
                if image.size != (CAPTURE_WIDTH, CAPTURE_HEIGHT):
                    raise SystemExit(
                        f"frame {index}: got {image.size}, "
                        f"expected {(CAPTURE_WIDTH, CAPTURE_HEIGHT)}"
                    )
                image = image.resize(
                    (OUTPUT_WIDTH, OUTPUT_HEIGHT),
                    Image.Resampling.LANCZOS,
                )
                target = OUTPUT / f"frame_{index:02d}.webp"
                image.save(target, "WEBP", quality=86, method=6)
                print(f"[zhiteng] {index + 1:02d}/{FRAME_COUNT}: {target.name}")
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
