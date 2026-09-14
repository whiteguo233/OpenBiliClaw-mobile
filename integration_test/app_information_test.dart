import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/app_information_view.dart';

/// Visual QA of the real bundled documents without personal backend data.
/// These screenshots are UI verification artifacts, not App Store marketing.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled privacy and support render on device', (tester) async {
    for (final dark in [false, true]) {
      for (final document in AppDocument.values) {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('${document.name}-$dark'),
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: AppInformationView(document: document),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.textContaining('OpenBiliClaw'), findsWidgets);
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(
          '${document.name}-${dark ? 'dark' : 'light'}',
        );
      }
    }
  });
}
