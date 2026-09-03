import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/views/native_bilibili_video_page.dart';

/// Focused real-backend test for the new Bilibili native player page.
/// It exercises the real OpenBiliClaw backend (127.0.0.1:8420 on iOS/macOS
/// simulator) with the real Bilibili Cookie and media_kit.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('原生 B 站播放器真实请求', (tester) async {
    final client = ApiClient(host: '127.0.0.1', port: 8420);

    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: client,
        child: const MaterialApp(
          home: NativeBilibiliVideoPage(
            bvid: 'BV1xx411c7mD',
            title: '真实端到端测试视频',
          ),
        ),
      ),
    );

    // 播放器应加载成功并显示互动按钮。
    await _pumpUntil(tester, () async {
      return find.text('点赞').evaluate().isNotEmpty &&
          find.text('投币').evaluate().isNotEmpty &&
          find.text('收藏').evaluate().isNotEmpty &&
          find.text('稍后').evaluate().isNotEmpty &&
          find.text('三连').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));
    expect(find.text('点赞'), findsOneWidget);
    expect(find.text('投币'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('三连'), findsOneWidget);

    // 评论/相关视频是异步增强能力，允许存在；至少不应因为错误而消失。
    await _pumpUntil(tester, () async {
      return find.text('评论').evaluate().isNotEmpty ||
          find.text('相关视频').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));

    debugPrint('E2E: bilibili native page loaded real backend data');
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await condition()) return;
  }
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .toList();
  debugPrint('E2E timeout page texts: $texts');
  throw TestFailure('等待条件超时');
}
