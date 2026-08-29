import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/api/client.dart';

/// LLM-backed end-to-end scenarios against the REAL backend.
///
/// These exercises require the backend LLM (e.g. SenseNova via
/// openai_compatible) to be configured and working — they assert that the
/// LLM actually produced content, not just that the endpoint responded.
/// They require the OpenBiliClaw backend on 127.0.0.1:8420.
///
void main() {
  final client = ApiClient(host: '127.0.0.1', port: 8420);

  setUpAll(() async {
    // Retry a few times: parallel e2e files can momentarily contend with
    // the backend's health endpoint.
    var ok = false;
    for (var attempt = 0; attempt < 4 && !ok; attempt++) {
      ok = await client.checkHealth();
      if (!ok) await Future<void>.delayed(const Duration(seconds: 3));
    }
    expect(ok, isTrue, reason: '端到端测试需要后端运行在 127.0.0.1:8420');
  });

  test('e2e-llm: 画像摘要由 LLM 生成真实人格素描', () async {
    final data = await client.get('/profile-summary?limit=5', timeout: 30);
    final portrait = (data['personality_portrait'] ?? '').toString().trim();
    expect(portrait.length, greaterThan(50), reason: '人格素描应为 LLM 生成的长文本');
    expect(data['speculative_interests'], isA<List>());
  });

  test('e2e-llm: 惊喜推荐带 LLM 个性化理由', () async {
    final data = await client.get(
      '/delight/pending-batch?limit=3',
      timeout: 30,
    );
    final items = (data['items'] as List?) ?? const [];
    expect(items, isNotEmpty, reason: '应返回惊喜推荐候选');
    final first = Map<String, dynamic>.from(items.first as Map);
    final reason = (first['delight_reason'] ?? '').toString().trim();
    expect(reason.length, greaterThan(20), reason: '推荐理由应为 LLM 生成');
  });

  test('e2e-llm: 对话 AI 回复由商汤真实生成', () async {
    final turnId = 'e2e-llm-${DateTime.now().millisecondsSinceEpoch}';
    await client.post(
      '/chat/turns',
      body: {
        'turn_id': turnId,
        'session': 'popup',
        'scope': 'chat',
        'message': '帮我分析一下：我最近关注的内容里，有什么共同主题？',
      },
      timeout: 20,
    );
    String reply = '';
    String status = '';
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 5));
      final turn = await client.get('/chat/turns/$turnId', timeout: 15);
      status = turn['status']?.toString() ?? '';
      reply = (turn['reply'] ?? turn['response'] ?? '').toString().trim();
      if (const {
            'done',
            'ok',
            'completed',
            'error',
            'failed',
          }.contains(status) ||
          reply.isNotEmpty) {
        break;
      }
    }
    expect(reply.length, greaterThan(50), reason: 'AI 回复应为 LLM 生成的长文本');
    expect(status, isNot(anyOf('error', 'failed')));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('e2e-llm: 待聊确认包含 hypothesis 卡', () async {
    final data = await client.get(
      '/chat/pending-confirmations?session=popup',
      timeout: 15,
    );
    final items = (data['items'] as List?) ?? const [];
    expect(items, isNotEmpty, reason: '应有待聊确认项');
  });

  test('e2e-llm: 活动流 headline 由 LLM 汇总', () async {
    final data = await client.get('/activity-feed?limit=5', timeout: 15);
    expect(data, isA<Map>());
    final headline = (data['headline'] ?? '').toString();
    expect(headline, isNotEmpty, reason: '活动流 headline 应为 LLM 汇总');
  });
}
