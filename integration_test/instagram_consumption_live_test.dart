import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/providers/saved_provider.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/recommend_view.dart';
import 'package:openbiliclaw_app/widgets/cover_image.dart';
import 'package:openbiliclaw_app/services/content_launcher.dart';

// Opt-in, isolated real backend. No fixture data or mocked HTTP/platform channels.
void main() {
  const enabled = bool.fromEnvironment('INSTAGRAM_LIVE_E2E');
  const host = String.fromEnvironment(
    'INSTAGRAM_E2E_HOST',
    defaultValue: '127.0.0.1',
  );
  const port = int.fromEnvironment('INSTAGRAM_E2E_PORT', defaultValue: 28925);
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Instagram real native consumption',
    (tester) async {
      final client = ApiClient(host: host, port: port);
      final recommendations = RecommendProvider(client);
      final saved = SavedProvider(client);
      addTearDown(recommendations.dispose);
      addTearDown(saved.dispose);
      // Refuse to toggle existing memberships: this test requires an isolated DB.
      await saved.loadAll();
      expect(saved.error, isEmpty);
      expect(saved.favorites, isEmpty);
      expect(saved.watchLater, isEmpty);
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
      unawaited(recommendations.load());
      unawaited(saved.loadAll());
      await until(
        tester,
        () =>
            recommendations.online &&
            !recommendations.loading &&
            recommendations.recommendations.isNotEmpty,
      );
      expect(
        recommendations.recommendations.every(
          (r) => r.sourcePlatform == 'instagram',
        ),
        isTrue,
      );
      final first = recommendations.recommendations.first;
      expect(Uri.parse(first.contentUrl).host, 'www.instagram.com');
      await until(
        tester,
        () => tester
            .widgetList<RawImage>(
              find.descendant(
                of: find.byType(CoverImage),
                matching: find.byType(RawImage),
              ),
            )
            .any((i) => i.image != null),
      );
      debugPrint('INS_LIVE: real recommendations and decoded cover PASS');
      await tester.tap(find.byTooltip('收藏').first);
      await until(tester, () => saved.favorites.isNotEmpty);
      expect(saved.favorites.first.sourcePlatform, 'instagram');
      await tester.tap(find.byTooltip('稍后再看').first);
      await until(tester, () => saved.watchLater.isNotEmpty);
      await saved.loadAll();
      expect(saved.favorites, isNotEmpty);
      expect(saved.watchLater, isNotEmpty);
      debugPrint('INS_LIVE: favorite/watch-later real write and readback PASS');
      await tester.tap(find.byTooltip('取消收藏').first);
      await until(tester, () => saved.favorites.isEmpty);
      await tester.tap(find.byTooltip('移出稍后再看').first);
      await until(tester, () => saved.watchLater.isEmpty);
      debugPrint('INS_LIVE: real saved cleanup PASS');
      expect(await ContentLauncher.openRecommendation(first), isTrue);
      debugPrint(
        'INS_LIVE: OS external content launch accepted; destination rendering not asserted',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 35));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Real native state timeout');
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 100));
}
