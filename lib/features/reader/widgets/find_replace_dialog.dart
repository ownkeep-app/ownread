import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('全文查找替换'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: _find,
              placeholder: const Text('查找'),
            ),
            const SizedBox(height: 10),
            ShadInput(
              controller: _replace,
              placeholder: const Text('替换为'),
            ),
            const SizedBox(height: 8),
            Text(
              '优先替换当前阅读章节，其余章节在后台继续处理，不影响阅读。',
              style: ShadTheme.of(context).textTheme.muted,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ShadButton(
          onPressed: () {
            Navigator.pop(
              context,
              FindReplaceResult(
                find: _find.text,
                replace: _replace.text,
              ),
            );
          },
          child: const Text('全部替换'),
        ),
      ],
    );
  }
}
