import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:ownread/core/services/chapter_splitter.dart';
import 'package:ownread/core/services/library_controller.dart';
import 'package:ownread/core/services/text_replace.dart';
import 'package:ownread/core/storage/novel_repository.dart';
import 'package:ownread/core/theme/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('theme builders return non-null schemes', () {
    final light = buildOwnReadLightTheme();
    final dark = buildOwnReadDarkTheme();
    expect(light.colorScheme.primary, OwnReadColors.orange);
    expect(dark.colorScheme.primary, OwnReadColors.orange);
    expect(dark.colorScheme.foreground, OwnReadColors.inkOnDark);
    expect(materialFromReading(dark: false).colorScheme.primary, isNotNull);
    expect(
      materialFromReading(dark: true).scaffoldBackgroundColor,
      OwnReadColors.surfaceDark,
    );
  });

  testWidgets('materialThemeBuilder applies dark onSurface', (tester) async {
    await tester.pumpWidget(
      ShadApp(
        theme: buildOwnReadLightTheme(),
        darkTheme: buildOwnReadDarkTheme(),
        themeMode: ThemeMode.dark,
        materialThemeBuilder: buildOwnReadMaterialTheme,
        home: Builder(
          builder: (context) {
            final t = Theme.of(context);
            return Text(
              'probe',
              key: ValueKey(t.colorScheme.onSurface.toARGB32()),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final theme = Theme.of(tester.element(find.text('probe')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.onSurface, OwnReadColors.inkOnDark);
  });

  test('decodeUtf8 and long truncate title', () {
    expect(TextReplace.decodeUtf8([0xe4, 0xb8, 0xad]), '中');
    // Line must stay within heading regex length; title display truncates at 40.
    final longTitle = '第一章 ${'标题' * 18}';
    final index = ChapterSplitter.split('$longTitle\n正文内容\n');
    expect(index.length, 1);
    expect(index.chapters.first.title.startsWith('第一章'), isTrue);
    expect(index.chapters.first.title.length, lessThanOrEqualTo(41));
  });

  test('library load on missing root still works after ensure', () async {
    final temp = await Directory.systemTemp.createTemp('ownread_cov_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final repo =
        NovelRepository(root: Directory(p.join(temp.path, 'ownread')));
    final lib = LibraryController(repo);
    await lib.load();
    expect(lib.loading, isFalse);
    expect(lib.novels, isEmpty);
    expect(lib.query, isEmpty);
    expect(lib.error, isNull);
  });

  test('library sorts by progress and chars', () async {
    final temp = await Directory.systemTemp.createTemp('ownread_sort_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final repo =
        NovelRepository(root: Directory(p.join(temp.path, 'ownread')));
    final lib = LibraryController(repo);
    final a = await lib.importText(title: '短', content: '第一章\n短\n');
    final b = await lib.importText(
      title: '长',
      content: '第一章\n${'字' * 200}\n第二章\n更多\n',
    );
    await repo.updateProgress(
      id: a.id,
      chapterIndex: 0,
      fractionInChapter: 0.9,
    );
    await lib.load();
    lib.setSortBy(NovelSortBy.progress);
    expect(lib.novels.first.id, a.id);
    lib.setSortBy(NovelSortBy.totalChars);
    expect(lib.novels.first.id, b.id);
    lib.setSortBy(NovelSortBy.updatedAt);
  });

  test('replaceAll no-op paths in repository', () async {
    final temp = await Directory.systemTemp.createTemp('ownread_cov2_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final repo =
        NovelRepository(root: Directory(p.join(temp.path, 'ownread')));
    final meta = await repo.importTxt(title: 't', content: '第一章\nabc\n');
    expect(
      await repo.replaceAllInNovel(id: meta.id, find: '', replace: 'x'),
      isNull,
    );
    expect(
      await repo.replaceAllInNovel(id: meta.id, find: 'zzz', replace: 'x'),
      isNull,
    );
    final ch = await repo.loadChapterByIndex(meta.id, 0);
    expect(
      await repo.saveChapterEdit(
        id: meta.id,
        chapterIndex: 0,
        newChapterText: ch!,
      ),
      isNull,
    );
    expect(
      await repo.saveChapterEdit(
        id: meta.id,
        chapterIndex: 99,
        newChapterText: 'x',
      ),
      isNull,
    );
    expect(await repo.getMeta('missing'), isNull);
    expect(await repo.loadHistory(meta.id, limit: 1), isEmpty);
    await repo.renameNovel('missing', 'x');
    await repo.updateProgress(
      id: 'missing',
      chapterIndex: 0,
      fractionInChapter: 0,
    );
  });

  test('import empty title uses source filename', () async {
    final temp = await Directory.systemTemp.createTemp('ownread_cov3_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final repo =
        NovelRepository(root: Directory(p.join(temp.path, 'ownread')));
    final meta = await repo.importTxt(
      title: '  ',
      content: '无标题正文',
      sourceFileName: 'from_disk.txt',
    );
    expect(meta.title, 'from_disk.txt');
    expect(meta.chapterCount, 1);
  });
}
