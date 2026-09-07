import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/providers/recommend_provider.dart';
import 'package:openbiliclaw_app/widgets/recommend_auto_load.dart';

Map<String, dynamic> item(String bvid) => {
  'id': bvid.hashCode.abs(),
  'bvid': bvid,
  'title': bvid,
  'source_platform': 'bilibili',
};
http.Response response(Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
Map<String, dynamic> inventory(int count, int version) => {
  'pool_available_count': count,
  'platform_available_counts': {'bilibili': count},
  'pool_status_version': version,
};

RecommendProvider provider(
  Future<http.Response> Function(http.Request) handler,
) => RecommendProvider(
  ApiClient(host: '127.0.0.1', directClientFactory: () => MockClient(handler)),
);

void main() {
  test(
    'reshuffle updates both inventories and ignores late old side channels',
    () async {
      final oldAvailability = Completer<http.Response>();
      final oldRuntime = Completer<http.Response>();
      final p = provider((r) async {
        final path = r.url.path;
        if (path.endsWith('/recommendations')) {
          return response({
            'items': [item('old')],
          });
        }
        if (path.endsWith('/reshuffle')) {
          return response({
            'items': [item('fresh')],
            'pool_status': inventory(7, 20),
          });
        }
        if (path.endsWith('/platform-availability')) {
          return oldAvailability.future;
        }
        if (path.endsWith('/runtime-status')) return oldRuntime.future;
        return response({'items': []});
      });
      await p.load();
      await p.reshuffle();
      expect(p.runtimeStatus.poolAvailableCount, 7);
      expect(p.platformAvailabilityBySource['bilibili'], 7);
      expect(p.recommendations.single.bvid, 'fresh');
      oldAvailability.complete(
        response({
          'total_available': 99,
          'by_platform': {'bilibili': 99},
          'pool_status_version': 10,
        }),
      );
      oldRuntime.complete(response({'pool_available_count': 99}));
      await Future<void>.delayed(Duration.zero);
      expect(p.runtimeStatus.poolAvailableCount, 7);
      expect(p.platformAvailability.totalAvailable, 7);
      p.dispose();
    },
  );

  test(
    'zero cached inventory does not block manual append or refresh',
    () async {
      var appendCalls = 0;
      var reshuffleCalls = 0;
      final p = provider((r) async {
        if (r.url.path.endsWith('/recommendations')) {
          return response({
            'items': [item('old')],
          });
        }
        if (r.url.path.endsWith('/append')) {
          appendCalls++;
          return response({
            'items': [],
            'has_more': false,
            'pool_status': inventory(0, 1),
          });
        }
        if (r.url.path.endsWith('/reshuffle')) {
          reshuffleCalls++;
          return response({
            'items': [item('new')],
            'pool_status': inventory(3, 2),
          });
        }
        return response({'items': []});
      });
      await p.load();
      await p.append();
      expect(p.autoLoadExhausted, isTrue);
      await p.append();
      expect(appendCalls, 2);
      await p.refresh();
      expect(reshuffleCalls, 1);
      expect(p.recommendations.single.bvid, 'new');
      p.dispose();
    },
  );

  test(
    'failed reshuffle releases busy state without exhausting the feed',
    () async {
      final p = provider((r) async {
        if (r.url.path.endsWith('/recommendations')) {
          return response({
            'items': [item('old')],
          });
        }
        if (r.url.path.endsWith('/reshuffle')) {
          throw TimeoutException('network stalled');
        }
        return response({'items': []});
      });
      await p.load();
      await p.reshuffle();
      expect(p.reshuffling, isFalse);
      expect(p.autoLoadExhausted, isFalse);
      expect(p.recommendations.single.bvid, 'old');
      expect(p.error, isNotEmpty);
      p.dispose();
    },
  );

  for (final action in ['reshuffle', 'append', 'refresh']) {
    test(
      '$action notifies cards and all inventory counts atomically',
      () async {
        final p = provider((r) async {
          if (r.url.path.endsWith('/recommendations')) {
            return response({
              'items': [item('old')],
            });
          }
          if (r.url.path.endsWith('/reshuffle') ||
              r.url.path.endsWith('/append')) {
            return response({
              'items': [item('fresh')],
              'pool_status': inventory(7, 20),
            });
          }
          if (r.url.path.endsWith('/platform-availability')) {
            return response({
              'total_available': 9,
              'by_platform': {'bilibili': 9},
              'pool_status_version': 10,
            });
          }
          return response({'items': []});
        });
        await p.load();
        await Future<void>.delayed(Duration.zero);
        final inconsistent = <String>[];
        p.addListener(() {
          final fresh = p.recommendations.any((r) => r.bvid == 'fresh');
          if ((p.poolAvailableCount == 7) != fresh) {
            inconsistent.add('cards=$fresh count=${p.poolAvailableCount}');
          }
        });
        if (action == 'reshuffle') await p.reshuffle();
        if (action == 'append') await p.append();
        if (action == 'refresh') await p.refresh();
        expect(inconsistent, isEmpty);
        expect(p.poolAvailableCount, 7);
        expect(p.inventoryStale, isFalse);
        p.dispose();
      },
    );
  }

  test(
    'legacy response reads fresh inventory before publishing new cards',
    () async {
      final oldRead = Completer<http.Response>();
      final freshRead = Completer<http.Response>();
      final readStarted = Completer<void>();
      var reads = 0;
      final p = provider((r) async {
        if (r.url.path.endsWith('/recommendations')) {
          return response({
            'items': [item('old')],
          });
        }
        if (r.url.path.endsWith('/reshuffle')) {
          return response({
            'items': [item('fresh')],
          });
        }
        if (r.url.path.endsWith('/platform-availability')) {
          if (++reads == 1) return oldRead.future;
          readStarted.complete();
          return freshRead.future;
        }
        return response({'items': []});
      });
      await p.load();
      final operation = p.reshuffle();
      await readStarted.future;
      expect(p.reshuffling, isTrue);
      expect(p.recommendations.single.bvid, 'old');
      freshRead.complete(
        response({
          'total_available': 4,
          'by_platform': {'bilibili': 1, 'twitter': 3},
          'pool_status_version': 20,
        }),
      );
      await operation;
      expect(p.recommendations.single.bvid, 'fresh');
      expect(p.runtimeStatus.poolAvailableCount, 4);
      expect(p.platformAvailabilityBySource, {'bilibili': 1, 'twitter': 3});
      oldRead.complete(
        response({
          'total_available': 99,
          'by_platform': {'bilibili': 99},
          'pool_status_version': 10,
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(p.poolAvailableCount, 4);
      p.dispose();
    },
  );

  test(
    'failed legacy inventory read never labels stale counts as current',
    () async {
      var failRead = false;
      final p = provider((r) async {
        if (r.url.path.endsWith('/recommendations')) {
          return response({
            'items': [item('old')],
          });
        }
        if (r.url.path.endsWith('/reshuffle')) {
          return response({
            'items': [item('fresh')],
          });
        }
        if (r.url.path.endsWith('/platform-availability')) {
          if (failRead) throw TimeoutException('inventory stalled');
          return response({
            'total_available': 9,
            'by_platform': {'bilibili': 9},
            'pool_status_version': 10,
          });
        }
        return response({'items': []});
      });
      await p.load();
      await Future<void>.delayed(Duration.zero);
      expect(p.poolAvailableCount, 9);
      failRead = true;
      await p.reshuffle();
      expect(p.recommendations.single.bvid, 'fresh');
      expect(p.reshuffling, isFalse);
      expect(p.inventoryStale, isTrue);
      p.dispose();
    },
  );

  testWidgets('scroll during cooldown is rechecked without a new gesture', (
    tester,
  ) async {
    var calls = 0;
    var eligible = true;
    final gate = RecommendAutoLoad(
      canLoad: () => eligible,
      load: () async {
        calls++;
      },
      waitingForRefill: () => false,
    );
    gate.request();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 1);
    gate.request();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 2);
    gate.request();
    eligible = false;
    await tester.pump(const Duration(seconds: 6));
    expect(calls, 2, reason: 'scrolling away cancels the pending load');
    gate.dispose();
  });

  testWidgets('refill can resume pending intent while idle at the bottom', (
    tester,
  ) async {
    var exhausted = false;
    var calls = 0;
    final gate = RecommendAutoLoad(
      canLoad: () => !exhausted,
      load: () async {
        calls++;
        exhausted = true;
      },
      waitingForRefill: () => exhausted,
    );
    gate.request();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, 1);
    exhausted = false;
    gate.recheck();
    await tester.pump(const Duration(seconds: 6));
    expect(calls, 2);
    gate.dispose();
  });
}
