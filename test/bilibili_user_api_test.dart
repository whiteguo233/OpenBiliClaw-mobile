import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/bilibili_api.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ApiClient clientWith(MockClient mock) =>
      ApiClient(host: '127.0.0.1', port: 8420, directClientFactory: () => mock);

  test('userCard reads follow state and fan count', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/bilibili/user/card');
      expect(request.url.queryParameters['mid'], '42');
      return http.Response(
        jsonEncode({
          'ok': true,
          'mid': 42,
          'name': '测试UP',
          'face': 'https://i0.hdslb.com/bfs/face/up.jpg',
          'sign': '签名',
          'fans': 12345,
          'following': true,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final up = await BilibiliApi(clientWith(mock)).userCard(mid: 42);

    expect(up.mid, 42);
    expect(up.name, '测试UP');
    expect(up.fans, 12345);
    expect(up.following, isTrue);
  });

  test(
    'followUser posts the flag through the backend and parses state',
    () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/bilibili/user/follow');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {'mid': 42, 'follow': true});
        return http.Response(
          jsonEncode({
            'ok': true,
            'mid': 42,
            'name': '测试UP',
            'fans': 12346,
            'following': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final up = await BilibiliApi(
        clientWith(mock),
      ).followUser(mid: 42, follow: true);

      expect(up.following, isTrue);
      expect(up.fans, 12346);
    },
  );

  test('followUser surfaces a 404 so the page can hide the button', () async {
    final mock = MockClient(
      (_) async => http.Response('{"detail":"Not Found"}', 404),
    );

    await expectLater(
      BilibiliApi(clientWith(mock)).followUser(mid: 42, follow: true),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('followUser surfaces a 401 so the page can prompt for login', () async {
    final mock = MockClient(
      (_) async => http.Response('{"detail":"expired"}', 401),
    );

    await expectLater(
      BilibiliApi(clientWith(mock)).followUser(mid: 42, follow: true),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });
}
