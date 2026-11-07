import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openbiliclaw_app/api/client.dart';

import 'native_custom_sources_live_test.dart' as sources;

/// Real native HTTP cancellation followed by the complete real source flow.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native HTTP timeout cancels before client cleanup', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = {
      for (final phase in ['headers', 'body']) phase: Completer<void>(),
    };
    final release = {
      for (final phase in ['headers', 'body']) phase: Completer<void>(),
    };
    server.listen((request) async {
      final phase = request.uri.pathSegments.last;
      try {
        request.response.headers.contentType = ContentType.json;
        if (phase == 'ok') {
          request.response.write('{"ok":true}');
        } else {
          seen[phase]!.complete();
          if (phase == 'body') {
            request.response.write('{"ok":');
            await request.response.flush();
          }
          await release[phase]!.future;
          request.response.write(phase == 'body' ? 'true}' : '{"ok":true}');
        }
        await request.response.close();
      } on HttpException {
        // A timed-out real NSURLSession request may close its socket first.
      } on SocketException {
        // The delayed fixture response is deliberately no longer consumed.
      }
    });
    try {
      final api = ApiClient(host: '127.0.0.1', port: server.port);
      expect((await api.get('/ok', timeout: 30))['ok'], true);
      for (final phase in ['headers', 'body']) {
        final result = expectLater(
          api.get('/$phase', timeout: 5),
          throwsA(isA<TimeoutException>()),
        );
        await seen[phase]!.future.timeout(const Duration(seconds: 15));
        await result;
        release[phase]!.complete();
        expect((await api.get('/ok', timeout: 30))['ok'], true);
        debugPrint(
          'NATIVE_HTTP timeout=$phase real_request=true recovered=true',
        );
      }
      expect(tester.takeException(), isNull);
    } finally {
      for (final gate in release.values) {
        if (!gate.isCompleted) gate.complete();
      }
      await server.close(force: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
  sources.main();
}
