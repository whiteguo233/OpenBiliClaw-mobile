import '../models/chat.dart';
import 'client.dart';

class ChatApi {
  final ApiClient _client;
  ChatApi(this._client);

  Future<ChatTurn> startTurn({String session = 'mobile', required String message}) async {
    final data = await _client.post('/chat/turns', body: {
      'session': session,
      'message': message,
    });
    return ChatTurn.fromJson(data);
  }

  Future<ChatTurn> fetchTurn(String turnId) async {
    final data = await _client.get('/chat/turns/${Uri.encodeComponent(turnId)}');
    return ChatTurn.fromJson(data);
  }

  Future<List<ChatTurn>> fetchTurns({String session = 'mobile', String scope = '', int limit = 50}) async {
    final qs = '?session=${Uri.encodeComponent(session)}${scope.isNotEmpty ? '&scope=${Uri.encodeComponent(scope)}' : ''}&limit=$limit';
    final data = await _client.get('/chat/turns$qs');
    return (data['turns'] as List?)?.map((e) => ChatTurn.fromJson(e)).toList() ?? [];
  }
}
