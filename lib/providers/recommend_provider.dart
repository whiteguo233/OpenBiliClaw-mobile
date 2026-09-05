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
  bool _online = false;
  bool _polling = false;
  String _error = '';
  String _platformFilter = '';
  RuntimeStatus _runtimeStatus = const RuntimeStatus();
  ActivityFeed _activityFeed = const ActivityFeed();
  Timer? _pollTimer;
  WebSocketChannel? _ws;
  Timer? _reconnectTimer;
  bool _wsConnecting = false;
  bool _running = false;
  int _pollGeneration = 0;
  bool _disposed = false;

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
  bool get online => _online;
  String get error => _error;
  RuntimeStatus get runtimeStatus => _runtimeStatus;
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
    if (_loading) return;
    _loading = true;
    _error = '';
    _safeNotify();
    try {
      final recs = await _api.fetch();
      _recommendations = recs;
      _online = true;
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
  /// 再拉取最新列表。避免只重新 GET 当前列表导致内容看起来“没变化”。
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = '';
    _safeNotify();
    try {
      await _api.refresh();
      final recs = await _api.fetch();
      _recommendations = recs;
      _online = true;
      _prunePlatformFilter();
    } catch (error) {
      _online = false;
      _error = _message(error, '推荐刷新失败');
    } finally {
      _loading = false;
      _safeNotify();
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

  /// 推荐池中已出现的平台（按固定顺序去重）。
  List<String> get availablePlatforms {
    final seen = <String>{};
    for (final item in _recommendations) {
      final slug = item.sourcePlatform.trim().toLowerCase();
      if (slug.isNotEmpty) seen.add(slug);
    }
    final known = _platformLabels.map((entry) => entry.$1);
    final ordered = <String>[
      ...known.where(seen.contains),
      ...seen.difference(known.toSet()).toList()..sort(),
    ];
    return ordered;
  }

  /// 只有单一来源时不显示平台选择（用户要求：一个来源直接刷）。
  bool get showPlatformChoice => availablePlatforms.length > 1;

  void setPlatformFilter(String slug) {
    final next = slug.trim().toLowerCase();
    if (_platformFilter == next) return;
    _platformFilter = next;
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
  }

  Future<void> _loadSideChannels() async {
    await Future.wait([
      _loadRuntimeStatus(),
      _loadActivityFeed(),
      _loadDelights(),
    ]);
  }

  Future<void> _loadRuntimeStatus() async {
    try {
      _runtimeStatus = await _api.fetchRuntimeStatus();
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
    if (_reshuffling || _loading) return;
    _reshuffling = true;
    _error = '';
    _safeNotify();
    try {
      final excluded = _recommendations.map((item) => item.bvid).toList();
      final next = await _api.reshuffle(excluded);
      if (next.isNotEmpty) _recommendations = next;
      _online = true;
      unawaited(_loadRuntimeStatus());
    } catch (error) {
      _error = _message(error, '换一批失败');
    } finally {
      _reshuffling = false;
      _safeNotify();
    }
  }

  Future<void> append() async {
    if (_loadingMore || _loading || _reshuffling) return;
    _loadingMore = true;
    _error = '';
    _safeNotify();
    try {
      final excluded = _recommendations.map((item) => item.bvid).toList();
      final newItems = await _api.append(excluded);
      final identities = _recommendations
          .map((item) => item.savedIdentity)
          .toSet();
      for (final item in newItems) {
        if (identities.add(item.savedIdentity)) _recommendations.add(item);
      }
      _online = true;
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
      await _api.submitFeedback(rec.id, type, note: note);
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
      final recs = await _api.fetch(timeout: 8);
      if (_recommendations.isEmpty && recs.isNotEmpty) {
        _recommendations = recs;
      }
      _online = true;
      _error = '';
      if (_delights.isEmpty) await _loadDelights();
      if (_activityFeed.items.isEmpty &&
          _activityFeed.headline.isEmpty &&
          _activityFeed.liveSummary.isEmpty) {
        await _loadActivityFeed();
      }
      await _loadRuntimeStatus();
      _safeNotify();
    } catch (_) {
      if (_online) {
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
