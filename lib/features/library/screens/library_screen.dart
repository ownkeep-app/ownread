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
import '../../../core/storage/gallery_repository.dart';
import '../../gallery/screens/gallery_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
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
      builder: (_) => const _BusyIndicator(),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入「${meta.title}」')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
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
            style: TextButton.styleFrom(
              foregroundColor: ShadTheme.of(ctx).colorScheme.destructive,
            ),
            child: const Text('删除'),
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
        content: SizedBox(
          width: 340,
          child: ShadInput(
            controller: controller,
            autofocus: true,
            placeholder: const Text('书名'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已导出')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _exportAll() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyIndicator(),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已导出所有书籍')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _importAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入所有'),
        content: const Text('将清空当前书架上的全部书籍，再从备份文件恢复。此操作不可撤销，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: ShadTheme.of(ctx).colorScheme.destructive,
            ),
            child: const Text('继续'),
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
      builder: (_) => const _BusyIndicator(),
    );
    try {
      final count = await lib.importAllBackupFromPath(path);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $count 本小说')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  Future<void> _showHistory(NovelMeta novel) async {
    final entries = await widget.repository.loadHistory(novel.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

  /// Apply and remember the sort so the next launch opens with it.
  void _setSort(NovelSortBy sort) {
    lib.setSortBy(sort);
    widget.settings.setSortBy(sort);
  }

  void _openSettings() => ReadingSettingsDialog.show(
    context,
    widget.settings,
    onExportAll: _exportAll,
    onImportAll: _importAll,
  );

  @override
  Widget build(BuildContext context) {
    final novels = lib.novels;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 640;
    final hPad = wide ? 32.0 : 16.0;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(hPad, wide ? 28 : 12, hPad, 0),
                  child: _LibraryHeader(
                    wide: wide,
                    count: lib.loading ? null : lib.totalCount,
                    search: _search,
                    sortBy: lib.sortBy,
                    onSort: _setSort,
                    onImport: _import,
                    onSettings: _openSettings,
                    onGallery: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => GalleryScreen(
                          repository: GalleryRepository(
                            root: Directory(
                              p.join(
                                widget.repository.libraryFile.parent.path,
                                'gallery',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: _buildBody(novels, wide: wide, hPad: hPad),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: novels.isEmpty || wide
          ? null
          : FloatingActionButton(
              tooltip: '导入 TXT',
              backgroundColor: OwnReadAccent.of(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              onPressed: _import,
              child: const Icon(LucideIcons.plus, color: Colors.white),
            ),
    );
  }

  Widget _buildBody(
    List<NovelMeta> novels, {
    required bool wide,
    required double hPad,
  }) {
    if (lib.loading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (lib.error != null) {
      return Center(key: const ValueKey('error'), child: Text(lib.error!));
    }
    if (novels.isEmpty) {
      return _EmptyLibrary(
        key: const ValueKey('empty'),
        searching: _search.text.trim().isNotEmpty,
        onImport: _import,
      );
    }
    return ListenableBuilder(
      key: const ValueKey('list'),
      listenable: widget.settings,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 920 ? 2 : 1;
          Widget card(int i) {
            final n = novels[i];
            return FadeSlideIn(
              key: ValueKey(n.id),
              delay: Duration(milliseconds: i < 12 ? 40 * i : 0),
              child: NovelListTile(
                index: i + 1,
                novel: n,
                onOpen: () => _openReader(n),
                onRename: () => _rename(n),
                onDelete: () => _confirmDelete(n),
                onExport: () => _export(n),
                onHistory: () => _showHistory(n),
                font: widget.settings.reading.font,
              ),
            );
          }

          final rows = (novels.length / columns).ceil();
          return EntranceScope(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(hPad, 4, hPad, wide ? 32 : 96),
              itemCount: rows,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, r) {
                if (columns == 1) return card(r);
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: 12),
                        Expanded(
                          child: r * columns + c < novels.length
                              ? card(r * columns + c)
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.wide,
    required this.count,
    required this.search,
    required this.sortBy,
    required this.onSort,
    required this.onImport,
    required this.onSettings,
    required this.onGallery,
  });

  final bool wide;
  final int? count;
  final TextEditingController search;
  final NovelSortBy sortBy;
  final ValueChanged<NovelSortBy> onSort;
  final VoidCallback onImport;
  final VoidCallback onSettings;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BlurText(
          '私人阅读',
          style: OwnReadType.heading(
            size: wide ? 30 : 24,
            color: cs.foreground,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            count == null ? '书架' : '书架 · 共 $count 本',
            key: ValueKey(count),
            style: TextStyle(color: cs.mutedForeground, fontSize: 13),
          ),
        ),
      ],
    );

    final searchField = ShadInput(
      controller: search,
      placeholder: const Text('查找小说'),
      leading: Padding(
        padding: const EdgeInsets.only(left: 4, right: 2),
        child: Icon(LucideIcons.search, size: 16, color: cs.mutedForeground),
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderIcon(
          icon: Icons.photo_library_outlined,
          tooltip: '图库',
          onTap: onGallery,
        ),
        const SizedBox(width: 6),
        PopupMenuButton<NovelSortBy>(
          tooltip: '排序',
          position: PopupMenuPosition.under,
          // Opens and closes instantly, no grow/fade.
          popUpAnimationStyle: AnimationStyle.noAnimation,
          onSelected: onSort,
          itemBuilder: (_) => [
            for (final s in NovelSortBy.values)
              PopupMenuItem(
                value: s,
                height: 40,
                child: Row(
                  children: [
                    if (sortBy == s)
                      Icon(
                        LucideIcons.check,
                        size: 16,
                        color: OwnReadAccent.of(context),
                      )
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 10),
                    Text(s.label),
                  ],
                ),
              ),
          ],
          child: _HeaderIcon(icon: LucideIcons.arrowUpDown),
        ),
        const SizedBox(width: 6),
        _HeaderIcon(
          icon: LucideIcons.settings,
          tooltip: '设置',
          onTap: onSettings,
        ),
        const SizedBox(width: 10),
        if (wide)
          ShadButton(
            onPressed: onImport,
            leading: const Icon(LucideIcons.filePlus2, size: 16),
            child: const Text('导入 TXT'),
          )
        else
          _HeaderIcon(
            icon: LucideIcons.filePlus2,
            tooltip: '导入 TXT',
            onTap: onImport,
          ),
      ],
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: title),
          const SizedBox(width: 16),
          SizedBox(width: 260, child: searchField),
          const SizedBox(width: 10),
          actions,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: title),
            actions,
          ],
        ),
        const SizedBox(height: 14),
        searchField,
      ],
    );
  }
}

/// Quiet square icon button used in the library header.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, this.tooltip, this.onTap});

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final box = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.border),
      ),
      child: Icon(icon, size: 17, color: cs.foreground),
    );
    if (onTap == null) return box;
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: box,
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    super.key,
    required this.searching,
    required this.onImport,
  });

  final bool searching;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Center(
      child: FadeSlideIn(
        blur: 4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    OwnReadAccent.of(context).withValues(alpha: 0.18),
                    OwnReadAccent.of(context).withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Icon(
                searching ? LucideIcons.searchX : LucideIcons.bookOpen,
                size: 40,
                color: OwnReadAccent.of(context),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              searching ? '没有匹配的小说' : '还没有小说',
              style: OwnReadType.heading(size: 18, color: cs.foreground),
            ),
            const SizedBox(height: 6),
            Text(
              searching ? '换个书名试试' : '导入本地 TXT，自动分章，离线阅读',
              style: TextStyle(color: cs.mutedForeground, fontSize: 13),
            ),
            if (!searching) ...[
              const SizedBox(height: 20),
              ShadButton(
                onPressed: onImport,
                leading: const Icon(LucideIcons.filePlus2, size: 16),
                child: const Text('导入 TXT'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small card shown while a long import/export runs.
class _BusyIndicator extends StatelessWidget {
  const _BusyIndicator();

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.border),
        ),
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
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
    final cs = ShadTheme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: cs.border,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Icon(
                LucideIcons.history,
                size: 18,
                color: OwnReadAccent.of(context),
              ),
              const SizedBox(width: 8),
              Text(
                '修改历史',
                style: OwnReadType.heading(size: 18, color: cs.foreground),
              ),
              const Spacer(),
              Text(
                '${entries.length} 条',
                style: TextStyle(color: cs.mutedForeground, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    '暂无修改记录',
                    style: TextStyle(color: cs.mutedForeground),
                  ),
                )
              : EntranceScope(
                  child: ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[entries.length - 1 - i];
                      final last = i == entries.length - 1;
                      return FadeSlideIn(
                        delay: Duration(milliseconds: i < 10 ? 30 * i : 0),
                        offset: 8,
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 18,
                                child: Column(
                                  children: [
                                    const SizedBox(height: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: OwnReadAccent.of(context),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    if (!last)
                                      Expanded(
                                        child: Container(
                                          width: 1,
                                          color: cs.border,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.summary,
                                        style: TextStyle(
                                          color: cs.foreground,
                                          fontSize: 14,
                                          height: 1.55,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _fmt(e.createdAt),
                                        style: TextStyle(
                                          color: cs.mutedForeground,
                                          fontSize: 12,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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
