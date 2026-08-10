import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/recommendation.dart';

void main() {
  test('parses a current multi-platform recommendation', () {
    final item = Recommendation.fromJson({
      'id': 42,
      'bvid': 'douyin:735123',
      'item_key': 'douyin:735123',
      'content_id': '735123',
      'source_platform': 'dy',
      'content_url': 'https://www.douyin.com/video/735123',
      'content_type': 'video',
      'title': 'AI &amp; 实测',
      'up_name': '作者',
      'view_count': 12034,
      'like_count': 203,
      'published_at': '2026-08-08T10:00:00+08:00',
    });

    expect(item.sourcePlatform, 'douyin');
    expect(item.contentId, '735123');
    expect(item.savedIdentity, 'douyin:735123');
    expect(item.title, 'AI & 实测');
    expect(item.statsLabel, contains('1.2万'));
    expect(item.toSavedPayload()['source_platform'], 'douyin');
  });

  test('recovers canonical content id from a namespaced legacy bvid', () {
    final item = Recommendation.fromJson({
      'id': 9,
      'bvid': 'youtube:dQw4w9WgXcQ',
      'source_platform': 'youtube',
    });

    expect(item.contentId, 'dQw4w9WgXcQ');
    expect(item.savedIdentity, 'youtube:dQw4w9WgXcQ');
  });

  test('treats articles and posts as text cards', () {
    for (final type in ['article', 'answer', 'tweet', 'post']) {
      final item = Recommendation(id: 1, bvid: type, contentType: type);
      expect(item.isTextCard, isTrue, reason: type);
    }
  });
}
