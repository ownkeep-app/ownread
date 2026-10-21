import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Small, calm motion primitives (Flutter takes on React Bits' FadeContent,
/// BlurText and SpotlightCard). Delays live inside the curve, not in timers,
/// so nothing is left pending when a widget is disposed mid-animation.

/// Limits [FadeSlideIn] below it to the items present on the scope's first
/// frame. Rows a list builds later (scrolled into view, or rebuilt after being
/// recycled) appear immediately instead of replaying the entrance.
class EntranceScope extends StatefulWidget {
  const EntranceScope({super.key, required this.child});

  final Widget child;

  /// False once the nearest scope has finished its first frame.
  static bool allowsEntrance(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_EntranceGate>()?.open ?? true;

  @override
  State<EntranceScope> createState() => _EntranceScopeState();
}

class _EntranceScopeState extends State<EntranceScope> {
  bool _open = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _EntranceGate(open: _open, child: widget.child);
}

class _EntranceGate extends InheritedWidget {
  const _EntranceGate({required this.open, required super.child});

  final bool open;

  // Read once in initState: mounted items keep animating, new ones don't.
  @override
  bool updateShouldNotify(_EntranceGate oldWidget) => false;
}

/// Fades and lifts [child] into place once, after [delay].
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = 14,
    this.blur = 0,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Vertical travel in logical pixels.
  final double offset;

  /// Starting blur sigma; 0 disables the blur pass.
  final double blur;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + widget.duration;
    _c = AnimationController(vsync: this, duration: total);
    if (!EntranceScope.allowsEntrance(context)) {
      _c.value = 1;
      _t = const AlwaysStoppedAnimation(1);
      return;
    }
    final start = total.inMicroseconds == 0
        ? 0.0
        : widget.delay.inMicroseconds / total.inMicroseconds;
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        Widget out = Transform.translate(
          offset: Offset(0, (1 - v) * widget.offset),
          child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
        );
        final sigma = (1 - v) * widget.blur;
        if (sigma > 0.05) {
          out = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: out,
          );
        }
        return out;
      },
    );
  }
}

/// Reveals [text] one character at a time with a soft blur (BlurText).
class BlurText extends StatefulWidget {
  const BlurText(
    this.text, {
    super.key,
    this.style,
    this.stagger = const Duration(milliseconds: 70),
    this.duration = const Duration(milliseconds: 520),
  });

  final String text;
  final TextStyle? style;
  final Duration stagger;
  final Duration duration;

  @override
  State<BlurText> createState() => _BlurTextState();
}

class _BlurTextState extends State<BlurText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  List<String> get _chars => widget.text.characters.toList();

  Duration get _total =>
      widget.stagger * (_chars.length - 1).clamp(0, 999) + widget.duration;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total)..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chars = _chars;
    final total = _total.inMicroseconds.toDouble();
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < chars.length; i++) _char(chars[i], i, total),
            ],
          ),
        ),
      ),
    );
  }

  Widget _char(String ch, int i, double total) {
    final start = (widget.stagger * i).inMicroseconds / total;
    final end = start + widget.duration.inMicroseconds / total;
    final v = Interval(
      start,
      end.clamp(0.0, 1.0),
      curve: Curves.easeOutCubic,
    ).transform(_c.value);
    final sigma = (1 - v) * 6;
    Widget out = Transform.translate(
      offset: Offset(0, (1 - v) * -8),
      child: Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Text(ch, style: widget.style),
      ),
    );
    if (sigma > 0.05) {
      out = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: out,
      );
    }
    return out;
  }
}

/// Card surface with a soft radial highlight that follows the pointer and a
/// slight lift on hover (SpotlightCard). Touch devices just get the surface.
class SpotlightSurface extends StatefulWidget {
  const SpotlightSurface({
    super.key,
    required this.child,
    required this.color,
    required this.borderColor,
    required this.hoverBorderColor,
    required this.spotlightColor,
    this.radius = 16,
    this.onTap,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final Color hoverBorderColor;
  final Color spotlightColor;
  final double radius;
  final VoidCallback? onTap;

  @override
  State<SpotlightSurface> createState() => _SpotlightSurfaceState();
}

class _SpotlightSurfaceState extends State<SpotlightSurface> {
  /// Pointer position as an [Alignment] inside the card.
  Alignment? _pointer;
  bool _hover = false;

  void _track(Offset local) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    setState(
      () => _pointer = Alignment(
        (local.dx / size.width) * 2 - 1,
        (local.dy / size.height) * 2 - 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pointer = null;
      }),
      onHover: (e) => _track(e.localPosition),
      child: AnimatedSlide(
        offset: Offset(0, _hover ? -0.012 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: radius,
            border: Border.all(
              color: _hover ? widget.hoverBorderColor : widget.borderColor,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hover ? 0.07 : 0.03),
                blurRadius: _hover ? 22 : 10,
                offset: Offset(0, _hover ? 8 : 3),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: radius,
              hoverColor: Colors.transparent,
              child: Stack(
                children: [
                  if (_pointer != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ClipRRect(
                          borderRadius: radius,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: _pointer!,
                                radius: 1.1,
                                colors: [
                                  widget.spotlightColor,
                                  widget.spotlightColor.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  widget.child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
