import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/reading_settings.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/theme/app_theme.dart';

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
        return AlertDialog(
          title: const Text('设置'),
          content: SizedBox(
            width: 320,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '风格',
                        style: TextStyle(color: cs.foreground, fontSize: 14),
                      ),
                      const Spacer(),
                      SegmentedButton<bool>(
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          ),
                          textStyle: const WidgetStatePropertyAll(
                            TextStyle(fontSize: 12),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(value: false, label: Text('淡色')),
                          ButtonSegment(value: true, label: Text('暗色')),
                        ],
                        selected: {reading.darkMode},
                        onSelectionChanged: (s) {
                          settings.setReading(
                            reading.copyWith(darkMode: s.first),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        '字号',
                        style: TextStyle(color: cs.foreground, fontSize: 14),
                      ),
                      Expanded(
                        child: Slider(
                          min: ReadingSettings.minFontSize,
                          max: ReadingSettings.maxFontSize,
                          value: reading.fontSize,
                          onChanged: (v) {
                            settings.setReading(
                              reading.copyWith(fontSize: v),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text(
                          reading.fontSize.toStringAsFixed(0),
                          textAlign: TextAlign.end,
                          style: TextStyle(color: cs.foreground, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '行距',
                        style: TextStyle(color: cs.foreground, fontSize: 14),
                      ),
                      Expanded(
                        child: Slider(
                          min: ReadingSettings.minLineHeight,
                          max: ReadingSettings.maxLineHeight,
                          value: reading.lineHeight,
                          onChanged: (v) {
                            settings.setReading(
                              reading.copyWith(lineHeight: v),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: 28,
                        child: Text(
                          reading.lineHeight.toStringAsFixed(1),
                          textAlign: TextAlign.end,
                          style: TextStyle(color: cs.foreground, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  if (onExportAll != null || onImportAll != null) ...[
                    const SizedBox(height: 20),
                    Divider(height: 1, color: cs.border),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '书籍备份',
                        style: TextStyle(
                          color: cs.mutedForeground,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (onExportAll != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                onExportAll!();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: OwnReadColors.orange,
                                side: BorderSide(
                                  color: OwnReadColors.orange
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                              child: const Text('导出所有'),
                            ),
                          ),
                        if (onExportAll != null && onImportAll != null)
                          const SizedBox(width: 10),
                        if (onImportAll != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                onImportAll!();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: OwnReadColors.orange,
                                side: BorderSide(
                                  color: OwnReadColors.orange
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                              child: const Text('导入所有'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        );
      },
    );
  }
}
