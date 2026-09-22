import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:ownread/core/storage/novel_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late NovelRepository repo;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ownread_test_');
    repo = NovelRepository(root: Directory(p.join(temp.path, 'ownread')));
    await repo.ensureReady();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('import creates meta, per-chapter files and lists novel', () async {
    const text = '第一章 开端\n从前有座山\n\n第二章 发展\n山里有座庙\n';
    final meta = await repo.importTxt(
      title: '测试小说',
      content: text,
      sourceFileName: 'test.txt',
    );
    expect(meta.title, '测试小说');
    expect(meta.chapterCount, 2);
    expect(meta.totalChars, greaterThan(0));
    expect(meta.editedChars, 0);

    final list = await repo.listNovels();
    expect(list.length, 1);
    expect(list.first.id, meta.id);

    final index = await repo.loadIndex(meta.id);
    expect(index.length, 2);
    expect(index.chapters.first.file, '0000.txt');

    final ch0 = await repo.loadChapterByIndex(meta.id, 0);
    expect(ch0, contains('第一章'));
    expect(ch0, isNot(contains('第二章')));
    expect(await repo.bookFile(meta.id).exists(), isFalse);
  });

  test('saveChapterEdit only writes that chapter file', () async {
    final meta = await repo.importTxt(
      title: '编辑',
      content: '第一章\n草泥马\n\n第二章\n保持\n',
    );
    final index = await repo.loadIndex(meta.id);
    final file1 = repo.chapterFile(meta.id, index.chapters[1].file);
    final otherBefore = await file1.readAsString();

    final old0 = await repo.loadChapterByIndex(meta.id, 0);
    final entry = await repo.saveChapterEdit(
      id: meta.id,
      chapterIndex: 0,
      newChapterText: old0!.replaceAll('草', '曹'),
    );
    expect(entry, isNotNull);
    expect(entry!.kind, 'chapter_edit');
    expect(entry.summary, contains('第1章'));

    final ch0 = await repo.loadChapterByIndex(meta.id, 0);
    final ch1 = await repo.loadChapterByIndex(meta.id, 1);
    expect(ch0, contains('曹'));
    expect(ch1, otherBefore);
    expect(await file1.readAsString(), otherBefore);
  });

  test('migrates legacy book.txt to chapter files', () async {
    const id = 'legacy-id';
    await repo.novelDir(id).create(recursive: true);
    const text = '第一章\n甲\n\n第二章\n乙\n';
    await repo.bookFile(id).writeAsString(text);
    await repo.indexFile(id).writeAsString(
      jsonEncode({
        'chapters': [
          {
            'index': 0,
            'title': '第一章',
            'startByte': 0,
            'endByte': 10,
            'charCount': 5,
          },
        ],
      }),
    );
    await repo.saveMeta(
      NovelMeta(
        id: id,
        title: '旧书',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        chapterCount: 1,
        totalChars: 5,
        editedChars: 0,
        progressChapterIndex: 0,
        progressFractionInChapter: 0,
      ),
    );
    await repo.libraryFile.writeAsString(jsonEncode({
      'ids': [id],
    }));

    final ch0 = await repo.loadChapterByIndex(id, 0);
    expect(ch0, contains('第一章'));
    final index = await repo.loadIndex(id);
    expect(index.length, 2);
    expect(await repo.chapterFile(id, '0000.txt').exists(), isTrue);
    expect(await repo.bookFile(id).exists(), isFalse);
  });

  test('replaceAll updates chapter files, history and editedChars', () async {
    final meta = await repo.importTxt(
      title: '替换',
      content: '第一章\n他18岁了，她也18岁了\n',
    );
    final entry = await repo.replaceAllInNovel(
      id: meta.id,
      find: '18岁',
      replace: '14岁',
    );
    expect(entry, isNotNull);
    expect(entry!.summary, contains('全文替换'));
    expect(entry.changedChars, greaterThan(0));

    final text = await repo.exportFullText(meta.id);
    expect(text, contains('14岁'));
    expect(text, isNot(contains('18岁')));

    final updated = await repo.getMeta(meta.id);
    expect(updated!.editedChars, greaterThan(0));

    final history = await repo.loadHistory(meta.id);
    expect(history.length, 1);
  });

  test('replaceAll processes priority chapter first', () async {
    final meta = await repo.importTxt(
      title: '优先',
      content: '第一章\n甲18岁\n\n第二章\n乙18岁\n\n第三章\n丙18岁\n',
    );
    final order = <int>[];
    ReplacePriorityResult? priority;
    final entry = await repo.replaceAllInNovel(
      id: meta.id,
      find: '18岁',
      replace: '14岁',
      priorityChapterIndex: 1,
      onChapterUpdated: (u) => order.add(u.chapterIndex),
      onPriorityComplete: (r) => priority = r,
    );
    expect(entry, isNotNull);
    expect(priority, isNotNull);
    expect(priority!.hadMatch, isTrue);
    expect(order.first, 1);
    expect(order.toSet(), {0, 1, 2});

    final ch1 = await repo.loadChapterByIndex(meta.id, 1);
    expect(ch1, contains('14岁'));
    expect(ch1, isNot(contains('18岁')));
  });

  test('rename delete progress', () async {
    final meta = await repo.importTxt(title: 'A', content: '第一章\n正文\n');
    await repo.renameNovel(meta.id, 'B');
    expect((await repo.getMeta(meta.id))!.title, 'B');

    await repo.updateProgress(
      id: meta.id,
      chapterIndex: 0,
      fractionInChapter: 0.5,
    );
    final m2 = await repo.getMeta(meta.id);
    expect(m2!.progressFractionInChapter, 0.5);
    expect(m2.readingProgress, greaterThan(0));

    await repo.deleteNovel(meta.id);
    expect(await repo.listNovels(), isEmpty);
  });

  test('exportLibraryBackup / importLibraryBackup round-trip', () async {
    final a = await repo.importTxt(
      title: '备份甲',
      content: '第一章\n甲内容\n\n第二章\n甲尾\n',
    );
    final b = await repo.importTxt(
      title: '备份乙',
      content: '第一章\n乙内容\n',
    );
    await repo.saveChapterEdit(
      id: a.id,
      chapterIndex: 0,
      newChapterText: '第一章\n甲内容已改\n',
    );
    await repo.updateProgress(
      id: b.id,
      chapterIndex: 0,
      fractionInChapter: 0.3,
    );

    final zip = await repo.exportLibraryBackup();
    expect(zip, isNotEmpty);

    // Pollute library, then restore from ZIP (must wipe first).
    await repo.importTxt(title: '应被清空', content: '第一章\n临时\n');
    expect(await repo.listNovels(), hasLength(3));

    final count = await repo.importLibraryBackup(zip);
    expect(count, 2);

    final list = await repo.listNovels();
    expect(list.map((n) => n.title).toSet(), {'备份甲', '备份乙'});

    final restoredA = list.firstWhere((n) => n.title == '备份甲');
    final ch0 = await repo.loadChapterByIndex(restoredA.id, 0);
    expect(ch0, contains('甲内容已改'));
    final history = await repo.loadHistory(restoredA.id);
    expect(history, isNotEmpty);

    final restoredB = list.firstWhere((n) => n.title == '备份乙');
    expect(
      (await repo.getMeta(restoredB.id))!.progressFractionInChapter,
      closeTo(0.3, 0.001),
    );

    // Path-based streaming import (Android-safe path).
    final zipFile = File('${temp.path}/backup.zip');
    await zipFile.writeAsBytes(zip);
    await repo.importTxt(title: '再次清空', content: '第一章\n临时\n');
    final count2 = await repo.importLibraryBackupFromPath(zipFile.path);
    expect(count2, 2);
    expect(await repo.listNovels(), hasLength(2));
  });

  test('NovelMeta progress math', () {
    final m = NovelMeta(
      id: 'x',
      title: 't',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      chapterCount: 10,
      totalChars: 1000,
      editedChars: 0,
      progressChapterIndex: 5,
      progressFractionInChapter: 0,
    );
    expect(m.readingProgress, closeTo(0.5, 0.001));
  });
}
