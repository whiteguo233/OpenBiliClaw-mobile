import '../api/utils.dart';

class RuntimeStatus {
  final int poolAvailableCount;
  final int lastReplenishedCount;
  final int poolPendingCount;
  final List<String> recentPoolTopics;
  final String activity;
  final bool busy;

  const RuntimeStatus({
    this.poolAvailableCount = 0,
    this.lastReplenishedCount = 0,
    this.poolPendingCount = 0,
    this.recentPoolTopics = const [],
    this.activity = '',
    this.busy = false,
  });

  factory RuntimeStatus.fromJson(Map<String, dynamic> json) {
    final rawTopics = json['recent_pool_topics'];
    final topics = rawTopics is List
        ? rawTopics
              .map((item) => _topicLabel(item?.toString() ?? ''))
              .where((item) => item.isNotEmpty)
              .toSet()
              .take(3)
              .toList()
        : const <String>[];
    return RuntimeStatus(
      poolAvailableCount: _integer(json['pool_available_count']),
      lastReplenishedCount: _integer(json['last_replenished_count']),
      poolPendingCount: _integer(json['pool_pending_count']),
      recentPoolTopics: topics,
      activity: decodeHtml(
        (json['activity'] ?? json['current_activity'] ?? '').toString(),
      ),
      busy:
          json['busy'] == true ||
          json['refreshing'] == true ||
          json['discovery_running'] == true,
    );
  }

  RuntimeStatus withPoolAvailableCount(int count) => RuntimeStatus(
    poolAvailableCount: count,
    lastReplenishedCount: lastReplenishedCount,
    poolPendingCount: poolPendingCount,
    recentPoolTopics: recentPoolTopics,
    activity: activity,
    busy: busy,
  );

  String get topicSummary => recentPoolTopics.join(' / ');
}

class PlatformAvailability {
  final int totalAvailable;
  final int version;
  final Map<String, int> byPlatform;

  const PlatformAvailability({
    this.totalAvailable = 0,
    this.version = 0,
    this.byPlatform = const {},
  });

  factory PlatformAvailability.fromJson(Map<String, dynamic> json) {
    final raw = json['by_platform'];
    final map = raw is Map
        ? raw.map(
            (key, value) => MapEntry(
              key.toString(),
              value is num
                  ? value.toInt()
                  : int.tryParse(value.toString()) ?? 0,
            ),
          )
        : const <String, int>{};
    return PlatformAvailability(
      totalAvailable: _integer(json['total_available']),
      version: _integer(json['pool_status_version']),
      byPlatform: Map<String, int>.unmodifiable(map),
    );
  }
}

class ActivityFeed {
  final String headline;
  final String liveSummary;
  final List<ActivityItem> items;
  final bool hasMore;
  final String nextCursor;

  const ActivityFeed({
    this.headline = '',
    this.liveSummary = '',
    this.items = const [],
    this.hasMore = false,
    this.nextCursor = '',
  });

  factory ActivityFeed.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return ActivityFeed(
      headline: decodeHtml(json['headline']?.toString() ?? ''),
      liveSummary: decodeHtml(json['live_summary']?.toString() ?? ''),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) =>
                      ActivityItem.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
      hasMore: json['has_more'] == true,
      nextCursor: json['next_cursor']?.toString() ?? '',
    );
  }
}

class ActivityItem {
  final String title;
  final String summary;
  final String createdAt;
  final String type;

  const ActivityItem({
    this.title = '',
    this.summary = '',
    this.createdAt = '',
    this.type = '',
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
    title: decodeHtml(
      (json['title'] ?? json['headline'] ?? json['type'] ?? '').toString(),
    ),
    summary: decodeHtml(
      (json['summary'] ?? json['message'] ?? json['detail'] ?? '').toString(),
    ),
    createdAt: (json['created_at'] ?? json['timestamp'] ?? '').toString(),
    type: json['type']?.toString() ?? '',
  );
}

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _topicLabel(String value) {
  final normalized = value.trim();
  final lower = normalized.toLowerCase();
  if (lower.startsWith('xhs-extension-')) return '小红书';
  if (lower.startsWith('dy-plugin-') || lower.startsWith('douyin-')) {
    return '抖音';
  }
  if (lower.startsWith('yt-') || lower.startsWith('youtube-')) {
    return 'YouTube';
  }
  if (lower.startsWith('reddit-')) return 'Reddit';
  if (lower.startsWith('bangumi-')) return 'Bangumi';
  return normalized;
}
