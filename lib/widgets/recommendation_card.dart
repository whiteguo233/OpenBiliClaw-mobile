import 'package:flutter/material.dart';
import '../models/recommendation.dart';
import 'cover_image.dart';

class RecommendationCard extends StatelessWidget {
  final Recommendation rec;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final VoidCallback? onDislike;

  const RecommendationCard({super.key, required this.rec, this.onTap, this.onLike, this.onDislike});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(onTap: onTap,
      child: Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
        color: theme.colorScheme.surface,
        child: rec.isTextCard ? _buildTextCard(theme) : _buildVideoCard(theme)));
  }

  Widget _buildVideoCard(ThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Stack(children: [
        CoverImage(url: rec.coverUrl, height: 180),
        if (rec.sourcePlatform.isNotEmpty)
          Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
            child: Text(_sourceLabel(rec.sourcePlatform), style: const TextStyle(color: Colors.white, fontSize: 10)))),
      ]),
      Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rec.displayTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(rec.displayUpName, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (rec.expression.isNotEmpty) ...[const SizedBox(height: 6),
          Text(rec.expression, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary.withValues(alpha: 0.8)), maxLines: 2, overflow: TextOverflow.ellipsis)],
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          _feedbackIcon(Icons.thumb_up_outlined, rec.feedbackType == 'like', () => onLike?.call()),
          const SizedBox(width: 16),
          _feedbackIcon(Icons.thumb_down_outlined, rec.feedbackType == 'dislike', () => onDislike?.call()),
        ]),
      ])),
    ]);
  }

  Widget _buildTextCard(ThemeData theme) {
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (rec.sourcePlatform.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(4)),
          child: Text(_sourceLabel(rec.sourcePlatform), style: TextStyle(fontSize: 10, color: theme.colorScheme.onPrimaryContainer))),
      ]),
      const SizedBox(height: 8),
      Text(rec.displayTitle, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      if (rec.bodyText.isNotEmpty) ...[const SizedBox(height: 6),
        Text(rec.bodyText, style: theme.textTheme.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis)],
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        _feedbackIcon(Icons.thumb_up_outlined, rec.feedbackType == 'like', () => onLike?.call()),
        const SizedBox(width: 16), _feedbackIcon(Icons.thumb_down_outlined, rec.feedbackType == 'dislike', () => onDislike?.call()),
      ]),
    ]));
  }

  Widget _feedbackIcon(IconData icon, bool active, VoidCallback? onTap) {
    return GestureDetector(onTap: onTap,
      child: Icon(icon, size: 20, color: active ? const Color(0xFFFB7299) : Colors.grey));
  }

  String _sourceLabel(String s) {
    switch (s) {
      case 'bilibili': return 'B站';
      case 'xiaohongshu': return '小红书';
      case 'douyin': return '抖音';
      case 'youtube': return 'YouTube';
      case 'twitter': return 'X';
      case 'zhihu': return '知乎';
      default: return s;
    }
  }
}
