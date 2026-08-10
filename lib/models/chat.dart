import '../api/utils.dart';

class ChatTurn {
  final String turnId;
  final String session;
  final String scope;
  final String subjectId;
  final String subjectTitle;
  final String replyToTurnId;
  final String message;
  final String reply;
  final String status;
  final String error;
  final Map<String, dynamic> payload;
  final String createdAt;
  final String updatedAt;

  const ChatTurn({
    required this.turnId,
    this.session = 'popup',
    this.scope = 'chat',
    this.subjectId = '',
    this.subjectTitle = '',
    this.replyToTurnId = '',
    this.message = '',
    this.reply = '',
    this.status = 'pending',
    this.error = '',
    this.payload = const {},
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory ChatTurn.fromJson(Map<String, dynamic> json) => ChatTurn(
    turnId: _text(json['turn_id']),
    session: _text(json['session']).isEmpty ? 'popup' : _text(json['session']),
    scope: _text(json['scope']).isEmpty ? 'chat' : _text(json['scope']),
    subjectId: _text(json['subject_id']),
    subjectTitle: decodeHtml(_text(json['subject_title'])),
    replyToTurnId: _text(json['reply_to_turn_id']),
    message: decodeHtml(_text(json['message'])),
    reply: decodeHtml(
      _text(json['reply']).isNotEmpty
          ? _text(json['reply'])
          : _text(json['response']),
    ),
    status: _text(json['status']).isEmpty ? 'pending' : _text(json['status']),
    error: decodeHtml(_text(json['error'])),
    payload: _map(json['payload']),
    createdAt: _text(json['created_at']),
    updatedAt: _text(json['updated_at']),
  );

  bool get isDone =>
      status == 'done' || status == 'ok' || status == 'completed';
  bool get hasError =>
      status == 'error' || status == 'failed' || error.isNotEmpty;
  bool get isPending => status == 'pending' || status == 'processing';
  bool get isCard => payload['type']?.toString() == 'card';
  bool get isQuestion => payload['type']?.toString() == 'question';
  String get cardKind => payload['kind']?.toString() ?? '';
  String get cardTitle => decodeHtml(
    (payload['title'] ?? (subjectTitle.isNotEmpty ? subjectTitle : message))
        .toString(),
  );
  String get cardState => payload['state']?.toString() ?? '';
  bool get cardTerminal => const {
    'confirmed',
    'rejected',
    'deferred',
    'revised',
  }.contains(cardState);
  List<String> get cardActions => _strings(payload['actions']);
  List<String> get evidence =>
      _strings(payload['evidence_refs']).take(5).toList();

  ChatTurn copyWith({
    String? status,
    String? error,
    Map<String, dynamic>? payload,
  }) => ChatTurn(
    turnId: turnId,
    session: session,
    scope: scope,
    subjectId: subjectId,
    subjectTitle: subjectTitle,
    replyToTurnId: replyToTurnId,
    message: message,
    reply: reply,
    status: status ?? this.status,
    error: error ?? this.error,
    payload: payload ?? this.payload,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

class PendingConfirmation {
  final String kind;
  final String ref;
  final String title;
  final String observation;
  final String interpretation;
  final List<String> evidence;
  final double confidence;
  final String createdAt;

  const PendingConfirmation({
    required this.kind,
    required this.ref,
    required this.title,
    this.observation = '',
    this.interpretation = '',
    this.evidence = const [],
    this.confidence = 0,
    this.createdAt = '',
  });

  factory PendingConfirmation.fromJson(Map<String, dynamic> json) =>
      PendingConfirmation(
        kind: _text(json['kind']),
        ref: _text(json['ref']),
        title: decodeHtml(_text(json['title'])),
        observation: decodeHtml(_text(json['observation'])),
        interpretation: decodeHtml(_text(json['interpretation'])),
        evidence: _strings(json['evidence_refs']).take(5).toList(),
        confidence: _number(json['confidence']),
        createdAt: _text(json['created_at']),
      );
}

class DialogueContext {
  final String replyToTurnId;
  final String sourceType;
  final String kind;
  final int generation;
  final String title;
  final List<String> evidenceLabels;
  final String contextDigest;

  const DialogueContext({
    required this.replyToTurnId,
    required this.sourceType,
    required this.kind,
    required this.generation,
    required this.title,
    this.evidenceLabels = const [],
    this.contextDigest = '',
  });

  factory DialogueContext.fromJson(Map<String, dynamic> json) =>
      DialogueContext(
        replyToTurnId: _text(json['reply_to_turn_id']),
        sourceType: _text(json['source_type']),
        kind: _text(json['kind']),
        generation: _integer(json['generation']),
        title: decodeHtml(_text(json['title'])),
        evidenceLabels: _strings(json['evidence_labels']),
        contextDigest: _text(json['context_digest']),
      );

  bool get valid =>
      replyToTurnId.isNotEmpty &&
      title.isNotEmpty &&
      const {'card', 'question'}.contains(sourceType) &&
      const {'hypothesis', 'confusion'}.contains(kind) &&
      generation > 0;
}

class ChatComposeContext {
  final String scope;
  final String subjectId;
  final String subjectTitle;

  const ChatComposeContext({
    this.scope = 'chat',
    this.subjectId = '',
    this.subjectTitle = '',
  });

  bool get active => scope != 'chat' || subjectId.isNotEmpty;
}

String _text(dynamic value) => value?.toString().trim() ?? '';

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<String> _strings(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => decodeHtml(_text(item)))
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

int _integer(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(_text(value)) ?? 0;
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(_text(value)) ?? 0;
}
