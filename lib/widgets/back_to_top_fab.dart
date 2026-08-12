import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Floating "back to top" button for a scroll view, aligned with the web
/// clients' behaviour: it appears once the view scrolls past [threshold]
/// pixels and animates the attached controller back to the top on tap.
class BackToTopFab extends StatefulWidget {
  const BackToTopFab({
    super.key,
    required this.controller,
    this.threshold = 240,
  });

  final ScrollController controller;
  final double threshold;

  @override
  State<BackToTopFab> createState() => _BackToTopFabState();
}

class _BackToTopFabState extends State<BackToTopFab> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(BackToTopFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    final visible =
        widget.controller.hasClients &&
        widget.controller.offset > widget.threshold;
    if (visible != _visible) {
      setState(() => _visible = visible);
    }
  }

  void _scrollToTop(BuildContext context) {
    if (!widget.controller.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      widget.controller.jumpTo(0);
      return;
    }
    widget.controller.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      child: IgnorePointer(
        ignoring: !_visible,
        child: FloatingActionButton.small(
          heroTag: null,
          tooltip: '回到顶部',
          backgroundColor: context.appColors.surface.withValues(alpha: 0.96),
          foregroundColor: Theme.of(context).colorScheme.primary,
          elevation: 3,
          onPressed: () => _scrollToTop(context),
          child: const Icon(Icons.arrow_upward_rounded, size: 20),
        ),
      ),
    );
  }
}
