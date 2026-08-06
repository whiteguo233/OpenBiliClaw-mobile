import 'client.dart';

class SavedApi {
  final ApiClient _client;
  SavedApi(this._client);

  Future<void> addToWatchLater(String bvid) => _client.post('/watch-later', body: {'bvid': bvid});
  Future<void> removeFromWatchLater(String bvid) => _client.delete('/watch-later/${Uri.encodeComponent(bvid)}');

  Future<List<Map<String, dynamic>>> fetchWatchLater({int limit = 50, int offset = 0}) async {
    final data = await _client.get('/watch-later?limit=$limit&offset=$offset');
    return (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<void> addToFavorite(String bvid) => _client.post('/favorites', body: {'bvid': bvid});
  Future<void> removeFromFavorite(String bvid) => _client.delete('/favorites/${Uri.encodeComponent(bvid)}');

  Future<List<Map<String, dynamic>>> fetchFavorites({int limit = 50, int offset = 0}) async {
    final data = await _client.get('/favorites?limit=$limit&offset=$offset');
    return (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }
}
