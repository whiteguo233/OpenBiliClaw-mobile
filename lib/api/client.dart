import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String _hostKey = 'api_host';
  static const String _portKey = 'api_port';
  static const String _sessionKey = 'session_token';
  static const String _defaultHost = '127.0.0.1';
  static const int _defaultPort = 8420;

  String _host = _defaultHost;
  int _port = _defaultPort;
  String _sessionToken = '';

  ApiClient();

  String get baseUrl => 'http://$_host:$_port/api';
  String get wsUrl => 'ws://$_host:$_port/api/runtime-stream';
  String get host => _host;
  int get port => _port;
  String get sessionToken => _sessionToken;
  Map<String, String> get wsHeaders => _sessionToken.isNotEmpty ? {'Cookie': 'obc_session=$_sessionToken'} : const {};

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_hostKey) ?? _defaultHost;
    _port = prefs.getInt(_portKey) ?? _defaultPort;
    _sessionToken = prefs.getString(_sessionKey) ?? '';
  }

  Future<void> saveSettings(String host, int port) async {
    final changed = host != _host || port != _port;
    _host = host;
    _port = port;
    if (changed) clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setInt(_portKey, port);
  }

  void clearSession() {
    _sessionToken = '';
    SharedPreferences.getInstance().then((prefs) => prefs.remove(_sessionKey));
  }

  void _captureSession(http.Response res) {
    final setCookie = res.headers['set-cookie'];
    if (setCookie == null) return;
    final match = RegExp(r'obc_session=([^;]*)').firstMatch(setCookie);
    if (match == null) return;
    final token = match.group(1) ?? '';
    if (token.isEmpty) {
      clearSession();
      return;
    }
    _sessionToken = token;
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_sessionKey, token));
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-OBC-Auth': '1',
    };
    if (_sessionToken.isNotEmpty) {
      headers['Cookie'] = 'obc_session=$_sessionToken';
      headers['Origin'] = 'http://$_host:$_port';
    }
    return headers;
  }

  Future<Map<String, dynamic>> get(String path, {int? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = http.Client();
    try {
      final res = await client.get(uri, headers: _headers()).timeout(Duration(seconds: timeout ?? 10));
      _captureSession(res);
      if (res.statusCode == 401) clearSession();
      if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
      return jsonDecode(res.body);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body, int? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = http.Client();
    try {
      final res = await client.post(uri, headers: _headers(), body: body != null ? jsonEncode(body) : null)
          .timeout(Duration(seconds: timeout ?? 10));
      _captureSession(res);
      if (res.statusCode == 401) clearSession();
      if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
      return jsonDecode(res.body);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = http.Client();
    try {
      final res = await client.delete(uri, headers: _headers()).timeout(const Duration(seconds: 10));
      _captureSession(res);
      if (res.statusCode == 401) clearSession();
      if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
      return res.body.isNotEmpty ? jsonDecode(res.body) : {};
    } finally {
      client.close();
    }
  }

  Future<bool> checkHealth({String? overrideHost, int? overridePort}) async {
    try {
      final h = overrideHost ?? _host;
      final p = overridePort ?? _port;
      final uri = Uri.parse('http://$h:$p/api/health');
      final client = http.Client();
      try {
        final res = await client.get(uri, headers: {'X-OBC-Auth': '1'}).timeout(const Duration(seconds: 5));
        return res.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);
  @override
  String toString() => 'ApiException($statusCode): $body';
}
