# 原生真实请求测试的构建与复用

`test_driver/native_live.dart` 可运行原生集成用例，保留完整验收门槛，不模拟后端、模型或网页。
网页 / Atom 来源用例连接隔离的 `localhost:18612`，会创建、审批和管理测试来源；勿连接日常数据。
后端须先启动、配置真实模型与托管 Ego Lite。来源用例成功后会停用本次来源，失败时须核对并停用
本次新增项，保留原有来源策略。原生聊天假设用例另需预先准备其明确要求的测试卡片。

聊天假设用例使用 `CONFIRM_HYPOTHESIS`、`DISCUSS_HYPOTHESIS` 指定两条内容不同且待确认的
隔离 fixture。`DISCUSS_HYPOTHESIS_ANCHOR` 默认是「通勤」；换场景时应指定该场景的具体
关键词，且不能为空，避免把准确的自然语言改述误判为上下文丢失。回复目标 ID、卡片状态、
待确认列表与持久结果的断言继续保留。不要通过清除真实卡片状态来重复测试。

```bash
flutter drive --no-pub --driver=test_driver/native_live.dart \
  --target=integration_test/native_custom_sources_live_test.dart -d <ios-simulator-id>
```

网页默认使用 NGA。可通过 `--dart-define-from-file=<local-json>` 同时指定
`NATIVE_SOURCE_LABEL`（名称前缀）和 `NATIVE_WEB_PROMPT`（完整聊天提示词），以相同用例验证
哔哩轻小说等其他网站。自定义提示词必须包含 `{sourceName}`，运行时替换为本次唯一名称，
以便关联真实审批和来源。Ego 执行器、审批、份额保存、定时采集、截图接管、返回聊天及
后续 Atom 的断言全部保留；自定义网址不能把外部阻断或失败变成跳过。配置在编译时生效，
复用原生包时必须核对其相同提示词、定义参数和源码版本。

仅后端发生变化时，可复用上述命令生成的原生包，避免每轮重编译：

```bash
flutter drive --no-pub --driver=test_driver/native_live.dart \
  --use-application-binary=build/ios/iphonesimulator/Runner.app \
  --target=integration_test/native_custom_sources_live_test.dart -d <ios-simulator-id>
```

必须确认包仍是同一用例和编译参数。`flutter test` 产生的是测试 bootstrap，不能直接用此 driver
复用。`--no-build` 已废弃且可能仍触发构建；使用 `--use-application-binary`。保存模拟器包时保留
`Runner.app` 名称，便于 Flutter 从原生日志发现 VM service；复制到其他目录即可，无需改名。

截图／退出／重新接管用例需要先选取本次已创建且停用的 NGA 测试来源：

```bash
flutter drive --no-pub --driver=test_driver/native_live.dart \
  --target=integration_test/native_source_login_live_test.dart \
  --dart-define=NATIVE_SOURCE_ID=<test-source-id> -d <ios-simulator-id>
```

也可先用 `flutter build ios --simulator --debug --no-pub --target=...` 和同一 `--dart-define`
编译，再用该包运行 driver。`takeScreenshot` 返回的实际图片还需人工核看。用例打印的模拟器
临时文件可能在 driver 卸载测试 App 时消失；host 侧 `build/integration_response_data.json`
的 `screenshots` 数组也保存原始 PNG bytes，应从该产物提取并留存。
原始会话日志、截图和模型请求可能包含私有信息，留在本机，不随测试代码提交。

验证 iframe 授权可单独测试：先在隔离后端准备一个真实 `needs_login` 草稿，再运行
`integration_test/native_verification_scope_live_test.dart`，编译参数为
`NATIVE_VERIFICATION_DRAFT`、`NATIVE_VERIFICATION_ORIGIN` 和可选的
`NATIVE_VERIFICATION_PORT`（默认 18614）。用例只点击 App 的精确域授权按钮，检查真实
Ego iframe 不再被权限拦截、截图绘制及退出释放；不操作网站验证码，不把授权成功算作
验证通过、聊天建源完成或已采集入池。勿使用正式数据或已有授权的草稿。

可另设 `NATIVE_FEED_URL` 切换后续订阅源，默认仍为阮一峰 Atom。
`NATIVE_CADENCE_RUNS` 默认 1；设置为 2 可保留本次网页来源等待至少两次真实后台成功运行，
只计算当前 workflow 版本，并校验前次完成到下次开始至少为配置间隔；
不把登录恢复后发布的新版本首轮计作上个版本的第二周期，不改写到期时间、不调用强制刷新。最后停用本次来源；失败须按唯一名称清理。

`native_source_attention_live_test.dart` 连接同一隔离 API 18612，需 `NATIVE_ATTENTION_DRAFT`
指向真正返回 `verification_required` 的草稿；覆盖完整 App 消息铃铛、原生接管截图与退出后
保留待处理提醒。用例不操作网站验证码，不把打开验证页视为通过验证。

2026-11-06 验收使用 iPhone 17 Pro / iOS 26.5 模拟器：Rust 网页聊天建源、改份额、
接管后再试采、Django RSS 聊天建源以及当前版本两轮自然采集整轮通过；周期实测 315.53 秒。
验证提醒专项另行重新构建并通过，截图已在 host 侧提取并人工核看。
后端完整证据见 `docs/testing/2026-11-06-source-attention-e2e.md`（后端仓库）。
这不是物理手机、Android 或网站验证码通过的验收。


来源故障专项 `native_source_failures_live_test.dart` 连接独立 18616 API 和 18617 测试控制进程，
编译参数 `NATIVE_FAILURE_SOURCE` 指定已真实试采的隔离来源，端口可通过 NATIVE_FAILURE_PORT /
NATIVE_FAILURE_CONTROL_PORT 覆盖。控制进程 POST /fail 应经正式采集路径触发三次可复现失败；
2026-11-07 使用进程内网络策略临时指定无监听的本地代理，让真实 HTTP 请求连接失败。
POST /recover 恢复正常网络，必须真实采集同一公开 Feed 并提交成功结果；仅测试脚本重置到期时间。
此前 2026-11-06 用例直接经 WorkflowStore 注入 timeout，仍仅作状态链路历史证据。
产品 API 不添加测试控制路由；须自行在私有数据目录准备控制脚本，禁止连接正式数据。
用例验证完整原生 App 铃铛、准确来源卡、失败与恢复记录、提醒清除和设置入口。
同一 driver/build 命令可将 target 替换为此用例，截图提取规则相同。
这是故障恢复路径验收，不是自然周期、真实上游 outage 或聊天模型验收。

2026-11-06 最终同一来源经历完整故障／恢复流程，58 秒通过，截图已检查；
后端重启保留历史，独立控制 worker 的新事件经 WebSocket 各转发一次。
私有测试源停用、服务关闭、模拟器恢复关机；没有合并发布。

2026-11-07 使用同一 iPhone 17 Pro／iOS 26.5 模拟器重新验收。故障专项改用真实
HTTP 连接失败，完整原生消息、异常历史、恢复与设置入口 1 分 37 秒通过，API 重启后
历史保留。聊天来源整轮已完成 Rust 网页与 Django RSS 的真实建源、份额、采集和
Ego 截图／继续试采，但因原生初始化间歇超时，当前版本第二次成功运行晚于用例的
12 分钟周期等待窗口，整轮仍为失败。保留原结果，未修改等待断言。

后端随后修复启动锁竞争与初始化总等待提前截断；新空库复测遇到系统严重资源压力，
Flutter 的模拟器设备查询在任何 App phase 之前卡住，驱动被停止、模拟器恢复关机。
这不是最终代码的原生整轮通过，也不替代物理手机／Android 验收。最终代码的后端请求
另列于后端仓库 `docs/testing/2026-11-07-real-native-source-e2e.md`，原生代码本轮未再改动。

继续验收使用新分支 `fix/native-http-lifecycle-20261107`，保留原生上一分支的差异。
实际截图复现 `Bad state: cannot close with running requests` 后，ApiClient 改为
发送取消信号，并等真实请求结束才释放独占客户端。21 项相关测试及完整 188 项单元
测试通过，静态分析无问题。`native_source_http_lifecycle_live_test.dart` 的真实
NSURLSession 专项覆盖响应头／响应体超时，并验证下一请求恢复；随后运行完整聊天来源用例。

最终组合包在 iPhone 17 Pro／iOS 26.5 模拟器 **18 分 05 秒通过**：Rust 网页、Django RSS
均经真实 Luna 聊天、审批及正式调度采到内容，网页使用官方 Ego Lite，份额与接管返回通过。
当前流程版本成功运行两次，中间一次 120 秒冷启动超时保留为失败；按正常 300 秒退避后，
再次冷启动在 20.37 秒内采到 3 条。未改写到期时间或放宽 12 分钟周期等待断言。
6 条去重后候选经真实模型／embedding 评估，4 条入池、2 条被原 0.6 门槛拒绝。
App 安装目录的 Runner、App framework 和 kernel_blob 哈希与保存的组合包一致。
这证明了本次完整路径及自动恢复，不声明高负载下从不超时。

同一最终 ApiClient 重新构建的故障专项 **1 分 16 秒通过**。真实连接拒绝连续三次，
准确来源卡和配置页显示失败次数；恢复请求为真实 Django RSS `not_modified`，
当前提醒清除。截图核对最新恢复 03:43:26 与警告 03:42:38；事件 `source:5/6`
各推送一次，6 条历史跨后端重启不变。故障包安装哈希与保存包一致。

完整原生用例结束后补充一轮正常周期：经配置 API 再启用本次 Rust 来源，核对到期值
未改变，距上次完成 300.19 秒后自动启动，31.84 秒取回 3 条、新增 0 条。
它是另列的调度复核，不改写原生用例日志，也不掩盖之前那一次超时。

本次测试来源与服务已关闭，iOS 模拟器恢复 Shutdown。旧原生 worktree 的 tracked／
untracked 文件哈希不变；改动留在上述独立分支，未提交、合并、推送或发布。

## 2026-11-08 后台 Ego 组合复验

`fix/native-real-e2e-20261108` 保留来源引导、提醒和 HTTP 生命周期改动；本轮未新增原生产品代码。
同一 iPhone 17 Pro／iOS 26.5 模拟器、官方 Ego Lite 0.6.2.9，使用隔离数据库和真实官方
Codex Responses GPT-6 Luna 请求。Rust 网页完整流程、份额 1→2、Ego 截图／继续试采、
Django RSS 及当前版本两次自然成功采集 **7 分 53 秒通过**，间隔 300.118 秒。

随后 `native_chat_hypothesis_live_test.dart` 使用两条明确的合成 fixture，
普通聊天暗号记忆、假设确认、指定假设上下文讨论、否认及普通聊天恢复 **1 分钟通过**；
实际安装的 Runner／App framework／kernel_blob 与该测试保存包的 SHA-256 一致。
来源故障专项的真实 HTTP 连接拒绝、App 消息／来源／异常记录及恢复 **51 秒通过**，
历史跨后端重启保留，独立 worker 的新失败／恢复事件各通过 WebSocket 推送一次。

Flutter 完整单元测试 **191 项通过**，`flutter analyze` 无问题。早期模型 CLI 兼容测试层
流式／工具审批及 JSON 协议错误保留为失败阶段，不计作产品通过；最终适配层只转译实际
官方模型请求，不生成回复或执行应用工具。后端 46,356 次窗口／焦点采样为零，最后采集
后约 120 秒自动退出。完整范围见后端仓库
`docs/testing/2026-11-08-real-dynamic-sources-e2e.md`，不替代物理手机／Android 验收。

### 主线合并验证

本轮将上述提交 `d846bbd` 与远端主线 `0b40c5b` 合并，保留扫码连接、代理路径前缀、
依赖升级及原有发布配置。合并后的 Flutter 单元／Widget 测试 240 项通过，静态分析和
格式检查通过；真实来源流程证据对应上节记录的模拟器组合包。本次仅合并代码，未改变
版本号、打发布标签或提交应用商店。主工作区原有未提交改动单独保留，未纳入此合并。

推送前再次同步主线 `f50f0a9`，保留新增的 iOS 1.0.2 发布记录与随包隐私／帮助说明；
此轮增量仅涉及文档与说明资源，应用代码和依赖未变，240 项回归结果继续适用。
