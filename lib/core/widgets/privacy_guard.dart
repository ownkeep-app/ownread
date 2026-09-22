import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Covers the whole app after idle timeout or when sent to background.
/// Long-press anywhere for [unlockHold] to dismiss the cover.
///
/// Any real user input resets the idle timer: taps, drags, scroll wheel,
/// trackpad scroll, and keyboard (including arrow keys).
class PrivacyGuard extends StatefulWidget {
  const PrivacyGuard({
    super.key,
    required this.child,
    this.idleTimeout = const Duration(minutes: 1),
    this.unlockHold = const Duration(seconds: 3),
  });

  final Widget child;
  final Duration idleTimeout;
  final Duration unlockHold;

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
    if (_locked) return;
    _idleTimer = Timer(widget.idleTimeout, _lock);
  }

  void _lock() {
    if (!mounted) return;
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

  void _onPointerDown(PointerDownEvent e) {
    if (_locked) {
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
    final theme = Theme.of(context);
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
                child: ColoredBox(
                  color: theme.scaffoldBackgroundColor,
                  child: Center(
                    child: Text(
                      '目前无内容',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.45),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
