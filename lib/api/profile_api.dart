import '../models/profile.dart';
import 'client.dart';

class ProfileApi {
  final ApiClient _client;
  ProfileApi(this._client);

  Future<ProfileSummary> fetchSummary({
    int limit = 5,
    String cursor = '',
  }) async {
    final query = Uri(
      queryParameters: {
        'limit': limit.toString(),
        if (cursor.isNotEmpty) 'cursor': cursor,
      },
    ).query;
    final data = await _client.get('/profile-summary?$query', timeout: 12);
    return ProfileSummary.fromJson(data);
  }

  Future<Map<String, dynamic>?> fetchPendingCognitionUpdate() async {
    final data = await _client.get('/cognition-updates/pending');
    final item = data['item'];
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return Map<String, dynamic>.from(item);
    return null;
  }

  Future<void> markCognitionSeen(String id) async {
    await _client.post('/cognition-updates/seen', body: {'id': id});
  }

  Future<List<Map<String, dynamic>>> fetchPendingProbes() async {
    final data = await _client.get('/interest-probes/pending');
    return _maps(data['items']);
  }

  Future<List<Map<String, dynamic>>> fetchPendingAvoidanceProbes() async {
    final data = await _client.get('/avoidance-probes/pending');
    return _maps(data['items']);
  }

  Future<void> respondToProbe(
    String domain,
    String response, {
    String message = '',
  }) async {
    await _client.post(
      '/interest-probes/respond',
      body: {'domain': domain, 'response': response, 'message': message},
      timeout: 35,
    );
  }

  Future<void> respondToAvoidanceProbe(
    String domain,
    String response, {
    String message = '',
  }) async {
    await _client.post(
      '/avoidance-probes/respond',
      body: {'domain': domain, 'response': response, 'message': message},
      timeout: 35,
    );
  }

  Future<Map<String, dynamic>> fetchEditState() {
    return _client.get('/profile/edit-state', timeout: 12);
  }

  Future<Map<String, dynamic>> edit({
    required String target,
    required String operation,
    Object? value,
    String parent = '',
    double? weight,
  }) {
    return _client.post(
      '/profile/edit',
      body: {
        'target': target,
        'op': operation,
        'value': value,
        'parent': parent,
        'weight': weight,
      },
      timeout: 60,
    );
  }

  List<Map<String, dynamic>> _maps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
