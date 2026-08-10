import '../models/chat.dart';
import 'client.dart';

class ChatApi {
  final ApiClient _client;
  ChatApi(this._client);

  Future<ChatTurn> startTurn({
    String turnId = '',
    String session = 'popup',
    String scope = 'chat',
    String subjectId = '',
    String subjectTitle = '',
    String replyToTurnId = '',
    required String message,
  }) async {
    final data = await _client.post(
      '/chat/turns',
      body: {
        'turn_id': turnId,
        'session': session,
        'scope': scope,
        'subject_id': subjectId,
        'subject_title': subjectTitle,
        'reply_to_turn_id': replyToTurnId,
        'message': message,
      },
      timeout: 35,
    );
    return ChatTurn.fromJson(data);
  }

  Future<ChatTurn> fetchTurn(String turnId) async {
    final data = await _client.get(
      '/chat/turns/${Uri.encodeComponent(turnId)}',
      timeout: 10,
    );
    return ChatTurn.fromJson(data);
  }

  Future<List<ChatTurn>> fetchTurns({
    String session = 'popup',
    String scope = '',
    int limit = 100,
  }) async {
    final query = <String, String>{
      'session': session,
      'limit': limit.toString(),
      if (scope.isNotEmpty) 'scope': scope,
    };
    final suffix = Uri(queryParameters: query).query;
    final data = await _client.get('/chat/turns?$suffix', timeout: 12);
    final rawItems = data['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map((item) => ChatTurn.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<PendingConfirmation>> fetchPendingConfirmations() async {
    final data = await _client.get(
      '/chat/pending-confirmations?session=popup',
      timeout: 10,
    );
    final rawItems = data['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map(
          (item) =>
              PendingConfirmation.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<ChatTurn> openPendingConfirmation(String ref) async {
    final data = await _client.post(
      '/chat/pending-confirmations/${Uri.encodeComponent(ref)}/open',
      body: const {'session': 'popup'},
      timeout: 60,
    );
    return ChatTurn.fromJson(data);
  }

  Future<Map<String, dynamic>> actOnCard(String turnId, String action) {
    return _client.post(
      '/chat/cards/${Uri.encodeComponent(turnId)}/action',
      body: {'action': action},
      timeout: 65,
    );
  }

  Future<DialogueContext> fetchContext(String turnId) async {
    final data = await _client.get(
      '/chat/contexts/${Uri.encodeComponent(turnId)}',
      timeout: 10,
    );
    return DialogueContext.fromJson(data);
  }
}
