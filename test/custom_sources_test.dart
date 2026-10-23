import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/chat_api.dart';
import 'package:openbiliclaw_app/api/custom_sources_api.dart';
import 'package:openbiliclaw_app/models/recommendation.dart';
import 'package:openbiliclaw_app/models/saved_item.dart';
import 'package:openbiliclaw_app/models/delight.dart';
import 'package:openbiliclaw_app/models/content_history.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/widgets/chat_approvals.dart';
import 'package:openbiliclaw_app/views/custom_sources_view.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'backend-owned takeover URLs support base paths and reject other origins',
    () {
      final api = CustomSourcesApi(
        ApiClient(
          scheme: 'https',
          host: 'private.test',
          port: 9443,
          basePath: 'obc',
        ),
      );
      expect(
        api.loginDraftId('/obc/web/source-login.html?draft_id=abc'),
        'abc',
      );
      expect(
        api.loginDraftId(
          'https://private.test:9443/obc/m/desktop/source-login.html?draft_id=abc',
        ),
        'abc',
      );
      for (final href in [
        'https://evil.test/web/source-login.html?draft_id=x',
        'http://private.test:9443/web/source-login.html?draft_id=x',
        '//evil.test/web/source-login.html?draft_id=x',
        'javascript:alert(1)',
        '/web/source-login.html',
        'https://user@private.test:9443/web/source-login.html?draft_id=x',
      ]) {
        expect(api.loginDraftId(href), isNull);
      }
    },
  );
  test(
    'source PATCH preserves backend prefix, cookie and exact fields',
    () async {
      SharedPreferences.setMockInitialValues({
        'session_token': 'test-session',
        'api_host': 'private.test',
        'api_port': 9443,
        'api_base_path': 'obc',
        'api_scheme': 'https',
      });
      late http.Request seen;
      final client = ApiClient(
        directClientFactory: () => MockClient((r) async {
          seen = r;
          return http.Response('{}', 200);
        }),
      );
      await client.loadSettings();
      await CustomSourcesApi(
        client,
      ).update('custom_a', {'target_share': 2, 'enabled': false});
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/obc/api/custom-sources/custom_a');
      expect(seen.headers['cookie'], contains('test-session'));
      expect(jsonDecode(seen.body), {'target_share': 2, 'enabled': false});
    },
  );
  test(
    'malformed source list is a failure rather than an empty success',
    () async {
      final api = CustomSourcesApi(
        ApiClient(
          directClientFactory: () =>
              MockClient((_) async => http.Response('{"items":null}', 200)),
        ),
      );
      await expectLater(api.list(), throwsFormatException);
    },
  );
  test('custom attribution survives all native content models', () {
    final json = {
      'source_platform': 'web',
      'source_id': 'custom_a',
      'source_name': 'NGA &amp; RSS',
      'title': 'title',
      'content_id': 'abc',
      'bvid': 'abc',
    };
    final rec = Recommendation.fromJson(json);
    expect(rec.sourceLabel, 'NGA & RSS');
    expect(SavedItem.fromRecommendation(rec).sourceId, 'custom_a');
    expect(SavedItem.fromJson(json).sourceLabel, 'NGA & RSS');
    expect(Delight.fromJson(json).toRecommendation().sourceLabel, 'NGA & RSS');
    expect(ContentHistoryItem.fromJson(json).sourceLabel, 'NGA & RSS');
  });
  test('agent streaming falls back only before execution begins', () async {
    final client = _StreamClient();
    final events = await ChatApi(
      client,
    ).streamChat(turnId: 'a', message: 'hello').toList();
    expect(client.paths, ['/chat/agent/stream', '/chat/stream']);
    expect(events.single.type, 'done');
    client.paths.clear();
    client.partial = true;
    await expectLater(
      ChatApi(client).streamChat(turnId: 'b', message: 'hello').toList(),
      throwsA(isA<ApiException>()),
    );
    expect(client.paths, ['/chat/agent/stream']);
  });
  testWidgets(
    'native approval disables resubmission and waits for executed status',
    (tester) async {
      var state = 'pending', posts = 0;
      final client = ApiClient(
        directClientFactory: () => MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            state = 'executing';
            return http.Response(
              jsonEncode({
                'approval': {'approval_id': 'a', 'status': state},
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'approval_id': 'a',
                  'status': state,
                  'summary': 'Add NGA',
                  'impact': 'Every 5 minutes',
                },
              ],
            }),
            200,
          );
        }),
      );
      final chat = ChatProvider(client);
      await chat.loadApprovals();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: chat,
          child: const MaterialApp(home: Scaffold(body: ChatApprovalsButton())),
        ),
      );
      await tester.tap(find.byKey(const Key('chatApprovals')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('批准执行'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.text('执行中'), findsOneWidget);
      expect(find.text('批准执行'), findsNothing);
      state = 'executed';
      await chat.loadApprovals();
      await tester.pumpAndSettle();
      expect(find.text('已完成'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      chat.dispose();
    },
  );
  testWidgets(
    'source settings preserve last good list on network error and show health',
    (tester) async {
      var broken = false;
      final api = CustomSourcesApi(
        ApiClient(
          directClientFactory: () => MockClient((r) async {
            if (broken) return http.Response('down', 503);
            return http.Response(
              jsonEncode({
                'executors': [],
                'items': [
                  {
                    'source_id': 'a',
                    'name': 'NGA',
                    'enabled': true,
                    'target_share': 1,
                    'interval_minutes': 5,
                    'health': {'status': 'ok', 'last_success_at': 1792778648},
                    'workflows': [],
                  },
                ],
              }),
              200,
            );
          }),
        ),
      );
      await tester.pumpWidget(MaterialApp(home: CustomSourcesView(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('NGA'), findsOneWidget);
      expect(find.text('正常'), findsOneWidget);
      expect(find.textContaining('最近成功'), findsOneWidget);
      broken = true;
      await tester.tap(find.byTooltip('刷新来源'));
      await tester.pumpAndSettle();
      expect(find.text('NGA'), findsOneWidget);
      expect(find.textContaining('来源加载失败'), findsOneWidget);
    },
  );
}

class _StreamClient extends ApiClient {
  final List<String> paths = [];
  bool partial = false;
  @override
  Stream<String> streamPostLines(
    String path, {
    Map<String, dynamic>? body,
  }) async* {
    paths.add(path);
    if (path == '/chat/agent/stream') {
      if (partial) {
        yield 'event: tool_call';
        yield 'data: {"tool_name":"source"}';
      }
      throw ApiException(503, 'unavailable');
    }
    yield 'event: done';
    yield 'data: {"reply":"ok"}';
  }
}
