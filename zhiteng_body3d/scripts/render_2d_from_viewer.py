"""Render the 2D body maps from the app's own Three.js viewer.

The 2D maps used to be Blender EEVEE renders with a flat grey material and a
world-fixed lamp, so they never matched the 3D stage (glass skin over muscle
and bone, camera-relative key light) and the back view was lit from behind.
This script opens ``assets/web/body3d.html?render2d=<view>`` in headless
Chrome: the page draws the default layer stack through an orthographic camera
framed exactly like ``build_from_zanatomy.render_views`` (same ortho scale,
same axis through the skin bounds centre), so the result has the 3D look and
still lines up with the Blender region masks (``<view>-mask.png``), which stay
the source of truth for hit-testing.

Usage (from zhiteng_body3d/):

    python3 scripts/render_2d_from_viewer.py            # writes export/2d/<view>.webp
    python3 scripts/render_2d_from_viewer.py --sync-app # also copies into zhiteng_app/assets/models/2d

Requires Google Chrome and Pillow. The GLBs are read from the app assets
folder (``zhiteng_app/assets/models``), i.e. whatever the app currently ships.
"""

from __future__ import annotations

import argparse
import functools
import http.server
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
APP_ASSETS = ROOT.parent / "zhiteng_app" / "assets"
EXPORT_2D = ROOT / "export" / "2d"
VIEWS = ("front", "back", "left", "right")
WIDTH, HEIGHT = 768, 1280
CHROME_CANDIDATES = (
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "google-chrome",
    "chromium",
)


def find_chrome() -> str:
    for candidate in CHROME_CANDIDATES:
        if Path(candidate).exists() or shutil.which(candidate):
            return candidate
    raise SystemExit("Google Chrome / Chromium not found; install it or edit CHROME_CANDIDATES")


HOLD_PATH = "/__zhiteng_hold"
READY_PATH = "/__zhiteng_ready"
# 1x1 transparent GIF returned once the page is ready, releasing its load event.
PIXEL_GIF = (
    b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,"
    b"\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;"
)


class ExportHandler(http.server.SimpleHTTPRequestHandler):
    """Static assets plus the load-event handshake.

    Headless Chrome takes its screenshot when the window load event fires,
    which is before the GLBs have been fetched and drawn. The page requests
    ``HOLD_PATH`` as an image before load; we answer it only after the page
    has hit ``READY_PATH`` from its first finished frame.
    """

    ready = threading.Event()

    def log_message(self, *_args) -> None:  # noqa: D401 - silence per-request logs
        pass

    def do_GET(self) -> None:  # noqa: N802 - http.server API
        path = self.path.split("?", 1)[0]
        if path == READY_PATH:
            ExportHandler.ready.set()
            self.send_response(204)
            self.end_headers()
            return
        if path == HOLD_PATH:
            ExportHandler.ready.wait(timeout=120)
            self.send_response(200)
            self.send_header("Content-Type", "image/gif")
            self.send_header("Content-Length", str(len(PIXEL_GIF)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(PIXEL_GIF)
            return
        super().do_GET()


def serve(directory: Path) -> tuple[http.server.ThreadingHTTPServer, int]:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    handler = functools.partial(ExportHandler, directory=str(directory))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, port


def screenshot(chrome: str, url: str, out: Path, profile: Path) -> None:
    ExportHandler.ready.clear()
    command = [
        chrome,
        "--headless=new",
        "--hide-scrollbars",
        "--no-first-run",
        "--disable-extensions",
        f"--user-data-dir={profile}",
        f"--window-size={WIDTH},{HEIGHT}",
        "--force-device-scale-factor=1",
        # Transparent page background so the WebP keeps its alpha.
        "--default-background-color=00000000",
        # Upper bound; normally the hold/ready handshake releases load earlier.
        "--timeout=60000",
        f"--screenshot={out}",
        url,
    ]
    # Headless Chrome reliably writes the screenshot but does not always exit
    # while the page keeps a requestAnimationFrame loop running, so wait for
    # the file rather than for the process.
    process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline:
            if out.exists() and out.stat().st_size > 0:
                time.sleep(1.0)  # let the write finish
                break
            if process.poll() is not None and not out.exists():
                raise SystemExit(f"Chrome exited without a screenshot for {url}")
            time.sleep(0.5)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
    if not out.exists():
        raise SystemExit(f"Chrome produced no screenshot for {url}")


def silhouette_iou(rendered: Image.Image, mask_path: Path) -> float:
    """Overlap between the rendered alpha and the Blender mask alpha."""
    mask = Image.open(mask_path).convert("RGBA")
    if mask.size != rendered.size:
        raise SystemExit(f"{mask_path.name} is {mask.size}, render is {rendered.size}")
    render_alpha = rendered.getchannel("A").point(lambda a: 255 if a > 24 else 0)
    mask_alpha = mask.getchannel("A").point(lambda a: 255 if a > 24 else 0)
    inter = ImageChops.multiply(render_alpha, mask_alpha).histogram()[255]
    union = ImageChops.lighter(render_alpha, mask_alpha).histogram()[255]
    return inter / union if union else 0.0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--assets", type=Path, default=APP_ASSETS, help="app assets dir (web/ + models/)")
    parser.add_argument("--out", type=Path, default=EXPORT_2D, help="where <view>.webp is written")
    parser.add_argument("--views", nargs="+", default=list(VIEWS), choices=VIEWS)
    parser.add_argument("--quality", type=int, default=92)
    parser.add_argument(
        "--layers",
        default="",
        help="comma-separated model layers passed to render2dLayers (for example skin,bone)",
    )
    parser.add_argument("--min-iou", type=float, default=0.97, help="required silhouette overlap with the mask")
    parser.add_argument("--sync-app", action="store_true", help="also copy the WebPs into the app assets")
    args = parser.parse_args()

    chrome = find_chrome()
    if not (args.assets / "web" / "body3d.html").exists():
        raise SystemExit(f"{args.assets} does not contain web/body3d.html")
    args.out.mkdir(parents=True, exist_ok=True)
    server, port = serve(args.assets)
    try:
        with tempfile.TemporaryDirectory(prefix="zhiteng-render2d-") as tmp:
            tmp_path = Path(tmp)
            for view in args.views:
                png = tmp_path / f"{view}.png"
                url = (
                    f"http://127.0.0.1:{port}/web/body3d.html?render2d={view}"
                    f"&hold={HOLD_PATH}&ready={READY_PATH}"
                )
                if args.layers:
                    url += f"&render2dLayers={urllib.parse.quote(args.layers)}"
                screenshot(chrome, url, png, tmp_path / f"profile-{view}")
                image = Image.open(png).convert("RGBA")
                if image.size != (WIDTH, HEIGHT):
                    raise SystemExit(f"{view}: screenshot is {image.size}, expected {(WIDTH, HEIGHT)}")
                coverage = image.getchannel("A").histogram()
                if sum(coverage[25:]) < 0.02 * WIDTH * HEIGHT:
                    raise SystemExit(f"{view}: render is (almost) empty; did the GLBs load?")
                mask_path = args.out / f"{view}-mask.png"
                if mask_path.exists():
                    iou = silhouette_iou(image, mask_path)
                    status = "ok" if iou >= args.min_iou else "MISALIGNED"
                    print(f"[zhiteng] {view}: silhouette IoU vs mask {iou:.4f} {status}")
                    if iou < args.min_iou:
                        raise SystemExit(f"{view}: render does not line up with {mask_path.name}")
                else:
                    print(f"[zhiteng] {view}: no mask at {mask_path}, skipping alignment check")
                target = args.out / f"{view}.webp"
                image.save(target, "WEBP", quality=args.quality, method=6)
                print(f"[zhiteng] wrote {target} ({target.stat().st_size // 1024} KB)")
                if args.sync_app:
                    app_target = args.assets / "models" / "2d" / target.name
                    shutil.copyfile(target, app_target)
                    print(f"[zhiteng] synced {app_target}")
    finally:
        server.shutdown()


if __name__ == "__main__":
    sys.exit(main())
