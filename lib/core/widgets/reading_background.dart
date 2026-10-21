import 'package:flutter/widgets.dart';

import '../models/reading_settings.dart';

/// Fills its area with the reading background: the tiled image for
/// [background] in light or dark, over the tile's base colour.
class ReadingBackgroundLayer extends StatelessWidget {
  const ReadingBackgroundLayer({
    super.key,
    required this.background,
    required this.dark,
    this.borderRadius,
    this.tileScale = 2,
    this.child,
  });

  final ReadingBackground background;
  final bool dark;
  final BorderRadius? borderRadius;

  /// Image pixels per logical pixel; larger shows more pattern (thumbnails).
  final double tileScale;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final asset = background.asset(dark);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background.base(dark),
        borderRadius: borderRadius,
        image: asset == null
            ? null
            : DecorationImage(
                image: AssetImage(asset),
                repeat: ImageRepeat.repeat,
                alignment: Alignment.topLeft,
                // Default 2: 1024 px tiles shown at 512 logical px, sharp on
                // Retina.
                scale: tileScale,
              ),
      ),
      child: child,
    );
  }
}
