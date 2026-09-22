import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/chapter_index.dart';
import '../models/edit_history_entry.dart';
import '../models/novel_meta.dart';
import '../services/chapter_splitter.dart';
import '../services/text_replace.dart';

/// Filesystem layout (fully offline, no DB):
/// ```
/// {root}/
///   library.json
///   novels/{id}/
///     meta.json
///     chapters.index.json
///     chapters/0000.txt …   # one file per chapter (fast edits)
///     history.jsonl
///     book.txt              # legacy monolith; migrated on open
/// ```
class NovelRepository {
  NovelRepository({
    required Directory root,
    Uuid? uuid,
  })  : _root = root,
        _uuid = uuid ?? const Uuid();

  final Directory _root;
  final Uuid _uuid;

  Directory get novelsDir => Directory(p.join(_root.path, 'novels'));
  File get libraryFile => File(p.join(_root.path, 'library.json'));

  Future<void> ensureReady() async {
    if (!await _root.exists()) await _root.create(recursive: true);
    if (!await novelsDir.exists()) await novelsDir.create(recursive: true);
    if (!await libraryFile.exists()) {
      await libraryFile.writeAsString(jsonEncode({'ids': <String>[]}));
    }
  }

  Directory novelDir(String id) => Directory(p.join(novelsDir.path, id));
  Directory chaptersDir(String id) =>
      Directory(p.join(novelDir(id).path, 'chapters'));
  File metaFile(String id) => File(p.join(novelDir(id).path, 'meta.json'));
  File bookFile(String id) => File(p.join(novelDir(id).path, 'book.txt'));
  File indexFile(String id) =>
      File(p.join(novelDir(id).path, 'chapters.index.json'));
  File historyFile(String id) =>
      File(p.join(novelDir(id).path, 'history.jsonl'));
  File chapterFile(String id, String fileName) =>
      File(p.join(chaptersDir(id).path, fileName));

  Future<List<String>> _readIds() async {
    await ensureReady();
    final raw =
        jsonDecode(await libraryFile.readAsString()) as Map<String, dynamic>;
    return (raw['ids'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList();
  }

  Future<void> _writeIds(List<String> ids) async {
    await libraryFile.writeAsString(jsonEncode({'ids': ids}));
  }

  Future<List<NovelMeta>> listNovels() async {
    final ids = await _readIds();
    final out = <NovelMeta>[];
    for (final id in ids) {
      final f = metaFile(id);
      if (await f.exists()) {
        out.add(NovelMeta.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        ));
      }
    }
    return out;
  }

  Future<NovelMeta?> getMeta(String id) async {
    final f = metaFile(id);
    if (!await f.exists()) return null;
    return NovelMeta.fromJson(
      jsonDecode(await f.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> saveMeta(NovelMeta meta) async {
    await metaFile(meta.id).writeAsString(
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
    );
  }

  Future<ChapterIndex> loadIndex(String id) async {
    await _migrateIfNeeded(id);
    final f = indexFile(id);
    if (!await f.exists()) return const ChapterIndex([]);
    return ChapterIndex.fromJson(
      jsonDecode(await f.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> _saveIndex(String id, ChapterIndex index) async {
    await indexFile(id).writeAsString(
      const JsonEncoder.withIndent('  ').convert(index.toJson()),
    );
  }

  /// Write split parts as individual chapter files and return the index.
  Future<ChapterIndex> _writeChapterParts(
    String id,
    List<SplitChapter> parts,
  ) async {
    final dir = chaptersDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    final index = ChapterSplitter.indexFromParts(parts);
    for (var i = 0; i < parts.length; i++) {
      final entry = index.chapters[i];
      await chapterFile(id, entry.file).writeAsString(
        parts[i].content,
        flush: true,
      );
    }
    await _saveIndex(id, index);
    return index;
  }

  /// Migrate legacy `book.txt` novels to per-chapter files (once).
  Future<void> _migrateIfNeeded(String id) async {
    final dir = chaptersDir(id);
    final hasChapters = await dir.exists() &&
        await dir.list().any((e) => e is File && e.path.endsWith('.txt'));
    if (hasChapters) {
      // Ensure index uses file field (rewrite if legacy byte-index only).
      final f = indexFile(id);
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        if (raw['version'] == 2) return;
      }
    }

    final book = bookFile(id);
    if (!await book.exists()) return;

    final text = await book.readAsString();
    final parts = ChapterSplitter.splitParts(text);
    await _writeChapterParts(id, parts);
    try {
      await book.delete();
    } catch (_) {}
  }

  /// Import a TXT file: split into per-chapter files (no monolith book.txt).
  Future<NovelMeta> importTxt({
    required String title,
    required String content,
    String? sourceFileName,
  }) async {
    await ensureReady();
    final id = _uuid.v4();
    final dir = novelDir(id);
    await dir.create(recursive: true);

    final normalized = _normalizeNewlines(content);
    final parts = ChapterSplitter.splitParts(normalized);
    final index = await _writeChapterParts(id, parts);

    final now = DateTime.now().toUtc();
    final meta = NovelMeta(
      id: id,
      title: title.trim().isEmpty ? (sourceFileName ?? '未命名') : title.trim(),
      createdAt: now,
      updatedAt: now,
      chapterCount: index.length,
      totalChars: index.totalChars,
      editedChars: 0,
      progressChapterIndex: 0,
      progressFractionInChapter: 0,
      sourceFileName: sourceFileName,
    );
    await saveMeta(meta);

    final ids = await _readIds();
    ids.insert(0, id);
    await _writeIds(ids);
    return meta;
  }

  Future<void> renameNovel(String id, String newTitle) async {
    final meta = await getMeta(id);
    if (meta == null) return;
    await saveMeta(
      meta.copyWith(title: newTitle.trim(), updatedAt: DateTime.now().toUtc()),
    );
  }

  Future<void> deleteNovel(String id) async {
    final dir = novelDir(id);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final ids = await _readIds()..remove(id);
    await _writeIds(ids);
  }

  Future<void> updateProgress({
    required String id,
    required int chapterIndex,
    required double fractionInChapter,
  }) async {
    final meta = await getMeta(id);
    if (meta == null) return;
    await saveMeta(
      meta.copyWith(
        progressChapterIndex: chapterIndex,
        progressFractionInChapter: fractionInChapter.clamp(0.0, 1.0),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Load one chapter file. Never loads the whole book.
  Future<String> loadChapterText(String id, ChapterIndexEntry entry) async {
    await _migrateIfNeeded(id);
    final f = chapterFile(id, entry.file);
    if (!await f.exists()) return '';
    return f.readAsString();
  }

  Future<String?> loadChapterByIndex(String id, int index) async {
    final chapters = await loadIndex(id);
    final entry = chapters[index];
    if (entry == null) return null;
    return loadChapterText(id, entry);
  }

  Future<String> exportFullText(String id) async {
    final index = await loadIndex(id);
    final buf = StringBuffer();
    for (final entry in index.chapters) {
      buf.write(await loadChapterText(id, entry));
    }
    return buf.toString();
  }

  static const libraryBackupFormat = 'ownread-library';
  static const libraryBackupVersion = 1;

  /// ZIP of the whole warehouse: `library.json`, every novel dir (meta,
  /// chapters, history), plus a small `manifest.json`.
  Future<Uint8List> exportLibraryBackup() async {
    await ensureReady();
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'format': libraryBackupFormat,
          'version': libraryBackupVersion,
          'exportedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      ),
    );

    if (await libraryFile.exists()) {
      archive.addFile(
        ArchiveFile.bytes('library.json', await libraryFile.readAsBytes()),
      );
    }

    if (await novelsDir.exists()) {
      await for (final entity in novelsDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final rel = p
            .relative(entity.path, from: _root.path)
            .replaceAll('\\', '/');
        archive.addFile(
          ArchiveFile.bytes(rel, await entity.readAsBytes()),
        );
      }
    }

    return ZipEncoder().encodeBytes(archive);
  }

  /// Replace the entire local library from a ZIP produced by
  /// [exportLibraryBackup].
  ///
  /// Prefer [importLibraryBackupFromPath] for large backups — loading ~100MB+
  /// into a [List<int>] often OOMs on Android phones.
  Future<int> importLibraryBackup(List<int> bytes) async {
    final tmp = File(
      p.join(
        Directory.systemTemp.path,
        'ownread_import_${DateTime.now().millisecondsSinceEpoch}.zip',
      ),
    );
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      return await importLibraryBackupFromPath(tmp.path);
    } finally {
      if (await tmp.exists()) {
        await tmp.delete();
      }
    }
  }

  /// Stream-extract a backup ZIP from disk (low peak memory).
  ///
  /// Clears all existing novels first. Returns the number of novels restored.
  Future<int> importLibraryBackupFromPath(String zipPath) async {
    String normalize(String name) {
      var n = name.replaceAll('\\', '/');
      if (n.startsWith('./')) n = n.substring(2);
      const wrap = 'ownread/';
      if (n.startsWith(wrap)) n = n.substring(wrap.length);
      return n;
    }

    // Pass 1: validate format without writing the warehouse.
    {
      final input = InputFileStream(zipPath);
      try {
        final archive = ZipDecoder().decodeStream(input);
        ArchiveFile? manifestEntry;
        var hasLibrary = false;
        for (final entry in archive) {
          if (!entry.isFile) continue;
          final name = normalize(entry.name);
          if (name.contains('..') || p.isAbsolute(name)) {
            throw StateError('备份包含非法路径：$name');
          }
          if (name == 'manifest.json') manifestEntry = entry;
          if (name == 'library.json') hasLibrary = true;
        }
        if (manifestEntry == null) {
          throw StateError('不是有效的 OwnRead 备份（缺少 manifest.json）');
        }
        if (!hasLibrary) {
          throw StateError('备份中缺少 library.json');
        }
        final manifestBytes = manifestEntry.readBytes() ?? manifestEntry.content;
        final manifest =
            jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
        if (manifest['format'] != libraryBackupFormat) {
          throw StateError('不支持的备份格式');
        }
      } finally {
        await input.close();
      }
    }

    await ensureReady();
    if (await novelsDir.exists()) {
      await novelsDir.delete(recursive: true);
    }
    await novelsDir.create(recursive: true);
    await libraryFile.writeAsString(jsonEncode({'ids': <String>[]}));

    // Pass 2: stream each entry to disk (decompresses one file at a time).
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      var written = 0;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = normalize(entry.name);
        if (name.isEmpty || name == 'manifest.json') continue;
        if (name.contains('..') || p.isAbsolute(name)) {
          throw StateError('备份包含非法路径：$name');
        }

        final outPath = p.join(_root.path, name);
        await Directory(p.dirname(outPath)).create(recursive: true);
        final output = OutputFileStream(outPath);
        try {
          entry.writeContent(output, freeMemory: true);
        } finally {
          await output.close();
        }
        entry.clear();

        written++;
        // Let the UI breathe on large archives.
        if (written % 25 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      await input.close();
    }

    final ids = await _readIds();
    return ids.length;
  }

  Future<List<EditHistoryEntry>> loadHistory(String id, {int? limit}) async {
    final f = historyFile(id);
    if (!await f.exists()) return const [];
    final lines = await f.readAsLines();
    final entries = <EditHistoryEntry>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      entries.add(
        EditHistoryEntry.fromJson(jsonDecode(line) as Map<String, dynamic>),
      );
    }
    if (limit != null && entries.length > limit) {
      return entries.sublist(entries.length - limit);
    }
    return entries;
  }

  Future<void> _appendHistory(String id, EditHistoryEntry entry) async {
    final f = historyFile(id);
    await f.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  /// In-flight replace-all jobs keyed by novel id (serialized per novel).
  final Map<String, Future<EditHistoryEntry?>> _replaceInFlight = {};

  /// Full-text find/replace across chapter files.
  ///
  /// Processes [priorityChapterIndex] first (typically the chapter being read),
  /// then continues through the rest while yielding between chapters so the UI
  /// stays responsive. [onPriorityComplete] fires once the priority chapter is
  /// done (before other chapters). [onChapterUpdated] fires for each chapter
  /// that actually changed.
  Future<EditHistoryEntry?> replaceAllInNovel({
    required String id,
    required String find,
    required String replace,
    int? priorityChapterIndex,
    void Function(ChapterReplaceUpdate update)? onChapterUpdated,
    void Function(ReplacePriorityResult result)? onPriorityComplete,
  }) {
    final previous = _replaceInFlight[id];
    late final Future<EditHistoryEntry?> next;
    next = () async {
      if (previous != null) await previous;
      return _replaceAllInNovelBody(
        id: id,
        find: find,
        replace: replace,
        priorityChapterIndex: priorityChapterIndex,
        onChapterUpdated: onChapterUpdated,
        onPriorityComplete: onPriorityComplete,
      );
    }();
    _replaceInFlight[id] = next;
    next.whenComplete(() {
      if (identical(_replaceInFlight[id], next)) {
        _replaceInFlight.remove(id);
      }
    });
    return next;
  }

  Future<EditHistoryEntry?> _replaceAllInNovelBody({
    required String id,
    required String find,
    required String replace,
    int? priorityChapterIndex,
    void Function(ChapterReplaceUpdate update)? onChapterUpdated,
    void Function(ReplacePriorityResult result)? onPriorityComplete,
  }) async {
    var priorityNotified = false;
    void notifyPriority(ReplacePriorityResult result) {
      if (priorityNotified) return;
      priorityNotified = true;
      onPriorityComplete?.call(result);
    }

    try {
      if (find.isEmpty) {
        notifyPriority(const ReplacePriorityResult(
          changedChars: 0,
          hadMatch: false,
        ));
        return null;
      }

      final index = await loadIndex(id);
      if (index.length == 0) {
        notifyPriority(const ReplacePriorityResult(
          changedChars: 0,
          hadMatch: false,
        ));
        return null;
      }

      final chapters = List<ChapterIndexEntry>.from(index.chapters);
      var totalChanged = 0;
      var any = false;

      Future<int> processChapter(int i) async {
        final entry = chapters[i];
        final original = await loadChapterText(id, entry);
        final result = TextReplace.replaceAll(original, find, replace);
        if (result.occurrenceCount == 0) return 0;

        await chapterFile(id, entry.file)
            .writeAsString(result.text, flush: true);
        final updatedEntry = entry.copyWith(
          title: ChapterSplitter.titleFromContent(
            result.text,
            fallback: entry.title,
          ),
          charCount: result.text.length,
        );
        chapters[i] = updatedEntry;
        final snapshot = ChapterIndex(List<ChapterIndexEntry>.from(chapters));
        await _saveIndex(id, snapshot);
        onChapterUpdated?.call(
          ChapterReplaceUpdate(
            chapterIndex: i,
            text: result.text,
            changedChars: result.changedChars,
            index: snapshot,
          ),
        );
        return result.changedChars;
      }

      final priority = priorityChapterIndex != null &&
              priorityChapterIndex >= 0 &&
              priorityChapterIndex < chapters.length
          ? priorityChapterIndex
          : null;

      if (priority != null) {
        final changed = await processChapter(priority);
        if (changed > 0) {
          any = true;
          totalChanged += changed;
        }
        notifyPriority(
          ReplacePriorityResult(changedChars: changed, hadMatch: changed > 0),
        );
      } else {
        notifyPriority(const ReplacePriorityResult(
          changedChars: 0,
          hadMatch: false,
        ));
      }

      for (var i = 0; i < chapters.length; i++) {
        if (i == priority) continue;
        // Yield so reading UI can paint / scroll while the rest runs.
        await Future<void>.delayed(Duration.zero);
        final changed = await processChapter(i);
        if (changed > 0) {
          any = true;
          totalChanged += changed;
        }
      }

      if (!any) return null;

      final newIndex = ChapterIndex(chapters);
      await _saveIndex(id, newIndex);

      final history = EditHistoryEntry(
        id: _uuid.v4(),
        createdAt: DateTime.now().toUtc(),
        summary: EditHistoryEntry.summaryReplaceAll(
          find: find,
          replace: replace,
          changedChars: totalChanged,
        ),
        changedChars: totalChanged,
        kind: 'replace_all',
      );
      await _appendHistory(id, history);

      final meta = await getMeta(id);
      if (meta != null) {
        await saveMeta(
          meta.copyWith(
            chapterCount: newIndex.length,
            totalChars: newIndex.totalChars,
            editedChars: meta.editedChars + totalChanged,
            updatedAt: DateTime.now().toUtc(),
            progressChapterIndex: meta.progressChapterIndex
                .clamp(0, mathMax(0, newIndex.length - 1)),
          ),
        );
      }
      return history;
    } catch (_) {
      notifyPriority(const ReplacePriorityResult(
        changedChars: 0,
        hadMatch: false,
      ));
      rethrow;
    }
  }

  /// Save one chapter: writes only that chapter file (fast).
  Future<EditHistoryEntry?> saveChapterEdit({
    required String id,
    required int chapterIndex,
    required String newChapterText,
  }) async {
    final index = await loadIndex(id);
    final entry = index[chapterIndex];
    if (entry == null) return null;

    final oldText = await loadChapterText(id, entry);
    if (oldText == newChapterText) return null;

    final sample = TextReplace.firstDiffSample(oldText, newChapterText);
    final changed = sample?.changedChars ??
        (oldText.length - newChapterText.length).abs().clamp(1, 1 << 30);

    await chapterFile(id, entry.file).writeAsString(newChapterText, flush: true);

    final newTitle = ChapterSplitter.titleFromContent(
      newChapterText,
      fallback: entry.title,
    );
    final newChapters = [
      for (final c in index.chapters)
        if (c.index == chapterIndex)
          c.copyWith(title: newTitle, charCount: newChapterText.length)
        else
          c,
    ];
    final newIndex = ChapterIndex(newChapters);
    await _saveIndex(id, newIndex);

    final history = EditHistoryEntry(
      id: _uuid.v4(),
      createdAt: DateTime.now().toUtc(),
      summary: EditHistoryEntry.summaryChapterEdit(
        chapterNumber1Based: chapterIndex + 1,
        sampleFrom: sample?.from,
        sampleTo: sample?.to,
        changedChars: changed,
      ),
      changedChars: changed,
      kind: 'chapter_edit',
      chapterIndex: chapterIndex,
    );
    await _appendHistory(id, history);

    final meta = await getMeta(id);
    if (meta != null) {
      await saveMeta(
        meta.copyWith(
          chapterCount: newIndex.length,
          totalChars: newIndex.totalChars,
          editedChars: meta.editedChars + changed,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    return history;
  }

  static String _normalizeNewlines(String s) =>
      s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

/// One chapter that changed during progressive replace-all.
class ChapterReplaceUpdate {
  const ChapterReplaceUpdate({
    required this.chapterIndex,
    required this.text,
    required this.changedChars,
    required this.index,
  });

  final int chapterIndex;
  final String text;
  final int changedChars;
  final ChapterIndex index;
}

/// Status after the priority (current-reading) chapter is processed.
class ReplacePriorityResult {
  const ReplacePriorityResult({
    required this.changedChars,
    required this.hadMatch,
  });

  final int changedChars;
  final bool hadMatch;
}

int mathMax(int a, int b) => a > b ? a : b;
