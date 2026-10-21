import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/chapter_index.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:ownread/core/services/app_settings.dart';
import 'package:ownread/core/storage/novel_repository.dart';
import 'package:ownread/core/theme/app_theme.dart';
import 'package:ownread/features/reader/screens/reader_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chapterCount = 40;
const _startChapter = 20;

String _title(int i) => '第${i + 1}章 标题${i + 1}';

String _body(int i) {
  // Uneven chapter lengths so any offset-compensation error shows up.
  final lines = 20 + ((i + 1) * 37) % 90;
  return [
    for (var l = 1; l <= lines; l++) '第${i + 1}章第$l行，这是一段用于测试滚动位置稳定性的正文内容。',
  ].join('\n');
}

/// In-memory repository; chapter loads resolve after a short delay like disk.
class _FakeRepository extends NovelRepository {
  _FakeRepository() : super(root: Directory.systemTemp);

  final index = ChapterIndex([
    for (var i = 0; i < _chapterCount; i++)
      ChapterIndexEntry(
        index: i,
        title: _title(i),
        file: '$i.txt',
        charCount: _body(i).length,
      ),
  ]);

  int progressChapter = _startChapter;
  double progressFraction = 0;

  @override
  Future<NovelMeta?> getMeta(String id) async => NovelMeta(
        id: id,
        title: '滚动测试',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        chapterCount: _chapterCount,
        totalChars: index.totalChars,
        editedChars: 0,
        progressChapterIndex: progressChapter,
        progressFractionInChapter: progressFraction,
      );

  @override
  Future<ChapterIndex> loadIndex(String id) async => index;

  @override
  Future<String?> loadChapterByIndex(String id, int i) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return (i >= 0 && i < _chapterCount) ? _body(i) : null;
  }

  @override
  Future<void> updateProgress({
    required String id,
    required int chapterIndex,
    required double fractionInChapter,
  }) async {
    progressChapter = chapterIndex;
    progressFraction = fractionInChapter;
  }
}

void main() {
  late _FakeRepository repo;
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    repo = _FakeRepository();
  });

  Future<void> settle(WidgetTester tester, {int frames = 40}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pumpReader(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadApp(
        theme: buildOwnReadLightTheme(),
        home: ReaderScreen(
          novelId: 'n',
          repository: repo,
          settings: settings,
        ),
      ),
    );
    await settle(tester, frames: 60);
  }

  double titleTop(WidgetTester tester, int chapter) =>
      tester.getTopLeft(find.text(_title(chapter))).dy;

  /// Drag without fling: pause before lifting so release velocity is ~0.
  Future<void> slowDrag(WidgetTester tester, double dy) async {
    final g = await tester.startGesture(const Offset(400, 500));
    final steps = (dy.abs() / 20).round();
    for (var i = 0; i < steps; i++) {
      await g.moveBy(Offset(0, dy.sign * 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await settle(tester, frames: 10);
  }

  testWidgets('opens at saved chapter with its title at the top',
      (tester) async {
    await pumpReader(tester);
    // Running header (44) + the small breathing space above each chapter title
    // (0.6 of one 18px × 1.7 line).
    expect(
      titleTop(tester, _startChapter),
      moreOrLessEquals(44 + 18 * 1.7 * 0.6, epsilon: 1),
    );
    // Previous chapter got loaded above without moving the current one.
    await slowDrag(tester, 200);
    expect(find.text(_title(_startChapter - 1)), findsOneWidget);
  });

  testWidgets('small drags after open move by the drag distance only',
      (tester) async {
    await pumpReader(tester);

    for (final dy in [-60.0, -60.0, 120.0, 200.0, -80.0]) {
      final before = titleTop(tester, _startChapter);
      await slowDrag(tester, dy);
      final moved = titleTop(tester, _startChapter) - before;
      // Touch slop eats up to ~18px of each drag; nothing else may move us.
      expect(moved.sign, dy.sign, reason: 'drag $dy moved $moved');
      expect(moved.abs(), lessThanOrEqualTo(dy.abs() + 1),
          reason: 'drag $dy moved $moved');
      expect(moved.abs(), greaterThan(dy.abs() - 25),
          reason: 'drag $dy moved $moved');
    }
  });

  testWidgets('arrow keys scroll by a small step, never far away',
      (tester) async {
    await pumpReader(tester);

    var previous = titleTop(tester, _startChapter);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await settle(tester, frames: 20);
      final now = titleTop(tester, _startChapter);
      expect(previous - now, inInclusiveRange(40, 130), reason: 'down #$i');
      previous = now;
    }
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await settle(tester, frames: 20);
      final now = titleTop(tester, _startChapter);
      expect(now - previous, inInclusiveRange(40, 130), reason: 'up #$i');
      previous = now;
    }
    expect(find.text(_title(_startChapter - 1)), findsOneWidget);
  });

  testWidgets('long run through lazily loaded chapters returns exactly',
      (tester) async {
    await pumpReader(tester);
    final start = titleTop(tester, _startChapter);

    for (var i = 0; i < 25; i++) {
      await slowDrag(tester, -600);
    }
    expect(find.text(_title(_startChapter)), findsNothing);
    for (var i = 0; i < 25; i++) {
      await slowDrag(tester, 600);
    }
    // Same drags both ways (same slop), so the title must be back in place.
    expect(titleTop(tester, _startChapter), moreOrLessEquals(start, epsilon: 1));

    // Scroll upward through earlier chapters and back as well.
    for (var i = 0; i < 20; i++) {
      await slowDrag(tester, 600);
    }
    expect(find.text(_title(_startChapter)), findsNothing);
    for (var i = 0; i < 20; i++) {
      await slowDrag(tester, -600);
    }
    expect(titleTop(tester, _startChapter), moreOrLessEquals(start, epsilon: 1));
  });

  testWidgets('saved progress reopens at the same reading line',
      (tester) async {
    await pumpReader(tester);
    for (var i = 0; i < 3; i++) {
      await slowDrag(tester, -500);
    }
    await tester.pump(const Duration(seconds: 1));
    final savedChapter = repo.progressChapter;
    final savedFraction = repo.progressFraction;
    final savedTop = titleTop(tester, savedChapter);

    await tester.pumpWidget(const SizedBox());
    await pumpReader(tester);
    expect(repo.progressChapter, savedChapter);
    expect(titleTop(tester, savedChapter), moreOrLessEquals(savedTop, epsilon: 2));
    expect(repo.progressFraction, moreOrLessEquals(savedFraction, epsilon: 0.01));
  });

  testWidgets('sidebar settings button opens the settings dialog',
      (tester) async {
    await pumpReader(tester);
    await tester.tapAt(const Offset(400, 500));
    await settle(tester, frames: 30);
    await tester.tap(find.byTooltip('设置'));
    await settle(tester, frames: 30);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('排版'), findsOneWidget);
    // Library backup stays on the bookshelf only.
    expect(find.text('导出所有'), findsNothing);
    // Sidebar closed so changes show on the page.
    expect(find.text('章节名 / 序号'), findsNothing);
  });
}
