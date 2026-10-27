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
