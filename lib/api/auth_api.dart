import 'client.dart';

class AuthApi {
  final ApiClient _client;
  AuthApi(this._client);

  Future<Map<String, dynamic>> status() => _client.get('/auth/status');

  Future<Map<String, dynamic>> login(String password) => _client.post('/auth/login', body: {'password': password});

  Future<void> logout() async {
    try {
      await _client.post('/auth/logout');
    } catch (_) {}
  }
}
