import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/bilibili_auth.dart';

void main() {
  group('BilibiliCookieSession', () {
    test('parses cookie map into a Cookie header value', () {
      final session = BilibiliCookieSession.fromJson({
        'ok': true,
        'cookies': {
          'SESSDATA': 'secret',
          'bili_jct': 'csrf',
          'DedeUserID': '123',
        },
        'user_agent': 'Mozilla/5.0 (iPhone)',
        'buvid': 'B1',
        'expires_at': '2026-01-01T00:00:00Z',
        'user': {'mid': 123, 'name': '昵称', 'face': 'https://face'},
      });

      expect(session.cookie, 'SESSDATA=secret; bili_jct=csrf; DedeUserID=123');
      expect(session.userAgent, 'Mozilla/5.0 (iPhone)');
      expect(session.buvid, 'B1');
      expect(session.expiresAt, '2026-01-01T00:00:00Z');
      expect(session.user?.mid, 123);
      expect(session.user?.name, '昵称');
      expect(session.isLoggedIn, isTrue);
    });

    test('accepts a raw cookie string from the backend', () {
      final session = BilibiliCookieSession.fromJson({
        'cookie': 'SESSDATA=raw; bili_jct=csrf',
        'user_agent': 'Mozilla/5.0',
      });

      expect(session.cookie, 'SESSDATA=raw; bili_jct=csrf');
      expect(session.userAgent, 'Mozilla/5.0');
      expect(session.buvid, isEmpty);
      expect(session.user, isNull);
    });

    test('empty session is not logged in', () {
      const session = BilibiliCookieSession();
      expect(session.isLoggedIn, isFalse);
      expect(session.cookie, isEmpty);
    });
  });
}
