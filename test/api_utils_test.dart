import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/api/utils.dart';

void main() {
  group('proxyImageUrl', () {
    test('builds an authenticated backend proxy URL', () {
      final result = proxyImageUrl(
        'https://i0.hdslb.com/bfs/archive/a cover.jpg',
        'https://example.test:9443/api',
        token: 'session token',
      );
      final uri = Uri.parse(result);

      expect(uri.origin, 'https://example.test:9443');
      expect(uri.path, '/api/image-proxy');
      expect(
        uri.queryParameters['url'],
        'https://i0.hdslb.com/bfs/archive/a cover.jpg',
      );
      expect(uri.queryParameters['token'], 'session token');
    });

    test('does not corrupt a host whose name starts with api', () {
      final result = proxyImageUrl(
        'https://example.test/cover.jpg',
        'https://api.example.test/api',
      );
      final uri = Uri.parse(result);

      expect(uri.host, 'api.example.test');
      expect(uri.path, '/api/image-proxy');
      expect(uri.queryParameters, {'url': 'https://example.test/cover.jpg'});
    });
  });
}
