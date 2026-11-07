import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/custom_sources_api.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';
import 'package:openbiliclaw_app/providers/profile_provider.dart';
import 'package:openbiliclaw_app/providers/source_attention_provider.dart';
import 'package:openbiliclaw_app/widgets/message_inbox.dart';

const warning = <String, dynamic>{
  'id': 'source:custom/a',
  'source_id': 'custom/a',
  'draft_id': '',
  'name': 'Rust 博客',
  'action': 'source_login',
  'code': 'verification_required',
  'action_label': '处理验证',
  'message': '网站要求人工安全验证。请完成验证并成功试采后继续。',
};

class QuietProfile extends ProfileProvider {
  QuietProfile(super.client);
  @override
  Future<void> loadNotifications() async {}
}

class QuietChat extends ChatProvider {
  QuietChat(super.client);
  @override
  Future<void> loadPendingConfirmations({bool notify = true}) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('ordinary collection failures open source settings from inbox', (
    tester,
  ) async {
    final item = {
      ...warning,
      'action': 'source_settings',
      'action_label': '查看来源',
      'code': 'source_timeout',
    };
    final paths = <String>[];
    final client = ApiClient(
      directClientFactory: () => MockClient((r) async {
        expect(r.method, 'GET');
        paths.add(r.url.path);
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('/attention')
                ? {
                    'items': [item],
                  }
                : {
                    'items': [
                      {
                        'source_id': 'custom/a',
                        'name': 'Rust 博客',
                        'enabled': true,
                        'workflows': [],
                        'health': {},
                      },
                    ],
                    'executors': [],
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final attention = SourceAttentionProvider(CustomSourcesApi(client));
    final profile = QuietProfile(client), chat = QuietChat(client);
    await attention.refresh();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileProvider>.value(value: profile),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider.value(value: attention),
        ],
        child: const MaterialApp(home: Scaffold(body: MessageInbox())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看来源'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('source-custom/a')), findsOneWidget);
    expect(paths.where((p) => p.endsWith('/login')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    attention.dispose();
    profile.dispose();
    chat.dispose();
  });

  testWidgets(
    'starting attention during home construction never notifies during build',
    (tester) async {
      final provider = SourceAttentionProvider(
        CustomSourcesApi(
          ApiClient(
            directClientFactory: () =>
                MockClient((_) async => http.Response('{"items":[]}', 200)),
          ),
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                context.watch<SourceAttentionProvider>();
                context.read<SourceAttentionProvider>().start();
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );

  test(
    'durable attention deduplicates, survives failed polls and clears on recovery',
    () async {
      var fail = false;
      var rows = [
        warning,
        warning,
        {'id': 'invalid', 'action': 'unknown'},
      ];
      final client = ApiClient(
        directClientFactory: () => MockClient((r) async {
          expect(r.url.path, '/api/custom-sources/attention');
          return fail
              ? http.Response('offline', 503)
              : http.Response(
                  jsonEncode({'items': rows}),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
        }),
      );
      expect(await CustomSourcesApi(client).attention(), rows);
      final provider = SourceAttentionProvider(CustomSourcesApi(client));
      addTearDown(provider.dispose);
      await provider.refresh();
      expect(provider.items, [warning]);
      fail = true;
      await provider.refresh();
      expect(provider.items, [warning]);
      fail = false;
      rows = [];
      await provider.refresh();
      expect(provider.items, isEmpty);
    },
  );

  testWidgets('polling stops in background and resumes immediately', (
    tester,
  ) async {
    var calls = 0;
    final provider = SourceAttentionProvider(
      CustomSourcesApi(
        ApiClient(
          directClientFactory: () => MockClient((_) async {
            calls++;
            return http.Response('{"items":[]}', 200);
          }),
        ),
      ),
    );
    provider.start();
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 31));
    expect(calls, 2);
    provider.stop();
    await tester.pump(const Duration(minutes: 2));
    expect(calls, 2);
    provider.start();
    await tester.pump();
    expect(calls, 3);
    provider.dispose();
  });

  for (final draft in [false, true]) {
    testWidgets(
      'inbox routes ${draft ? "draft" : "source"} warning to its own recovery and refreshes',
      (tester) async {
        final item = {
          ...warning,
          if (draft) ...{
            'id': 'draft:d/a',
            'source_id': '',
            'draft_id': 'd/a',
            'action': 'draft_login',
          },
        };
        var recovered = false;
        final opened = <http.Request>[];
        final client = ApiClient(
          directClientFactory: () => MockClient((r) async {
            if (r.url.path == '/api/custom-sources/attention') {
              return http.Response(
                jsonEncode({
                  'items': recovered ? [] : [item],
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            opened.add(r);
            recovered = true;
            return http.Response('{"draft_id":"d/a","status":"ready"}', 200);
          }),
        );
        final attention = SourceAttentionProvider(CustomSourcesApi(client));
        final profile = QuietProfile(client);
        final chat = QuietChat(client);
        await attention.refresh();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ProfileProvider>.value(value: profile),
              ChangeNotifierProvider<ChatProvider>.value(value: chat),
              ChangeNotifierProvider.value(value: attention),
            ],
            child: const MaterialApp(home: Scaffold(body: MessageInbox())),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Rust 博客'), findsOneWidget);
        expect(find.text(warning['message'] as String), findsOneWidget);
        await tester.tap(find.text('处理验证'));
        await tester.pumpAndSettle();
        expect(opened, hasLength(1));
        expect(opened.single.method, draft ? 'GET' : 'POST');
        expect(
          opened.single.url.path,
          draft
              ? '/api/custom-sources/drafts/d%2Fa'
              : '/api/custom-sources/custom%2Fa/login',
        );
        expect(find.text('Rust 博客'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        attention.dispose();
        profile.dispose();
        chat.dispose();
      },
    );
  }
}
