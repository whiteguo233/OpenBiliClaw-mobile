import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/content_history.dart';
import '../models/saved_item.dart';
import '../providers/saved_provider.dart';
import '../services/content_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chrome.dart';
import '../widgets/back_to_top_fab.dart';
import '../widgets/cover_image.dart';

class SavedView extends StatelessWidget {
  const SavedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SavedProvider>(
      builder: (context, provider, _) {
        return DefaultTabController(
          length: 3,
          child: Column(
            children: [
              AppPageHeader(
                icon: Icons.video_library_rounded,
                title: '内容库',
                subtitle:
                    '${provider.watchLater.length} 条稍后看 · ${provider.favorites.length} 条收藏',
              ),
              Container(
                height: 48,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                  border: Border.all(color: AppColors.line),
                ),
                child: TabBar(
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  tabs: const [
                    Tab(text: '稍后再看'),
                    Tab(text: '我的收藏'),
                    Tab(text: '历史记录'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _SavedList(
                      kind: SavedListKind.watchLater,
                      items: provider.watchLater,
                      provider: provider,
                    ),
                    _SavedList(
                      kind: SavedListKind.favorite,
                      items: provider.favorites,
                      provider: provider,
                    ),
                    const _HistoryView(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SavedList extends StatelessWidget {
  const _SavedList({
    required this.kind,
    required this.items,
    required this.provider,
  });

  final SavedListKind kind;
  final List<SavedItem> items;
  final SavedProvider provider;

  @override
  Widget build(BuildContext context) {
    final pendingCount = items.where((item) => item.canSync).length;
    if (provider.loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: kind == SavedListKind.watchLater
          ? provider.loadWatchLater
          : provider.loadFavorites,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(AppRadius.large),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${items.length} 条本地内容',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        onPressed: pendingCount == 0 || provider.syncing
                            ? null
                            : () => _syncPending(context),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(44, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: provider.syncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync, size: 17),
                        label: Text('同步 $pendingCount 条'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.verified_user_outlined,
                          size: 14,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '默认只保存在本地；只有手动同步才会写入对应平台。',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                  if (provider.error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _errorBanner(context, provider.error),
                  ],
                ],
              ),
            ),
          ),
          if (items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _empty(context))
          else
            SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _itemCard(context, items[index]),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            kind == SavedListKind.watchLater ? '还没有稍后再看的内容' : '还没有收藏的内容',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(BuildContext context, SavedItem item) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.large),
        onTap: () => _open(context, item),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                height: 78,
                child: CoverImage(
                  url: item.coverUrl,
                  width: 104,
                  height: 78,
                  borderRadius: 12,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isNotEmpty ? item.title : item.contentId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _sourceChip(item.sourcePlatform),
                        if (item.authorName.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ] else
                          const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _syncChip(item),
                        const Spacer(),
                        if (item.canSync)
                          IconButton(
                            tooltip: '同步到平台',
                            onPressed: provider.syncing
                                ? null
                                : () => _syncOne(context, item),
                            icon: const Icon(Icons.sync_rounded, size: 19),
                          ),
                        IconButton(
                          tooltip: '只从本地移除',
                          onPressed: () => _confirmRemove(context, item),
                          icon: const Icon(Icons.delete_outline, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _feedbackChip(
                          Icons.thumb_up_outlined,
                          '喜欢',
                          () => _feedback(context, item, 'like'),
                        ),
                        const SizedBox(width: 6),
                        _feedbackChip(
                          Icons.thumb_down_outlined,
                          '不感兴趣',
                          () => _feedback(context, item, 'dislike'),
                        ),
                        const SizedBox(width: 6),
                        _feedbackChip(
                          Icons.chat_bubble_outline_rounded,
                          '聊一聊',
                          () => _comment(context, item),
                        ),
                        const Spacer(),
                        _crossToggle(context, item),
                      ],
                    ),
                    if (item.syncDetail.isNotEmpty)
                      Text(
                        item.syncDetail,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feedbackChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.ink),
            const SizedBox(width: 3),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _crossToggle(BuildContext context, SavedItem item) {
    final crossKind = kind == SavedListKind.watchLater
        ? SavedListKind.favorite
        : SavedListKind.watchLater;
    final active = provider.containsItem(crossKind, item);
    final icon = crossKind == SavedListKind.favorite
        ? Icons.star_border_rounded
        : Icons.bookmark_border_rounded;
    final label = crossKind == SavedListKind.favorite ? '收藏' : '稍后再看';
    return Tooltip(
      message: active ? '取消$label' : label,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () => _crossToggleItem(context, item, crossKind, active),
        icon: Icon(
          icon,
          size: 19,
          color: active ? AppColors.brandStrong : AppColors.ink,
        ),
      ),
    );
  }

  Future<void> _crossToggleItem(
    BuildContext context,
    SavedItem item,
    SavedListKind crossKind,
    bool active,
  ) async {
    final ok = await provider.toggleItem(crossKind, item, !active);
    if (!context.mounted) return;
    _message(
      context,
      ok
          ? (active ? '已从${crossKind.label}移除' : '已加入${crossKind.label}')
          : provider.error,
      error: !ok,
    );
  }

  Future<void> _feedback(
    BuildContext context,
    SavedItem item,
    String type,
  ) async {
    final ok = await provider.submitFeedback(item, feedbackType: type);
    if (!context.mounted) return;
    _message(
      context,
      ok ? (type == 'like' ? '已记下：喜欢' : '已记下：不感兴趣') : provider.error,
      error: !ok,
    );
  }

  Future<void> _comment(BuildContext context, SavedItem item) async {
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
              '想围绕这条聊什么？',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '例如：这类内容我一般看中的是…',
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
      final ok = await provider.submitFeedback(
        item,
        feedbackType: 'comment',
        note: note,
      );
      if (!context.mounted) return;
      _message(context, ok ? '已提交聊天线索' : provider.error, error: !ok);
    }
  }

  Widget _sourceChip(String source) {
    final label = switch (source) {
      'bilibili' => 'B站',
      'xiaohongshu' => '小红书',
      'douyin' => '抖音',
      'youtube' => 'YouTube',
      'twitter' => 'X',
      'zhihu' => '知乎',
      'reddit' => 'Reddit',
      'bangumi' => 'Bangumi',
      _ => source,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF5AA9FF).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: const TextStyle(fontSize: 9)),
    );
  }

  Widget _syncChip(SavedItem item) {
    final color = item.synced
        ? const Color(0xFF30B980)
        : item.errorMessage.isNotEmpty
        ? const Color(0xFFEF7A86)
        : const Color(0xFF5AA9FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(item.syncLabel, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _errorBanner(BuildContext context, String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        error,
        style: const TextStyle(fontSize: 12, color: Colors.red),
      ),
    );
  }

  Future<void> _open(BuildContext context, SavedItem item) async {
    final opened = await ContentLauncher.openSaved(item);
    if (context.mounted && !opened) {
      _message(context, '没有可打开的内容链接', error: true);
    }
  }

  Future<void> _syncPending(BuildContext context) async {
    final ok = await provider.syncPending(kind);
    if (!context.mounted) return;
    _message(context, ok ? '平台同步任务已完成' : provider.error, error: !ok);
  }

  Future<void> _syncOne(BuildContext context, SavedItem item) async {
    final ok = await provider.syncOne(kind, item);
    if (!context.mounted) return;
    _message(context, ok ? '同步状态已更新' : provider.error, error: !ok);
  }

  Future<void> _confirmRemove(BuildContext context, SavedItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('从本地移除？'),
        content: Text(
          '${item.title.isNotEmpty ? item.title : '这条内容'}\n\n不会删除平台账号里已有的稍后再看或收藏。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('只从本地移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await provider.remove(kind, item);
    if (!context.mounted) return;
    _message(context, ok ? '已从本地移除' : provider.error, error: !ok);
  }

  void _message(BuildContext context, String message, {bool error = false}) {
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

/// Bounded 30-day content history: opened, surfaced-but-unopened and recently
/// removed, aligned with the web / extension content library history tab.
class _HistoryView extends StatefulWidget {
  const _HistoryView();

  static const List<_HistorySectionSpec> _sections = [
    _HistorySectionSpec(
      category: ContentHistoryCategory.clicked,
      eyebrow: 'Opened',
      title: '主动点开过',
      description: '你明确选择打开的内容，最近一次操作排在前面。',
    ),
    _HistorySectionSpec(
      category: ContentHistoryCategory.shown,
      eyebrow: 'Passed by',
      title: '出现过，但没点开',
      description: '曾进入推荐列表、但近 30 天没有打开记录的内容。',
    ),
    _HistorySectionSpec(
      category: ContentHistoryCategory.removed,
      eyebrow: 'Recently removed',
      title: '最近移除',
      description: '从保存列表移除、忽略或标记不感兴趣的内容。',
    ),
  ];

  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // The tab is lazily built by TabBarView, so kick the first load here in
    // case the user reaches the tab before HomeView's eager preload lands.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<SavedProvider>();
      if (!provider.historyLoadedOnce) {
        unawaited(provider.loadAllHistory());
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SavedProvider>(
      builder: (context, provider, _) {
        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: provider.loadAllHistory,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _HistoryHeader(provider: provider)),
                  for (final spec in _HistoryView._sections) ...[
                    SliverToBoxAdapter(
                      child: _HistorySectionHeader(spec: spec),
                    ),
                    _HistorySectionBody(spec: spec),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
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
}

class _HistorySectionSpec {
  final ContentHistoryCategory category;
  final String eyebrow;
  final String title;
  final String description;

  const _HistorySectionSpec({
    required this.category,
    required this.eyebrow,
    required this.title,
    required this.description,
  });
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.provider});

  final SavedProvider provider;

  @override
  Widget build(BuildContext context) {
    final total = ContentHistoryCategory.values.fold<int>(
      0,
      (sum, category) => sum + provider.historyTotal(category),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 4),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                total > 0 ? '$total 条近 30 天记录' : '近 30 天记录',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (provider.historyBusy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '你点开过、刷到过或移除过的内容都会收在这里；重新加入稍后看或收藏可恢复。',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (provider.error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                provider.error,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistorySectionHeader extends StatelessWidget {
  const _HistorySectionHeader({required this.spec});

  final _HistorySectionSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.eyebrow.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.brandStrong,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(spec.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            spec.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySectionBody extends StatelessWidget {
  const _HistorySectionBody({required this.spec});

  final _HistorySectionSpec spec;

  @override
  Widget build(BuildContext context) {
    return Consumer<SavedProvider>(
      builder: (context, provider, _) {
        final items = provider.historyItems(spec.category);
        final loading = provider.historyLoading(spec.category);
        final error = provider.historyError(spec.category);
        if (loading && items.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (error.isNotEmpty && items.isEmpty) {
          return SliverToBoxAdapter(
            child: _historyError(context, provider, spec.category, error),
          );
        }
        if (items.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  provider.historyLoadedOnce ? '还没有记录' : '正在整理这段历史…',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            ),
          );
        }
        return SliverList.builder(
          itemCount:
              items.length + (provider.historyHasMore(spec.category) ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return _loadMoreButton(context, provider, spec.category);
            }
            return _HistoryCard(
              spec: spec,
              item: items[index],
              provider: provider,
            );
          },
        );
      },
    );
  }

  Widget _historyError(
    BuildContext context,
    SavedProvider provider,
    ContentHistoryCategory category,
    String error,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 17),
          const SizedBox(width: 8),
          Expanded(child: Text(error, style: const TextStyle(fontSize: 12))),
          TextButton(
            onPressed: () => provider.loadHistory(category),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _loadMoreButton(
    BuildContext context,
    SavedProvider provider,
    ContentHistoryCategory category,
  ) {
    final loadingMore = provider.historyLoadingMore(category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: loadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: () => provider.loadMoreHistory(category),
                icon: const Icon(Icons.expand_more),
                label: const Text('加载更多'),
              ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.spec,
    required this.item,
    required this.provider,
  });

  final _HistorySectionSpec spec;
  final ContentHistoryItem item;
  final SavedProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRemoved = spec.category == ContentHistoryCategory.removed;
    final contextEntries = item.contexts.isEmpty && item.context.isNotEmpty
        ? [
            ContentHistoryContext(
              context: item.context,
              occurredAt: item.occurredAt,
              restored: item.restored,
            ),
          ]
        : item.contexts;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.large),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    height: 72,
                    child: CoverImage(
                      url: item.coverUrl,
                      width: 96,
                      height: 72,
                      borderRadius: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title.isNotEmpty ? item.title : item.contentId,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _sourceChip(item.sourcePlatform),
                            if (item.authorName.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.authorName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            ] else
                              const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            _eventChip(
                              item.eventLabelFor(spec.category),
                              isRemoved
                                  ? const Color(0xFFEF7A86)
                                  : const Color(0xFF5AA9FF),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(item.occurredAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isRemoved && contextEntries.isNotEmpty) ...[
                const Divider(height: 16),
                ...contextEntries.map((entry) => _removalRow(context, entry)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _removalRow(BuildContext context, ContentHistoryContext entry) {
    final busy = provider.restoreBusy(item.itemKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.removalLabel,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (entry.restorable)
            TextButton(
              onPressed: busy || entry.restored
                  ? null
                  : () => _restore(context, entry),
              child: Text(
                entry.restored ? '已恢复' : entry.restoreLabel,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceChip(String source) {
    final label = switch (source) {
      'bilibili' => 'B站',
      'xiaohongshu' => '小红书',
      'douyin' => '抖音',
      'youtube' => 'YouTube',
      'twitter' => 'X',
      'zhihu' => '知乎',
      'reddit' => 'Reddit',
      'bangumi' => 'Bangumi',
      _ => source,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF5AA9FF).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label, style: const TextStyle(fontSize: 9)),
    );
  }

  Widget _eventChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Future<void> _open(BuildContext context) async {
    unawaited(provider.reportHistoryClick(spec.category, item));
    final opened = await ContentLauncher.open(
      sourcePlatform: item.sourcePlatform,
      contentId: item.contentId,
      contentUrl: item.contentUrl,
    );
    if (context.mounted && !opened) {
      _message(context, '没有可打开的内容链接', error: true);
    }
  }

  Future<void> _restore(
    BuildContext context,
    ContentHistoryContext entry,
  ) async {
    final ok = await provider.restoreFromHistory(
      spec.category,
      item,
      entry.context,
      listKind: entry.context == 'favorite' ? 'favorite' : 'watch_later',
    );
    if (!ok && context.mounted) {
      _message(context, provider.error, error: true);
    }
  }

  void _message(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red[700] : null,
        ),
      );
  }

  String _formatTime(String value) {
    final text = value.trim();
    if (text.isEmpty) return '时间未知';
    // Backend returns "YYYY-MM-DD HH:MM:SS" (UTC) or ISO-8601.
    final iso = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(text)
        ? '${text.replaceFirst(' ', 'T')}Z'
        : text;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return text;
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }
}
