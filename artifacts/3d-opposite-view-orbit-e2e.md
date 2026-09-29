# 3D 对向视角圆弧过渡 E2E

- 验收日期：2026-09-24
- 设备：iPhone 17（iOS 26.4 Simulator）
- 构建方式：`flutter run -d 51FB85A6-2374-4CD3-8215-C6EFFDCF4C7F --debug`

## 验收路径

1. 进入「记一次疼痛」，切换到「3D 精细」和「全身」。
2. 单独录制「左侧 → 右侧」，按 10fps 抽帧检查动画全过程。
3. 单独录制「正面 → 背面」，按 10fps 抽帧检查动画全过程。
4. 确认两组 180° 对向切换都沿模型外侧的等距离圆弧运动，不穿过模型中心。
5. 确认正面/背面与左右侧之间的 90° 切换仍使用原有路径。
6. 连续录制「正面 ↔ 背面」和「左侧 ↔ 右侧」，按 15fps 抽帧检查模型缩放与视角 Tab 选中态。

## 结果

- 左右侧互相切换时，模型高度和屏幕占比稳定，无突然放大，通过。
- 正反面互相切换时，模型高度和屏幕占比稳定，无突然放大，通过。
- 90° 相邻视角切换未改变，通过。
- 180° 对向切换采用与 90° 切换相同的距离曲线，最近距离有界为 `sqrt(1/2)`，有明显放大再恢复效果，不会穿过模型中心，通过。
- 相机过渡期间不再向 Flutter 回传中间方位；抽帧中 Tab 始终从起点直接切到目标，无中间 Tab 闪烁，通过。

## 可复查工件

- `artifacts/3d-left-right-orbit-e2e.mov`
- `artifacts/3d-front-back-orbit-e2e.mov`
- `artifacts/3d-left-right-orbit-contact.png`
- `artifacts/3d-front-back-orbit-contact.png`
- `artifacts/3d-opposite-dolly-tab-e2e.mov`
- `artifacts/3d-opposite-dolly-contact.png`
- `artifacts/3d-opposite-tabs-contact.png`
