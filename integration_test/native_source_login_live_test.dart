import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/custom_sources_api.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/source_login_view.dart';

// Visual follow-up to the complete chat flow. Uses its disabled isolated source.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native Ego screenshot renders and real trial resumes', (
    tester,
  ) async {
    const sourceId = String.fromEnvironment('NATIVE_SOURCE_ID');
    expect(
      sourceId,
      isNotEmpty,
      reason: 'Pass an isolated test source via --dart-define=NATIVE_SOURCE_ID',
    );
    final api = CustomSourcesApi(ApiClient(host: 'localhost', port: 18612));
    final draft = await api.login(sourceId);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: SourceLoginView(api: api, draftId: draft['draft_id'].toString()),
      ),
    );
    final screenshot = find.byKey(const Key('sourceLoginScreenshot'));
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 300));
      if (screenshot.evaluate().isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    expect(screenshot, findsOneWidget);
    expect(tester.getSize(screenshot).width, greaterThan(100));
    expect(tester.getSize(screenshot).height, greaterThan(100));
    expect((await api.login(sourceId))['draft_id'], draft['draft_id']);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('下一个输入框'));
    final actionDeadline = DateTime.now().add(const Duration(seconds: 45));
    do {
      await tester.pump(const Duration(milliseconds: 300));
    } while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
        DateTime.now().isBefore(actionDeadline));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final raw = find.descendant(
      of: screenshot,
      matching: find.byType(RawImage),
    );
    final paintDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(paintDeadline)) {
      await tester.pump(const Duration(milliseconds: 300));
      if (raw.evaluate().isNotEmpty &&
          tester.widget<RawImage>(raw).image != null) {
        break;
      }
    }
    expect(tester.widget<RawImage>(raw).image, isNotNull);
    await tester.pump(const Duration(milliseconds: 300));
    final bytes = await binding.takeScreenshot('native-ego-login');
    final file = File('${Directory.systemTemp.path}/obc-native-ego-login.png');
    await file.writeAsBytes(bytes);
    debugPrint(
      'NATIVE_VISUAL screenshot=${file.path} pixels=${tester.getSize(screenshot)}',
    );
    // Leave without resuming: the native page must release the real Ego tab.
    await tester.pumpWidget(const SizedBox.shrink());
    var released = false;
    final closeDeadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(closeDeadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      try {
        await api.screenshot(draft['draft_id'].toString());
      } on ApiException catch (error) {
        if (error.statusCode != 409) rethrow;
        released = true;
        break;
      }
    }
    expect(
      released,
      isTrue,
      reason: 'Native exit must release the backend tab',
    );
    final reopened = await api.login(sourceId);
    expect(reopened['draft_id'], isNot(draft['draft_id']));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: SourceLoginView(
          api: api,
          draftId: reopened['draft_id'].toString(),
        ),
      ),
    );
    final reopenDeadline = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(reopenDeadline)) {
      await tester.pump(const Duration(milliseconds: 300));
      if (screenshot.evaluate().isNotEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    expect(screenshot, findsOneWidget);
    final resume = find.byKey(const Key('sourceLoginResume'));
    await tester.ensureVisible(resume);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
    await tester.tap(resume);
    await tester.scrollUntilVisible(
      find.byKey(const Key('sourceLoginStatus')),
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    final end = DateTime.now().add(const Duration(seconds: 180));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.textContaining('试跑成功').evaluate().isNotEmpty) break;
    }
    expect(find.textContaining('试跑成功'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 6)));
}
