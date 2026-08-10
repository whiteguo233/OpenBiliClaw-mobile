import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String _schemeKey = 'api_scheme';
  static const String _hostKey = 'api_host';
  static const String _portKey = 'api_port';
  static const String _sessionKey = 'session_token';
  static const int _defaultPort = 8420;

  // Android emulators expose the host machine as 10.0.2.2. A physical
  // Android device still needs the computer's LAN address in Settings.
  static String get _defaultHost =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : '127.0.0.1';

  String _scheme;
  String _host;
  int _port;
  String _sessionToken = '';

  ApiClient({String scheme = 'http', String? host, int port = _defaultPort})
    : _scheme = _normalizeScheme(scheme),
      _host = _normalizeHost(host ?? _defaultHost),
      _port = port;

  Uri get _originUri => Uri(scheme: _scheme, host: _host, port: _port);
  String get baseUrl => _originUri.replace(path: '/api').toString();
  String get wsUrl => _originUri
      .replace(
        scheme: _scheme == 'https' ? 'wss' : 'ws',
        path: '/api/runtime-stream',
      )
      .toString();
  String get scheme => _scheme;
  String get host => _host;
  int get port => _port;
  String get sessionToken => _sessionToken;
  Map<String, String> get wsHeaders => _sessionToken.isNotEmpty
      ? {
          'Cookie': 'obc_session=$_sessionToken',
          'Origin': _originUri.toString(),
        }
      : const {};

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _scheme = _normalizeScheme(prefs.getString(_schemeKey) ?? _scheme);
    _host = _normalizeHost(prefs.getString(_hostKey) ?? _host);
    _port = prefs.getInt(_portKey) ?? _defaultPort;
    _sessionToken = prefs.getString(_sessionKey) ?? '';
  }

  Future<void> saveSettings(String host, int port, {String? scheme}) async {
    final nextScheme = _normalizeScheme(scheme ?? _scheme);
    final nextHost = _normalizeHost(host);
    final changed = nextScheme != _scheme || nextHost != _host || port != _port;
    _scheme = nextScheme;
    _host = nextHost;
    _port = port;
    if (changed) clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_schemeKey, _scheme);
    await prefs.setString(_hostKey, _host);
    await prefs.setInt(_portKey, port);
  }

  Uri apiUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final relative = Uri.parse(normalizedPath);
    return _originUri.replace(
      path: '/api${relative.path}',
      query: relative.hasQuery ? relative.query : null,
    );
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
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(_sessionKey, token),
    );
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-OBC-Auth': '1',
    };
    if (_sessionToken.isNotEmpty) {
      headers['Cookie'] = 'obc_session=$_sessionToken';
      headers['Origin'] = _originUri.toString();
    }
    return headers;
  }

  Future<Map<String, dynamic>> get(String path, {int? timeout}) async {
    final uri = apiUri(path);
    final client = http.Client();
    try {
      final res = await client
          .get(uri, headers: _headers())
          .timeout(Duration(seconds: timeout ?? 10));
      _captureSession(res);
      if (res.statusCode == 401) clearSession();
      if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
      return _decodeMap(res.body);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    int? timeout,
  }) async {
    final uri = apiUri(path);
    final client = http.Client();
    try {
      final res = await client
          .post(
            uri,
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: timeout ?? 10));
      _captureSession(res);
      if (res.statusCode == 401) clearSession();
      if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
      return _decodeMap(res.body);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    int? timeout,
  }) async {
    final uri = apiUri(path);
    final client = http.Client();
    try {
      final res = await client
          .put(
            uri,
            headers: _headers(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(Duration(seconds: timeout ?? 60));
      _captureSession(res);
      if (res.statusCode == 401) clearSession();
      if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
      return _decodeMap(res.body);
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final uri = apiUri(path);
    final client = http.Client();
    try {
      final res = await client
          .delete(uri, headers: _headers())
          .timeout(const Duration(seconds: 10));
      _captureSession(res);
      if (res.statusCode == 401) clearSession();
      if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
      return _decodeMap(res.body);
    } finally {
      client.close();
    }
  }

  Future<bool> checkHealth({String? overrideHost, int? overridePort}) async {
    try {
      var nextScheme = _scheme;
      var nextHost = overrideHost ?? _host;
      final parsed = Uri.tryParse(nextHost);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        nextScheme = _normalizeScheme(parsed.scheme);
        nextHost = parsed.host;
      }
      final h = _normalizeHost(nextHost);
      final p = overridePort ?? _port;
      final uri = Uri(
        scheme: nextScheme,
        host: h,
        port: p,
        path: '/api/health',
      );
      final client = http.Client();
      try {
        final res = await client
            .get(uri, headers: {'X-OBC-Auth': '1'})
            .timeout(const Duration(seconds: 5));
        return res.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  static String _normalizeScheme(String value) {
    return value.trim().toLowerCase() == 'https' ? 'https' : 'http';
  }

  static String _normalizeHost(String value) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed.host;
    }
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  static Map<String, dynamic> _decodeMap(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Expected a JSON object response');
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  String get message {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) return detail;
        if (detail is Map) {
          final message = detail['message'] ?? detail['detail'];
          if (message is String && message.trim().isNotEmpty) return message;
        }
      }
    } catch (_) {}
    return body.trim().isEmpty ? 'HTTP $statusCode' : body;
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
