import 'package:flutter/material.dart';

import '../models/bilibili_interaction.dart';
import '../models/bilibili_play.dart';
import 'bilibili_video_layout.dart';
import 'cover_image.dart';

class BilibiliVideoIntroduction extends StatefulWidget {
  const BilibiliVideoIntroduction({
    super.key,
    required this.title,
    required this.bvid,
    required this.actions,
    required this.onSelectPage,
    required this.onOpenRelated,
    this.creator,
    this.description = '',
    this.recommendationReason = '',
    this.viewCount,
    this.danmakuCount,
    this.publishedAt = 0,
    this.pages = const [],
    this.selectedCid,
    this.related = const [],
    this.relatedLoading = false,
    this.relatedFailed = false,
    this.onRetryRelated,
    this.switchingPage = false,
  });

  final String title;
  final String bvid;
  final Widget? creator;
  final List<Widget> actions;
  final String description;
  final String recommendationReason;
  final int? viewCount;
  final int? danmakuCount;
  final int publishedAt;
  final List<BilibiliPlayPage> pages;
  final int? selectedCid;
  final bool switchingPage;
  final ValueChanged<BilibiliPlayPage> onSelectPage;
  final List<BilibiliRelatedVideo> related;
  final ValueChanged<BilibiliRelatedVideo> onOpenRelated;
  final bool relatedLoading;
  final bool relatedFailed;
  final VoidCallback? onRetryRelated;

  @override
  State<BilibiliVideoIntroduction> createState() =>
      _BilibiliVideoIntroductionState();
}

class _BilibiliVideoIntroductionState extends State<BilibiliVideoIntroduction> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = widget.publishedAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(widget.publishedAt * 1000)
        : null;
    return CustomScrollView(
      key: const PageStorageKey('bilibili-introduction'),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.creator != null) widget.creator!,
              Semantics(
                expanded: _expanded,
                child: InkWell(
                  key: const ValueKey('bilibili-video-title'),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: _expanded ? null : 2,
                            overflow: _expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    if (widget.viewCount != null)
                      _Metric(
                        Icons.play_circle_outline_rounded,
                        '${formatBilibiliCount(widget.viewCount!)}播放',
                      ),
                    if (widget.danmakuCount != null)
                      _Metric(
                        Icons.subtitles_outlined,
                        '${formatBilibiliCount(widget.danmakuCount!)}弹幕',
                      ),
                    if (date != null)
                      Text(
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        widget.bvid,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (widget.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.description,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: colors.onSurface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final action in widget.actions)
                      Expanded(child: action),
                  ],
                ),
              ),
              if (widget.pages.length > 1)
                _EpisodePicker(
                  pages: widget.pages,
                  selectedCid: widget.selectedCid,
                  onSelect: widget.onSelectPage,
                  busy: widget.switchingPage,
                ),
              if (widget.recommendationReason.isNotEmpty)
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    minTileHeight: 48,
                    leading: Icon(
                      Icons.auto_awesome_outlined,
                      size: 18,
                      color: colors.primary,
                    ),
                    title: const Text('推荐理由', style: TextStyle(fontSize: 13)),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.recommendationReason,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.6,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '相关推荐',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        SliverList.builder(
          itemCount: widget.related.length,
          itemBuilder: (context, index) => _RelatedVideoTile(
            video: widget.related[index],
            onTap: () => widget.onOpenRelated(widget.related[index]),
          ),
        ),
        if (widget.related.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: widget.relatedLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : widget.relatedFailed
                    ? TextButton(
                        onPressed: widget.onRetryRelated,
                        child: const Text('推荐加载失败，点击重试'),
                      )
                    : Text(
                        '暂无相关推荐',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }
}

class BilibiliVideoAction extends StatelessWidget {
  const BilibiliVideoAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.count,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int? count;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = active ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: active,
      label: '$label${count != null ? '，$count' : ''}',
      hint: onLongPress != null ? '长按一键三连' : null,
      child: Tooltip(
        message: onLongPress != null ? '$label · 长按三连' : label,
        child: InkWell(
          onTap: busy ? null : onTap,
          onLongPress: busy ? null : onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 28,
                    width: 28,
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(3),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(icon, color: color, size: 27),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    count != null && count! > 0
                        ? formatBilibiliCount(count!)
                        : label,
                    style: TextStyle(fontSize: 12, color: color),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodePicker extends StatelessWidget {
  const _EpisodePicker({
    required this.pages,
    required this.selectedCid,
    required this.onSelect,
    required this.busy,
  });
  final List<BilibiliPlayPage> pages;
  final int? selectedCid;
  final ValueChanged<BilibiliPlayPage> onSelect;
  final bool busy;

  Future<void> _showAll(BuildContext context) async {
    final selected = await showModalBottomSheet<BilibiliPlayPage>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '选集',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: pages.length,
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    return ListTile(
                      selected: page.cid == selectedCid,
                      leading: Text('${page.page}'.padLeft(2, '0')),
                      title: Text(page.part),
                      subtitle: page.duration > 0
                          ? Text(formatBilibiliDuration(page.duration))
                          : null,
                      trailing: page.cid == selectedCid
                          ? const Icon(Icons.equalizer_rounded)
                          : null,
                      onTap: busy ? null : () => Navigator.pop(context, page),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final index = pages.indexWhere((page) => page.cid == selectedCid);
    return Column(
      children: [
        ListTile(
          title: const Text(
            '选集',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${index < 0 ? 1 : index + 1}/${pages.length}',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
          onTap: () => _showAll(context),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              // Keep the current episode visible even when selected from the sheet.
              for (final page in pages.skip(index < 0 ? 0 : index).take(6))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: page.cid == selectedCid
                        ? colors.primary.withValues(alpha: 0.08)
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    child: Semantics(
                      selected: page.cid == selectedCid,
                      child: InkWell(
                        onTap: busy ? null : () => onSelect(page),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 168,
                          constraints: const BoxConstraints(minHeight: 64),
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '${page.page}. ${page.part}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: page.cid == selectedCid
                                  ? colors.primary
                                  : colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RelatedVideoTile extends StatelessWidget {
  const _RelatedVideoTile({required this.video, required this.onTap});
  final BilibiliRelatedVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth * 0.42).clamp(100.0, 200.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    CoverImage(
                      url: video.coverUrl,
                      sourcePlatform: 'bilibili',
                      width: width,
                      height: width * 9 / 16,
                      borderRadius: 6,
                    ),
                    if (video.duration > 0)
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            formatBilibiliDuration(video.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        video.upName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _Metric(
                            Icons.play_circle_outline_rounded,
                            formatBilibiliCount(video.view),
                          ),
                          if (video.danmaku > 0)
                            _Metric(
                              Icons.subtitles_outlined,
                              formatBilibiliCount(video.danmaku),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
