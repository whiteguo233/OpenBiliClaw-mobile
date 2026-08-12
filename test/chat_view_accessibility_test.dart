import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/models/chat.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/chat_view.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'chat composer fits an iOS keyboard-sized accessibility viewport',
    (tester) async {
      tester.view.physicalSize = const Size(402, 752);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      final provider = _RespondingChatProvider();
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<ChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.2)),
              child: child!,
            ),
            home: const Scaffold(body: ChatView()),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('和阿B聊聊'), findsOneWidget);
      expect(find.text('15 条待聊确认'), findsOneWidget);

      // Reproduce the frame in which the iOS keyboard starts resizing the
      // Scaffold. Accessibility chrome must not overflow during the transition.
      tester.view.viewInsets = const FakeViewPadding(bottom: 335);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('停止等待'), findsOneWidget);
    },
  );
}

class _RespondingChatProvider extends ChatProvider {
  _RespondingChatProvider() : super(ApiClient());

  @override
  List<ChatTurn> get turns => const [
    ChatTurn(
      turnId: 'pending-accessibility-turn',
      message: '测试：推荐一个轻松点的内容方向',
      status: 'pending',
    ),
  ];

  @override
  bool get responding => true;

  @override
  int get pendingCount => 15;

  @override
  String get error => '回复仍在后台处理中，稍后会从共享历史自动恢复。';
}
