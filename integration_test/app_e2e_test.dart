import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:openbiliclaw_app/main.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/providers/saved_provider.dart';
import 'package:openbiliclaw_app/providers/profile_provider.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/views/recommend_view.dart';
import 'package:openbiliclaw_app/views/saved_view.dart';
import 'package:openbiliclaw_app/views/profile_view.dart';
import 'package:openbiliclaw_app/views/chat_view.dart';

/// Real end-to-end test: launches the actual app against the REAL local
/// backend (127.0.0.1:8420 on desktop / 10.0.2.2 on Android emulator) and
/// asserts that data loads across all four tabs plus the history tab.
///
/// Requires the OpenBiliClaw backend to be running.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实后端：四个 tab 均能加载数据并渲染', (tester) async {
    await tester.pumpWidget(const OpenBiliClawApp());
    // Wait for loadSettings + auth check + first recommend load.
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await _pumpUntil(tester, () async {
      final ctx = tester.element(find.byType(RecommendView));
      final rp = ctx.read<RecommendProvider>();
      return !rp.loading && rp.online;
    }, timeout: const Duration(seconds: 20));

    // ── Tab 1: 推荐 ──
    final ctx = tester.element(find.byType(RecommendView));
    final recommend = ctx.read<RecommendProvider>();
    expect(recommend.online, isTrue, reason: '推荐页应在线并连上后端');
    expect(recommend.recommendations, isNotEmpty, reason: '推荐列表应有真实数据');
    expect(find.byType(RecommendView), findsOneWidget);
    // 惊喜推荐 banner（LLM 生成）应展示（后端有候选时）。
    if (recommend.delights.isNotEmpty) {
      expect(find.text('惊喜推荐'), findsOneWidget, reason: '有惊喜推荐候选时页面应展示 banner');
    }

    // ── Tab 2: 内容库（稍后再看/收藏/历史记录）──
    await tester.tap(find.text('内容库'));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () async {
      final saved = tester
          .element(find.byType(SavedView))
          .read<SavedProvider>();
      return !saved.loading;
    }, timeout: const Duration(seconds: 15));
    expect(find.text('稍后再看'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('历史记录'), findsOneWidget);

    // 切到历史记录 tab 并等待加载。
    await tester.tap(find.text('历史记录'));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () async {
      final saved = tester
          .element(find.byType(SavedView))
          .read<SavedProvider>();
      return saved.historyLoadedOnce;
    }, timeout: const Duration(seconds: 15));
    final saved = tester.element(find.byType(SavedView)).read<SavedProvider>();
    expect(saved.historyLoadedOnce, isTrue, reason: '历史记录应完成首次加载');

    // ── Tab 3: 画像 ──
    await tester.tap(find.text('画像'));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () async {
      final profile = tester
          .element(find.byType(ProfileView))
          .read<ProfileProvider>();
      return !profile.loading && profile.summary != null;
    }, timeout: const Duration(seconds: 15));
    final profile = tester
        .element(find.byType(ProfileView))
        .read<ProfileProvider>();
    expect(profile.summary, isNotNull, reason: '画像应加载成功');
    expect(find.text('我的画像'), findsOneWidget);
    // LLM 生成的人格素描应渲染出来（真实文本，非占位）。
    expect(find.text('人格素描'), findsOneWidget, reason: '画像页应展示 LLM 生成的人格素描');
    expect(
      profile.summary!.portrait.length,
      greaterThan(50),
      reason: '人格素描应为 LLM 生成的真实长文本',
    );

    // ── Tab 4: 对话 ──
    await tester.tap(find.text('对话'));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () async {
      final chat = tester.element(find.byType(ChatView)).read<ChatProvider>();
      return !chat.loading;
    }, timeout: const Duration(seconds: 15));
    expect(find.text('和阿B聊聊'), findsOneWidget);

    // 发送一条真实消息，等待商汤 LLM 生成回复（端到端 AI 链路）。
    final chatProvider = tester
        .element(find.byType(ChatView))
        .read<ChatProvider>();
    final beforeCount = chatProvider.turns.length;
    await tester.enterText(find.byType(TextField).last, '测试：推荐一个轻松点的内容方向');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await _pumpUntil(tester, () async {
      final chat = tester.element(find.byType(ChatView)).read<ChatProvider>();
      if (chat.turns.length <= beforeCount) return false;
      final last = chat.turns.last;
      return last.isDone || last.hasError || last.reply.isNotEmpty;
    }, timeout: const Duration(seconds: 90));
    final chat = tester.element(find.byType(ChatView)).read<ChatProvider>();
    final last = chat.turns.last;
    expect(last.reply, isNotEmpty, reason: '商汤 LLM 应生成真实回复');
    expect(last.hasError, isFalse, reason: 'AI 回复不应报错');
    expect(find.byType(ChatView), findsOneWidget);
  });
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
