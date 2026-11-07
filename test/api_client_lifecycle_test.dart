import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openbiliclaw_app/api/client.dart';

void main() {
  test('timeout aborts a native request before closing its client', () async {
    final transport = _PendingNativeClient();
    final api = ApiClient(directClientFactory: () => transport);
    addTearDown(transport.finish);

    await expectLater(
      api.get('/chat/turns', timeout: 0),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);

    expect(transport.abortCount, 1);
    expect(transport.closeWhileRunning, 0);
    expect(transport.closed, isTrue);
  });

  final requests = <String, Future<Object?> Function(ApiClient)>{
    'GET': (api) => api.get('/chat/turns'),
    'POST': (api) => api.post('/chat/turns', body: {'message': '新增来源'}),
    'PATCH': (api) =>
        api.patch('/custom-sources/test', body: {'target_share': 2}),
    'PUT': (api) => api.put('/settings', body: {'enabled': true}),
    'DELETE': (api) => api.delete('/custom-sources/test'),
    'bytes': (api) => api.getBytes(Uri.parse('http://localhost/screenshot')),
  };
  for (final entry in requests.entries) {
    testWidgets(
      '${entry.key} returns timeout before native cancellation finishes',
      (tester) async {
        final transport = _PendingNativeClient(autoCancel: false);
        final api = ApiClient(directClientFactory: () => transport);
        addTearDown(transport.finish);
        final result = expectLater(
          entry.value(api),
          throwsA(isA<TimeoutException>()),
        );

        await tester.pump(const Duration(seconds: 61));
        await result;
        expect(transport.abortCount, 1);
        expect(transport.closed, isFalse);
        expect(transport.closeWhileRunning, 0);
        transport.cancel();
        await tester.pump();
        expect(transport.closed, isTrue);
        expect(transport.closeWhileRunning, 0);
      },
    );
  }

  test('response body timeout cancels the active native task', () async {
    final transport = _PendingNativeClient(headersImmediately: true);
    final api = ApiClient(directClientFactory: () => transport);
    addTearDown(transport.finish);

    await expectLater(
      api.get('/chat/turns', timeout: 0),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.abortCount, 1);
    expect(transport.closeWhileRunning, 0);
    expect(transport.closed, isTrue);
  });

  test(
    'successful response keeps its payload and closes only after completion',
    () async {
      final transport = _PendingNativeClient();
      final api = ApiClient(directClientFactory: () => transport);
      final result = api.post('/chat/turns', body: {'message': '新增来源'});
      expect(transport.request?.method, 'POST');
      expect((transport.request as http.Request).body, contains('新增来源'));
      expect(transport.request?.headers['X-OBC-Auth'], '1');
      expect(transport.closed, isFalse);
      transport.finish();

      expect(await result, isEmpty);
      expect(transport.closed, isTrue);
      expect(transport.abortCount, 0);
      expect(transport.closeWhileRunning, 0);
    },
  );

  test(
    'late response after timeout is drained and closed without applying cookies',
    () async {
      final transport = _PendingNativeClient(autoCancel: false);
      final api = ApiClient(directClientFactory: () => transport);
      await expectLater(
        api.get('/auth/status', timeout: 0),
        throwsA(isA<TimeoutException>()),
      );
      transport.finish(headers: {'set-cookie': 'obc_session=late; Path=/'});
      await Future<void>.delayed(Duration.zero);

      expect(transport.closed, isTrue);
      expect(api.sessionToken, isEmpty);
      expect(transport.closeWhileRunning, 0);
    },
  );
}

/// Models NSURLSession's restriction: close cannot cancel an active request.
class _PendingNativeClient extends http.BaseClient {
  _PendingNativeClient({
    this.autoCancel = true,
    this.headersImmediately = false,
  });

  final bool autoCancel;
  final bool headersImmediately;
  final _response = Completer<http.StreamedResponse>();
  final _body = StreamController<List<int>>();
  http.BaseRequest? request;
  var running = false;
  var closed = false;
  var closeWhileRunning = 0;
  var abortCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    this.request = request;
    running = true;
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.then((_) {
          abortCount += 1;
          if (autoCancel) cancel();
        }),
      );
    }
    if (headersImmediately) _sendHeaders();
    return _response.future;
  }

  void _sendHeaders({Map<String, String> headers = const {}}) {
    if (!_response.isCompleted) {
      _response.complete(
        http.StreamedResponse(_body.stream, 200, headers: headers),
      );
    }
  }

  void cancel() {
    if (!running) return;
    running = false;
    final error = http.RequestAbortedException(request?.url);
    if (_response.isCompleted) {
      _body.addError(error);
    } else {
      _response.completeError(error);
    }
    unawaited(_body.close());
  }

  void finish({Map<String, String> headers = const {}}) {
    if (!running) return;
    _sendHeaders(headers: headers);
    running = false;
    _body.add([123, 125]);
    unawaited(_body.close());
  }

  @override
  void close() {
    if (running) {
      closeWhileRunning += 1;
      throw StateError('cannot close with running requests');
    }
    closed = true;
  }
}
