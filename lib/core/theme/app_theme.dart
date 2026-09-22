import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Warm orange brand accents (same in light/dark).
abstract final class OwnReadColors {
  static const orange = Color(0xFFE07A3D);
  static const orangeDeep = Color(0xFFC45E24);
  static const orangeSoft = Color(0xFFFFF4EC);
  static const ink = Color(0xFF2A211C);
  static const inkMuted = Color(0xFF6B5E56);
  static const surface = Color(0xFFFFFBF7);
  static const surfaceDark = Color(0xFF1C1917);
  static const paperDark = Color(0xFF292524);
  static const border = Color(0xFFE8D9CC);
  static const inkOnDark = Color(0xFFF5F0EB);
  static const inkMutedOnDark = Color(0xFFA8A29E);
}

ShadThemeData buildOwnReadLightTheme() {
  return ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const ShadOrangeColorScheme.light(
      primary: OwnReadColors.orange,
      primaryForeground: Colors.white,
      background: OwnReadColors.surface,
      foreground: OwnReadColors.ink,
      card: Colors.white,
      cardForeground: OwnReadColors.ink,
      muted: OwnReadColors.orangeSoft,
      mutedForeground: OwnReadColors.inkMuted,
      secondary: OwnReadColors.orangeSoft,
      secondaryForeground: OwnReadColors.ink,
      accent: OwnReadColors.orangeSoft,
      accentForeground: OwnReadColors.ink,
      border: OwnReadColors.border,
      input: OwnReadColors.border,
      ring: OwnReadColors.orange,
    ),
  );
}

ShadThemeData buildOwnReadDarkTheme() {
  return ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadOrangeColorScheme.dark(
      primary: OwnReadColors.orange,
      primaryForeground: Colors.white,
      background: OwnReadColors.surfaceDark,
      foreground: OwnReadColors.inkOnDark,
      card: OwnReadColors.paperDark,
      cardForeground: OwnReadColors.inkOnDark,
      muted: Color(0xFF3F3A36),
      mutedForeground: OwnReadColors.inkMutedOnDark,
      secondary: Color(0xFF3F3A36),
      secondaryForeground: OwnReadColors.inkOnDark,
      accent: Color(0xFF3F3A36),
      accentForeground: OwnReadColors.inkOnDark,
      border: Color(0xFF44403C),
      input: Color(0xFF44403C),
      ring: OwnReadColors.orange,
      popover: OwnReadColors.paperDark,
      popoverForeground: OwnReadColors.inkOnDark,
    ),
  );
}

/// Maps Shad tokens onto Material so ListTile / Slider / AppBar / dialogs
/// follow the same light/dark switch as [ShadApp.themeMode].
ThemeData buildOwnReadMaterialTheme(BuildContext context, ThemeData base) {
  final shad = ShadTheme.of(context);
  final cs = shad.colorScheme;
  final dark = shad.brightness == Brightness.dark;

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
      titleTextStyle: TextStyle(
        color: cs.foreground,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: cs.foreground,
      iconColor: cs.foreground,
      selectedColor: OwnReadColors.orange,
      selectedTileColor: OwnReadColors.orange.withValues(alpha: dark ? 0.18 : 0.12),
    ),
    iconTheme: IconThemeData(color: cs.foreground),
    textTheme: base.textTheme.apply(
      bodyColor: cs.foreground,
      displayColor: cs.foreground,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      bodyColor: cs.foreground,
      displayColor: cs.foreground,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: OwnReadColors.orange,
      thumbColor: OwnReadColors.orange,
      inactiveTrackColor: cs.muted,
      overlayColor: OwnReadColors.orange.withValues(alpha: 0.12),
      valueIndicatorColor: OwnReadColors.orange,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return OwnReadColors.orange.withValues(alpha: dark ? 0.28 : 0.15);
          }
          return cs.muted;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return dark ? OwnReadColors.orange : OwnReadColors.orangeDeep;
          }
          return cs.foreground;
        }),
        side: WidgetStatePropertyAll(BorderSide(color: cs.border)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cs.card,
      textStyle: TextStyle(color: cs.foreground),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.card,
      titleTextStyle: TextStyle(
        color: cs.foreground,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(color: cs.foreground),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.card,
      modalBackgroundColor: cs.card,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: OwnReadColors.orange,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: OwnReadColors.orange,
      linearTrackColor: cs.muted,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? const Color(0xFF44403C) : OwnReadColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white),
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
