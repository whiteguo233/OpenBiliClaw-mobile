import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/models/chat.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/chat_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('对话标签红点默认关闭并持久化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final provider = ChatProvider(ApiClient());
    addTearDown(provider.dispose);
    expect(provider.showPendingBadge, isFalse);
    expect(provider.pendingBadgeCount, 0);

    await provider.loadShowPendingBadge();
    expect(provider.showPendingBadge, isFalse);

    await provider.setShowPendingBadge(true);
    expect(provider.showPendingBadge, isTrue);
    expect(
      provider.pendingBadgeCount,
      provider.pendingTotal,
      reason: '开关开启后底部红点应跟随待聊积压总数',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(ChatProvider.showPendingBadgePreferenceKey),
      isTrue,
      reason: '开关状态应写入 SharedPreferences',
    );

    final reloaded = ChatProvider(ApiClient());
    addTearDown(reloaded.dispose);
    await reloaded.loadShowPendingBadge();
    expect(reloaded.showPendingBadge, isTrue, reason: '重启后应恢复上次选择');
  });

  testWidgets('对话页顶部开关可切换红点偏好', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ChatProvider.showPendingBadgePreferenceKey: false,
    });
    final provider = _PendingBadgeChatProvider();
    addTearDown(provider.dispose);
    await provider.loadShowPendingBadge();

    await tester.pumpWidget(
      ChangeNotifierProvider<ChatProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ChatView()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('对话标签红点'), findsOneWidget);
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pump();

    expect(provider.showPendingBadge, isTrue);
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(provider.pendingBadgeCount, 3);
  });
}

class _PendingBadgeChatProvider extends ChatProvider {
  _PendingBadgeChatProvider() : super(ApiClient());

  @override
  int get pendingCount => 3;

  @override
  int get pendingTotal => 3;

  @override
  List<PendingConfirmation> get pendingConfirmations => const [];
}
