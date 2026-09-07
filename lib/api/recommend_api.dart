import 'dart:math';
import '../models/recommendation.dart';
import '../models/delight.dart';
import '../models/runtime_status.dart';
import 'client.dart';

String _newRequestId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

class RecommendAppendResult {
  const RecommendAppendResult({
    required this.items,
    required this.hasMore,
    this.poolStatus,
  });

  final List<Recommendation> items;
  final bool hasMore;
  final PlatformAvailability? poolStatus;
}

class RecommendApi {
  final ApiClient _client;
  RecommendApi(this._client);

  Future<List<Recommendation>> fetch({int? timeout}) async {
    final data = await _client.get('/recommendations', timeout: timeout ?? 12);
    return _recommendations(data['items']);
  }

  Future<RecommendAppendResult> reshuffle(
    List<String> excludedBvids, {
    String sourcePlatform = '',
  }) async {
    final data = await _client.post(
      '/recommendations/reshuffle',
      body: {
        'excluded_bvids': excludedBvids,
        if (sourcePlatform.isNotEmpty) 'source_platform': sourcePlatform,
      },
      timeout: 12,
    );
    return RecommendAppendResult(
      items: _recommendations(data['items']),
      hasMore: true,
      poolStatus: _poolStatus(data['pool_status']),
    );
  }

  Future<RecommendAppendResult> append(
    List<String> excludedBvids, {
    String sourcePlatform = '',
  }) async {
    final data = await _client.post(
      '/recommendations/append',
      body: {
        'excluded_bvids': excludedBvids,
        if (sourcePlatform.isNotEmpty) 'source_platform': sourcePlatform,
      },
      timeout: 12,
    );
    return RecommendAppendResult(
      items: _recommendations(data['items']),
      hasMore: data['has_more'] != false,
      poolStatus: _poolStatus(data['pool_status']),
    );
  }

  Future<bool> reportClick(Map<String, dynamic> payload) async {
    try {
      await _client.post(
        '/recommendation-click',
        body: {...payload, 'request_id': _newRequestId('click')},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> submitFeedback(
    int recommendationId,
    String type, {
    String bvid = '',
    String itemKey = '',
    String? note,
  }) {
    return _client.post(
      '/feedback',
      body: {
        'recommendation_id': recommendationId,
        'feedback_type': type,
        'note': note ?? '',
        'request_id': _newRequestId('fb'),
        'bvid': bvid,
        'item_key': itemKey,
      },
      timeout: 35,
    );
  }

  Future<Map<String, dynamic>> refresh() =>
      _client.post('/recommendations/refresh', timeout: 60);

  Future<PlatformAvailability> fetchPlatformAvailability() async {
    final data = await _client.get(
      '/recommendations/platform-availability',
      timeout: 8,
    );
    return PlatformAvailability.fromJson(data);
  }

  Future<Set<String>> fetchEnabledSources() async {
    final data = await _client.get('/sources/status', timeout: 8);
    final enabled = <String>{};
    data.forEach((key, value) {
      if (value is Map && value['enabled'] == true) {
        enabled.add(key);
      }
    });
    return enabled;
  }

  Future<RuntimeStatus> fetchRuntimeStatus() async {
    final data = await _client.get('/runtime-status', timeout: 8);
    return RuntimeStatus.fromJson(data);
  }

  Future<ActivityFeed> fetchActivity({
    int limit = 5,
    String before = '',
  }) async {
    final suffix = before.isEmpty
        ? '?limit=$limit'
        : '?limit=$limit&before=${Uri.encodeQueryComponent(before)}';
    final data = await _client.get('/activity-feed$suffix', timeout: 8);
    return ActivityFeed.fromJson(data);
  }

  Future<List<Delight>> fetchDelights({int? limit}) async {
    final qs = limit != null ? '?limit=$limit' : '';
    final data = await _client.get('/delight/pending-batch$qs');
    final items = data['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((item) => Delight.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, dynamic>> respondToDelight(
    String bvid,
    String response, {
    String title = '',
    String message = '',
  }) => _client.post(
    '/delight/respond',
    body: {
      'bvid': bvid,
      'response': response,
      'title': title,
      'message': message,
      'request_id': _newRequestId('delight'),
    },
    timeout: 35,
  );

  Future<void> markDelightSent(String bvid) =>
      _client.post('/delight/sent', body: {'bvid': bvid});

  PlatformAvailability? _poolStatus(dynamic raw) {
    if (raw is! Map ||
        raw['pool_available_count'] is! num ||
        raw['platform_available_counts'] is! Map) {
      return null;
    }
    return PlatformAvailability.fromJson({
      'total_available': raw['pool_available_count'],
      'by_platform': raw['platform_available_counts'],
      'pool_status_version': raw['pool_status_version'],
    });
  }

  List<Recommendation> _recommendations(dynamic rawItems) {
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map((item) => Recommendation.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}
