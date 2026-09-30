import 'dart:convert';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import 'package:openbiliclaw_app/api/bilibili_api.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/native_bilibili_video_page.dart';
import 'package:openbiliclaw_app/widgets/bilibili_comment_widgets.dart';
import 'package:openbiliclaw_app/widgets/bilibili_video_introduction.dart';
import 'package:openbiliclaw_app/widgets/danmaku_overlay.dart';

/// Real backend, real Bilibili requests, and native media decoding. No fixtures
/// or mocked transport. Account writes are deliberately outside this suite.
///
/// flutter drive --driver test_driver/bilibili_player_live.dart \
///   --target integration_test/bilibili_player_live_e2e_test.dart \
///   --dart-define=BILIBILI_E2E_BASE_URL=http://127.0.0.1:18420 -d DEVICE_ID
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  MediaKit.ensureInitialized();
  final backend = Uri.parse(
    const String.fromEnvironment(
      'BILIBILI_E2E_BASE_URL',
      defaultValue: 'http://127.0.0.1:8420',
    ),
  );
  final requests = <Map<String, Object?>>[];
  final checks = <Map<String, Object?>>[];
  binding.reportData = {
    'live': {'requests': requests, 'checks': checks},
  };

  ApiClient client() => ApiClient(
    scheme: backend.scheme,
    host: backend.host,
    port: backend.port,
    basePath: backend.path,
    directClientFactory: () => _RecordingClient(
      defaultTargetPlatform == TargetPlatform.iOS
          ? CupertinoClient.defaultSessionConfiguration()
          : http.Client(),
      requests,
    ),
  );

  void record(String name, [Map<String, Object?> details = const {}]) {
    final result = {'check': name, ...details};
    checks.add(result);
    debugPrint('LIVE ${jsonEncode(result)}');
  }

  Future<void> open(
    WidgetTester tester,
    String bvid, {
    bool dark = false,
  }) async {
    final apiClient = client();
    final status = await BilibiliApi(apiClient).authStatus();
    record('backend_auth', {'status': status.state.apiValue});
    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: apiClient,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: NativeBilibiliVideoPage(bvid: bvid, title: '加载中'),
        ),
      ),
    );
    await _until(tester, 'video and creator data', () {
      final intro = find.byType(BilibiliVideoIntroduction);
      return find.byType(Video).evaluate().isNotEmpty &&
          intro.evaluate().isNotEmpty &&
          tester.widget<BilibiliVideoIntroduction>(intro).title != '加载中' &&
          find.textContaining('粉丝').evaluate().isNotEmpty;
    });
    final player = tester.widget<Video>(find.byType(Video)).controller.player;
    // Saved position alone is not proof of playback: require actual progress.
    await _until(tester, 'native playback progress', () {
      return player.state.position.inMilliseconds > 500 &&
          (player.state.width ?? 0) > 0 &&
          !player.state.buffering;
    });
    if (player.state.position > const Duration(seconds: 10)) {
      await player.seek(Duration.zero);
      await _until(
        tester,
        'reset saved position',
        () => player.state.position < const Duration(seconds: 2),
      );
      await player.play();
    }
    final startedAt = player.state.position;
    await _until(tester, 'three seconds of decoded playback', () {
      return player.state.position - startedAt > const Duration(seconds: 3) &&
          !player.state.buffering;
    });
    record('native_playback', {
      'bvid': bvid,
      'width': player.state.width,
      'height': player.state.height,
      'position_ms': player.state.position.inMilliseconds,
      'advanced_ms': (player.state.position - startedAt).inMilliseconds,
    });
    expect(tester.takeException(), isNull);
  }

  testWidgets('live portrait player, comments, fullscreen and related video', (
    tester,
  ) async {
    const bvid = 'BV19XkQY2EES';
    await open(tester, bvid);
    final player = tester.widget<Video>(find.byType(Video)).controller.player;
    final intro = tester.widget<BilibiliVideoIntroduction>(
      find.byType(BilibiliVideoIntroduction),
    );
    expect(intro.viewCount, greaterThan(0));
    expect(find.byKey(const ValueKey('bilibili-like')), findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.byType(Video)).bottom,
      lessThan(screen.height - 200),
    );
    await _until(tester, 'real danmaku', () {
      return tester
          .widget<DanmakuOverlay>(find.byType(DanmakuOverlay))
          .items
          .isNotEmpty;
    });
    record('portrait_layout_and_danmaku', {
      'items': tester
          .widget<DanmakuOverlay>(find.byType(DanmakuOverlay))
          .items
          .length,
      'title_from_backend': intro.title != '加载中',
    });
    await binding.takeScreenshot('live-portrait-introduction');

    await tester.tap(find.byKey(const ValueKey('bilibili-video-title')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(bvid), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bilibili-video-title')));
    await tester.pump(const Duration(milliseconds: 300));

    // Playback settings use the real stream's available qualities.
    await tester.tap(find.byTooltip('更多'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('一键三连'), findsOneWidget);
    await tester.tap(find.text('播放设置'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('清晰度'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<double>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('1.5x').last);
    await _until(tester, 'playback speed', () => player.state.rate == 1.5);
    await tester.tap(find.byType(DropdownButtonFormField<double>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('1.0x').last);
    await _until(
      tester,
      'restore playback speed',
      () => player.state.rate == 1,
    );
    Navigator.of(tester.element(find.text('播放设置'))).pop();
    await tester.pump(const Duration(milliseconds: 500));
    record('playback_speed');

    final playRequestsBeforeTabs = _playRequests(requests);
    await _tab(tester, '评论');
    await _until(
      tester,
      'real comments',
      () => find.byType(BilibiliCommentTile).evaluate().isNotEmpty,
    );
    final firstComment = tester
        .widget<BilibiliCommentTile>(find.byType(BilibiliCommentTile).first)
        .comment;
    expect(firstComment.rpid, greaterThan(0));
    expect(firstComment.message, isNotEmpty);
    await binding.takeScreenshot('live-comments');
    record('real_comments', {'first_rpid': firstComment.rpid});

    // Open replies through the UI, then focus the native keyboard without posting.
    final thread = find
        .byWidgetPredicate(
          (widget) =>
              widget is BilibiliCommentTile && widget.comment.replyCount > 0,
        )
        .first;
    await tester.ensureVisible(thread);
    await tester.tap(find.descendant(of: thread, matching: find.text('回复')));
    await _until(
      tester,
      'real reply sheet',
      () =>
          find.byTooltip('关闭').evaluate().isNotEmpty &&
          find.textContaining('回复 ').evaluate().isNotEmpty,
    );
    await _until(
      tester,
      'reply rows',
      () =>
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(BilibiliAvatar),
              )
              .evaluate()
              .length >
          1,
    );
    await tester.showKeyboard(find.byType(TextField).last);
    await _until(
      tester,
      'reply keyboard',
      () => tester.view.viewInsets.bottom > 0,
    );
    expect(find.byType(TextField).last.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('live-replies-keyboard');
    await tester.tap(find.byTooltip('关闭'));
    await _until(
      tester,
      'reply sheet closed',
      () =>
          find.byTooltip('关闭').evaluate().isEmpty &&
          tester.view.viewInsets.bottom == 0,
    );

    const draft = '仅本机输入测试，未发送';
    await tester.enterText(find.byType(TextField), draft);
    await _until(
      tester,
      'main comment keyboard',
      () => tester.view.viewInsets.bottom > 0,
    );
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.takeScreenshot('live-comment-draft');
    FocusManager.instance.primaryFocus?.unfocus();
    await _until(
      tester,
      'keyboard closed',
      () => tester.view.viewInsets.bottom == 0,
    );
    await _tab(tester, '简介');
    await _tab(tester, '评论');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      draft,
    );
    expect(_playRequests(requests), playRequestsBeforeTabs);
    expect(
      identical(
        tester.widget<Video>(find.byType(Video)).controller.player,
        player,
      ),
      isTrue,
    );
    await tester.enterText(find.byType(TextField), '');
    FocusManager.instance.primaryFocus?.unfocus();
    await _until(
      tester,
      'draft keyboard closed',
      () => tester.view.viewInsets.bottom == 0,
    );
    record('reply_keyboard_and_draft_preservation');

    final commentsScroll = find.byKey(
      const PageStorageKey('bilibili-comments'),
    );
    int commentCount() => tester
        .widget<SliverList>(
          find.descendant(
            of: commentsScroll,
            matching: find.byType(SliverList),
          ),
        )
        .delegate
        .estimatedChildCount!;
    final initialCount = commentCount();
    for (
      var attempt = 0;
      attempt < 25 && commentCount() <= initialCount;
      attempt++
    ) {
      await tester.drag(commentsScroll, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _until(
      tester,
      'real comment pagination',
      () => commentCount() > initialCount,
    );
    record('comment_pagination', {
      'before': initialCount,
      'after': commentCount(),
    });

    // Fullscreen reuses the same playing video and supports real comments.
    await _tab(tester, '简介');
    await tester.tapAt(tester.getRect(find.byType(Video)).center);
    await _until(
      tester,
      'fullscreen control',
      () => find.byIcon(Icons.fullscreen).hitTestable().evaluate().isNotEmpty,
    );
    await tester.tap(find.byIcon(Icons.fullscreen));
    await _until(
      tester,
      'fullscreen page',
      () => find.byTooltip('退出全屏').hitTestable().evaluate().isNotEmpty,
    );
    await _until(
      tester,
      'fullscreen transition completed',
      () =>
          ModalRoute.of(
            tester.element(find.byTooltip('退出全屏')),
          )!.animation!.isCompleted &&
          find.byTooltip('查看评论').hitTestable().evaluate().isNotEmpty,
    );
    await binding.takeScreenshot('live-fullscreen');
    await tester.tap(find.byTooltip('查看评论'));
    await _until(
      tester,
      'fullscreen comment rows',
      () =>
          find.byTooltip('关闭').evaluate().isNotEmpty &&
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(BilibiliCommentTile),
              )
              .evaluate()
              .isNotEmpty,
    );
    await tester.tap(find.byTooltip('关闭'));
    await _until(
      tester,
      'fullscreen comments closed',
      () => find.byTooltip('关闭').evaluate().isEmpty,
    );
    if (find.byTooltip('退出全屏').hitTestable().evaluate().isEmpty) {
      await tester.tapAt(tester.getRect(find.byType(Video)).center);
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.byTooltip('退出全屏'));
    await _until(
      tester,
      'return from fullscreen',
      () =>
          find.byType(BilibiliVideoIntroduction).evaluate().isNotEmpty &&
          find.byTooltip('退出全屏').evaluate().isEmpty,
    );
    expect(_playRequests(requests), playRequestsBeforeTabs);
    record('fullscreen_and_comments');
    await player.play();

    await _until(
      tester,
      'real related videos',
      () => tester
          .widget<BilibiliVideoIntroduction>(
            find.byType(BilibiliVideoIntroduction),
          )
          .related
          .isNotEmpty,
    );
    final related = tester
        .widget<BilibiliVideoIntroduction>(
          find.byType(BilibiliVideoIntroduction),
        )
        .related
        .first;
    final relatedCard = find.text(related.title).hitTestable();
    // Lazy slivers build rows outside the viewport. Wait for actual hit
    // testing after each scroll/compact-player animation, not just existence.
    for (
      var attempt = 0;
      attempt < 20 && relatedCard.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(
        find.byKey(const PageStorageKey('bilibili-introduction')),
        const Offset(0, -200),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(relatedCard, findsOneWidget);
    await tester.tap(relatedCard);
    await _until(tester, 'related video decoding', () {
      if (find.byType(Video).evaluate().isEmpty) return false;
      final next = tester.widget<Video>(find.byType(Video)).controller.player;
      return !identical(next, player) &&
          next.state.position.inMilliseconds > 1000 &&
          !next.state.buffering;
    });
    expect(player.state.playing, isFalse);
    record('related_video_playback', {'bvid': related.bvid});
    await tester.tap(find.byTooltip('返回'));
    await _until(
      tester,
      'original player resumes',
      () =>
          player.state.playing &&
          find.byType(BilibiliVideoIntroduction).evaluate().length == 1 &&
          tester
                  .widget<BilibiliVideoIntroduction>(
                    find.byType(BilibiliVideoIntroduction),
                  )
                  .bvid ==
              bvid,
    );
    final resumedAt = player.state.position;
    await _until(
      tester,
      'resumed playback progress',
      () =>
          player.state.position - resumedAt > const Duration(seconds: 1) &&
          !player.state.buffering,
    );
    record('return_resumes_original_player', {
      'advanced_ms': (player.state.position - resumedAt).inMilliseconds,
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 7)));

  testWidgets('live multipart selection and stream switch in dark theme', (
    tester,
  ) async {
    const bvid = 'BV1Eb411u7Fw';
    await open(tester, bvid, dark: true);
    final intro = tester.widget<BilibiliVideoIntroduction>(
      find.byType(BilibiliVideoIntroduction),
    );
    expect(intro.pages.length, greaterThan(1));
    final target = intro.pages[1];
    await tester.scrollUntilVisible(
      find.text('选集'),
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('bilibili-introduction')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('选集'));
    await tester.pump(const Duration(milliseconds: 400));
    await binding.takeScreenshot('live-episode-picker');
    await tester.tap(find.text(target.part).last);
    await _until(
      tester,
      'selected episode data',
      () =>
          tester
                  .widget<BilibiliVideoIntroduction>(
                    find.byType(BilibiliVideoIntroduction),
                  )
                  .selectedCid ==
              target.cid &&
          !tester
              .widget<BilibiliVideoIntroduction>(
                find.byType(BilibiliVideoIntroduction),
              )
              .switchingPage,
    );
    final player = tester.widget<Video>(find.byType(Video)).controller.player;
    final startedAt = player.state.position;
    await _until(
      tester,
      'second episode playback progress',
      () =>
          player.state.position - startedAt > const Duration(seconds: 3) &&
          !player.state.buffering,
    );
    expect(
      requests.any((r) => r['cid'] == target.cid && r['status'] == 200),
      isTrue,
    );
    await binding.takeScreenshot('live-episode-playing-dark');
    record('multipart_switch', {
      'pages': intro.pages.length,
      'selected_page': target.page,
      'cid': target.cid,
      'advanced_ms': (player.state.position - startedAt).inMilliseconds,
    });

    await tester.tap(find.byTooltip('更多'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('播放设置'));
    await tester.pump(const Duration(milliseconds: 400));
    final qualityField = find.byType(DropdownButtonFormField<int>).first;
    final qualityOptions = tester
        .widget<DropdownButton<int>>(
          find.descendant(
            of: qualityField,
            matching: find.byType(DropdownButton<int>),
          ),
        )
        .items!;
    final lowerQuality = qualityOptions.firstWhere((item) => item.value == 32);
    final qualityLabel = (lowerQuality.child as Text).data!;
    await tester.tap(qualityField);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(qualityLabel).last);
    await _until(
      tester,
      'real quality switch',
      () =>
          requests.any(
            (row) =>
                row['bvid'] == bvid &&
                row['cid'] == target.cid &&
                row['qn'] == 32 &&
                row['status'] == 200,
          ) &&
          (player.state.height ?? 1080) <= 480 &&
          !player.state.buffering,
    );
    Navigator.of(tester.element(find.text('播放设置'))).pop();
    await tester.pump(const Duration(milliseconds: 400));
    final qualityStartedAt = player.state.position;
    await _until(
      tester,
      'lower quality playback',
      () =>
          player.state.position - qualityStartedAt >
              const Duration(seconds: 3) &&
          !player.state.buffering,
    );
    record('quality_switch', {
      'qn': 32,
      'width': player.state.width,
      'height': player.state.height,
      'advanced_ms': (player.state.position - qualityStartedAt).inMilliseconds,
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

int _playRequests(List<Map<String, Object?>> requests) =>
    requests.where((r) => r['path'] == '/api/bilibili/player/play-url').length;

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(TabBar),
      matching: find.textContaining(label),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _until(
  WidgetTester tester,
  String name,
  bool Function() ready,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 75));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (ready()) return;
  }
  fail('Timed out: $name');
}

/// Delegates every allowed request to the platform's real network transport.
/// The report contains neither credentials, response bodies nor signed URLs.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.inner, this.requests);
  final http.Client inner;
  final List<Map<String, Object?>> requests;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (request.method != 'GET' &&
        !(request.method == 'POST' &&
            (path.endsWith('/player/play-url') ||
                path.endsWith('/auth/export')))) {
      throw StateError('Live player suite does not allow account writes');
    }
    final row = <String, Object?>{'method': request.method, 'path': path};
    if (path.endsWith('/player/play-url') && request is http.Request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      for (final key in ['bvid', 'cid', 'qn']) {
        if (body.containsKey(key)) row[key] = body[key];
      }
    }
    requests.add(row);
    final clock = Stopwatch()..start();
    try {
      final response = await inner.send(request);
      row['status'] = response.statusCode;
      return response;
    } finally {
      row['elapsed_ms'] = clock.elapsedMilliseconds;
      debugPrint('LIVE_REQUEST ${jsonEncode(row)}');
    }
  }

  @override
  void close() => inner.close();
}
