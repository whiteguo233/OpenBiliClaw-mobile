import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/bilibili_api.dart';
import 'package:openbiliclaw_app/api/client.dart';

void main() {
  test('postComment posts bvid/message/root/parent to the backend route', () async {
    late http.Request captured;
    final client = ApiClient(
      host: '127.0.0.1',
      directClientFactory: () => MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode('{"ok": true, "rpid": 987}'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final api = BilibiliApi(client);

    final result = await api.postComment(
      bvid: 'BV1xx411c7mD',
      message: '你好呀',
      root: 12,
      parent: 34,
    );

    expect(result['rpid'], 987);
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/bilibili/video/comment');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['bvid'], 'BV1xx411c7mD');
    expect(body['message'], '你好呀');
    expect(body['root'], 12);
    expect(body['parent'], 34);
  });

  test('top-level comment omits root/parent from the body', () async {
    late http.Request captured;
    final client = ApiClient(
      host: '127.0.0.1',
      directClientFactory: () => MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode('{"ok": true, "rpid": 1}'),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final api = BilibiliApi(client);

    await api.postComment(bvid: 'BV1xx411c7mD', message: '评论');

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body.containsKey('root'), isFalse);
    expect(body.containsKey('parent'), isFalse);
  });
}
