import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbiliclaw_app/main.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/custom_sources_api.dart';
import 'package:openbiliclaw_app/views/custom_sources_view.dart';
import 'package:openbiliclaw_app/views/diagnostics_view.dart';
import 'package:openbiliclaw_app/providers/source_attention_provider.dart';

// Private backend only. The control process injects failures through WorkflowStore;
// recovery performs a real public RSS fetch. This is not a natural-cadence test.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native source failure, history and recovery use the real API', (
    tester,
  ) async {
    const sourceId = String.fromEnvironment('NATIVE_FAILURE_SOURCE');
    const port = int.fromEnvironment(
      'NATIVE_FAILURE_PORT',
      defaultValue: 18616,
    );
    const controlPort = int.fromEnvironment(
      'NATIVE_FAILURE_CONTROL_PORT',
      defaultValue: 18617,
    );
    expect(sourceId, isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    await prefs.setString('api_host', 'localhost');
    await prefs.setInt('api_port', port);
    await prefs.setString('api_scheme', 'http');
    await prefs.setString('api_base_path', '');
    await prefs.setString('connection_mode', 'direct');
    await prefs.remove('session_token');

    Future<void> waitFor(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(ready(), isTrue);
    }

    Future<void> control(String action) async {
      final response = await http
          .post(Uri.parse('http://localhost:$controlPort/$action'))
          .timeout(const Duration(seconds: 120));
      expect(response.statusCode, 200);
    }

    Future<void> screenshot(String name) async {
      // Wait for route animation and the following native compositor frame.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      await binding.takeScreenshot(name);
    }

    try {
      await tester.pumpWidget(const OpenBiliClawApp());
      await waitFor(() => find.text('对话').evaluate().isNotEmpty);
      final context = tester.element(find.text('对话'));
      final api = CustomSourcesApi(context.read<ApiClient>());
      final attention = context.read<SourceAttentionProvider>();
      expect(
        (await api.attention()).where((x) => x['source_id'] == sourceId),
        isEmpty,
      );
      await control('fail');
      await waitFor(
        () => find.byTooltip(RegExp('条待处理消息')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      final card = find.byKey(ValueKey('source-attention-source:$sourceId'));
      await waitFor(() => card.evaluate().isNotEmpty);
      await tester.ensureVisible(card);
      await tester.pump(const Duration(seconds: 1));
      await screenshot('source-failure-inbox');
      await tester.tap(find.descendant(of: card, matching: find.text('查看来源')));
      await waitFor(
        () => find
            .descendant(
              of: find.byKey(const ValueKey('source-$sourceId')),
              matching: find.textContaining('已连续失败 3 次'),
            )
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('处理登录或验证'), findsNothing);
      await screenshot('source-failure-settings');
      await tester.tap(find.byTooltip('查看异常记录'));
      await waitFor(
        () => find.text('警告 · Django RSS 异常提醒验收').evaluate().isNotEmpty,
      );
      await screenshot('source-failure-history');
      await control('recover');
      await tester.tap(find.byTooltip('刷新异常记录'));
      await waitFor(
        () => find.text('已恢复 · Django RSS 异常提醒验收').evaluate().isNotEmpty,
      );
      expect(find.text('警告 · Django RSS 异常提醒验收'), findsWidgets);
      expect(
        (await api.attention()).where((x) => x['source_id'] == sourceId),
        isEmpty,
      );
      await screenshot('source-recovered-history');
      await tester.pageBack();
      await waitFor(() => find.byType(DiagnosticsView).evaluate().isEmpty);
      await tester.pageBack();
      await waitFor(() => find.byType(CustomSourcesView).evaluate().isEmpty);
      await attention.refresh();
      await tester.pump(const Duration(seconds: 1));
      expect(card, findsNothing);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byTooltip('连接设置'));
      final history = find.byKey(const Key('diagnosticsSettings'));
      await waitFor(() => history.evaluate().isNotEmpty);
      await tester.ensureVisible(history);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(history);
      await waitFor(
        () =>
            find.byType(DiagnosticsView).evaluate().isNotEmpty &&
            find.text('已恢复 · Django RSS 异常提醒验收').evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      debugPrint(
        'NATIVE_SOURCE_FAILURES PASS source=$sourceId warning/recovery/history/settings',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await prefs.clear();
      for (final e in before.entries) {
        final v = e.value;
        if (v is String) {
          await prefs.setString(e.key, v);
        } else if (v is int) {
          await prefs.setInt(e.key, v);
        } else if (v is bool) {
          await prefs.setBool(e.key, v);
        } else if (v is double) {
          await prefs.setDouble(e.key, v);
        } else if (v is List<String>) {
          await prefs.setStringList(e.key, v);
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 7)));
}
