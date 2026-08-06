import '../api/utils.dart';

class Delight {
  final String bvid;
  final String title;
  final String reason;
  final String coverUrl;
  final String upName;
  final String contentUrl;
  final String sourcePlatform;

  Delight({
    required this.bvid,
    this.title = '',
    this.reason = '',
    this.coverUrl = '',
    this.upName = '',
    this.contentUrl = '',
    this.sourcePlatform = 'bilibili',
  });

  factory Delight.fromJson(Map<String, dynamic> json) => Delight(
    bvid: json['bvid'] ?? '',
    title: decodeHtml(json['title'] ?? ''),
    reason: decodeHtml(json['reason'] ?? ''),
    coverUrl: json['cover_url'] ?? '',
    upName: decodeHtml(json['up_name'] ?? ''),
    contentUrl: json['content_url'] ?? '',
    sourcePlatform: json['source_platform'] ?? 'bilibili',
  );
}
