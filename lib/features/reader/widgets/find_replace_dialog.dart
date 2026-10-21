import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/theme/app_theme.dart';

class FindReplaceResult {
  const FindReplaceResult({required this.find, required this.replace});
  final String find;
  final String replace;
}

class FindReplaceDialog extends StatefulWidget {
  const FindReplaceDialog({super.key});

  @override
  State<FindReplaceDialog> createState() => _FindReplaceDialogState();
}

class _FindReplaceDialogState extends State<FindReplaceDialog> {
  final _find = TextEditingController();
  final _replace = TextEditingController();

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      FindReplaceResult(find: _find.text, replace: _replace.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    Widget field(String label, IconData icon, TextEditingController c,
        {bool autofocus = false}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.mutedForeground,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          ShadInput(
            controller: c,
            autofocus: autofocus,
            placeholder: Text(label),
            onSubmitted: (_) => _submit(),
            leading: Padding(
              padding: const EdgeInsets.only(left: 4, right: 2),
              child: Icon(icon, size: 15, color: cs.mutedForeground),
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.replace, size: 18, color: OwnReadAccent.of(context)),
          SizedBox(width: 8),
          Text('全文查找替换'),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field('查找', LucideIcons.search, _find, autofocus: true),
            const SizedBox(height: 14),
            field('替换为', LucideIcons.cornerDownRight, _replace),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.muted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      LucideIcons.info,
                      size: 14,
                      color: cs.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '优先替换当前阅读章节，其余章节在后台继续处理，不影响阅读。',
                      style: TextStyle(
                        color: cs.mutedForeground,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: cs.foreground)),
        ),
        ShadButton(
          onPressed: _submit,
          child: const Text('全部替换'),
        ),
      ],
    );
  }
}
