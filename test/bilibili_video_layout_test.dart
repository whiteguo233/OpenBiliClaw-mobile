import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/bilibili_interaction.dart';
import 'package:openbiliclaw_app/models/bilibili_play.dart';
import 'package:openbiliclaw_app/widgets/bilibili_comment_widgets.dart';
import 'package:openbiliclaw_app/widgets/bilibili_video_introduction.dart';
import 'package:openbiliclaw_app/widgets/bilibili_video_layout.dart';

const _capture = bool.fromEnvironment('CAPTURE_PLAYER_UI');
const _fontPath = String.fromEnvironment('PLAYER_UI_FONT');
const _title = '把日常拍成电影：普通人的生活，也值得认真记录';
const _description = '从光线、构图到声音，分享几个让日常画面更有故事感的小技巧。\n带上相机，一起出门走走吧。';
const _introKey = PageStorageKey('bilibili-introduction');
const _playerKey = ValueKey('bilibili-player-area');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Optional local screenshots use a supplied CJK font; CI needs no assets.
    if (_capture && _fontPath.isNotEmpty) {
      final font = FontLoader('PlayerCapture');
      font.addFont(
        Future.value(ByteData.sublistView(await File(_fontPath).readAsBytes())),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    Brightness brightness = Brightness.light,
    double textScale = 1,
    double keyboard = 0,
    double aspectRatio = 16 / 9,
    int selectedCid = 1,
    ValueChanged<BilibiliPlayPage>? onSelect,
    ValueChanged<BilibiliRelatedVideo>? onRelated,
    Future<String?> Function(String)? onSubmit,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: bilibiliVideoTheme(
          ThemeData(
            brightness: brightness,
            fontFamily: _capture && _fontPath.isNotEmpty
                ? 'PlayerCapture'
                : null,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 20),
            viewInsets: EdgeInsets.only(bottom: keyboard),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: _FixturePage(
          aspectRatio: aspectRatio,
          selectedCid: selectedCid,
          onSelect: onSelect,
          onRelated: onRelated,
          onSubmit: onSubmit,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectComments(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.textContaining('评论'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'player and tabs stay above the scrolling creator and video details',
    (tester) async {
      await pumpPage(tester);
      final player = tester.getRect(find.byKey(_playerKey));
      final tabs = tester.getRect(find.byType(TabBar));
      final creator = tester.getRect(find.text('日常记录所'));
      expect(tabs.top, player.bottom);
      expect(creator.top, greaterThan(tabs.bottom));
      expect(find.text(_description), findsNothing);
      await _captureScreen(tester, 'introduction-light');
      await tester.drag(find.byKey(_introKey), const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_playerKey)), player);
      expect(tester.getRect(find.byType(TabBar)), tabs);
      expect(find.text('日常记录所').hitTestable(), findsNothing);
    },
  );

  testWidgets(
    'tab changes retain expanded details, scroll position and comment draft',
    (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('bilibili-video-title')));
      await tester.pumpAndSettle();
      expect(find.text(_description), findsOneWidget);
      await selectComments(tester);
      await tester.enterText(find.byType(TextField), '保留这条评论草稿');
      await tester.tap(find.text('简介'));
      await tester.pumpAndSettle();
      expect(find.text(_description), findsOneWidget);
      await tester.drag(find.byKey(_introKey), const Offset(0, -300));
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(_introKey),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;
      await selectComments(tester);
      expect(find.text('保留这条评论草稿'), findsOneWidget);
      await tester.tap(find.text('简介'));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(_introKey),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position
            .pixels,
        scroll,
      );
    },
  );

  testWidgets(
    'portrait playback compacts for comments but ignores horizontal episode scrolling',
    (tester) async {
      await pumpPage(tester, aspectRatio: 9 / 16, size: const Size(390, 1100));
      final expanded = tester.getSize(find.byKey(_playerKey)).height;
      final episodeScroll = find.descendant(
        of: find.byKey(_introKey),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      );
      await tester.ensureVisible(episodeScroll);
      await tester.pumpAndSettle();
      final beforeHorizontal = tester.getSize(find.byKey(_playerKey)).height;
      await tester.drag(episodeScroll, const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_playerKey)).height, beforeHorizontal);
      await selectComments(tester);
      expect(tester.getSize(find.byKey(_playerKey)).height, lessThan(expanded));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('episode sheet exposes every part and returns the selected cid', (
    tester,
  ) async {
    BilibiliPlayPage? selected;
    await pumpPage(tester, selectedCid: 3, onSelect: (page) => selected = page);
    expect(find.text('3/12'), findsOneWidget);
    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    final list = find.byType(ListView).last;
    await tester.scrollUntilVisible(
      find.text('第 10 集 · 剪辑与节奏'),
      160,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.tap(find.text('第 10 集 · 剪辑与节奏'));
    await tester.pumpAndSettle();
    expect(selected?.cid, 10);
    expect(find.text('10/12'), findsOneWidget);
  });

  testWidgets(
    'related videos beyond the first eight remain reachable and actionable',
    (tester) async {
      BilibiliRelatedVideo? selected;
      await pumpPage(tester, onRelated: (video) => selected = video);
      final scrollable = find
          .descendant(
            of: find.byKey(_introKey),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('推荐视频 10：发现生活中的另一种视角'),
        350,
        scrollable: scrollable,
      );
      await tester.tap(find.text('推荐视频 10：发现生活中的另一种视角'));
      await tester.pumpAndSettle();
      expect(selected?.bvid, 'BV10');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'danmaku toggle reflects its state and comment failures preserve input',
    (tester) async {
      var calls = 0;
      await pumpPage(
        tester,
        onSubmit: (text) async {
          calls++;
          return calls == 1 ? '请先登录 B 站账号' : null;
        },
      );
      await tester.tap(find.byTooltip('关闭弹幕'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('开启弹幕'), findsOneWidget);
      await selectComments(tester);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '发送',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '今天也有认真记录生活');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(find.text('请先登录 B 站账号'), findsOneWidget);
      expect(find.text('今天也有认真记录生活'), findsOneWidget);
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('今天也有认真记录生活'), findsNothing);
      expect(find.text('请先登录 B 站账号'), findsNothing);
    },
  );

  testWidgets('a long press invokes triple without also liking', (
    tester,
  ) async {
    var likes = 0;
    var triples = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BilibiliVideoAction(
            icon: Icons.thumb_up_outlined,
            label: '点赞',
            count: 45000,
            onTap: () => likes++,
            onLongPress: () => triples++,
          ),
        ),
      ),
    );
    await tester.longPress(find.byType(BilibiliVideoAction));
    await tester.pumpAndSettle();
    expect(triples, 1);
    expect(likes, 0);
    await tester.tap(find.byType(BilibiliVideoAction));
    await tester.pumpAndSettle();
    expect(likes, 1);
  });

  for (final scenario in <(String, Size, double, double)>[
    ('small phone', const Size(375, 667), 1, 0),
    ('keyboard', const Size(375, 667), 1, 300),
    ('large text and keyboard', const Size(375, 812), 3.2, 300),
    ('landscape', const Size(812, 375), 1, 0),
    ('tablet', const Size(1024, 1366), 1, 0),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '${scenario.$1} in ${brightness.name} has usable tabs and composer',
        (tester) async {
          await pumpPage(
            tester,
            size: scenario.$2,
            textScale: scenario.$3,
            keyboard: scenario.$4,
            brightness: brightness,
          );
          expect(tester.takeException(), isNull);
          await selectComments(tester);
          expect(tester.takeException(), isNull);
          final composer = tester.getRect(find.byType(BilibiliCommentComposer));
          expect(
            composer.bottom,
            lessThanOrEqualTo(scenario.$2.height - scenario.$4),
          );
          expect(composer.height, greaterThanOrEqualTo(48));
          expect(find.byType(TextField).hitTestable(), findsOneWidget);
          if (scenario.$1 == 'small phone') {
            await _captureScreen(tester, 'comments-${brightness.name}');
          }
        },
      );
    }
  }

  testWidgets('dark introduction visual preview', (tester) async {
    await pumpPage(tester, brightness: Brightness.dark);
    await _captureScreen(tester, 'introduction-dark');
    expect(tester.takeException(), isNull);
  });

  test('related metadata parses optional counters and duration', () {
    final video = BilibiliRelatedVideo.fromJson({
      'bvid': 'BV1',
      'duration': '125',
      'stat': {'view': 24000, 'danmaku': '180'},
    });
    expect(video.duration, 125);
    expect(video.danmaku, 180);
    expect(formatBilibiliDuration(video.duration), '02:05');
    expect(formatBilibiliCount(video.view), '2.4万');
    expect(BilibiliRelatedVideo.fromJson({}).duration, 0);
  });
}

Future<void> _captureScreen(WidgetTester tester, String name) async {
  if (!_capture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/player-ui/widgets/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _FixturePage extends StatefulWidget {
  const _FixturePage({
    required this.aspectRatio,
    required this.selectedCid,
    this.onSelect,
    this.onRelated,
    this.onSubmit,
  });
  final double aspectRatio;
  final int selectedCid;
  final ValueChanged<BilibiliPlayPage>? onSelect;
  final ValueChanged<BilibiliRelatedVideo>? onRelated;
  final Future<String?> Function(String)? onSubmit;

  @override
  State<_FixturePage> createState() => _FixturePageState();
}

class _FixturePageState extends State<_FixturePage> {
  late int _cid = widget.selectedCid;
  bool _danmaku = true;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      key: const ValueKey('capture'),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: Material(
            color: colors.surface,
            child: BilibiliVideoLayout(
              aspectRatio: widget.aspectRatio,
              keyboardVisible: MediaQuery.viewInsetsOf(context).bottom > 0,
              commentTotal: 128,
              danmakuEnabled: _danmaku,
              onToggleDanmaku: () => setState(() => _danmaku = !_danmaku),
              onDanmakuSettings: () {},
              player: const _PreviewPlayer(),
              introduction: BilibiliVideoIntroduction(
                title: _title,
                bvid: 'BV1example',
                description: _description,
                viewCount: 283400,
                danmakuCount: 1256,
                publishedAt: 1789884000,
                creator: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const BilibiliAvatar(url: '', name: '日常', size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '日常记录所',
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '12.8万粉丝',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(onPressed: () {}, child: const Text('+ 关注')),
                    ],
                  ),
                ),
                actions: [
                  for (final action in [
                    (Icons.thumb_up_outlined, '点赞', 16400),
                    (Icons.monetization_on_outlined, '投币', 3680),
                    (Icons.star_border_rounded, '收藏', 8100),
                    (Icons.reply_rounded, '分享', 0),
                  ])
                    BilibiliVideoAction(
                      icon: action.$1,
                      label: action.$2,
                      count: action.$3,
                      onTap: () {},
                    ),
                ],
                pages: List.generate(
                  12,
                  (index) => BilibiliPlayPage(
                    cid: index + 1,
                    page: index + 1,
                    part: '第 ${index + 1} 集 · 剪辑与节奏',
                    duration: 180,
                  ),
                ),
                selectedCid: _cid,
                onSelectPage: (page) {
                  setState(() => _cid = page.cid);
                  widget.onSelect?.call(page);
                },
                related: List.generate(
                  12,
                  (index) => BilibiliRelatedVideo(
                    bvid: 'BV${index + 1}',
                    title: '推荐视频 ${index + 1}：发现生活中的另一种视角',
                    upName: '影像生活',
                    view: 54600,
                    duration: 325,
                    danmaku: 386,
                  ),
                ),
                onOpenRelated: (video) => widget.onRelated?.call(video),
              ),
              comments: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            '全部评论 128',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        BilibiliCommentTile(
                          comment: const BilibiliComment(
                            rpid: 1,
                            uname: '今天也要开心',
                            message: '原来生活里的小事，也能拍得这么温柔。周末就带上相机出门试试看！',
                            likeCount: 328,
                            replyCount: 12,
                            replies: [
                              BilibiliComment(
                                uname: '日常记录所',
                                message: '期待你的作品，一起记录生活呀。',
                              ),
                            ],
                          ),
                          onOpenReplies: () {},
                        ),
                        BilibiliCommentTile(
                          comment: const BilibiliComment(
                            rpid: 2,
                            uname: '慢慢来',
                            message: '最后一段的光线好美，已经收藏了。',
                            likeCount: 126,
                          ),
                          onOpenReplies: () {},
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                      child: BilibiliCommentComposer(
                        hint: '发一条友善的评论…',
                        onSubmit: widget.onSubmit ?? (_) async => null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPlayer extends StatelessWidget {
  const _PreviewPlayer();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF233D4D), Color(0xFF10171C)],
      ),
    ),
    child: Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_outline_rounded,
                color: Colors.white70,
                size: 40,
              ),
              SizedBox(height: 8),
              Text(
                '示例视频画面',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        Positioned(
          left: 16,
          top: 16,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: Icon(Icons.more_horiz_rounded, color: Colors.white),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '01:24 / 08:36',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Icon(Icons.fullscreen, color: Colors.white),
            ],
          ),
        ),
      ],
    ),
  );
}
