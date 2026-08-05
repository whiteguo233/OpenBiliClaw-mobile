import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/client.dart';
import '../api/chat_api.dart';
import '../models/chat.dart';

class ChatProvider extends ChangeNotifier {
  final ChatApi _api;

  List<ChatTurn> _turns = [];
  bool _loading = false;
  bool _responding = false;

  ChatProvider(ApiClient client) : _api = ChatApi(client);

  List<ChatTurn> get turns => _turns;
  bool get loading => _loading;
  bool get responding => _responding;

  Future<void> loadTurns() async {
    _loading = true;
    notifyListeners();
    try {
      _turns = await _api.fetchTurns(session: 'popup', limit: 50);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty || _responding) return;
    _responding = true;
    final userTurn = ChatTurn(turnId: DateTime.now().millisecondsSinceEpoch.toString(), message: message, status: 'done');
    _turns.add(userTurn);
    notifyListeners();

    try {
      final result = await _api.startTurn(message: message, session: 'popup');
      await _pollForResponse(result.turnId);
    } catch (e) {
      _turns.add(ChatTurn(turnId: 'err-${DateTime.now().millisecondsSinceEpoch}', status: 'error', message: '抱歉，我暂时没接上。', error: e.toString()));
    }
    _responding = false;
    notifyListeners();
  }

  void cancelResponse() {
    if (!_responding) return;
    _responding = false;
    notifyListeners();
  }

  Future<void> _pollForResponse(String turnId) async {
    for (var i = 0; i < 180; i++) {
      if (!_responding) return;
      await Future.delayed(const Duration(seconds: 2));
      try {
        final turn = await _api.fetchTurn(turnId);
        if (turn.isDone || turn.hasError) {
          _replaceLastTurn(turn);
          notifyListeners();
          return;
        }
      } catch (_) {}
    }
    _replaceLastTurn(ChatTurn(turnId: 'timeout-${DateTime.now().millisecondsSinceEpoch}',
        status: 'error', message: '等待超时，可能是后端 LLM 比较慢，等一下再试。'));
    notifyListeners();
  }

  void _replaceLastTurn(ChatTurn turn) {
    if (_turns.isNotEmpty) {
      _turns[_turns.length - 1] = turn;
    } else {
      _turns.add(turn);
    }
  }
}
