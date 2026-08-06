import 'package:flutter/foundation.dart';
import '../api/client.dart';
import '../api/profile_api.dart';
import '../models/profile.dart';

class ProfileProvider extends ChangeNotifier {
  final ProfileApi _api;

  ProfileSummary? _summary;
  bool _loading = false;
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _probes = [];
  List<Map<String, dynamic>> _avoidanceProbes = [];

  ProfileProvider(ApiClient client) : _api = ProfileApi(client);

  ProfileSummary? get summary => _summary;
  bool get loading => _loading;
  List<Map<String, dynamic>> get notifications => _notifications;
  List<Map<String, dynamic>> get probes => _probes;
  List<Map<String, dynamic>> get avoidanceProbes => _avoidanceProbes;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _summary = await _api.fetchSummary();
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> loadNotifications() async {
    try {
      _notifications = await _api.fetchPendingNotifications();
      _probes = await _api.fetchPendingProbes();
      _avoidanceProbes = await _api.fetchPendingAvoidanceProbes();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> respondToProbe(String domain, String response) async {
    try {
      await _api.respondToProbe(domain, response);
      _probes.removeWhere((p) => p['domain'] == domain);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> respondToAvoidanceProbe(String domain, String response) async {
    try {
      await _api.respondToAvoidanceProbe(domain, response);
      _avoidanceProbes.removeWhere((p) => p['domain'] == domain);
      notifyListeners();
    } catch (_) {}
  }
}
