import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/saved_item.dart';

void main() {
  test('parses canonical saved list metadata and sync state', () {
    final item = SavedItem.fromJson({
      'item_key': 'xiaohongshu:abc123',
      'source_platform': 'xiaohongshu',
      'content_id': 'abc123',
      'title': '测试笔记',
      'author_name': '作者',
      'sync_status': 'login_required',
      'error_message': '需要登录小红书',
    });

    expect(item.itemKey, 'xiaohongshu:abc123');
    expect(item.bvid, 'xiaohongshu:abc123');
    expect(item.upName, '作者');
    expect(item.canSync, isTrue);
    expect(item.syncLabel, '需要登录');
    expect(item.syncDetail, '需要登录小红书');
  });

  test('marks unsupported content type as local only', () {
    final item = SavedItem.fromJson({
      'item_key': 'twitter:1',
      'source_platform': 'twitter',
      'content_id': '1',
      'sync_status': 'unsupported',
      'error_code': 'unsupported_content_type',
    });

    expect(item.localOnly, isTrue);
    expect(item.canSync, isFalse);
    expect(item.syncLabel, '仅本地保存');
  });
}
