import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/saved_api.dart';
import '../models/recommendation.dart';
import '../models/saved_item.dart';

class SavedProvider extends ChangeNotifier {
  final SavedApi _api;

  List<SavedItem> _watchLater = [];
  List<SavedItem> _favorites = [];
  int _activeLoads = 0;
  bool _syncing = false;
  String _error = '';

  SavedProvider(ApiClient client) : _api = SavedApi(client);

  List<SavedItem> get watchLater => List.unmodifiable(_watchLater);
  List<SavedItem> get favorites => List.unmodifiable(_favorites);
  bool get loading => _activeLoads > 0;
  bool get syncing => _syncing;
  String get error => _error;

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
