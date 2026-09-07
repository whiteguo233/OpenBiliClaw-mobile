import 'dart:convert';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/tailnet_service.dart';

enum ConnectionMode { direct, tailscale }

class ApiClient {
  static const String _schemeKey = 'api_scheme';
  static const String _hostKey = 'api_host';
  static const String _portKey = 'api_port';
  static const String _sessionKey = 'session_token';
  static const String _connectionModeKey = 'connection_mode';
  static const String _backendConfigKey = 'backend_url_config';
  static const String _basePathKey = 'api_base_path';
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
  String _basePath = '';
  String _sessionToken = '';
  ConnectionMode _connectionMode;
  final TailnetService? _tailnetService;
  final http.Client Function() _directClientFactory;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  ApiClient({
    String scheme = 'http',
    String? host,
    int port = _defaultPort,
    ConnectionMode connectionMode = ConnectionMode.direct,
    String basePath = '',
    TailnetService? tailnetService,
    http.Client Function()? directClientFactory,
  }) : _scheme = _normalizeScheme(scheme),
       _host = _normalizeHost(host ?? _defaultHost),
       // Keep the public named argument `port` instead of exposing `_port`.
       // ignore: prefer_initializing_formals
       _port = port,
       _basePath = _normalizeBasePath(basePath),
       // Keep the public named argument `connectionMode`.
       // ignore: prefer_initializing_formals
       _connectionMode = connectionMode,
       // Keep the public named argument `tailnetService`.
       // ignore: prefer_initializing_formals
       _tailnetService = tailnetService,
       _directClientFactory =
           directClientFactory ?? _defaultDirectClientFactory;

  /// dart:io's raw sockets fight iOS Local Network privacy (release-mode
  /// `errno = 65`); use the NSURLSession-backed client on iOS so the same
  /// permission rules as Safari/CFNetwork apply. See flutter/flutter#171197.
  static http.Client _defaultDirectClientFactory() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoClient.defaultSessionConfiguration();
    }
    return http.Client();
  }

  Uri get _originUri => Uri(scheme: _scheme, host: _host, port: _port);
  String get _apiPathPrefix => _basePath.isEmpty ? '/api' : '/$_basePath/api';
  String get baseUrl => _originUri.replace(path: _apiPathPrefix).toString();
  String get wsUrl => _originUri
      .replace(
        scheme: _scheme == 'https' ? 'wss' : 'ws',
        path: '$_apiPathPrefix/runtime-stream',
      )
      .toString();
  String get scheme => _scheme;
  String get host => _host;
  int get port => _port;
  String get basePath => _basePath;
  ConnectionMode get connectionMode => _connectionMode;
  bool get usesTailscale => _connectionMode == ConnectionMode.tailscale;
  bool get supportsWebSocket => !usesTailscale;
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
    _basePath = _normalizeBasePath(prefs.getString(_basePathKey) ?? '');
    _sessionToken = prefs.getString(_sessionKey) ?? '';
    final savedMode = prefs.getString(_connectionModeKey);
    _connectionMode =
        savedMode == ConnectionMode.tailscale.name &&
            _tailnetService?.supported == true
        ? ConnectionMode.tailscale
        : ConnectionMode.direct;
    // 重装 App 后 SharedPreferences 会被清空，但 iOS Keychain / Android
    // Keystore 可能仍保留上次配置。这里用于恢复后端地址，避免每次重装都重填。
    if (_host == _defaultHost) {
      try {
        final stored = await _secureStorage.read(key: _backendConfigKey);
        if (stored != null && stored.isNotEmpty) {
          final decoded = jsonDecode(stored);
          if (decoded is Map) {
            final storedHost = decoded['host']?.toString().trim() ?? '';
            if (storedHost.isNotEmpty) {
              _scheme = _normalizeScheme(
                decoded['scheme']?.toString() ?? _scheme,
              );
              _host = _normalizeHost(storedHost);
              _port = decoded['port'] is num
                  ? (decoded['port'] as num).toInt()
                  : _defaultPort;
              _basePath = _normalizeBasePath(
                decoded['base_path']?.toString() ?? '',
              );
              final storedMode = decoded['connection_mode']?.toString();
              _connectionMode =
                  storedMode == ConnectionMode.tailscale.name &&
                      _tailnetService?.supported == true
                  ? ConnectionMode.tailscale
                  : ConnectionMode.direct;
            }
          }
        }
      } catch (_) {
        // 读不到安全存储时继续使用默认/普通配置。
      }
    }
    if (usesTailscale) await _tailnetService?.connect();
  }

  Future<void> saveSettings(
    String host,
    int port, {
    String? scheme,
    String basePath = '',
    ConnectionMode? connectionMode,
  }) async {
    final nextScheme = _normalizeScheme(scheme ?? _scheme);
    final nextHost = _normalizeHost(host);
    final nextBasePath = _normalizeBasePath(basePath);
    final requestedMode = connectionMode ?? _connectionMode;
    final nextMode =
        requestedMode == ConnectionMode.tailscale &&
            _tailnetService?.supported == true
        ? requestedMode
        : ConnectionMode.direct;
    final changed =
        nextScheme != _scheme ||
        nextHost != _host ||
        port != _port ||
        nextBasePath != _basePath ||
        nextMode != _connectionMode;
    _scheme = nextScheme;
    _host = nextHost;
    _port = port;
    _basePath = nextBasePath;
    _connectionMode = nextMode;
    if (changed) clearSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_schemeKey, _scheme);
    await prefs.setString(_hostKey, _host);
    await prefs.setInt(_portKey, port);
    await prefs.setString(_basePathKey, _basePath);
    await prefs.setString(_connectionModeKey, _connectionMode.name);
    try {
      await _secureStorage.write(
        key: _backendConfigKey,
        value: jsonEncode({
          'scheme': _scheme,
          'host': _host,
          'port': _port,
          'base_path': _basePath,
          'connection_mode': _connectionMode.name,
        }),
      );
    } catch (_) {
      // Keychain/Keystore failure must not block normal setting saves.
    }
  }

  Uri apiUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final relative = Uri.parse(normalizedPath);
    return _originUri.replace(
      path: '$_apiPathPrefix${relative.path}',
      query: relative.hasQuery ? relative.query : null,
    );
  }

  static String _normalizeBasePath(String value) {
    var path = value.trim();
    if (path.isEmpty) return '';
    if (path == '/') return '';
    if (path.startsWith('/')) path = path.substring(1);
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  void clearSession() {
    _sessionToken = '';
    SharedPreferences.getInstance().then((prefs) => prefs.remove(_sessionKey));
  }

  void _captureSession(http.BaseResponse res) {
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
    final res = await _getWithRetry(
      uri,
      headers: _headers(),
      timeout: Duration(seconds: timeout ?? 10),
    );
    _captureSession(res);
    if (res.statusCode == 401) clearSession();
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return _decodeMap(res.body);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    int? timeout,
  }) async {
    final uri = apiUri(path);
    final lease = _openClient();
    try {
      final res = await lease.client
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
      lease.close();
    }
  }

  Stream<String> streamPostLines(
    String path, {
    Map<String, dynamic>? body,
  }) async* {
    final uri = apiUri(path);
    // Use a plain http.Client (not CupertinoClient) for SSE: CupertinoClient
    // can buffer streaming responses until the connection closes, which makes
    // chat look like "后台处理中 → 整段出现".
    final client = http.Client();
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(_headers())
        ..body = jsonEncode(body ?? {});
      final response = await client.send(request);
      _captureSession(response);
      if (response.statusCode == 401) clearSession();
      if (response.statusCode >= 400) {
        final text = await response.stream.bytesToString();
        throw ApiException(response.statusCode, text);
      }
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        yield line;
      }
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
    final lease = _openClient();
    try {
      final res = await lease.client
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
      lease.close();
    }
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final uri = apiUri(path);
    final lease = _openClient();
    try {
      final res = await lease.client
          .delete(uri, headers: _headers())
          .timeout(const Duration(seconds: 10));
      _captureSession(res);
      if (res.statusCode == 401) clearSession();
      if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
      return _decodeMap(res.body);
    } finally {
      lease.close();
    }
  }

  Future<Uint8List> getBytes(Uri uri, {Map<String, String>? headers}) async {
    final res = await _getWithRetry(
      uri,
      headers: {..._headers(), ...?headers},
      timeout: const Duration(seconds: 15),
    );
    _captureSession(res);
    if (res.statusCode == 401) clearSession();
    if (res.statusCode >= 400) throw ApiException(res.statusCode, res.body);
    return res.bodyBytes;
  }

  Future<bool> checkHealth({
    String? overrideHost,
    int? overridePort,
    String? overrideBasePath,
    ConnectionMode? overrideConnectionMode,
  }) async {
    try {
      var nextScheme = _scheme;
      var nextHost = overrideHost ?? _host;
      var nextBasePath = _normalizeBasePath(overrideBasePath ?? _basePath);
      final parsed = Uri.tryParse(nextHost);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        nextScheme = _normalizeScheme(parsed.scheme);
        nextHost = parsed.host;
        final parsedPath = parsed.path.replaceFirst(RegExp(r'^/'), '');
        if (parsedPath.isNotEmpty) {
          // Support pasting the full backend URL, including an optional path
          // segment before the API root (e.g. /openbiliclaw/api).
          nextBasePath = parsedPath == 'api' ? '' : parsedPath;
          if (nextBasePath.endsWith('/api')) {
            nextBasePath = nextBasePath.substring(0, nextBasePath.length - 4);
          }
          nextBasePath = _normalizeBasePath(nextBasePath);
        }
      }
      final h = _normalizeHost(nextHost);
      final p = overridePort ?? _port;
      final prefix = nextBasePath.isEmpty ? '/api' : '/$nextBasePath/api';
      final uri = Uri(
        scheme: nextScheme,
        host: h,
        port: p,
        path: '$prefix/health',
      );
      final selectedMode = overrideConnectionMode ?? _connectionMode;
      final res = await _getWithRetry(
        uri,
        headers: const {'X-OBC-Auth': '1'},
        timeout: Duration(
          seconds: selectedMode == ConnectionMode.tailscale ? 30 : 5,
        ),
        mode: selectedMode,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _getWithRetry(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ConnectionMode? mode,
  }) async {
    final selectedMode = mode ?? _connectionMode;
    // A freshly-running mobile tailnet can report its node state before the
    // first peer path has fully settled. Keep retries bounded to idempotent
    // GETs and known transport failures, but allow enough time for that path
    // to become usable on slower Android devices.
    const retryDelays = [
      Duration(milliseconds: 300),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ];

    for (var attempt = 0; ; attempt += 1) {
      final lease = _openClient(mode: selectedMode);
      try {
        return await lease.client.get(uri, headers: headers).timeout(timeout);
      } catch (error) {
        final canRetry =
            selectedMode == ConnectionMode.tailscale &&
            attempt < retryDelays.length &&
            _isTransientTailnetGetError(error);
        if (!canRetry) rethrow;
      } finally {
        lease.close();
      }
      await Future<void>.delayed(retryDelays[attempt]);
    }
  }

  static bool _isTransientTailnetGetError(Object error) {
    if (error is! http.ClientException) return false;
    final message = error.message.toLowerCase();
    return message.contains('eof') ||
        message.contains('connection reset') ||
        message.contains('broken pipe') ||
        message.contains('closed before');
  }

  _ClientLease _openClient({ConnectionMode? mode}) {
    final selectedMode = mode ?? _connectionMode;
    if (selectedMode == ConnectionMode.tailscale) {
      final client = _tailnetService?.httpClient;
      if (client == null) {
        throw StateError('Tailscale 尚未连接');
      }
      return _ClientLease(client, owned: false);
    }
    return _ClientLease(_directClientFactory(), owned: true);
  }

  static String _normalizeScheme(String value) {
    return value.trim().toLowerCase() == 'https' ? 'https' : 'http';
  }

  static String _normalizeHost(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;

    // Treat the setting as an authority even when the user pastes `host:port`.
    // Parsing that value as a relative URI leaves the port attached to the
    // host, and a later `Uri(host: ...)` then throws "Illegal IPv4 address".
    // Adding a temporary scheme lets Uri consistently extract IPv4, DNS and
    // bracketed IPv6 hosts. The separately configured port remains authoritative.
    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
    final candidate = hasScheme ? trimmed : 'http://$trimmed';
    try {
      final parsed = Uri.tryParse(candidate);
      if (parsed != null && parsed.host.isNotEmpty) return parsed.host;
    } on FormatException {
      // Fall through for a raw, unbracketed IPv6 literal.
    }

    if (trimmed.startsWith('[')) {
      final closingBracket = trimmed.indexOf(']');
      if (closingBracket > 1) return trimmed.substring(1, closingBracket);
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

class _ClientLease {
  const _ClientLease(this.client, {required this.owned});

  final http.Client client;
  final bool owned;

  void close() {
    if (owned) client.close();
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
