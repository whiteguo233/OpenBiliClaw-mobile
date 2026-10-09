import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/io_client.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Opt-in, read-only requests to a real backend. Persistence is isolated from
// the user's settings. Run with --dart-define=LIVE_BACKEND_URL=https://host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('LIVE_BACKEND_URL');
  test(
    'real backend health before and after persisting the endpoint',
    () async {
      expect(url, isNotEmpty, reason: 'Provide LIVE_BACKEND_URL');
      final endpoint = Uri.parse(url);
      final oldOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = oldOverrides);
      // test_e2e is an opt-in test directory outside the analyzer's test/ root.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
      // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
      ApiClient makeClient() => ApiClient(
        directClientFactory: () =>
            IOClient(HttpClient()..findProxy = (_) => 'DIRECT'),
      );
      final client = makeClient();
      expect(
        await client.checkHealth(
          overrideScheme: endpoint.scheme,
          overrideHost: endpoint.host,
          overridePort: endpoint.port,
          overrideBasePath: endpoint.path,
        ),
        isTrue,
        reason: 'Real /api/health request must return HTTP 200',
      );
      await client.saveSettings(
        endpoint.host,
        endpoint.port,
        scheme: endpoint.scheme,
        basePath: endpoint.path,
      );
      final restored = makeClient();
      await restored.loadSettings();
      expect(restored.baseUrl, client.baseUrl);
      expect(await restored.checkHealth(), isTrue);
      final health = await restored.get('/health');
      expect(health['status'], 'ok');
      // Log no hostnames, response bodies, cookies or credentials.
      debugPrint(
        'LIVE PASS: ${endpoint.scheme} port=${endpoint.port}; '
        'health HTTP 200 before/after save; backend status=ok',
      );
    },
  );
}
