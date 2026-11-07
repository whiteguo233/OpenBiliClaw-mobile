import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/diagnostics_api.dart';
import 'package:openbiliclaw_app/views/diagnostics_view.dart';

const event = {
  'id': 'source:1',
  'category': 'discovery',
  'severity': 'warning',
  'source_id': 'custom/a',
  'source_name': 'Rust 博客',
  'message': '连接网站超时，稍后自动重试。',
  'last_seen': 1793976000,
  'count': 1,
};
const source = {
  'source_id': 'custom/a',
  'name': 'Rust 博客',
  'enabled': true,
  'target_share': 3,
  'interval_minutes': 5,
  'entry_url': 'https://example.com/',
  'health': {
    'status': 'failed',
    'attention_required': true,
    'attention_action': 'source_settings',
    'message': '已连续失败 3 次。连接网站超时。',
    'next_run_at': 1793976000,
  },
  'workflows': [
    {'executor': 'http', 'status': 'failed', 'intent': '最新文章'},
  ],
};

http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'history retains errors on failed polling and shows recovery separately',
    (tester) async {
      var fail = false, recovered = false, calls = 0;
      final client = ApiClient(
        directClientFactory: () => MockClient((r) async {
          expectSync(r.url.path, '/api/diagnostics/alerts');
          calls++;
          if (fail) return http.Response('offline', 503);
          return json({
            'alerts': [
              if (recovered)
                {
                  ...event,
                  'id': 'source:2',
                  'severity': 'info',
                  'message': '采集已恢复',
                },
              event,
            ],
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: DiagnosticsView(api: DiagnosticsApi(client))),
      );
      await tester.pumpAndSettle();
      expect(find.text('警告 · Rust 博客'), findsOneWidget);
      fail = true;
      await tester.tap(find.byTooltip('刷新异常记录'));
      await tester.pumpAndSettle();
      expect(find.text('连接网站超时，稍后自动重试。'), findsOneWidget);
      expect(find.text('异常记录暂时无法刷新，请稍后重试。'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = calls;
      await tester.pump(const Duration(seconds: 31));
      expect(calls, before);
      fail = false;
      recovered = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(calls, before + 1, reason: 'foreground must refresh history');
      expect(find.text('已恢复 · Rust 博客'), findsOneWidget);
      expect(find.text('警告 · Rust 博客'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'history opens only the affected source and never starts login or retries',
    (tester) async {
      final paths = <String>[];
      final client = ApiClient(
        directClientFactory: () => MockClient((r) async {
          expectSync(r.method, 'GET');
          paths.add(r.url.path);
          if (r.url.path == '/api/diagnostics/alerts') {
            return json({
              'alerts': [event],
            });
          }
          expectSync(r.url.path, '/api/custom-sources');
          return json({
            'items': [
              source,
              {...source, 'source_id': 'other', 'name': '另一个来源'},
            ],
            'executors': [],
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: DiagnosticsView(api: DiagnosticsApi(client))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看来源'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('source-custom/a')), findsOneWidget);
      expect(find.byKey(const ValueKey('source-other')), findsNothing);
      expect(find.text('已连续失败 3 次。连接网站超时。'), findsOneWidget);
      expect(find.text('处理登录或验证'), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      expect(paths, ['/api/diagnostics/alerts', '/api/custom-sources']);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
