import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/main.dart' as app;
import 'package:openbiliclaw_app/models/backend_connection_link.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/views/home_view.dart';
import 'package:provider/provider.dart';

import 'backend_qr_live_test.dart' as qr;
import 'mobile_web_connection_live_test.dart' as web;

/// Two actual process launches, using one binary on a disposable emulator.
/// First launch scans screenshots and renders the real mobile website. After
/// the driver exits, the host force-stops the app, creates the phase marker in
/// the app cache (not in its settings), then launches the same binary again.
/// The second launch calls production app.main() and never writes a backend.
void main() {
  const casesJson = String.fromEnvironment('OBC_LIVE_QR_CASES');
  const keepSettings = bool.fromEnvironment('OBC_LIVE_QR_KEEP_SETTINGS');
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  debugPrint('LIVE QR FULL TEMP: ${Directory.systemTemp.path}');
  if (!File(
    '${Directory.systemTemp.path}/obc-qr-verify-restart',
  ).existsSync()) {
    qr.main();
    web.main();
    return;
  }

  testWidgets(
    'saved QR connection survives a real process restart in the production app',
    (tester) async {
      expect(keepSettings, isTrue, reason: 'Use only a disposable emulator');
      final cases = (jsonDecode(casesJson) as List)
          .cast<Map<String, dynamic>>();
      final expected = BackendConnectionLink.parse(cases.last['url'] as String);
      app.main();
      final elapsed = Stopwatch()..start();
      while (find.byType(HomeView).evaluate().isEmpty &&
          elapsed.elapsed < const Duration(seconds: 45)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(find.byType(HomeView), findsOneWidget);
      final context = tester.element(find.byType(HomeView));
      final client = context.read<ApiClient>();
      expect(client.host, expected.backendUri.host);
      expect(client.port, expected.backendUri.port);
      expect(client.scheme, expected.backendUri.scheme);
      // ApiClient stores its internal prefix without a leading slash. Check
      // the public request URL instead of comparing that implementation form
      // with Uri.path, which includes the slash.
      expect(Uri.parse(client.baseUrl).path, '${expected.backendUri.path}/api');
      expect(client.usesTailscale, expected.usesEmbeddedTailnet);
      final recommendations = context.read<RecommendProvider>();
      while ((!recommendations.online ||
              recommendations.recommendations.isEmpty) &&
          elapsed.elapsed < const Duration(seconds: 90)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(recommendations.online, isTrue);
      expect(recommendations.recommendations, isNotEmpty);
      final firstCard = find.text(recommendations.recommendations.first.title);
      // Data notification and the SliverList's next frame are asynchronous.
      // Wait for the real widget, then scroll it into view below the header.
      while (firstCard.evaluate().isEmpty &&
          elapsed.elapsed < const Duration(seconds: 100)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(firstCard, findsWidgets);
      await tester.ensureVisible(firstCard.first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(firstCard.hitTestable(), findsWidgets);
      expect((await client.get('/ping'))['status'], 'ok');
      await tester.tap(find.byTooltip('连接设置'));
      while (find.byTooltip('扫码连接').hitTestable().evaluate().isEmpty &&
          elapsed.elapsed < const Duration(seconds: 100)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(find.byTooltip('扫码连接').hitTestable(), findsOneWidget);
      debugPrint(
        'LIVE QR PROCESS RESTART: production app loaded saved endpoint; '
        '${recommendations.recommendations.length} real recommendations loaded; '
        'first card rendered; ping PASS',
      );
      recommendations.stopPolling();
    },
    skip: casesJson.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
