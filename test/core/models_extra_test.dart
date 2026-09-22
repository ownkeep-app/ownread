import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/chapter_index.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:ownread/core/models/reading_settings.dart';
import 'package:ownread/core/services/app_settings.dart';
import 'package:ownread/core/services/text_replace.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('ReadingSettings equality and fromJson defaults', () {
    const a = ReadingSettings(darkMode: true, fontSize: 16, lineHeight: 1.5);
    const b = ReadingSettings(darkMode: true, fontSize: 16, lineHeight: 1.5);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(ReadingSettings.fromJson({}), const ReadingSettings());
  });

  test('ChapterIndex out of range and equality', () {
    const e = ChapterIndexEntry(
      index: 0,
      title: 't',
      file: '0000.txt',
      charCount: 1,
    );
    const idx = ChapterIndex([e]);
    expect(idx[-1], isNull);
    expect(idx[3], isNull);
    expect(idx[0], e);
    expect(e, ChapterIndexEntry.fromJson(e.toJson()));
    expect(e.hashCode, isNonZero);
  });

  test('NovelMeta copyWith and fromJson defaults', () {
    final now = DateTime.utc(2026, 1, 1);
    final m = NovelMeta(
      id: 'id',
      title: 't',
      createdAt: now,
      updatedAt: now,
      chapterCount: 0,
      totalChars: 0,
      editedChars: 0,
      progressChapterIndex: 0,
      progressFractionInChapter: 0,
    );
    expect(m.readingProgress, 0);
    final c = m.copyWith(title: 'n', editedChars: 3, sourceFileName: 'a.txt');
    expect(c.title, 'n');
    expect(c.editedChars, 3);
    expect(c.sourceFileName, 'a.txt');
    final again = NovelMeta.fromJson({
      'id': 'x',
      'title': 'y',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
    expect(again.chapterCount, 0);
  });

  test('AppSettings tolerates corrupt reading json', () async {
    SharedPreferences.setMockInitialValues({
      'ownread.reading_settings': '{not-json',
      'ownread.library_sort': 'nope',
    });
    final prefs = await SharedPreferences.getInstance();
    final s = AppSettings(prefs);
    expect(s.reading, const ReadingSettings());
    expect(s.sortBy, NovelSortBy.updatedAt);
  });

  test('TextReplace insert-only and delete-only diffs', () {
    final a = TextReplace.firstDiffSample('abc', 'abcXYZ');
    expect(a, isNotNull);
    expect(a!.to, contains('XYZ'));
    final b = TextReplace.firstDiffSample('abcXYZ', 'abc');
    expect(b!.from, contains('XYZ'));
  });
}
