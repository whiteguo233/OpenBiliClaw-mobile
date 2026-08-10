import 'package:flutter/material.dart';
import '../models/delight.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';

class DelightBanner extends StatelessWidget {
  final Delight delight;
  final int currentIndex;
  final int totalCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onView;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;
  final VoidCallback? onChat;
  final VoidCallback? onDismiss;

  const DelightBanner({
    super.key,
    required this.delight,
    this.currentIndex = 0,
    this.totalCount = 1,
    this.onPrev,
    this.onNext,
    this.onView,
    this.onLike,
    this.onDislike,
    this.onChat,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      decoration: BoxDecoration(
        gradient: AppGradients.brandSoft(),
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 19,
                    color: AppColors.brandStrong,
                  ),
                ),
                const SizedBox(width: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '惊喜推荐',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: AppColors.brandStrong,
                      ),
                    ),
                    Text(
                      _sourceLabel(delight.sourcePlatform),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const Spacer(),
                if (totalCount > 1)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '上一条惊喜推荐',
                        onPressed: onPrev,
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      ),
                      Text(
                        '${currentIndex + 1}/$totalCount',
                        style: theme.textTheme.labelMedium,
                      ),
                      IconButton(
                        tooltip: '下一条惊喜推荐',
                        onPressed: onNext,
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (delight.coverUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 14, bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 96,
                      height: 72,
                      child: CoverImage(
                        url: delight.coverUrl,
                        width: 96,
                        height: 72,
                        borderRadius: 12,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delight.title.isNotEmpty
                            ? delight.title
                            : '这条惊喜推荐还没起好标题',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (delight.reason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          delight.reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (delight.hook.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          delight.hook,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.brandStrong,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 10, 12),
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionChip(
                  '去看看',
                  Icons.open_in_new_rounded,
                  () => onView?.call(),
                  primary: true,
                ),
                _actionChip(
                  delight.state == 'liked' ? '已喜欢' : '喜欢',
                  delight.state == 'liked'
                      ? Icons.thumb_up_rounded
                      : Icons.thumb_up_outlined,
                  delight.state == 'liked' ? null : () => onLike?.call(),
                ),
                _actionChip(
                  '不感兴趣',
                  Icons.thumb_down_outlined,
                  () => onDislike?.call(),
                ),
                if (onChat != null)
                  _actionChip(
                    '聊一聊',
                    Icons.chat_bubble_outline_rounded,
                    () => onChat?.call(),
                  ),
                IconButton(
                  tooltip: '忽略',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onDismiss,
                  color: AppColors.inkMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool primary = false,
  }) {
    if (primary) {
      return FilledButton.tonalIcon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.surface.withValues(alpha: 0.88),
          foregroundColor: AppColors.brandStrong,
        ),
        icon: Icon(icon, size: 17),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface.withValues(alpha: 0.72),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
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
      _ => source.isEmpty ? '内容' : source,
    };
  }
}
