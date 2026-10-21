import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../models/reading_settings.dart';

/// Warm orange brand accents (same in light/dark).
abstract final class OwnReadColors {
  static const orange = Color(0xFFE07A3D);
  static const orangeDeep = Color(0xFFC45E24);
  static const orangeSoft = Color(0xFFFCEFE4);
  static const ink = Color(0xFF2A231E);
  static const inkMuted = Color(0xFF7A6D63);
  static const surface = Color(0xFFFAF6F1);
  static const surfaceDark = Color(0xFF171513);
  static const paperDark = Color(0xFF221F1C);
  static const border = Color(0xFFEDE3D8);
  static const inkOnDark = Color(0xFFF2ECE6);
  static const inkMutedOnDark = Color(0xFF9C948D);

  /// Reading page: warm paper with a softened ink, tuned for long CJK text.
  static const readerPaper = Color(0xFFF7F1E7);
  static const readerInk = Color(0xFF332C26);
  static const readerPaperDark = Color(0xFF1A1816);
  static const readerInkDark = Color(0xFFD8D0C7);

  static Color readerBackground(bool dark) =>
      dark ? readerPaperDark : readerPaper;
  static Color readerText(bool dark) => dark ? readerInkDark : readerInk;
}

/// The theme colour chosen in settings (「主题颜色」), read from the theme so
/// it follows the setting live.
abstract final class OwnReadAccent {
  static Color of(BuildContext context) =>
      ShadTheme.of(context).colorScheme.primary;

  /// Accent for text and small icons: a darker shade on light backgrounds
  /// for contrast, the plain colour in dark mode.
  static Color text(BuildContext context) {
    final theme = ShadTheme.of(context);
    final c = theme.colorScheme.primary;
    return theme.brightness == Brightness.dark ? c : deep(c);
  }

  static Color deep(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }

  /// Very light tint used for muted surfaces in light mode.
  static Color soft(Color c) => Color.lerp(Colors.white, c, 0.09)!;
}

/// Text styles. Everything uses the font chosen in settings: the themes set it
/// as the app default, so [heading] inherits it; [reading] names it
/// explicitly for previews of a font other than the current one.
abstract final class OwnReadType {
  /// Text in [font] (reader body, editor, font picker samples).
  static TextStyle reading(
    ReadingFont font, {
    double? size,
    FontWeight? weight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: font.family,
      fontFamilyFallback: ReadingSettings.fontFamilyFallbacks,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle heading({
    double size = 20,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? height,
    double letterSpacing = 0.5,
  }) {
    return TextStyle(
      fontFamilyFallback: ReadingSettings.fontFamilyFallbacks,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}

ShadThemeData buildOwnReadLightTheme([
  ReadingFont font = ReadingSettings.defaultFont,
  ThemeAccent accent = ReadingSettings.defaultAccent,
]) {
  final soft = OwnReadAccent.soft(accent.color);
  return ShadThemeData(
    brightness: Brightness.light,
    textTheme: ShadTextTheme(family: font.family),
    colorScheme: ShadOrangeColorScheme.light(
      primary: accent.color,
      primaryForeground: Colors.white,
      background: OwnReadColors.surface,
      foreground: OwnReadColors.ink,
      card: Colors.white,
      cardForeground: OwnReadColors.ink,
      muted: soft,
      mutedForeground: OwnReadColors.inkMuted,
      secondary: soft,
      secondaryForeground: OwnReadColors.ink,
      accent: soft,
      accentForeground: OwnReadColors.ink,
      border: OwnReadColors.border,
      input: OwnReadColors.border,
      ring: accent.color,
    ),
    radius: const BorderRadius.all(Radius.circular(10)),
  );
}

ShadThemeData buildOwnReadDarkTheme([
  ReadingFont font = ReadingSettings.defaultFont,
  ThemeAccent accent = ReadingSettings.defaultAccent,
]) {
  return ShadThemeData(
    brightness: Brightness.dark,
    textTheme: ShadTextTheme(family: font.family),
    colorScheme: ShadOrangeColorScheme.dark(
      primary: accent.color,
      primaryForeground: Colors.white,
      background: OwnReadColors.surfaceDark,
      foreground: OwnReadColors.inkOnDark,
      card: OwnReadColors.paperDark,
      cardForeground: OwnReadColors.inkOnDark,
      muted: Color(0xFF302C28),
      mutedForeground: OwnReadColors.inkMutedOnDark,
      secondary: Color(0xFF302C28),
      secondaryForeground: OwnReadColors.inkOnDark,
      accent: Color(0xFF302C28),
      accentForeground: OwnReadColors.inkOnDark,
      border: Color(0xFF35302C),
      input: Color(0xFF3B3631),
      ring: accent.color,
      popover: OwnReadColors.paperDark,
      popoverForeground: OwnReadColors.inkOnDark,
    ),
    radius: const BorderRadius.all(Radius.circular(10)),
  );
}

/// Maps Shad tokens onto Material so ListTile / Slider / AppBar / dialogs
/// follow the same light/dark switch as [ShadApp.themeMode].
ThemeData buildOwnReadMaterialTheme(BuildContext context, ThemeData base) {
  final shad = ShadTheme.of(context);
  final cs = shad.colorScheme;
  final dark = shad.brightness == Brightness.dark;
  final accent = cs.primary;
  final accentDeep = OwnReadAccent.deep(accent);
  // The chosen reading font (set on the Shad text theme) is the app font.
  final family = shad.textTheme.family;
  TextStyle f(TextStyle s) => s.copyWith(
        fontFamily: family,
        fontFamilyFallback: ReadingSettings.fontFamilyFallbacks,
      );
  const fallback = ReadingSettings.fontFamilyFallbacks;

  return base.copyWith(
    brightness: shad.brightness,
    scaffoldBackgroundColor: cs.background,
    canvasColor: cs.background,
    cardColor: cs.card,
    dividerColor: cs.border,
    colorScheme: base.colorScheme.copyWith(
      brightness: shad.brightness,
      primary: cs.primary,
      onPrimary: cs.primaryForeground,
      secondary: cs.secondary,
      onSecondary: cs.secondaryForeground,
      surface: cs.card,
      onSurface: cs.foreground,
      surfaceContainerHighest: cs.muted,
      onSurfaceVariant: cs.mutedForeground,
      outline: cs.border,
      error: cs.destructive,
      onError: cs.destructiveForeground,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cs.card,
      foregroundColor: cs.foreground,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: cs.foreground),
      titleTextStyle: f(TextStyle(
        color: cs.foreground,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      )),
    ),
    listTileTheme: ListTileThemeData(
      textColor: cs.foreground,
      iconColor: cs.foreground,
      selectedColor: accent,
      selectedTileColor: accent.withValues(alpha: dark ? 0.18 : 0.12),
    ),
    iconTheme: IconThemeData(color: cs.foreground),
    textTheme: base.textTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
      bodyColor: cs.foreground,
      displayColor: cs.foreground,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: family,
      fontFamilyFallback: fallback,
      bodyColor: cs.foreground,
      displayColor: cs.foreground,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: accent,
      thumbColor: accent,
      inactiveTrackColor: cs.muted,
      overlayColor: accent.withValues(alpha: 0.12),
      valueIndicatorColor: accent,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return accent.withValues(alpha: dark ? 0.28 : 0.15);
          }
          return cs.muted;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return dark ? accent : accentDeep;
          }
          return cs.foreground;
        }),
        side: WidgetStatePropertyAll(BorderSide(color: cs.border)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cs.card,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.border),
      ),
      textStyle: f(TextStyle(color: cs.foreground, fontSize: 14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.border),
      ),
      titleTextStyle: f(OwnReadType.heading(size: 19, color: cs.foreground)),
      contentTextStyle: f(
        TextStyle(color: cs.foreground, fontSize: 14, height: 1.6),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? accent : accentDeep,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3B3631) : OwnReadColors.ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: f(const TextStyle(color: Colors.white, fontSize: 12)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.card,
      modalBackgroundColor: cs.card,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: cs.muted,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF3B3631) : OwnReadColors.ink,
      contentTextStyle: f(const TextStyle(color: Colors.white, fontSize: 14)),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// @deprecated Use [buildOwnReadMaterialTheme] via ShadApp.materialThemeBuilder.
ThemeData materialFromReading({required bool dark}) {
  final base = dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: OwnReadColors.orange,
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    scaffoldBackgroundColor:
        dark ? OwnReadColors.surfaceDark : OwnReadColors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? OwnReadColors.paperDark : OwnReadColors.surface,
      foregroundColor: dark ? Colors.white : OwnReadColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
  );
}
