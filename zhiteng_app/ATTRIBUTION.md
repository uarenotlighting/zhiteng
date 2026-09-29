# Attribution

## 人体模型

App 内的 2D 和 3D 人体资产由同一份 Blender 母版生成，构建脚本、许可筛选与完整说明见 `../zhiteng_body3d/ATTRIBUTION.md`。

- Source: Z-Anatomy / BodyParts3D (DBCLS)
- License: CC BY-SA 4.0 / CC BY-SA 2.1 Japan
- Derivative: 知疼无性别临床人体定位模型 `zhiteng_zanatomy_neutral_20260922_v24`
- Changes: 分层筛选、减面、排除泌尿生殖区与肛周源表面、重建平整骨盆外壳、移除性别化胸部细节、临床中性材质、离线 GLB 导出、同源 2D 正交图与掩码、按稳定 ID 补齐主要器官。BodyParts3D 肾脏取代了 Z-Anatomy 中另行限制的肾脏资产，正式包不包含任何生殖系统结构。

App 本地包含 `skin` / `muscle` / `bone` / `organ` 四层 GLB，以及正面、背面、左侧、右侧四组 2D 图和点选掩码；运行时不依赖外部模型 CDN。

## 3D 运行库

- Three.js and example loaders/controls: MIT License
- Google Draco decoder: Apache License 2.0

上述文件以本地 App 资产形式打包，用于离线加载 GLB。

“疼痛坐标”仅作交互参考，未使用其未开源资产。
