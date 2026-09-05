import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/back_to_top_fab.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, provider, _) {
        final summary = provider.summary;
        return Column(
          children: [
            if (summary != null && summary.initialized)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openEditor(context, provider),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      backgroundColor: context.appColors.brandSoft,
                      foregroundColor: AppColors.brandStrong,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('编辑画像'),
                  ),
                ),
              ),
            Expanded(
              child: provider.loading && summary == null
                  ? const Center(child: CircularProgressIndicator.adaptive())
                  : summary == null || !summary.hasContent
                  ? _emptyState(context, summary)
                  : Stack(
                      children: [
                        RefreshIndicator(
                          onRefresh: () async {
                            await provider.load();
                            await provider.loadNotifications();
                          },
                          child: ListView(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                            children: [
                              if (provider.error.isNotEmpty)
                                _errorBanner(context, provider),
                              if (provider.cognitionNotification != null)
                                _cognitionNotice(context, provider),
                              _portrait(context, summary),
                              _coreSection(context, summary),
                              _valuesSection(context, summary),
                              _interestSection(context, summary),
                              _roleSection(context, summary),
                              _surfaceSection(context, summary),
                              if (summary.speculativeInterests.isNotEmpty)
                                _speculationSection(
                                  context,
                                  provider,
                                  summary.speculativeInterests,
                                  avoidance: false,
                                ),
                              if (summary.speculativeAvoidances.isNotEmpty)
                                _speculationSection(
                                  context,
                                  provider,
                                  summary.speculativeAvoidances,
                                  avoidance: true,
                                ),
                              if (provider.cognitionUpdates.isNotEmpty)
                                _cognitionSection(context, provider),
                              if (summary.activeInsights.isNotEmpty)
                                _insightsSection(
                                  context,
                                  summary.activeInsights,
                                ),
                              if (summary.recentAwareness.isNotEmpty)
                                _awarenessSection(
                                  context,
                                  summary.recentAwareness,
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: BackToTopFab(controller: _scrollController),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, ProfileSummary? summary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 48,
            color: context.appColors.lineStrong,
          ),
          const SizedBox(height: 8),
          Text(
            summary?.initialized == false
                ? '画像尚未初始化，请先在后端完成 openbiliclaw init。'
                : '画像还在慢慢攒，先多看一阵。',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appColors.inkMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context, ProfileProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(provider.error, style: const TextStyle(fontSize: 12)),
          ),
          IconButton(
            onPressed: provider.clearError,
            icon: const Icon(Icons.close, size: 17),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _cognitionNotice(BuildContext context, ProfileProvider provider) {
    final item = provider.cognitionNotification!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            context.appPositive.withValues(alpha: 0.12),
            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: context.appPositive),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '画像有一条新认知',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  (item['summary'] ?? '').toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: provider.markCognitionSeen,
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _portrait(BuildContext context, ProfileSummary summary) {
    final edited =
        summary.overrides.isNotEmpty &&
        summary.overrides.values.any((value) {
          if (value is Map) return value.isNotEmpty;
          return value != null && value.toString().isNotEmpty;
        });
    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.brandSoft(context),
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.12)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandStrong,
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: const Icon(
            Icons.fingerprint_rounded,
            size: 24,
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            const Expanded(
              child: Text(
                '人格素描',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (edited) _badge('含手动修正', Theme.of(context).colorScheme.primary),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            summary.portrait,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.appColors.ink),
          ),
        ),
        children: [
          const Divider(),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              summary.portrait,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.65),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coreSection(BuildContext context, ProfileSummary summary) {
    return _section(
      context,
      '核心层',
      Icons.center_focus_strong,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, '核心特质'),
          _chips(context, summary.layers.map((item) => item.name), brand: true),
          if (summary.deepNeeds.isNotEmpty) ...[
            const SizedBox(height: 12),
            _label(context, '深层需求'),
            _bulletList(context, summary.deepNeeds),
          ],
          if (summary.mbti.type.isNotEmpty) ...[
            const SizedBox(height: 12),
            _mbti(context, summary.mbti),
          ],
        ],
      ),
    );
  }

  Widget _valuesSection(BuildContext context, ProfileSummary summary) {
    if (summary.values.isEmpty && summary.motivationalDrivers.isEmpty) {
      return const SizedBox.shrink();
    }
    return _section(
      context,
      '价值观与驱动力',
      Icons.explore_outlined,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.values.isNotEmpty)
            _chips(context, summary.values, success: true),
          if (summary.motivationalDrivers.isNotEmpty) ...[
            const SizedBox(height: 10),
            _label(context, '内在驱动力'),
            _bulletList(context, summary.motivationalDrivers),
          ],
        ],
      ),
    );
  }

  Widget _interestSection(BuildContext context, ProfileSummary summary) {
    return _section(
      context,
      '兴趣领域',
      Icons.interests_outlined,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.interests.isNotEmpty) ...[
            _label(context, '喜欢'),
            ...summary.interests.map((item) => _interest(context, item)),
          ],
          if (summary.avoidances.isNotEmpty) ...[
            const SizedBox(height: 10),
            _label(
              context,
              '明显会避开',
              color: Theme.of(context).colorScheme.error,
            ),
            ...summary.avoidances.map(
              (item) => _interest(context, item, avoidance: true),
            ),
          ],
          if (summary.favoriteUpUsers.isNotEmpty) ...[
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              dense: true,
              initiallyExpanded: true,
              title: Text('关注的创作者（${summary.favoriteUpUsers.length}）'),
              children: [
                _chips(context, summary.favoriteUpUsers.take(40), brand: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleSection(BuildContext context, ProfileSummary summary) {
    if (summary.lifeStage.isEmpty && summary.currentPhase.isEmpty) {
      return const SizedBox.shrink();
    }
    return _section(
      context,
      '角色与阶段',
      Icons.timeline,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.lifeStage.isNotEmpty) ...[
            _label(context, '人生阶段'),
            Text(summary.lifeStage),
          ],
          if (summary.currentPhase.isNotEmpty) ...[
            const SizedBox(height: 10),
            _label(context, '当前阶段'),
            Text(summary.currentPhase),
          ],
        ],
      ),
    );
  }

  Widget _surfaceSection(BuildContext context, ProfileSummary summary) {
    return _section(
      context,
      '认知与内容风格',
      Icons.tune,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.cognitiveStyle.isNotEmpty) ...[
            _label(context, '认知风格'),
            _chips(context, summary.cognitiveStyle),
            const SizedBox(height: 10),
          ],
          _preferenceBar(context, '质量敏感度', summary.style.qualitySensitivity),
          _preferenceBar(context, '幽默偏好', summary.style.humorPreference),
          _preferenceBar(context, '深度偏好', summary.style.depthPreference),
          _preferenceBar(context, '探索开放度', summary.explorationOpenness),
          if (summary.style.preferredDuration.isNotEmpty)
            _keyValue(context, '偏好时长', summary.style.preferredDuration),
          if (summary.style.preferredPace.isNotEmpty)
            _keyValue(context, '偏好节奏', summary.style.preferredPace),
          if (summary.context.weekdayPatterns.isNotEmpty)
            _keyValue(context, '工作日', summary.context.weekdayPatterns),
          if (summary.context.weekendPatterns.isNotEmpty)
            _keyValue(context, '周末', summary.context.weekendPatterns),
          if (summary.context.timeOfDayPatterns.isNotEmpty)
            _keyValue(context, '时间模式', summary.context.timeOfDayPatterns),
          if (summary.context.sessionType.isNotEmpty)
            _keyValue(context, '浏览会话', summary.context.sessionType),
        ],
      ),
    );
  }

  Widget _speculationSection(
    BuildContext context,
    ProfileProvider provider,
    List<ProfileSpeculation> items, {
    required bool avoidance,
  }) {
    return _section(
      context,
      avoidance ? '待确认的避雷方向' : '推测性兴趣',
      avoidance ? Icons.shield_outlined : Icons.travel_explore,
      Column(
        children: items
            .map(
              (item) => _speculationCard(
                context,
                provider,
                item,
                avoidance: avoidance,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _speculationCard(
    BuildContext context,
    ProfileProvider provider,
    ProfileSpeculation item, {
    required bool avoidance,
  }) {
    final busy = provider.probeBusy(item.domain, avoidance: avoidance);
    final progress = item.confirmationThreshold > 0
        ? item.confirmationCount / item.confirmationThreshold
        : 0.0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            (avoidance
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.secondary)
                .withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.domain,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _badge(
                item.challenge ? '挑战方向' : '${(item.confidence * 100).round()}%',
                item.challenge
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.secondary,
              ),
            ],
          ),
          if (item.reason.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(item.reason, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (item.specifics.isNotEmpty) ...[
            const SizedBox(height: 6),
            _chips(context, item.specifics.take(5)),
          ],
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 3,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () => _probeAction(
                        context,
                        provider,
                        item.domain,
                        'confirm',
                        avoidance,
                      ),
                child: Text(avoidance ? '是雷点' : '喜欢'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => _probeAction(
                        context,
                        provider,
                        item.domain,
                        'reject',
                        avoidance,
                      ),
                child: Text(avoidance ? '不是' : '不喜欢'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => _probeAction(
                        context,
                        provider,
                        item.domain,
                        'defer',
                        avoidance,
                      ),
                child: const Text('稍后再说'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _cognitionSection(BuildContext context, ProfileProvider provider) {
    final summary = provider.summary!;
    return _section(
      context,
      '认知更新历史',
      Icons.history,
      Column(
        children: [
          ...provider.cognitionUpdates.map(
            (item) => ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              dense: true,
              title: Text(item.summary, style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                [
                  item.sourceLabel,
                  item.createdAt,
                ].where((value) => value.isNotEmpty).join(' · '),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              children: [
                if (item.contextLine.isNotEmpty)
                  _detailText(context, '背景', item.contextLine),
                if (item.impact.isNotEmpty)
                  _detailText(context, '影响', item.impact),
                if (item.reasoning.isNotEmpty)
                  _detailText(context, '推理', item.reasoning),
                if (item.evidence.isNotEmpty)
                  _detailText(context, '依据', item.evidence),
              ],
            ),
          ),
          if (summary.hasMoreCognitionUpdates)
            TextButton.icon(
              onPressed: provider.loadingMoreCognition
                  ? null
                  : provider.loadMoreCognition,
              icon: provider.loadingMoreCognition
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: const Text('加载更多'),
            ),
        ],
      ),
    );
  }

  Widget _insightsSection(BuildContext context, List<ProfileInsight> items) {
    return _section(
      context,
      '活跃洞察',
      Icons.lightbulb_outline,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '这些是只读认知；需要确认或纠正时，请到“对话”的待聊确认入口。',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          ...items.map(
            (item) => ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                item.hypothesis,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                '置信 ${(item.confidence * 100).round()}%${item.validated ? ' · 已验证' : ''}',
              ),
              children: [_bulletList(context, item.evidence)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _awarenessSection(BuildContext context, List<ProfileAwareness> items) {
    return _section(
      context,
      '近期感知',
      Icons.eco_outlined,
      Column(
        children: items
            .map(
              (item) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: context.appPositive.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.date,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(item.observation),
                    if (item.trend.isNotEmpty)
                      _detailText(context, '趋势', item.trend),
                    if (item.emotionGuess.isNotEmpty)
                      _detailText(context, '状态猜测', item.emotionGuess),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    Widget child,
  ) {
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.appColors.brandSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _interest(
    BuildContext context,
    ProfileInterest item, {
    bool avoidance = false,
  }) {
    final color = avoidance
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.secondary;
    final generatedReason = item.specifics.isNotEmpty
        ? '细分：${item.specifics.join('、')}'
        : '';
    final showReason = item.reason.isNotEmpty && item.reason != generatedReason;
    final category = item.category.trim();
    final showCategory = category.isNotEmpty && category != item.name;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        dense: true,
        initiallyExpanded: true,
        title: Row(
          children: [
            Icon(
              avoidance ? Icons.block_rounded : Icons.favorite_border_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showCategory)
                    Text(
                      category,
                      style: TextStyle(
                        fontSize: 10,
                        color: context.appColors.inkMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (item.weight > 0)
              _badge('${(item.weight * 100).round()}%', color),
          ],
        ),
        children: [
          if (showReason)
            _profileDetailBlock(
              context,
              icon: Icons.lightbulb_outline_rounded,
              label: '推荐理由',
              child: _ExpandableText(
                text: item.reason,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (item.specifics.isNotEmpty)
            _profileDetailBlock(
              context,
              icon: Icons.tag_rounded,
              label: '细分偏好',
              child: _chips(context, item.specifics),
            ),
        ],
      ),
    );
  }

  Widget _profileDetailBlock(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }

  Widget _mbti(BuildContext context, ProfileMbti mbti) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                mbti.type,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text('置信 ${(mbti.confidence * 100).round()}%'),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: mbti.dimensions.entries
                .map(
                  (entry) => Text(
                    '${entry.key}: ${entry.value.pole} ${(entry.value.strength * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _preferenceBar(BuildContext context, String label, double value) {
    final normalized = value.clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: normalized,
              minHeight: 5,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(normalized * 100).round()}%',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _keyValue(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: Theme.of(context).textTheme.labelSmall),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _chips(
    BuildContext context,
    Iterable<String> values, {
    bool brand = false,
    bool success = false,
  }) {
    final color = brand
        ? Theme.of(context).colorScheme.primary
        : success
        ? context.appPositive
        : Theme.of(context).colorScheme.secondary;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: values
          .where((value) => value.isNotEmpty)
          .map(
            (value) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(value, style: const TextStyle(fontSize: 11)),
            ),
          )
          .toList(),
    );
  }

  Widget _bulletList(BuildContext context, Iterable<String> values) {
    return Column(
      children: values
          .where((value) => value.isNotEmpty)
          .map(
            (value) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _detailText(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _label(BuildContext context, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        value,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _badge(String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(value, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Future<void> _probeAction(
    BuildContext context,
    ProfileProvider provider,
    String domain,
    String action,
    bool avoidance,
  ) async {
    final ok = avoidance
        ? await provider.respondToAvoidanceProbe(domain, action)
        : await provider.respondToProbe(domain, action);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已记下你的选择' : provider.error),
        backgroundColor: ok ? null : Colors.red[700],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    ProfileProvider provider,
  ) async {
    final ok = await provider.loadEditState();
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: const _ProfileEditSheet(),
      ),
    );
  }
}

class _ProfileEditSheet extends StatelessWidget {
  const _ProfileEditSheet();

  static const labels = <String, String>{
    'personality_portrait': '人格素描',
    'core.core_traits': '核心特质',
    'core.deep_needs': '深层需求',
    'values_layer.values': '价值观',
    'values_layer.motivational_drivers': '内在驱动力',
    'likes': '感兴趣的方向',
    'dislikes': '明显会避开',
    'interest.favorite_up_users': '关注的创作者',
    'role.life_stage': '人生阶段',
    'role.current_phase': '当前阶段',
    'surface.cognitive_style': '认知风格',
    'surface.exploration_openness': '探索开放度',
    'surface.style.quality_sensitivity': '质量敏感度',
    'surface.style.humor_preference': '幽默偏好',
    'surface.style.depth_preference': '深度偏好',
  };

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, provider, _) {
        final rawFields = provider.editState?['fields'];
        final fields = rawFields is Map ? rawFields : const {};
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '编辑画像',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '修改会作为用户覆盖层长期保留。误删后可用“恢复 AI 建议”撤销该字段的手动修改。',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.inkMuted,
                  ),
                ),
              ),
              if (provider.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    provider.error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: labels.entries.map((entry) {
                    final raw = fields[entry.key];
                    if (raw is! Map) return const SizedBox.shrink();
                    return _field(
                      context,
                      provider,
                      entry.key,
                      entry.value,
                      Map<String, dynamic>.from(raw),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    BuildContext context,
    ProfileProvider provider,
    String path,
    String label,
    Map<String, dynamic> field,
  ) {
    final type = field['type']?.toString() ?? '';
    final edited =
        field['pinned'] == true ||
        (field['added'] is List && (field['added'] as List).isNotEmpty) ||
        (field['removed'] is List && (field['removed'] as List).isNotEmpty) ||
        (field['removed_domains'] is List &&
            (field['removed_domains'] as List).isNotEmpty);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            if (edited)
              Text(
                '已编辑',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (type == 'text')
            _textEditor(context, provider, path, field)
          else if (type == 'scalar')
            _scalarEditor(context, provider, path, field)
          else if (type == 'list')
            _listEditor(context, provider, path, field)
          else if (type == 'interest')
            _interestEditor(context, provider, path, field),
          if (edited)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    provider.applyEdit(target: path, operation: 'reset'),
                child: const Text('恢复 AI 建议'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _textEditor(
    BuildContext context,
    ProfileProvider provider,
    String path,
    Map<String, dynamic> field,
  ) {
    final value = (field['value'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, maxLines: 5, overflow: TextOverflow.ellipsis),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () => _editText(context, provider, path, value),
            child: const Text('修改文本'),
          ),
        ),
      ],
    );
  }

  Widget _scalarEditor(
    BuildContext context,
    ProfileProvider provider,
    String path,
    Map<String, dynamic> field,
  ) {
    final value = field['value'] is num
        ? (field['value'] as num).toDouble()
        : double.tryParse('${field['value']}') ?? 0.5;
    return Row(
      children: [
        Expanded(child: LinearProgressIndicator(value: value.clamp(0, 1))),
        const SizedBox(width: 10),
        Text('${(value * 100).round()}%'),
        TextButton(
          onPressed: () => _editScalar(context, provider, path, value),
          child: const Text('调整'),
        ),
      ],
    );
  }

  Widget _listEditor(
    BuildContext context,
    ProfileProvider provider,
    String path,
    Map<String, dynamic> field,
  ) {
    final items = field['items'] is List
        ? (field['items'] as List).map((item) => item.toString()).toList()
        : const <String>[];
    return _editableChips(context, provider, path, items);
  }

  Widget _interestEditor(
    BuildContext context,
    ProfileProvider provider,
    String path,
    Map<String, dynamic> field,
  ) {
    final domains = field['domains'] is List
        ? (field['domains'] as List)
              .whereType<Map>()
              .map((item) => item['domain']?.toString() ?? '')
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    return _editableChips(context, provider, path, domains);
  }

  Widget _editableChips(
    BuildContext context,
    ProfileProvider provider,
    String path,
    List<String> items,
  ) {
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: items.take(80).map((item) {
                return InputChip(
                  label: Text(item, style: const TextStyle(fontSize: 11)),
                  onDeleted: () => provider.applyEdit(
                    target: path,
                    operation: 'remove',
                    value: item,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            onPressed: () => _addItem(context, provider, path),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('添加'),
          ),
        ),
      ],
    );
  }

  Future<void> _editText(
    BuildContext context,
    ProfileProvider provider,
    String path,
    String initial,
  ) async {
    final controller = TextEditingController(text: initial);
    final value = await showAdaptiveDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('修改画像文本'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty) {
      await provider.applyEdit(target: path, operation: 'set', value: value);
    }
  }

  Future<void> _editScalar(
    BuildContext context,
    ProfileProvider provider,
    String path,
    double initial,
  ) async {
    var value = initial.clamp(0, 1).toDouble();
    final result = await showAdaptiveDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog.adaptive(
          title: Text('${(value * 100).round()}%'),
          content: Slider(
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, value),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await provider.applyEdit(target: path, operation: 'set', value: result);
    }
  }

  Future<void> _addItem(
    BuildContext context,
    ProfileProvider provider,
    String path,
  ) async {
    final controller = TextEditingController();
    final value = await showAdaptiveDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('添加一项'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty) {
      await provider.applyEdit(target: path, operation: 'add', value: value);
    }
  }
}

/// 可展开/收起的文本块：默认最多显示 2 行，长文本可展开看全文。
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 2,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : 2,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (overflow)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      Text(
                        _expanded ? '收起' : '展开',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
