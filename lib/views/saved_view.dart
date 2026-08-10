import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/saved_item.dart';
import '../providers/saved_provider.dart';
import '../services/content_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chrome.dart';
import '../widgets/cover_image.dart';

class SavedView extends StatelessWidget {
  const SavedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SavedProvider>(
      builder: (context, provider, _) {
        return DefaultTabController(
          length: 2,
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
