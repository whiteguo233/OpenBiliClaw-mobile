import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/client.dart';

void main() {
  test('connection check does not wait for cold provider readiness', () async {
    final requests = <String>[];
    final client = ApiClient(
      host: '192.168.1.7',
      directClientFactory: () => MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/api/ping') {
          return http.Response('{"status":"ok"}', 200);
        }
        throw TimeoutException('embedding readiness is still probing');
      }),
    );
    expect(await client.checkHealth(), isTrue);
    expect(requests, ['/api/ping']);
  });

  test(
    'legacy backend without ping falls back to health with prefix',
    () async {
      final requests = <Uri>[];
      final client = ApiClient(
        scheme: 'https',
        host: 'backend.example',
        port: 9443,
        basePath: '/prefix',
        directClientFactory: () => MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            '{}',
            request.url.path.endsWith('/ping') ? 404 : 200,
          );
        }),
      );
      expect(await client.checkHealth(), isTrue);
      expect(requests.map((uri) => uri.toString()), [
        'https://backend.example:9443/prefix/api/ping',
        'https://backend.example:9443/prefix/api/health',
      ]);
    },
  );

  for (final status in [401, 403, 500]) {
    test('does not hide ping HTTP $status behind a health fallback', () async {
      var calls = 0;
      final client = ApiClient(
        directClientFactory: () => MockClient((request) async {
          calls++;
          return http.Response('{}', status);
        }),
      );
      expect(await client.checkHealth(), isFalse);
      expect(calls, 1);
    });
  }
}
