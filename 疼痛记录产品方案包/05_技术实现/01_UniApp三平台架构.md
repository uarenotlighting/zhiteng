# UniApp 三平台架构

## 结论

UniApp 可以作为微信、抖音和小红书普通小程序的主体代码方案，小红书普通小程序使用 `mp-xhs` 编译目标。小红书“小组件”是另一种邀请制、单页、2MB 的轻量形态，当前明确不开发，也不作为普通小程序的替代载体。

## 推荐目录

```text
src/
  core/
    models/
    validation/
    statistics/
    body-taxonomy/
  api/
  components/
    body-map/
    pain-editor/
    timeline/
  pages/
  stores/
  platform/
    weixin.ts
    douyin.ts
    xhs.ts
  config/
```

## 可共用部分

- TypeScript 数据模型。
- API SDK。
- 身体部位定义。
- SVG/Canvas 身体图。
- 记录和校验逻辑。
- 基础统计。
- 大部分页面和组件。
- 设计 token 和文案。

## 必须分别适配

- 登录与用户身份。
- 隐私授权。
- 分享入口。
- 文件导出。
- 语音和录音权限。
- 订阅消息。
- 平台开发工具和真机表现。
- 审核文案与功能开关。

## 条件编译

```text
#ifdef MP-WEIXIN
微信能力
#endif

#ifdef MP-TOUTIAO
抖音能力
#endif

#ifdef MP-XHS
小红书能力
#endif
```

条件编译只放在平台适配层，避免业务页面充满平台判断。

## 发布流程

1. UniApp 构建目标平台代码。
2. 导入对应平台开发者工具。
3. 在 iOS 和 Android 真机验证。
4. 运行平台专项测试。
5. 使用各平台审核版配置提交。

## 小红书小组件

当前版本和既定路线均不开发小红书小组件，具体约束如下：

- 不创建独立 XHSML/CSS/JS 原生小组件工程。
- 不为小组件设计“疼痛快速记录”等缩减版功能。
- 不把个人主体无法认证普通小程序的问题转化为小组件开发需求。
- 现有 UniApp `mp-xhs`、Vue 页面和 TDesign Uniapp 组件不按小组件兼容目标建设。
- 将来如获得邀请且产品决定投入，必须作为独立项目重新评估产品价值、资质、原生技术栈、数据接入和维护成本。
