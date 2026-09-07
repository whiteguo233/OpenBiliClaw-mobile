# 推荐换批、库存与续页一致性

完整库存能力需要 OpenBiliClaw 后端 main `ac942817` 或后续版本（换批响应包含 `pool_status`）。

## 数据流

```text
换批/追加 → POST recommendations/{reshuffle,append}
         ← items + pool_status（总量、来源数量、读取版本）
         → RecommendProvider 一次应用卡片和库存
后台补货 → 主 API runtime-stream → 同一库存合并入口
旧后端   → 立即有界补读 platform-availability，再一并发布卡片与库存
补读失败 → 卡片保持可用，所有库存徽标标为「待同步」，后续有效快照恢复
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

## 真实请求验收（2026-09-07）

新增 `integration_test/recommendation_consistency_live_test.dart`：挂载生产
RecommendView、真实 providers 和 ApiClient，使用真实 HTTP/WebSocket，验证两次点击换批、
实际 fling 触发追加、真实 ID、无重复及总量/来源图一致。不改已保存的连接设置，不发反馈或聊天。

iOS 26.5 的 iPhone 17 Pro 模拟器两轮通过；最终后端版本下 UI 换批完成约 5.67 / 2.64 秒，
fling 至卡片 10→20 约 8.45 秒（含滚动及 debug 渲染，不等于接口延迟）。
第二轮 Flutter 提示预期输出路径不存在，但同版本模拟器 App 实际启动并完成全部断言；
本轮没有更改已提交的原生业务代码。实体 iOS 18.5 设备已完成签名编译，但无线 Dart VM
服务未连接，不能记为通过；需要解锁、允许本地网络或 USB 连接后补验。

```bash
flutter test integration_test/recommendation_consistency_live_test.dart \
  -d <模拟器ID> --no-uninstall
flutter drive --driver=test_driver/recommendation_live.dart \
  --target=integration_test/recommendation_consistency_live_test.dart \
  -d <实体设备ID> --publish-port \
  --dart-define=LIVE_BACKEND_HOST=<电脑局域网地址>
```

以上会真实消耗推荐库存。结束后应安装正常 `lib/main.dart` 入口的 App，避免保留测试入口。
完整后端计时、真实环境发现的活动动态主线程阻塞与事务重复计算补修，记录在后端仓库
`docs/verification/2026-09-07-recommendation-live.md`。

现场收尾：实体 iPhone 已成功安装以 `lib/main.dart` 为入口的正常 Release 包，替换临时测试入口并保留应用数据。安装成功仍不代表实体 UI 自动化通过。

## 2026-09-08：首帧库存一致性

换批、追加和下拉刷新均先准备同批库存，再同步修改卡片与库存，最后一次通知页面。顶部「当前可换」、Tab「全部」与各平台数字共用 `PlatformAvailability`；后台 runtime-status 不能覆盖这组数字。请求开始时更新读请求代次，屏蔽开始于该操作之前的库存查询。

新后端响应直接携带库存，客户端不会为了更新徽标额外 GET，也不等待轮询或 WebSocket。旧响应缺少库存时，立即发起独立补读，绕过正在等待的旧库存查询，最多等待既有 8 秒读取截止时间；卡片与数字随后一起发布。这是兼容路径，不能承诺旧后端与新后端有相同延迟。补读失败时展示新卡片，但将所有旧库存数字标为「待同步」，直到有效快照到达；缺字段的响应不会被解释成库存为零。

页面测试在 runtime-status 一直未返回的条件下，实际点击「换一批」，验证响应完成后的第一帧同时显示新卡片、顶部数量和三个来源选择徽标，并验证没有额外库存 GET。状态测试另覆盖三种批次操作的通知一致性、旧库存查询滞后与兼容补读失败。

本机 main 后端的真实请求实测：库存 3 → 换批返回 3 条与库存 0 同时出现在响应中，约 593ms；未观察到该实例在响应后才更新库存。这次客户端修复补齐可复现的通知与兼容路径缺口，手机实际连接地址和用户所述延迟的发生阶段尚未确认，不能把它们视为已定位的线上根因。

本轮验证：定向测试 11 项通过，完整 `flutter test` 88 项通过，`flutter analyze` 无问题，`git diff --check` 通过。正常入口 `flutter build ios --release --target lib/main.dart --no-pub` 编译成功，已通过 devicectl 安装到配对 iPhone；尚未完成用户实际连接实例上的手机页面复测。
