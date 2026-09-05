import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openbiliclaw_app/api/bilibili_api.dart';
import 'package:openbiliclaw_app/api/client.dart';

void main() {
  test(
    'exportSession posts to auth/export and parses the cookie session',
    () async {
      final apiClient = ApiClient(
        host: '127.0.0.1',
        port: 8420,
        directClientFactory: () => _FakeHttpClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/bilibili/auth/export');
          return http.Response(
            jsonEncode({
              'ok': true,
              'cookies': {'SESSDATA': 'secret', 'bili_jct': 'csrf'},
              'user_agent': 'Mozilla/5.0 (iPhone)',
              'buvid': 'B1',
              'expires_at': '2026-01-01T00:00:00Z',
              'user': {'mid': 123, 'name': '昵称'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final api = BilibiliApi(apiClient);
      final session = await api.exportSession();

      expect(session.cookie, 'SESSDATA=secret; bili_jct=csrf');
      expect(session.userAgent, 'Mozilla/5.0 (iPhone)');
      expect(session.user?.name, '昵称');
    },
  );
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
