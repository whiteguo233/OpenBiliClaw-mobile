import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../api/utils.dart';
import '../providers/saved_provider.dart';

class SavedView extends StatelessWidget {
  const SavedView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = context.read<ApiClient>();
    final baseUrl = client.baseUrl;
    final token = client.sessionToken;
    return Consumer<SavedProvider>(builder: (context, sp, _) {
      return DefaultTabController(length: 2, child: Scaffold(
        appBar: AppBar(title: const Text('收藏'), centerTitle: true, backgroundColor: theme.colorScheme.surface, elevation: 0,
          bottom: TabBar(labelColor: const Color(0xFFFB7299), unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFFFB7299), tabs: const [
            Tab(text: '稍后再看'), Tab(text: '我的收藏'),
          ])),
        body: TabBarView(children: [
          _buildList(theme, baseUrl, token, sp.watchLater, '还没有稍后再看的内容', () => sp.loadWatchLater()),
          _buildList(theme, baseUrl, token, sp.favorites, '还没有收藏的内容', () => sp.loadFavorites()),
        ]),
      ));
    });
  }

  Widget _buildList(ThemeData theme, String baseUrl, String token, List<SavedItem> items, String emptyText, VoidCallback onRefresh) {
    return RefreshIndicator(onRefresh: () async => onRefresh(),
      child: ListView.separated(padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final isBili = item.coverUrl.contains('hdslb.com');
          final imgUrl = isBili ? item.coverUrl : proxyImageUrl(item.coverUrl, baseUrl, token: token);
          final imgHeaders = isBili || token.isEmpty ? null : {'Cookie': 'obc_session=$token'};
          return ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 4),
            leading: item.coverUrl.isNotEmpty
              ? ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: SizedBox(width: 64, height: 48,
                    child: Image.network(imgUrl, headers: imgHeaders, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: Colors.grey[200]))))
              : Container(width: 64, height: 48, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.movie_outlined, color: Colors.grey)),
            title: Text(item.title.isNotEmpty ? item.title : '未命名', style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: item.upName.isNotEmpty ? Text(item.upName, style: theme.textTheme.bodySmall) : null,
          );
        }));
  }
}
