# 器官层端到端验收

- 日期：2026-09-24
- 设备：iPhone 17 Simulator，iOS 26.4
- 模型版本：`zhiteng_zanatomy_neutral_20260922_v24`
- 构建：`flutter build ios --simulator` 通过

验收路径：首页 → 记一次疼痛 → 3D 精细 → 器官 → 泌尿。

已在真实 WebView + GLB 渲染链路中确认：

1. 器官层在点击“器官”后才载入。
2. “泌尿”快捷项会聚焦模型，并把记录页自动滚回人体舞台。
3. 左右肾、左右输尿管和膀胱完整可见，其他器官降低透明度作为位置参照。
4. 器官使用低饱和临床配色，皮肤层在器官模式下进一步变淡。

验收截图：`organ-layer-e2e-urinary.png`

SHA-256：`b07d7f382ac11d12bcdc47efeccd9c54be2f2647ca10c2ae74b6a748bda96dda`

重复截图命令：

```bash
xcrun simctl io 51FB85A6-2374-4CD3-8215-C6EFFDCF4C7F screenshot \
  artifacts/organ-layer-e2e-urinary.png
```
