import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/profile_api.dart';
import '../models/profile.dart';

class ProfileProvider extends ChangeNotifier {
  final ProfileApi _api;

  ProfileSummary? _summary;
  List<ProfileCognitionUpdate> _cognitionUpdates = [];
  bool _loading = false;
  bool _loadingMoreCognition = false;
  bool _loadingEditState = false;
  String _error = '';
  Map<String, dynamic>? _cognitionNotification;
  List<Map<String, dynamic>> _probes = [];
  List<Map<String, dynamic>> _avoidanceProbes = [];
  Map<String, dynamic>? _editState;
  final Set<String> _busyProbeKeys = {};

  ProfileProvider(ApiClient client) : _api = ProfileApi(client);

  ProfileSummary? get summary => _summary;
  List<ProfileCognitionUpdate> get cognitionUpdates =>
      List.unmodifiable(_cognitionUpdates);
  bool get loading => _loading;
  bool get loadingMoreCognition => _loadingMoreCognition;
  bool get loadingEditState => _loadingEditState;
  String get error => _error;
  Map<String, dynamic>? get cognitionNotification => _cognitionNotification;
  List<Map<String, dynamic>> get probes => List.unmodifiable(_probes);
  List<Map<String, dynamic>> get avoidanceProbes =>
      List.unmodifiable(_avoidanceProbes);
  Map<String, dynamic>? get editState => _editState;
  bool probeBusy(String domain, {required bool avoidance}) =>
      _busyProbeKeys.contains('${avoidance ? 'avoid' : 'like'}:$domain');

  void clearError() {
    if (_error.isEmpty) return;
    _error = '';
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _error = '';
    notifyListeners();
    try {
      _summary = await _api.fetchSummary(limit: 5);
      _cognitionUpdates = [...?_summary?.cognitionUpdates];
    } catch (error) {
      _error = _message(error, '画像加载失败');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadNotifications() async {
    try {
      final results = await Future.wait([
        _api.fetchPendingProbes(),
        _api.fetchPendingAvoidanceProbes(),
      ]);
      _probes = results[0];
      _avoidanceProbes = results[1];
      _cognitionNotification = await _api.fetchPendingCognitionUpdate();
      notifyListeners();
    } catch (error) {
      _error = _message(error, '画像待确认信息加载失败');
      notifyListeners();
    }
  }

  Future<bool> markCognitionSeen() async {
    final id = _cognitionNotification?['id']?.toString() ?? '';
    if (id.isEmpty) return true;
    try {
      await _api.markCognitionSeen(id);
      _cognitionNotification = null;
      notifyListeners();
      return true;
    } catch (error) {
      _error = _message(error, '认知更新确认失败');
      notifyListeners();
      return false;
    }
  }

  Future<bool> respondToProbe(String domain, String response) {
    return _respond(domain, response, avoidance: false);
  }

  Future<bool> respondToAvoidanceProbe(String domain, String response) {
    return _respond(domain, response, avoidance: true);
  }

  Future<bool> _respond(
    String domain,
    String response, {
    required bool avoidance,
  }) async {
    final key = '${avoidance ? 'avoid' : 'like'}:$domain';
    if (_busyProbeKeys.contains(key)) return false;
    _busyProbeKeys.add(key);
    _error = '';
    notifyListeners();
    try {
      if (avoidance) {
        await _api.respondToAvoidanceProbe(domain, response);
        _avoidanceProbes.removeWhere((item) => item['domain'] == domain);
      } else {
        await _api.respondToProbe(domain, response);
        _probes.removeWhere((item) => item['domain'] == domain);
      }
      _summary = await _api.fetchSummary(limit: 5);
      _cognitionUpdates = [...?_summary?.cognitionUpdates];
      return true;
    } catch (error) {
      _error = _message(error, '探测反馈提交失败');
      return false;
    } finally {
      _busyProbeKeys.remove(key);
      notifyListeners();
    }
  }

  Future<void> loadMoreCognition() async {
    final summary = _summary;
    if (summary == null ||
        !summary.hasMoreCognitionUpdates ||
        summary.nextCognitionCursor.isEmpty ||
        _loadingMoreCognition) {
      return;
    }
    _loadingMoreCognition = true;
    _error = '';
    notifyListeners();
    try {
      final next = await _api.fetchSummary(
        limit: 10,
        cursor: summary.nextCognitionCursor,
      );
      final seen = _cognitionUpdates
          .map((item) => '${item.createdAt}|${item.summary}')
          .toSet();
      for (final item in next.cognitionUpdates) {
        if (seen.add('${item.createdAt}|${item.summary}')) {
          _cognitionUpdates.add(item);
        }
      }
      _summary = next;
    } catch (error) {
      _error = _message(error, '更多认知记录加载失败');
    } finally {
      _loadingMoreCognition = false;
      notifyListeners();
    }
  }

  Future<bool> loadEditState() async {
    _loadingEditState = true;
    _error = '';
    notifyListeners();
    try {
      _editState = await _api.fetchEditState();
      return _editState?['initialized'] != false;
    } catch (error) {
      _error = _message(error, '画像编辑状态加载失败');
      return false;
    } finally {
      _loadingEditState = false;
      notifyListeners();
    }
  }

  Future<bool> applyEdit({
    required String target,
    required String operation,
    Object? value,
    String parent = '',
    double? weight,
  }) async {
    _error = '';
    try {
      final response = await _api.edit(
        target: target,
        operation: operation,
        value: value,
        parent: parent,
        weight: weight,
      );
      final nested = response['edit_state'];
      _editState = nested is Map ? Map<String, dynamic>.from(nested) : response;
      _summary = await _api.fetchSummary(limit: 5);
      _cognitionUpdates = [...?_summary?.cognitionUpdates];
      notifyListeners();
      return true;
    } catch (error) {
      _error = _message(error, '画像修改失败');
      notifyListeners();
      return false;
    }
  }

  String _message(Object error, String fallback) {
    if (error is ApiException) return error.message;
    final text = error.toString().trim();
    return text.isEmpty ? fallback : text;
  }
}
