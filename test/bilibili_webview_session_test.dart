import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/services/bilibili_webview_session.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  group('parseCookieHeader', () {
    test('splits a Cookie header into name/value pairs', () {
      final cookies = parseCookieHeader(
        'SESSDATA=secret; bili_jct=csrf; DedeUserID=123',
      );

      expect(cookies, {
        'SESSDATA': 'secret',
        'bili_jct': 'csrf',
        'DedeUserID': '123',
      });
    });

    test('keeps the first "=" inside the cookie value', () {
      final cookies = parseCookieHeader('token=a=b=c; SESSDATA=x');

      expect(cookies['token'], 'a=b=c');
      expect(cookies['SESSDATA'], 'x');
    });

    test('ignores blank and malformed segments', () {
      final cookies = parseCookieHeader(' ; SESSDATA= ; =oops ; bili_jct=y');

      expect(cookies, {'bili_jct': 'y'});
    });

    test('empty header yields no cookies', () {
      expect(parseCookieHeader(''), isEmpty);
      expect(parseCookieHeader('   '), isEmpty);
    });
  });

  group('buildBilibiliCookieScript', () {
    test('preserves percent-escapes instead of double-encoding them', () {
      final script = buildBilibiliCookieScript(
        'SESSDATA=abc%2Adef%2Cghi; bili_jct=csrf',
      );

      expect(script, contains('document.cookie='));
      expect(script, contains('abc%2Adef%2Cghi'));
      expect(script, isNot(contains('%252A')));
      expect(script, isNot(contains('%252C')));
      expect(script, contains('domain=.bilibili.com'));
    });

    test('escapes quotes and backslashes so the script stays valid', () {
      final script = buildBilibiliCookieScript(r'token=a"b\c');

      expect(script, contains(r'a\"b\\c'));
    });

    test('returns an empty string when there is no cookie', () {
      expect(buildBilibiliCookieScript(''), isEmpty);
    });
  });

  group('injectBilibiliCookies', () {
    test('writes every cookie as a .bilibili.com domain cookie', () async {
      final written = <WebViewCookie>[];

      final count = await injectBilibiliCookies(
        cookieHeader: 'SESSDATA=secret; bili_jct=csrf',
        setCookie: (cookie) async => written.add(cookie),
      );

      expect(count, 2);
      expect(written.map((cookie) => cookie.name).toSet(), {
        'SESSDATA',
        'bili_jct',
      });
      expect(
        written.every((cookie) => cookie.domain == '.bilibili.com'),
        isTrue,
      );
      expect(written.every((cookie) => cookie.path == '/'), isTrue);
    });

    test('does not call the setter when there is no cookie', () async {
      var called = 0;

      final count = await injectBilibiliCookies(
        cookieHeader: '',
        setCookie: (_) async => called++,
      );

      expect(count, 0);
      expect(called, 0);
    });

    test('a failing cookie does not stop the remaining writes', () async {
      final written = <WebViewCookie>[];

      final count = await injectBilibiliCookies(
        cookieHeader: 'SESSDATA=secret; bili_jct=csrf',
        setCookie: (cookie) async {
          if (cookie.name == 'SESSDATA') {
            throw StateError('unsupported value');
          }
          written.add(cookie);
        },
      );

      expect(count, 1);
      expect(written.single.name, 'bili_jct');
    });
  });
}
