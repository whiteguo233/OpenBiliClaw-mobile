import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/providers/saved_provider.dart';
import 'package:openbiliclaw_app/theme/app_theme.dart';
import 'package:openbiliclaw_app/views/recommend_view.dart';
import 'package:provider/provider.dart';

http.Response _response(Map<String, dynamic> body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  testWidgets('first completed batch frame updates headline and every tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final batch = Completer<http.Response>();
    final slowRuntime = Completer<http.Response>();
    var availabilityReads = 0;
    final client = ApiClient(
      host: '127.0.0.1',
      directClientFactory: () => MockClient((r) async {
        if (r.url.path.endsWith('/recommendations')) {
          return _response({'items': []});
        }
        if (r.url.path.endsWith('/reshuffle')) return batch.future;
        if (r.url.path.endsWith('/platform-availability')) {
          availabilityReads++;
          return _response({
            'total_available': 50,
            'by_platform': {'bilibili': 30, 'twitter': 20},
            'pool_status_version': 10,
          });
        }
        if (r.url.path.endsWith('/runtime-status')) return slowRuntime.future;
        return _response({'items': []});
      }),
    );
    final p = RecommendProvider(client);
    final saved = SavedProvider(client);
    await p.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: client),
          ChangeNotifierProvider<RecommendProvider>.value(value: p),
          ChangeNotifierProvider<SavedProvider>.value(value: saved),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: RecommendView()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('50 条'), findsOneWidget);
    expect(find.text('全部 50'), findsOneWidget);
    expect(find.text('B 站 30'), findsOneWidget);
    expect(find.text('X (Twitter) 20'), findsOneWidget);
    await tester.tap(find.text('换一批'));
    await tester.pump();
    batch.complete(
      _response({
        'items': [
          {
            'id': 1,
            'bvid': 'twitter:new',
            'title': 'New batch card',
            'source_platform': 'twitter',
            'content_type': 'tweet',
            'body_text': 'New content',
          },
        ],
        'pool_status': {
          'pool_available_count': 48,
          'platform_available_counts': {'bilibili': 29, 'twitter': 19},
          'pool_status_version': 20,
        },
      }),
    );
    await tester.pump();
    expect(p.reshuffling, isFalse);
    expect(find.text('New batch card'), findsWidgets);
    expect(find.text('48 条'), findsOneWidget);
    expect(find.text('全部 48'), findsOneWidget);
    expect(find.text('B 站 29'), findsOneWidget);
    expect(find.text('X (Twitter) 19'), findsOneWidget);
    expect(find.text('50 条'), findsNothing);
    expect(find.text('全部 50'), findsNothing);
    expect(
      availabilityReads,
      1,
      reason: 'batch receipt needs no follow-up GET',
    );
    slowRuntime.complete(_response({'pool_available_count': 999}));
    await tester.pump();
    expect(find.text('48 条'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    p.dispose();
    saved.dispose();
  });
}
