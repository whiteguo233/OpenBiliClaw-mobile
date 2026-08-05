import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recommend_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/saved_provider.dart';
import 'recommend_view.dart';
import 'chat_view.dart';
import 'profile_view.dart';
import 'saved_view.dart';
import 'settings_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _currentIndex = 0;

  final _pages = const [
    RecommendView(),
    ChatView(),
    ProfileView(),
    SavedView(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final rec = context.read<RecommendProvider>();
    final chat = context.read<ChatProvider>();
    final profile = context.read<ProfileProvider>();
    final saved = context.read<SavedProvider>();
    await Future.wait([rec.load(), chat.loadTurns(), profile.load(), profile.loadNotifications(), saved.loadWatchLater(), saved.loadFavorites()]);
    rec.startPolling();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenBiliClaw'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined, size: 22),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsView()));
              _loadData();
            }),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: const Color(0xFFFB7299).withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore, color: Color(0xFFFB7299)), label: '推荐'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat, color: Color(0xFFFB7299)), label: '对话'),
          NavigationDestination(icon: Icon(Icons.psychology_outlined), selectedIcon: Icon(Icons.psychology, color: Color(0xFFFB7299)), label: '画像'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), selectedIcon: Icon(Icons.bookmark, color: Color(0xFFFB7299)), label: '收藏'),
        ],
      ),
    );
  }
}
