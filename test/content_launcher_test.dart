import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/delight.dart';
import 'package:openbiliclaw_app/models/recommendation.dart';
import 'package:openbiliclaw_app/services/content_launcher.dart';

void main() {
  group('source platform parity', () {
    test('normalizes sources added by the current backend', () {
      expect(normalizeSourcePlatform('wb'), 'weibo');
      expect(normalizeSourcePlatform('linux.do'), 'linuxdo');
      expect(normalizeSourcePlatform('v2'), 'v2ex');
      expect(normalizeSourcePlatform('rednote'), 'xiaohongshu');
      expect(normalizeSourcePlatform('tiktok'), 'douyin');
      expect(normalizeSourcePlatform('', bvid: 'wb:123'), 'weibo');
    });

    test('infers new sources from canonical URLs', () {
      expect(
        normalizeSourcePlatform('', contentUrl: 'https://weibo.com/123/a'),
        'weibo',
      );
      expect(
        normalizeSourcePlatform('', contentUrl: 'https://linux.do/t/topic/1'),
        'linuxdo',
      );
      expect(
        normalizeSourcePlatform('', contentUrl: 'https://www.v2ex.com/t/1'),
        'v2ex',
      );
    });

    test('renders user-facing labels for every current source', () {
      expect(sourcePlatformLabel('weibo'), '微博');
      expect(sourcePlatformLabel('wb'), '微博');
      expect(sourcePlatformLabel('linuxdo'), 'Linux.do');
      expect(sourcePlatformLabel('linux.do'), 'Linux.do');
      expect(sourcePlatformLabel('v2ex'), 'V2EX');
    });

    test('normalizes source aliases in delight payloads before saving', () {
      final delight = Delight.fromJson({
        'bvid': 'wb:123',
        'content_id': '123',
        'source_platform': 'wb',
        'content_url': 'https://weibo.com/1/123',
      });

      expect(delight.sourcePlatform, 'weibo');
      expect(delight.itemKey, 'weibo:123');
      expect(delight.toRecommendation().sourcePlatform, 'weibo');
    });
  });

  group('native launch parity', () {
    test('preserves Xiaohongshu launch tokens before the web fallback', () {
      final uris = ContentLauncher.buildLaunchUris(
        sourcePlatform: 'xiaohongshu',
        contentId: 'note123',
        contentUrl:
            'https://www.xiaohongshu.com/explore/note123?xsec_token=abc%2B123&xsec_source=pc_search',
      );

      expect(uris, hasLength(2));
      expect(uris.first.scheme, 'xhsdiscover');
      expect(uris.first.queryParameters['xsec_token'], 'abc+123');
      expect(uris.first.queryParameters['xsec_source'], 'pc_search');
      expect(uris.last.scheme, 'https');
    });

    test('maps Zhihu answers and articles to their native routes', () {
      final answer = ContentLauncher.buildLaunchUris(
        sourcePlatform: 'zhihu',
        contentId: '456',
        contentUrl: 'https://www.zhihu.com/question/123/answer/456',
      );
      final article = ContentLauncher.buildLaunchUris(
        sourcePlatform: 'zhihu',
        contentId: '789',
        contentUrl: 'https://zhuanlan.zhihu.com/p/789',
      );

      expect(answer.first.toString(), 'zhihu://answers/456');
      expect(article.first.toString(), 'zhihu://articles/789');
    });

    test('builds Linux.do and V2EX canonical web fallbacks', () {
      final linuxDo = ContentLauncher.buildLaunchUris(
        sourcePlatform: 'linuxdo',
        contentId: 'topic:12345',
      );
      final v2ex = ContentLauncher.buildLaunchUris(
        sourcePlatform: 'v2ex',
        contentId: '98765',
      );

      expect(linuxDo.single.toString(), 'https://linux.do/t/12345');
      expect(v2ex.single.toString(), 'https://www.v2ex.com/t/98765');
    });

    test('builds a canonical Weibo fallback from a status id', () {
      final uris = ContentLauncher.buildLaunchUris(
        sourcePlatform: 'weibo',
        contentId: 'P8x123',
      );

      expect(uris.single.toString(), 'https://m.weibo.cn/detail/P8x123');
    });

    test('rejects unsafe or credential-bearing fallback schemes', () {
      for (final url in [
        'javascript:alert(1)',
        'intent://open/#Intent;scheme=evil;end',
        'file:///etc/passwd',
        'https://user:password@example.com/private',
      ]) {
        expect(
          ContentLauncher.buildLaunchUris(
            sourcePlatform: 'web',
            contentId: '',
            contentUrl: url,
          ),
          isEmpty,
          reason: url,
        );
      }

      expect(
        ContentLauncher.buildLaunchUris(
          sourcePlatform: 'web',
          contentId: '',
          contentUrl: 'https://example.com/content',
        ).single.toString(),
        'https://example.com/content',
      );
    });
  });
}
