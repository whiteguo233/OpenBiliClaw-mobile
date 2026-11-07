import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbiliclaw_app/main.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/custom_sources_api.dart';
import 'package:openbiliclaw_app/views/source_login_view.dart';

// Real backend draft and real Ego screen. Never operate the site's CAPTCHA.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real verification warning reaches native inbox and recovery', (
    tester,
  ) async {
    const draftId = String.fromEnvironment('NATIVE_ATTENTION_DRAFT');
    expect(draftId, isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    await prefs.setString('api_host', 'localhost');
    await prefs.setInt('api_port', 18612);
    await prefs.setString('api_scheme', 'http');
    await prefs.setString('api_base_path', '');
    await prefs.setString('connection_mode', 'direct');
    await prefs.remove('session_token');

    Future<void> waitFor(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 150));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(ready(), isTrue);
    }

    try {
      await tester.pumpWidget(const OpenBiliClawApp());
      await waitFor(() => find.text('对话').evaluate().isNotEmpty);
      final api = CustomSourcesApi(
        tester.element(find.text('对话')).read<ApiClient>(),
      );
      final item = (await api.attention()).singleWhere(
        (x) => x['draft_id'] == draftId,
      );
      expect(item['code'], 'verification_required');
      await waitFor(
        () => find.byTooltip(RegExp('条待处理消息')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await waitFor(
        () => find
            .byKey(ValueKey('source-attention-draft:$draftId'))
            .evaluate()
            .isNotEmpty,
      );
      final card = find.byKey(ValueKey('source-attention-draft:$draftId'));
      await tester.ensureVisible(card);
      await tester.pump(const Duration(seconds: 1));
      await binding.takeScreenshot('source-attention-inbox');
      await tester.tap(find.descendant(of: card, matching: find.text('处理验证')));
      await waitFor(
        () =>
            find.byType(SourceLoginView).evaluate().isNotEmpty &&
            find
                .byKey(const Key('sourceLoginScreenshot'))
                .evaluate()
                .isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      final raw = find.descendant(
        of: find.byKey(const Key('sourceLoginScreenshot')),
        matching: find.byType(RawImage),
      );
      await waitFor(
        () =>
            raw.evaluate().isNotEmpty &&
            tester.widget<RawImage>(raw).image != null,
      );
      await binding.takeScreenshot('source-attention-recovery');
      await tester.pageBack();
      await waitFor(() => find.byType(SourceLoginView).evaluate().isEmpty);
      expect((await api.draft(draftId))['trial_success'], false);
      expect(
        (await api.attention()).where((x) => x['draft_id'] == draftId),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      debugPrint(
        'NATIVE_ATTENTION PASS draft=$draftId unresolved warning preserved',
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
  }, timeout: const Timeout(Duration(minutes: 6)));
}
