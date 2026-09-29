# 人体模型署名与许可

## 当前正式上游

- **Z-Anatomy — The libre 3D atlas of anatomy**  
  https://www.z-anatomy.com/  
  https://github.com/Z-Anatomy/Models-of-human-anatomy  
  License: Creative Commons Attribution-ShareAlike 4.0 International.
- **BodyParts3D — The Database Center for Life Science (DBCLS)**  
  https://dbarchive.biosciencedbc.jp/data/bodyparts3d/  
  Original model data credited by Z-Anatomy under CC BY-SA.

知疼对上述模型进行了移动端减面、中性材质、分层导出、固定正交视图和区域 ID 映射。当前皮肤层还排除了泌尿生殖区与肛周源表面，重建了连续、平整的骨盆外壳，并移除了乳头等性别特征。2D 与 3D 使用同一重建外壳。
本项目分发的派生 GLB 与 2D 渲染资产继续按 **CC BY-SA 4.0** 共享。

## 正式资产选型（已确定）

正式 `export/*.glb` 统一以下列数据为上游，由项目在 Blender 中筛选、减面、分层、合并并导出 App / Mini 两档 LOD：

1. **BodyParts3D** — The Database Center for Life Science — CC BY-SA 2.1 Japan。
2. **Z-Anatomy** — The libre 3D atlas of anatomy — 主体内容 CC BY-SA 4.0。

参考工程不自动成为资产授权来源：

- `hpfrei/body-anatomy-3d-viewer`：可参考 Z-Anatomy 简化、结构元数据与 Web 加载。
- `yamz8/human-body-simulator`：可参考分层、透明度和本地解码。
- `DrMuratAltun/anatomi-simulatoru`：可参考 Blender 导出、合批和结构 ID。

引用上述工程代码时，必须另行遵守它们的代码许可；不得用代码的 MIT 许可覆盖模型的 CC BY-SA 许可。

## 商业使用白名单

Z-Anatomy 完整集中存在少量单独的非商业或需额外核验组件，包括某些内耳、肾脏等第三方资产。正式模型必须采用「白名单导出」：

- 默认仅导出已核对来源和可商用条款的皮肤、浅表肌肉、骨骼与必要器官。
- 条款冲突、来源不明或含 NC（NonCommercial）限制的结构不进入商业包。
- 必须展示该结构时，换用条款可接受的 BodyParts3D 对应资产，并单独记录来源。

当前 `build_from_zanatomy.py` 明确排除了 Z-Anatomy 内含 NC 限制的 kidney / renal、inner ear 及 Brainder / white-matter reference structures。`build_major_organs.py` 用 BodyParts3D 4.0 的 FMA7204 / FMA7205 取代了不可商用的肾脏来源，并用 FMA15571 / FMA15572 补齐左右输尿管。

正式器官层只按明确的 FMA / FJ 稳定 ID 与 Z-Anatomy 精确对象名导出，不再用名称包含关系。导出物包含心脏、左右肺、气管、食管、肝、胆、胃、胰、脾、小肠、大肠、左右肾、左右输尿管和膀胱。不包含外生殖器，也不包含子宫、卵巢、输卵管、前列腺、精囊、睾丸等体内生殖系统结构。构建脚本会对最终 GLB 再做一次敏感结构审计。

## 派生资产要求

由 BodyParts3D / Z-Anatomy 改制的 GLB 需按适用的 CC BY-SA 条款处理：

- 保留上游作者、数据库、许可名称和许可链接。
- 记录删除、减面、合并、材质修改、坐标转换和压缩方式。
- 对外分发改制模型时，按相同方式共享派生模型资产。
- 不要求与模型无关的原创业务代码自动使用模型许可，但必须保持代码与模型资产的许可边界清晰。

每换一版模型，更新：

- `export/manifest.json` → `bodyModelVersion`、`license`、`attribution`
- 本版资产白名单、上游版本/提交号、导出脚本版本和文件哈希
- App / 小程序内的 `ATTRIBUTION.md`
- 用户可见的「关于 / 开源致谢」（若许可要求）
