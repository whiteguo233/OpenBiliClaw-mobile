# 原生真实请求测试的构建与复用

`test_driver/native_live.dart` 可运行现有原生集成用例，不修改断言，不模拟后端、模型或网页。
NGA / Atom 来源用例连接隔离的 `localhost:18612`，会创建、审批和管理测试来源；勿连接日常数据。
后端须先启动、配置真实模型与托管 Ego Lite。来源用例成功后会停用本次来源，失败时须核对并停用
本次新增项，保留原有来源策略。原生聊天假设用例另需预先准备其明确要求的测试卡片。

```bash
flutter drive --no-pub --driver=test_driver/native_live.dart \
  --target=integration_test/native_custom_sources_live_test.dart -d <ios-simulator-id>
```

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
编译，再用该包运行 driver。`takeScreenshot` 返回的实际图片还需人工核看，文件位置由用例打印。
原始会话日志、截图和模型请求可能包含私有信息，留在本机，不随测试代码提交。
