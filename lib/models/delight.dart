import '../api/utils.dart';

class Delight {
  final String bvid;
  final String itemKey;
  final String contentId;
  final String title;
  final String reason;
  final String hook;
  final String coverUrl;
  final String contentUrl;
  final String sourcePlatform;
  final String contentType;
  final String bodyText;
  final String state;

  Delight({
    required this.bvid,
    this.itemKey = '',
    this.contentId = '',
    this.title = '',
    this.reason = '',
    this.hook = '',
    this.coverUrl = '',
    this.contentUrl = '',
    this.sourcePlatform = 'bilibili',
    this.contentType = 'video',
    this.bodyText = '',
    this.state = 'pending',
  });

  factory Delight.fromJson(Map<String, dynamic> json) {
    final bvid = json['bvid']?.toString() ?? '';
    final contentId = json['content_id']?.toString() ?? '';
    return Delight(
      bvid: bvid,
      itemKey:
          json['item_key']?.toString() ??
          (contentId.isEmpty ? '' : '${json['source_platform']}:$contentId'),
      contentId: contentId,
      title: decodeHtml(json['title']?.toString() ?? ''),
      reason: decodeHtml(json['delight_reason']?.toString() ?? ''),
      hook: decodeHtml(json['delight_hook']?.toString() ?? ''),
      coverUrl: json['cover_url']?.toString() ?? '',
      contentUrl: json['content_url']?.toString() ?? '',
      sourcePlatform: json['source_platform']?.toString() ?? 'bilibili',
      contentType: json['content_type']?.toString() ?? 'video',
      bodyText: decodeHtml(json['body_text']?.toString() ?? ''),
      state: json['state']?.toString() ?? 'pending',
    );
  }

  Delight copyWith({String? state}) => Delight(
    bvid: bvid,
    itemKey: itemKey,
    contentId: contentId,
    title: title,
    reason: reason,
    hook: hook,
    coverUrl: coverUrl,
    contentUrl: contentUrl,
    sourcePlatform: sourcePlatform,
    contentType: contentType,
    bodyText: bodyText,
    state: state ?? this.state,
  );
}
