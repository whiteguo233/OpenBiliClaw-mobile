import 'dart:async';
import 'dart:convert';
// ponytail: dart:io WebSocket 仅原生平台（移动/桌面）；web 平台跑不了就退化轮询，需要 web 支持时换 web_socket_channel
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../api/client.dart';
import '../api/recommend_api.dart';
import '../models/recommendation.dart';
import '../models/delight.dart';

class RecommendProvider extends ChangeNotifier {
  final RecommendApi _api;
  final ApiClient _client;

  List<Recommendation> _recommendations = [];
  List<Delight> _delights = [];
  int _delightIndex = 0;
  bool _loading = false;
  bool _online = false;
  Timer? _pollTimer;
  WebSocket? _ws;
  Timer? _reconnectTimer;
  bool _wsConnecting = false;

  RecommendProvider(ApiClient client)
      : _client = client,
        _api = RecommendApi(client);

  List<Recommendation> get recommendations => _recommendations;
  List<Delight> get delights => _delights;
  int get delightIndex => _delightIndex;
  bool get loading => _loading;
  bool get online => _online;

  void nextDelight() {
    if (_delights.isNotEmpty) _delightIndex = (_delightIndex + 1) % _delights.length;
    notifyListeners();
  }

  void prevDelight() {
    if (_delights.isNotEmpty) _delightIndex = (_delightIndex - 1 + _delights.length) % _delights.length;
    notifyListeners();
  }

  String? contentUrlFor(Recommendation rec) {
    if (rec.contentUrl.isNotEmpty) return rec.contentUrl;
    if (rec.bvid.isNotEmpty) return 'https://www.bilibili.com/video/${rec.bvid}';
    return null;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      final recs = await _api.fetch();
      _recommendations = recs;
      _delights = await _api.fetchDelights(limit: 10);
      _delightIndex = 0;
      _online = true;
    } catch (_) {
      _online = false;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> append() async {    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final excluded = _recommendations.map((r) => r.bvid).toList();
      final data = await _api.append(excluded);
      final newItems = (data['items'] as List?)?.map((e) => Recommendation.fromJson(e)).toList() ?? [];
      final existingBvids = _recommendations.map((r) => r.bvid).toSet();
      for (final item in newItems) {
        if (!existingBvids.contains(item.bvid)) {
          _recommendations.add(item);
          existingBvids.add(item.bvid);
        }
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> submitFeedback(Recommendation rec, String type, {String? note}) async {
    await _api.submitFeedback(rec.id, rec.bvid, type, note: note);
    for (var r in _recommendations) {
      if (r.bvid == rec.bvid) r.feedbackType = type;
    }
    notifyListeners();
  }

  Future<void> respondToDelight(String bvid, String response, {String message = ''}) async {
    await _api.respondToDelight(bvid, response, message: message);
    _delights.removeWhere((d) => d.bvid == bvid);
    _delightIndex = _delightIndex.clamp(0, (_delights.length - 1).clamp(0, _delights.length));
    notifyListeners();
  }

  Future<void> reportClick(Recommendation rec) async {
    await _api.reportClick({'recommendation_id': rec.id, 'bvid': rec.bvid, 'title': rec.title, 'up_name': rec.upName, 'source_platform': rec.sourcePlatform, 'content_url': rec.contentUrl});
  }

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
    _connectStream();
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _ws?.close();
    _ws = null;
  }

  Future<void> _poll() async {
    try {
      final status = await _api.fetch(timeout: 5);
      _online = true;
      if (_delights.isEmpty) {
        final delights = await _api.fetchDelights(limit: 10);
        if (delights.isNotEmpty) {
          _delights = delights;
          _delightIndex = 0;
          notifyListeners();
        }
      }
    } catch (_) {
      _online = false;
      notifyListeners();
    }
  }

  Future<void> _connectStream() async {
    if (_wsConnecting || _ws != null) return;
    _wsConnecting = true;
    try {
      final ws = await WebSocket.connect(_client.wsUrl, headers: _client.wsHeaders);
      _ws = ws;
      ws.listen((raw) {
        try {
          final event = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = event['type'] as String? ?? '';
          if (type.isNotEmpty && type != 'runtime.heartbeat') _poll();
        } catch (_) {}
      }, onDone: () {
        _ws = null;
        _scheduleReconnect();
      }, onError: (_) {
        _ws = null;
        _scheduleReconnect();
      });
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _wsConnecting = false;
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      _reconnectTimer = null;
      _connectStream();
    });
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
