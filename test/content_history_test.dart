import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/content_history.dart';

void main() {
  test('parses content history categories', () {
    expect(
      ContentHistoryCategory.parse('clicked'),
      ContentHistoryCategory.clicked,
    );
    expect(ContentHistoryCategory.parse('shown'), ContentHistoryCategory.shown);
    expect(
      ContentHistoryCategory.parse('removed'),
      ContentHistoryCategory.removed,
    );
    expect(
      ContentHistoryCategory.parse('unknown'),
      ContentHistoryCategory.clicked,
    );
  });

  test('parses history item with restored contexts', () {
    final item = ContentHistoryItem.fromJson({
      'item_key': 'bilibili:BV123',
      'source_platform': 'bilibili',
      'content_id': 'BV123',
      'title': '测试视频',
      'author_name': 'UP主',
      'cover_url': 'https://i0.hdslb.com/x.jpg',
      'occurred_at': '2025-01-01 10:00:00',
      'context': 'favorite',
      'restored': false,
      'contexts': [
        {
          'context': 'favorite',
          'occurred_at': '2025-01-01 10:00:00',
          'restored': false,
        },
        {
          'context': 'dismiss',
          'occurred_at': '2025-01-02 08:00:00',
          'restored': true,
        },
      ],
    });

    expect(item.itemKey, 'bilibili:BV123');
    expect(item.sourcePlatform, 'bilibili');
    expect(item.title, '测试视频');
    expect(item.contexts, hasLength(2));
    expect(item.contexts.first.context, 'favorite');
    expect(item.contexts.first.restorable, isTrue);
    expect(item.contexts.first.restoreLabel, '重新收藏');
    expect(item.contexts.last.context, 'dismiss');
    expect(item.contexts.last.restorable, isFalse);
    expect(item.canRestore, isTrue);
  });

  test('event labels match web clients per category', () {
    final item = ContentHistoryItem.fromJson({
      'item_key': 'bilibili:BV1',
      'source_platform': 'bilibili',
      'content_id': 'BV1',
      'context': 'watch_later',
    });

    expect(item.eventLabelFor(ContentHistoryCategory.clicked), '点开');
    expect(item.eventLabelFor(ContentHistoryCategory.shown), '出现');
    expect(item.eventLabelFor(ContentHistoryCategory.removed), '从稍后再看移除');
  });

  test('normalizes current source aliases in history payloads', () {
    final item = ContentHistoryItem.fromJson({
      'item_key': 'v2:123',
      'source_platform': 'v2',
      'content_id': '123',
      'content_url': 'https://www.v2ex.com/t/123',
    });

    expect(item.sourcePlatform, 'v2ex');
  });

  test('removal labels cover every context', () {
    final item = ContentHistoryItem.fromJson({
      'item_key': 'bilibili:BV1',
      'source_platform': 'bilibili',
      'content_id': 'BV1',
      'contexts': [
        {'context': 'watch_later', 'occurred_at': '', 'restored': false},
        {'context': 'favorite', 'occurred_at': '', 'restored': false},
        {'context': 'dismiss', 'occurred_at': '', 'restored': false},
        {'context': 'dislike', 'occurred_at': '', 'restored': false},
      ],
    });

    final labels = item.contexts.map((entry) => entry.removalLabel).toList();
    expect(labels, ['从稍后再看移除', '从收藏移除', '已忽略', '不感兴趣']);
  });

  test('parses paginated history page', () {
    final page = ContentHistoryPage.fromJson({
      'category': 'removed',
      'total': 25,
      'retention_days': 30,
      'has_more': true,
      'next_cursor': 'abc123',
      'items': [
        {
          'item_key': 'bilibili:BV1',
          'source_platform': 'bilibili',
          'content_id': 'BV1',
        },
        {
          'item_key': 'youtube:abc',
          'source_platform': 'youtube',
          'content_id': 'abc',
        },
      ],
    });

    expect(page.category, ContentHistoryCategory.removed);
    expect(page.items, hasLength(2));
    expect(page.total, 25);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'abc123');
  });

  test('normalizes missing has_more to no cursor', () {
    final page = ContentHistoryPage.fromJson({
      'category': 'clicked',
      'items': <Object>[],
    });

    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isEmpty);
  });
}
