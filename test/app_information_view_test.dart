import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/app_information_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final document in AppDocument.values) {
    testWidgets('${document.title} opens offline and returns to its entry', (
      tester,
    ) async {
      // Read the actual bundled policy, without a backend or provider tree.
      await tester.runAsync(() => rootBundle.loadString(document.asset));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AppInformationLinks()),
        ),
      );
      await tester.tap(find.text(document.title));
      await tester.runAsync(() => tester.pumpAndSettle());
      expect(find.byType(AppInformationView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('OpenBiliClaw'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.runAsync(() => tester.pumpAndSettle());
      expect(find.byType(AppInformationLinks), findsOneWidget);
    });
  }

  for (final dark in [false, true]) {
    for (final size in [
      const Size(375, 812),
      const Size(812, 375),
      const Size(1024, 1366),
    ]) {
      testWidgets('policy remains readable at large text: $dark / $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(
          () => rootBundle.loadString(AppDocument.privacy.asset),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(3.2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const AppInformationView(document: AppDocument.privacy),
          ),
        );
        await tester.runAsync(() => tester.pumpAndSettle());
        expect(tester.takeException(), isNull);
        final scrollable = find.byType(Scrollable).first;
        final state = tester.state<ScrollableState>(scrollable);
        expect(state.position.maxScrollExtent, greaterThan(0));
        // Markdown lays out its sections lazily; an initial maxScrollExtent
        // is only an estimate. Exercise scrolling to the actual last heading.
        await tester.scrollUntilVisible(
          find.textContaining('政策更新与联系'),
          600,
          scrollable: scrollable,
          maxScrolls: 100,
        );
        await tester.runAsync(() => tester.pumpAndSettle());
        expect(tester.takeException(), isNull);
        expect(find.textContaining('政策更新与联系'), findsWidgets);
      });
    }
  }
}
