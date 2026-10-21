import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/chapter_index.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:ownread/core/services/app_settings.dart';
import 'package:ownread/core/storage/novel_repository.dart';
import 'package:ownread/core/theme/app_theme.dart';
import 'package:ownread/features/reader/screens/reader_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _raw = '　　第一段。\n\n\n　　第二段。\n \n\n　　第三段。\n\n';

class _Repo extends NovelRepository {
  _Repo() : super(root: Directory.systemTemp);

  @override
  Future<NovelMeta?> getMeta(String id) async => NovelMeta(
        id: id,
        title: '空行',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        chapterCount: 1,
        totalChars: _raw.length,
        editedChars: 0,
        progressChapterIndex: 0,
        progressFractionInChapter: 0,
      );

  @override
  Future<ChapterIndex> loadIndex(String id) async => const ChapterIndex([
        ChapterIndexEntry(index: 0, title: '第1章', file: '0.txt', charCount: 9),
      ]);

  @override
  Future<String?> loadChapterByIndex(String id, int i) async =>
      i == 0 ? _raw : null;

  @override
  Future<void> updateProgress({
    required String id,
    required int chapterIndex,
    required double fractionInChapter,
  }) async {}
}

void main() {
  testWidgets('reader hides blank lines but keeps the stored text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    await tester.pumpWidget(ShadApp(
      theme: buildOwnReadLightTheme(),
      materialThemeBuilder: buildOwnReadMaterialTheme,
      home: ReaderScreen(novelId: 'n', repository: _Repo(), settings: settings),
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('　　第一段。\n　　第二段。\n　　第三段。'), findsOneWidget);
  });
}
