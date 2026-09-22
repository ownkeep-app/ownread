import 'package:flutter/foundation.dart';

import '../models/novel_meta.dart';
import '../storage/novel_repository.dart';

/// Library list state: load, search, sort, mutate.
class LibraryController extends ChangeNotifier {
  LibraryController(this._repo);

  final NovelRepository _repo;

  List<NovelMeta> _all = [];
  String _query = '';
  NovelSortBy _sortBy = NovelSortBy.updatedAt;
  bool _loading = true;
  String? _error;

  List<NovelMeta> get novels => _filteredSorted();
  /// Total novels in the library (ignores search filter).
  int get totalCount => _all.length;
  String get query => _query;
  NovelSortBy get sortBy => _sortBy;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load({NovelSortBy? sortBy}) async {
    _loading = true;
    _error = null;
    if (sortBy != null) _sortBy = sortBy;
    notifyListeners();
    try {
      await _repo.ensureReady();
      _all = await _repo.listNovels();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void setSortBy(NovelSortBy sort) {
    _sortBy = sort;
    notifyListeners();
  }

  Future<void> rename(String id, String title) async {
    await _repo.renameNovel(id, title);
    await load();
  }

  Future<void> delete(String id) async {
    await _repo.deleteNovel(id);
    await load();
  }

  Future<NovelMeta> importText({
    required String title,
    required String content,
    String? sourceFileName,
  }) async {
    final meta = await _repo.importTxt(
      title: title,
      content: content,
      sourceFileName: sourceFileName,
    );
    await load();
    return meta;
  }

  /// Full-library ZIP backup (meta / chapters / history).
  Future<Uint8List> exportAllBackup() => _repo.exportLibraryBackup();

  /// Replace all local novels with a ZIP from [exportAllBackup].
  Future<int> importAllBackup(List<int> bytes) async {
    final count = await _repo.importLibraryBackup(bytes);
    await load();
    return count;
  }

  /// Stream-import a large backup ZIP from a filesystem path (preferred on
  /// Android to avoid OOM).
  Future<int> importAllBackupFromPath(String zipPath) async {
    final count = await _repo.importLibraryBackupFromPath(zipPath);
    await load();
    return count;
  }

  List<NovelMeta> _filteredSorted() {
    var list = List<NovelMeta>.from(_all);
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((n) => n.title.toLowerCase().contains(q)).toList();
    }
    list.sort((a, b) {
      switch (_sortBy) {
        case NovelSortBy.title:
          return a.title.compareTo(b.title);
        case NovelSortBy.progress:
          return b.readingProgress.compareTo(a.readingProgress);
        case NovelSortBy.totalChars:
          return b.totalChars.compareTo(a.totalChars);
        case NovelSortBy.updatedAt:
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });
    return list;
  }
}
