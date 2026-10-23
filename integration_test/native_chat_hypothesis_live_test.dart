import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbiliclaw_app/main.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/models/chat.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/views/chat_view.dart';
import 'native_custom_sources_live_test.dart' as live;

// Requires two explicitly seeded hypotheses in an isolated real backend.
// UI actions and model responses are real; no production profile is used.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real native chat, hypothesis confirmation and contextual discussion', (
    tester,
  ) async {
    const confirmTitle = String.fromEnvironment('CONFIRM_HYPOTHESIS');
    const discussTitle = String.fromEnvironment('DISCUSS_HYPOTHESIS');
    expect(confirmTitle, isNotEmpty);
    expect(discussTitle, isNotEmpty);
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
      final chat = context.read<ChatProvider>();
      final api = context.read<ApiClient>();
      final code = '松果${DateTime.now().millisecondsSinceEpoch}';
      await send(
        tester,
        chat,
        '这次对话的临时暗号是“$code”。只在这次对话中记住它，不要保存到画像或笔记。请简单回应。',
      );
      final remembered = await send(tester, chat, '我刚才说的临时暗号是什么？只回复暗号。');
      expect(
        remembered.reply,
        contains(code),
        reason: 'Ordinary chat must retain its actual prior turn',
      );
      debugPrint(
        'CHAT_LIVE ordinary ${jsonEncode({'turn': remembered.turnId, 'reply': remembered.reply})}',
      );

      final confirmation = await openHypothesis(tester, chat, confirmTitle);
      await live.tapVisible(tester, cardAction(confirmTitle, '说得准'));
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

      final discussion = await openHypothesis(tester, chat, discussTitle);
      await live.tapVisible(tester, cardAction(discussTitle, '聊一聊'));
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
      final response = await send(
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
      await live.tapVisible(tester, cardAction(discussTitle, '不准确'));
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
      final free = await send(tester, chat, '我们结束刚才那个猜测话题。现在只回复“普通聊天恢复”。');
      expect(free.replyToTurnId, isEmpty);
      expect(free.reply, contains('普通聊天恢复'));
      expect(tester.takeException(), isNull);
      debugPrint(
        'CHAT_LIVE PASS confirm=${confirmation.turnId} discuss=${discussion.turnId} final=${free.turnId}',
      );
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
  }, timeout: const Timeout(Duration(minutes: 18)));
}

Future<ChatTurn> send(
  WidgetTester tester,
  ChatProvider chat,
  String message,
) async {
  await live.wait(
    tester,
    () => !chat.responding,
    'composer ready',
    seconds: 180,
  );
  final previousIds = chat.turns.map((t) => t.turnId).toSet();
  bool isNewTurn(ChatTurn t) =>
      t.message == message && !previousIds.contains(t.turnId);
  final input = find.byKey(const Key('chatMessageInput'));
  await tester.tap(input);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(input, message);
  expect(
    tester.widget<TextField>(input).controller!.text,
    message,
    reason: 'The native text input must receive the typed message',
  );
  await live.tapVisible(tester, find.byKey(const Key('chatSend')));
  FocusManager.instance.primaryFocus?.unfocus();
  await live.wait(
    tester,
    () => chat.turns.any(isNewTurn),
    'message submitted',
    seconds: 10,
  );
  await live.wait(
    tester,
    () {
      final turns = chat.turns.where(isNewTurn);
      if (turns.any((t) => t.hasError)) {
        fail('Real chat failed: ${turns.first.error}');
      }
      return turns.any((t) => t.isDone && t.reply.isNotEmpty) &&
          !chat.responding;
    },
    'real chat reply',
    seconds: 300,
  );
  return chat.turns.firstWhere(isNewTurn);
}

Finder cardAction(String title, String label) {
  final column = find
      .ancestor(of: find.text(title).last, matching: find.byType(Column))
      .first;
  return find.descendant(
    of: column,
    matching: find.widgetWithText(OutlinedButton, label),
  );
}

Future<ChatTurn> openHypothesis(
  WidgetTester tester,
  ChatProvider chat,
  String title,
) async {
  await live.wait(
    tester,
    () => chat.pendingConfirmations.any((p) => p.title == title),
    'pending hypothesis',
    seconds: 60,
  );
  final compact = find.textContaining('条待聊确认');
  final sheet = compact.evaluate().isNotEmpty;
  if (sheet) {
    await tester.tap(compact);
    await tester.pump(const Duration(milliseconds: 500));
  }
  await live.tapVisible(tester, find.textContaining('待聊确认（'));
  await tester.pump(const Duration(milliseconds: 500));
  final column = find
      .ancestor(of: find.text(title), matching: find.byType(Column))
      .first;
  await live.tapVisible(
    tester,
    find.descendant(of: column, matching: find.text('放进对话')),
  );
  await live.wait(
    tester,
    () => chat.turns.any((t) => t.payload['title'] == title && t.isCard),
    'open hypothesis',
    seconds: 210,
  );
  if (sheet) {
    await live.wait(
      tester,
      () => find.byType(BottomSheet).evaluate().isEmpty,
      'pending sheet dismissed',
    );
  }
  expect(
    chat.error,
    isEmpty,
    reason: 'Opening a pending card must not report an inactive discussion',
  );
  return chat.turns.lastWhere((t) => t.payload['title'] == title && t.isCard);
}
