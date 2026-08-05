import 'dart:math';
import '../models/recommendation.dart';
import '../models/delight.dart';
import 'client.dart';

String _newRequestId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

class RecommendApi {
  final ApiClient _client;
  RecommendApi(this._client);

  Future<List<Recommendation>> fetch({int? timeout}) async {
    final data = await _client.get('/recommendations', timeout: timeout ?? 12);
    return (data['items'] as List?)?.map((e) => Recommendation.fromJson(e)).toList() ?? [];
  }

  Future<Map<String, dynamic>> append(List<String> excludedBvids) =>
      _client.post('/recommendations/append', body: {'excluded_bvids': excludedBvids});

  Future<void> reportClick(Map<String, dynamic> payload) async {
    try {
      await _client.post('/recommendation-click', body: {
        ...payload,
        'request_id': _newRequestId('click'),
      });
    } catch (_) {}
  }

  Future<void> submitFeedback(int recommendationId, String bvid, String type, {String? note}) async {
    try {
      await _client.post('/feedback', body: {
        'recommendation_id': recommendationId,
        'feedback_type': type,
        'note': note ?? '',
        'request_id': _newRequestId('fb'),
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>> refresh() => _client.post('/recommendations/refresh');

  Future<List<Delight>> fetchDelights({int? limit}) async {
    final qs = limit != null ? '?limit=$limit' : '';
    final data = await _client.get('/delight/pending-batch$qs');
    return (data['items'] as List?)?.map((e) => Delight.fromJson(e)).toList() ?? [];
  }

  Future<void> respondToDelight(String bvid, String response, {String title = '', String message = ''}) =>
      _client.post('/delight/respond', body: {'bvid': bvid, 'response': response, 'title': title, 'message': message});

  Future<void> markDelightSent(String bvid) => _client.post('/delight/sent', body: {'bvid': bvid});
}
