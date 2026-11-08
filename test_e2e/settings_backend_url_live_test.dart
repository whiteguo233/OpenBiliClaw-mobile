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
    'real backend liveness before and after persisting the endpoint',
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
        reason: 'Real provider-independent /api/ping must return HTTP 200',
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
      final ping = await restored.get('/ping');
      expect(ping['status'], 'ok');
      // Log no hostnames, response bodies, cookies or credentials.
      debugPrint(
        'LIVE PASS: ${endpoint.scheme} port=${endpoint.port}; '
        'liveness HTTP 200 before/after save; backend status=ok',
      );
    },
  );
}
