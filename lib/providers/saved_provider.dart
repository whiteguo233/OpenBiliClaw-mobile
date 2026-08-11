import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/events_api.dart';
import '../api/history_api.dart';
import '../api/saved_api.dart';
import '../models/content_history.dart';
import '../models/recommendation.dart';
import '../models/saved_item.dart';

class SavedProvider extends ChangeNotifier {
  final SavedApi _api;
  final HistoryApi _historyApi;
  final EventsApi _eventsApi;

  List<SavedItem> _watchLater = [];
  List<SavedItem> _favorites = [];
  int _activeLoads = 0;
  bool _syncing = false;
  String _error = '';

  /// Per-category content-history state (bounded 30-day history).
  final Map<ContentHistoryCategory, _HistoryPageState> _historyPages = {};
  final Set<String> _busyRestores = {};
  int _historyLoads = 0;
  int _historyMoreLoads = 0;
  bool _historyLoadedOnce = false;

  SavedProvider(ApiClient client)
    : _api = SavedApi(client),
      _historyApi = HistoryApi(client),
      _eventsApi = EventsApi(client);

  List<SavedItem> get watchLater => List.unmodifiable(_watchLater);
  List<SavedItem> get favorites => List.unmodifiable(_favorites);
  bool get loading => _activeLoads > 0;
  bool get syncing => _syncing;
  String get error => _error;

  _HistoryPageState _pageState(ContentHistoryCategory category) =>
      _historyPages.putIfAbsent(category, () => _HistoryPageState());

  List<ContentHistoryItem> historyItems(ContentHistoryCategory category) =>
      List.unmodifiable(_pageState(category).items);

  int historyTotal(ContentHistoryCategory category) =>
      _pageState(category).total;

  bool historyLoading(ContentHistoryCategory category) {
    final page = _historyPages[category];
    return page?.loading ?? false;
  }

  bool historyLoadingMore(ContentHistoryCategory category) {
    final page = _historyPages[category];
    return page?.loadingMore ?? false;
  }

  String historyError(ContentHistoryCategory category) =>
      _pageState(category).error;

  bool historyHasMore(ContentHistoryCategory category) =>
      _pageState(category).hasMore;

  bool get historyBusy =>
      _historyLoads > 0 || _historyMoreLoads > 0 || _busyRestores.isNotEmpty;

  /// Whether the first history load has completed at least once. Used by the
  /// history view to decide between "loading" and "no records yet" states.
  bool get historyLoadedOnce => _historyLoadedOnce;

  bool restoreBusy(String itemKey) => _busyRestores.contains(itemKey);

  /// Refresh every content-history category from its first page.
  Future<void> loadAllHistory() async {
    _historyLoadedOnce = true;
    await Future.wait(ContentHistoryCategory.values.map(loadHistory));
  }

  /// Refresh the given history category from its first page.
  Future<void> loadHistory(ContentHistoryCategory category) async {
    final page = _pageState(category);
    if (page.loading) return;
    page.loading = true;
    page.error = '';
    _historyLoads += 1;
    notifyListeners();
    try {
      final fetched = await _historyApi.fetch(category);
      page.items = fetched.items;
      page.total = fetched.total;
      page.nextCursor = fetched.nextCursor;
      page.hasMore = fetched.hasMore;
    } catch (error) {
      page.error = _message(error, '历史记录加载失败');
    } finally {
      page.loading = false;
      _historyLoads -= 1;
      notifyListeners();
    }
  }

  /// Append the next page of a history category.
  Future<void> loadMoreHistory(ContentHistoryCategory category) async {
    final page = _pageState(category);
    if (page.loading ||
        page.loadingMore ||
        !page.hasMore ||
        page.nextCursor.isEmpty) {
      return;
    }
    page.loadingMore = true;
    page.error = '';
    _historyMoreLoads += 1;
    notifyListeners();
    try {
      final fetched = await _historyApi.fetch(
        category,
        cursor: page.nextCursor,
      );
      final seen = page.items.map((item) => item.itemKey).toSet();
      for (final item in fetched.items) {
        if (seen.add(item.itemKey)) page.items.add(item);
      }
      page.total = fetched.total;
      page.nextCursor = fetched.nextCursor;
      page.hasMore = fetched.hasMore;
    } catch (error) {
      page.error = _message(error, '更多历史记录加载失败');
    } finally {
      page.loadingMore = false;
      _historyMoreLoads -= 1;
      notifyListeners();
    }
  }

  /// Report a history card open, best-effort. Refreshes the `shown` category
  /// after a successful report so the card moves into `clicked` (mirrors the
  /// web clients' history open flow).
  Future<void> reportHistoryClick(
    ContentHistoryCategory category,
    ContentHistoryItem item,
  ) async {
    final reported = await _historyApi.reportClick(item);
    if (reported && category == ContentHistoryCategory.shown) {
      await loadHistory(category);
    }
  }

  /// Restore a removed history item back into a saved list.
  Future<bool> restoreFromHistory(
    ContentHistoryCategory category,
    ContentHistoryItem item,
    String context, {
    required String listKind,
  }) async {
    final key = item.itemKey;
    if (_busyRestores.contains(key)) return false;
    _busyRestores.add(key);
    _error = '';
    notifyListeners();
    try {
      await _historyApi.restore(listKind, item);
      final page = _pageState(category);
      final updated = page.items.map((entry) {
        if (entry.itemKey != key) return entry;
        final contexts = entry.contexts
            .map(
              (ctx) => ctx.context == context
                  ? ContentHistoryContext(
                      context: ctx.context,
                      occurredAt: ctx.occurredAt,
                      restored: true,
                    )
                  : ctx,
            )
            .toList();
        return ContentHistoryItem(
          itemKey: entry.itemKey,
          sourcePlatform: entry.sourcePlatform,
          contentId: entry.contentId,
          contentUrl: entry.contentUrl,
          contentType: entry.contentType,
          title: entry.title,
          authorName: entry.authorName,
          coverUrl: entry.coverUrl,
          bodyText: entry.bodyText,
          recommendationId: entry.recommendationId,
          occurredAt: entry.occurredAt,
          context: entry.context,
          restored: entry.context == context ? true : entry.restored,
          contexts: contexts,
        );
      }).toList();
      page.items = updated;
      unawaited(loadAll());
      return true;
    } catch (error) {
      _error = _message(error, '恢复失败，请稍后重试');
      notifyListeners();
      return false;
    } finally {
      _busyRestores.remove(key);
      notifyListeners();
    }
  }

  List<SavedItem> itemsFor(SavedListKind kind) =>
      kind == SavedListKind.watchLater ? _watchLater : _favorites;

  bool contains(SavedListKind kind, Recommendation item) {
    final identity = item.savedIdentity;
    return itemsFor(kind).any(
      (saved) =>
          saved.itemKey == identity ||
          (saved.sourcePlatform == item.sourcePlatform &&
              saved.contentId == item.contentId),
    );
  }

  bool containsItem(SavedListKind kind, SavedItem item) {
    return itemsFor(kind).any(
      (saved) =>
          saved.itemKey == item.itemKey ||
          (saved.sourcePlatform == item.sourcePlatform &&
              saved.contentId == item.contentId),
    );
  }

  /// Cross-toggle a saved item into the other list (watch later ↔ favorite),
  /// mirroring the web clients' cross-toggle on saved cards.
  Future<bool> toggleItem(SavedListKind kind, SavedItem item, bool add) async {
    _error = '';
    try {
      if (add) {
        await _api.save(kind, item);
      } else {
        await _api.remove(kind, item.itemKey);
      }
      await _load(kind);
      return true;
    } catch (error) {
      _error = _message(error, '${kind.label}操作失败');
      notifyListeners();
      return false;
    }
  }

  /// Report like / dislike / comment feedback about a saved item, best-effort
  /// (mirrors the web clients' `postSavedFeedback`).
  Future<bool> submitFeedback(
    SavedItem item, {
    required String feedbackType,
    String note = '',
  }) async {
    _error = '';
    try {
      await _eventsApi.sendSavedFeedback(
        item,
        feedbackType: feedbackType,
        note: note,
      );
      return true;
    } catch (error) {
      _error = _message(error, '反馈提交失败');
      notifyListeners();
      return false;
    }
  }

  Future<void> loadAll() async {
    await Future.wait([loadWatchLater(), loadFavorites()]);
  }

  Future<void> loadWatchLater() => _load(SavedListKind.watchLater);

  Future<void> loadFavorites() => _load(SavedListKind.favorite);

  Future<void> _load(SavedListKind kind) async {
    _activeLoads += 1;
    _error = '';
    notifyListeners();
    try {
      final items = await _api.fetch(kind);
      if (kind == SavedListKind.watchLater) {
        _watchLater = items;
      } else {
        _favorites = items;
      }
    } catch (error) {
      _error = _message(error, '收藏列表加载失败');
    } finally {
      _activeLoads -= 1;
      notifyListeners();
    }
  }

  Future<bool> toggle(
    SavedListKind kind,
    Recommendation recommendation,
    bool add,
  ) async {
    _error = '';
    final item = SavedItem.fromRecommendation(recommendation);
    try {
      if (add) {
        await _api.save(kind, item);
      } else {
        await _api.remove(kind, item.itemKey);
      }
      await _load(kind);
      return true;
    } catch (error) {
      _error = _message(error, '${kind.label}操作失败');
      notifyListeners();
      return false;
    }
  }

  Future<bool> remove(SavedListKind kind, SavedItem item) async {
    _error = '';
    try {
      await _api.remove(kind, item.itemKey);
      await _load(kind);
      return true;
    } catch (error) {
      _error = _message(error, '移除失败');
      notifyListeners();
      return false;
    }
  }

  Future<bool> syncOne(SavedListKind kind, SavedItem item) {
    return syncItems(kind, [item.itemKey]);
  }

  Future<bool> syncPending(SavedListKind kind) {
    final keys = itemsFor(
      kind,
    ).where((item) => item.canSync).map((item) => item.itemKey).toList();
    return syncItems(kind, keys);
  }

  Future<bool> syncItems(SavedListKind kind, List<String> itemKeys) async {
    if (_syncing) return false;
    _syncing = true;
    _error = '';
    notifyListeners();
    try {
      final started = await _api.sync(kind, itemKeys);
      final taskId = started['task_id']?.toString() ?? '';
      if (taskId.isNotEmpty && !_syncFinished(started)) {
        for (var attempt = 0; attempt < 12; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          final current = await _api.pollSync(taskId);
          if (_syncFinished(current)) break;
        }
      }
      await _load(kind);
      return true;
    } catch (error) {
      _error = _message(error, '平台同步失败');
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  bool _syncFinished(Map<String, dynamic> payload) {
    final items = payload['items'];
    if (items is! List || items.isEmpty) return true;
    const pending = {'pending', 'syncing'};
    return items.every((item) {
      if (item is! Map) return true;
      return !pending.contains(item['status']?.toString());
    });
  }

  String _message(Object error, String fallback) {
    if (error is ApiException) return error.message;
    final text = error.toString().trim();
    return text.isEmpty ? fallback : text;
  }
}

/// Mutable per-category state for one bounded content-history page.
class _HistoryPageState {
  List<ContentHistoryItem> items = [];
  int total = 0;
  String nextCursor = '';
  bool hasMore = false;
  bool loading = false;
  bool loadingMore = false;
  String error = '';
}
