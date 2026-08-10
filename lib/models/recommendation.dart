import '../api/utils.dart';

class Recommendation {
  final int id;
  final String bvid;
  final String itemKey;
  final String contentId;
  final String title;
  final String upName;
  final String coverUrl;
  final String expression;
  final String topicLabel;
  final String contentUrl;
  final String sourcePlatform;
  final String contentType;
  final String bodyText;
  final String publishedAt;
  final String publishedLabel;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int favoriteCount;
  final int danmakuCount;
  final double ratingScore;
  final int ratingCount;
  final int sourceRank;
  String feedbackType;

  Recommendation({
    required this.id,
    required this.bvid,
    this.itemKey = '',
    this.contentId = '',
    this.title = '',
    this.upName = '',
    this.coverUrl = '',
    this.expression = '',
    this.topicLabel = '',
    this.contentUrl = '',
    this.sourcePlatform = 'bilibili',
    this.contentType = 'video',
    this.bodyText = '',
    this.publishedAt = '',
    this.publishedLabel = '',
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.favoriteCount = 0,
    this.danmakuCount = 0,
    this.ratingScore = 0,
    this.ratingCount = 0,
    this.sourceRank = 0,
    this.feedbackType = '',
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    final bvid = _text(json['bvid']);
    final source = normalizeSourcePlatform(
      _text(json['source_platform']),
      contentUrl: _text(json['content_url']),
      bvid: bvid,
    );
    final explicitContentId = _text(json['content_id']);
    final contentId = explicitContentId.isNotEmpty
        ? explicitContentId
        : (bvid.contains(':') ? bvid.split(':').skip(1).join(':') : bvid);
    return Recommendation(
      id: _integer(json['id']),
      bvid: bvid,
      itemKey: _text(json['item_key']).isNotEmpty
          ? _text(json['item_key'])
          : (contentId.isEmpty ? '' : '$source:$contentId'),
      contentId: contentId,
      title: decodeHtml(_text(json['title'])),
      upName: decodeHtml(_text(json['up_name'])),
      coverUrl: _text(json['cover_url']),
      expression: decodeHtml(_text(json['expression'])),
      topicLabel: decodeHtml(_text(json['topic_label'])),
      contentUrl: _text(json['content_url']),
      sourcePlatform: source,
      contentType: _text(json['content_type']).isNotEmpty
          ? _text(json['content_type'])
          : 'video',
      bodyText: decodeHtml(_text(json['body_text'])),
      publishedAt: _text(json['published_at']),
      publishedLabel: _text(json['published_label']),
      viewCount: _integer(json['view_count']),
      likeCount: _integer(json['like_count']),
      commentCount: _integer(json['comment_count']),
      favoriteCount: _integer(json['favorite_count']),
      danmakuCount: _integer(json['danmaku_count']),
      ratingScore: _number(json['rating_score']),
      ratingCount: _integer(json['rating_count']),
      sourceRank: _integer(json['source_rank']),
      feedbackType: _text(json['feedback_type']),
    );
  }

  String get displayTitle => title.isNotEmpty ? title : '这条标题还没对上号';
  String get displayUpName => upName.isNotEmpty ? upName : '这位 UP 还没认出来';
  bool get isTextCard =>
      coverUrl.isEmpty ||
      const {
        'tweet',
        'thread',
        'answer',
        'article',
        'question',
        'post',
        'comment',
      }.contains(contentType.toLowerCase());

  String get savedIdentity {
    if (itemKey.isNotEmpty) return itemKey;
    if (contentId.isNotEmpty) return '$sourcePlatform:$contentId';
    if (bvid.isNotEmpty) return '$sourcePlatform:$bvid';
    return contentUrl;
  }

  Map<String, dynamic> toSavedPayload() => {
    'source_platform': sourcePlatform,
    'content_id': contentId,
    'content_url': contentUrl,
    'content_type': contentType,
    'title': title,
    'author_name': upName,
    'cover_url': coverUrl,
    'note': '',
  };

  String get statsLabel {
    final parts = <String>[];
    if (viewCount > 0) parts.add('▶ ${formatCount(viewCount)}');
    if (likeCount > 0) parts.add('👍 ${formatCount(likeCount)}');
    if (commentCount > 0) parts.add('💬 ${formatCount(commentCount)}');
    if (favoriteCount > 0) parts.add('⭐ ${formatCount(favoriteCount)}');
    if (danmakuCount > 0) parts.add('弹幕 ${formatCount(danmakuCount)}');
    if (ratingScore > 0) parts.add('评分 ${ratingScore.toStringAsFixed(1)}');
    if (ratingCount > 0) parts.add('${formatCount(ratingCount)} 人评分');
    if (sourceRank > 0) parts.add('排名 #$sourceRank');
    return parts.join(' · ');
  }

  String get publishedDisplay {
    final parsed = DateTime.tryParse(publishedAt)?.toLocal();
    if (parsed == null) return publishedLabel;
    final now = DateTime.now();
    final difference = now.difference(parsed);
    if (!difference.isNegative && difference.inMinutes < 1) return '刚刚';
    if (!difference.isNegative && difference.inHours < 24) {
      return '${difference.inHours.clamp(1, 23)} 小时前';
    }
    if (!difference.isNegative && difference.inDays < 7) {
      return '${difference.inDays} 天前';
    }
    if (parsed.year == now.year) return '${parsed.month}月${parsed.day}日';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}

String normalizeSourcePlatform(
  String value, {
  String contentUrl = '',
  String bvid = '',
}) {
  final source = value.trim().toLowerCase();
  const aliases = {
    'bili': 'bilibili',
    'bilibili': 'bilibili',
    'xhs': 'xiaohongshu',
    'xiaohongshu': 'xiaohongshu',
    'dy': 'douyin',
    'douyin': 'douyin',
    'yt': 'youtube',
    'youtube': 'youtube',
    'x': 'twitter',
    'twitter': 'twitter',
    'zhihu': 'zhihu',
    'reddit': 'reddit',
    'bangumi': 'bangumi',
    'web': 'web',
  };
  if (aliases.containsKey(source)) return aliases[source]!;
  final url = contentUrl.toLowerCase();
  if (url.contains('bilibili.com') || url.contains('b23.tv')) {
    return 'bilibili';
  }
  if (url.contains('xiaohongshu.com') || url.contains('xhslink.com')) {
    return 'xiaohongshu';
  }
  if (url.contains('douyin.com')) return 'douyin';
  if (url.contains('youtube.com') || url.contains('youtu.be')) {
    return 'youtube';
  }
  if (url.contains('x.com') || url.contains('twitter.com')) return 'twitter';
  if (url.contains('zhihu.com')) return 'zhihu';
  if (url.contains('reddit.com') || url.contains('redd.it')) return 'reddit';
  if (url.contains('bgm.tv') || url.contains('bangumi.tv')) return 'bangumi';
  if (bvid.isNotEmpty && !bvid.contains(':')) return 'bilibili';
  return source.isEmpty ? 'web' : source;
}

String formatCount(int value) {
  if (value >= 100000000) {
    return _compactNumber(value / 100000000, '亿');
  }
  if (value >= 10000) return _compactNumber(value / 10000, '万');
  return value.toString();
}

String _compactNumber(double value, String suffix) {
  final fixed = value.toStringAsFixed(1);
  return '${fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed}$suffix';
}

String _text(dynamic value) => value?.toString().trim() ?? '';

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(_text(value)) ?? 0;
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value)) ?? 0;
}
