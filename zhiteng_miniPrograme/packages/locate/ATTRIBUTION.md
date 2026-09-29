# 3D 人体模型与引擎归属

## 引擎

- `three-platformize` 1.133.3（MIT）— DeepKolos
  - 源码镜像：`packages/locate/libs/three-platformize/`
  - 用于微信 / 抖音小程序 Canvas WebGL 渲染，未通过 npm 安装（按 AGENTS 以 vendor 方式引入）

## 人体模型

- 本地路径：`/packages/locate/static/models/human_body.glb`
- 文件位置：`packages/locate/static/models/human_body.glb`
- 中间产物来源：[hpfrei/body-anatomy-3d-viewer](https://github.com/hpfrei/body-anatomy-3d-viewer) 的 `public/body.glb`（由 Z-Anatomy 数据集简化）
- 原始解剖数据：
  - **BodyParts3D** — The Database Center for Life Science — **CC-BY-SA 2.1 Japan**
  - **Z-Anatomy** — The libre 3D atlas of anatomy — **CC-BY-SA 4.0**
- 本仓库内版本：仅保留浅表肌肉层，经 simplify + quantize（`KHR_mesh_quantization`），**无 Draco / meshopt**，便于小程序 GLTFLoader 直接加载

## 许可注意

派生作品需遵守 CC-BY-SA（署名 + 相同方式共享）。应用内或关于页应保留对 BodyParts3D / Z-Anatomy 的署名。
