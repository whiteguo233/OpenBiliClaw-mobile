import 'client.dart';

/// Thin client for the backend `/api/config` surface used by the mobile
/// settings page (saved-sync auto-sync toggle), mirroring the web clients'
/// `fetchConfig` / `updateConfig`.
class ConfigApi {
  final ApiClient _client;
  ConfigApi(this._client);

  Future<Map<String, dynamic>> fetch() {
    return _client.get('/config', timeout: 10);
  }

  Future<Map<String, dynamic>> update(Map<String, dynamic> patch) {
    return _client.put('/config', body: patch, timeout: 30);
  }

  /// Read whether saved items auto-sync to their platform on save.
  Future<bool> savedAutoSyncEnabled() async {
    try {
      final data = await fetch();
      final savedSync = data['saved_sync'];
      if (savedSync is Map) {
        return savedSync['auto_sync_enabled'] == true;
      }
    } catch (_) {}
    return false;
  }

  /// Set whether saved items auto-sync to their platform on save.
  /// Returns true when the backend accepted the change.
  Future<bool> setSavedAutoSync(bool enabled) async {
    try {
      final data = await fetch();
      final savedSync = data['saved_sync'];
      final current = savedSync is Map
          ? Map<String, dynamic>.from(savedSync)
          : <String, dynamic>{};
      current['auto_sync_enabled'] = enabled;
      final updated = await update({'saved_sync': current});
      final result = updated['saved_sync'];
      if (result is Map) return result['auto_sync_enabled'] == enabled;
      return true;
    } catch (_) {
      return false;
    }
  }
}
