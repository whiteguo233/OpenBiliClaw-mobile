import 'dart:math';

import '../models/content_history.dart';
import 'client.dart';

/// Bounded content-history access: clicked / shown / removed categories with
/// keyset-cursor pagination, plus the restore helper that re-adds a removed
/// item to a saved list (mirrors the web clients' `saveItem`).
class HistoryApi {
  final ApiClient _client;
  HistoryApi(this._client);

  static const int pageSize = 12;

  Future<ContentHistoryPage> fetch(
    ContentHistoryCategory category, {
    int limit = HistoryApi.pageSize,
    String cursor = '',
  }) async {
    final query = StringBuffer(
      '?category=${Uri.encodeQueryComponent(category.apiValue)}'
      '&limit=${limit.clamp(1, 50)}',
    );
    final trimmedCursor = cursor.trim();
    if (trimmedCursor.isNotEmpty) {
      query.write('&cursor=${Uri.encodeQueryComponent(trimmedCursor)}');
    }
    final data = await _client.get('/content-history$query', timeout: 12);
    return ContentHistoryPage.fromJson(data);
  }

  /// Report that the user opened a history item, best-effort (mirrors the
  /// web clients' `reportClick` used when opening history cards).
  Future<bool> reportClick(ContentHistoryItem item) async {
    try {
      await _client.post(
        '/recommendation-click',
        body: {
          'recommendation_id': item.recommendationId,
          'bvid': item.contentId,
          'content_id': item.contentId,
          'content_url': item.contentUrl,
          'source_platform': item.sourcePlatform,
          'title': item.title,
          'up_name': item.authorName,
          'request_id':
              'history-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}',
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Re-add a removed history item to a saved list (restore action).
  /// Mirrors the web clients' `saveItem(listKind, item)` payload shape.
  Future<Map<String, dynamic>> restore(
    String listKind,
    ContentHistoryItem item,
  ) {
    return _client.post(
      '/saved/$listKind',
      body: {
        'source_platform': item.sourcePlatform,
        'content_id': item.contentId,
        'content_url': item.contentUrl,
        'content_type': item.contentType.isNotEmpty
            ? item.contentType
            : 'video',
        'title': item.title,
        'author_name': item.authorName,
        'cover_url': item.coverUrl,
      },
      timeout: 35,
    );
  }
}
