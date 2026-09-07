import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/adapter_web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/client.dart';
import '../api/recommend_api.dart';
import '../models/delight.dart';
import '../models/recommendation.dart';
import '../models/runtime_status.dart';

class RecommendProvider extends ChangeNotifier {
  final RecommendApi _api;
  final ApiClient _client;

  /// 与桌面 Web（web/desktop sourceFilterDefinitions）一致的平台标签顺序。
  static const List<(String, String)> _platformLabels = [
    ('bilibili', 'B 站'),
    ('xiaohongshu', '小红书'),
    ('douyin', '抖音'),
    ('weibo', '微博'),
    ('youtube', 'YouTube'),
    ('twitter', 'X (Twitter)'),
    ('github', 'GitHub'),
    ('zhihu', '知乎'),
    ('reddit', 'Reddit'),
    ('bangumi', 'Bangumi'),
    ('linuxdo', 'Linux.do'),
    ('v2ex', 'V2EX'),
  ];

  List<Recommendation> _recommendations = [];
  List<Delight> _delights = [];
  int _delightIndex = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _reshuffling = false;
  bool _autoLoadExhausted = false;
  bool _online = false;
  int _consecutivePollFailures = 0;
  bool _polling = false;
  String _error = '';
  String _platformFilter = '';
  RuntimeStatus _runtimeStatus = const RuntimeStatus();
  PlatformAvailability _platformAvailability = const PlatformAvailability();
  Set<String> _enabledSources = {};
  ActivityFeed _activityFeed = const ActivityFeed();
  Timer? _pollTimer;
  WebSocketChannel? _ws;
  Timer? _reconnectTimer;
  bool _wsConnecting = false;
  bool _running = false;
  int _pollGeneration = 0;
  bool _disposed = false;
  bool _hasPlatformAvailability = false;
  int _inventoryGeneration = 0;
  bool _inventoryLoading = false;
  bool _inventoryReloadPending = false;

  RecommendProvider(ApiClient client)
    : _client = client,
      _api = RecommendApi(client);

  /// Notifies listeners unless the provider has already been disposed.
  ///
  /// The poll loop and WebSocket callbacks can complete after the owning
  /// widget tree is torn down; calling [ChangeNotifier.notifyListeners] on a
  /// disposed notifier throws, so all notifications go through here.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  List<Recommendation> get recommendations =>
      List.unmodifiable(_recommendations);
  List<Delight> get delights => List.unmodifiable(_delights);
  int get delightIndex => _delightIndex;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get reshuffling => _reshuffling;
  bool get autoLoadExhausted => _autoLoadExhausted;
  bool get online => _online;
  String get error => _error;
  RuntimeStatus get runtimeStatus => _runtimeStatus;
  PlatformAvailability get platformAvailability => _platformAvailability;
  Map<String, int> get platformAvailabilityBySource =>
      _platformAvailability.byPlatform;
  Set<String> get enabledSources => Set.unmodifiable(_enabledSources);
  ActivityFeed get activityFeed => _activityFeed;

  void nextDelight() {
    if (_delights.isNotEmpty) {
      _delightIndex = (_delightIndex + 1) % _delights.length;
      _safeNotify();
    }
  }

  void prevDelight() {
    if (_delights.isNotEmpty) {
      _delightIndex = (_delightIndex - 1 + _delights.length) % _delights.length;
      _safeNotify();
    }
  }

  String? contentUrlFor(Recommendation rec) {
    if (rec.contentUrl.isNotEmpty) return rec.contentUrl;
    final contentId = rec.contentId.isNotEmpty
        ? rec.contentId
        : (rec.bvid.contains(':')
              ? rec.bvid.split(':').skip(1).join(':')
              : rec.bvid);
    if (contentId.isEmpty) return null;
    switch (rec.sourcePlatform) {
      case 'youtube':
        return 'https://www.youtube.com/watch?v=$contentId';
      case 'twitter':
        return 'https://x.com/i/status/$contentId';
      case 'zhihu':
        return 'https://www.zhihu.com/question/$contentId';
      case 'reddit':
        return 'https://www.reddit.com/comments/$contentId';
      case 'douyin':
        return 'https://www.douyin.com/video/$contentId';
      case 'xiaohongshu':
        return 'https://www.xiaohongshu.com/explore/$contentId';
      case 'bangumi':
        return 'https://bgm.tv/subject/$contentId';
      case 'linuxdo':
        final topicId = contentId.replaceFirst(
          RegExp(r'^topic[:_]', caseSensitive: false),
          '',
        );
        return RegExp(r'^[1-9]\d*$').hasMatch(topicId)
            ? 'https://linux.do/t/$topicId'
            : null;
      case 'v2ex':
        return 'https://www.v2ex.com/t/$contentId';
      case 'weibo':
        return 'https://m.weibo.cn/detail/$contentId';
      case 'bilibili':
        return 'https://www.bilibili.com/video/$contentId';
      default:
        return null;
    }
  }

  Future<void> load() async {
    if (_loading || _reshuffling || _loadingMore) return;
    _loading = true;
    _error = '';
    _safeNotify();
    try {
      final recs = await _api.fetch();
      _recommendations = recs;
      _online = true;
      _autoLoadExhausted = false;
      _prunePlatformFilter();
    } catch (error) {
      _online = false;
      _error = _message(error, '推荐加载失败');
    } finally {
      _loading = false;
      _safeNotify();
    }
    unawaited(_loadSideChannels());
  }

  /// 下拉刷新 / 点击推荐 Tab 回顶刷新：先让后端真正刷新一次推荐池，
  /// 再换一批新内容，避免只重新 GET 当前列表导致内容看起来“没变化”。
  Future<void> refresh() async {
    if (_loading || _reshuffling || _loadingMore) {
      debugPrint('[RecommendProvider] refresh skipped: already loading');
      return;
    }
    _loading = true;
    _error = '';
    _safeNotify();
    debugPrint('[RecommendProvider] refresh start');
    try {
      // POST /refresh is only a background pool-replenishment trigger. It must
      // not gate the user-visible refresh: if the response is lost on the
      // physical device, fire-and-forget it and continue to 换一批.
      unawaited(
        _api.refresh().catchError((Object error) {
          debugPrint('[RecommendProvider] refresh POST ignored: $error');
          return <String, dynamic>{};
        }),
      );
      debugPrint('[RecommendProvider] refresh: POST /refresh fired');
      final excluded = _recommendations.map((item) => item.bvid).toList();
      final requestPlatform = _platformFilter;
      final result = await _api.reshuffle(
        excluded,
        sourcePlatform: requestPlatform,
      );
      _applyPoolStatus(result.poolStatus);
      _replaceBatch(result.items, requestPlatform);
      _online = true;
      if (_platformFilter == requestPlatform) {
        _autoLoadExhausted = result.items.isEmpty;
      }
      _prunePlatformFilter();
    } catch (error) {
      debugPrint('[RecommendProvider] refresh error: $error');
      // 用户触发的刷新失败不能代表整体掉线；真正的在线状态由轮询维护。
      _error = _message(error, '推荐刷新失败');
    } finally {
      _loading = false;
      _safeNotify();
      debugPrint('[RecommendProvider] refresh finished');
    }
    unawaited(_loadSideChannels());
  }

  /// 平台过滤（与桌面 Web 的「全部 / 平台」过滤一致，纯客户端过滤）：
  /// 空字符串表示「全部」。
  String get platformFilter => _platformFilter;

  /// 当前过滤后应展示的推荐列表。
  List<Recommendation> get visibleRecommendations {
    if (_platformFilter.isEmpty) return _recommendations;
    return _recommendations
        .where((item) => item.sourcePlatform == _platformFilter)
        .toList();
  }

  /// 可选来源：优先按后端“是否启用该来源”展示；启用过的来源即使当前
  /// 候选池为 0 也保留 tab。旧后端/接口异常时回退为当前列表已出现的来源。
  List<String> get availablePlatforms {
    final availabilitySet = _platformAvailability.byPlatform.keys.toSet();
    if (_enabledSources.isNotEmpty) {
      final known = _platformLabels.map((entry) => entry.$1);
      final union = {..._enabledSources, ...availabilitySet};
      final ordered = <String>[
        ...known.where(union.contains),
        ...union.difference(known.toSet()).toList()..sort(),
      ];
      return ordered;
    }
    final seen = <String>{};
    for (final item in _recommendations) {
      final slug = item.sourcePlatform.trim().toLowerCase();
      if (slug.isNotEmpty) seen.add(slug);
    }
    final union = {...seen, ...availabilitySet};
    final known = _platformLabels.map((entry) => entry.$1);
    return <String>[
      ...known.where(union.contains),
      ...union.difference(known.toSet()).toList()..sort(),
    ];
  }

  /// 只要启用了多个来源就显示平台选择（即使某个来源当前没有库存）。
  bool get showPlatformChoice => availablePlatforms.length > 1;

  void setPlatformFilter(String slug) {
    final next = slug.trim().toLowerCase();
    if (_platformFilter == next) return;
    _platformFilter = next;
    _autoLoadExhausted = false;
    _safeNotify();
  }

  /// 与桌面 Web 一致的平台中文标签；未知平台原样显示 slug。
  static String platformLabel(String slug) {
    final key = slug.trim().toLowerCase();
    for (final entry in _platformLabels) {
      if (entry.$1 == key) return entry.$2;
    }
    return slug.trim();
  }

  void _prunePlatformFilter() {
    if (_platformFilter.isEmpty) return;
    if (availablePlatforms.contains(_platformFilter)) return;
    _platformFilter = '';
    _autoLoadExhausted = false;
  }

  Future<void> _loadSideChannels() async {
    await Future.wait([
      _loadRuntimeStatus(),
      _loadActivityFeed(),
      _loadDelights(),
      _loadPlatformAvailability(),
      _loadEnabledSources(),
    ]);
  }

  int _availableForScope(PlatformAvailability status) => _platformFilter.isEmpty
      ? status.totalAvailable
      : (status.byPlatform[_platformFilter] ?? 0);

  bool _applyPoolStatus(PlatformAvailability? status) {
    if (status == null || _disposed) return false;
    if (status.version < _platformAvailability.version) return true;
    final previous = _availableForScope(_platformAvailability);
    _hasPlatformAvailability = true;
    _platformAvailability = status;
    _inventoryGeneration += 1;
    _runtimeStatus = _runtimeStatus.withPoolAvailableCount(
      status.totalAvailable,
    );
    // Other platforms having stock cannot revive an exhausted scoped feed.
    if (_autoLoadExhausted && _availableForScope(status) > previous) {
      _autoLoadExhausted = false;
    }
    _safeNotify();
    return true;
  }

  void _replaceBatch(List<Recommendation> items, String scope) {
    if (items.isEmpty) return;
    _recommendations = scope.isEmpty
        ? items
        : [
            ..._recommendations.where((item) => item.sourcePlatform != scope),
            ...items,
          ];
  }

  Future<void> _loadRuntimeStatus() async {
    try {
      final status = await _api.fetchRuntimeStatus();
      _runtimeStatus = _hasPlatformAvailability
          ? status.withPoolAvailableCount(_platformAvailability.totalAvailable)
          : status;
      _safeNotify();
    } catch (_) {}
  }

  Future<void> _loadPlatformAvailability() async {
    if (_inventoryLoading) {
      _inventoryReloadPending = true;
      return;
    }
    _inventoryLoading = true;
    final generation = _inventoryGeneration;
    try {
      final status = await _api.fetchPlatformAvailability();
      if (generation == _inventoryGeneration) _applyPoolStatus(status);
    } catch (_) {
      // Keep last successful counts. Failed reads are not empty inventory.
    } finally {
      _inventoryLoading = false;
      if (_inventoryReloadPending && !_disposed) {
        _inventoryReloadPending = false;
        unawaited(_loadPlatformAvailability());
      }
    }
  }

  Future<void> _loadEnabledSources() async {
    try {
      _enabledSources = await _api.fetchEnabledSources();
      _safeNotify();
    } catch (_) {}
  }

  Future<void> _loadActivityFeed() async {
    try {
      _activityFeed = await _api.fetchActivity();
      _safeNotify();
    } catch (_) {}
  }

  Future<void> _loadDelights() async {
    try {
      final delights = await _api.fetchDelights(limit: 10);
      _delights = delights;
      _delightIndex = _delightIndex.clamp(
        0,
        (_delights.length - 1).clamp(0, _delights.length),
      );
      _safeNotify();
    } catch (_) {}
  }

  Future<void> reshuffle() async {
    if (_reshuffling || _loading || _loadingMore) return;
    _reshuffling = true;
    _error = '';
    _safeNotify();
    debugPrint('[RecommendProvider] reshuffle start');
    try {
      final excluded = _recommendations.map((item) => item.bvid).toList();
      final requestPlatform = _platformFilter;
      final result = await _api.reshuffle(
        excluded,
        sourcePlatform: requestPlatform,
      );
      final inventoryApplied = _applyPoolStatus(result.poolStatus);
      _replaceBatch(result.items, requestPlatform);
      _online = true;
      if (_platformFilter == requestPlatform) {
        _autoLoadExhausted = result.items.isEmpty;
      }
      if (!inventoryApplied) unawaited(_loadPlatformAvailability());
      unawaited(_loadRuntimeStatus());
    } catch (error) {
      debugPrint('[RecommendProvider] reshuffle error: $error');
      _error = _message(error, '换一批失败');
    } finally {
      _reshuffling = false;
      _safeNotify();
      debugPrint('[RecommendProvider] reshuffle finished');
    }
  }

  Future<void> append() async {
    if (_loadingMore || _loading || _reshuffling) return;
    // Manual retries must reach the server even if the last inventory read
    // was zero or failed. Only the view's automatic loading uses exhaustion.
    _loadingMore = true;
    _error = '';
    _safeNotify();
    try {
      final excluded = _recommendations.map((item) => item.bvid).toList();
      final requestPlatform = _platformFilter;
      final result = await _api.append(
        excluded,
        sourcePlatform: requestPlatform,
      );
      final inventoryApplied = _applyPoolStatus(result.poolStatus);
      final newItems = result.items;
      final identities = _recommendations
          .map((item) => item.savedIdentity)
          .toSet();
      var addedCount = 0;
      for (final item in newItems) {
        if (identities.add(item.savedIdentity)) {
          _recommendations.add(item);
          addedCount += 1;
        }
      }
      _online = true;
      if (_platformFilter == requestPlatform) {
        _autoLoadExhausted = addedCount == 0 || !result.hasMore;
      }
      if (!inventoryApplied) unawaited(_loadPlatformAvailability());
    } catch (error) {
      _error = _message(error, '加载更多失败');
    } finally {
      _loadingMore = false;
      _safeNotify();
    }
  }

  Future<bool> submitFeedback(
    Recommendation rec,
    String type, {
    String? note,
  }) async {
    _error = '';
    try {
      await _api.submitFeedback(
        rec.id,
        type,
        bvid: rec.bvid,
        itemKey: rec.itemKey,
        note: note,
      );
      for (final item in _recommendations) {
        if (item.id == rec.id) item.feedbackType = type;
      }
      _safeNotify();
      return true;
    } catch (error) {
      _error = _message(error, '反馈提交失败');
      _safeNotify();
      return false;
    }
  }

  Future<bool> respondToDelight(
    Delight delight,
    String response, {
    String message = '',
  }) async {
    _error = '';
    try {
      await _api.respondToDelight(
        delight.bvid,
        response,
        title: delight.title,
        message: message,
      );
      if (response == 'like' || response == 'view') {
        final nextState = response == 'like' ? 'liked' : 'viewed';
        _delights = _delights
            .map(
              (item) => item.bvid == delight.bvid
                  ? item.copyWith(state: nextState)
                  : item,
            )
            .toList();
      } else {
        _delights.removeWhere((item) => item.bvid == delight.bvid);
        unawaited(_api.markDelightSent(delight.bvid));
      }
      _delightIndex = _delightIndex.clamp(
        0,
        (_delights.length - 1).clamp(0, _delights.length),
      );
      _safeNotify();
      return true;
    } catch (error) {
      _error = _message(error, '惊喜推荐操作失败');
      _safeNotify();
      return false;
    }
  }

  Future<void> reportClick(Recommendation rec) async {
    await _api.reportClick({
      'recommendation_id': rec.id,
      'bvid': rec.bvid,
      'content_id': rec.contentId,
      'title': rec.title,
      'up_name': rec.upName,
      'topic_label': rec.topicLabel,
      'source_platform': rec.sourcePlatform,
      'content_url': contentUrlFor(rec) ?? rec.contentUrl,
    });
  }

  void startPolling() {
    _running = true;
    final generation = ++_pollGeneration;
    _pollTimer?.cancel();
    unawaited(_runPollLoop(generation));
    unawaited(_connectStream());
  }

  /// 从后台回到前台时调用：重新建立轮询和 WebSocket，并立刻触发一次拉取，
  /// 避免 iOS/Android 挂起后恢复却仍显示“离线”。
  void resume() {
    if (!_running) return;
    startPolling();
  }

  void stopPolling() {
    _running = false;
    _pollGeneration += 1;
    _pollTimer?.cancel();
    _pollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_ws?.sink.close() ?? Future.value());
    _ws = null;
  }

  Future<void> _runPollLoop(int generation) async {
    await _poll();
    if (!_running || generation != _pollGeneration) return;
    _pollTimer = Timer(
      Duration(seconds: _online ? 30 : 3),
      () => unawaited(_runPollLoop(generation)),
    );
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final recs = await _api.fetch(timeout: 12);
      if (_recommendations.isEmpty && recs.isNotEmpty) {
        _recommendations = recs;
      }
      _online = true;
      _consecutivePollFailures = 0;
      _error = '';
      // 先通知主列表，再异步加载侧栏状态；侧栏慢时不要拖慢首屏/轮询。
      _safeNotify();
      unawaited(_loadDelights());
      unawaited(_loadActivityFeed());
      unawaited(_loadRuntimeStatus());
      unawaited(_loadPlatformAvailability());
      unawaited(_loadEnabledSources());
    } catch (_) {
      // 短暂超时不立刻判离线，连续 2 次失败才切离线，避免图片/请求多时误报。
      _consecutivePollFailures += 1;
      if (_online && _consecutivePollFailures >= 2) {
        _online = false;
        _safeNotify();
      }
    } finally {
      _polling = false;
    }
  }

  /// dart:io's [WebSocket.connect] uses raw sockets that fight iOS Local
  /// Network privacy (release-mode `errno = 65`, see flutter/flutter#171197).
  /// On iOS go through NSURLSessionWebSocketTask (CupertinoWebSocket), which
  /// follows the same permission rules as Safari/CFNetwork.
  Future<WebSocketChannel> _openRuntimeStream() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final socket = await CupertinoWebSocket.connect(Uri.parse(_client.wsUrl));
      return AdapterWebSocketChannel(socket);
    }
    final ws = await WebSocket.connect(
      _client.wsUrl,
      headers: _client.wsHeaders,
    );
    return IOWebSocketChannel(ws);
  }

  Future<void> _connectStream() async {
    if (kIsWeb ||
        !_client.supportsWebSocket ||
        !_running ||
        _wsConnecting ||
        _ws != null) {
      return;
    }
    _wsConnecting = true;
    try {
      final ws = await _openRuntimeStream();
      _ws = ws;
      ws.stream.listen(
        (raw) {
          try {
            final event = jsonDecode(raw as String) as Map<String, dynamic>;
            final type = event['type']?.toString() ?? '';
            if (type == 'runtime.heartbeat') return;
            if (type == 'delight.candidate' || type == 'delight.liked') {
              unawaited(_loadDelights());
            }
            if (type == 'refresh.pool_updated' &&
                event['pool_available_count'] is num &&
                event['platform_available_counts'] is Map) {
              _applyPoolStatus(
                PlatformAvailability.fromJson({
                  'total_available': event['pool_available_count'],
                  'by_platform': event['platform_available_counts'],
                  'pool_status_version': event['pool_status_version'],
                }),
              );
              return;
            }
            if (type == 'refresh.pool_updated' || type.isNotEmpty) {
              // 实时事件先直接刷新顶部状态；_poll() 可能因为正在轮询而早退，
              // 如果只依赖 _poll() 会让“当前可换 / 最近补进 / 现在在忙”这些
              // 条目不及时更新。
              unawaited(_loadRuntimeStatus());
              unawaited(_poll());
            }
          } catch (_) {}
        },
        onDone: () {
          _ws = null;
          _scheduleReconnect();
        },
        onError: (_) {
          _ws = null;
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _wsConnecting = false;
    }
  }

  void _scheduleReconnect() {
    if (!_running || !_client.supportsWebSocket || _reconnectTimer != null) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      _reconnectTimer = null;
      unawaited(_connectStream());
    });
  }

  String _message(Object error, String fallback) {
    if (error is ApiException) return error.message;
    final text = error.toString().trim();
    final lower = text.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('connection failed') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused')) {
      return '$fallback：暂时连不上后端，将自动重试。';
    }
    if (lower.contains('timeoutexception') || lower.contains('timed out')) {
      return '$fallback：连接超时，将自动重试。';
    }
    return text.isEmpty ? fallback : text;
  }

  @override
  void dispose() {
    _disposed = true;
    _pollGeneration += 1; // Stop any in-flight poll/WS work.
    stopPolling();
    super.dispose();
  }
}
