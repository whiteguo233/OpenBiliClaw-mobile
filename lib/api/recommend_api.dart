import 'dart:math';
import '../models/recommendation.dart';
import '../models/delight.dart';
import '../models/runtime_status.dart';
import 'client.dart';

String _newRequestId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

class RecommendApi {
  final ApiClient _client;
  RecommendApi(this._client);

  Future<List<Recommendation>> fetch({int? timeout}) async {
    final data = await _client.get('/recommendations', timeout: timeout ?? 12);
    return _recommendations(data['items']);
  }

  Future<List<Recommendation>> reshuffle(List<String> excludedBvids) async {
    final data = await _client.post(
      '/recommendations/reshuffle',
      body: {'excluded_bvids': excludedBvids},
      timeout: 30,
    );
    return _recommendations(data['items']);
  }

  Future<List<Recommendation>> append(List<String> excludedBvids) async {
    final data = await _client.post(
      '/recommendations/append',
      body: {'excluded_bvids': excludedBvids},
      timeout: 30,
    );
    return _recommendations(data['items']);
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
    String? note,
  }) {
    return _client.post(
      '/feedback',
      body: {
        'recommendation_id': recommendationId,
        'feedback_type': type,
        'note': note ?? '',
        'request_id': _newRequestId('fb'),
      },
      timeout: 35,
    );
  }

  Future<Map<String, dynamic>> refresh() =>
      _client.post('/recommendations/refresh', timeout: 60);

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

  List<Recommendation> _recommendations(dynamic rawItems) {
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map((item) => Recommendation.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }
}
