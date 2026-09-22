import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/novel_meta.dart';
import '../../../core/theme/app_theme.dart';

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
  });

  /// 1-based position in the current library list.
  final int index;
  final NovelMeta novel;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final pct = (novel.readingProgress * 100).clamp(0, 100);

    return Material(
      color: theme.colorScheme.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$index.',
                    style: theme.textTheme.large.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.mutedForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      novel.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.large.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(LucideIcons.ellipsisVertical, size: 18),
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
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('修改书名')),
                      PopupMenuItem(value: 'export', child: Text('导出全文')),
                      PopupMenuItem(value: 'history', child: Text('修改历史')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${novel.chapterCount} 章 · ${novel.totalChars} 字 · 修改 ${novel.editedChars} 字',
                style: theme.textTheme.small.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: novel.readingProgress.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: theme.colorScheme.muted,
                        color: OwnReadColors.orange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: theme.textTheme.small.copyWith(
                      color: OwnReadColors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
