import '../models/profile.dart';
import 'client.dart';

class ProfileApi {
  final ApiClient _client;
  ProfileApi(this._client);

  Future<ProfileSummary> fetchSummary() async {
    final data = await _client.get('/profile-summary?limit=5');
    return ProfileSummary.fromJson(data);
  }

  Future<List<Map<String, dynamic>>> fetchPendingNotifications() async {
    final data = await _client.get('/notifications/pending');
    final item = data['item'];
    return item is Map<String, dynamic> ? [item] : [];
  }

  Future<List<Map<String, dynamic>>> fetchPendingProbes() async {
    final data = await _client.get('/interest-probes/pending');
    return (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<List<Map<String, dynamic>>> fetchPendingAvoidanceProbes() async {
    final data = await _client.get('/avoidance-probes/pending');
    return (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<void> respondToProbe(String domain, String response, {String message = ''}) =>
      _client.post('/interest-probes/respond', body: {'domain': domain, 'response': response, 'message': message});

  Future<void> respondToAvoidanceProbe(String domain, String response, {String message = ''}) =>
      _client.post('/avoidance-probes/respond', body: {'domain': domain, 'response': response, 'message': message});
}
