import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Neutral reading surfaces beneath the black player, in either app theme.
ThemeData bilibiliVideoTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final colors = base.colorScheme.copyWith(
    primary: dark ? AppColors.brandStrongDark : AppColors.brandStrong,
    surface: dark ? const Color(0xFF17181A) : Colors.white,
    onSurface: dark ? const Color(0xFFF1F2F3) : const Color(0xFF18191C),
    onSurfaceVariant: dark ? const Color(0xFFB4B6BC) : const Color(0xFF686B73),
    surfaceContainerHighest: dark
        ? const Color(0xFF28292D)
        : const Color(0xFFF4F4F6),
    outlineVariant: dark ? const Color(0xFF34363B) : const Color(0xFFE8E8ED),
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    textTheme: base.textTheme.apply(
      bodyColor: colors.onSurface,
      displayColor: colors.onSurface,
    ),
    dividerColor: colors.outlineVariant,
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 0.5,
      space: 1,
    ),
    iconTheme: IconThemeData(color: colors.onSurfaceVariant),
  );
}

/// Keeps playback and navigation fixed while each tab owns its scroll position.
/// The media player is supplied by the route so tab changes never reopen it.
class BilibiliVideoLayout extends StatefulWidget {
  const BilibiliVideoLayout({
    super.key,
    required this.player,
    required this.introduction,
    required this.comments,
    required this.aspectRatio,
    required this.commentTotal,
    required this.danmakuEnabled,
    required this.onToggleDanmaku,
    required this.onDanmakuSettings,
    this.keyboardVisible = false,
  });

  final Widget player;
  final Widget introduction;
  final Widget comments;
  final double aspectRatio;
  final int commentTotal;
  final bool danmakuEnabled;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onDanmakuSettings;
  final bool keyboardVisible;

  @override
  State<BilibiliVideoLayout> createState() => _BilibiliVideoLayoutState();
}

class _BilibiliVideoLayoutState extends State<BilibiliVideoLayout>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_tabChanged);
  bool _introScrolled = false;
  int _activeTab = 0;

  void _tabChanged() {
    if (_activeTab != _tabs.index) setState(() => _activeTab = _tabs.index);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 22;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            _activeTab == 1 || _introScrolled || widget.keyboardVisible;
        final ratio = widget.aspectRatio > 0 ? widget.aspectRatio : 16 / 9;
        final tabHeight = math.max(
          48.0,
          MediaQuery.textScalerOf(context).scale(14) + 28,
        );
        // Reserve room for comments and their composer even with the keyboard.
        final maxHeight = math.min(
          constraints.maxHeight * 0.6,
          math.max(0.0, constraints.maxHeight - tabHeight - 160),
        );
        final playerHeight = math.min(
          math.min(
            constraints.maxWidth / (compact && ratio < 1 ? 16 / 9 : ratio),
            480.0,
          ),
          maxHeight,
        );
        return Column(
          children: [
            SizedBox(
              key: const ValueKey('bilibili-player-area'),
              width: double.infinity,
              height: playerHeight,
              child: ColoredBox(color: Colors.black, child: widget.player),
            ),
            Material(
              color: colors.surface,
              child: SizedBox(
                height: tabHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: TabBar(
                        controller: _tabs,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        padding: const EdgeInsets.only(left: 8),
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        labelColor: colors.primary,
                        unselectedLabelColor: colors.onSurfaceVariant,
                        labelStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        indicatorColor: AppColors.brand,
                        indicatorSize: TabBarIndicatorSize.label,
                        dividerHeight: 0,
                        tabs: [
                          const Tab(text: '简介'),
                          Tab(
                            text: widget.commentTotal > 0 && !largeText
                                ? '评论 ${formatBilibiliCount(widget.commentTotal)}'
                                : '评论',
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      toggled: widget.danmakuEnabled,
                      child: IconButton(
                        tooltip: widget.danmakuEnabled ? '关闭弹幕' : '开启弹幕',
                        color: widget.danmakuEnabled
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        onPressed: widget.onToggleDanmaku,
                        icon: Icon(
                          widget.danmakuEnabled
                              ? Icons.subtitles_outlined
                              : Icons.subtitles_off_outlined,
                          size: 22,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '弹幕设置',
                      onPressed: widget.onDanmakuSettings,
                      icon: const Icon(Icons.tune_rounded, size: 20),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.depth != 0 ||
                          notification.metrics.axis != Axis.vertical) {
                        return false;
                      }
                      final offset = notification.metrics.pixels;
                      // Hysteresis avoids shrinking/expanding repeatedly at the threshold.
                      final scrolled =
                          offset > 80 || (_introScrolled && offset > 0);
                      if (_introScrolled != scrolled) {
                        setState(() => _introScrolled = scrolled);
                      }
                      return false;
                    },
                    child: _KeepAliveTab(child: widget.introduction),
                  ),
                  _KeepAliveTab(child: widget.comments),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});
  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

String formatBilibiliCount(int value) {
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}亿';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}万';
  }
  return '$value';
}

String formatBilibiliDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final tail =
      '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  return hours > 0 ? '$hours:$tail' : tail;
}
