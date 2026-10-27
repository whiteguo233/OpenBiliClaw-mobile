import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openbiliclaw_app/main.dart' as app;
import 'package:openbiliclaw_app/views/backend_scan_view.dart';
import 'package:openbiliclaw_app/views/settings_view.dart';

/// Opens the production app and its real camera route on a simulator/device.
/// This verifies navigation and screenshots, not optical QR recognition.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('backend URL exposes inline QR scan and paste icons', (
    tester,
  ) async {
    app.main();
    await _waitFor(tester, find.byTooltip('连接设置'));
    await _screenshot(tester, binding, 'qr-home-entry');

    await tester.tap(find.byTooltip('连接设置'));
    await _waitFor(tester, find.byTooltip('扫码连接'));
    expect(find.byType(SettingsView), findsOneWidget);
    expect(find.byTooltip('粘贴连接链接'), findsOneWidget);
    expect(find.byTooltip('扫码连接').hitTestable(), findsOneWidget);
    await _screenshot(tester, binding, 'qr-settings-simulator');

    await tester.tap(find.byTooltip('粘贴连接链接'));
    await _waitFor(tester, find.text('粘贴连接链接'));
    await tester.tap(find.text('取消'));
    await _waitFor(tester, find.byTooltip('扫码连接'));

    await tester.tap(find.byTooltip('扫码连接'));
    await _waitFor(tester, find.text('扫码连接后端'));
    expect(find.byType(BackendScanView), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await _screenshot(tester, binding, 'qr-camera-simulator');

    await tester.pageBack();
    await _waitFor(tester, find.byTooltip('扫码连接'));
    expect(find.byType(BackendScanView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _screenshot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  // Let the native compositor present the Flutter frame before iOS capture.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 800)),
  );
  await binding.takeScreenshot(name);
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (finder.hitTestable().evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(milliseconds: 400));
}
