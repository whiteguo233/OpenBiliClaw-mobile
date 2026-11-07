import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/models/chat.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/chat_view.dart';
import 'package:provider/provider.dart';

void main() {
  for (final scenario in [
    (size: const Size(390, 844), scale: 1.0, dark: false),
    (size: const Size(320, 568), scale: 3.2, dark: true),
    (size: const Size(844, 390), scale: 1.0, dark: false),
  ]) {
    testWidgets(
      'source guide remains readable and preserves drafts: $scenario',
      (tester) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = _GuideChatProvider();
        addTearDown(provider.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider<ChatProvider>.value(
            value: provider,
            child: MaterialApp(
              theme: scenario.dark ? AppTheme.dark() : AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
                child: child!,
              ),
              home: const Scaffold(body: ChatView()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        const draft = '我还没写完的需求';
        final input = find.byKey(const Key('chatMessageInput'));
        await tester.enterText(input, draft);
        await tester.tap(find.byKey(const Key('chatSourceGuide')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(BottomSheet), findsOneWidget);
        final scrollable = find
            .descendant(
              of: find.byKey(const Key('chatSourceGuideBody')),
              matching: find.byType(Scrollable),
            )
            .first;
        for (final text in ['网站示例', 'RSS 示例', '历史见「设置 → 异常记录」']) {
          await tester.scrollUntilVisible(
            find.textContaining(text),
            180,
            scrollable: scrollable,
            maxScrolls: 30,
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .getRect(find.textContaining(text))
                .overlaps(
                  tester.getRect(find.byKey(const Key('chatSourceGuideBody'))),
                ),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byKey(const Key('chatSourceGuideClose')));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.widget<TextField>(input).controller!.text, draft);
        expect(provider.sent, isEmpty);
        expect(input.hitTestable(), findsOneWidget);
        // Reading help must leave the ordinary send action usable.
        await tester.tap(find.byKey(const Key('chatSend')));
        await tester.pumpAndSettle();
        expect(provider.sent, [draft]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _GuideChatProvider extends ChatProvider {
  _GuideChatProvider() : super(ApiClient());
  final sent = <String>[];

  @override
  List<ChatTurn> get turns => const [
    ChatTurn(turnId: 'existing', message: '已有聊天记录', status: 'done'),
  ];

  @override
  Future<bool> sendMessage(String message) async {
    sent.add(message);
    return true;
  }
}
