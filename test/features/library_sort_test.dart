import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:ownread/core/services/app_settings.dart';
import 'package:ownread/core/services/library_controller.dart';
import 'package:ownread/core/storage/novel_repository.dart';
import 'package:ownread/core/theme/app_theme.dart';
import 'package:ownread/features/library/screens/library_screen.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('choosing a sort is remembered for the next launch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = AppSettings(prefs);
    final root = Directory.systemTemp.createTempSync('sort');
    addTearDown(() => root.deleteSync(recursive: true));
    final repo = NovelRepository(root: root);
    final lib = LibraryController(repo);
    await tester.runAsync(() async {
      await repo.ensureReady();
      await lib.load(sortBy: settings.sortBy);
    });

    await tester.pumpWidget(ShadApp(
      theme: buildOwnReadLightTheme(),
      materialThemeBuilder: buildOwnReadMaterialTheme,
      home: LibraryScreen(library: lib, repository: repo, settings: settings),
    ));
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('排序'));
    await tester.pump();
    await tester.tap(find.text(NovelSortBy.progress.label).last);
    await tester.pump(const Duration(seconds: 1));

    expect(lib.sortBy, NovelSortBy.progress);
    // A fresh AppSettings on the same storage = the app reopened.
    expect(AppSettings(prefs).sortBy, NovelSortBy.progress);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
