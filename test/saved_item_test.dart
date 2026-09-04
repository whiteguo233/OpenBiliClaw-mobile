import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/recommendation.dart';
import 'package:openbiliclaw_app/models/saved_item.dart';

void main() {
  group('SavedItem cross-list projection', () {
    SavedItem item() => SavedItem.fromJson({
      'item_key': 'bilibili:BV1',
      'source_platform': 'bilibili',
      'content_id': 'BV1',
      'title': '测试',
      'content_url': 'https://www.bilibili.com/video/BV1',
      'content_type': 'video',
    });

    test('toSavePayload carries the canonical identity fields', () {
      final payload = item().toSavePayload();

      expect(payload['source_platform'], 'bilibili');
      expect(payload['content_id'], 'BV1');
      expect(payload['content_url'], 'https://www.bilibili.com/video/BV1');
      expect(payload['content_type'], 'video');
      expect(payload['title'], '测试');
    });

    test('bvid getter is namespaced for non-bilibili sources', () {
      final xhs = SavedItem.fromJson({
        'item_key': 'xiaohongshu:abc',
        'source_platform': 'xiaohongshu',
        'content_id': 'abc',
      });
      expect(xhs.bvid, 'xiaohongshu:abc');
    });

    test('fromRecommendation strips control characters before saving', () {
      final item = SavedItem.fromRecommendation(
        Recommendation(
          id: 0,
          bvid: 'douyin:123',
          sourcePlatform: 'douyin',
          contentId: '123',
          title: '第一行\n第二行\t第三行',
          upName: 'UP\nName',
          contentUrl: 'https://www.douyin.com/video/123',
        ),
      );

      expect(item.title, '第一行 第二行 第三行');
      expect(item.authorName, 'UP Name');
      expect(item.toSavePayload()['title'], '第一行 第二行 第三行');
      expect(item.toSavePayload()['author_name'], 'UP Name');
    });
  });
}
