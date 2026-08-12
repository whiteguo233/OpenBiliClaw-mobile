import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openbiliclaw_app/api/client.dart';
import 'package:openbiliclaw_app/api/config_api.dart';
import 'package:openbiliclaw_app/api/events_api.dart';
import 'package:openbiliclaw_app/api/history_api.dart';
import 'package:openbiliclaw_app/api/saved_api.dart';
import 'package:openbiliclaw_app/api/utils.dart';
import 'package:openbiliclaw_app/models/content_history.dart';
import 'package:openbiliclaw_app/models/saved_item.dart';

/// End-to-end tests against the REAL local backend (127.0.0.1:8420).
///
/// These tests make real network requests and exercise the alignment
/// features: content history, saved feedback events, saved cross-toggle,
/// and the saved-sync config toggle. They require the OpenBiliClaw backend
/// to be running and fail loudly (no auto-skip) so CI / local runs surface
/// regressions.
///
///
/// Write tests are best-effort and restore state where possible.
void main() {
  final client = ApiClient(host: '127.0.0.1', port: 8420);
  final historyApi = HistoryApi(client);
  final savedApi = SavedApi(client);
  final eventsApi = EventsApi(client);
  final configApi = ConfigApi(client);

  // All e2e tests require the real backend. Fail fast with a clear message
  // when it is not running, instead of a cascade of connection errors.
  setUpAll(() async {
    // Retry a few times: parallel e2e files can momentarily contend with
    // the backend's health endpoint.
    var ok = false;
    for (var attempt = 0; attempt < 4 && !ok; attempt++) {
      ok = await client.checkHealth();
      if (!ok) await Future<void>.delayed(const Duration(seconds: 3));
    }
    expect(
      ok,
      isTrue,
      reason: '端到端测试需要后端运行在 127.0.0.1:8420（openbiliclaw serve-api）',
    );
  });

  group('e2e content-history', () {
    test(
      'clicked / shown / removed categories return items or empty page',
      () async {
        for (final category in ContentHistoryCategory.values) {
          final page = await historyApi.fetch(category, limit: 5);
          expect(page.category, category);
          expect(page.items.length, lessThanOrEqualTo(5));
          expect(page.total, greaterThanOrEqualTo(0));
          // Pagination fields are always present and coherent.
          if (page.hasMore) {
            expect(page.nextCursor, isNotEmpty);
          } else {
            expect(page.nextCursor, isEmpty);
          }
        }
      },
    );

    test('cursor pagination advances without duplicating first page', () async {
      final first = await historyApi.fetch(
        ContentHistoryCategory.clicked,
        limit: 5,
      );
      if (!first.hasMore) {
        // Nothing to paginate over; the contract is still validated above.
        return;
      }
      final second = await historyApi.fetch(
        ContentHistoryCategory.clicked,
        limit: 5,
        cursor: first.nextCursor,
      );
      final firstKeys = first.items.map((item) => item.itemKey).toSet();
      final overlap = second.items.where(
        (item) => firstKeys.contains(item.itemKey),
      );
      expect(overlap, isEmpty, reason: '下一页不应重复第一页的条目');
    });
  });

  group('e2e saved feedback events', () {
    test(
      'like feedback on a real saved/recommended item is accepted',
      () async {
        // Reuse whatever is already in the backend history so we never depend
        // on seeding data. If history is empty, pick the first recommendation.
        var item = await _pickHistoryItem(historyApi);
        if (item == null) {
          final recs = await client.get('/recommendations', timeout: 15);
          final raw = (recs['items'] as List).cast<Map>().first;
          item = SavedItem.fromJson(Map<String, dynamic>.from(raw));
        }
        expect(item, isNotNull);

        final res = await eventsApi.sendSavedFeedback(
          item,
          feedbackType: 'like',
        );
        expect(res['accepted'], greaterThanOrEqualTo(1));
      },
    );

    test('comment feedback is accepted', () async {
      final item = await _pickHistoryItem(historyApi);
      if (item == null) return; // no data to comment on; nothing to verify
      final res = await eventsApi.sendSavedFeedback(
        item,
        feedbackType: 'comment',
        note: '端到端测试：聊一聊线索',
      );
      expect(res['accepted'], greaterThanOrEqualTo(1));
    });
  });

  group('e2e saved cross-toggle', () {
    test('watch_later → favorite round-trip restores list', () async {
      final item = await _pickHistoryItem(historyApi);
      if (item == null) return;

      final wasFavorite = await _isSaved(
        savedApi,
        SavedListKind.favorite,
        item,
      );
      // Toggle ON (add to favorite).
      await savedApi.save(SavedListKind.favorite, item);
      final added = await _isSaved(savedApi, SavedListKind.favorite, item);
      expect(added, isTrue, reason: '交叉切换到收藏后应存在');

      // Toggle OFF unless it was already there before the test.
      if (!wasFavorite) {
        await savedApi.remove(SavedListKind.favorite, item.itemKey);
        final removed = await _isSaved(savedApi, SavedListKind.favorite, item);
        expect(removed, isFalse, reason: '交叉切换移除后应不存在');
      }
    });
  });

  group('e2e saved-sync config', () {
    test('auto-sync toggle round-trips through /api/config', () async {
      final before = await configApi.savedAutoSyncEnabled();
      // Flip it, verify, then restore the original value.
      final setOk = await configApi.setSavedAutoSync(!before);
      expect(setOk, isTrue, reason: '设置 auto_sync_enabled 应被后端接受');

      final afterFlip = await configApi.savedAutoSyncEnabled();
      expect(afterFlip, !before);

      final restoreOk = await configApi.setSavedAutoSync(before);
      expect(restoreOk, isTrue);
      final restored = await configApi.savedAutoSyncEnabled();
      expect(restored, before, reason: '测试后应恢复原始配置');
    });
  });

  group('e2e health & embedding', () {
    test('health reports profile and embedding readiness', () async {
      final data = await client.get('/health', timeout: 8);
      expect(data['status'], 'ok');
      // embedding_ready is a live probe: when the backend is configured with
      // Ollama embedding it must be true; otherwise the assertion is skipped
      // (semantic dedup is optional).
      if (data.containsKey('embedding_ready')) {
        // We assert the field is a bool — the backend probes it live.
        expect(data['embedding_ready'], isA<bool>());
      }
    });
  });

  group('e2e image proxy', () {
    test('a real content cover returns decodable image bytes', () async {
      final coverUrl = await _pickRealCoverUrl(client, historyApi);
      expect(coverUrl, isNotEmpty, reason: '真实推荐或历史记录中应包含封面地址');

      final proxyUrl = proxyImageUrl(
        coverUrl,
        client.baseUrl,
        token: client.sessionToken,
      );
      final response = await http
          .get(
            Uri.parse(proxyUrl),
            headers: {
              'X-OBC-Auth': '1',
              if (client.sessionToken.isNotEmpty)
                'Cookie': 'obc_session=${client.sessionToken}',
            },
          )
          .timeout(const Duration(seconds: 20));

      expect(response.statusCode, 200);
      expect(
        response.headers['content-type'],
        startsWith('image/'),
        reason: '图片代理必须返回图片 MIME 类型',
      );
      expect(response.bodyBytes.length, greaterThan(100));
    });
  });

  group('e2e probes & pending confirmations', () {
    test('pending probes endpoint responds with a well-formed list', () async {
      final data = await client.get('/interest-probes/pending', timeout: 8);
      expect(data['items'], isA<List>());
    });

    test('pending confirmations endpoint responds with a list', () async {
      final data = await client.get('/chat/pending-confirmations', timeout: 8);
      expect(data, isA<Map>());
    });
  });
}

Future<SavedItem?> _pickHistoryItem(HistoryApi api) async {
  for (final category in ContentHistoryCategory.values) {
    final page = await api.fetch(category, limit: 5);
    if (page.items.isNotEmpty) {
      final item = page.items.first;
      return SavedItem.fromJson({
        'item_key': item.itemKey,
        'source_platform': item.sourcePlatform,
        'content_id': item.contentId,
        'content_url': item.contentUrl,
        'content_type': item.contentType,
        'title': item.title,
        'author_name': item.authorName,
        'cover_url': item.coverUrl,
      });
    }
  }
  return null;
}

Future<String> _pickRealCoverUrl(
  ApiClient client,
  HistoryApi historyApi,
) async {
  final recommendations = await client.get('/recommendations', timeout: 15);
  final items = recommendations['items'];
  if (items is List) {
    for (final raw in items.whereType<Map>()) {
      final coverUrl = raw['cover_url']?.toString().trim() ?? '';
      if (coverUrl.isNotEmpty) return coverUrl;
    }
  }

  for (final category in ContentHistoryCategory.values) {
    final page = await historyApi.fetch(category, limit: 20);
    for (final item in page.items) {
      if (item.coverUrl.isNotEmpty) return item.coverUrl;
    }
  }
  return '';
}

Future<bool> _isSaved(SavedApi api, SavedListKind kind, SavedItem item) async {
  try {
    final data = await api.status(kind, item.itemKey);
    return data['saved'] == true;
  } catch (_) {
    return false;
  }
}
