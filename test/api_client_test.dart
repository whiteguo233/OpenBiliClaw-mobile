import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/services/tailnet_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'apiUri preserves query parameters instead of encoding them into path',
    () {
      final client = ApiClient(host: '127.0.0.1', port: 8420);

      final uri = client.apiUri('/activity-feed?limit=5&before=a%3Ab');

      expect(uri.path, '/api/activity-feed');
      expect(uri.queryParameters['limit'], '5');
      expect(uri.queryParameters['before'], 'a:b');
      expect(uri.toString(), contains('/api/activity-feed?'));
      expect(uri.toString(), isNot(contains('%3Flimit')));
    },
  );

  test('constructs https and wss endpoints from one origin', () {
    final client = ApiClient(scheme: 'https', host: 'example.test', port: 9443);

    expect(client.baseUrl, 'https://example.test:9443/api');
    expect(client.wsUrl, 'wss://example.test:9443/api/runtime-stream');
    expect(client.apiUri('profile-summary').scheme, 'https');
  });

  test('accepts an IPv4 host pasted with its port', () {
    final client = ApiClient(host: '100.100.100.100:8420', port: 8420);

    expect(client.host, '100.100.100.100');
    expect(client.baseUrl, 'http://100.100.100.100:8420/api');
    expect(client.apiUri('recommendations').host, '100.100.100.100');
  });

  test('extracts hosts from common endpoint input formats', () {
    final domain = ApiClient(host: 'openbiliclaw.local:8420', port: 8420);
    final url = ApiClient(
      scheme: 'https',
      host: 'https://example.test:9443/api',
      port: 9443,
    );
    final ipv6 = ApiClient(host: '[fd00::1234]:8420', port: 8420);

    expect(domain.host, 'openbiliclaw.local');
    expect(url.host, 'example.test');
    expect(ipv6.host, 'fd00::1234');
    expect(ipv6.baseUrl, 'http://[fd00::1234]:8420/api');
  });

  test('uses the shared tailnet HTTP client without closing it', () async {
    final transport = _TrackingClient();
    final tailnet = _FakeTailnetService(transport);
    final client = ApiClient(
      host: 'openbiliclaw-server',
      connectionMode: ConnectionMode.tailscale,
      tailnetService: tailnet,
    );

    final healthy = await client.checkHealth(
      overrideConnectionMode: ConnectionMode.tailscale,
    );

    expect(healthy, isTrue);
    expect(transport.closed, isFalse);
    expect(transport.lastRequest?.url.host, 'openbiliclaw-server');
  });

  test('retries a transient EOF for an idempotent tailnet GET', () async {
    final transport = _TransientEofClient();
    final tailnet = _FakeTailnetService(transport);
    final client = ApiClient(
      host: 'openbiliclaw-server',
      connectionMode: ConnectionMode.tailscale,
      tailnetService: tailnet,
    );

    final healthy = await client.checkHealth();

    expect(healthy, isTrue);
    expect(transport.sendCalls, 2);
    expect(transport.closed, isFalse);
  });

  test(
    'allows a freshly-started tailnet path to survive repeated resets',
    () async {
      final transport = _TransientResetClient(failures: 3);
      final tailnet = _FakeTailnetService(transport);
      final client = ApiClient(
        host: 'openbiliclaw-server',
        connectionMode: ConnectionMode.tailscale,
        tailnetService: tailnet,
      );

      final healthy = await client.checkHealth();

      expect(healthy, isTrue);
      expect(transport.sendCalls, 4);
      expect(transport.closed, isFalse);
    },
  );

  test(
    'restores tailnet mode and reconnects without persisting an auth key',
    () async {
      final firstService = _FakeTailnetService(_TrackingClient());
      final firstClient = ApiClient(tailnetService: firstService);
      await firstClient.saveSettings(
        'server.tailnet.test',
        8420,
        connectionMode: ConnectionMode.tailscale,
      );

      final restoredService = _FakeTailnetService(_TrackingClient());
      final restoredClient = ApiClient(tailnetService: restoredService);
      await restoredClient.loadSettings();

      expect(restoredClient.connectionMode, ConnectionMode.tailscale);
      expect(restoredService.initializeCalls, 1);
      expect(restoredService.connectCalls, 1);
      expect(restoredService.lastAuthKey, isEmpty);
    },
  );

  test('direct mode never initializes the native tailnet runtime', () async {
    SharedPreferences.setMockInitialValues({
      'connection_mode': ConnectionMode.direct.name,
    });
    final service = _FakeTailnetService(_TrackingClient());
    final client = ApiClient(tailnetService: service);

    await client.loadSettings();

    expect(client.connectionMode, ConnectionMode.direct);
    expect(service.initializeCalls, 0);
    expect(service.connectCalls, 0);
  });
}

class _TrackingClient extends http.BaseClient {
  bool closed = false;
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _TransientEofClient extends http.BaseClient {
  int sendCalls = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCalls += 1;
    if (sendCalls == 1) {
      throw http.ClientException('EOF', request.url);
    }
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _TransientResetClient extends http.BaseClient {
  _TransientResetClient({required this.failures});

  final int failures;
  int sendCalls = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCalls += 1;
    if (sendCalls <= failures) {
      throw http.ClientException('connection reset by peer', request.url);
    }
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _FakeTailnetService extends TailnetService {
  _FakeTailnetService(this._client);

  final http.Client _client;
  int initializeCalls = 0;
  int connectCalls = 0;
  String lastAuthKey = '';

  @override
  bool get supported => true;

  @override
  TailnetState get state => TailnetState.running;

  @override
  String get statusMessage => '已连接';

  @override
  String? get ipAddress => '100.64.0.2';

  @override
  Uri? get authUrl => null;

  @override
  http.Client get httpClient => _client;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<bool> connect({String authKey = ''}) async {
    await initialize();
    connectCalls += 1;
    lastAuthKey = authKey;
    return true;
  }

  @override
  Future<bool> waitForConnection({
    Duration timeout = const Duration(minutes: 5),
  }) async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> logout() async {}
}
