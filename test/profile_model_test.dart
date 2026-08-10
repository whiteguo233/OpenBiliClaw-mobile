import 'package:flutter_test/flutter_test.dart';
import 'package:openbiliclaw_app/models/profile.dart';

void main() {
  test('parses the current backend profile schema', () {
    final summary = ProfileSummary.fromJson({
      'initialized': true,
      'personality_portrait': '重视因果与信息密度',
      'core_traits': ['审慎的杂食者', '喜欢探索'],
      'likes': [
        {
          'domain': '科技',
          'weight': 0.85,
          'specifics': [
            {'name': 'AI 模型部署', 'weight': 0.8},
          ],
        },
      ],
      'dislikes': [
        {'domain': '标题党', 'weight': 0.9, 'specifics': []},
      ],
    });

    expect(summary.hasContent, isTrue);
    expect(summary.portrait, '重视因果与信息密度');
    expect(summary.layers.map((layer) => layer.name), ['审慎的杂食者', '喜欢探索']);
    expect(summary.interests.single.name, '科技');
    expect(summary.interests.single.reason, contains('AI 模型部署'));
    expect(summary.avoidances.single.name, '标题党');
    expect(summary.deepNeeds, isEmpty);
  });

  test('parses all five profile layers and cognition extensions', () {
    final summary = ProfileSummary.fromJson({
      'initialized': true,
      'personality_portrait': '重因果与边界',
      'core_traits': ['审慎'],
      'deep_needs': ['注意力沉淀'],
      'mbti': {
        'type': 'ISTP',
        'confidence': 0.65,
        'dimensions': {
          'EI': {'pole': 'I', 'strength': 0.6},
        },
      },
      'values': ['信息效率'],
      'motivational_drivers': ['可复用判断'],
      'life_stage': '职业爬坡期',
      'current_phase': '多领域探索',
      'cognitive_style': ['重实测'],
      'style': {'depth_preference': 0.8},
      'context': {'weekday_patterns': '晚间浏览'},
      'exploration_openness': 0.7,
      'speculative_interests': [
        {
          'domain': '嵌入式 DIY',
          'confidence': 0.4,
          'probe_mode': 'bridge',
          'challenge': true,
          'specifics': [
            {'name': '树莓派'},
          ],
        },
      ],
      'recent_cognition_updates': [
        {'summary': '画像已整理', 'source_label': '画像整理'},
      ],
      'active_insights': [
        {'hypothesis': '偏向验证', 'confidence': 0.7},
      ],
      'recent_awareness': [
        {'date': '2026-08-08', 'observation': '持续关注 AI 实测'},
      ],
    });

    expect(summary.deepNeeds.single, '注意力沉淀');
    expect(summary.mbti.type, 'ISTP');
    expect(summary.mbti.dimensions['EI']?.pole, 'I');
    expect(summary.values.single, '信息效率');
    expect(summary.style.depthPreference, 0.8);
    expect(summary.context.weekdayPatterns, '晚间浏览');
    expect(summary.speculativeInterests.single.challenge, isTrue);
    expect(summary.speculativeInterests.single.specifics, ['树莓派']);
    expect(summary.cognitionUpdates.single.summary, '画像已整理');
    expect(summary.activeInsights.single.hypothesis, '偏向验证');
    expect(summary.recentAwareness.single.observation, '持续关注 AI 实测');
  });

  test('keeps compatibility with the legacy profile schema', () {
    final summary = ProfileSummary.fromJson({
      'portrait': '旧版画像',
      'layers': [
        {'name': '关注细节', 'summary': '喜欢具体分析'},
      ],
      'interests': [
        {'name': '科技', 'weight': 0.8, 'reason': '长期关注'},
      ],
      'avoidances': [
        {'name': '标题党', 'weight': 0.9},
      ],
    });

    expect(summary.portrait, '旧版画像');
    expect(summary.layers.single.summary, '喜欢具体分析');
    expect(summary.interests.single.reason, '长期关注');
    expect(summary.avoidances.single.name, '标题党');
  });
}
