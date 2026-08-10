import '../api/utils.dart';
import 'recommendation.dart';

enum SavedListKind {
  watchLater('watch_later', '稍后再看'),
  favorite('favorite', '收藏');

  const SavedListKind(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class SavedItem {
  final String itemKey;
  final String sourcePlatform;
  final String contentId;
  final String contentUrl;
  final String contentType;
  final String title;
  final String coverUrl;
  final String authorName;
  final String note;
  final String addedAt;
  final String syncStatus;
  final String syncTaskId;
  final String resolvedTarget;
  final String errorCode;
  final String errorMessage;

  const SavedItem({
    required this.itemKey,
    required this.sourcePlatform,
    required this.contentId,
    this.contentUrl = '',
    this.contentType = 'video',
    this.title = '',
    this.coverUrl = '',
    this.authorName = '',
    this.note = '',
    this.addedAt = '',
    this.syncStatus = 'pending',
    this.syncTaskId = '',
    this.resolvedTarget = '',
    this.errorCode = '',
    this.errorMessage = '',
  });

  factory SavedItem.fromJson(Map<String, dynamic> json) {
    final legacyBvid = _text(json['bvid']);
    final source = normalizeSourcePlatform(
      _text(json['source_platform']),
      contentUrl: _text(json['content_url']),
      bvid: legacyBvid,
    );
    final contentId = _text(json['content_id']).isNotEmpty
        ? _text(json['content_id'])
        : (legacyBvid.contains(':')
              ? legacyBvid.split(':').skip(1).join(':')
              : legacyBvid);
    return SavedItem(
      itemKey: _text(json['item_key']).isNotEmpty
          ? _text(json['item_key'])
          : '$source:$contentId',
      sourcePlatform: source,
      contentId: contentId,
      contentUrl: _text(json['content_url']),
      contentType: _text(json['content_type']).isNotEmpty
          ? _text(json['content_type'])
          : 'video',
      title: decodeHtml(_text(json['title'])),
      coverUrl: _text(json['cover_url']),
      authorName: decodeHtml(
        _text(json['author_name']).isNotEmpty
            ? _text(json['author_name'])
            : _text(json['up_name']),
      ),
      note: decodeHtml(_text(json['note'])),
      addedAt: _text(json['added_at']),
      syncStatus: _text(json['sync_status']).isNotEmpty
          ? _text(json['sync_status'])
          : 'pending',
      syncTaskId: _text(json['sync_task_id']),
      resolvedTarget: decodeHtml(_text(json['resolved_target'])),
      errorCode: _text(json['error_code']),
      errorMessage: decodeHtml(_text(json['error_message'])),
    );
  }

  factory SavedItem.fromRecommendation(Recommendation item) => SavedItem(
    itemKey: item.savedIdentity,
    sourcePlatform: item.sourcePlatform,
    contentId: item.contentId,
    contentUrl: item.contentUrl,
    contentType: item.contentType,
    title: item.title,
    coverUrl: item.coverUrl,
    authorName: item.upName,
  );

  String get bvid =>
      sourcePlatform == 'bilibili' ? contentId : '$sourcePlatform:$contentId';
  String get upName => authorName;
  bool get synced => syncStatus == 'synced' || syncStatus == 'already_synced';
  bool get syncing =>
      syncStatus == 'syncing' ||
      (syncStatus == 'pending' && syncTaskId.isNotEmpty);
  bool get localOnly =>
      syncStatus == 'unsupported' && errorCode == 'unsupported_content_type';
  bool get canSync => !synced && !syncing && !localOnly;

  String get syncLabel {
    switch (syncStatus) {
      case 'syncing':
        return '同步中';
      case 'synced':
      case 'already_synced':
        return '已同步';
      case 'login_required':
        return '需要登录';
      case 'extension_required':
        return '需要插件';
      case 'rate_limited':
      case 'failed':
        return '同步失败';
      case 'unsupported':
        return localOnly ? '仅本地保存' : '同步暂不可用';
      default:
        return '待同步';
    }
  }

  String get syncDetail {
    if (errorMessage.isNotEmpty) return errorMessage;
    if (resolvedTarget.isNotEmpty) return resolvedTarget;
    switch (syncStatus) {
      case 'login_required':
        return '请先登录对应平台后重试。';
      case 'extension_required':
        return '请连接装有 OpenBiliClaw 插件的登录态浏览器。';
      case 'rate_limited':
        return '平台请求较频繁，请稍后重试。';
      case 'failed':
        return '平台同步失败，可以重试。';
      case 'unsupported':
        return localOnly ? '此内容类型暂时只能保存在本地。' : '请更新后端和插件后重试。';
      case 'syncing':
        return '平台同步任务已提交。';
      case 'synced':
      case 'already_synced':
        return '平台已确认同步完成。';
      default:
        return '已保存在 OpenBiliClaw，可手动同步到平台。';
    }
  }

  Map<String, dynamic> toSavePayload() => {
    'source_platform': sourcePlatform,
    'content_id': contentId,
    'content_url': contentUrl,
    'content_type': contentType,
    'title': title,
    'author_name': authorName,
    'cover_url': coverUrl,
    'note': note,
  };
}

String _text(dynamic value) => value?.toString().trim() ?? '';
