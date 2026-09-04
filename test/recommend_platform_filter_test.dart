import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';

Map<String, dynamic> _item(String platform, String bvid) => {
  'id': 1,
  'bvid': bvid,
  'title': '标题 $bvid',
  'summary': '摘要',
  'source_platform': platform,
  'content_type': 'video',
};

RecommendProvider _providerWith(List<Map<String, dynamic>> items) {
  final client = ApiClient(
    host: '127.0.0.1',
    directClientFactory: () => MockClient((request) async {
      if (request.url.path.endsWith('/recommendations')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'items': items})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response.bytes(
        utf8.encode('{"items": []}'),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return RecommendProvider(client);
}

void main() {
  test('platform filter lists sources in fixed order and filters items', () async {
    final provider = _providerWith([
      _item('douyin', 'a'),
      _item('bilibili', 'b'),
      _item('douyin', 'c'),
    ]);
    await provider.load();

    expect(provider.availablePlatforms, ['bilibili', 'douyin']);
    expect(provider.showPlatformChoice, isTrue);
    expect(provider.visibleRecommendations.length, 3);

    provider.setPlatformFilter('douyin');
    expect(provider.platformFilter, 'douyin');
    expect(
      provider.visibleRecommendations.map((r) => r.sourcePlatform).toSet(),
      {'douyin'},
    );
    expect(provider.visibleRecommendations.length, 2);
  });

  test('single source hides the platform choice entirely', () async {
    final provider = _providerWith([
      _item('douyin', 'a'),
      _item('douyin', 'b'),
    ]);
    await provider.load();

    expect(provider.availablePlatforms, ['douyin']);
    expect(provider.showPlatformChoice, isFalse);
  });

  test('unknown platform slug normalizes into a known family', () async {
    final provider = _providerWith([
      _item('douyin', 'a'),
      _item('mystery', 'b'),
      _item('bilibili', 'c'),
    ]);
    await provider.load();

    // Recommendation.fromJson normalizes unknown slugs via contentUrl/bvid;
    // with a bvid it lands in bilibili (existing model behaviour).
    expect(provider.availablePlatforms, ['bilibili', 'douyin']);
    expect(RecommendProvider.platformLabel('mystery'), 'mystery');
    expect(RecommendProvider.platformLabel('douyin'), '抖音');
  });

  test('stale platform filter resets to all after reload', () async {
    final provider = _providerWith([
      _item('douyin', 'a'),
      _item('bilibili', 'b'),
    ]);
    await provider.load();
    provider.setPlatformFilter('bilibili');
    expect(provider.platformFilter, 'bilibili');

    final onlyDouyin = _providerWith([_item('douyin', 'x')]);
    await onlyDouyin.load();
    onlyDouyin.setPlatformFilter('bilibili');
    await onlyDouyin.load();
    expect(onlyDouyin.platformFilter, isEmpty);
    expect(onlyDouyin.showPlatformChoice, isFalse);
  });
}
