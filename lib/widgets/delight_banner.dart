import 'package:flutter/material.dart';
import '../models/delight.dart';
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
  final VoidCallback? onDismiss;

  const DelightBanner({super.key, required this.delight, this.currentIndex = 0, this.totalCount = 1, this.onPrev, this.onNext, this.onView, this.onLike, this.onDislike, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFFFB7299).withValues(alpha:  0.12),
          const Color(0xFF5AA9FF).withValues(alpha:  0.08)]),
        borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Text('惊喜推荐', style: theme.textTheme.labelSmall?.copyWith(color: const Color(0xFFFB7299), fontWeight: FontWeight.w600)),
            const Spacer(),
            if (totalCount > 1) Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(onTap: onPrev, child: const Icon(Icons.chevron_left, size: 20, color: Colors.grey)),
              Text('${currentIndex + 1}/$totalCount', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              GestureDetector(onTap: onNext, child: const Icon(Icons.chevron_right, size: 20, color: Colors.grey)),
            ]),
          ])),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (delight.coverUrl.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 16, bottom: 12),
            child: ClipRRect(borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 80, height: 60, child: CoverImage(url: delight.coverUrl, width: 80, height: 60, borderRadius: 8)))),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 16, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(delight.title.isNotEmpty ? delight.title : '这条惊喜推荐还没起好标题',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (delight.reason.isNotEmpty) ...[const SizedBox(height: 4),
              Text(delight.reason, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)],
          ]))),
        ]),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          _actionChip('去看看', () => onView?.call()),
          const SizedBox(width: 8),
          _actionChip('喜欢', () => onLike?.call()),
          const SizedBox(width: 8),
          _actionChip('不感兴趣', () => onDislike?.call()),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onDismiss, padding: EdgeInsets.zero, constraints: const BoxConstraints(), color: Colors.grey),
        ])),
      ]));
  }

  Widget _actionChip(String label, VoidCallback? onTap) {
    return GestureDetector(onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha:  0.8), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
        child: Text(label, style: const TextStyle(fontSize: 12))));
  }
}
