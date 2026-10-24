import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbiliclaw_app/main.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/custom_sources_api.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/views/chat_view.dart';
import 'native_chat_hypothesis_live_test.dart' as hypothesis;
import 'native_custom_sources_live_test.dart' as live;

// Independent live checks: a recall or website-planning failure must not hide
// the results of hypothesis actions and feed onboarding. The original full
// scenarios retain their strict assertions and must still be reported.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('independent real native hypothesis actions', (tester) async {
    const confirmTitle = String.fromEnvironment('CONFIRM_HYPOTHESIS');
    const discussTitle = String.fromEnvironment('DISCUSS_HYPOTHESIS');
    expect(confirmTitle, isNotEmpty);
    expect(discussTitle, isNotEmpty);
    await withLiveChat(tester, (chat, api) async {
      final confirmation = await hypothesis.openHypothesis(
        tester,
        chat,
        confirmTitle,
      );
      await live.tapVisible(tester, hypothesis.cardAction(confirmTitle, '说得准'));
      await live.wait(
        tester,
        () =>
            !chat.cardBusy(confirmation.turnId) &&
            chat.turns.any(
              (t) =>
                  t.turnId == confirmation.turnId && t.cardState == 'confirmed',
            ),
        'confirmed hypothesis',
        seconds: 150,
      );
      final confirmed = await api.get('/chat/turns/${confirmation.turnId}');
      expect((confirmed['payload'] as Map)['state'], 'confirmed');
      final pendingAfterConfirm = await api.get(
        '/chat/pending-confirmations?session=popup',
      );
      expect(
        (pendingAfterConfirm['items'] as List).any(
          (r) => r['title'] == confirmTitle,
        ),
        false,
      );
      debugPrint('CHAT_LIVE confirmed ${confirmation.turnId}');

      final discussion = await hypothesis.openHypothesis(
        tester,
        chat,
        discussTitle,
      );
      await live.tapVisible(tester, hypothesis.cardAction(discussTitle, '聊一聊'));
      await live.wait(
        tester,
        () =>
            chat.turns.any(
              (t) =>
                  t.turnId == discussion.turnId && t.cardState == 'discussing',
            ) &&
            chat.dialogueContext?.replyToTurnId == discussion.turnId,
        'hypothesis discuss context',
        seconds: 100,
      );
      final response = await hypothesis.send(
        tester,
        chat,
        '先别确认或否认这个猜测，也不要修改画像。请解释你正在跟我讨论的这个具体猜测，再问一个问题核实它。',
      );
      expect(response.replyToTurnId, discussion.turnId);
      expect(
        response.reply,
        contains('通勤'),
        reason:
            'Model must receive the selected hypothesis, not the prior confirmed card',
      );
      final stored = await api.get('/chat/turns/${response.turnId}');
      expect(stored['reply_to_turn_id'], discussion.turnId);
      debugPrint(
        'CHAT_LIVE discussion ${jsonEncode({'card': discussion.turnId, 'turn': response.turnId, 'reply': response.reply})}',
      );
      await live.tapVisible(tester, hypothesis.cardAction(discussTitle, '不准确'));
      await live.wait(
        tester,
        () =>
            !chat.cardBusy(discussion.turnId) &&
            chat.turns.any(
              (t) => t.turnId == discussion.turnId && t.cardState == 'rejected',
            ),
        'reject discussed hypothesis',
        seconds: 150,
      );
      expect(
        chat.dialogueContext,
        isNull,
        reason: 'Settling the selected card must release the compose context',
      );
      final rejected = await api.get('/chat/turns/${discussion.turnId}');
      expect((rejected['payload'] as Map)['state'], 'rejected');
      final pending = await api.get(
        '/chat/pending-confirmations?session=popup',
      );
      expect(
        (pending['items'] as List).any((r) => r['title'] == discussTitle),
        false,
      );
      final free = await hypothesis.send(
        tester,
        chat,
        '我们结束刚才那个猜测话题。现在只回复“普通聊天恢复”。',
      );
      expect(free.replyToTurnId, isEmpty);
      expect(free.reply, contains('普通聊天恢复'));
      expect(tester.takeException(), isNull);
      debugPrint(
        'FOLLOWUP_LIVE HYPOTHESES PASS confirm=${confirmation.turnId} discuss=${discussion.turnId} final=${free.turnId}',
      );
    });
  }, timeout: const Timeout(Duration(minutes: 12)));

  testWidgets('independent real native feed onboarding', (tester) async {
    await withLiveChat(tester, (chat, api) async {
      await live.addFeed(tester, CustomSourcesApi(api), chat);
      expect(tester.takeException(), isNull);
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<void> withLiveChat(
  WidgetTester tester,
  Future<void> Function(ChatProvider, ApiClient) action,
) async {
  final prefs = await SharedPreferences.getInstance();
  final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
  await prefs.setString('api_host', 'localhost');
  await prefs.setInt('api_port', 18612);
  await prefs.setString('api_scheme', 'http');
  await prefs.setString('api_base_path', '');
  await prefs.setString('connection_mode', 'direct');
  await prefs.remove('session_token');
  try {
    await tester.pumpWidget(const OpenBiliClawApp());
    await live.wait(
      tester,
      () => find.text('对话').evaluate().isNotEmpty,
      'home',
    );
    await tester.tap(find.text('对话'));
    await tester.pump(const Duration(seconds: 1));
    final context = tester.element(find.byType(ChatView));
    await action(context.read<ChatProvider>(), context.read<ApiClient>());
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await prefs.clear();
    for (final entry in before.entries) {
      final value = entry.value;
      if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is List<String>) {
        await prefs.setStringList(entry.key, value);
      }
    }
  }
}
