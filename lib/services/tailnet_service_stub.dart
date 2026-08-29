import 'package:http/http.dart' as http;

import 'tailnet_service.dart';

TailnetService createTailnetService() => _UnsupportedTailnetService();

class _UnsupportedTailnetService extends TailnetService {
  @override
  bool get supported => false;

  @override
  TailnetState get state => TailnetState.unsupported;

  @override
  String get statusMessage => '当前平台暂不支持内置 Tailscale';

  @override
  String? get ipAddress => null;

  @override
  Uri? get authUrl => null;

  @override
  http.Client? get httpClient => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> connect({String authKey = ''}) async => false;

  @override
  Future<bool> waitForConnection({
    Duration timeout = const Duration(minutes: 5),
  }) async => false;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> logout() async {}
}
