import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/chat_api.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/models/chat.dart';
import 'package:openbiliclaw_app/providers/chat_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'pending cards open without claiming an inactive discussion context',
    () async {
      for (final state in ['pending', 'discussing', 'question']) {
        var contextRequests = 0;
        final provider = ChatProvider(
          ApiClient(
            directClientFactory: () => MockClient((request) async {
              if (request.url.path.endsWith('/open')) {
                return http.Response(
                  jsonEncode({
                    'turn_id': 'card-a',
                    'status': 'completed',
                    'payload': {
                      'type': state == 'question' ? 'question' : 'card',
                      'kind': state == 'question' ? 'confusion' : 'hypothesis',
                      'state': state,
                      'title': 'A hypothesis',
                    },
                  }),
                  200,
                );
              }
              if (request.url.path.contains('/contexts/')) {
                contextRequests++;
                if (state == 'pending') return http.Response('inactive', 409);
                return http.Response(
                  jsonEncode({
                    'reply_to_turn_id': 'card-a',
                    'source_type': state == 'question' ? 'question' : 'card',
                    'kind': state == 'question' ? 'confusion' : 'hypothesis',
                    'generation': 1,
                    'title': 'A hypothesis',
                  }),
                  200,
                );
              }
              return http.Response('{"items":[],"total":0}', 200);
            }),
          ),
        );
        try {
          expect(
            await provider.openPendingConfirmation(
              const PendingConfirmation(
                kind: 'hypothesis',
                ref: 'ref-a',
                title: 'A hypothesis',
              ),
            ),
            true,
          );
          expect(provider.error, isEmpty);
          expect(provider.turns.single.turnId, 'card-a');
          expect(contextRequests, state == 'pending' ? 0 : 1);
          if (state == 'pending') {
            expect(provider.dialogueContext, isNull);
          } else {
            expect(provider.dialogueContext?.replyToTurnId, 'card-a');
          }
        } finally {
          provider.dispose();
        }
      }
    },
  );

  test(
    'opening a hypothesis waits through explicit dialogue busy admission',
    () async {
      var calls = 0;
      final api = ChatApi(
        ApiClient(
          directClientFactory: () => MockClient((request) async {
            expect(
              request.url.path,
              '/api/chat/pending-confirmations/ref-a/open',
            );
            expect(jsonDecode(request.body), {'session': 'popup'});
            calls++;
            if (calls <= 2) {
              return http.Response(
                '{"detail":{"code":"dialogue_busy","message":"busy"}}',
                503,
              );
            }
            return http.Response(
              jsonEncode({
                'turn_id': 'card-a',
                'status': 'completed',
                'payload': {
                  'type': 'card',
                  'kind': 'hypothesis',
                  'state': 'pending',
                },
              }),
              200,
            );
          }),
        ),
      );
      final card = await api.openPendingConfirmation('ref-a');
      expect(card.turnId, 'card-a');
      expect(calls, 3);
    },
  );

  test(
    'opening does not retry other failures or uncertain transport errors',
    () async {
      for (final code in [401, 404, 409, 503]) {
        var calls = 0;
        final api = ChatApi(
          ApiClient(
            directClientFactory: () => MockClient((_) async {
              calls++;
              return http.Response(
                '{"detail":{"code":"different_failure"}}',
                code,
              );
            }),
          ),
        );
        await expectLater(
          api.openPendingConfirmation('ref-a'),
          throwsA(isA<ApiException>()),
        );
        expect(calls, 1);
      }
    },
  );
  test(
    'expired busy wait is finite and cancellation prevents a retry',
    () async {
      var calls = 0;
      final api = ChatApi(
        ApiClient(
          directClientFactory: () => MockClient((_) async {
            calls++;
            return http.Response('{"detail":{"code":"dialogue_busy"}}', 503);
          }),
        ),
      );
      await expectLater(
        api.openPendingConfirmation('ref-a', busyRetryWindow: Duration.zero),
        throwsA(
          isA<ApiException>().having(
            (e) => e.body,
            'body',
            contains('dialogue_busy_timeout'),
          ),
        ),
      );
      expect(calls, 1);
      var cancelled = false;
      await expectLater(
        api.openPendingConfirmation(
          'ref-a',
          isCancelled: () => cancelled,
          onWaiting: () => cancelled = true,
        ),
        throwsStateError,
      );
      expect(calls, 2);
    },
  );

  test('uncertain transport failure is never replayed', () async {
    var calls = 0;
    final api = ChatApi(
      ApiClient(
        directClientFactory: () => MockClient((_) async {
          calls++;
          throw http.ClientException('interrupted');
        }),
      ),
    );
    await expectLater(
      api.openPendingConfirmation('ref-a'),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 1);
  });
}
