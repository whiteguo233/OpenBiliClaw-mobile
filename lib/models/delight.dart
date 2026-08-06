import '../api/utils.dart';

class Delight {
  final String bvid;
  final String title;
  final String reason;
  final String coverUrl;
  final String contentUrl;
  final String sourcePlatform;

  Delight({
    required this.bvid,
    this.title = '',
    this.reason = '',
    this.coverUrl = '',
    this.contentUrl = '',
    this.sourcePlatform = 'bilibili',
  });

  factory Delight.fromJson(Map<String, dynamic> json) => Delight(
    bvid: json['bvid'] ?? '',
    title: decodeHtml(json['title'] ?? ''),
    reason: decodeHtml(json['delight_reason'] ?? ''),
    coverUrl: json['cover_url'] ?? '',
    contentUrl: json['content_url'] ?? '',
    sourcePlatform: json['source_platform'] ?? 'bilibili',
  );
}
