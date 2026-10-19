import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/theme/app_theme.dart';
import 'package:ownread/features/library/widgets/novel_list_tile.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('NovelListTile shows title and progress', (tester) async {
    final novel = NovelMeta(
      id: '1',
      title: '测试书',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      chapterCount: 10,
      totalChars: 1000,
      editedChars: 12,
      progressChapterIndex: 5,
      progressFractionInChapter: 0,
    );

    await tester.pumpWidget(
      ShadApp(
        theme: buildOwnReadLightTheme(),
        home: Scaffold(
          body: NovelListTile(
            index: 0,
            novel: novel,
            onOpen: () {},
            onRename: () {},
            onDelete: () {},
            onExport: () {},
            onHistory: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('测试书'), findsOneWidget);
    expect(find.textContaining('修改 12 字'), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 10)));
}
