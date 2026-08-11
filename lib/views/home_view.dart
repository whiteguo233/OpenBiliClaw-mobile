import 'dart:async';

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
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBrandMark(size: 30),
                SizedBox(width: 9),
                Text(
                  'OpenBiliClaw',
                  style: TextStyle(
                    color: AppColors.brandStrong,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.25,
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.background.withValues(alpha: 0.96),
            actions: [
              AppStatusDot(
                online: recommend.online,
                showLabel: MediaQuery.sizeOf(context).width >= 380,
              ),
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
                    ? Badge.count(
                        count: inboxCount,
                        backgroundColor: AppColors.brandStrong,
                        child: const Icon(Icons.notifications_none_rounded),
                      )
                    : const Icon(Icons.notifications_none_rounded),
              ),
              IconButton(
                tooltip: '连接设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: DecoratedBox(
            decoration: const BoxDecoration(gradient: AppGradients.background),
            child: IndexedStack(index: _currentIndex, children: pages),
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                HapticFeedback.selectionClick();
                _selectTab(index);
              },
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
                  icon: chat.pendingCount > 0
                      ? Badge.count(
                          count: chat.pendingCount,
                          backgroundColor: AppColors.brandStrong,
                          child: const Icon(Icons.chat_bubble_outline_rounded),
                        )
                      : const Icon(Icons.chat_bubble_outline_rounded),
                  selectedIcon: chat.pendingCount > 0
                      ? Badge.count(
                          count: chat.pendingCount,
                          backgroundColor: AppColors.brandStrong,
                          child: const Icon(Icons.chat_bubble_rounded),
                        )
                      : const Icon(Icons.chat_bubble_rounded),
                  label: '对话',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
