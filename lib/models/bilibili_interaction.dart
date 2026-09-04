import '../api/utils.dart';

class BilibiliVideoState {
  final bool like;
  final int coin;
  final bool favorite;
  final bool watchLater;

  const BilibiliVideoState({
    this.like = false,
    this.coin = 0,
    this.favorite = false,
    this.watchLater = false,
  });

  factory BilibiliVideoState.fromJson(Map<String, dynamic> json) =>
      BilibiliVideoState(
        like: json['like'] == true,
        coin: _int(json['coin']),
        favorite: json['favorite'] == true,
        watchLater: json['watch_later'] == true,
      );

  BilibiliVideoState copyWith({
    bool? like,
    int? coin,
    bool? favorite,
    bool? watchLater,
  }) => BilibiliVideoState(
    like: like ?? this.like,
    coin: coin ?? this.coin,
    favorite: favorite ?? this.favorite,
    watchLater: watchLater ?? this.watchLater,
  );
}

class BilibiliRelatedVideo {
  final String bvid;
  final String title;
  final String coverUrl;
  final String upName;
  final int view;

  const BilibiliRelatedVideo({
    this.bvid = '',
    this.title = '',
    this.coverUrl = '',
    this.upName = '',
    this.view = 0,
  });

  factory BilibiliRelatedVideo.fromJson(Map<String, dynamic> json) {
    final stat = json['stat'];
    final statMap = stat is Map ? Map<String, dynamic>.from(stat) : const {};
    final owner = json['owner'];
    final ownerMap = owner is Map ? Map<String, dynamic>.from(owner) : const {};
    return BilibiliRelatedVideo(
      bvid: _text(json['bvid']),
      title: decodeHtml(_text(json['title'])),
      coverUrl: _text(json['pic'] ?? json['cover']),
      upName: decodeHtml(_text(ownerMap['name'] ?? '')),
      view: _int(statMap['view']),
    );
  }
}

class BilibiliComment {
  final int rpid;
  final int mid;
  final String uname;
  final String message;
  final int likeCount;
  final int replyCount;
  final List<BilibiliComment> replies;

  const BilibiliComment({
    this.rpid = 0,
    this.mid = 0,
    this.uname = '',
    this.message = '',
    this.likeCount = 0,
    this.replyCount = 0,
    this.replies = const [],
  });

  factory BilibiliComment.fromJson(Map<String, dynamic> json) {
    final rawReplies = json['replies'];
    return BilibiliComment(
      rpid: _int(json['rpid']),
      mid: _int(json['mid']),
      uname: _text(json['uname']),
      message: decodeHtml(_text(json['message'])),
      likeCount: _int(json['like_count']),
      replyCount: _int(json['reply_count']),
      replies: rawReplies is List
          ? rawReplies
                .whereType<Map>()
                .map(
                  (item) =>
                      BilibiliComment.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
    );
  }

  /// Parses one raw item of Bilibili's `/x/v2/reply` family of endpoints,
  /// including the embedded preview sub-replies.
  factory BilibiliComment.fromBilibiliJson(Map<String, dynamic> json) {
    final member = json['member'];
    final content = json['content'];
    final rawReplies = json['replies'];
    return BilibiliComment(
      rpid: _int(json['rpid']),
      mid: _int(json['mid']),
      uname: member is Map ? _text(member['uname']) : '',
      message: decodeHtml(content is Map ? _text(content['message']) : ''),
      likeCount: _int(json['like']),
      replyCount: _int(json['rcount']),
      replies: rawReplies is List
          ? rawReplies
                .whereType<Map>()
                .map(
                  (item) => BilibiliComment.fromBilibiliJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }
}

class BilibiliCommentPage {
  final List<BilibiliComment> items;
  final int total;
  final int page;
  final bool hasMore;

  const BilibiliCommentPage({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.hasMore = false,
  });

  factory BilibiliCommentPage.fromJson(Map<String, dynamic> data) {
    final rawItems = data['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) =>
                    BilibiliComment.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const <BilibiliComment>[];
    return BilibiliCommentPage(
      items: items,
      total: _int(data['total']),
      page: _int(data['page']) == 0 ? 1 : _int(data['page']),
      hasMore: data['has_more'] == true,
    );
  }

  /// Parses the `data` payload of Bilibili's `/x/v2/reply` or
  /// `/x/v2/reply/reply` endpoints. `page.count` is trusted as-is; Bilibili
  /// may report fewer than the true total, so [hasMore] is a best-effort
  /// estimate from the returned metadata.
  factory BilibiliCommentPage.fromBilibiliJson(
    Map<String, dynamic> data, {
    required int page,
    required int pageSize,
  }) {
    final pageInfo = data['page'];
    final total = pageInfo is Map ? _int(pageInfo['count']) : 0;
    final rawItems = data['replies'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (item) => BilibiliComment.fromBilibiliJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : const <BilibiliComment>[];
    return BilibiliCommentPage(
      items: items.length > pageSize ? items.sublist(0, pageSize) : items,
      total: total,
      page: page,
      hasMore: page * pageSize < total,
    );
  }
}

String _text(dynamic value) => value?.toString().trim() ?? '';

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(_text(value)) ?? 0;
}
