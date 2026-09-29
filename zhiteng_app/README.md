# 知疼 App（Flutter）

与 `zhiteng_miniPrograme`、`zhiteng_server` 平级的 iOS / Android 工程。

## 技术选型（文档约定）

| 能力 | 方案 |
|---|---|
| 跨端 UI | Flutter |
| 本地存储 | SQLite（`sqflite`） |
| 3D | Blender 导出低模 GLB + Three.js raycasting；共享目录 `zhiteng_body3d` |
| 状态 | `provider` |
| 主题 | 品牌 Token（Cursor 聊天浅色 / 暗色中性灰，无微信绿） |

交互参考抖音创作者「西陆1004」[疼痛坐标](https://www.douyin.com/user/MS4wLjABAAAAQK4rcSdxmaxumxdjzvrNwZhy2vyym5rS9yTlwwP0vWtQjZ_55mjmCAv5bUX2GXNx) 前三支产品演示：大面积人体舞台、点选定位、全身分区、导出给医生沟通；公开回复中提到 GPT 协同与 Blender 建模。

## 运行

```bash
cd zhiteng_app
flutter pub get
flutter run
```

3D 人体、Three.js 和解码器均从本地 assets 加载；记录页可切换同源 2D / 3D 模式。

2D / 3D 均提供“头部（头、颈、肩）”“上身（上肢、手、上身）”“下身（下肢、脚）”
三个局部视图，并保留“全身”总览。两个模式各自记住所选区域；切换区域只改变取景，
不移动已标记的位置。新旧记录的 `head` / `lower` / `full` 字段保持兼容，新增 `upper`。

## 验证

```bash
flutter analyze
flutter test
node --test test/body3d_depth.test.cjs
```

3D 回归测试直接加载 App 内的 Three.js、人体 GLB 和定位代码，验证连续深度移动、
四个观察方向、皮肤内壁过滤、肢体间空隙边界、点线同步与默认线宽，无需安装 npm 依赖。
深度沿选点时的射线调整，旋转不改变深入方向；“侧看深度”可观察体表入口到痛点的虚线。
回归还覆盖侧视下的实际屏幕位移，以及 6–24 cm 范围的连续深度反馈。
区域取景回归逐个投影实际人体顶点，检查四视图中肩、手、脚不被裁切；部位名称使用
完整人体坐标推断，不随局部缩放改变（名称仅表示大致位置）。

## 目录

```text
lib/
  core/          主题与 PainEntry 模型
  data/          SQLite 仓储
  state/         设置与记录控制器
  features/      首页 / 记录 / 历史 / 趋势 / 我的 / 引导
  widgets/       通用按钮与 Chip
assets/web/      Three.js 人体定位页
```

## 下一步（按产品文档顺序）

1. 统一账号与小程序数据迁移
2. 日历热力与更完整趋势
3. 批量就医 PDF / 用药提醒
4. 本地打包低模分层 GLB（表面 / 肌肉 / 骨骼）
5. Apple Watch 快捷记录

开发约束见 `AGENTS.md`。
