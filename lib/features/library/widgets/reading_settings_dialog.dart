import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/reading_settings.dart';
import '../../../core/services/app_env.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/reading_background.dart';

/// Modal for reading appearance + library backup.
class ReadingSettingsDialog extends StatelessWidget {
  const ReadingSettingsDialog({
    super.key,
    required this.settings,
    this.onExportAll,
    this.onImportAll,
  });

  final AppSettings settings;
  final VoidCallback? onExportAll;
  final VoidCallback? onImportAll;

  static Future<void> show(
    BuildContext context,
    AppSettings settings, {
    VoidCallback? onExportAll,
    VoidCallback? onImportAll,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ReadingSettingsDialog(
        settings: settings,
        onExportAll: onExportAll,
        onImportAll: onImportAll,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final reading = settings.reading;
        final cs = ShadTheme.of(context).colorScheme;
        final label = TextStyle(
          color: cs.foreground,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        );
        final section = TextStyle(
          color: cs.mutedForeground,
          fontSize: 12,
          letterSpacing: 1,
        );
        return AlertDialog(
          title: const Text('设置'),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  inactiveTrackColor: cs.border,
                  overlayShape: SliderComponentShape.noOverlay,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CollapsibleSection(
                      title: '主题',
                      icon: LucideIcons.palette,
                      titleStyle: label,
                      summary:
                          '${reading.darkMode ? '暗色' : '淡色'} · ${reading.accent.label} · ${reading.background.label}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('风格', style: label),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _ThemeTile(
                                  label: '淡色',
                                  dark: false,
                                  background: reading.background,
                                  selected: !reading.darkMode,
                                  onTap: () => settings.setReading(
                                    reading.copyWith(darkMode: false),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ThemeTile(
                                  label: '暗色',
                                  dark: true,
                                  background: reading.background,
                                  selected: reading.darkMode,
                                  onTap: () => settings.setReading(
                                    reading.copyWith(darkMode: true),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              SizedBox(
                                width: 72,
                                child: Text('主题颜色', style: label),
                              ),
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final a in ThemeAccent.values)
                                      _AccentSwatch(
                                        accent: a,
                                        selected: reading.accent == a,
                                        onTap: () => settings.setReading(
                                          reading.copyWith(accent: a),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text('阅读背景', style: label),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final b in ReadingBackground.values)
                                _BackgroundChoice(
                                  background: b,
                                  dark: reading.darkMode,
                                  selected: reading.background == b,
                                  onTap: () => settings.setReading(
                                    reading.copyWith(background: b),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _CollapsibleSection(
                      title: '排版',
                      icon: LucideIcons.type,
                      titleStyle: label,
                      summary:
                          '${reading.font.label} · 字号 ${reading.fontSize.toStringAsFixed(0)} · 行距 ${reading.lineHeight.toStringAsFixed(1)}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),
                          _Preview(reading: reading),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 7),
                                child: SizedBox(
                                  width: 40,
                                  child: Text('字体', style: label),
                                ),
                              ),
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final f in ReadingFont.values)
                                      _FontChip(
                                        font: f,
                                        selected: reading.font == f,
                                        onTap: () => settings.setReading(
                                          reading.copyWith(font: f),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _SliderRow(
                            label: Text('字号', style: label),
                            min: ReadingSettings.minFontSize,
                            max: ReadingSettings.maxFontSize,
                            value: reading.fontSize,
                            display: reading.fontSize.toStringAsFixed(0),
                            leadingIcon: Text(
                              'A',
                              style: TextStyle(
                                color: cs.mutedForeground,
                                fontSize: 12,
                              ),
                            ),
                            trailingIcon: Text(
                              'A',
                              style: TextStyle(
                                color: cs.mutedForeground,
                                fontSize: 18,
                              ),
                            ),
                            onChanged: (v) => settings.setReading(
                              reading.copyWith(fontSize: v),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _SliderRow(
                            label: Text('行距', style: label),
                            min: ReadingSettings.minLineHeight,
                            max: ReadingSettings.maxLineHeight,
                            value: reading.lineHeight,
                            display: reading.lineHeight.toStringAsFixed(1),
                            leadingIcon: Icon(
                              LucideIcons.alignJustify,
                              size: 13,
                              color: cs.mutedForeground,
                            ),
                            trailingIcon: Icon(
                              LucideIcons.alignJustify,
                              size: 18,
                              color: cs.mutedForeground,
                            ),
                            onChanged: (v) => settings.setReading(
                              reading.copyWith(lineHeight: v),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('隐私', style: section),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('自动锁屏', style: label),
                              const SizedBox(height: 2),
                              Text(
                                '闲置 ${AppEnv.privacyIdleTimeout.inSeconds} 秒或切到后台时显示「目前无内容」，长按图案 ${AppEnv.privacyUnlockHold.inSeconds} 秒解除',
                                style: TextStyle(
                                  color: cs.mutedForeground,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: settings.autoLock,
                          onChanged: settings.setAutoLock,
                          activeThumbColor: Colors.white,
                          activeTrackColor: OwnReadAccent.of(context),
                          inactiveThumbColor: cs.mutedForeground,
                          inactiveTrackColor: cs.muted,
                          trackOutlineColor: WidgetStatePropertyAll(cs.border),
                        ),
                      ],
                    ),
                    if (onExportAll != null || onImportAll != null) ...[
                      const SizedBox(height: 24),
                      Text('书籍备份', style: section),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (onExportAll != null)
                            Expanded(
                              child: _BackupButton(
                                icon: LucideIcons.archive,
                                label: '导出所有',
                                onPressed: () {
                                  Navigator.pop(context);
                                  onExportAll!();
                                },
                              ),
                            ),
                          if (onExportAll != null && onImportAll != null)
                            const SizedBox(width: 10),
                          if (onImportAll != null)
                            Expanded(
                              child: _BackupButton(
                                icon: LucideIcons.archiveRestore,
                                label: '导入所有',
                                onPressed: () {
                                  Navigator.pop(context);
                                  onImportAll!();
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '导入所有会先清空当前书架。',
                        style: TextStyle(
                          color: cs.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            ShadButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }
}

/// Miniature reading page in light or dark, used as the theme switch.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.label,
    required this.dark,
    required this.background,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool dark;
  final ReadingBackground background;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final ink = OwnReadColors.readerText(dark);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? OwnReadAccent.of(context) : cs.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: ReadingBackgroundLayer(
            background: background,
            dark: dark,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 90,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('第一章', style: OwnReadType.heading(size: 12, color: ink)),
                  const SizedBox(height: 6),
                  for (final w in const [1.0, 0.8])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: FractionallySizedBox(
                        widthFactor: w,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      AnimatedScale(
                        scale: selected ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          LucideIcons.circleCheck,
                          size: 14,
                          color: OwnReadAccent.of(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section header that shows a one-line summary when collapsed and reveals
/// [child] on tap. Starts collapsed; the state lasts while the dialog is open.
class _CollapsibleSection extends StatefulWidget {
  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.titleStyle,
    required this.summary,
    required this.child,
  });

  final String title;
  final IconData icon;
  final TextStyle titleStyle;
  final String summary;
  final Widget child;

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection>
    with SingleTickerProviderStateMixin {
  bool _open = false;

  /// Drives the slide (height) and fade of the body; the body is only built
  /// while open or animating.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  )..addStatusListener((_) => setState(() {}));
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final dark = ShadTheme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(12);
    return Container(
      // One card: header row on top, options below when open. Neutral tint
      // so the accent-tinted slider rails stay visible.
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.04)
            : Color.lerp(cs.card, cs.foreground, 0.04),
        borderRadius: radius,
        border: Border.all(color: cs.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 16,
                      color: OwnReadAccent.of(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: widget.titleStyle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _open ? '' : widget.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 18,
                        color: cs.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open || _c.status != AnimationStatus.dismissed)
            SizeTransition(
              sizeFactor: _curve,
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: _curve,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(height: 1, color: cs.border),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                      child: widget.child,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Thumbnail of one reading background (current light/dark variant).
class _BackgroundChoice extends StatelessWidget {
  const _BackgroundChoice({
    required this.background,
    required this.dark,
    required this.selected,
    required this.onTap,
  });

  final ReadingBackground background;
  final bool dark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final accent = OwnReadAccent.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 40,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? accent : cs.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ReadingBackgroundLayer(
                background: background,
                dark: dark,
                borderRadius: BorderRadius.circular(7),
                tileScale: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              background.label,
              style: TextStyle(
                fontSize: 11,
                color: selected
                    ? OwnReadAccent.text(context)
                    : cs.mutedForeground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round colour swatch for 「主题颜色」.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final ThemeAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Tooltip(
      message: accent.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? accent.color : cs.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.color,
                shape: BoxShape.circle,
              ),
              child: selected
                  ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// One selectable typeface, labelled in its own font.
class _FontChip extends StatelessWidget {
  const _FontChip({
    required this.font,
    required this.selected,
    required this.onTap,
  });

  final ReadingFont font;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final dark = ShadTheme.of(context).brightness == Brightness.dark;
    final accent = OwnReadAccent.text(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? OwnReadAccent.of(
                    context,
                  ).withValues(alpha: dark ? 0.18 : 0.10)
                : cs.background,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? OwnReadAccent.of(context) : cs.border,
            ),
          ),
          child: Text(
            font.label,
            style: OwnReadType.reading(
              font,
              size: 14,
              color: selected ? accent : cs.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// Live sample of the reading typography.
class _Preview extends StatelessWidget {
  const _Preview({required this.reading});

  final ReadingSettings reading;

  @override
  Widget build(BuildContext context) {
    final dark = reading.darkMode;
    final cs = ShadTheme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.border),
      ),
      child: ReadingBackgroundLayer(
        background: reading.background,
        dark: dark,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            '　　春风又绿江南岸，明月何时照我还。窗外细雨如丝，他合上书页，静静听着檐下的雨声。',
            maxLines: 3,
            overflow: TextOverflow.fade,
            style: OwnReadType.reading(
              reading.font,
              size: reading.fontSize.clamp(14, 22),
              height: reading.lineHeight,
              letterSpacing: 0.4,
              color: OwnReadColors.readerText(dark),
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.display,
    required this.leadingIcon,
    required this.trailingIcon,
    required this.onChanged,
  });

  final Widget label;
  final double min;
  final double max;
  final double value;
  final String display;
  final Widget leadingIcon;
  final Widget trailingIcon;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(width: 40, child: label),
        SizedBox(width: 18, child: Center(child: leadingIcon)),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(min: min, max: max, value: value, onChanged: onChanged),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 22, child: Center(child: trailingIcon)),
        const SizedBox(width: 8),
        Container(
          width: 40,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: cs.muted,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            display,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _BackupButton extends StatelessWidget {
  const _BackupButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = OwnReadAccent.text(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: fg,
        side: BorderSide(
          color: OwnReadAccent.of(context).withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
