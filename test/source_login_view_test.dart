import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/custom_sources_api.dart';
import 'package:openbiliclaw_app/views/source_login_view.dart';

void main() {
  testWidgets(
    'verification frame scope requires a click and clears after consent',
    (tester) async {
      const origin = 'https://challenges.cloudflare.com';
      final api = _LoginApi();
      api.snapshot['suggested_login_origins'] = [origin];
      api.snapshot['blocked_navigation_origins'] = <String>[];
      api.snapshot['blocked_frame_origins'] = [origin];
      await tester.pumpWidget(
        MaterialApp(
          home: SourceLoginView(api: api, draftId: 'draft'),
        ),
      );
      await settle(tester);
      expect(api.takeoverOrigins, ['']);
      final button = find.text('允许此登录或验证页面：$origin');
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester);
      expect(api.takeoverOrigins, ['', origin]);
      expect(button, findsNothing);
      expect(api.resumes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary blocked frames are not consent choices', (
    tester,
  ) async {
    final api = _LoginApi();
    api.snapshot['suggested_login_origins'] = <String>[];
    api.snapshot['blocked_frame_origins'] = ['https://ads.example.com'];
    await tester.pumpWidget(
      MaterialApp(
        home: SourceLoginView(api: api, draftId: 'draft'),
      ),
    );
    await settle(tester);
    expect(find.textContaining('允许此登录'), findsNothing);
    expect(api.takeoverOrigins, ['']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'native login deduplicates fields, clears secrets and resumes explicitly',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _LoginApi();
      await tester.pumpWidget(
        MaterialApp(
          home: SourceLoginView(api: api, draftId: 'draft'),
        ),
      );
      await settle(tester);
      expect(api.resumes, 0);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'private-password');
      await tester.ensureVisible(find.text('填入网站'));
      await tester.tap(find.text('填入网站'));
      await settle(tester);
      expect(api.actions.single['value'], 'private-password');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('sourceLoginResume')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sourceLoginResume')));
      await settle(tester);
      expect(api.resumes, 1);
      await tester.scrollUntilVisible(
        find.byKey(const Key('sourceLoginStatus')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.textContaining('试跑成功'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(api.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('leaving during takeover also releases a late session', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final api = _LoginApi()..pendingTakeover = pending;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceLoginView(api: api, draftId: 'draft'),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(api.closes, 1);
    pending.complete(api.snapshot);
    await tester.pump();
    expect(api.closes, 2);
    expect(api.shots, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background screenshot cannot disable or swallow resume', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _LoginApi();
    await tester.pumpWidget(
      MaterialApp(
        home: SourceLoginView(api: api, draftId: 'draft'),
      ),
    );
    await settle(tester);
    final pending = Completer<Uint8List>();
    api.pendingScreenshot = pending;
    await tester.pump(const Duration(seconds: 4));
    final resume = find.byKey(const Key('sourceLoginResume'));
    expect(tester.widget<FilledButton>(resume).onPressed, isNotNull);
    await tester.tap(resume);
    await settle(tester);
    expect(api.resumes, 1);
    pending.completeError(StateError('old screenshot session closed'));
    await tester.pump();
    expect(find.textContaining('试跑成功'), findsOneWidget);
    expect(find.textContaining('画面连接中断'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'expired takeover shows explicit recovery and stops screenshot polling',
    (tester) async {
      final api = _LoginApi()..expired = true;
      await tester.pumpWidget(
        MaterialApp(
          home: SourceLoginView(api: api, draftId: 'draft'),
        ),
      );
      await settle(tester);
      expect(find.textContaining('操作未完成'), findsOneWidget);
      final calls = api.shots;
      await tester.pump(const Duration(seconds: 12));
      expect(api.shots, calls);
      expect(api.resumes, 0);
      expect(find.text('重新打开登录窗口'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _LoginApi extends CustomSourcesApi {
  _LoginApi() : super(ApiClient());
  int resumes = 0, shots = 0;
  bool expired = false;
  Completer<Uint8List>? pendingScreenshot;
  Completer<Map<String, dynamic>>? pendingTakeover;
  final List<Map<String, dynamic>> actions = [];
  final takeoverOrigins = <String>[];
  final Map<String, dynamic> snapshot = {
    'elements': [
      {'tag': 'input', 'type': 'password', 'selector': '#password', 'text': ''},
      {'tag': 'input', 'type': 'password', 'selector': '#password', 'text': ''},
    ],
  };
  int closes = 0;
  @override
  Future<void> closeLogin(String draftId) async {
    closes += 1;
  }

  @override
  Future<Map<String, dynamic>> draft(String draftId) async => {};
  @override
  Future<Map<String, dynamic>> takeover(
    String draftId, {
    String origin = '',
  }) async {
    takeoverOrigins.add(origin);
    if (origin.isNotEmpty) {
      snapshot['suggested_login_origins'] = <String>[];
      snapshot['blocked_navigation_origins'] = [origin];
    }
    return pendingTakeover != null ? await pendingTakeover!.future : snapshot;
  }

  @override
  Future<Uint8List> screenshot(String draftId) async {
    shots++;
    if (pendingScreenshot != null) return pendingScreenshot!.future;
    if (expired) throw ApiException(409, 'Open the login window first');
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=',
    );
  }

  @override
  Future<Map<String, dynamic>> action(
    String draftId,
    Map<String, dynamic> action,
  ) async {
    actions.add(action);
    return snapshot;
  }

  @override
  Future<Map<String, dynamic>> resume(String draftId) async {
    resumes++;
    return {'status': 'ready'};
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 1));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Login operation did not settle');
}
