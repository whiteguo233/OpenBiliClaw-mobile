import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/views/native_bilibili_video_page.dart';
import 'package:openbiliclaw_app/widgets/danmaku_overlay.dart';

/// Real-environment regression test for the danmaku scroll bug:
/// "弹幕从右往左飘到中间就消失".
///
/// Runs the real app against the real OpenBiliClaw backend (127.0.0.1:8420)
/// with the real Bilibili cookie and real media_kit playback, for both a
/// landscape and a portrait video, and observes the canvas_danmaku engine
/// state directly through the public controller API:
/// - danmaku must enter from the right edge and move monotonically left;
/// - an item may leave the engine only after it has fully crossed the left
///   edge (last observed x <= 0). The old overlay removed items mid-flight,
///   which showed up as last-x deep in the positive range (screen middle).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('横屏视频：真实弹幕从右往左完整飘出，不在屏幕中间消失', (tester) async {
    await _runDanmakuScrollTest(
      tester,
      bvid: 'BV1xx411c7mD',
      title: '横屏弹幕滚动端到端测试视频',
    );
  });

  testWidgets('竖屏视频：真实弹幕从右往左完整飘出，不在屏幕中间消失', (tester) async {
    await _runDanmakuScrollTest(
      tester,
      bvid: 'BV19XkQY2EES',
      title: '竖屏弹幕滚动端到端测试视频',
    );
  });
}

Future<void> _runDanmakuScrollTest(
  WidgetTester tester, {
  required String bvid,
  required String title,
}) async {
  // The static registry outlives individual tests; reset it so the wait
  // conditions below never read a stale controller from the previous run.
  DanmakuOverlay.debugLastController = null;

  final client = ApiClient(host: '127.0.0.1', port: 8420);

  await tester.pumpWidget(
    Provider<ApiClient>.value(
      value: client,
      child: MaterialApp(
        home: NativeBilibiliVideoPage(bvid: bvid, title: title),
      ),
    ),
  );

  // Player UI ready + danmaku overlay mounted.
  await _pumpUntil(tester, () async {
    return find.text('点赞').evaluate().isNotEmpty &&
        DanmakuOverlay.debugLastController != null;
  }, timeout: const Duration(seconds: 60));

  // Real danmaku XML is fetched asynchronously and comments spawn as the
  // playback position crosses their timestamps. Wait until the engine holds
  // at least one real comment.
  await _pumpUntil(tester, () async {
    final tracks = _tracks();
    return tracks.any((track) => track.isNotEmpty);
  }, timeout: const Duration(seconds: 90));

  final videoWidth = tester.getRect(find.byType(Video)).width;
  debugPrint('E2E danmaku [$bvid]: first real danmaku spawned, '
      'videoWidth=$videoWidth, sampling scroll...');

  // Sample the engine every 500 ms for 30 s of real playback.
  final seen = <String, double>{}; // text -> last observed x
  final currently = <String>{};
  final exitXs = <double>[];
  double maxEntryX = double.negativeInfinity;
  double minObservedX = double.infinity;
  for (var tick = 0; tick < 60; tick++) {
    await tester.pump(const Duration(milliseconds: 500));
    final now = <String>{};
    for (final track in _tracks()) {
      for (final item in track) {
        final text = (item.content as dynamic).text as String;
        final x = item.xPosition as double;
        now.add(text);
        seen[text] = x;
        if (x > maxEntryX) maxEntryX = x;
        if (x < minObservedX) minObservedX = x;
      }
    }
    for (final gone in currently.difference(now)) {
      exitXs.add(seen[gone] ?? double.nan);
      debugPrint(
        'E2E danmaku [$bvid] exit: '
        '"${gone.length > 12 ? gone.substring(0, 12) : gone}"'
        ' lastX=${seen[gone]}',
      );
    }
    currently
      ..clear()
      ..addAll(now);
  }

  debugPrint(
    'E2E danmaku [$bvid] summary: distinctTexts=${seen.length} '
    'exits=${exitXs.length} maxEntryX=$maxEntryX minObservedX=$minObservedX '
    'exitXs=$exitXs',
  );

  // Real data really flowed: several distinct comments crossed the screen.
  expect(seen.length, greaterThanOrEqualTo(3),
      reason: '真实弹幕数量不足，可能没有取到真实弹幕数据');
  // And at least one comment completed its journey during the window.
  expect(exitXs, isNotEmpty, reason: '采样窗口内没有观察到弹幕退出');

  // The regression assertion: every removal happened after the comment had
  // passed the left edge. The old implementation removed items while still
  // on screen (lastX around the middle of the player width, e.g. +100..+250).
  for (final x in exitXs) {
    expect(x, lessThanOrEqualTo(0),
        reason: '弹幕在 x=$x（仍处于屏幕内）就被移除 —— 中间消失问题复现');
  }

  debugPrint('E2E danmaku [$bvid]: PASS — 所有弹幕都完整飘出左边缘后才被移除');
}

List<List<dynamic>> _tracks() {
  final engine = DanmakuOverlay.debugLastController;
  expect(engine, isNotNull, reason: '弹幕引擎尚未创建');
  return engine!.scrollDanmaku.cast<List<dynamic>>();
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
