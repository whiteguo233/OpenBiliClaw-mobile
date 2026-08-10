import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/chat.dart';

void main() {
  test('parses durable hypothesis card and actions', () {
    final turn = ChatTurn.fromJson({
      'turn_id': 'confirmation-1',
      'session': 'popup',
      'scope': 'hypothesis',
      'status': 'completed',
      'payload': {
        'type': 'card',
        'kind': 'hypothesis',
        'title': '你更在意真实可用性',
        'state': 'active',
        'actions': ['confirm', 'reject', 'discuss', 'defer'],
        'evidence_refs': ['连续查看了三个实测视频'],
      },
    });

    expect(turn.isCard, isTrue);
    expect(turn.cardKind, 'hypothesis');
    expect(turn.cardTitle, '你更在意真实可用性');
    expect(turn.cardActions, contains('discuss'));
    expect(turn.evidence.single, '连续查看了三个实测视频');
    expect(turn.cardTerminal, isFalse);
  });

  test('validates canonical dialogue context shape', () {
    final context = DialogueContext.fromJson({
      'active': true,
      'reply_to_turn_id': 'confirmation-1',
      'source_type': 'card',
      'kind': 'hypothesis',
      'generation': 2,
      'title': '一个猜测',
      'context_digest': 'digest',
    });

    expect(context.valid, isTrue);
  });

  test('parses pending confusion work item', () {
    final item = PendingConfirmation.fromJson({
      'kind': 'confusion',
      'ref': '20',
      'title': 'NBA球员训练日常',
      'confidence': 0.6667,
    });

    expect(item.kind, 'confusion');
    expect(item.ref, '20');
    expect(item.confidence, closeTo(0.6667, 0.0001));
  });
}
