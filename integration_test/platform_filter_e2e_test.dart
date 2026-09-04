import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:openbiliclaw_app/main.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/views/recommend_view.dart';

/// Real-environment E2E for the platform filter (「全部 / 平台」).
///
/// Launches the actual app against the REAL local OpenBiliClaw backend
/// (127.0.0.1:8420) and asserts against the live recommendation pool:
/// - recommendations load over a real request;
/// - the choice UI follows the single-source rule: when the live pool holds
///   only one source, no「全部 / 平台」filter row is rendered at all
///   (the user asked for exactly this: 一个来源直接刷).
///
/// Requires the OpenBiliClaw backend to be running.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真实后端：平台过滤随来源数显示，单一来源不显示选择', (tester) async {
    await tester.pumpWidget(const OpenBiliClawApp());
    await tester.pump(const Duration(milliseconds: 500));
    await _pumpUntil(tester, () async {
      if (tester.widgetList(find.byType(RecommendView)).isEmpty) return false;
      final ctx = tester.element(find.byType(RecommendView));
      final rp = ctx.read<RecommendProvider>();
      return !rp.loading && rp.online;
    }, timeout: const Duration(seconds: 20));

    final ctx = tester.element(find.byType(RecommendView));
    final rp = ctx.read<RecommendProvider>();
    expect(rp.online, isTrue, reason: '应连上真实后端');
    expect(rp.recommendations, isNotEmpty, reason: '真实推荐池应有内容');

    final platforms = rp.availablePlatforms;
    debugPrint('E2E: real pool sources = $platforms '
        '(count=${rp.recommendations.length})');

    if (platforms.length <= 1) {
      // 单一来源：完全不出过滤条。
      expect(rp.showPlatformChoice, isFalse, reason: '单一来源不应显示平台选择');
      expect(
        find.byType(ChoiceChip),
        findsNothing,
        reason: '单一来源时首页不应渲染任何平台过滤 chip',
      );
      debugPrint('E2E phase: single-source pool → no filter UI (as designed)');
    } else {
      // 多来源：显示「全部」+ 各平台 chips，且切换真实生效。
      expect(rp.showPlatformChoice, isTrue);
      expect(find.text('全部'), findsOneWidget);
      for (final slug in platforms) {
        expect(
          find.text(RecommendProvider.platformLabel(slug)),
          findsWidgets,
          reason: '首页应渲染 $slug 的过滤 chip',
        );
      }
      final first = platforms.first;
      rp.setPlatformFilter(first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        rp.visibleRecommendations.every((r) => r.sourcePlatform == first),
        isTrue,
        reason: '选择 $first 后应只显示该平台内容',
      );
      rp.setPlatformFilter('');
      await tester.pump(const Duration(milliseconds: 300));
      expect(rp.visibleRecommendations.length, rp.recommendations.length);
      debugPrint('E2E phase: multi-source pool → filter switch verified');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('等待条件超时（$timeout）');
}
