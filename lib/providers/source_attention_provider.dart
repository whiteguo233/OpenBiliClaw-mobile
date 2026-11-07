import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/custom_sources_api.dart';

/// Active source warnings come from durable backend state, not transient events.
class SourceAttentionProvider extends ChangeNotifier {
  SourceAttentionProvider(this.api);
  final CustomSourcesApi api;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> get items => List.unmodifiable(_items);
  Timer? _timer;
  bool _running = false, _loading = false, _disposed = false;
  int _generation = 0;
  String _backend = '';

  void start() {
    if (_running || _disposed) return;
    _running = true;
    // Home starts this provider while constructing its authenticated subtree.
    // Defer the first notification until that build has completed.
    unawaited(
      Future<void>.microtask(() async {
        if (_running && !_disposed) await refresh();
      }),
    );
  }

  void stop({bool clear = false}) {
    _running = false;
    _timer?.cancel();
    if (clear) {
      _generation++;
      _items = [];
    }
  }

  Future<void> refresh() async {
    if (_disposed || _loading) return;
    _loading = true;
    _timer?.cancel();
    final generation = _generation;
    final backend = api.client.baseUrl;
    if (backend != _backend) {
      _backend = backend;
      _items = [];
      notifyListeners();
    }
    try {
      final rows = await api.attention();
      if (_disposed ||
          generation != _generation ||
          backend != api.client.baseUrl) {
        return;
      }
      final unique = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty &&
            [
              'source_login',
              'draft_login',
              'source_settings',
            ].contains(row['action'])) {
          unique[id] = row;
        }
      }
      _items = unique.values.toList();
      notifyListeners();
    } catch (_) {
      // A failed poll must not erase a still-unresolved warning.
    } finally {
      _loading = false;
      if (_running && !_disposed) {
        _timer = Timer(const Duration(seconds: 30), refresh);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop(clear: true);
    super.dispose();
  }
}
