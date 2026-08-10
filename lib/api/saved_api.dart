import 'client.dart';
import '../models/saved_item.dart';

class SavedApi {
  final ApiClient _client;
  SavedApi(this._client);

  String _path(SavedListKind kind) => '/saved/${kind.apiValue}';

  Future<Map<String, dynamic>> save(SavedListKind kind, SavedItem item) {
    return _client.post(_path(kind), body: item.toSavePayload());
  }

  Future<Map<String, dynamic>> remove(SavedListKind kind, String itemKey) {
    return _client.post('${_path(kind)}/remove', body: {'item_key': itemKey});
  }

  Future<List<SavedItem>> fetch(
    SavedListKind kind, {
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client.get(
      '${_path(kind)}?limit=$limit&offset=$offset',
    );
    final rawItems = data['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map((item) => SavedItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, dynamic>> status(SavedListKind kind, String itemKey) {
    return _client.get(
      '${_path(kind)}/status?item_key=${Uri.encodeQueryComponent(itemKey)}',
    );
  }

  Future<Map<String, dynamic>> sync(SavedListKind kind, List<String> itemKeys) {
    return _client.post(
      '${_path(kind)}/sync',
      body: {'item_keys': itemKeys.toSet().toList()},
      timeout: 30,
    );
  }

  Future<Map<String, dynamic>> pollSync(String taskId) {
    return _client.get(
      '/saved-sync/tasks/${Uri.encodeComponent(taskId)}',
      timeout: 15,
    );
  }
}
