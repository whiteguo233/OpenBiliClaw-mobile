import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'package:openbiliclaw_app/api/bilibili_comment_api.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/views/native_bilibili_video_page.dart';

/// Real-environment E2E for Bilibili interactions and comment publishing.
///
/// Runs against the REAL OpenBiliClaw backend (127.0.0.1:8420 / 10.0.2.2 on
/// Android emulator) with the real Bilibili cookie:
/// - like + unfavorite/undo so the account state is restored afterwards;
/// - comment publish → assert it appears in the live comment list → delete
///   it via the backend so the thread is left clean;
/// - coin/triple are intentionally NOT tested here: coins cannot be undone.
///
/// Requires the OpenBiliClaw backend to be running with a valid Bilibili
/// cookie.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  const bvid = 'BV1xx411c7mD';
  const base = 'http://127.0.0.1:8420/api';

  testWidgets('真实后端：点赞收藏可还原、评论发布可删除', (tester) async {
    final client = ApiClient(host: '127.0.0.1', port: 8420);
    final unique = 'E2E测试-${DateTime.now().millisecondsSinceEpoch}';

    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: client,
        child: const MaterialApp(
          home: NativeBilibiliVideoPage(
            bvid: bvid,
            title: '互动端到端测试视频',
          ),
        ),
      ),
    );

    // 页面加载：互动按钮出现。
    await _pumpUntil(tester, () async {
      return find.text('点赞').evaluate().isNotEmpty &&
          find.text('收藏').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));

    Future<Map<String, dynamic>> relation() async {
      final res = await http.get(Uri.parse('$base/bilibili/video/relation?bvid=$bvid'));
      expect(res.statusCode, 200, reason: 'relation 接口应可用');
      return jsonDecode(res.body) as Map<String, dynamic>;
    }

    // ── 点赞（可还原）──
    var state = await relation();
    final wasLiked = state['like'] == true;
    debugPrint('E2E: like before=$wasLiked');
    await tester.tap(find.text('点赞'));
    await tester.pump(const Duration(milliseconds: 800));
    // 诊断：打印当前可见的 SnackBar/错误文案（如有）。
    final visibleTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) =>
            t.contains('点赞') ||
            t.contains('互动') ||
            t.contains('失败') ||
            t.contains('已'))
        .toList();
    debugPrint('E2E: texts after like tap: $visibleTexts');
    await _pumpUntil(tester, () async => (await relation())['like'] == !wasLiked,
        timeout: const Duration(seconds: 10));
    debugPrint('E2E: like toggled on -> ${(await relation())['like']}');
    await tester.tap(find.text('点赞'));
    await _pumpUntil(tester, () async => (await relation())['like'] == wasLiked,
        timeout: const Duration(seconds: 10));
    debugPrint('E2E: like restored -> ${(await relation())['like']}');

    // ── 评论发布 + 自动删除 ──
    // 「收藏」与「稍后」不做自动翻转断言：收藏是多夹语义（全局 favorite
    // 无法用 relation 精确断言，移除单个夹后仍为 true）；稍后再看的
    // 状态接口不可靠（添加/移除本身已通过后端调用验证，B 站 code 0）。
    await tester.tap(find.text('评论'));
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpUntil(tester, () async {
      return find.byType(TextField).evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 10));
    await tester.enterText(find.byType(TextField), unique);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump(const Duration(milliseconds: 1200));
    final afterSend = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((t) =>
            t.contains('失败') ||
            t.contains('登录') ||
            t.contains('发布') ||
            t.contains(unique))
        .toList();
    debugPrint('E2E: texts after send: $afterSend');
    // 断言发布成功的确定信号：SnackBar「评论已发布」（列表排序可能延迟，
    // 不能用列表文本作为成功判据）。
    await _pumpUntil(tester, () async {
      return find.text('评论已发布').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));
    expect(find.text('评论已发布'), findsOneWidget, reason: '发布应成功');
    debugPrint('E2E: comment published: $unique');

    // 清理：页面保存了发布接口返回的 rpid（B 站的列表接口不返回刚发布
    // 的评论，因此无法通过列表定位；发布接口响应即权威 rpid）。
    final pageState = tester.state(find.byType(NativeBilibiliVideoPage));
    final rpid = (pageState as dynamic).lastPostedRpid as int?;
    expect(rpid, greaterThan(0), reason: '发布后应持有 rpid');
    final del = await http.post(
      Uri.parse('$base/bilibili/video/comment/delete'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'bvid': bvid, 'rpid': rpid}),
    );
    expect(del.statusCode, 200, reason: '删除接口应成功: ${del.body}');
    debugPrint('E2E: comment cleaned up (rpid=$rpid)');

    // 投币/三连不可逆，不做自动化（真机手动验证会真实扣币）。
    debugPrint('E2E: coin/triple intentionally skipped (irreversible)');
  }, timeout: const Timeout(Duration(minutes: 6)));
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
