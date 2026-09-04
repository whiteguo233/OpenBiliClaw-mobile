import 'dart:async';

import 'package:flutter/material.dart';

class DanmakuItem {
  const DanmakuItem({
    required this.time,
    required this.text,
    this.color = Colors.white,
  });

  final Duration time;
  final String text;
  final Color color;
}

/// Lightweight Bilibili-style scrolling danmaku overlay.
///
/// It watches the player position stream and renders the comments whose
/// timestamp has just passed and that are still within their scroll window.
/// Each visible comment animates from the right edge of the video to the
/// left, leaving the screen completely before it is removed.
class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({
    super.key,
    required this.position,
    required this.items,
    this.enabled = true,
  });

  final Stream<Duration> position;
  final List<DanmakuItem> items;
  final bool enabled;

  /// How long a danmaku takes to cross the screen. A comment stays visible
  /// for exactly this long after its timestamp passes.
  static const Duration scrollDuration = Duration(seconds: 7);

  /// Maximum number of danmaku rendered at once.
  static const int maxVisible = 20;

  /// Number of vertical lanes the danmaku are distributed across.
  static const int laneCount = 6;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return StreamBuilder<Duration>(
      stream: position,
      builder: (context, snapshot) {
        final current = snapshot.data ?? Duration.zero;
        final visible = items
            .where(
              (item) =>
                  item.time <= current &&
                  item.time >= current - scrollDuration,
            )
            .toList();
        final capped = visible.length > maxVisible
            ? visible.sublist(visible.length - maxVisible)
            : visible;
        return ClipRect(
          child: Stack(
            children: [
              for (final item in capped)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _lane(item) * 26.0,
                  child: _ScrollingDanmakuText(
                    key: ValueKey(
                      '${item.time.inMilliseconds}-${item.text}',
                    ),
                    item: item,
                    scrollDuration: scrollDuration,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Stable lane assignment per danmaku, independent of how many other
  /// danmaku are currently visible.
  static int _lane(DanmakuItem item) {
    return (item.time.inMilliseconds ~/ 1000 + item.text.hashCode).abs() %
        laneCount;
  }
}

class _ScrollingDanmakuText extends StatefulWidget {
  const _ScrollingDanmakuText({
    super.key,
    required this.item,
    required this.scrollDuration,
  });

  final DanmakuItem item;
  final Duration scrollDuration;

  @override
  State<_ScrollingDanmakuText> createState() => _ScrollingDanmakuTextState();
}

class _ScrollingDanmakuTextState extends State<_ScrollingDanmakuText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.scrollDuration,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _textWidth() {
    final painter = TextPainter(
      text: TextSpan(text: widget.item.text, style: _textStyle(widget.item)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final textWidth = _textWidth();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // From fully off-screen right to fully off-screen left.
            final dx = width + (-textWidth - width) * _controller.value;
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.item.text,
                maxLines: 1,
                style: _textStyle(widget.item),
              ),
            ),
          ),
        );
      },
    );
  }

  static TextStyle _textStyle(DanmakuItem item) {
    return TextStyle(
      color: item.color,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
    );
  }
}
