import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Leaky integration keeps angular velocity from accumulating into drift.
class LyricTilt {
  Offset value = Offset.zero;
  void reset() => value = Offset.zero;

  Offset update(double x, double y, double seconds) {
    if (!x.isFinite || !y.isFinite || !seconds.isFinite) return value;
    final dt = seconds.clamp(0.0, .05);
    final decay = math.exp(-dt * 2.8);
    value = Offset(
      (value.dx * decay + y.clamp(-4.0, 4.0) * dt * .45).clamp(-1.0, 1.0),
      (value.dy * decay + x.clamp(-4.0, 4.0) * dt * .45).clamp(-1.0, 1.0),
    );
    return value;
  }
}

class LyricGyroscope extends ValueNotifier<Offset> {
  LyricGyroscope() : super(Offset.zero);
  static const channel = EventChannel('app.sonorynth.player/lyric_gyroscope');
  final tilt = LyricTilt();
  StreamSubscription<dynamic>? _subscription;
  double? _lastTimestamp;

  void setEnabled(bool enabled) {
    if (!enabled) {
      final subscription = _subscription;
      _subscription = null;
      unawaited(subscription?.cancel());
      _lastTimestamp = null;
      tilt.reset();
      value = Offset.zero;
      return;
    }
    if (_subscription != null ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _subscription = channel.receiveBroadcastStream().listen(
      (event) {
        if (event is! List || event.length != 3) return;
        final timestamp = (event[2] as num).toDouble();
        final previous = _lastTimestamp;
        _lastTimestamp = timestamp;
        if (previous == null || timestamp <= previous) return;
        value = tilt.update(
          (event[0] as num).toDouble(),
          (event[1] as num).toDouble(),
          timestamp - previous,
        );
      },
      onError: (Object _) {
        // A missing sensor/platform channel leaves the stage centered.
        tilt.reset();
        value = Offset.zero;
      },
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
