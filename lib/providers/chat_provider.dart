import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/chat_api.dart';
import '../api/client.dart';
import '../models/chat.dart';

class ChatProvider extends ChangeNotifier {
  final ChatApi _api;
  final Random _random = Random();

  List<ChatTurn> _turns = [];
  List<PendingConfirmation> _pendingConfirmations = [];
  final Set<String> _busyCardIds = {};
  final Set<String> _busyConfirmationRefs = {};
  bool _loading = false;
  bool _responding = false;
  bool _syncingHistory = false;
  String _error = '';
  String _historySignature = '';
  String _pendingSignature = '';
  int _responseGeneration = 0;
  Timer? _historyTimer;
  DialogueContext? _dialogueContext;
  ChatComposeContext _composeContext = const ChatComposeContext();
  bool _disposed = false;
  static const int _historyPageSize = 30;
  static const int _historyMaxLimit = 200;
  int _historyLimit = _historyPageSize;
  bool _loadingOlder = false;
  bool _hasMoreHistory = true;

  ChatProvider(ApiClient client) : _api = ChatApi(client);

  /// Notifies listeners unless the provider has already been disposed.
  ///
  /// In-flight async work (e.g. the periodic history sync) can complete after
  /// the owning widget tree is torn down; calling [ChangeNotifier.notifyListeners]
  /// on a disposed notifier throws, so all notifications go through here.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  List<ChatTurn> get turns {
    const mainScopes = {
      'chat',
      'hypothesis',
      'confusion',
      'probe',
      'avoidance_probe',
    };
    return List.unmodifiable(
      _turns.where((turn) {
        if (mainScopes.contains(turn.scope)) return true;
        return turn.scope == _composeContext.scope &&
            turn.subjectId == _composeContext.subjectId;
      }),
    );
  }

  List<PendingConfirmation> get pendingConfirmations =>
      List.unmodifiable(_pendingConfirmations);
  int get pendingCount => _pendingConfirmations.length;
  bool get loading => _loading;
  bool get loadingOlder => _loadingOlder;
  bool get hasMoreHistory => _hasMoreHistory;
  bool get responding => _responding;
  String get error => _error;
  DialogueContext? get dialogueContext => _dialogueContext;
  ChatComposeContext get composeContext => _composeContext;
  bool cardBusy(String turnId) => _busyCardIds.contains(turnId);
  bool confirmationBusy(String ref) => _busyConfirmationRefs.contains(ref);

  void clearError() {
    if (_error.isEmpty) return;
    _error = '';
    _safeNotify();
  }

  Future<void> loadTurns({bool showLoading = true}) async {
    if (_syncingHistory || _loadingOlder) return;
    _syncingHistory = true;
    var changed = false;
    if (showLoading) {
      _loading = true;
      _safeNotify();
    }
    try {
      final fetched = await _api.fetchTurns(
        session: 'popup',
        limit: _historyLimit,
      );
      _hasMoreHistory =
          fetched.length >= _historyLimit && _historyLimit < _historyMaxLimit;
      final fetchedIds = fetched.map((turn) => turn.turnId).toSet();
      final localPending = _turns
          .where(
            (turn) =>
                turn.isPending &&
                turn.turnId.isNotEmpty &&
                !fetchedIds.contains(turn.turnId),
          )
          .toList();
      final nextTurns = [...fetched, ...localPending];
      final nextSignature = _turnSignature(nextTurns);
      if (nextSignature != _historySignature) {
        _turns = nextTurns;
        _historySignature = nextSignature;
        changed = true;
      }
      if (_error.isNotEmpty) {
        _error = '';
        changed = true;
      }
      changed = await _loadPendingConfirmations() || changed;
    } catch (error) {
      final nextError = _message(error, '对话历史加载失败');
      if (_error != nextError) {
        _error = nextError;
        changed = true;
      }
    } finally {
      _syncingHistory = false;
      final wasLoading = _loading;
      _loading = false;
      if (changed || wasLoading) _safeNotify();
    }
  }

  Future<void> loadPendingConfirmations({bool notify = true}) async {
    final changed = await _loadPendingConfirmations();
    if (changed && notify) _safeNotify();
  }

  Future<bool> _loadPendingConfirmations() async {
    try {
      final items = await _api.fetchPendingConfirmations();
      final signature = items
          .map((item) => '${item.kind}|${item.ref}|${item.title}')
          .join('\n');
      if (signature == _pendingSignature) return false;
      _pendingConfirmations = items;
      _pendingSignature = signature;
      return true;
    } catch (_) {
      // Keep the last good work-list while the backend reconnects.
      return false;
    }
  }

  /// 往上滑到历史顶部时，按页扩大后端 limit 拉取更早的对话。
  Future<void> loadOlderTurns() async {
    if (_syncingHistory || _loadingOlder || !_hasMoreHistory) return;
    if (_historyLimit >= _historyMaxLimit) return;
    _loadingOlder = true;
    _error = '';
    _safeNotify();
    try {
      final nextLimit = min(_historyLimit + _historyPageSize, _historyMaxLimit);
      final fetched = await _api.fetchTurns(session: 'popup', limit: nextLimit);
      final fetchedIds = fetched.map((turn) => turn.turnId).toSet();
      final localPending = _turns
          .where(
            (turn) =>
                turn.isPending &&
                turn.turnId.isNotEmpty &&
                !fetchedIds.contains(turn.turnId),
          )
          .toList();
      _turns = [...fetched, ...localPending];
      _historyLimit = nextLimit;
      _historySignature = _turnSignature(_turns);
      _hasMoreHistory =
          fetched.length >= nextLimit && nextLimit < _historyMaxLimit;
      _safeNotify();
    } catch (error) {
      _error = _message(error, '更多对话加载失败');
      _safeNotify();
    } finally {
      _loadingOlder = false;
      _safeNotify();
    }
  }

  void startHistorySync() {
    _historyTimer?.cancel();
    unawaited(loadTurns(showLoading: _turns.isEmpty));
    _historyTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => loadTurns(showLoading: false),
    );
  }

  void stopHistorySync() {
    _historyTimer?.cancel();
    _historyTimer = null;
  }

  void startContextualChat(
    String scope,
    String subjectId,
    String subjectTitle,
  ) {
    _dialogueContext = null;
    _composeContext = ChatComposeContext(
      scope: scope.isEmpty ? 'chat' : scope,
      subjectId: subjectId,
      subjectTitle: subjectTitle,
    );
    _safeNotify();
  }

  void clearComposeContext() {
    _composeContext = const ChatComposeContext();
    _safeNotify();
  }

  void clearDialogueContext() {
    _dialogueContext = null;
    _safeNotify();
  }

  Future<bool> sendMessage(String message) async {
    final value = message.trim();
    if (value.isEmpty || _responding) return false;
    _responding = true;
    _error = '';
    final generation = ++_responseGeneration;
    final turnId = _newTurnId();
    final replyContext = _dialogueContext;
    final contextual = _composeContext;
    final scope = replyContext == null ? contextual.scope : 'chat';
    final subjectId = replyContext == null ? contextual.subjectId : '';
    final subjectTitle = replyContext == null ? contextual.subjectTitle : '';
    final optimistic = ChatTurn(
      turnId: turnId,
      scope: scope,
      subjectId: subjectId,
      subjectTitle: subjectTitle,
      replyToTurnId: replyContext?.replyToTurnId ?? '',
      message: value,
      status: 'pending',
      createdAt: DateTime.now().toIso8601String(),
    );
    _turns.add(optimistic);
    _safeNotify();

    try {
      final started = await _api.startTurn(
        turnId: turnId,
        session: 'popup',
        scope: scope,
        subjectId: subjectId,
        subjectTitle: subjectTitle,
        replyToTurnId: replyContext?.replyToTurnId ?? '',
        message: value,
      );
      _upsertTurn(started);
      _safeNotify();
      if (started.isPending) {
        await _pollForResponse(started.turnId, generation);
      }
      if (generation == _responseGeneration) {
        await loadPendingConfirmations(notify: false);
      }
      return !(_turnById(turnId)?.hasError ?? false);
    } catch (error) {
      final message = _message(error, '这句没有发送成功，请重试');
      _upsertTurn(optimistic.copyWith(status: 'failed', error: message));
      _error = message;
      return false;
    } finally {
      if (generation == _responseGeneration) {
        _responding = false;
      }
      _safeNotify();
    }
  }

  void cancelResponse() {
    if (!_responding) return;
    _responseGeneration += 1;
    _responding = false;
    _safeNotify();
  }

  Future<void> _pollForResponse(String turnId, int generation) async {
    const backoff = [1, 2, 2, 5, 5, 5, 5, 5];
    for (final seconds in backoff) {
      if (generation != _responseGeneration) return;
      await Future<void>.delayed(Duration(seconds: seconds));
      if (generation != _responseGeneration) return;
      try {
        final turn = await _api.fetchTurn(turnId);
        _upsertTurn(turn);
        _safeNotify();
        if (turn.isDone || turn.hasError) return;
      } catch (_) {
        // A transient read failure is retried inside the fixed 30s window.
      }
    }
    _error = '回复仍在后台处理中，稍后会从共享历史自动恢复。';
  }

  Future<bool> openPendingConfirmation(PendingConfirmation item) async {
    if (_busyConfirmationRefs.contains(item.ref)) return false;
    _busyConfirmationRefs.add(item.ref);
    _error = '';
    _safeNotify();
    try {
      final turn = await _api.openPendingConfirmation(item.ref);
      _upsertTurn(turn);
      await selectDialogueContext(turn.turnId);
      await loadPendingConfirmations(notify: false);
      return true;
    } catch (error) {
      _error = _message(error, '这条待聊内容暂时打不开');
      return false;
    } finally {
      _busyConfirmationRefs.remove(item.ref);
      _safeNotify();
    }
  }

  Future<bool> selectDialogueContext(String turnId) async {
    try {
      final context = await _api.fetchContext(turnId);
      if (!context.valid) throw const FormatException('invalid context');
      _composeContext = const ChatComposeContext();
      _dialogueContext = context;
      _safeNotify();
      return true;
    } catch (error) {
      _error = _message(error, '无法进入这条对话上下文');
      _safeNotify();
      return false;
    }
  }

  Future<bool> actOnCard(ChatTurn turn, String action) async {
    if (_busyCardIds.contains(turn.turnId)) return false;
    _busyCardIds.add(turn.turnId);
    _error = '';
    _safeNotify();
    try {
      final response = await _api.actOnCard(turn.turnId, action);
      final outcome = response['outcome']?.toString() ?? '';
      if (outcome == 'processing' || response['state'] == 'processing') {
        await _pollCard(turn.turnId);
      } else {
        await _refreshTurn(turn.turnId);
      }
      if (action == 'discuss') {
        final rawPreview = response['context_preview'];
        if (rawPreview is Map) {
          final context = DialogueContext.fromJson(
            Map<String, dynamic>.from(rawPreview),
          );
          if (context.valid) _dialogueContext = context;
        }
        if (_dialogueContext == null) {
          await selectDialogueContext(turn.turnId);
        }
      } else if (_dialogueContext?.replyToTurnId == turn.turnId) {
        _dialogueContext = null;
      }
      await loadPendingConfirmations(notify: false);
      return true;
    } catch (error) {
      _error = _message(error, '猜测卡操作失败，请重试');
      return false;
    } finally {
      _busyCardIds.remove(turn.turnId);
      _safeNotify();
    }
  }

  Future<void> _pollCard(String turnId) async {
    const delays = [1, 2, 5, 5, 5, 5, 5];
    for (final delay in delays) {
      await Future<void>.delayed(Duration(seconds: delay));
      final turn = await _api.fetchTurn(turnId);
      _upsertTurn(turn);
      _safeNotify();
      if (turn.cardTerminal || turn.hasError) return;
    }
    throw TimeoutException('卡片仍在后台处理中');
  }

  Future<void> _refreshTurn(String turnId) async {
    try {
      _upsertTurn(await _api.fetchTurn(turnId));
    } catch (_) {
      await loadTurns(showLoading: false);
    }
  }

  ChatTurn? _turnById(String turnId) {
    for (final turn in _turns) {
      if (turn.turnId == turnId) return turn;
    }
    return null;
  }

  void _upsertTurn(ChatTurn turn) {
    final index = _turns.indexWhere((item) => item.turnId == turn.turnId);
    if (index < 0) {
      _turns.add(turn);
    } else {
      _turns[index] = turn;
    }
    _historySignature = _turnSignature(_turns);
  }

  String _turnSignature(List<ChatTurn> turns) {
    return turns
        .map(
          (turn) => [
            turn.turnId,
            turn.status,
            turn.updatedAt,
            turn.reply.length,
            turn.error,
            turn.cardState,
            turn.replyToTurnId,
          ].join('|'),
        )
        .join('\n');
  }

  String _newTurnId() {
    final random = _random.nextInt(1 << 32).toRadixString(36);
    return 'mobile-${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  String _message(Object error, String fallback) {
    if (error is ApiException) return error.message;
    final text = error.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  @override
  void dispose() {
    _disposed = true;
    _responseGeneration += 1; // Stop any in-flight response polling.
    stopHistorySync();
    super.dispose();
  }
}
