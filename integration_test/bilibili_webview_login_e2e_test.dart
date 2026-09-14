import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:openbiliclaw_app/api/bilibili_api.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/services/bilibili_webview_session.dart';
import 'package:openbiliclaw_app/views/bilibili_video_page.dart';

/// 真实后端验证：内置 WebView 首屏就带上后端已有的 B 站登录态。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('内置 WebView 带上后端 B 站登录态', (tester) async {
    final client = _backendClient();
    final session = await BilibiliApi(client).exportSession();
    expect(session.cookie, isNotEmpty, reason: '后端没有可用的 B 站登录态');

    await tester.pumpWidget(
      Provider<ApiClient>.value(
        value: client,
        child: MaterialApp(
          home: BilibiliVideoPage(
            bvid: 'BV1xx411c7mD',
            title: 'WebView 登录态测试',
            sessionCookie: session.cookie,
          ),
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () async => find.textContaining('已带上 B 站登录态').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 30),
    );
    expect(find.textContaining('已带上 B 站登录态'), findsOneWidget);
  });

  testWidgets('B 站同源引导页可用 document.cookie 写入未编码的值', (tester) async {
    final manager = WebViewCookieManager();
    await manager.clearCookies();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final loaded = Completer<void>();
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: controller)),
      ),
    );
    await controller.loadRequest(Uri.parse(kBilibiliCookieBootstrapUrl));
    await loaded.future.timeout(const Duration(seconds: 20));

    const rawValue = 'raw%2Avalue%2Cpart';
    await controller.runJavaScript(
      buildBilibiliCookieScript('SESSDATA=$rawValue; bili_jct=csrf'),
    );

    final cookies = await manager.getCookies(
      domain: Uri.parse('https://www.bilibili.com'),
    );
    final sessdata = cookies
        .where((cookie) => cookie.name == 'SESSDATA')
        .toList();
    expect(sessdata, isNotEmpty, reason: '引导页没有写入 SESSDATA');
    expect(sessdata.last.value, rawValue, reason: 'Cookie 值被再次 URL 编码');
    await manager.clearCookies();
  });

  testWidgets('WKHTTPCookieStore 原样保存后端 Cookie 值', (tester) async {
    final manager = WebViewCookieManager();
    await manager.clearCookies();
    const rawValue = 'raw%2Avalue%2Cpart';

    final written = await injectBilibiliCookies(
      cookieHeader: 'SESSDATA=$rawValue; bili_jct=csrf',
    );
    expect(written, 2);

    final cookies = await manager.getCookies(
      domain: Uri.parse('https://www.bilibili.com'),
    );
    final sessdata = cookies
        .where((cookie) => cookie.name == 'SESSDATA')
        .toList();
    expect(sessdata, isNotEmpty, reason: 'WKHTTPCookieStore 没有写入 SESSDATA');
    expect(sessdata.last.value, rawValue, reason: 'Cookie 值被改动');
    await manager.clearCookies();
  });

  testWidgets('真实 B 站 nav 接口确认 WebView 已是登录态', (tester) async {
    final client = _backendClient();
    final session = await BilibiliApi(client).exportSession();
    expect(session.cookie, isNotEmpty, reason: '后端没有可用的 B 站登录态');

    final manager = WebViewCookieManager();
    await manager.clearCookies();
    final written = await injectBilibiliCookies(cookieHeader: session.cookie);
    expect(written, greaterThan(0));

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    final navResult = Completer<Map<String, dynamic>>();
    controller.addJavaScriptChannel(
      'BiliNav',
      onMessageReceived: (message) {
        if (navResult.isCompleted) return;
        try {
          final decoded = jsonDecode(message.message);
          if (decoded is Map) {
            navResult.complete(Map<String, dynamic>.from(decoded));
          } else {
            navResult.completeError(
              StateError('nav 返回不是对象: ${message.message}'),
            );
          }
        } catch (error) {
          navResult.completeError(error);
        }
      },
    );
    final loaded = Completer<void>();
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: controller)),
      ),
    );
    await controller.loadRequest(
      Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
    );
    await loaded.future.timeout(const Duration(seconds: 30));

    await controller.runJavaScript(r'''
      fetch('https://api.bilibili.com/x/web-interface/nav', {credentials: 'include'})
        .then(function(r) { return r.json(); })
        .then(function(d) {
          BiliNav.postMessage(JSON.stringify({
            code: d.code,
            isLogin: !!(d.data && d.data.isLogin),
            uname: (d.data && d.data.uname) || ''
          }));
        })
        .catch(function(e) {
          BiliNav.postMessage(JSON.stringify({error: String(e)}));
        });
    ''');

    final result = await navResult.future.timeout(const Duration(seconds: 20));
    debugPrint('E2E bilibili nav result: $result');
    expect(result['error'], isNull, reason: 'B 站 nav 请求失败: $result');
    expect(result['code'], 0, reason: 'B 站 nav 返回异常: $result');
    expect(result['isLogin'], isTrue, reason: 'WebView 未携带登录态: $result');

    await manager.clearCookies();
  });
}

ApiClient _backendClient() {
  // Android 模拟器通过 10.0.2.2 访问宿主机；iOS/macOS 直接走 127.0.0.1。
  final host = defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : '127.0.0.1';
  return ApiClient(host: host, port: 8420);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (await condition()) return;
  }
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .toList();
  debugPrint('E2E timeout page texts: $texts');
  throw TestFailure('等待条件超时');
}
