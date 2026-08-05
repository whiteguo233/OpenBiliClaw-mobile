import 'package:flutter/foundation.dart';
import '../api/client.dart';
import '../api/auth_api.dart';

class AuthProvider extends ChangeNotifier {
  final AuthApi _authApi;

  bool _authenticated = false;
  bool _authEnabled = false;
  bool _loading = true;
  bool _needsLogin = false;

  AuthProvider(ApiClient client) : _authApi = AuthApi(client);

  bool get authenticated => _authenticated;
  bool get authEnabled => _authEnabled;
  bool get loading => _loading;
  bool get needsLogin => _needsLogin;

  Future<void> checkStatus() async {
    _loading = true;
    notifyListeners();
    try {
      final status = await _authApi.status();
      _authEnabled = status['enabled'] == true;
      _authenticated = status['authenticated'] != false;
      _needsLogin = _authEnabled && !_authenticated;
    } catch (_) {
      _needsLogin = false;
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> login(String password) async {
    try {
      final result = await _authApi.login(password);
      if (result['ok'] == true) {
        _authenticated = true;
        _needsLogin = false;
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    await _authApi.logout();
    _authenticated = false;
    _needsLogin = _authEnabled;
    notifyListeners();
  }
}
