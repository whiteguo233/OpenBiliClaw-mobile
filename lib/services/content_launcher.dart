import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/delight.dart';
import '../models/recommendation.dart';
import '../models/saved_item.dart';
import '../views/native_bilibili_video_page.dart';

class ContentLauncher {
  const ContentLauncher._();

  static Future<bool> openRecommendation(
    Recommendation item, {
    BuildContext? context,
  }) {
    return open(
      sourcePlatform: item.sourcePlatform,
      contentId: item.contentId,
      contentUrl: item.contentUrl,
      fallbackId: item.bvid,
      title: item.displayTitle,
      coverUrl: item.coverUrl,
      contentType: item.contentType,
      recommendationReason: item.expression.isNotEmpty
          ? item.expression
          : item.bodyText,
      context: context,
    );
  }

  static Future<bool> openDelight(Delight item, {BuildContext? context}) {
    return open(
      sourcePlatform: item.sourcePlatform,
      contentId: item.contentId,
      contentUrl: item.contentUrl,
      fallbackId: item.bvid,
      title: item.title,
      coverUrl: item.coverUrl,
      contentType: item.contentType,
      recommendationReason: item.reason,
      context: context,
    );
  }

  static Future<bool> openSaved(SavedItem item, {BuildContext? context}) {
    return open(
      sourcePlatform: item.sourcePlatform,
      contentId: item.contentId,
      contentUrl: item.contentUrl,
      title: item.title,
      coverUrl: item.coverUrl,
      contentType: item.contentType,
      context: context,
    );
  }

  static Future<bool> open({
    required String sourcePlatform,
    required String contentId,
    String contentUrl = '',
    String fallbackId = '',
    String title = '',
    String coverUrl = '',
    String contentType = 'video',
    String recommendationReason = '',
    BuildContext? context,
  }) async {
    final source = normalizeSourcePlatform(
      sourcePlatform,
      contentUrl: contentUrl,
      bvid: fallbackId,
    );
    final id = _canonicalId(contentId, fallbackId, source);
    if (context != null &&
        _canOpenInAppBilibili(source, id, contentType: contentType)) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NativeBilibiliVideoPage(
            bvid: id,
            title: title,
            contentUrl: contentUrl,
            coverUrl: coverUrl,
            recommendationReason: recommendationReason,
          ),
        ),
      );
      return true;
    }

    for (final candidate in buildLaunchUris(
      sourcePlatform: sourcePlatform,
      contentId: contentId,
      contentUrl: contentUrl,
      fallbackId: fallbackId,
    )) {
      try {
        if (await launchUrl(candidate, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (_) {
        // Native platform apps are optional. Continue through the candidates
        // until the canonical web URL is reached.
      }
    }
    return false;
  }

  /// Whether this mobile build can keep Bilibili videos inside an embedded
  /// web view instead of handing them to the system-native Bilibili app.
  static bool _canOpenInAppBilibili(
    String source,
    String id, {
    String contentType = 'video',
  }) {
    if (kIsWeb || id.isEmpty) return false;
    if (contentType.trim().isEmpty) {
      // Legacy data may not carry a content type yet; keep the previous
      // in-app behavior for unknown types rather than silently breaking taps.
    } else if (contentType.trim().toLowerCase() != 'video') {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => source == 'bilibili',
      _ => false,
    };
  }

  /// Pure launch plan shared by the runtime and regression tests. Native app
  /// links come first; the canonical web URL is always the last candidate.
  static List<Uri> buildLaunchUris({
    required String sourcePlatform,
    required String contentId,
    String contentUrl = '',
    String fallbackId = '',
  }) {
    final source = normalizeSourcePlatform(
      sourcePlatform,
      contentUrl: contentUrl,
      bvid: fallbackId,
    );
    final id = _canonicalId(contentId, fallbackId, source);
    final candidates = _deepLinks(source, id, contentUrl);
    final fallbackText = contentUrl.trim().isNotEmpty
        ? contentUrl.trim()
        : _webUrl(source, id);
    final fallback = Uri.tryParse(fallbackText);
    if (fallback != null &&
        const {'http', 'https'}.contains(fallback.scheme.toLowerCase()) &&
        fallback.host.isNotEmpty &&
        fallback.userInfo.isEmpty) {
      candidates.add(fallback);
    }
    return candidates;
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

  static List<Uri> _deepLinks(String source, String id, String contentUrl) {
    if (source == 'zhihu') {
      final uri = _zhihuDeepLink(contentUrl, id);
      return uri == null ? <Uri>[] : [uri];
    }
    if (id.isEmpty) return <Uri>[];
    return switch (source) {
      'bilibili' => [Uri(scheme: 'bilibili', host: 'video', path: '/$id')],
      'youtube' => [
        Uri(
          scheme: 'vnd.youtube',
          host: 'www.youtube.com',
          path: '/watch',
          queryParameters: {'v': id},
        ),
        Uri(
          scheme: 'youtube',
          host: 'www.youtube.com',
          path: '/watch',
          queryParameters: {'v': id},
        ),
      ],
      'douyin' => [
        Uri(scheme: 'snssdk1128', host: 'aweme', path: '/detail/$id'),
      ],
      'xiaohongshu' => [_xiaohongshuDeepLink(id, contentUrl)],
      'twitter' => [
        Uri(scheme: 'twitter', host: 'status', queryParameters: {'id': id}),
      ],
      'reddit' => [
        Uri(scheme: 'reddit', host: 'reddit.com', path: '/comments/$id'),
      ],
      _ => <Uri>[],
    };
  }

  static Uri _xiaohongshuDeepLink(String id, String contentUrl) {
    final source = Uri.tryParse(contentUrl);
    final query = <String, String>{};
    for (final key in const ['xsec_token', 'xsec_source']) {
      final value = source?.queryParameters[key];
      if (value != null && value.isNotEmpty) query[key] = value;
    }
    return Uri(
      scheme: 'xhsdiscover',
      host: 'item',
      path: '/$id',
      queryParameters: query.isEmpty ? null : query,
    );
  }

  static Uri? _zhihuDeepLink(String contentUrl, String fallbackId) {
    final source = Uri.tryParse(contentUrl);
    final segments = source?.pathSegments ?? const <String>[];
    final questionIndex = segments.indexOf('question');
    final answerIndex = segments.indexOf('answer');
    if (answerIndex >= 0 && answerIndex + 1 < segments.length) {
      return Uri(
        scheme: 'zhihu',
        host: 'answers',
        path: '/${segments[answerIndex + 1]}',
      );
    }
    final articleIndex = segments.indexOf('p');
    if (source?.host.startsWith('zhuanlan.') == true &&
        articleIndex >= 0 &&
        articleIndex + 1 < segments.length) {
      return Uri(
        scheme: 'zhihu',
        host: 'articles',
        path: '/${segments[articleIndex + 1]}',
      );
    }
    final questionId = questionIndex >= 0 && questionIndex + 1 < segments.length
        ? segments[questionIndex + 1]
        : fallbackId;
    if (questionId.isEmpty) return null;
    return Uri(scheme: 'zhihu', host: 'questions', path: '/$questionId');
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
      'linuxdo' => _linuxDoUrl(id),
      'v2ex' => 'https://www.v2ex.com/t/$id',
      'weibo' => 'https://m.weibo.cn/detail/$id',
      _ => '',
    };
  }

  static String _linuxDoUrl(String id) {
    final topicId = id.replaceFirst(
      RegExp(r'^topic[:_]', caseSensitive: false),
      '',
    );
    return RegExp(r'^[1-9]\d*$').hasMatch(topicId)
        ? 'https://linux.do/t/$topicId'
        : '';
  }
}
