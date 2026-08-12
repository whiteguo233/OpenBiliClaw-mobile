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

  test('accepts an IPv4 host pasted with its port', () {
    final client = ApiClient(host: '100.100.100.100:8420', port: 8420);

    expect(client.host, '100.100.100.100');
    expect(client.baseUrl, 'http://100.100.100.100:8420/api');
    expect(client.apiUri('recommendations').host, '100.100.100.100');
  });

  test('extracts hosts from common endpoint input formats', () {
    final domain = ApiClient(host: 'openbiliclaw.local:8420', port: 8420);
    final url = ApiClient(
      scheme: 'https',
      host: 'https://example.test:9443/api',
      port: 9443,
    );
    final ipv6 = ApiClient(host: '[fd00::1234]:8420', port: 8420);

    expect(domain.host, 'openbiliclaw.local');
    expect(url.host, 'example.test');
    expect(ipv6.host, 'fd00::1234');
    expect(ipv6.baseUrl, 'http://[fd00::1234]:8420/api');
  });
}
