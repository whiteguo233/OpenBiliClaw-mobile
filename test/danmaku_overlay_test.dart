import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/widgets/danmaku_overlay.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('DanmakuOverlay timing window', () {
    final items = [
      const DanmakuItem(time: Duration(seconds: 5), text: 'early'),
      const DanmakuItem(time: Duration(seconds: 10), text: 'later'),
    ];

    testWidgets('shows danmaku whose timestamp just passed, not future ones',
        (tester) async {
      final position = StreamController<Duration>();
      addTearDown(() => unawaited(position.close()));
      await tester.pumpWidget(
        _wrap(DanmakuOverlay(position: position.stream, items: items)),
      );
      position.add(const Duration(seconds: 7));
      await tester.pump();

      expect(find.text('early'), findsOneWidget);
      expect(find.text('later'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('removes danmaku after its scroll window elapsed',
        (tester) async {
      final position = StreamController<Duration>();
      addTearDown(() => unawaited(position.close()));
      await tester.pumpWidget(
        _wrap(DanmakuOverlay(position: position.stream, items: items)),
      );
      position.add(const Duration(seconds: 7));
      await tester.pump();
      expect(find.text('early'), findsOneWidget);

      position.add(const Duration(seconds: 13));
      await tester.pump();
      expect(find.text('early'), findsNothing);
      expect(find.text('later'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('renders nothing when disabled', (tester) async {
      final position = StreamController<Duration>();
      addTearDown(() => unawaited(position.close()));
      await tester.pumpWidget(
        _wrap(
          DanmakuOverlay(position: position.stream, items: items, enabled: false),
        ),
      );
      await tester.pump();

      expect(find.text('early'), findsNothing);
    });
  });
}
