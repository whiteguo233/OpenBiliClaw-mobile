import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/native_bilibili_video_page.dart';
import 'package:openbiliclaw_app/widgets/bilibili_comment_widgets.dart';
import '../test/fixtures/bilibili_player_video.dart';

/// Exercises the real page and native player using a local silent clip and
/// deterministic API responses. No Bilibili login or account writes are used.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  for (final dark in [false, true]) {
    testWidgets(
      'native player layout, comment retry and keyboard (${dark ? 'dark' : 'light'})',
      (tester) async {
        final errorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrintStack(
            label: details.exceptionAsString(),
            stackTrace: details.stack,
          );
          errorHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = errorHandler);
        SharedPreferences.setMockInitialValues({});
        final videoBytes = base64Decode(bilibiliPlayerVideoBase64);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final subscription = server.listen((request) async {
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.contentLength = videoBytes.length;
          request.response.add(videoBytes);
          await request.response.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await server.close(force: true);
        });
        var playRequests = 0;
        var commentRequests = 0;
        const title = '把日常拍成电影：普通人的生活，也值得认真记录';
        final mock = MockClient((request) async {
          Object payload;
          final path = request.url.path;
          if (path.endsWith('/player/play-url')) {
            playRequests++;
            payload = {
              'bvid': 'BVfixture', 'cid': 1,
              'video': {
                'url': 'http://127.0.0.1:${server.port}/video.mp4',
                'qn': 32,
                'width': 640,
                'height': 360,
              },
              // Empty quality options must still allow playback settings to open.
              'qualities': [],
              'pages': [
                for (var i = 1; i <= 4; i++)
                  {'cid': i, 'page': i, 'part': '发现生活中的光线与色彩', 'duration': 30},
              ],
            };
          } else if (path.endsWith('/video/info')) {
            payload = {
              'title': title,
              'desc': '从光线、构图到声音，分享几个让日常画面更有故事感的小技巧。',
              'pubdate': 1789884000,
              'owner': {'mid': 42, 'name': '日常记录所'},
              'stat': {
                'view': 283400,
                'danmaku': 1256,
                'like': 16400,
                'coin': 3680,
                'favorite': 8100,
                'reply': 128,
              },
            };
          } else if (path.endsWith('/user/card')) {
            payload = {
              'mid': 42,
              'name': '日常记录所',
              'fans': 128000,
              'following': false,
            };
          } else if (path.endsWith('/video/relation')) {
            payload = {'like': false, 'favorite': false, 'coin': 0};
          } else if (path.endsWith('/video/related')) {
            payload = {
              'items': [
                for (var i = 1; i <= 5; i++)
                  {
                    'bvid': 'BVrelated$i',
                    'title': '普通人也能学会的摄影构图，让画面更有故事感',
                    'duration': 325,
                    'owner': {'name': '影像生活'},
                    'stat': {'view': 54600, 'danmaku': 386},
                  },
              ],
            };
          } else if (path.endsWith('/video/comment-replies')) {
            payload = {
              'items': [
                {
                  'rpid': 2,
                  'uname': '日常记录所',
                  'message': '期待你的作品，一起记录生活呀。',
                  'like_count': 42,
                },
              ],
              'total': 1,
              'page': 1,
              'has_more': false,
            };
          } else if (path.endsWith('/auth/export')) {
            return http.Response('{"error":"fixture has no login"}', 404);
          } else if (path.endsWith('/video/comments')) {
            commentRequests++;
            if (commentRequests == 1) {
              return http.Response('{"error":"offline fixture"}', 503);
            }
            payload = {
              'items': [
                {
                  'rpid': 1,
                  'uname': '今天也要开心',
                  'message': '原来生活里的小事，也能拍得这么温柔。周末就带上相机出门试试看！',
                  'like_count': 328,
                  'reply_count': 12,
                  'replies': [
                    {'rpid': 2, 'uname': '日常记录所', 'message': '期待你的作品，一起记录生活呀。'},
                  ],
                },
                {
                  'rpid': 3,
                  'uname': '慢慢来',
                  'message': '最后一段的光线好美，已经收藏了。',
                  'like_count': 126,
                },
              ],
              'total': 128,
              'page': 1,
              'has_more': false,
            };
          } else {
            fail('Unexpected fixture request: ${request.method} $path');
          }
          return http.Response(
            jsonEncode(payload),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final client = ApiClient(
          host: '127.0.0.1',
          port: server.port,
          directClientFactory: () => mock,
        );
        await tester.pumpWidget(
          Provider<ApiClient>.value(
            value: client,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: const NativeBilibiliVideoPage(
                bvid: 'BVfixture',
                title: title,
              ),
            ),
          ),
        );
        await _until(
          tester,
          () =>
              find.byType(Video).evaluate().isNotEmpty &&
              find.text('12.8万粉丝').evaluate().isNotEmpty,
        );
        final controller = tester.widget<Video>(find.byType(Video)).controller;
        await _until(
          tester,
          () =>
              controller.player.state.position.inMilliseconds > 0 &&
              !controller.player.state.buffering,
        );
        await controller.player.pause();
        await tester.pump(const Duration(seconds: 1));
        expect(playRequests, 1);
        expect(find.byKey(const ValueKey('bilibili-like')), findsOneWidget);
        await binding.takeScreenshot(
          'player-introduction-${dark ? 'dark' : 'light'}',
        );

        await tester.tap(find.byTooltip('更多'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('稍后再看'), findsOneWidget);
        expect(find.text('一键三连'), findsOneWidget);
        await tester.tap(find.text('播放设置'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('倍速'), findsOneWidget);
        Navigator.of(tester.element(find.text('播放设置'))).pop();
        await tester.pump(const Duration(milliseconds: 500));

        await tester.tap(
          find.descendant(
            of: find.byType(TabBar),
            matching: find.textContaining('评论'),
          ),
        );
        await _until(
          tester,
          () => find.text('评论加载失败，点击重试').hitTestable().evaluate().isNotEmpty,
        );
        await tester.tap(find.text('评论加载失败，点击重试'));
        await _until(tester, () => find.text('今天也要开心').evaluate().isNotEmpty);
        expect(
          identical(
            tester.widget<Video>(find.byType(Video)).controller,
            controller,
          ),
          isTrue,
        );
        expect(
          playRequests,
          1,
          reason: 'Changing tabs must not reload the video',
        );
        expect(commentRequests, 2);
        await binding.takeScreenshot(
          'player-comments-${dark ? 'dark' : 'light'}',
        );

        await tester.tap(find.text('共 12 条回复 ›'));
        await _until(tester, () => find.text('回复 1').evaluate().isNotEmpty);
        await tester.showKeyboard(find.byType(TextField).last);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(find.byType(TextField).last.hitTestable(), findsOneWidget);
        await binding.takeScreenshot(
          'player-replies-${dark ? 'dark' : 'light'}',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(tester.element(find.text('回复 1'))).pop();
        await _until(tester, () => find.text('回复 1').evaluate().isEmpty);

        await tester.showKeyboard(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '先保存为草稿');
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.byType(BilibiliCommentComposer).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(
          'player-keyboard-${dark ? 'dark' : 'light'}',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await _until(tester, () => tester.view.viewInsets.bottom == 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 500));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 150; i++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for player fixture');
}
