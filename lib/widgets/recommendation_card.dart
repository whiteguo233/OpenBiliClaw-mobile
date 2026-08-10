import 'package:flutter/material.dart';

import '../models/recommendation.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.rec,
    this.onTap,
    this.onLike,
    this.onDislike,
    this.onComment,
    this.onWatchLater,
    this.onFavorite,
    this.watchLaterActive = false,
    this.favoriteActive = false,
  });

  final Recommendation rec;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;
  final VoidCallback? onComment;
  final VoidCallback? onWatchLater;
  final VoidCallback? onFavorite;
  final bool watchLaterActive;
  final bool favoriteActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
      side: const BorderSide(color: AppColors.line),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: rec.isTextCard
              ? _buildTextCard(context, theme)
              : _buildVideoCard(context, theme),
        ),
      ),
    );
  }

  Widget _buildVideoCard(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CoverImage(
                url: rec.coverUrl,
                height: double.infinity,
                borderRadius: 0,
              ),
            ),
            Positioned(top: 10, left: 10, child: _sourceChip(dark: true)),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  if (onWatchLater != null)
                    _floatingAction(
                      icon: watchLaterActive
                          ? Icons.watch_later_rounded
                          : Icons.watch_later_outlined,
                      active: watchLaterActive,
                      onTap: onWatchLater,
                      tooltip: watchLaterActive ? '移出稍后再看' : '稍后再看',
                    ),
                  if (onFavorite != null) ...[
                    const SizedBox(width: 8),
                    _floatingAction(
                      icon: favoriteActive
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      active: favoriteActive,
                      onTap: onFavorite,
                      tooltip: favoriteActive ? '取消收藏' : '收藏',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        _details(context, theme),
        const Divider(),
        _actionBar(),
      ],
    );
  }

  Widget _buildTextCard(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(gradient: AppGradients.brandSoft()),
          child: Row(
            children: [
              _sourceChip(),
              const Spacer(),
              if (onWatchLater != null)
                _inlineSaveAction(
                  icon: watchLaterActive
                      ? Icons.watch_later_rounded
                      : Icons.watch_later_outlined,
                  active: watchLaterActive,
                  onTap: onWatchLater,
                  tooltip: watchLaterActive ? '移出稍后再看' : '稍后再看',
                ),
              if (onFavorite != null)
                _inlineSaveAction(
                  icon: favoriteActive
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  active: favoriteActive,
                  onTap: onFavorite,
                  tooltip: favoriteActive ? '取消收藏' : '收藏',
                ),
            ],
          ),
        ),
        _details(context, theme, showBody: true),
        const Divider(),
        _actionBar(),
      ],
    );
  }

  Widget _details(
    BuildContext context,
    ThemeData theme, {
    bool showBody = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rec.displayTitle,
            style: theme.textTheme.titleMedium?.copyWith(height: 1.34),
            maxLines: showBody ? 3 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!showBody) ...[_sourceChip(), const SizedBox(width: 7)],
              Expanded(
                child: Text(
                  rec.displayUpName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              if (rec.publishedDisplay.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(rec.publishedDisplay, style: theme.textTheme.labelSmall),
              ],
            ],
          ),
          if (rec.topicLabel.isNotEmpty) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: AppColors.lavender,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    rec.topicLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.lavender,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (rec.statsLabel.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              rec.statsLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
          if (showBody && rec.bodyText.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              rec.bodyText,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (rec.expression.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              rec.expression,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.inkMuted,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionBar() {
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          Expanded(
            child: _CardAction(
              icon: Icons.link_rounded,
              label: '打开',
              onTap: onTap,
            ),
          ),
          const VerticalDivider(),
          Expanded(
            child: _CardAction(
              icon: rec.feedbackType == 'like'
                  ? Icons.thumb_up_rounded
                  : Icons.thumb_up_outlined,
              label: '喜欢',
              active: rec.feedbackType == 'like',
              onTap: onLike,
            ),
          ),
          const VerticalDivider(),
          Expanded(
            child: _CardAction(
              icon: rec.feedbackType == 'dislike'
                  ? Icons.thumb_down_rounded
                  : Icons.thumb_down_outlined,
              label: '不喜欢',
              active: rec.feedbackType == 'dislike',
              onTap: onDislike,
            ),
          ),
          if (onComment != null) ...[
            const VerticalDivider(),
            Expanded(
              child: _CardAction(
                icon: rec.feedbackType == 'comment'
                    ? Icons.chat_bubble_rounded
                    : Icons.chat_bubble_outline_rounded,
                label: '聊一聊',
                active: rec.feedbackType == 'comment',
                onTap: onComment,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sourceChip({bool dark = false}) {
    final background = dark
        ? Colors.black.withValues(alpha: 0.58)
        : AppColors.surfaceMuted;
    final foreground = dark ? Colors.white : AppColors.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: dark ? null : Border.all(color: AppColors.line),
      ),
      child: Text(
        _sourceLabel(rec.sourcePlatform),
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _floatingAction({
    required IconData icon,
    required bool active,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.brandStrong
            : Colors.black.withValues(alpha: 0.5),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 21, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _inlineSaveAction({
    required IconData icon,
    required bool active,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      color: active ? AppColors.brandStrong : AppColors.inkMuted,
      icon: Icon(icon, size: 21),
    );
  }

  String _sourceLabel(String source) {
    return switch (source.toLowerCase()) {
      'bilibili' => 'B站',
      'xiaohongshu' => '小红书',
      'douyin' => '抖音',
      'youtube' => 'YouTube',
      'twitter' => 'X',
      'zhihu' => '知乎',
      'reddit' => 'Reddit',
      'bangumi' => 'Bangumi',
      'web' => '网页',
      _ => source.isEmpty ? '内容' : source,
    };
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.brandStrong : AppColors.inkMuted;
    return Semantics(
      button: true,
      label: label,
      selected: active,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
