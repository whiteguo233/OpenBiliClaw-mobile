import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/services/tailnet_service.dart';
import 'package:openbiliclaw_app/views/settings_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _IdleRecommendations extends RecommendProvider {
  _IdleRecommendations(super.client);
  int restarts = 0;
  @override
  void startPolling() => restarts++;
  @override
  void stopPolling() {}
}

class _Tailnet extends TailnetService {
  _Tailnet({this.canConnect = true});
  final bool canConnect;
  int connections = 0;
  TailnetState _state = TailnetState.idle;
  @override
  bool get supported => true;
  @override
  TailnetState get state => _state;
  @override
  String get statusMessage => canConnect ? '已连接' : '登录未完成';
  @override
  String? get ipAddress => '100.100.1.9';
  @override
  Uri? get authUrl => null;
  @override
  http.Client get httpClient =>
      MockClient((_) async => http.Response('{}', 200));
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> connect({String authKey = ''}) async {
    connections++;
    _state = canConnect ? TailnetState.running : TailnetState.error;
    return canConnect;
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

void main() {
  for (final entry in <String?, String>{
    'http://192.168.1.7:8420/m/': 'http://192.168.1.7:8420/api',
    'http://100.100.1.2:19090/m/': 'http://100.100.1.2:19090/api',
    'http://100.100.1.3:8421/m/?obc_connection=tailscale':
        'http://100.100.1.3:8421/api',
    'https://obc.example.com:9443/prefix/m/':
        'https://obc.example.com:9443/prefix/api',
    'http://127.0.0.1:8420/m/': 'http://192.168.9.9:8420/api',
    null: 'http://192.168.9.9:8420/api',
    'http://100.100.1.4:8421/m/?obc_connection=tailscale':
        'http://192.168.9.9:8420/api',
  }.entries) {
    testWidgets('scan saves and reconnects ${entry.key}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final canConnect = !(entry.key?.contains('100.100.1.4') ?? false);
      final tailnet = _Tailnet(canConnect: canConnect);
      final client = ApiClient(
        host: '192.168.9.9',
        tailnetService: tailnet,
        directClientFactory: () =>
            MockClient((_) async => http.Response('{}', 200)),
      );
      await client.saveSettings('192.168.9.9', 8420);
      final recommendations = _IdleRecommendations(client);
      addTearDown(tailnet.dispose);
      addTearDown(recommendations.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: client),
            ChangeNotifierProvider<TailnetService>.value(value: tailnet),
            ChangeNotifierProvider<RecommendProvider>.value(
              value: recommendations,
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SettingsView(scanConnection: (_) async => entry.key),
                    ),
                  ),
                  child: const Text('连接设置'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('连接设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('扫码连接'));
      await tester.pumpAndSettle();
      expect(client.baseUrl, entry.value);
      expect(
        client.usesTailscale,
        canConnect &&
            (entry.key?.contains('obc_connection=tailscale') ?? false),
      );
      expect(
        tailnet.connections,
        (entry.key?.contains('obc_connection=tailscale') ?? false) ? 1 : 0,
      );
      final imported =
          canConnect && entry.key != null && !entry.key!.contains('127.0.0.1');
      expect(recommendations.restarts, imported ? 1 : 0);
      expect(find.byTooltip('扫码连接'), imported ? findsNothing : findsOneWidget);
      final restored = ApiClient(tailnetService: tailnet);
      await restored.loadSettings();
      expect(restored.baseUrl, client.baseUrl);
      expect(restored.connectionMode, client.connectionMode);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
