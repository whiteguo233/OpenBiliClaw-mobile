import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import 'package:openbiliclaw_app/api/bilibili_api.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/views/native_bilibili_video_page.dart';

/// Real-environment E2E for the UP card / follow strip on the native player.
///
/// Runs against the real OpenBiliClaw backend (127.0.0.1:8420) with the real
/// Bilibili Cookie and performs real follow / unfollow requests on the video
/// owner. The original relation state is restored through the API in a
/// `finally` block, so a failure mid-test cannot leave the account changed.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  const bvid = 'BV1xx411c7mD';

  testWidgets('真实后端：UP 主信息条与关注/取关真实请求（状态自动还原）', (tester) async {
    final client = ApiClient(host: '127.0.0.1', port: 8420);
    final api = BilibiliApi(client);

    final info = await api.videoInfo(bvid: bvid);
    final rawOwner = info['owner'];
    expect(rawOwner, isA<Map>(), reason: 'video/info 必须返回 owner');
    final owner = Map<String, dynamic>.from(rawOwner as Map);
    final mid = (owner['mid'] as num).toInt();
    final ownerName = owner['name']?.toString().trim() ?? '';
    expect(mid, greaterThan(0));
    expect(ownerName, isNotEmpty);

    final initial = await api.userCard(mid: mid);
    debugPrint(
      'E2E up: mid=$mid name=$ownerName initialFollowing=${initial.following}',
    );

    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: client,
        child: const MaterialApp(
          home: NativeBilibiliVideoPage(bvid: bvid, title: 'UP 主信息条真实端到端测试'),
        ),
      ),
    );

    // Interaction row proves the page loaded; the owner row follows the
    // asynchronous video/info request.
    await _pumpUntil(tester, () async {
      return find.textContaining('点赞').evaluate().isNotEmpty &&
          find.text(ownerName).evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 45));
    expect(find.text(ownerName), findsOneWidget);

    // The fan count only exists on the user-card enrichment call.
    await _pumpUntil(tester, () async {
      return find.textContaining('粉丝').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));

    final expectedLabel = initial.following ? '已关注' : '关注';
    final expectedButton = initial.following
        ? find.widgetWithText(OutlinedButton, '已关注')
        : find.widgetWithText(FilledButton, '关注');
    await _pumpUntil(tester, () async {
      return expectedButton.evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 30));
    debugPrint('E2E up: follow button rendered as $expectedLabel');

    try {
      if (!initial.following) {
        // Follow through the UI, verify upstream state, then unfollow and
        // verify the account is restored to the original state.
        await tester.tap(find.widgetWithText(FilledButton, '关注'));
        await _pumpUntil(tester, () async {
          return find
              .widgetWithText(OutlinedButton, '已关注')
              .evaluate()
              .isNotEmpty;
        }, timeout: const Duration(seconds: 45));
        expect(
          (await api.userCard(mid: mid)).following,
          isTrue,
          reason: '点击关注后 B 站关系应为已关注',
        );

        await tester.tap(find.widgetWithText(OutlinedButton, '已关注'));
        await _pumpUntil(tester, () async {
          return find.text('取消关注').evaluate().isNotEmpty;
        }, timeout: const Duration(seconds: 10));
        await tester.tap(find.widgetWithText(FilledButton, '取消关注'));
        await _pumpUntil(tester, () async {
          return find
                  .widgetWithText(FilledButton, '关注')
                  .evaluate()
                  .isNotEmpty &&
              find.widgetWithText(OutlinedButton, '已关注').evaluate().isEmpty;
        }, timeout: const Duration(seconds: 45));
        expect(
          (await api.userCard(mid: mid)).following,
          isFalse,
          reason: '确认取关后 B 站关系应恢复为未关注',
        );
      } else {
        // Already followed: the first tap verifies the confirmation dialog can
        // be cancelled without changing state, then unfollow + follow restores
        // the original relation.
        await tester.tap(find.widgetWithText(OutlinedButton, '已关注'));
        await _pumpUntil(tester, () async {
          return find.text('取消关注').evaluate().isNotEmpty;
        }, timeout: const Duration(seconds: 10));
        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await _pumpUntil(tester, () async {
          return find.text('取消关注').evaluate().isEmpty &&
              find.widgetWithText(OutlinedButton, '已关注').evaluate().isNotEmpty;
        }, timeout: const Duration(seconds: 10));
        expect(
          (await api.userCard(mid: mid)).following,
          isTrue,
          reason: '取消对话框不应改变关注状态',
        );

        await tester.tap(find.widgetWithText(OutlinedButton, '已关注'));
        await _pumpUntil(tester, () async {
          return find.text('取消关注').evaluate().isNotEmpty;
        }, timeout: const Duration(seconds: 10));
        await tester.tap(find.widgetWithText(FilledButton, '取消关注'));
        await _pumpUntil(tester, () async {
          return find
                  .widgetWithText(FilledButton, '关注')
                  .evaluate()
                  .isNotEmpty &&
              find.widgetWithText(OutlinedButton, '已关注').evaluate().isEmpty;
        }, timeout: const Duration(seconds: 45));
        expect(
          (await api.userCard(mid: mid)).following,
          isFalse,
          reason: '确认取关后 B 站关系应为未关注',
        );

        await tester.tap(find.widgetWithText(FilledButton, '关注'));
        await _pumpUntil(tester, () async {
          return find
              .widgetWithText(OutlinedButton, '已关注')
              .evaluate()
              .isNotEmpty;
        }, timeout: const Duration(seconds: 45));
        expect(
          (await api.userCard(mid: mid)).following,
          isTrue,
          reason: '重新关注后应恢复测试前的关注状态',
        );
      }

      debugPrint('E2E up: real follow/unfollow round-trip verified');
    } finally {
      // Do not rely on the UI reaching its final state: always restore the
      // original relation via the API if the test failed halfway.
      try {
        final current = await api.userCard(mid: mid);
        if (current.following != initial.following) {
          await api.followUser(mid: mid, follow: initial.following);
          debugPrint(
            'E2E up: restored following=${initial.following} after test',
          );
        }
      } catch (error) {
        debugPrint('E2E up: failed to restore relation: $error');
      }
    }

    // Layout regression: opening the comment composer raises the keyboard on a
    // phone-sized screen. The player height budget must shrink so the lower
    // Column keeps enough room instead of throwing RenderFlex overflows.
    await tester.pump(const Duration(seconds: 5)); // 等关注 SnackBar 消失
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.textContaining('评论'),
      ),
    );
    await _pumpUntil(tester, () async {
      return find.byType(TextField).evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 20));
    await tester.ensureVisible(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 500));
    final videoHeightBeforeKeyboard = tester.getRect(find.byType(Video)).height;
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      final videoHeightWithKeyboard = tester.getRect(find.byType(Video)).height;
      expect(
        videoHeightWithKeyboard,
        lessThan(videoHeightBeforeKeyboard - 40),
        reason: '键盘弹出后播放器应为评论区让出高度',
      );
    }
    debugPrint('E2E up: comment composer layout with keyboard verified');
  }, timeout: const Timeout(Duration(minutes: 8)));
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
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .take(40)
      .toList();
  fail('等待条件超时（$timeout）；visible texts=$texts');
}
