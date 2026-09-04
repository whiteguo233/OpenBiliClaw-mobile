import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openbiliclaw_app/api/bilibili_comment_api.dart';
import 'package:openbiliclaw_app/models/bilibili_interaction.dart';

void main() {
  group('BilibiliCommentApi', () {
    test('resolveAid reads aid from /x/web-interface/view', () async {
      final api = BilibiliCommentApi(
        cookie: 'SESSDATA=x',
        client: _FakeClient((request) {
          expect(request.url.path, '/x/web-interface/view');
          expect(request.url.queryParameters['bvid'], 'BV1xx411c7mD');
          expect(request.headers['cookie'], 'SESSDATA=x');
          return {
            'code': 0,
            'data': {'aid': 2},
          };
        }),
      );

      expect(await api.resolveAid('BV1xx411c7mD'), 2);
    });

    test('videoComments parses replies, sub-replies and pagination', () async {
      final api = BilibiliCommentApi(
        cookie: '',
        client: _FakeClient((request) {
          expect(request.url.path, '/x/v2/reply');
          expect(request.url.queryParameters['pn'], '2');
          expect(request.url.queryParameters['sort'], '2');
          expect(request.headers.containsKey('cookie'), isFalse);
          return {
            'code': 0,
            'data': {
              'page': {'count': 45, 'num': 2, 'size': 20},
              'replies': [
                {
                  'rpid': 11,
                  'mid': 22,
                  'member': {
                    'uname': '甲',
                    'avatar': 'https://i0.hdslb.com/avatar.jpg',
                  },
                  'content': {'message': '前排 &amp; 合影'},
                  'like': 99,
                  'rcount': 3,
                  'replies': [
                    {
                      'rpid': 12,
                      'mid': 23,
                      'member': {
                        'uname': '乙',
                        'avatar': 'https://i0.hdslb.com/reply.jpg',
                      },
                      'content': {'message': '同感'},
                      'like': 4,
                    },
                  ],
                },
              ],
            },
          };
        }),
      );

      final page = await api.videoComments(aid: 2, pn: 2);

      expect(page.total, 45);
      expect(page.page, 2);
      expect(page.hasMore, isTrue); // 2 * 20 = 40 < 45
      expect(page.items.single.rpid, 11);
      expect(page.items.single.uname, '甲');
      expect(page.items.single.avatarUrl, 'https://i0.hdslb.com/avatar.jpg');
      expect(page.items.single.message, '前排 & 合影');
      expect(page.items.single.likeCount, 99);
      expect(page.items.single.replyCount, 3);
      expect(page.items.single.replies.single.uname, '乙');
      expect(
        page.items.single.replies.single.avatarUrl,
        'https://i0.hdslb.com/reply.jpg',
      );
    });

    test('hasMore turns false on the last page', () async {
      final api = BilibiliCommentApi(
        cookie: '',
        client: _FakeClient(
          (request) => {
            'code': 0,
            'data': {
              'page': {'count': 40},
              'replies': const [],
            },
          },
        ),
      );

      final page = await api.videoComments(aid: 2, pn: 2);
      expect(page.hasMore, isFalse); // 2 * 20 = 40, not < 40
    });

    test('commentReplies passes root and parses the thread', () async {
      final api = BilibiliCommentApi(
        cookie: 'SESSDATA=x',
        client: _FakeClient((request) {
          expect(request.url.path, '/x/v2/reply/reply');
          expect(request.url.queryParameters['root'], '495059');
          return {
            'code': 0,
            'data': {
              'page': {'count': 2},
              'replies': [
                {
                  'rpid': 1,
                  'mid': 5,
                  'member': {'uname': '层主'},
                  'content': {'message': '来了'},
                  'like': 1,
                },
              ],
            },
          };
        }),
      );

      final page = await api.commentReplies(aid: 2, root: 495059);
      expect(page.items.single.uname, '层主');
      expect(page.total, 2);
    });

    test('null replies and error codes are handled', () async {
      final emptyApi = BilibiliCommentApi(
        cookie: '',
        client: _FakeClient(
          (request) => {
            'code': 0,
            'data': {'page': null, 'replies': null},
          },
        ),
      );
      final empty = await emptyApi.videoComments(aid: 2);
      expect(empty.items, isEmpty);
      expect(empty.hasMore, isFalse);

      final failingApi = BilibiliCommentApi(
        cookie: '',
        client: _FakeClient((request) => {'code': -412, 'message': '风控'}),
      );
      expect(
        () => failingApi.videoComments(aid: 2),
        throwsA(isA<BilibiliCommentException>()),
      );
    });
  });

  group('BilibiliCommentPage legacy backend parsing', () {
    test('keeps parsing the backend proxy contract', () {
      final page = BilibiliCommentPage.fromJson({
        'ok': true,
        'items': [
          {'rpid': 1, 'mid': 1, 'uname': '甲', 'message': '前排'},
        ],
        'total': 45,
        'page': 1,
        'has_more': true,
      });

      expect(page.items.single.rpid, 1);
      expect(page.total, 45);
      expect(page.hasMore, isTrue);
    });
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final Map<String, dynamic> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = utf8.encode(jsonEncode(handler(request)));
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}
