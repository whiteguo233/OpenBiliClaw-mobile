import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/bilibili_auth.dart';
import '../models/bilibili_interaction.dart';

/// Direct client for Bilibili's comment endpoints.
///
/// The play-url protocol already delivers the backend's Bilibili cookie to
/// the device (the player needs it to fetch the streams), so comment reads
/// reuse that cookie and call `api.bilibili.com` directly — the same pattern
/// the danmaku loader already uses. No WBI signing is required for these
/// endpoints, but anonymous paging is blocked upstream, which is why the
/// cookie matters.
class BilibiliCommentApi {
  BilibiliCommentApi({
    required this.cookie,
    String? userAgent,
    http.Client? client,
  }) : userAgent = userAgent ?? _defaultUserAgent,
       _client = client ?? http.Client();

  /// 从后端导出的 [BilibiliCookieSession] 创建直连客户端。
  factory BilibiliCommentApi.fromSession(BilibiliCookieSession session) {
    return BilibiliCommentApi(
      cookie: session.cookie,
      userAgent: session.userAgent,
    );
  }

  static const String _defaultUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  final String cookie;
  final String userAgent;
  final http.Client _client;

  Map<String, String> get _headers => {
    'referer': 'https://www.bilibili.com',
    'user-agent': userAgent,
    if (cookie.isNotEmpty) 'cookie': cookie,
  };

  /// Resolves the numeric aid for a bvid via `/x/web-interface/view`.
  Future<int> resolveAid(String bvid) async {
    final data = await _getData('/x/web-interface/view', {'bvid': bvid});
    return _int(data['aid']);
  }

  /// Returns Bilibili's `/x/web-interface/view` payload for [bvid].
  /// The response contains the video `desc`, title, owner, stat and other
  /// metadata used by the native player's intro tab.
  Future<Map<String, dynamic>> videoInfo(String bvid) async {
    return _getData('/x/web-interface/view', {'bvid': bvid});
  }

  /// `/x/v2/reply` — hot-sorted top-level comments, page-numbered.
  Future<BilibiliCommentPage> videoComments({
    required int aid,
    int pn = 1,
    int ps = 20,
  }) async {
    final data = await _getData('/x/v2/reply', {
      'type': '1',
      'oid': '$aid',
      'sort': '2',
      'pn': '$pn',
      'ps': '$ps',
    });
    return BilibiliCommentPage.fromBilibiliJson(data, page: pn, pageSize: ps);
  }

  /// `/x/v2/reply/reply` — the full reply thread under one root comment.
  Future<BilibiliCommentPage> commentReplies({
    required int aid,
    required int root,
    int pn = 1,
    int ps = 10,
  }) async {
    final data = await _getData('/x/v2/reply/reply', {
      'type': '1',
      'oid': '$aid',
      'root': '$root',
      'pn': '$pn',
      'ps': '$ps',
    });
    return BilibiliCommentPage.fromBilibiliJson(data, page: pn, pageSize: ps);
  }

  Future<Map<String, dynamic>> _getData(
    String path,
    Map<String, String> query,
  ) async {
    final response = await _client.get(
      Uri.https('api.bilibili.com', path, query),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw BilibiliCommentException('HTTP ${response.statusCode}');
    }
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload is! Map) {
      throw const BilibiliCommentException('unexpected payload');
    }
    if (_int(payload['code']) != 0) {
      throw BilibiliCommentException(
        'bilibili error ${payload['code']}: ${payload['message']}',
      );
    }
    final data = payload['data'];
    return data is Map ? Map<String, dynamic>.from(data) : const {};
  }

  static int _int(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class BilibiliCommentException implements Exception {
  const BilibiliCommentException(this.message);
  final String message;

  @override
  String toString() => 'BilibiliCommentException: $message';
}
