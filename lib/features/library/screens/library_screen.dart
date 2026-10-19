import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/edit_history_entry.dart';
import '../../../core/models/novel_meta.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/library_controller.dart';
import '../../../core/services/txt_file_decoder.dart';
import '../../../core/storage/novel_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../reader/screens/reader_screen.dart';
import '../widgets/novel_list_tile.dart';
import '../widgets/reading_settings_dialog.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.library,
    required this.repository,
    required this.settings,
  });

  final LibraryController library;
  final NovelRepository repository;
  final AppSettings settings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();

  LibraryController get lib => widget.library;

  @override
  void initState() {
    super.initState();
    lib.addListener(_onLib);
    _search.addListener(() => lib.setQuery(_search.text));
  }

  @override
  void dispose() {
    lib.removeListener(_onLib);
    _search.dispose();
    super.dispose();
  }

  void _onLib() {
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final path = file.path;
    if (path == null) return;

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final content = await TxtFileDecoder.readFile(path);
      final title = p.basenameWithoutExtension(path);
      final meta = await lib.importText(
        title: title,
        content: content,
        sourceFileName: p.basename(path),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入「${meta.title}」')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _openReader(NovelMeta meta) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          novelId: meta.id,
          repository: widget.repository,
          settings: widget.settings,
        ),
      ),
    );
    await lib.load();
  }

  Future<void> _confirmDelete(NovelMeta novel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除小说'),
        content: Text('确定删除《${novel.title}》？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) await lib.delete(novel.id);
  }

  Future<void> _rename(NovelMeta novel) async {
    final controller = TextEditingController(text: novel.title);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改书名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '书名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (next != null && next.isNotEmpty) {
      await lib.rename(novel.id, next);
    }
  }

  Future<void> _export(NovelMeta novel) async {
    try {
      final text = await widget.repository.exportFullText(novel.id);
      final bytes = Uint8List.fromList(utf8.encode(text));
      // macOS/desktop: saveFile only returns a path; bytes are unsupported.
      // Android: bytes are written by the picker.
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出全文',
        fileName: '${novel.title}.txt',
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        bytes: Platform.isAndroid ? bytes : null,
      );
      if (path == null) return;
      if (!Platform.isAndroid) {
        final out = path.endsWith('.txt') ? path : '$path.txt';
        await File(out).writeAsBytes(bytes, flush: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已导出')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _exportAll() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final bytes = await lib.exportAllBackup();
      if (!mounted) return;
      Navigator.of(context).pop();
      final stamp = DateTime.now().toIso8601String().split('T').first;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出所有书籍',
        fileName: 'ownread-backup-$stamp.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: Platform.isAndroid ? bytes : null,
      );
      if (path == null) return;
      if (!Platform.isAndroid) {
        final out = path.endsWith('.zip') ? path : '$path.zip';
        await File(out).writeAsBytes(bytes, flush: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已导出所有书籍')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  Future<void> _importAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入所有'),
        content: const Text(
          '将清空当前书架上的全部书籍，再从备份文件恢复。此操作不可撤销，确定继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      // Keep the ZIP on disk — loading ~100MB into RAM crashes many phones.
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    var path = file.path;
    if (path == null || path.isEmpty) {
      // Rare fallback: picker only returned bytes.
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final tmp = File(
        '${Directory.systemTemp.path}/ownread_import_${DateTime.now().millisecondsSinceEpoch}.zip',
      );
      await tmp.writeAsBytes(bytes, flush: true);
      path = tmp.path;
    }

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final count = await lib.importAllBackupFromPath(path);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $count 本小说')),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _showHistory(NovelMeta novel) async {
    final entries = await widget.repository.loadHistory(novel.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, scroll) =>
            _HistorySheet(entries: entries, controller: scroll),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final novels = lib.novels;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          lib.loading ? '私人阅读' : '私人阅读 · 共 ${lib.totalCount} 本',
        ),
        actions: [
          PopupMenuButton<NovelSortBy>(
            tooltip: '排序',
            icon: const Icon(LucideIcons.arrowUpDown, size: 20),
            onSelected: lib.setSortBy,
            itemBuilder: (_) => [
              for (final s in NovelSortBy.values)
                PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      if (lib.sortBy == s)
                        const Icon(
                          LucideIcons.check,
                          size: 16,
                          color: OwnReadColors.orange,
                        )
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(s.label),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: '导入 TXT',
            onPressed: _import,
            icon: const Icon(LucideIcons.filePlus2, size: 22),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => ReadingSettingsDialog.show(
              context,
              widget.settings,
              onExportAll: _exportAll,
              onImportAll: _importAll,
            ),
            icon: const Icon(LucideIcons.settings, size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ShadInput(
              controller: _search,
              placeholder: const Text('查找小说'),
              leading: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(LucideIcons.search, size: 16),
              ),
            ),
          ),
          Expanded(
            child: lib.loading
                ? const Center(child: CircularProgressIndicator())
                : lib.error != null
                    ? Center(child: Text(lib.error!))
                    : novels.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  LucideIcons.bookOpen,
                                  size: 48,
                                  color: OwnReadColors.orange.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '还没有小说',
                                  style: ShadTheme.of(context).textTheme.muted,
                                ),
                                const SizedBox(height: 8),
                                ShadButton(
                                  onPressed: _import,
                                  child: const Text('导入 TXT'),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: novels.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final n = novels[i];
                              return NovelListTile(
                                index: i + 1,
                                novel: n,
                                onOpen: () => _openReader(n),
                                onRename: () => _rename(n),
                                onDelete: () => _confirmDelete(n),
                                onExport: () => _export(n),
                                onHistory: () => _showHistory(n),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: novels.isEmpty
          ? null
          : FloatingActionButton(
              backgroundColor: OwnReadColors.orange,
              onPressed: _import,
              child: const Icon(LucideIcons.plus, color: Colors.white),
            ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.entries, required this.controller});

  final List<EditHistoryEntry> entries;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('修改历史', style: ShadTheme.of(context).textTheme.large),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('暂无修改记录'))
              : ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = entries[entries.length - 1 - i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.summary),
                      subtitle: Text(
                        _fmt(e.createdAt),
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
