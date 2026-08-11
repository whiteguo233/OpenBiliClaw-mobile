import '../api/utils.dart';

/// One bounded content-history category. Mirrors the backend
/// `ContentHistoryCategory` literal: `clicked` / `shown` / `removed`.
enum ContentHistoryCategory {
  clicked('clicked'),
  shown('shown'),
  removed('removed');

  const ContentHistoryCategory(this.apiValue);
  final String apiValue;

  static ContentHistoryCategory parse(String value) {
    return switch (value) {
      'clicked' => ContentHistoryCategory.clicked,
      'shown' => ContentHistoryCategory.shown,
      'removed' => ContentHistoryCategory.removed,
      _ => ContentHistoryCategory.clicked,
    };
  }
}

/// One removal context attached to a removed history card, e.g. which list
/// the item was removed from and whether it has been restored.
class ContentHistoryContext {
  final String context;
  final String occurredAt;
  final bool restored;

  const ContentHistoryContext({
    required this.context,
    required this.occurredAt,
    this.restored = false,
  });

  factory ContentHistoryContext.fromJson(Map<String, dynamic> json) {
    return ContentHistoryContext(
      context: _text(json['context']),
      occurredAt: _text(json['occurred_at']),
      restored: json['restored'] == true,
    );
  }

  /// Whether this context is a restorable saved-list membership.
  bool get restorable => context == 'favorite' || context == 'watch_later';

  String get restoreLabel => context == 'favorite' ? '重新收藏' : '重新加入稍后';

  String get removalLabel {
    return switch (context) {
      'watch_later' => '从稍后再看移除',
      'favorite' => '从收藏移除',
      'dismiss' => '已忽略',
      'dislike' => '不感兴趣',
      _ => '已移除',
    };
  }
}

/// One canonical item in a bounded content-history category.
class ContentHistoryItem {
  final String itemKey;
  final String sourcePlatform;
  final String contentId;
  final String contentUrl;
  final String contentType;
  final String title;
  final String authorName;
  final String coverUrl;
  final String bodyText;
  final int? recommendationId;
  final String occurredAt;
  final String context;
  final bool restored;
  final List<ContentHistoryContext> contexts;

  const ContentHistoryItem({
    required this.itemKey,
    required this.sourcePlatform,
    this.contentId = '',
    this.contentUrl = '',
    this.contentType = 'video',
    this.title = '',
    this.authorName = '',
    this.coverUrl = '',
    this.bodyText = '',
    this.recommendationId,
    this.occurredAt = '',
    this.context = '',
    this.restored = false,
    this.contexts = const [],
  });

  factory ContentHistoryItem.fromJson(Map<String, dynamic> json) {
    final rawContexts = json['contexts'];
    final contexts = rawContexts is List
        ? rawContexts
              .whereType<Map>()
              .map(
                (item) => ContentHistoryContext.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : <ContentHistoryContext>[];
    return ContentHistoryItem(
      itemKey: _text(json['item_key']),
      sourcePlatform: _text(json['source_platform']).isNotEmpty
          ? _text(json['source_platform'])
          : 'bilibili',
      contentId: _text(json['content_id']),
      contentUrl: _text(json['content_url']),
      contentType: _text(json['content_type']).isNotEmpty
          ? _text(json['content_type'])
          : 'video',
      title: decodeHtml(_text(json['title'])),
      authorName: decodeHtml(_text(json['author_name'])),
      coverUrl: _text(json['cover_url']),
      bodyText: decodeHtml(_text(json['body_text'])),
      recommendationId: json['recommendation_id'] is num
          ? (json['recommendation_id'] as num).toInt()
          : null,
      occurredAt: _text(json['occurred_at']),
      context: _text(json['context']),
      restored: json['restored'] == true,
      contexts: contexts,
    );
  }

  /// Whether the card currently carries any restore-able saved context that
  /// has not been restored yet.
  bool get canRestore =>
      contexts.any((entry) => entry.restorable && !entry.restored);

  /// Event label used by the history list header, matching the web clients.
  String eventLabelFor(ContentHistoryCategory category) {
    if (category == ContentHistoryCategory.clicked) return '点开';
    if (category == ContentHistoryCategory.shown) return '出现';
    if (contexts.isNotEmpty) return contexts.first.removalLabel;
    return context.isNotEmpty ? _removalLabelFor(context) : '已移除';
  }

  static String _removalLabelFor(String context) {
    return switch (context) {
      'watch_later' => '从稍后再看移除',
      'favorite' => '从收藏移除',
      'dismiss' => '已忽略',
      'dislike' => '不感兴趣',
      _ => '已移除',
    };
  }
}

/// One paginated content-history category page.
class ContentHistoryPage {
  final ContentHistoryCategory category;
  final List<ContentHistoryItem> items;
  final int total;
  final int retentionDays;
  final String nextCursor;
  final bool hasMore;

  const ContentHistoryPage({
    required this.category,
    required this.items,
    this.total = 0,
    this.retentionDays = 30,
    this.nextCursor = '',
    this.hasMore = false,
  });

  factory ContentHistoryPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ContentHistoryPage(
      category: ContentHistoryCategory.parse(_text(json['category'])),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => ContentHistoryItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
      total: json['total'] is num ? (json['total'] as num).toInt() : 0,
      retentionDays: json['retention_days'] is num
          ? (json['retention_days'] as num).toInt()
          : 30,
      nextCursor: json['has_more'] == true ? _text(json['next_cursor']) : '',
      hasMore: json['has_more'] == true,
    );
  }
}

String _text(dynamic value) => value?.toString().trim() ?? '';
