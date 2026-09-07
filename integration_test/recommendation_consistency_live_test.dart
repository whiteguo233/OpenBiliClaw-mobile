import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/providers/saved_provider.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/recommend_view.dart';

// Opt-in: real device UI + real HTTP/WebSocket, consumes live recommendations.
// No mock HTTP, seeded content, saved connection changes, or feedback writes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const host = String.fromEnvironment(
    'LIVE_BACKEND_HOST',
    defaultValue: '127.0.0.1',
  );
  testWidgets('live inventory, reshuffle and fling pagination', (tester) async {
    final client = ApiClient(host: host);
    final recommendations = RecommendProvider(client);
    final saved = SavedProvider(client);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: client),
          ChangeNotifierProvider<RecommendProvider>.value(
            value: recommendations,
          ),
          ChangeNotifierProvider<SavedProvider>.value(value: saved),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SafeArea(child: RecommendView())),
        ),
      ),
    );
    try {
      unawaited(recommendations.load());
      recommendations.startPolling();
      await until(
        tester,
        () =>
            recommendations.online &&
            !recommendations.loading &&
            recommendations.recommendations.isNotEmpty,
      );
      final seen = <String>{};
      for (var i = 0; i < 2; i++) {
        final previous = recommendations.recommendations
            .map((x) => x.savedIdentity)
            .toSet();
        final watch = Stopwatch()..start();
        await tester.tap(find.text('换一批'));
        await tester.pump();
        await until(tester, () => !recommendations.reshuffling);
        expect(recommendations.error, isEmpty);
        expect(recommendations.recommendations, isNotEmpty);
        for (final card in recommendations.recommendations) {
          expect(previous.contains(card.savedIdentity), isFalse);
          expect(seen.add(card.savedIdentity), isTrue);
          expect(card.id, greaterThan(0));
        }
        checkInventory(recommendations);
        expect(
          find.text('${recommendations.runtimeStatus.poolAvailableCount} 条'),
          findsWidgets,
        );
        debugPrint(
          'LIVE_E2E ${jsonEncode({'action': 'reshuffle', 'ms': watch.elapsedMilliseconds, 'cards': recommendations.recommendations.length, 'remaining': recommendations.platformAvailability.totalAvailable, 'sources': recommendations.platformAvailabilityBySource})}',
        );
      }
      final before = recommendations.recommendations.length;
      final scroll = find
          .descendant(
            of: find.byType(RecommendView),
            matching: find.byType(Scrollable),
          )
          .first;
      final watch = Stopwatch()..start();
      // Real drag notifications, including ballistic movement after release.
      for (
        var i = 0;
        i < 20 && recommendations.recommendations.length == before;
        i++
      ) {
        await tester.fling(scroll, const Offset(0, -650), 2000);
        await tester.pump(const Duration(milliseconds: 500));
        if (recommendations.loadingMore) break;
      }
      await until(
        tester,
        () =>
            !recommendations.loadingMore &&
            recommendations.recommendations.length > before,
      );
      expect(recommendations.error, isEmpty);
      for (final card in recommendations.recommendations.skip(before)) {
        expect(seen.add(card.savedIdentity), isTrue);
        expect(card.id, greaterThan(0));
      }
      checkInventory(recommendations);
      debugPrint(
        'LIVE_E2E ${jsonEncode({'action': 'fling_append', 'ms': watch.elapsedMilliseconds, 'cards_before': before, 'cards_after': recommendations.recommendations.length, 'remaining': recommendations.platformAvailability.totalAvailable, 'sources': recommendations.platformAvailabilityBySource})}',
      );
    } finally {
      recommendations.stopPolling();
      await tester.pumpWidget(const SizedBox.shrink());
      recommendations.dispose();
      saved.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

void checkInventory(RecommendProvider provider) {
  expect(provider.platformAvailability.version, greaterThan(0));
  expect(
    provider.platformAvailability.totalAvailable,
    provider.platformAvailabilityBySource.values.fold<int>(
      0,
      (sum, n) => sum + n,
    ),
  );
  expect(
    provider.runtimeStatus.poolAvailableCount,
    provider.platformAvailability.totalAvailable,
  );
}

Future<void> until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Live recommendation state did not recover within 25 seconds');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
