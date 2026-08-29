import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'tailnet_service_stub.dart'
    if (dart.library.io) 'tailnet_service_native.dart'
    as implementation;

enum TailnetState {
  unsupported,
  idle,
  connecting,
  running,
  needsLogin,
  needsApproval,
  stopped,
  error,
}

abstract class TailnetService extends ChangeNotifier {
  bool get supported;
  TailnetState get state;
  String get statusMessage;
  String? get ipAddress;
  Uri? get authUrl;
  http.Client? get httpClient;

  Future<void> initialize();
  Future<bool> connect({String authKey = ''});
  Future<bool> waitForConnection({
    Duration timeout = const Duration(minutes: 5),
  });
  Future<void> disconnect();
  Future<void> logout();
}

TailnetService createTailnetService() => implementation.createTailnetService();
