import '../models/bilibili_auth.dart';
import '../models/bilibili_interaction.dart';
import '../models/bilibili_play.dart';
import 'client.dart';

/// Client for the Bilibili auth/player protocol exposed by the OpenBiliClaw
/// backend. The backend owns Bilibili cookies and WBI signing; the mobile
/// client only exchanges high-level auth and play-url payloads.
class BilibiliApi {
  final ApiClient _client;
  BilibiliApi(this._client);

  /// `GET /api/bilibili/auth/status`
  Future<BilibiliAuthInfo> authStatus() async {
    final data = await _client.get('/bilibili/auth/status');
    return BilibiliAuthInfo.fromJson(data);
  }

  /// `POST /api/bilibili/auth/qrcode`
  Future<BilibiliQrLogin> startQrLogin() async {
    final data = await _client.post('/bilibili/auth/qrcode', body: const {});
    return BilibiliQrLogin.fromJson(data);
  }

  /// `GET /api/bilibili/auth/qrcode/poll?key=...`
  Future<BilibiliQrPoll> pollQrLogin({required String qrcodeKey}) async {
    final data = await _client.get(
      '/bilibili/auth/qrcode/poll?key=${Uri.encodeQueryComponent(qrcodeKey)}',
    );
    return BilibiliQrPoll.fromJson(data);
  }

  /// `POST /api/bilibili/auth/import`
  Future<BilibiliAuthInfo> importSession({
    required Map<String, String> cookies,
    String userAgent = '',
    String buvid = '',
    String source = 'mobile_webview',
  }) async {
    final data = await _client.post(
      '/bilibili/auth/import',
      body: {
        'cookies': cookies,
        'user_agent': userAgent,
        'buvid': buvid,
        'source': source,
      },
    );
    return BilibiliAuthInfo.fromJson(data);
  }

  /// `DELETE /api/bilibili/auth/session`
  Future<void> clearSession() async {
    await _client.delete('/bilibili/auth/session');
  }

  /// `POST /api/bilibili/player/play-url`
  Future<BilibiliPlayResult> playUrl({
    required String bvid,
    int? cid,
    int? qn,
    String? preferredCodec,
    int? fnval,
    int? fourk,
  }) async {
    final data = await _client.post(
      '/bilibili/player/play-url',
      body: {
        'bvid': bvid,
        'cid': ?cid,
        'qn': ?qn,
        if (preferredCodec != null && preferredCodec.isNotEmpty)
          'preferred_codec': preferredCodec,
        'fnval': ?fnval,
        'fourk': ?fourk,
      },
      timeout: 30,
    );
    return BilibiliPlayResult.fromJson(data);
  }

  /// `GET /api/bilibili/video/relation?bvid=...`
  Future<BilibiliVideoState> videoRelation({required String bvid}) async {
    final data = await _client.get(
      '/bilibili/video/relation?bvid=${Uri.encodeQueryComponent(bvid)}',
    );
    return BilibiliVideoState.fromJson(data);
  }

  /// `POST /api/bilibili/video/like`
  Future<BilibiliVideoState> likeVideo(
    String bvid, {
    required bool like,
  }) async {
    final data = await _client.post(
      '/bilibili/video/like',
      body: {'bvid': bvid, 'like': like},
    );
    return BilibiliVideoState.fromJson({...data, 'like': like});
  }

  /// `POST /api/bilibili/video/coin`
  Future<void> coinVideo(
    String bvid, {
    int multiply = 1,
    bool selectLike = false,
  }) async {
    await _client.post(
      '/bilibili/video/coin',
      body: {'bvid': bvid, 'multiply': multiply, 'select_like': selectLike},
    );
  }

  /// `POST /api/bilibili/video/triple`
  Future<BilibiliVideoState> tripleVideo(String bvid) async {
    final data = await _client.post(
      '/bilibili/video/triple',
      body: {'bvid': bvid},
    );
    return BilibiliVideoState.fromJson(
      data['state'] is Map
          ? Map<String, dynamic>.from(data['state'] as Map)
          : const {},
    );
  }

  /// `POST /api/bilibili/video/favorite`
  Future<BilibiliVideoState> favoriteVideo(
    String bvid, {
    required bool favorite,
    int? mediaId,
  }) async {
    final data = await _client.post(
      '/bilibili/video/favorite',
      body: {'bvid': bvid, 'favorite': favorite, 'media_id': ?mediaId},
    );
    return BilibiliVideoState.fromJson(
      data['state'] is Map
          ? Map<String, dynamic>.from(data['state'] as Map)
          : const {},
    );
  }

  /// `POST /api/bilibili/video/watch-later`
  Future<BilibiliVideoState> watchLaterVideo(
    String bvid, {
    required bool add,
  }) async {
    final data = await _client.post(
      '/bilibili/video/watch-later',
      body: {'bvid': bvid, 'add': add},
    );
    return BilibiliVideoState.fromJson(
      data['state'] is Map
          ? Map<String, dynamic>.from(data['state'] as Map)
          : const {},
    );
  }

  /// `GET /api/bilibili/video/related?bvid=...`
  Future<List<BilibiliRelatedVideo>> relatedVideos({
    required String bvid,
  }) async {
    final data = await _client.get(
      '/bilibili/video/related?bvid=${Uri.encodeQueryComponent(bvid)}',
    );
    final rawItems = data['items'];
    if (rawItems is List) {
      return rawItems
          .whereType<Map>()
          .map(
            (item) =>
                BilibiliRelatedVideo.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    }
    return const [];
  }

  /// `GET /api/bilibili/video/comments?bvid=...&pn=...&limit=...`
  Future<BilibiliCommentPage> videoComments({
    required String bvid,
    int pn = 1,
    int limit = 20,
  }) async {
    final data = await _client.get(
      '/bilibili/video/comments?bvid=${Uri.encodeQueryComponent(bvid)}&pn=$pn&limit=$limit',
    );
    return BilibiliCommentPage.fromJson(data);
  }

  /// `GET /api/bilibili/video/comment-replies?bvid=...&root=...&pn=...&limit=...`
  Future<BilibiliCommentPage> commentReplies({
    required String bvid,
    required int root,
    int pn = 1,
    int limit = 10,
  }) async {
    final data = await _client.get(
      '/bilibili/video/comment-replies?bvid=${Uri.encodeQueryComponent(bvid)}&root=$root&pn=$pn&limit=$limit',
    );
    return BilibiliCommentPage.fromJson(data);
  }
}
