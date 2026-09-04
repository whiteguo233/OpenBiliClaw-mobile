import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart'
    show DanmakuController, DanmakuScreen;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/widgets/danmaku_overlay.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 300, child: child),
    ),
  );
}

Iterable<String> _visibleTexts(DanmakuController<Object?> controller) sync* {
  for (final track in controller.scrollDanmaku) {
    for (final item in track) {
      yield item.content.text;
    }
  }
}

void main() {
  group('DanmakuOverlay (canvas_danmaku engine)', () {
    testWidgets('adds a danmaku when playback crosses its timestamp',
        (tester) async {
      final position = StreamController<Duration>();
      addTearDown(() => unawaited(position.close()));
      DanmakuController<Object?>? engine;
      await tester.pumpWidget(
        _wrap(
          DanmakuOverlay(
            position: position.stream,
            items: const [
              DanmakuItem(time: Duration(seconds: 5), text: 'early'),
              DanmakuItem(time: Duration(seconds: 10), text: 'later'),
            ],
            onControllerCreated: (c) => engine = c,
          ),
        ),
      );

      // Realistic playback cadence: position updates every ~1 s.
      position.add(const Duration(seconds: 3));
      await tester.pump();
      expect(_visibleTexts(engine!), isEmpty);

      position.add(const Duration(seconds: 4));
      position.add(const Duration(seconds: 5, milliseconds: 200));
      await tester.pump();
      expect(_visibleTexts(engine!), contains('early'));
      expect(_visibleTexts(engine!), isNot(contains('later')));

      for (var s = 6; s <= 9; s++) {
        position.add(Duration(seconds: s));
      }
      await tester.pump();
      expect(_visibleTexts(engine!), isNot(contains('later')));

      position.add(const Duration(seconds: 10, milliseconds: 300));
      await tester.pump();
      expect(_visibleTexts(engine!), contains('later'));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('removes a danmaku only after it has scrolled out',
        (tester) async {
      final position = StreamController<Duration>();
      addTearDown(() => unawaited(position.close()));
      DanmakuController<Object?>? engine;
      await tester.pumpWidget(
        _wrap(
          DanmakuOverlay(
            position: position.stream,
            items: const [
              DanmakuItem(time: Duration(seconds: 5), text: 'early'),
            ],
            onControllerCreated: (c) => engine = c,
          ),
        ),
      );

      position.add(const Duration(seconds: 3));
      position.add(const Duration(seconds: 5, milliseconds: 200));
      await tester.pump();
      expect(_visibleTexts(engine!), contains('early'));

      // Engine default scroll duration is 10 s: the item stays until it has
      // fully crossed the screen, then the painter flags it expired and the
      // engine's periodic garbage collection removes it (every ~11 ticks).
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_visibleTexts(engine!), isEmpty);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('never back-fills comments whose timestamp already passed',
        (tester) async {
      final position = StreamController<Duration>();
      addTearDown(() => unawaited(position.close()));
      DanmakuController<Object?>? engine;
      await tester.pumpWidget(
        _wrap(
          DanmakuOverlay(
            position: position.stream,
            items: const [],
            onControllerCreated: (c) => engine = c,
          ),
        ),
      );

      // Playback reaches 7 s before the danmaku list arrives.
      position.add(const Duration(seconds: 3));
      position.add(const Duration(seconds: 7));
      await tester.pump();

      // List arrives late, containing a comment from 5 s — it must be
      // skipped, not spawned in a back-dated burst.
      await tester.pumpWidget(
        _wrap(
          DanmakuOverlay(
            position: position.stream,
            items: const [
              DanmakuItem(time: Duration(seconds: 5), text: 'early'),
              DanmakuItem(time: Duration(seconds: 9), text: 'fresh'),
            ],
            onControllerCreated: (c) => engine = c,
          ),
        ),
      );

      position.add(const Duration(seconds: 9, milliseconds: 400));
      await tester.pump();
      expect(_visibleTexts(engine!), contains('fresh'));
      expect(_visibleTexts(engine!), isNot(contains('early')));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('re-shows danmaku after seeking backwards', (tester) async {
      final position = StreamController<Duration>();
      addTearDown(() => unawaited(position.close()));
      DanmakuController<Object?>? engine;
      await tester.pumpWidget(
        _wrap(
          DanmakuOverlay(
            position: position.stream,
            items: const [
              DanmakuItem(time: Duration(seconds: 5), text: 'early'),
            ],
            onControllerCreated: (c) => engine = c,
          ),
        ),
      );

      position.add(const Duration(seconds: 3));
      position.add(const Duration(seconds: 5, milliseconds: 200));
      await tester.pump();
      expect(_visibleTexts(engine!).where((t) => t == 'early'), hasLength(1));

      position.add(const Duration(seconds: 6));
      await tester.pump();

      // Rewind across the timestamp: the comment spawns again.
      position.add(const Duration(seconds: 5));
      await tester.pump();
      expect(_visibleTexts(engine!).where((t) => t == 'early'), hasLength(2));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('does not spawn danmaku while playback is paused',
        (tester) async {
      final position = StreamController<Duration>();
      final playing = StreamController<bool>();
      addTearDown(() => unawaited(position.close()));
      addTearDown(() => unawaited(playing.close()));
      DanmakuController<Object?>? engine;
      await tester.pumpWidget(
        _wrap(
          DanmakuOverlay(
            position: position.stream,
            playing: playing.stream,
            items: const [
              DanmakuItem(time: Duration(seconds: 5), text: 'early'),
              DanmakuItem(time: Duration(seconds: 10), text: 'later'),
            ],
            onControllerCreated: (c) => engine = c,
          ),
        ),
      );

      playing.add(false);
      await tester.pump();
      position.add(const Duration(seconds: 4));
      position.add(const Duration(seconds: 5, milliseconds: 200));
      await tester.pump();
      expect(_visibleTexts(engine!), isEmpty);

      // Resumed playback spawns comments again from here on; the comment
      // whose timestamp was skipped during the pause stays skipped.
      playing.add(true);
      await tester.pump();
      position.add(const Duration(seconds: 6));
      position.add(const Duration(seconds: 10, milliseconds: 300));
      await tester.pump();
      expect(_visibleTexts(engine!), contains('later'));
      expect(_visibleTexts(engine!), isNot(contains('early')));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('renders nothing when disabled', (tester) async {
      final position = StreamController<Duration>();
      addTearDown(() => unawaited(position.close()));
      await tester.pumpWidget(
        _wrap(
          DanmakuOverlay(
            position: position.stream,
            items: const [],
            enabled: false,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DanmakuScreen<Object?>), findsNothing);
    });
  });
}
