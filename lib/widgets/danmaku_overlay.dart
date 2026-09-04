import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
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

/// Bilibili-style danmaku overlay backed by the same `canvas_danmaku` engine
/// the PiliPlus (biliplus) reference client uses.
///
/// Lifecycle mirrors the reference implementation:
/// - A comment is added exactly when playback crosses its timestamp (100 ms
///   buckets). Comments whose timestamp already passed when the list arrives
///   (late fetch) are skipped, never back-filled in a burst.
/// - Scrolling, track collision and removal are engine-driven: an item is
///   removed only after it has fully scrolled past the left edge, so it can
///   never vanish mid-screen.
/// - The engine pauses/resumes with the [playing] stream, so danmaku freeze
///   together with the video.
class DanmakuOverlay extends StatelessWidget {
  const DanmakuOverlay({
    super.key,
    required this.position,
    required this.items,
    this.playing,
    this.enabled = true,
    this.onControllerCreated,
  });

  final Stream<Duration> position;

  /// Whether playback is currently running. When false the engine pauses and
  /// position updates no longer spawn danmaku.
  final Stream<bool>? playing;

  final List<DanmakuItem> items;
  final bool enabled;

  /// Optional hook for tests/diagnostics to inspect the engine controller.
  final ValueChanged<DanmakuController<Object?>>? onControllerCreated;

  /// Engine options. Fixed-duration scroll mode (the engine default) so the
  /// whole text always crosses in the same time.
  static const DanmakuOption engineOption = DanmakuOption();

  /// Last engine controller created by an overlay instance. Test-only seam:
  /// the E2E test observes engine state through the public controller API
  /// instead of reaching into private widget state (Dart 3 forbids cross-
  /// library dynamic access to private members).
  @visibleForTesting
  static DanmakuController<Object?>? debugLastController;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    return _DanmakuEngine(
      position: position,
      playing: playing,
      items: items,
      onControllerCreated: onControllerCreated,
    );
  }
}

class _DanmakuEngine extends StatefulWidget {
  const _DanmakuEngine({
    required this.position,
    required this.items,
    this.playing,
    this.onControllerCreated,
  });

  final Stream<Duration> position;
  final Stream<bool>? playing;
  final List<DanmakuItem> items;
  final ValueChanged<DanmakuController<Object?>>? onControllerCreated;

  @override
  State<_DanmakuEngine> createState() => _DanmakuEngineState();
}

class _DanmakuEngineState extends State<_DanmakuEngine> {
  DanmakuController<Object?>? _controller;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  bool _playing = true;

  /// Danmaku indexed by the 100 ms playback bucket they belong to, mirroring
  /// PiliPlus's `_dmSegMap[progress ~/ 100]` lookup. Order-independent, so the
  /// list does not need to be sorted.
  Map<int, List<DanmakuItem>> _buckets = const {};

  /// Last bucket that has been added, so a bucket is spawned at most once.
  int _lastBucket = -1;

  @override
  void initState() {
    super.initState();
    _rebuildBuckets();
    _positionSub = widget.position.listen(_onPosition);
    _playingSub = widget.playing?.listen(_onPlayingChanged);
  }

  @override
  void didUpdateWidget(_DanmakuEngine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.items, oldWidget.items)) {
      _rebuildBuckets();
    }
    if (widget.position != oldWidget.position) {
      _positionSub?.cancel();
      _positionSub = widget.position.listen(_onPosition);
    }
    if (widget.playing != oldWidget.playing) {
      _playingSub?.cancel();
      _playingSub = widget.playing?.listen(_onPlayingChanged);
    }
  }

  void _rebuildBuckets() {
    final buckets = <int, List<DanmakuItem>>{};
    for (final item in widget.items) {
      final bucket = item.time.inMilliseconds ~/ 100;
      buckets.putIfAbsent(bucket, () => []).add(item);
    }
    _buckets = buckets;
  }

  void _onPlayingChanged(bool playing) {
    _playing = playing;
    final controller = _controller;
    if (controller == null) return;
    if (playing) {
      controller.resume();
    } else {
      controller.pause();
    }
  }

  void _onPosition(Duration position) {
    // Track the bucket even while the danmaku list is still empty: the
    // position cursor is about playback, not about the list, so a list that
    // arrives later keeps the cursor where playback already is.
    if (_controller == null) return;
    if (!_playing) return;
    final bucket = position.inMilliseconds ~/ 100;
    if (_lastBucket == -1) {
      // First position event: spawn this bucket only, never back-fill the
      // history that played before the overlay started listening (late list
      // load, fullscreen entry mid-video).
      _lastBucket = bucket;
      _addBucket(bucket);
      return;
    }
    if (bucket == _lastBucket) return;
    if (bucket > _lastBucket) {
      // Catch up buckets the position stream skipped between updates
      // (stream jitter or a brief stall), but not a large forward jump:
      // that's a seek, where only new danmaku from the landing point should
      // appear.
      if (bucket - _lastBucket <= 50) {
        // 50 buckets = 5 s
        for (var b = _lastBucket + 1; b <= bucket; b++) {
          _addBucket(b);
        }
      } else {
        _addBucket(bucket);
      }
    } else {
      // Seek backwards: re-show from the landing bucket, like bilibili.
      _addBucket(bucket);
    }
    _lastBucket = bucket;
  }

  void _addBucket(int bucket) {
    final list = _buckets[bucket];
    if (list == null) return;
    final controller = _controller;
    if (controller == null) return;
    for (final item in list) {
      controller.addDanmaku(
        DanmakuContentItem<Object?>(item.text, color: item.color),
      );
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _playingSub?.cancel();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.hasBoundedWidth &&
                constraints.hasBoundedHeight
            ? constraints.biggest
            : Size.zero;
        return DanmakuScreen<Object?>(
          createdController: (controller) {
            _controller = controller;
            DanmakuOverlay.debugLastController = controller;
            widget.onControllerCreated?.call(controller);
            if (!_playing) controller.pause();
          },
          option: DanmakuOverlay.engineOption,
          size: size,
        );
      },
    );
  }
}
