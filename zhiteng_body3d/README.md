# 知疼人体 3D（Blender 管线）

本目录是 **App / 小程序共用的人体模型源**，与 `zhiteng_app`、`zhiteng_miniPrograme` 平级。

正式约定：**以 BodyParts3D / Z-Anatomy 中已核验可用的结构为上游，由本项目在 Blender 中改制并导出低模 GLB**。运行时用本地 Three.js 加载并 raycast，模型不依赖外部 CDN。

本项目不从零手工雕刻完整医学人体，不搬运「疼痛坐标」未开源 mesh。目标是使用同源开源人体自建资产管线，独立复现其十字准星、体内深度和皮肤遮挡交互。

## 目录

```text
zhiteng_body3d/
  README.md                 ← 本文件
  ATTRIBUTION.md            ← 上游许可与署名
  blender/                  ← .blend 源文件（可提交 LFS）
    export/                   ← 导出的 glTF/GLB（给两端拷贝或引用）
    manifest.json           ← 版本与分层清单
    skin.glb
    region.glb              ← 不可见的表面区域拾取代理
    muscle.glb              ← 可选，按需加载
    bone.glb
    organ.glb
    organ.zanatomy-base.glb  ← 已对齐的 Z-Anatomy 中间层，仅供器官重建脚本读取
    2d/
      front.webp
      back.webp
      left.webp
      right.webp
      front-mask.png
      back-mask.png
      left-mask.png
      right-mask.png
      regions.json
  scripts/
    build_from_zanatomy.py  ← 从官方 Z-Anatomy 母版构建全部产物
    preview_full_neutral_shell.py ← 构建无性别临床人体外壳
    zt_leg_stretch.py       ← 外壳腿部拉伸常量与函数（外壳与内部层共用）
    export_internal_layers.py ← 按同一拉伸导出 muscle / bone / organ，保证与外壳对齐
    build_major_organs.py ← 用明确 ID 重建完整主要器官层，补齐心脏、肾、输尿管和肠道
    bake_surface_regions.py ← 把 Z-Anatomy 区域转移到连续外壳，生成 2D 蒙版与 3D 拾取代理
    render_2d_from_viewer.py ← 用 App 的 Three.js 查看器（无头 Chrome）渲染四视图 WebP，与 3D 同材质同光
    clean_neutral_2d_gap.py ← 旧的正面腿间抠图；现导出已用单面剔除，脚本不再改像素
    decompress_glbs.py      ← 旧 Draco 产物转 App 离线 GLB
```

## 分层与命名（强制）

| Blender Collection / Object 前缀 | 导出文件 | 运行时 layer |
|---|---|---|
| `ZT_Skin` | `export/skin.glb` | `skin` / surface |
| `ZT_SurfaceRegions` | `export/region.glb` | 不可见 surface-region raycast |
| `ZT_Muscle` | `export/muscle.glb` | `muscle` |
| `ZT_Bone` | `export/bone.glb` | `bone` |
| `ZT_Organ` | `export/organ.glb` | `organ` |

要求：

1. **性别中性**、低面数；不得包含性器官、乳头或其他性别特征；首屏默认只带 `skin.glb`。
2. 原点在脚底中心或骨盆中心，全身直立，+Y 向上（与 glTF 一致）。
3. 每个可点选 mesh 有稳定 `name`（如 `head`、`left_knee`），写入记录的 `meshId`。
4. 材质用简单临床灰；半透明与剖切可在运行时改，不必在贴图里做诊断色。
5. 每次导出更新 `export/manifest.json` 的 `bodyModelVersion`；客户端保存点位时必须带上该版本。

## 同源三类产物（强制）

Blender 母版同时生成 App 3D、后续 Mini 3D 和 App/小程序共用的2D预渲染产物。各端不得换用其他人体或单独手绘简笔人体：

| 档位 | 包含层 | 预算 | 运行时要求 |
|---|---|---|---|
| App LOD | 皮肤壳、浅表肌肉、简化骨骼、按需器官 | 不设固定体积上限，优先保证模型与功能完整 | 模型、Three.js、解码器均本地打包 |
| Mini LOD（后续版） | 低模皮肤壳、浅表肌肉 | 700–900 KB | 小程序首版不发布；后续放入 `packages/locate` 分包，分包总预算不高于 1.8 MB |
| 2D Render | 正/背/左/右正交 WebP、区域蒙版、映射 JSON | 正背 100–250 KB；四视图 200–500 KB | App 与小程序共用，不运行 WebGL |

三类资产的原点、比例、朝向、站姿、坐标定义和 `bodyModelVersion` 必须一致。Mini LOD 可减面和合并网格，但必须保留与 App LOD 的区域映射。2D 必须使用版本化的固定正交相机，以便将 `view + normalizedX/Y` 反投影为3D ray。

### 版本范围

- App：正式提供2D＋3D，两种模式共享数据和坐标迁移。
- 小程序第一版：只发布2D真实人体。
- 小程序后续版：保留 Mini LOD、WebGL、深度和遮挡设计，待包体与真机性能验证后上线。首版不因此3D储备方案增加发布包体。

### 2D 预渲染规则

- 显示图使用性别中性、临床灰白材质，保留真实人体轮廓与轻微肌肉/关节结构。
- **显示图（`<view>.webp`）由 App 的 3D 查看器渲染，不再用 Blender 渲染**：`body3d.html?render2d=<view>` 用正交相机画默认层叠（玻璃皮肤 + 肌肉 + 骨），正交框幅与 Blender 蒙版相机完全一致（`ortho_scale = max(高 × 1.08, 宽 × 1.75)`，相机在视轴上穿过皮肤包围盒中心），所以 2D 与 3D 颜色、透明度、光照完全同源，且与蒙版逐像素对齐（脚本会校验轮廓 IoU ≥ 0.97）。主光挂在相机上，任何视角都不会背光。蒙版仍由 Blender 生成。
- 四视图的分辨率、相机矩阵、裁切边界和透明背景必须固定并写入 manifest。
- 左右按**解剖侧**命名：母版人体面向 −Y，`.l` 结构在 +X，所以 `left` 视图相机放在 +X（看到的是人体自己的左侧，脸朝画面左）。App 的 3D 视图切换（`body3d.html` 的 `VIEW_DIRECTIONS`）沿用同一约定，不要改成"观察者的左"。
- 蒙版为无损 PNG 或等价 ID buffer，不得使用有损压缩，避免区域边缘颜色污染。
- 蒙版、`regions.json` 和 `region.glb` 必须由同一批 mesh / structure ID 自动生成，不手工涂抹维护。2D 与 3D 因此保存同一个表面区域 ID。
- 2D 只保存主观深度 `surface / internal_unknown / unknown`；未经 App 3D 校准不生成 Z 坐标。

## 导出步骤

1. 安装 [Blender](https://www.blender.org/) 3.6+。
2. 下载官方 Z-Anatomy `Startup.blend`。
3. 命令行构建 Blender 母版、四层 GLB 和四视图 2D 资产：

```bash
blender -b /path/to/Z-Anatomy/Startup.blend \
  -P scripts/build_from_zanatomy.py -- "$PWD"
```

4. 从已构建的母版生成正式无性别皮肤外壳与同源2D四视图：

```bash
blender -b blender/zhiteng_body.blend \
  -P scripts/preview_full_neutral_shell.py -- "$PWD" --final
python3 scripts/clean_neutral_2d_gap.py
```

该步骤在内存中排除泌尿生殖区和肛周源表面，重建连续骨盆外壳，压平胸部细节并减面。脚本不保存母版；2D 和 3D 均由同一个重建外壳产生。

裆部按人偶方式闭合：在体素重建**之前**用三个椭球（耻骨垫、会阴填充、后侧填充）精确盖住被剔除的源面片留下的洞（坐标由源网格实测得出，见脚本注释），重建后再对裆部做一次局部平滑。结果是两腿在腹股沟处平滑汇合成倒 V、耻骨为平面、无性征；不要再用方块凸包或删面来处理——前者留下矩形柱，后者留下贯通到背面的洞。

外壳会把腿部从腰部起拉长并略微外展（`zt_leg_stretch.py` 中的 `LEG_PIVOT` / `LEG_SCALE` / `HIP_Z` / `FOOT_SPREAD`）。皮肤脚本用从脚底出发的连通性洪水填充识别腿（手臂垂在大腿旁，不能靠 |x| 阈值区分，否则会把大腿外侧剪出一条棱）；内部层按对象分类（`is_lower_limb_object`：髋线以下 min|x| < 0.19 为下肢）。内部层必须紧接着用同一变换重新导出，否则骨骼会比皮肤矮约 22 cm、股骨从大腿内侧穿出，红点的皮肤遮挡表达失效：

```bash
blender -b blender/zhiteng_body.blend \
  -P scripts/export_internal_layers.py -- "$PWD"
```

该脚本同样只在内存中修改，导出 `muscle.glb` / `bone.glb` / `organ.glb`，递增 `manifest.json` 的 `bodyModelVersion`，并写入 `internalLayersAlignedToSkin`。四层 GLB 的包围盒高度应一致（约 1.92 m）。

内部层对齐后，从 BodyParts3D 4.0 官方 `PART-OF` OBJ 包补齐主要器官，并重建可发布的器官层：

```bash
python3 scripts/build_major_organs.py \
  --bodyparts-root /path/to/partof_BP3D_4.0_obj_99 \
  --element-parts /path/to/partof_element_parts.txt \
  --sync-app
```

该步骤只按 FMA / FJ 稳定 ID 取数，导出心脏、左右肺、肝胆、胃肠、左右肾、左右输尿管和膀胱等 17 个可点选网格。整肝与肝段不重复，小肠/大肠交界不重复；脚本在写入后会重新读取 GLB 并执行生殖系统敏感词审计，命中即构建失败。

然后把母版中的 Z-Anatomy 人体表面区域按最近顶点转移到最终连续外壳，一次生成四视图 ID 蒙版、`regions.json` 和不可见的 `region.glb`：

```bash
blender -b blender/zhiteng_body.blend \
  -P scripts/bake_surface_regions.py -- "$PWD" --sync-app
```

`region.glb` 只用于 raycast，不渲染，不改变连续人偶的视觉效果。当前管线从 234 个合规源区域中在最终外壳上生成 230 个实际可见区域；被排除或在中性外壳上不再可见的区域不会进入运行时。

5. GLB 同步到 App 后（见第 6 步），用 App 自己的查看器重新渲染四视图显示图，保证 2D 与 3D 观感一致：

```bash
python3 scripts/render_2d_from_viewer.py --sync-app
```

需要本机有 Google Chrome 与 Pillow。脚本从 `zhiteng_app/assets` 起本地静态服务，逐视图用无头 Chrome 截 768×1280 透明 PNG，和 `export/2d/<view>-mask.png` 比对轮廓 IoU（< 0.97 直接失败，说明框幅或几何变了），再写出 `export/2d/<view>.webp`；`--sync-app` 同时复制到 `zhiteng_app/assets/models/2d/`。蒙版与 `regions.json` 仍来自第 4 步的 Blender 渲染。

6. 将 `export/*.glb`、`export/2d/` 与 `manifest.json` 同步到：

- App：`zhiteng_app/assets/models/`，同时打包2D与3D资产。
- 小程序第一版：只同步2D展示图、蒙版和映射 JSON。
- 小程序后续3D：`zhiteng_miniPrograme/packages/locate/static/models/`（必须本地化；不把模型放主包，不用远程模型作正式依赖）。

## 与「疼痛坐标」的关系

交互可参考其十字准星、表面/体内表达；**模型资产必须由我们从合规开源上游自行改制导出，交互工程独立实现**，并保留完整许可链路。不得直接搬运对方未开源的 mesh 或代码。

## 医疗边界

低模坐标只用于个人记录与沟通，**不是解剖定位诊断**。文案与界面不得宣称医学级精度。
