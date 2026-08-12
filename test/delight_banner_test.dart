import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/delight.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/widgets/delight_banner.dart';

void main() {
  testWidgets('delight header does not overflow at accessibility text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 812),
            textScaler: TextScaler.linear(3.2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: DelightBanner(
                delight: Delight(
                  bvid: 'wb:123',
                  title: '这是一条用于辅助功能字号回归验收的超长惊喜推荐标题',
                  reason: '推荐原因在大字模式下仍应当可读，且不会破坏整体布局。',
                  hook: '可以继续深入了解',
                  sourcePlatform: 'weibo',
                ),
                currentIndex: 14,
                totalCount: 20,
                onPrev: () {},
                onNext: () {},
                onView: () {},
                onLike: () {},
                onDislike: () {},
                onDismiss: () {},
                onWatchLater: () {},
                onFavorite: () {},
                onChat: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('15/20'), findsOneWidget);
    expect(find.text('惊喜推荐'), findsOneWidget);
  });
}
