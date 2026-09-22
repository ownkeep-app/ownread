/// Global reading appearance settings (persisted in SharedPreferences).
class ReadingSettings {
  const ReadingSettings({
    this.darkMode = false,
    this.fontSize = 18,
    this.lineHeight = 1.7,
  });

  final bool darkMode;

  /// Font size in logical pixels. Microsoft YaHei with platform fallbacks.
  final double fontSize;

  final double lineHeight;

  static const minFontSize = 14.0;
  static const maxFontSize = 32.0;
  static const minLineHeight = 1.2;
  static const maxLineHeight = 2.4;

  /// Preferred Chinese reading font; falls back on platforms without YaHei.
  static const fontFamily = 'Microsoft YaHei';
  static const fontFamilyFallbacks = <String>[
    'PingFang SC',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'sans-serif',
  ];

  ReadingSettings copyWith({
    bool? darkMode,
    double? fontSize,
    double? lineHeight,
  }) {
    return ReadingSettings(
      darkMode: darkMode ?? this.darkMode,
      fontSize: (fontSize ?? this.fontSize).clamp(minFontSize, maxFontSize),
      lineHeight:
          (lineHeight ?? this.lineHeight).clamp(minLineHeight, maxLineHeight),
    );
  }

  Map<String, dynamic> toJson() => {
        'darkMode': darkMode,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
      };

  factory ReadingSettings.fromJson(Map<String, dynamic> json) {
    return ReadingSettings(
      darkMode: json['darkMode'] as bool? ?? false,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.7,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadingSettings &&
          darkMode == other.darkMode &&
          fontSize == other.fontSize &&
          lineHeight == other.lineHeight;

  @override
  int get hashCode => Object.hash(darkMode, fontSize, lineHeight);
}
