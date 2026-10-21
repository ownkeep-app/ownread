import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Covers the whole app after idle timeout or when sent to background.
/// Long-press the cover's empty-box drawing for [unlockHold] to dismiss it;
/// holding anywhere else does nothing.
///
/// Any real user input resets the idle timer: taps, drags, scroll wheel,
/// trackpad scroll, and keyboard (including arrow keys).
class PrivacyGuard extends StatefulWidget {
  const PrivacyGuard({
    super.key,
    required this.child,
    this.idleTimeout = const Duration(minutes: 1),
    this.unlockHold = const Duration(seconds: 3),
    this.enabled = true,
  });

  final Widget child;
  final Duration idleTimeout;
  final Duration unlockHold;

  /// Settings switch 「自动锁屏」; when false the cover never appears.
  final bool enabled;

  @override
  State<PrivacyGuard> createState() => _PrivacyGuardState();
}

class _PrivacyGuardState extends State<PrivacyGuard>
    with WidgetsBindingObserver {
  bool _locked = false;
  Timer? _idleTimer;
  Timer? _holdTimer;
  Offset? _holdStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _armIdleTimer();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PrivacyGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled == widget.enabled) return;
    if (widget.enabled) {
      _armIdleTimer();
    } else {
      _idleTimer?.cancel();
      _holdTimer?.cancel();
      _holdStart = null;
      _locked = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cover as soon as the app leaves the foreground.
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _lock();
      case AppLifecycleState.resumed:
        break;
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    // Arrow keys, typing, shortcuts — all count as online activity.
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _onActivity();
    }
    return false;
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (_locked || !widget.enabled) return;
    _idleTimer = Timer(widget.idleTimeout, _lock);
  }

  void _lock() {
    if (!mounted || !widget.enabled) return;
    _idleTimer?.cancel();
    _holdTimer?.cancel();
    _holdStart = null;
    if (_locked) return;
    setState(() => _locked = true);
  }

  void _unlock() {
    if (!mounted || !_locked) return;
    _holdTimer?.cancel();
    _holdStart = null;
    setState(() => _locked = false);
    _armIdleTimer();
  }

  void _onActivity() {
    if (_locked) return;
    _armIdleTimer();
  }

  /// The empty-box drawing on the cover; only a hold on it unlocks.
  final _unlockTargetKey = GlobalKey();

  /// Whether [global] falls on the cover's drawing (its on-screen rect,
  /// including the cover's scale).
  bool _onUnlockTarget(Offset global) {
    final box = _unlockTargetKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    );
    return rect.contains(global);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_locked) {
      _holdTimer?.cancel();
      _holdTimer = null;
      _holdStart = null;
      // Holding anywhere else on the cover does nothing.
      if (!_onUnlockTarget(e.position)) return;
      _holdStart = e.position;
      _holdTimer?.cancel();
      _holdTimer = Timer(widget.unlockHold, _unlock);
      return;
    }
    _onActivity();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_locked) {
      // Cancel hold if finger drifts too far (not a deliberate long-press).
      final start = _holdStart;
      if (start != null && (e.position - start).distance > 24) {
        _holdTimer?.cancel();
        _holdTimer = null;
        _holdStart = null;
      }
      return;
    }
    _onActivity();
  }

  void _onPointerUp(PointerUpEvent e) {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStart = null;
    if (!_locked) _onActivity();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStart = null;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    // Mouse wheel / trackpad scroll (ListView may claim the signal itself;
    // ScrollNotification below covers that path too).
    if (e is PointerScrollEvent || e is PointerPanZoomUpdateEvent) {
      _onActivity();
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    // User-driven scroll (finger, wheel, scrollbar) — not programmatic jumps.
    if (n is UserScrollNotification ||
        n is ScrollUpdateNotification && n.dragDetails != null) {
      _onActivity();
    } else if (n is ScrollUpdateNotification && n.scrollDelta != null) {
      // Wheel / trackpad often arrives without dragDetails.
      _onActivity();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        onPointerSignal: _onPointerSignal,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_locked)
              Positioned.fill(
                child: _EmptyCover(unlockTargetKey: _unlockTargetKey),
              ),
          ],
        ),
      ),
    );
  }
}

/// The cover itself: an ordinary-looking empty page (no hint that it is a
/// lock), with a quiet line-art illustration instead of bare text.
class _EmptyCover extends StatelessWidget {
  const _EmptyCover({required this.unlockTargetKey});

  final GlobalKey unlockTargetKey;

  static const _scale = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        // Everything is vector (paths + text), so scaling stays crisp.
        child: Transform.scale(
          scale: _scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: unlockTargetKey,
                width: 132,
                height: 108,
                child: CustomPaint(painter: _EmptyTrayPainter(fg)),
              ),
              const SizedBox(height: 20),
              Text(
                '目前无内容',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: fg.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '这里暂时空空如也',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg.withValues(alpha: 0.35),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty open tray with a soft shadow ellipse and a couple of sparkles.
class _EmptyTrayPainter extends CustomPainter {
  const _EmptyTrayPainter(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()
      ..color = ink.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = ink.withValues(alpha: 0.05);

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.9),
        width: w * 0.8,
        height: h * 0.1,
      ),
      Paint()..color = ink.withValues(alpha: 0.06),
    );

    // Tray body: back rim, slanted sides, front with a dip.
    final top = h * 0.38, bottom = h * 0.78;
    final left = w * 0.16, right = w * 0.84;
    final body = Path()
      ..moveTo(left, top + h * 0.12)
      ..lineTo(left + w * 0.1, top - h * 0.02)
      ..lineTo(right - w * 0.1, top - h * 0.02)
      ..lineTo(right, top + h * 0.12)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..close();
    canvas.drawPath(body, fill);
    canvas.drawPath(body, line);

    final front = Path()
      ..moveTo(left, top + h * 0.12)
      ..lineTo(w * 0.36, top + h * 0.12)
      ..quadraticBezierTo(w * 0.38, top + h * 0.24, w * 0.5, top + h * 0.24)
      ..quadraticBezierTo(w * 0.62, top + h * 0.24, w * 0.64, top + h * 0.12)
      ..lineTo(right, top + h * 0.12);
    canvas.drawPath(front, line);

    // Sparkles above the tray.
    void sparkle(Offset c, double r) {
      final p = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx + r * 0.18, c.dy - r * 0.18, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx + r * 0.18, c.dy + r * 0.18, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx - r * 0.18, c.dy + r * 0.18, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx - r * 0.18, c.dy - r * 0.18, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(p, Paint()..color = ink.withValues(alpha: 0.22));
    }

    sparkle(Offset(w * 0.3, h * 0.14), 7);
    sparkle(Offset(w * 0.72, h * 0.08), 5);
    canvas.drawCircle(
      Offset(w * 0.52, h * 0.16),
      2.2,
      Paint()..color = ink.withValues(alpha: 0.2),
    );
  }

  @override
  bool shouldRepaint(_EmptyTrayPainter old) => old.ink != ink;
}
