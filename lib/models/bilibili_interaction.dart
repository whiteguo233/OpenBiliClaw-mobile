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
  final int mid;
  final String uname;
  final String message;
  final int likeCount;

  const BilibiliComment({
    this.mid = 0,
    this.uname = '',
    this.message = '',
    this.likeCount = 0,
  });

  factory BilibiliComment.fromJson(Map<String, dynamic> json) =>
      BilibiliComment(
        mid: _int(json['mid']),
        uname: _text(json['uname']),
        message: decodeHtml(_text(json['message'])),
        likeCount: _int(json['like_count']),
      );
}

String _text(dynamic value) => value?.toString().trim() ?? '';

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(_text(value)) ?? 0;
}
