import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/custom_sources_api.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/source_login_view.dart';

// Requires an isolated, real needs_login draft. This tests permission handoff,
// not CAPTCHA completion, content collection, or a complete chat flow.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native verification frame consent reaches the real Ego session', (
    tester,
  ) async {
    const draftId = String.fromEnvironment('NATIVE_VERIFICATION_DRAFT');
    const origin = String.fromEnvironment('NATIVE_VERIFICATION_ORIGIN');
    const port = int.fromEnvironment(
      'NATIVE_VERIFICATION_PORT',
      defaultValue: 18614,
    );
    expect(draftId, isNotEmpty);
    expect(origin, isNotEmpty);
    final api = CustomSourcesApi(ApiClient(host: 'localhost', port: port));
    final before = await api.draft(draftId);
    expect(before['status'], 'needs_login');
    expect(before['trial_success'], false);

    Future<void> waitFor(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 120));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(ready(), isTrue);
    }

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: SourceLoginView(api: api, draftId: draftId),
      ),
    );
    final choice = find.text('允许此登录或验证页面：$origin');
    final screenshot = find.byKey(const Key('sourceLoginScreenshot'));
    await waitFor(
      () =>
          choice.evaluate().isNotEmpty &&
          screenshot.evaluate().isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    final observed = await api.takeover(draftId);
    expect(observed['suggested_login_origins'], contains(origin));
    expect(observed['blocked_navigation_origins'], isEmpty);
    await tester.ensureVisible(choice);
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('native-verification-before-consent');

    // Only click our exact-domain permission button, never the site's challenge.
    await tester.tap(choice);
    await waitFor(
      () =>
          choice.evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    final allowed = await api.takeover(draftId);
    expect(allowed['suggested_login_origins'], isNot(contains(origin)));
    expect(allowed['blocked_frame_origins'], isNot(contains(origin)));
    final raw = find.descendant(
      of: screenshot,
      matching: find.byType(RawImage),
    );
    await waitFor(
      () =>
          raw.evaluate().isNotEmpty &&
          tester.widget<RawImage>(raw).image != null,
    );
    await tester.ensureVisible(screenshot);
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('native-verification-after-consent');
    expect((await api.draft(draftId))['trial_success'], false);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    var released = false;
    for (var attempt = 0; attempt < 30 && !released; attempt++) {
      await tester.pump(const Duration(milliseconds: 300));
      try {
        await api.screenshot(draftId);
      } on ApiException catch (error) {
        if (error.statusCode != 409) rethrow;
        released = true;
      }
    }
    expect(released, isTrue);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
