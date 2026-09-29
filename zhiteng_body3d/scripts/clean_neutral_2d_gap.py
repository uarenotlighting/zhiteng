"""Front orthographic renders already use front-face culling.

The neutral shell seals the rear thigh gap with a back-facing cap. Runtime GLB
and the 2D export both draw front faces only, so the rear wall is not projected
into the front view. Punching a rectangle out of the WebP would cut a hole into
that finished render, so this step is now a no-op kept for the old command.
"""

print("[zhiteng] front render already matches front-face-only 3D; no pixel cleanup")
