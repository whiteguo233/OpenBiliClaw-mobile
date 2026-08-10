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

  String get topicSummary => recentPoolTopics.join(' / ');
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
