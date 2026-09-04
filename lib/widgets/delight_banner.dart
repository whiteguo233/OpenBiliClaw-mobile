import 'package:flutter/material.dart';
import '../models/delight.dart';
import '../models/recommendation.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';

class DelightBanner extends StatefulWidget {
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
  final VoidCallback? onWatchLater;
  final VoidCallback? onFavorite;

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
    this.onWatchLater,
    this.onFavorite,
  });

  @override
  State<DelightBanner> createState() => _DelightBannerState();
}

class _DelightBannerState extends State<DelightBanner> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final delight = widget.delight;
    final totalCount = widget.totalCount;
    final onView = widget.onView;
    final onLike = widget.onLike;
    final onDislike = widget.onDislike;
    final onChat = widget.onChat;
    final onDismiss = widget.onDismiss;
    final onWatchLater = widget.onWatchLater;
    final onFavorite = widget.onFavorite;
    final theme = Theme.of(context);
    final accessibilityLayout = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      decoration: BoxDecoration(
        gradient: AppGradients.brandSoft(context),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.brand, AppColors.sky],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '惊喜推荐',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        delight.hook.isNotEmpty
                            ? delight.hook
                            : sourcePlatformLabel(delight.sourcePlatform),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (totalCount > 1 && !accessibilityLayout)
                      _pagination(context),
                    if (onDismiss != null && !accessibilityLayout)
                      IconButton(
                        tooltip: '忽略',
                        icon: const Icon(Icons.close_rounded, size: 19),
                        onPressed: onDismiss,
                      ),
                  ],
                ),
                if (totalCount > 1 && accessibilityLayout)
                  Align(
                    alignment: Alignment.centerRight,
                    child: _pagination(context),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_expanded && delight.coverUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CoverImage(
                    url: delight.coverUrl,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: 12,
                  ),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_expanded && delight.coverUrl.isNotEmpty)
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
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                      if (delight.reason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          delight.reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: _expanded ? null : 2,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                      ],
                      if (delight.hook.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          delight.hook,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: _expanded ? null : 2,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                      ],
                      if (_expanded && delight.bodyText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '详细内容',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          delight.bodyText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                      if (delight.reason.isNotEmpty ||
                          delight.hook.isNotEmpty ||
                          delight.bodyText.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: _toggleExpanded,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 0,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 17,
                          ),
                          label: Text(_expanded ? '收起详情' : '展开详情'),
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
            child: accessibilityLayout
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _actionChip(
                        context,
                        '去看看',
                        Icons.open_in_new_rounded,
                        onView,
                        primary: true,
                      ),
                      _actionChip(
                        context,
                        delight.state == 'liked' ? '已喜欢' : '喜欢',
                        Icons.thumb_up_outlined,
                        delight.state == 'liked' ? null : onLike,
                      ),
                      if (onWatchLater != null)
                        _actionChip(
                          context,
                          '稍后再看',
                          Icons.schedule_rounded,
                          onWatchLater,
                        ),
                      if (onFavorite != null)
                        _actionChip(
                          context,
                          '收藏',
                          Icons.star_border_rounded,
                          onFavorite,
                        ),
                      _actionChip(
                        context,
                        '不感兴趣',
                        Icons.thumb_down_outlined,
                        onDislike,
                      ),
                      if (onChat != null)
                        _actionChip(
                          context,
                          '聊一聊',
                          Icons.chat_bubble_outline_rounded,
                          onChat,
                        ),
                      IconButton(
                        tooltip: '忽略',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: onDismiss,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _compactAction(
                          context,
                          label: '看看',
                          onTap: onView,
                          primary: true,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _compactAction(
                          context,
                          label: delight.state == 'liked' ? '已喜欢' : '喜欢',
                          onTap: delight.state == 'liked' ? null : onLike,
                        ),
                      ),
                      if (onWatchLater != null) ...[
                        const SizedBox(width: 6),
                        _compactAction(
                          context,
                          label: '稍后再看',
                          icon: Icons.schedule_rounded,
                          onTap: onWatchLater,
                        ),
                      ],
                      if (onFavorite != null) ...[
                        const SizedBox(width: 6),
                        _compactAction(
                          context,
                          label: '收藏',
                          icon: Icons.star_border_rounded,
                          onTap: onFavorite,
                        ),
                      ],
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: _compactAction(
                          context,
                          label: '不感兴趣',
                          onTap: onDislike,
                        ),
                      ),
                      if (onChat != null) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: _compactAction(
                            context,
                            label: '聊一聊',
                            onTap: onChat,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _compactAction(
    BuildContext context, {
    required String label,
    required VoidCallback? onTap,
    IconData? icon,
    bool primary = false,
  }) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: primary
              ? AppColors.brandStrong
              : context.appColors.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppRadius.small),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: icon == null ? null : 44,
              height: 44,
              child: Center(
                child: icon == null
                    ? Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: primary ? Colors.white : context.appColors.ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Icon(icon, size: 19, color: context.appColors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pagination(BuildContext context) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '上一条惊喜推荐',
            onPressed: widget.onPrev,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
          Text(
            '${widget.currentIndex + 1}/${widget.totalCount}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          IconButton(
            tooltip: '下一条惊喜推荐',
            onPressed: widget.onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool primary = false,
  }) {
    if (primary) {
      return FilledButton.tonalIcon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: context.appColors.surface.withValues(alpha: 0.88),
          foregroundColor: Theme.of(context).colorScheme.primary,
        ),
        icon: Icon(icon, size: 17),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: context.appColors.surface.withValues(alpha: 0.72),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
