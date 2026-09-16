import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/services/bilibili_space_launcher.dart';

void main() {
  group('Bilibili space launch plan', () {
    test('tries the native app route before the web space URL', () {
      final uris = BilibiliSpaceLauncher.buildUris(mid: '42');

      expect(uris, hasLength(2));
      expect(uris.first.scheme, 'bilibili');
      expect(uris.first.toString(), 'bilibili://space/42');
      expect(uris.last.toString(), 'https://space.bilibili.com/42');
    });

    test('trims whitespace around a numeric mid', () {
      final uris = BilibiliSpaceLauncher.buildUris(mid: ' 42 ');

      expect(uris, hasLength(2));
      expect(uris.first.path, '/42');
    });

    test('rejects missing and non-numeric mids', () {
      expect(BilibiliSpaceLauncher.buildUris(mid: ''), isEmpty);
      expect(BilibiliSpaceLauncher.buildUris(mid: '0'), isEmpty);
      expect(BilibiliSpaceLauncher.buildUris(mid: 'not-a-mid'), isEmpty);
      expect(BilibiliSpaceLauncher.isValidMid('-1'), isFalse);
    });
  });
}
