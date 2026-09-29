import 'dart:async';

/// Immediate feedback followed by bounded updates, always retaining the latest
/// value. Slider release should call [flush] before confirming/saving a value.
class ControlThrottle<T> {
  ControlThrottle({
    required this.onValue,
    this.interval = const Duration(milliseconds: 64),
  });

  final void Function(T value) onValue;
  final Duration interval;
  Timer? _timer;
  T? _pending;
  bool _hasPending = false;
  bool _disposed = false;

  void add(T value) {
    if (_disposed) return;
    if (_timer != null) {
      _pending = value;
      _hasPending = true;
      return;
    }
    _timer = Timer(interval, _tick);
    onValue(value);
  }

  void _tick() {
    _timer = null;
    if (_disposed || !_hasPending) return;
    final value = _pending as T;
    _pending = null;
    _hasPending = false;
    _timer = Timer(interval, _tick);
    onValue(value);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || !_hasPending) return;
    final value = _pending as T;
    _pending = null;
    _hasPending = false;
    onValue(value);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    _hasPending = false;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
