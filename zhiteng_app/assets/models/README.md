# Body model assets

Generated from `../../zhiteng_body3d/blender/zhiteng_body.blend` through the documented Z-Anatomy pipeline.

- `skin.glb`: one continuous gender-neutral clinical surface; genital, anal,
  and sex-specific chest detail is excluded from the generated geometry
- `region.glb`: invisible decimated copy of that final shell, split into 230
  transferred Z-Anatomy surface regions for 3D raycasting
- `muscle.glb`, `bone.glb`: optional anatomical layers; each selectable mesh
  retains its Z-Anatomy source name and stable `bodyPartId`
- `organ.glb`: on-demand layer with 17 explicit Z-Anatomy / BodyParts3D
  allowlisted meshes grouped as heart, lung, hepatobiliary, digestive and
  urinary. It contains no reproductive structures.
- `2d/*.webp`: orthographic views from the same mother model
- `2d/*-mask.png` and `2d/regions.json`: lossless ID masks generated from the
  same transferred surface regions as `region.glb`. Both 2D and 3D therefore
  resolve the same stable source ID/name; the coarse Chinese label is only the
  user-facing vocabulary layered on top.
- `manifest.json`: model and coordinate-system versions

Do not hand-edit generated files. See `../ATTRIBUTION.md` and `../../zhiteng_body3d/ATTRIBUTION.md` for licensing.
