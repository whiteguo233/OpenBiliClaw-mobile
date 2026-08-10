import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/api/client.dart';

void main() {
  test(
    'apiUri preserves query parameters instead of encoding them into path',
    () {
      final client = ApiClient(host: '127.0.0.1', port: 8420);

      final uri = client.apiUri('/activity-feed?limit=5&before=a%3Ab');

      expect(uri.path, '/api/activity-feed');
      expect(uri.queryParameters['limit'], '5');
      expect(uri.queryParameters['before'], 'a:b');
      expect(uri.toString(), contains('/api/activity-feed?'));
      expect(uri.toString(), isNot(contains('%3Flimit')));
    },
  );

  test('constructs https and wss endpoints from one origin', () {
    final client = ApiClient(scheme: 'https', host: 'example.test', port: 9443);

    expect(client.baseUrl, 'https://example.test:9443/api');
    expect(client.wsUrl, 'wss://example.test:9443/api/runtime-stream');
    expect(client.apiUri('profile-summary').scheme, 'https');
  });
}
