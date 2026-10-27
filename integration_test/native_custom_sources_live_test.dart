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
import 'package:openbiliclaw_app/views/custom_sources_view.dart';
import 'package:openbiliclaw_app/views/source_login_view.dart';

// Isolated real backend only; no mock model, browser or source responses.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native chat → approval → Ego source → management → login return', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    // localhost avoids recovering a previously saved 127.0.0.1 Keychain endpoint.
    await prefs.setString('api_host', 'localhost');
    await prefs.setInt('api_port', 18612);
    await prefs.setString('api_scheme', 'http');
    await prefs.setString('api_base_path', '');
    await prefs.setString('connection_mode', 'direct');
    await prefs.remove('session_token');
    try {
      await tester.pumpWidget(const OpenBiliClawApp());
      await wait(tester, () => find.text('对话').evaluate().isNotEmpty, 'home');
      await tester.tap(find.text('对话'));
      await tester.pump(const Duration(seconds: 1));
      final ctx = tester.element(find.byType(ChatView));
      final api = CustomSourcesApi(ctx.read<ApiClient>());
      final chat = ctx.read<ChatProvider>();
      const sourceLabel = String.fromEnvironment(
        'NATIVE_SOURCE_LABEL',
        defaultValue: 'NGA 原生验收',
      );
      const promptTemplate = String.fromEnvironment('NATIVE_WEB_PROMPT');
      final name = '$sourceLabel ${DateTime.now().millisecondsSinceEpoch}';
      final prompt = promptTemplate.isEmpty
          ? '新增独立 Discovery 网页来源，名称“$name”，网址 https://bbs.nga.cn/thread.php?fid=-447601 。使用 Ego Lite。二次元国家地理板块第一页，允许置顶、公告、高亮和专楼，只收 read.php?tid= 帖子详情，不收导航和子版块。每轮最多3条、1页，不翻页，提取标题链接和作者，摘要没有留空。不需要登录。每5分钟采集，份额1。请现在真实试跑并提交激活审批。'
          : promptTemplate.replaceAll('{sourceName}', name);
      expect(
        prompt,
        contains(name),
        reason: 'A custom prompt must retain the unique source name',
      );
      await tester.tap(find.byKey(const Key('chatMessageInput')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const Key('chatMessageInput')), prompt);
      await tester.tap(find.byKey(const Key('chatSend')));
      FocusManager.instance.primaryFocus?.unfocus();
      await wait(
        tester,
        () {
          final own = chat.turns.where((t) => t.message == prompt);
          if (own.any((t) => t.hasError)) {
            fail('Agent turn failed: ${own.first.error}');
          }
          return chat.approvals.any(
            (a) =>
                a['status'] == 'pending' &&
                a['summary'].toString().contains(name),
          );
        },
        'source approval',
        seconds: 420,
      );
      final approval = chat.approvals.firstWhere(
        (a) =>
            a['status'] == 'pending' && a['summary'].toString().contains(name),
      );
      debugPrint('NATIVE_LIVE approval ${jsonEncode(approval)}');
      await tester.tap(find.byKey(const Key('chatApprovals')));
      await tester.pump(const Duration(seconds: 1));
      final approve = find.byKey(Key('approve-${approval['approval_id']}'));
      await tapVisible(tester, approve);
      await wait(
        tester,
        () => chat.approvals.any(
          (a) =>
              a['approval_id'] == approval['approval_id'] &&
              a['status'] == 'executed',
        ),
        'activation',
        seconds: 180,
      );
      await tester.tap(find.byTooltip('关闭审批'));
      await tester.pump(const Duration(seconds: 1));
      final rows = sourceMaps((await api.list())['items']);
      final source = rows.firstWhere((s) => s['name'] == name);
      final id = source['source_id'].toString();
      expect(source['enabled'], true);
      expect(
        sourceMaps(source['workflows']).every((w) => w['executor'] == 'ego'),
        true,
      );
      debugPrint('NATIVE_LIVE activated $id $name');
      await tester.tap(find.byTooltip('连接设置'));
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(
        find.byKey(const Key('customSourcesSettings')),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('customSourcesSettings')));
      await wait(
        tester,
        () =>
            find.byType(CustomSourcesView).evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
        'source settings',
      );
      final card = find.byKey(ValueKey('source-$id'));
      await tester.scrollUntilVisible(
        card,
        350,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      final edit = find.descendant(of: card, matching: find.text('来源设置'));
      await tapVisible(tester, edit);
      await tester.pump(const Duration(seconds: 1));
      await tester.enterText(find.byKey(const Key('sourceShareInput')), '2');
      FocusManager.instance.primaryFocus?.unfocus();
      await tapVisible(tester, find.text('保存来源设置'));
      await tester.pump(const Duration(seconds: 2));
      expect(
        sourceMaps(
          (await api.list())['items'],
        ).firstWhere((s) => s['source_id'] == id)['target_share'],
        2,
      );
      // Let the real background discovery tick collect the activated source.
      final deadline = DateTime.now().add(const Duration(minutes: 4));
      var collected = false;
      while (DateTime.now().isBefore(deadline)) {
        final runs = sourceMaps((await api.runs(id))['items']);
        if (runs.any((r) => (r['discovered_count'] as num? ?? 0) > 0)) {
          debugPrint('NATIVE_LIVE collected ${jsonEncode(runs)}');
          collected = true;
          break;
        }
        await tester.pump(const Duration(seconds: 3));
      }
      expect(
        collected,
        true,
        reason: 'real scheduler must collect through Ego',
      );
      final login = find.descendant(of: card, matching: find.text('重新登录'));
      await tapVisible(tester, login);
      await wait(
        tester,
        () => find.byType(SourceLoginView).evaluate().isNotEmpty,
        'native takeover',
      );
      await wait(
        tester,
        () =>
            find.byKey(const Key('sourceLoginResume')).evaluate().isNotEmpty &&
            tester
                    .widget<FilledButton>(
                      find.byKey(const Key('sourceLoginResume')),
                    )
                    .onPressed !=
                null,
        'Ego screenshot ready',
        seconds: 120,
      );
      await tapVisible(tester, find.byKey(const Key('sourceLoginResume')));
      await wait(
        tester,
        () => find.textContaining('试跑成功').evaluate().isNotEmpty,
        'real trial resume',
        seconds: 180,
      );
      await tapVisible(tester, find.byKey(const Key('sourceLoginReturn')));
      await wait(
        tester,
        () =>
            find.byType(ChatView).evaluate().isNotEmpty &&
            find.byType(CustomSourcesView).evaluate().isEmpty,
        'return chat',
      );
      // Stop only this newly created test source; preserve source history as evidence.
      await api.update(id, {'enabled': false});
      debugPrint('NATIVE_LIVE PASS source=$id');
      await addFeed(tester, api, chat);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await prefs.clear();
      for (final e in before.entries) {
        final v = e.value;
        if (v is String) {
          await prefs.setString(e.key, v);
        } else if (v is int) {
          await prefs.setInt(e.key, v);
        } else if (v is bool) {
          await prefs.setBool(e.key, v);
        } else if (v is double) {
          await prefs.setDouble(e.key, v);
        } else if (v is List<String>) {
          await prefs.setStringList(e.key, v);
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}

Future<void> wait(
  WidgetTester tester,
  bool Function() ready,
  String phase, {
  int seconds = 45,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    if (ready()) {
      debugPrint('NATIVE_LIVE phase $phase');
      return;
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  fail('Native live timeout: $phase');
}

Future<void> addFeed(
  WidgetTester tester,
  CustomSourcesApi api,
  ChatProvider chat,
) async {
  final name = 'RSS 原生验收 ${DateTime.now().millisecondsSinceEpoch}';
  final prompt =
      '新建一个独立订阅来源，名称“$name”，使用 https://www.ruanyifeng.com/blog/atom.xml ，收最新文章标题、链接、作者和摘要，每轮最多3条，每5分钟一次，候选池份额1。无需登录。用 HTTP 订阅源执行器真实试跑后提交激活审批，不修改已有来源。';
  await wait(
    tester,
    () => !chat.responding,
    'chat ready for feed',
    seconds: 90,
  );
  await tester.tap(find.byKey(const Key('chatMessageInput')));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(find.byKey(const Key('chatMessageInput')), prompt);
  await tester.tap(find.byKey(const Key('chatSend')));
  FocusManager.instance.primaryFocus?.unfocus();
  await wait(
    tester,
    () {
      final own = chat.turns.where((t) => t.message == prompt);
      if (own.any((t) => t.hasError)) {
        fail('Feed turn failed: ${own.first.error}');
      }
      return chat.approvals.any(
        (a) =>
            a['status'] == 'pending' && a['summary'].toString().contains(name),
      );
    },
    'feed approval',
    seconds: 300,
  );
  final approval = chat.approvals.firstWhere(
    (a) => a['status'] == 'pending' && a['summary'].toString().contains(name),
  );
  await tester.tap(find.byKey(const Key('chatApprovals')));
  await tester.pump(const Duration(seconds: 1));
  final approve = find.byKey(Key('approve-${approval['approval_id']}'));
  await tester.scrollUntilVisible(
    approve,
    300,
    scrollable: find.byType(Scrollable).last,
    maxScrolls: 30,
  );
  await tester.tap(approve);
  await wait(
    tester,
    () => chat.approvals.any(
      (a) =>
          a['approval_id'] == approval['approval_id'] &&
          a['status'] == 'executed',
    ),
    'feed activated',
    seconds: 120,
  );
  await tester.tap(find.byTooltip('关闭审批'));
  await tester.pump(const Duration(seconds: 1));
  final source = sourceMaps(
    (await api.list())['items'],
  ).firstWhere((s) => s['name'] == name);
  final id = source['source_id'].toString();
  try {
    expect(
      sourceMaps(
        source['workflows'],
      ).every((w) => w['executor'] == 'http' && w['kind'] == 'feed'),
      true,
    );
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    var collected = false;
    while (DateTime.now().isBefore(deadline)) {
      final runs = sourceMaps((await api.runs(id))['items']);
      if (runs.any((r) => (r['discovered_count'] as num? ?? 0) > 0)) {
        debugPrint('NATIVE_LIVE FEED collected source=$id ${jsonEncode(runs)}');
        collected = true;
        break;
      }
      await tester.pump(const Duration(seconds: 3));
    }
    expect(collected, true);
  } finally {
    await api.update(id, {'enabled': false});
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 12 && finder.hitTestable().evaluate().isEmpty; i++) {
    final element = finder.evaluate().first;
    final scroll = Scrollable.maybeOf(element);
    if (scroll == null) break;
    final below =
        tester.getCenter(finder).dy >
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 2;
    await tester.drag(
      find.byWidget(scroll.widget),
      Offset(0, below ? -220 : 220),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'Target must be physically tappable',
  );
  await tester.tap(finder.hitTestable());
}
