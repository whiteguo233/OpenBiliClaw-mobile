# 推荐换批、库存与续页一致性

本客户端需配合 OpenBiliClaw 后端 `fix/recommendation-consistency` 分支使用完整能力。

## 数据流

```text
换批/追加 → POST recommendations/{reshuffle,append}
         ← items + pool_status（总量、来源数量、读取版本）
         → RecommendProvider 一次应用卡片和库存
后台补货 → 主 API runtime-stream → 同一库存合并入口
旧后端   → 有界 platform-availability 补读；失败保留最后成功值
```

`RecommendApi.reshuffle()` / `append()` 返回 `RecommendAppendResult`，新增可空
`poolStatus`。两条操作都在 ApiClient 内设 12 秒截止时间，覆盖响应正文并关闭请求连接，
移除外层先退出、底层仍继续 30 秒的重复 timeout。失败保留卡片并在 finally 解除忙碌状态。

`PlatformAvailability.version` 对应 `pool_status_version`。总数与来源徽标采用同一快照；
开始于换批之前的侧通道查询不能覆盖新库存，迟到 runtime-status 只更新活动等字段。
平台定向换批保留其它来源卡片，追加/换批/下拉刷新互斥，请求期间切来源不污染新来源的耗尽状态。

手动「加载更多」及下拉刷新始终可以请求后端，不会被旧的零库存 / exhausted 挡住。
失败不标记耗尽。自动续页只在用户已经发出滚动意图、当前靠近底部且操作可用时触发；
`RecommendAutoLoad` 保留五秒冷却 / 350ms 去抖，并安排到点复查；加载中到达底部、
补货通知、组件重建都会重新检查条件。一次请求结束后不会在无人操作时无条件连续吃完整池。
手指松开后的惯性滚动保留本次手势意图；离开底部后不发起计划内加载，dispose 取消定时器。

## 验证

- `flutter test`：82 项通过，含新加的旧响应乱序、零库存手动重试、失败收尾、冷却复查、补货续页测试。
- `flutter analyze`：无问题。
- 本轮未安装到实体 Android/iOS 手机；网络和设备后台恢复时延不能由单元测试代替。
- 后端的真实 SQLite 原子提交 / 独立进程库存事件桥接在后端仓库验证；没有新增第三方依赖或用户配置。
