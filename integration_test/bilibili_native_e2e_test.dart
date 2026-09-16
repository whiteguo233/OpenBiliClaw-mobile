import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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

    // 播放器应加载成功并显示互动按钮。互动计数异步到达后标签会变成
    // 「12.3万 点赞」这类文案，因此统一用 textContaining 匹配。
    await _pumpUntil(tester, () async {
      return find.textContaining('点赞').evaluate().isNotEmpty &&
          find.textContaining('投币').evaluate().isNotEmpty &&
          find.textContaining('收藏').evaluate().isNotEmpty &&
          find.textContaining('稍后').evaluate().isNotEmpty &&
          find.textContaining('三连').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));
    expect(find.textContaining('点赞'), findsOneWidget);
    expect(find.textContaining('投币'), findsOneWidget);
    expect(find.textContaining('收藏'), findsOneWidget);
    expect(find.textContaining('稍后'), findsOneWidget);
    expect(find.textContaining('三连'), findsOneWidget);

    // UP 主信息条来自真实 video/info 的 owner 与 user/card 的粉丝数。
    await _pumpUntil(tester, () async {
      return find.textContaining('粉丝').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));

    // 评论/相关视频是异步增强能力，允许存在；至少不应因为错误而消失。
    await _pumpUntil(tester, () async {
      return find.textContaining('评论').evaluate().isNotEmpty ||
          find.text('相关视频').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));

    debugPrint('E2E: bilibili native page loaded real backend data');
  });

  testWidgets('竖屏视频不全屏占位，全屏可看评论', (tester) async {
    final client = ApiClient(host: '127.0.0.1', port: 8420);

    // BV19XkQY2EES 是真实竖屏视频（1080x1920，由后端 play-url 确认）。
    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: client,
        child: const MaterialApp(
          home: NativeBilibiliVideoPage(
            bvid: 'BV19XkQY2EES',
            title: '竖屏端到端测试视频',
          ),
        ),
      ),
    );

    await _pumpUntil(tester, () async {
      return find.textContaining('点赞').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));
    await _pumpUntil(tester, () async {
      return find.byType(Video).evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final videoRect = tester.getRect(find.byType(Video));
    debugPrint('E2E portrait: screen=$screen videoRect=$videoRect');

    // 竖屏视频不应吃满整页：底部必须留出操作栏 + 标题/评论区的空间。
    expect(
      videoRect.bottom,
      lessThan(screen.height - 200),
      reason: '竖屏视频播放器吃满了整页，标题/评论被挤出屏幕',
    );

    // 互动操作栏应在屏幕内。
    final likeRect = tester.getRect(find.textContaining('点赞'));
    expect(likeRect.bottom, lessThanOrEqualTo(screen.height + 1));

    // 正文标题应无需滚动即在可视区域内（AppBar 标题在最上方，正文标题在
    // 播放器下方）。
    final bodyTitleVisible = find.text('竖屏端到端测试视频').evaluate().any((element) {
      final rect = tester.getRect(find.byWidget(element.widget));
      return rect.top > videoRect.bottom && rect.bottom <= screen.height + 1;
    });
    expect(bodyTitleVisible, isTrue, reason: '正文标题不在可视区域内');

    // media_kit 桌面端使用原生控制层，沙盒测试环境不会出现移动端那套
    // fullscreen 按钮 overlay；布局断言已在上方完成，桌面端到此结束。
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows);
    if (isDesktop) {
      debugPrint(
        'E2E: desktop player layout verified; fullscreen overlay test skipped',
      );
      return;
    }

    // 进入全屏：点出控制层后点全屏按钮。真机上路由转场需要多帧才完成，
    // 用 _pumpUntil 等待全屏页出现，而不是固定 pump 时长。
    await tester.tapAt(videoRect.center);
    await tester.pump(const Duration(milliseconds: 500));
    await _pumpUntil(tester, () async {
      return find.byIcon(Icons.fullscreen).evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 10));
    await tester.tap(find.byIcon(Icons.fullscreen));
    await _pumpUntil(tester, () async {
      return find.byTooltip('退出全屏').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 15));

    // 全屏页：有退出按钮，也有评论入口（背景页不含这两个 tooltip）。
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    expect(find.byTooltip('查看评论'), findsOneWidget);

    // 打开评论弹层，真实请求评论数据。
    await tester.tap(find.byTooltip('查看评论'));
    await _pumpUntil(tester, () async {
      return find.textContaining('评论').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));
    expect(find.textContaining('评论'), findsWidgets);

    // 关闭弹层并退出全屏。
    await tester.tap(find.byTooltip('关闭'));
    await _pumpUntil(tester, () async {
      return find.byTooltip('退出全屏').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 15));
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pump(const Duration(seconds: 1));

    debugPrint('E2E: portrait video layout + fullscreen comments verified');
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
