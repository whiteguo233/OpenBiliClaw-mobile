import '../api/utils.dart';

class ChatTurn {
  final String turnId;
  final String session;
  final String scope;
  final String message;
  final String reply;
  final String status;
  final String error;
  final String createdAt;

  ChatTurn({
    required this.turnId,
    this.session = 'popup',
    this.scope = 'chat',
    this.message = '',
    this.reply = '',
    this.status = 'pending',
    this.error = '',
    this.createdAt = '',
  });

  factory ChatTurn.fromJson(Map<String, dynamic> json) => ChatTurn(
    turnId: json['turn_id'] ?? '',
    session: json['session'] ?? 'popup',
    scope: json['scope'] ?? 'chat',
    message: decodeHtml(json['message'] ?? ''),
    reply: decodeHtml(json['reply'] ?? ''),
    status: json['status'] ?? 'pending',
    error: decodeHtml(json['error'] ?? ''),
    createdAt: json['created_at'] ?? '',
  );

  bool get isDone => status == 'done' || status == 'ok' || status == 'completed';
  bool get hasError => status == 'error' || status == 'failed' || error.isNotEmpty;
  bool get isPending => status == 'pending' || status == 'processing';
}
