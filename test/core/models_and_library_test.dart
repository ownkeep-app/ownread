import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/chapter_index.dart';
import 'package:ownread/core/models/edit_history_entry.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:ownread/core/models/reading_settings.dart';
import 'package:ownread/core/services/library_controller.dart';
import 'package:ownread/core/storage/novel_repository.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  group('models json roundtrip', () {
    test('ChapterIndex', () {
      const idx = ChapterIndex([
        ChapterIndexEntry(
          index: 0,
          title: '第一章',
          file: '0000.txt',
          charCount: 5,
        ),
      ]);
      final again = ChapterIndex.fromJson(idx.toJson());
      expect(again.chapters.first, idx.chapters.first);
      expect(again.totalChars, 5);
    });

    test('EditHistoryEntry', () {
      final e = EditHistoryEntry(
        id: '1',
        createdAt: DateTime.utc(2026, 1, 2),
        summary: 'x',
        changedChars: 3,
        kind: 'replace_all',
      );
      final again = EditHistoryEntry.fromJson(e.toJson());
      expect(again.id, '1');
      expect(again.changedChars, 3);
    });

    test('ReadingSettings clamp', () {
      const s = ReadingSettings();
      expect(s.copyWith(fontSize: 100).fontSize, ReadingSettings.maxFontSize);
      expect(s.copyWith(lineHeight: 0.1).lineHeight, ReadingSettings.minLineHeight);
      expect(ReadingSettings.fromJson(s.toJson()), s);
    });

    test('NovelSortBy labels', () {
      expect(NovelSortBy.title.label, '书名');
      expect(NovelSortBy.updatedAt.label, '最近阅读');
    });
  });

  group('LibraryController', () {
    late Directory temp;
    late LibraryController lib;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('ownread_lib_');
      final repo = NovelRepository(root: Directory(p.join(temp.path, 'ownread')));
      await repo.ensureReady();
      lib = LibraryController(repo);
      await lib.importText(title: '雪山飞狐', content: '第一章\n甲\n');
      await lib.importText(title: '天龙八部', content: '第一章\n乙\n');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('search and sort', () async {
      await lib.load();
      expect(lib.novels.length, 2);
      lib.setQuery('雪山');
      expect(lib.novels.length, 1);
      expect(lib.novels.first.title, '雪山飞狐');
      lib.setQuery('');
      lib.setSortBy(NovelSortBy.title);
      expect(lib.novels.first.title, '天龙八部');
    });

    test('rename and delete', () async {
      await lib.load();
      final id = lib.novels.first.id;
      await lib.rename(id, '新名字');
      expect(lib.novels.any((n) => n.title == '新名字'), isTrue);
      await lib.delete(id);
      expect(lib.novels.any((n) => n.id == id), isFalse);
    });
  });
}
