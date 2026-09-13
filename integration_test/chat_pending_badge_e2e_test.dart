import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openbiliclaw_app/main.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/views/chat_view.dart';

/// 真实 App 端到端：启动真实客户端连接本机 127.0.0.1:8420 后端，验证
/// 「对话」Tab 红点开关默认关闭、开启后使用真实待聊积压总数、关闭后隐藏，
/// 且偏好写回真实 SharedPreferences。
///
/// 运行：flutter test integration_test/chat_pending_badge_e2e_test.dart -d 设备ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实后端：对话标签红点默认关闭且可切换', (tester) async {
    // 清掉真实偏好，建立“默认关闭”的干净起点。
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ChatProvider.showPendingBadgePreferenceKey);

    await tester.pumpWidget(const OpenBiliClawApp());
    await tester.pump(const Duration(milliseconds: 500));

    // 等首页底部导航出现，然后切到「对话」Tab（IndexedStack 的非当前页
    // 默认是 offstage，finder 需要先选中该 Tab 才能拿到 ChatView）。
    await _pumpUntil(tester, () async {
      return find.text('对话').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));
    await tester.tap(find.text('对话'));
    await tester.pump(const Duration(milliseconds: 500));

    // 等真实后端返回非空待聊积压。
    await _pumpUntil(tester, () async {
      if (find.byType(ChatView).evaluate().isEmpty) return false;
      final chat = tester.element(find.byType(ChatView)).read<ChatProvider>();
      return chat.pendingTotal > 0;
    }, timeout: const Duration(seconds: 30));

    final chat = tester.element(find.byType(ChatView)).read<ChatProvider>();
    debugPrint(
      'E2E real pending: total=${chat.pendingTotal} page=${chat.pendingCount}',
    );
    expect(chat.pendingTotal, greaterThan(0), reason: '真实后端应有待聊积压');
    expect(chat.showPendingBadge, isFalse, reason: '默认不应展示红点');
    expect(chat.pendingBadgeCount, 0, reason: '默认开关关闭时红点数量应为 0');

    // 找到「对话」Tab 顶部的小开关。
    expect(find.text('对话标签红点'), findsOneWidget);
    final toggle = find.byKey(const Key('chatPendingBadgeToggle'));
    expect(toggle, findsOneWidget);

    // 开启：红点数量应等于真实积压总数，底部导航真实渲染 Badge。
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 300));
    expect(chat.showPendingBadge, isTrue);
    expect(chat.pendingBadgeCount, chat.pendingTotal);
    expect(_navBadgeFinder(), findsOneWidget, reason: '底部对话 Tab 应出现红点');

    // 关闭：红点归零并消失，并写回真实偏好存储。
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 300));
    expect(chat.showPendingBadge, isFalse);
    expect(chat.pendingBadgeCount, 0);
    expect(_navBadgeFinder(), findsNothing, reason: '关闭后底部对话 Tab 不应有红点');
    final stored = (await SharedPreferences.getInstance()).getBool(
      ChatProvider.showPendingBadgePreferenceKey,
    );
    expect(stored, isFalse);
    debugPrint('E2E phase: chat pending badge verified');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// 底部导航里的对话红点：iOS 用 CupertinoTabBar，其余平台用 NavigationBar。
Finder _navBadgeFinder() {
  final navBar = find.byType(CupertinoTabBar).evaluate().isNotEmpty
      ? find.byType(CupertinoTabBar)
      : find.byType(NavigationBar);
  return find.descendant(of: navBar, matching: find.byType(Badge));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('等待条件超时（$timeout）');
}
