import 'dart:async';

/// Keeps a user's bottom-scroll intent until loading becomes eligible again.
class RecommendAutoLoad {
  RecommendAutoLoad({
    required this.canLoad,
    required this.load,
    required this.waitingForRefill,
  });

  final bool Function() canLoad;
  final Future<void> Function() load;
  final bool Function() waitingForRefill;
  Timer? _timer;
  DateTime? _lastStarted;
  bool _armed = false;
  bool _disposed = false;

  void request() {
    _armed = true;
    recheck();
  }

  void recheck() {
    if (_disposed || !_armed || _timer != null || !canLoad()) return;
    // Preserve the existing feed's five-second cooldown and 350ms debounce,
    // but arrange a recheck at the deadline instead of dropping the gesture.
    final elapsed = _lastStarted == null
        ? const Duration(seconds: 5)
        : DateTime.now().difference(_lastStarted!);
    final remaining = const Duration(seconds: 5) - elapsed;
    _timer = Timer(
      remaining > const Duration(milliseconds: 350)
          ? remaining
          : const Duration(milliseconds: 350),
      () async {
        _timer = null;
        if (_disposed || !_armed || !canLoad()) return;
        _armed = false;
        _lastStarted = DateTime.now();
        await load();
        if (_disposed) return;
        if (waitingForRefill()) _armed = true;
        recheck();
      },
    );
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
