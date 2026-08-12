import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/recommend_provider.dart';
import '../providers/saved_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_chrome.dart';
import '../widgets/message_inbox.dart';
import 'chat_view.dart';
import 'profile_view.dart';
import 'recommend_view.dart';
import 'saved_view.dart';
import 'settings_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _currentIndex = 0;
  final Set<int> _loadedTabs = {};
  bool _providersReady = false;
  bool _disposed = false;
  late RecommendProvider _recommendProvider;
  late ChatProvider _chatProvider;
  late ProfileProvider _profileProvider;
  late SavedProvider _savedProvider;
  late AuthProvider _authProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTab(0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_providersReady) return;
    _recommendProvider = context.read<RecommendProvider>();
    _chatProvider = context.read<ChatProvider>();
    _profileProvider = context.read<ProfileProvider>();
    _savedProvider = context.read<SavedProvider>();
    _authProvider = context.read<AuthProvider>();
    _providersReady = true;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_providersReady) {
      _recommendProvider.stopPolling();
      _chatProvider.stopHistorySync();
    }
    super.dispose();
  }

  Future<void> _loadTab(int index, {bool force = false}) async {
    if (_disposed || !mounted || !_providersReady) return;
    if (!force && _loadedTabs.contains(index)) return;
    _loadedTabs.add(index);
    switch (index) {
      case 0:
        await _recommendProvider.load();
        if (_disposed || !mounted) return;
        _recommendProvider.startPolling();
        unawaited(_savedProvider.loadAll());
        unawaited(_chatProvider.loadPendingConfirmations());
        unawaited(_profileProvider.loadNotifications());
        return;
      case 1:
        await _savedProvider.loadAll();
        if (_disposed || !mounted) return;
        await _savedProvider.loadAllHistory();
        return;
      case 2:
        await _profileProvider.load();
        if (_disposed || !mounted) return;
        await _profileProvider.loadNotifications();
        return;
      case 3:
        _chatProvider.startHistorySync();
        return;
    }
  }

  void _selectTab(int index) {
    if (_currentIndex == 3 && index != 3) {
      _chatProvider.stopHistorySync();
    }
    setState(() => _currentIndex = index);
    unawaited(_loadTab(index));
  }

  void _startContextualChat(
    String scope,
    String subjectId,
    String subjectTitle,
  ) {
    _chatProvider.startContextualChat(scope, subjectId, subjectTitle);
    _selectTab(3);
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsView()),
    );
    if (_disposed || !mounted) return;
    _recommendProvider.stopPolling();
    _chatProvider.stopHistorySync();
    await _authProvider.checkStatus();
    if (_disposed || !mounted) return;
    _loadedTabs.clear();
    await _loadTab(_currentIndex, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appColors;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactChrome = screenWidth < 350 || textScale > 1.3;
    final pages = [
      RecommendView(onStartChat: _startContextualChat),
      const SavedView(),
      const ProfileView(),
      const ChatView(),
    ];
    return Consumer3<RecommendProvider, ChatProvider, ProfileProvider>(
      builder: (context, recommend, chat, profile, _) {
        final profilePending =
            profile.probes.length +
            profile.avoidanceProbes.length +
            (profile.cognitionNotification == null ? 0 : 1);
        final inboxCount = profilePending + chat.pendingCount;
        return Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            titleSpacing: compactChrome ? 12 : null,
            title: Semantics(
              header: true,
              label: 'OpenBiliClaw',
              child: ExcludeSemantics(
                child: Text(
                  'OpenBiliClaw',
                  style: TextStyle(
                    color: AppColors.brandStrong,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.35,
                  ),
                ),
              ),
            ),
            backgroundColor: palette.background.withValues(alpha: 0.96),
            actions: [
              AppStatusDot(online: recommend.online, showLabel: !compactChrome),
              const SizedBox(width: 2),
              IconButton(
                tooltip: inboxCount > 0 ? '$inboxCount 条待处理消息' : '暂无待处理消息',
                onPressed: () async {
                  await MessageInbox.show(context);
                  if (!_disposed && mounted && context.mounted) {
                    // A probe "多聊聊" may have started a contextual chat.
                    final chat = context.read<ChatProvider>();
                    if (chat.composeContext.active) {
                      _selectTab(3);
                    }
                  }
                },
                icon: inboxCount > 0
                    ? MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.2,
                        child: Badge.count(
                          count: inboxCount,
                          backgroundColor: AppColors.brandStrong,
                          child: const Icon(Icons.notifications_none_rounded),
                        ),
                      )
                    : const Icon(Icons.notifications_none_rounded),
              ),
              IconButton(
                tooltip: '连接设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
              const SizedBox(width: 2),
            ],
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.background(context),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: SizedBox(
                    width: constraints.maxWidth.clamp(0, 760).toDouble(),
                    height: constraints.maxHeight,
                    child: IndexedStack(index: _currentIndex, children: pages),
                  ),
                );
              },
            ),
          ),
          bottomNavigationBar: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: _HomeBottomNavigation(
              currentIndex: _currentIndex,
              pendingCount: chat.pendingCount,
              onSelected: (index) {
                HapticFeedback.selectionClick();
                _selectTab(index);
              },
            ),
          ),
        );
      },
    );
  }
}

class _HomeBottomNavigation extends StatelessWidget {
  const _HomeBottomNavigation({
    required this.currentIndex,
    required this.pendingCount,
    required this.onSelected,
  });

  final int currentIndex;
  final int pendingCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.appColors;
    if (theme.platform == TargetPlatform.iOS) {
      return CupertinoTabBar(
        currentIndex: currentIndex,
        onTap: onSelected,
        backgroundColor: palette.surface.withValues(alpha: 0.96),
        activeColor: theme.colorScheme.primary,
        inactiveColor: palette.inkMuted,
        iconSize: 21,
        height: 48,
        border: Border(top: BorderSide(color: palette.line, width: 0.5)),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.sparkles),
            label: '推荐',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.rectangle_stack),
            activeIcon: Icon(CupertinoIcons.rectangle_stack_fill),
            label: '内容库',
          ),
          const BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_crop_circle),
            activeIcon: Icon(CupertinoIcons.person_crop_circle_fill),
            label: '画像',
          ),
          BottomNavigationBarItem(
            icon: _chatIcon(
              const Icon(CupertinoIcons.chat_bubble),
              pendingCount,
            ),
            activeIcon: _chatIcon(
              const Icon(CupertinoIcons.chat_bubble_fill),
              pendingCount,
            ),
            label: '对话',
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.line)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onSelected,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_mosaic_outlined),
            selectedIcon: Icon(Icons.auto_awesome_mosaic_rounded),
            label: '推荐',
          ),
          const NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: '内容库',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_search_outlined),
            selectedIcon: Icon(Icons.person_search_rounded),
            label: '画像',
          ),
          NavigationDestination(
            icon: _chatIcon(
              const Icon(Icons.chat_bubble_outline_rounded),
              pendingCount,
            ),
            selectedIcon: _chatIcon(
              const Icon(Icons.chat_bubble_rounded),
              pendingCount,
            ),
            label: '对话',
          ),
        ],
      ),
    );
  }

  Widget _chatIcon(Widget icon, int count) {
    if (count <= 0) return icon;
    return Badge.count(
      count: count,
      backgroundColor: AppColors.brandStrong,
      child: icon,
    );
  }
}
