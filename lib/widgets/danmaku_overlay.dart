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
/// It watches the player position stream and renders only the comments that
/// should be visible in the current time window. Each visible comment animates
/// from the right edge of the video to the left.
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
                  item.time >= current &&
                  item.time <= current + const Duration(seconds: 7),
            )
            .take(20)
            .toList();
        return ClipRect(
          child: Stack(
            children: [
              for (var i = 0; i < visible.length; i++)
                Positioned(
                  left: 0,
                  right: 0,
                  top: (i % 6) * 26.0,
                  child: _ScrollingDanmakuText(
                    key: ValueKey(
                      '${visible[i].time.inMilliseconds}-${visible[i].text}-$i',
                    ),
                    item: visible[i],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScrollingDanmakuText extends StatefulWidget {
  const _ScrollingDanmakuText({super.key, required this.item});

  final DanmakuItem item;

  @override
  State<_ScrollingDanmakuText> createState() => _ScrollingDanmakuTextState();
}

class _ScrollingDanmakuTextState extends State<_ScrollingDanmakuText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final dx = width * (1 - progress);
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
            style: TextStyle(
              color: widget.item.color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
            ),
          ),
        ),
      ),
    );
  }
}
