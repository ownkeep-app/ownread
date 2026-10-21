import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/novel_meta.dart';
import '../../../core/models/reading_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';

class NovelListTile extends StatelessWidget {
  const NovelListTile({
    super.key,
    required this.index,
    required this.novel,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onExport,
    required this.onHistory,
    this.font = ReadingSettings.defaultFont,
  });

  /// 1-based position in the current library list.
  final int index;
  final NovelMeta novel;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback onHistory;

  /// Global reading font; the title, details and spine glyph use it.
  final ReadingFont font;

  /// Big numbers read better in 万 for Chinese readers (e.g. 128.4 万字).
  static String formatChars(int n) {
    if (n >= 10000) {
      final w = n / 10000;
      return '${w >= 100 ? w.toStringAsFixed(0) : w.toStringAsFixed(1)} 万';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final progress = novel.readingProgress.clamp(0.0, 1.0);
    final pct = (progress * 100).clamp(0, 100);

    return SpotlightSurface(
      onTap: onOpen,
      color: cs.card,
      borderColor: cs.border,
      hoverBorderColor: OwnReadAccent.of(context).withValues(alpha: 0.45),
      spotlightColor: OwnReadAccent.of(context).withValues(alpha: dark ? 0.10 : 0.07),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _BookSpine(title: novel.title, font: font),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          novel.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OwnReadType.reading(
                            font,
                            size: 17,
                            weight: FontWeight.w600,
                            color: cs.foreground,
                            height: 1.25,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Text(
                        '#$index',
                        style: theme.textTheme.small.copyWith(
                          color: cs.mutedForeground.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${novel.chapterCount} 章 · ${formatChars(novel.totalChars)}字 · 修改 ${novel.editedChars} 字',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OwnReadType.reading(
                            font,
                            size: 13,
                            // Pin line boxes: some bundled fonts have very
                            // tall default metrics that bloat the card.
                            height: 1.3,
                            color: cs.mutedForeground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: theme.textTheme.small.copyWith(
                          color: OwnReadAccent.text(context),
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: v,
                        minHeight: 4,
                        backgroundColor: cs.muted,
                        color: OwnReadAccent.of(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: Icon(
                LucideIcons.ellipsis,
                size: 18,
                color: cs.mutedForeground,
              ),
              position: PopupMenuPosition.under,
              onSelected: (v) {
                switch (v) {
                  case 'rename':
                    onRename();
                  case 'export':
                    onExport();
                  case 'history':
                    onHistory();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                _item('rename', LucideIcons.pencilLine, '修改书名', cs),
                _item('export', LucideIcons.download, '导出全文', cs),
                _item('history', LucideIcons.history, '修改历史', cs),
                const PopupMenuDivider(height: 8),
                _item('delete', LucideIcons.trash2, '删除', cs,
                    color: cs.destructive),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label,
    ShadColorScheme cs, {
    Color? color,
  }) {
    final c = color ?? cs.foreground;
    return PopupMenuItem(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? cs.mutedForeground),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: c, fontSize: 14)),
        ],
      ),
    );
  }
}

/// Typographic "spine": the title's first character on a warm tone picked
/// from the title, so books are recognisable at a glance without covers.
class _BookSpine extends StatelessWidget {
  const _BookSpine({required this.title, required this.font});

  final String title;
  final ReadingFont font;

  static const _tones = <List<Color>>[
    [Color(0xFFE88A4F), Color(0xFFC85F28)],
    [Color(0xFFD4A15A), Color(0xFFB07A33)],
    [Color(0xFFB9785A), Color(0xFF8E5139)],
    [Color(0xFF8E9B6B), Color(0xFF66744A)],
    [Color(0xFF7C8FA0), Color(0xFF55687A)],
    [Color(0xFFA27B9C), Color(0xFF7A5574)],
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final glyph = trimmed.isEmpty ? '书' : trimmed.characters.first;
    final seed = trimmed.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    final tone = _tones[seed % _tones.length];
    return Container(
      width: 40,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomLeft: Radius.circular(4),
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tone,
        ),
        boxShadow: [
          BoxShadow(
            color: tone.last.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Binding edge.
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1.5,
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
          Center(
            child: Text(
              glyph,
              style: OwnReadType.reading(
                font,
                size: 19,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
