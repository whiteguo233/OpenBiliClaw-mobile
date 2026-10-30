import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Load the actual mobile SPA in a device browser engine. The origin and all
/// resources/API responses come from the supplied real backend, without routes,
/// service stubs, fixture HTML, or injected application state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const casesJson = String.fromEnvironment('OBC_LIVE_QR_CASES');

  testWidgets(
    'real QR destinations load the mobile web recommendations',
    (tester) async {
      final cases = (jsonDecode(casesJson) as List)
          .cast<Map<String, dynamic>>();
      expect(cases, isNotEmpty);
      for (final entry in cases) {
        final label = entry['label'] as String;
        final uri = Uri.parse(entry['url'] as String);
        final errors = <String>[];
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onWebResourceError: (error) {
                if (error.isForMainFrame == true) {
                  errors.add('${error.errorCode}: ${error.description}');
                }
              },
            ),
          );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: WebViewWidget(controller: controller)),
          ),
        );
        await controller.loadRequest(uri);
        var cards = 0;
        var decodedCovers = 0;
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (cards == 0 && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 250));
          try {
            final result = await controller.runJavaScriptReturningResult('''
            JSON.stringify({
              cards: document.querySelectorAll('#view-recommend .card-title').length,
              decodedCovers: [...document.querySelectorAll('.card-cover')]
                .filter(image => image.complete && image.naturalWidth > 0).length
            })
          ''');
            final state = _decodeObject(result);
            cards = (state['cards'] as num?)?.toInt() ?? 0;
            decodedCovers = (state['decodedCovers'] as num?)?.toInt() ?? 0;
          } catch (_) {
            // An evaluation racing navigation may lose the JS context. Retry
            // within the same bounded readiness wait, never hide a final failure.
          }
        }
        expect(errors, isEmpty, reason: '$label: main document load');
        expect(
          cards,
          greaterThan(0),
          reason: '$label: real recommendation API → rendered mobile cards',
        );
        final current = Uri.parse((await controller.currentUrl())!);
        expect(current.host, uri.host);
        expect(current.port, uri.port);
        expect(current.fragment, '/recommend');
        debugPrint(
          'LIVE MOBILE WEB $label: $cards real cards rendered; '
          '$decodedCovers decoded covers',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    skip: casesJson.isEmpty,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Map<String, dynamic> _decodeObject(Object value) {
  var result = value;
  // Android and WKWebView differ in whether the returned JSON string is itself
  // JSON quoted; accept both platform-channel representations.
  for (var i = 0; i < 2 && result is String; i++) {
    result = jsonDecode(result);
  }
  return (result as Map).cast<String, dynamic>();
}
