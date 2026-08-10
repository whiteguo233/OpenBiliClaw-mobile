import 'package:url_launcher/url_launcher.dart';

import '../models/delight.dart';
import '../models/recommendation.dart';
import '../models/saved_item.dart';

class ContentLauncher {
  const ContentLauncher._();

  static Future<bool> openRecommendation(Recommendation item) {
    return open(
      sourcePlatform: item.sourcePlatform,
      contentId: item.contentId,
      contentUrl: item.contentUrl,
      fallbackId: item.bvid,
    );
  }

  static Future<bool> openDelight(Delight item) {
    return open(
      sourcePlatform: item.sourcePlatform,
      contentId: item.contentId,
      contentUrl: item.contentUrl,
      fallbackId: item.bvid,
    );
  }

  static Future<bool> openSaved(SavedItem item) {
    return open(
      sourcePlatform: item.sourcePlatform,
      contentId: item.contentId,
      contentUrl: item.contentUrl,
    );
  }

  static Future<bool> open({
    required String sourcePlatform,
    required String contentId,
    String contentUrl = '',
    String fallbackId = '',
  }) async {
    final source = normalizeSourcePlatform(
      sourcePlatform,
      contentUrl: contentUrl,
      bvid: fallbackId,
    );
    final id = _canonicalId(contentId, fallbackId, source);
    for (final deepLink in _deepLinks(source, id)) {
      try {
        if (await launchUrl(deepLink, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // The platform app is optional. Continue to the canonical web URL.
      }
    }

    final fallback = Uri.tryParse(
      contentUrl.trim().isNotEmpty ? contentUrl.trim() : _webUrl(source, id),
    );
    if (fallback == null || !fallback.hasScheme) return false;
    try {
      return await launchUrl(fallback, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static String _canonicalId(
    String contentId,
    String fallbackId,
    String source,
  ) {
    var id = contentId.trim();
    if (id.isEmpty) id = fallbackId.trim();
    final prefix = '$source:';
    if (id.toLowerCase().startsWith(prefix)) id = id.substring(prefix.length);
    if (id.contains(':') && contentId.trim().isEmpty) {
      id = id.split(':').skip(1).join(':');
    }
    return id;
  }

  static List<Uri> _deepLinks(String source, String id) {
    if (id.isEmpty) return const [];
    final values = switch (source) {
      'bilibili' => ['bilibili://video/$id'],
      'youtube' => [
        'vnd.youtube://$id',
        'youtube://www.youtube.com/watch?v=$id',
      ],
      'douyin' => ['snssdk1128://aweme/detail/$id'],
      'xiaohongshu' => ['xhsdiscover://item/$id'],
      'twitter' => ['twitter://status?id=$id'],
      'reddit' => ['reddit://reddit.com/comments/$id'],
      _ => const <String>[],
    };
    return values.map(Uri.parse).toList();
  }

  static String _webUrl(String source, String id) {
    if (id.isEmpty) return '';
    return switch (source) {
      'bilibili' => 'https://www.bilibili.com/video/$id',
      'youtube' => 'https://www.youtube.com/watch?v=$id',
      'douyin' => 'https://www.douyin.com/video/$id',
      'xiaohongshu' => 'https://www.xiaohongshu.com/explore/$id',
      'twitter' => 'https://x.com/i/status/$id',
      'zhihu' => 'https://www.zhihu.com/question/$id',
      'reddit' => 'https://www.reddit.com/comments/$id',
      'bangumi' => 'https://bgm.tv/subject/$id',
      _ => '',
    };
  }
}
