import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/delight.dart';
import '../models/recommendation.dart';
import '../models/saved_item.dart';
import '../providers/recommend_provider.dart';
import '../providers/saved_provider.dart';
import '../services/content_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/back_to_top_fab.dart';
import '../widgets/delight_banner.dart';
import '../widgets/recommendation_card.dart';

class RecommendView extends StatefulWidget {
  const RecommendView({super.key, this.onStartChat});

  final void Function(String scope, String subjectId, String subjectTitle)?
  onStartChat;

  @override
  State<RecommendView> createState() => _RecommendViewState();
}

class _RecommendViewState extends State<RecommendView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<RecommendProvider, SavedProvider>(
      builder: (context, rp, sp, _) {
        final delightsCount = rp.delights.length;
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 520 &&
                    rp.recommendations.isNotEmpty) {
                  unawaited(rp.append());
                }
                return false;
              },
              child: RefreshIndicator(
                onRefresh: rp.load,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(context, rp)),
                    if (rp.error.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _statusBanner(
                          context,
                          rp.error,
                          Icons.error_outline,
                          Colors.red,
                        ),
                      )
                    else if (!rp.online && !rp.loading)
                      SliverToBoxAdapter(
                        child: _statusBanner(
                          context,
                          '无法连接后端，下拉可重试',
                          Icons.wifi_off,
                          Colors.orange,
                        ),
                      ),
                    if (rp.activityFeed.headline.isNotEmpty ||
                        rp.activityFeed.liveSummary.isNotEmpty)
                      SliverToBoxAdapter(child: _buildActivity(context, rp)),
                    if (delightsCount > 0)
                      SliverToBoxAdapter(
                        child: _buildDelight(context, rp, delightsCount),
                      ),
                    if (rp.loading && rp.recommendations.isEmpty)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (rp.recommendations.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _emptyState(context, rp),
                      )
                    else
                      SliverList.builder(
                        itemCount: rp.recommendations.length,
                        itemBuilder: (context, index) {
                          final rec = rp.recommendations[index];
                          final watchLaterActive = sp.contains(
                            SavedListKind.watchLater,
                            rec,
                          );
                          final favoriteActive = sp.contains(
                            SavedListKind.favorite,
                            rec,
                          );
                          return RecommendationCard(
                            rec: rec,
                            watchLaterActive: watchLaterActive,
                            favoriteActive: favoriteActive,
                            onTap: () async {
                              unawaited(rp.reportClick(rec));
                              final opened =
                                  await ContentLauncher.openRecommendation(rec);
                              if (context.mounted && !opened) {
                                _showMessage(
                                  context,
                                  '没有可打开的内容链接',
                                  error: true,
                                );
                              }
                            },
                            onLike: () => _feedback(context, rp, rec, 'like'),
                            onDislike: () =>
                                _feedback(context, rp, rec, 'dislike'),
                            onComment: () => _comment(context, rp, rec),
                            onWatchLater: () => _toggleSaved(
                              context,
                              sp,
                              SavedListKind.watchLater,
                              rec,
                              !watchLaterActive,
                            ),
                            onFavorite: () => _toggleSaved(
                              context,
                              sp,
                              SavedListKind.favorite,
                              rec,
                              !favoriteActive,
                            ),
                          );
                        },
                      ),
                    if (rp.recommendations.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: rp.loadingMore
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : TextButton.icon(
                                    onPressed: rp.append,
                                    icon: const Icon(Icons.expand_more),
                                    label: const Text('加载更多推荐'),
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 14,
              bottom: 14,
              child: BackToTopFab(controller: _scrollController),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, RecommendProvider rp) {
    final status = rp.runtimeStatus;
    final liveSummary = rp.activityFeed.liveSummary.trim();
    final summary = liveSummary.isNotEmpty
        ? liveSummary
        : status.poolAvailableCount > 0
        ? '阿B 已经备好 ${status.poolAvailableCount} 条内容，慢慢挑。'
        : '阿B 这会儿先替你盯着。';
    final runtimeSummary = [
      '${status.poolAvailableCount} 条可换',
      if (status.poolPendingCount > 0) '${status.poolPendingCount} 条整理中',
      if (status.lastReplenishedCount > 0)
        '刚补 ${status.lastReplenishedCount} 条',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.lavender.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.brand, AppColors.lavender],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'For You',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: rp.reshuffling ? null : rp.reshuffle,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(92, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: AppColors.brandSoft,
                  foregroundColor: AppColors.brandStrong,
                ),
                icon: rp.reshuffling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.shuffle_rounded, size: 18),
                label: const Text('换一批'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('这几条，你大概会点开', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.lavenderSoft.withValues(alpha: 0.64),
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppColors.lavender,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        runtimeSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.lavender,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivity(BuildContext context, RecommendProvider rp) {
    final feed = rp.activityFeed;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.line),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.bolt_rounded,
            size: 20,
            color: AppColors.success,
          ),
        ),
        title: Text(
          feed.headline.isNotEmpty ? feed.headline : feed.liveSummary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: feed.headline.isNotEmpty && feed.liveSummary.isNotEmpty
            ? Text(
                feed.liveSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              )
            : null,
        children: feed.items
            .take(5)
            .map(
              (item) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                title: Text(
                  item.title,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                subtitle: item.summary.isEmpty
                    ? null
                    : Text(
                        item.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDelight(
    BuildContext context,
    RecommendProvider rp,
    int delightsCount,
  ) {
    final index = rp.delightIndex.clamp(0, delightsCount - 1);
    final delight = rp.delights[index];
    final sp = context.read<SavedProvider>();
    final projection = delight.toRecommendation();
    final watchLaterActive = sp.contains(SavedListKind.watchLater, projection);
    final favoriteActive = sp.contains(SavedListKind.favorite, projection);
    return DelightBanner(
      delight: delight,
      currentIndex: index,
      totalCount: delightsCount,
      onPrev: rp.prevDelight,
      onNext: rp.nextDelight,
      onView: () async {
        unawaited(rp.respondToDelight(delight, 'view'));
        final opened = await ContentLauncher.openDelight(delight);
        if (context.mounted && !opened) {
          _showMessage(context, '没有可打开的内容链接', error: true);
        }
      },
      onLike: () => _delightAction(context, rp, delight, 'like'),
      onDislike: () => _delightAction(context, rp, delight, 'dislike'),
      onDismiss: () => _delightAction(context, rp, delight, 'dismiss'),
      onWatchLater: () => _toggleSaved(
        context,
        sp,
        SavedListKind.watchLater,
        projection,
        !watchLaterActive,
      ),
      onFavorite: () => _toggleSaved(
        context,
        sp,
        SavedListKind.favorite,
        projection,
        !favoriteActive,
      ),
      onChat: widget.onStartChat == null
          ? null
          : () => widget.onStartChat!(
              'delight',
              delight.contentId.isNotEmpty ? delight.contentId : delight.bvid,
              delight.title,
            ),
    );
  }

  Widget _statusBanner(
    BuildContext context,
    String message,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, RecommendProvider rp) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text(
            rp.online ? '推荐池暂时为空' : '后端暂时不可达',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: rp.load, child: const Text('重新加载')),
        ],
      ),
    );
  }

  Future<void> _feedback(
    BuildContext context,
    RecommendProvider provider,
    Recommendation item,
    String type, {
    String? note,
  }) async {
    final ok = await provider.submitFeedback(item, type, note: note);
    if (!context.mounted) return;
    _showMessage(
      context,
      ok
          ? (type == 'like'
                ? '已记下：喜欢'
                : type == 'dislike'
                ? '已记下：不喜欢'
                : '反馈已提交')
          : provider.error,
      error: !ok,
    );
  }

  Future<void> _comment(
    BuildContext context,
    RecommendProvider provider,
    Recommendation item,
  ) async {
    final controller = TextEditingController();
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '告诉阿B哪里对、哪里不对',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '例如：方向对，但我更想看实测和边界分析',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isNotEmpty) Navigator.pop(sheetContext, value);
                },
                child: const Text('提交'),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (note != null && context.mounted) {
      await _feedback(context, provider, item, 'comment', note: note);
    }
  }

  Future<void> _toggleSaved(
    BuildContext context,
    SavedProvider provider,
    SavedListKind kind,
    Recommendation item,
    bool add,
  ) async {
    final ok = await provider.toggle(kind, item, add);
    if (!context.mounted) return;
    _showMessage(
      context,
      ok
          ? (add ? '已加入本地${kind.label}' : '已从本地${kind.label}移除')
          : provider.error,
      error: !ok,
    );
  }

  Future<void> _delightAction(
    BuildContext context,
    RecommendProvider provider,
    Delight delight,
    String action,
  ) async {
    final ok = await provider.respondToDelight(delight, action);
    if (!context.mounted || ok) return;
    _showMessage(context, provider.error, error: true);
  }

  void _showMessage(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    if (message.trim().isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red[700] : null,
        ),
      );
  }
}
