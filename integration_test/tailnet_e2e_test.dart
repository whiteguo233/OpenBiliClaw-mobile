import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/services/tailnet_service.dart';

/// Real embedded-Tailscale smoke test.
///
/// Supply the short-lived enrollment credential at build time:
///
/// flutter test integration_test/tailnet_e2e_test.dart -d IOS_DEVICE_ID \
///   --dart-define=OBC_E2E_TAILSCALE_AUTH_KEY=ONE_OFF_KEY \
///   --dart-define=OBC_E2E_TAILSCALE_HOST=TAILNET_IP_OR_MAGICDNS
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const authKey = String.fromEnvironment('OBC_E2E_TAILSCALE_AUTH_KEY');
  const authUrlOnly = bool.fromEnvironment('OBC_E2E_AUTH_URL_ONLY');
  const host = String.fromEnvironment('OBC_E2E_TAILSCALE_HOST');
  const port = int.fromEnvironment(
    'OBC_E2E_TAILSCALE_PORT',
    defaultValue: 8420,
  );

  testWidgets('内置 Tailscale：入网、真实健康请求、无 Key 重连', (tester) async {
    final stopwatch = Stopwatch()..start();
    void stage(String message) {
      // Device labs and software-rendered emulators can be very slow. These
      // markers make a timeout actionable without exposing the enrollment key.
      // ignore: avoid_print
      print('[tailnet-e2e +${stopwatch.elapsed.inSeconds}s] $message');
    }

    final tailnet = createTailnetService();
    addTearDown(() async {
      stage('清理设备身份');
      await tailnet.logout();
      tailnet.dispose();
      stage('清理完成');
    });

    expect(tailnet.supported, isTrue, reason: tailnet.statusMessage);
    expect(host, isNotEmpty, reason: '必须通过 dart-define 提供 tailnet 后端地址');
    stage('开始初次入网');
    var enrolled = await tailnet.connect(authKey: authKey);
    stage('初次入网结束：state=${tailnet.state.name}');
    if (authKey.isNotEmpty) {
      expect(
        enrolled,
        isTrue,
        reason: '已提供 Auth Key，但控制面仍要求网页登录：${tailnet.statusMessage}',
      );
    }
    if (!enrolled && authUrlOnly) {
      expect(tailnet.authUrl, isNotNull, reason: tailnet.statusMessage);
      expect(tailnet.authUrl!.scheme, 'https');
      expect(tailnet.authUrl!.host, 'login.tailscale.com');
      return;
    }
    if (!enrolled && tailnet.authUrl != null) {
      final opened = await launchUrl(
        tailnet.authUrl!,
        mode: LaunchMode.externalApplication,
      );
      expect(opened, isTrue, reason: '无法打开 Tailscale 网页登录');
      enrolled = await tailnet.waitForConnection();
    }
    expect(enrolled, isTrue, reason: tailnet.statusMessage);
    expect(tailnet.state, TailnetState.running);
    expect(tailnet.ipAddress, isNotNull);

    final client = ApiClient(
      host: host,
      port: port,
      connectionMode: ConnectionMode.tailscale,
      tailnetService: tailnet,
    );
    stage('开始第一次真实健康请求');
    final health = await client.get('/health', timeout: 30);
    expect(health['status'], 'ok');
    stage('第一次真实健康请求成功');

    stage('断开 tailnet');
    await tailnet.disconnect();
    stage('开始无 Key 重连');
    final reconnected = await tailnet.connect();
    expect(reconnected, isTrue, reason: tailnet.statusMessage);
    stage('无 Key 重连成功');
    final reconnectHealth = await client.get('/health', timeout: 30);
    expect(reconnectHealth['status'], 'ok');
    stage('第二次真实健康请求成功');
    expect(await client.checkHealth(), isTrue);
    stage('完整 E2E 流程通过');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
