import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/services/tailnet_service.dart';
import 'package:openbiliclaw_app/services/tailnet_service_stub.dart' as stub;
import 'package:openbiliclaw_app/views/settings_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IdleRecommendations extends RecommendProvider {
  _IdleRecommendations(super.client);
  @override
  void startPolling() {}
  @override
  void stopPolling() {}
}

void main() {
  for (final entry in {
    'https://example.com': 'https://example.com',
    'http://example.com': 'http://example.com',
    'https://example.com:443': 'https://example.com',
    'http://example.com:80': 'http://example.com',
    'https://example.com:9443/openbiliclaw/api':
        'https://example.com:9443/openbiliclaw',
    'example.com': 'http://example.com',
    '192.168.1.10:8420': 'http://192.168.1.10:8420',
    'http://[fd00::1234]:8420': 'http://[fd00::1234]:8420',
  }.entries) {
    testWidgets('test, save and reopen backend URL ${entry.key}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      final client = ApiClient(
        directClientFactory: () => MockClient((request) async {
          requests.add(request.url);
          return http.Response('{}', 200);
        }),
      );
      final tailnet = stub.createTailnetService();
      final recommendations = _IdleRecommendations(client);
      addTearDown(tailnet.dispose);
      addTearDown(recommendations.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: client),
            ChangeNotifierProvider<TailnetService>.value(value: tailnet),
            ChangeNotifierProvider<RecommendProvider>.value(
              value: recommendations,
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsView(),
                    ),
                  ),
                  child: const Text('Open settings'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, entry.key);
      await tester.tap(find.text('测试连接'));
      await tester.pumpAndSettle();
      expect(requests.last.toString(), '${entry.value}/api/health');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(client.baseUrl, '${entry.value}/api');
      final restored = ApiClient();
      await restored.loadSettings();
      expect(restored.baseUrl, '${entry.value}/api');
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, entry.value);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
