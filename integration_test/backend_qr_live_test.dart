import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/models/backend_connection_link.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/services/tailnet_service.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/settings_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in device acceptance against real servers. Each case supplies a PNG
/// captured from the real QR panel, its expected URL, and a non-sensitive label.
/// No API, HTTP client, persistence, or Tailnet service is replaced.
/// Image analysis exercises the native decoder, not optical camera capture.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const casesJson = String.fromEnvironment('OBC_LIVE_QR_CASES');
  const camera = bool.fromEnvironment('OBC_LIVE_QR_CAMERA');
  // macOS CI may have native plugins but no foreground window. This mode
  // exercises decoder, persistence and transport, and explicitly excludes UI.
  const transportOnly = bool.fromEnvironment('OBC_LIVE_QR_TRANSPORT_ONLY');

  testWidgets(
    'live QR → native import → recommendations → saved reconnect',
    (tester) async {
      final cases = (jsonDecode(casesJson) as List)
          .cast<Map<String, dynamic>>();
      expect(cases, isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      const keys = [
        'api_scheme',
        'api_host',
        'api_port',
        'api_base_path',
        'connection_mode',
        'session_token',
      ];
      final previous = {for (final key in keys) key: prefs.get(key)};
      const secureStorage = FlutterSecureStorage();
      final previousSecure = await secureStorage.read(
        key: 'backend_url_config',
      );
      final directory = await Directory.systemTemp.createTemp('obc-live-qr-');
      final scanner = MobileScannerController(autoStart: false);
      final tailnet = createTailnetService();
      RecommendProvider? recommendations;
      addTearDown(() async {
        recommendations?.stopPolling();
        recommendations?.dispose();
        // Preserve any existing enrollment; never log out or delete node keys.
        tailnet.dispose();
        await scanner.dispose();
        await directory.delete(recursive: true);
        for (final entry in previous.entries) {
          final value = entry.value;
          if (value == null) {
            await prefs.remove(entry.key);
          } else if (value is String) {
            await prefs.setString(entry.key, value);
          } else if (value is int) {
            await prefs.setInt(entry.key, value);
          }
        }
        if (previousSecure == null) {
          await secureStorage.delete(key: 'backend_url_config');
        } else {
          await secureStorage.write(
            key: 'backend_url_config',
            value: previousSecure,
          );
        }
      });

      for (var i = 0; i < cases.length; i++) {
        final entry = cases[i];
        final label = entry['label'] as String;
        final expected = entry['url'] as String;
        final endpoint = BackendConnectionLink.parse(expected);
        final image = File('${directory.path}/connection-$i.png');
        await image.writeAsBytes(base64Decode(entry['png'] as String));
        final capture = await scanner.analyzeImage(image.path);
        final decoded = capture?.barcodes
            .map((barcode) => barcode.rawValue)
            .whereType<String>()
            .firstWhere((value) => value == expected);
        expect(decoded, expected, reason: '$label: native QR decoding');
        debugPrint('LIVE QR $label: native image decoded');

        final client = ApiClient(
          host: endpoint.backendUri.host,
          port: endpoint.backendUri.port,
          scheme: endpoint.backendUri.scheme,
          basePath: endpoint.backendUri.path,
          tailnetService: tailnet,
        );
        recommendations?.dispose();
        final currentRecommendations = RecommendProvider(client);
        recommendations = currentRecommendations;
        if (transportOnly) {
          expect(
            camera,
            isFalse,
            reason: 'Camera requires the UI acceptance mode',
          );
          if (endpoint.usesEmbeddedTailnet) {
            expect(
              await tailnet.connect(),
              isTrue,
              reason: tailnet.statusMessage,
            );
          }
          await client.saveSettings(
            endpoint.backendUri.host,
            endpoint.backendUri.port,
            scheme: endpoint.backendUri.scheme,
            basePath: endpoint.backendUri.path,
            connectionMode: endpoint.usesEmbeddedTailnet
                ? ConnectionMode.tailscale
                : ConnectionMode.direct,
          );
          debugPrint(
            'LIVE QR $label: transport-only settings saved (UI excluded)',
          );
          await currentRecommendations.load();
        } else {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                Provider<ApiClient>.value(value: client),
                ChangeNotifierProvider<TailnetService>.value(value: tailnet),
                ChangeNotifierProvider<RecommendProvider>.value(
                  value: currentRecommendations,
                ),
              ],
              child: MaterialApp(
                theme: AppTheme.light(),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SettingsView(
                              scanConnection: camera
                                  ? null
                                  : (_) async => decoded,
                            ),
                          ),
                        ),
                        child: const Text('打开连接设置'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开连接设置'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.byTooltip('扫码连接'));
          if (Platform.isIOS) {
            await binding.takeScreenshot('qr-settings-$label');
          }
          await tester.tap(find.byTooltip('扫码连接'));
          await _until(
            tester,
            () => find.text('打开连接设置').hitTestable().evaluate().isNotEmpty,
            const Duration(minutes: 3),
            '$label: scan import did not complete',
          );
        }
        expect(client.host, endpoint.backendUri.host);
        expect(client.port, endpoint.backendUri.port);
        expect(client.usesTailscale, endpoint.usesEmbeddedTailnet);
        await _until(
          tester,
          () =>
              currentRecommendations.online &&
              currentRecommendations.recommendations.isNotEmpty,
          const Duration(seconds: 45),
          '$label: real recommendations did not load',
        );
        expect(
          await client.checkHealth(),
          isTrue,
          reason: '$label: real liveness request',
        );
        final restored = ApiClient(tailnetService: tailnet);
        await restored.loadSettings();
        expect(restored.baseUrl, client.baseUrl);
        expect(restored.connectionMode, client.connectionMode);
        expect((await restored.get('/ping'))['status'], 'ok');
        debugPrint(
          'LIVE QR $label: saved; real recommendations '
          '${currentRecommendations.recommendations.length}; liveness/ping PASS',
        );
        currentRecommendations.stopPolling();
        if (!transportOnly) {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    },
    skip: casesJson.isEmpty,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  Duration timeout,
  String message,
) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(ready(), isTrue, reason: message);
}
