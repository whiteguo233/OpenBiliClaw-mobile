import '../api/utils.dart';

class Recommendation {
  final int id;
  final String bvid;
  final String title;
  final String upName;
  final String coverUrl;
  final String expression;
  final String topicLabel;
  final String contentUrl;
  final String sourcePlatform;
  final String contentType;
  final String bodyText;
  String feedbackType;

  Recommendation({
    required this.id,
    required this.bvid,
    this.title = '',
    this.upName = '',
    this.coverUrl = '',
    this.expression = '',
    this.topicLabel = '',
    this.contentUrl = '',
    this.sourcePlatform = 'bilibili',
    this.contentType = 'video',
    this.bodyText = '',
    this.feedbackType = '',
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      id: json['id'] ?? 0,
      bvid: json['bvid'] ?? '',
      title: decodeHtml(json['title'] ?? ''),
      upName: decodeHtml(json['up_name'] ?? ''),
      coverUrl: json['cover_url'] ?? '',
      expression: decodeHtml(json['expression'] ?? ''),
      topicLabel: decodeHtml(json['topic_label'] ?? ''),
      contentUrl: json['content_url'] ?? '',
      sourcePlatform: json['source_platform'] ?? 'bilibili',
      contentType: json['content_type'] ?? 'video',
      bodyText: decodeHtml(json['body_text'] ?? ''),
      feedbackType: json['feedback_type'] ?? '',
    );
  }

  String get displayTitle => title.isNotEmpty ? title : '这条标题还没对上号';
  String get displayUpName => upName.isNotEmpty ? upName : '这位 UP 还没认出来';
  bool get isTextCard => contentType == 'tweet' || contentType == 'thread';
}
