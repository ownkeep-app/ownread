import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/reading_settings.dart';
import 'package:ownread/core/services/app_settings.dart';
import 'package:ownread/core/theme/app_theme.dart';
import 'package:ownread/features/library/widgets/reading_settings_dialog.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('主题 and 排版 start collapsed; theme colour applies', (tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ListenableBuilder(
      listenable: settings,
      builder: (_, _) => ShadApp(
        navigatorKey: nav,
        theme: buildOwnReadLightTheme(
          settings.reading.font,
          settings.reading.accent,
        ),
        materialThemeBuilder: buildOwnReadMaterialTheme,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    ReadingSettingsDialog.show(nav.currentContext!, settings);
    await tester.pumpAndSettle();

    expect(find.text('主题'), findsOneWidget);
    expect(find.text('主题颜色'), findsNothing);
    expect(find.text('淡色 · 暖橙 · 宣纸'), findsOneWidget); // summary line
    expect(find.text('排版'), findsOneWidget);
    expect(find.text('字号'), findsNothing);
    expect(find.textContaining('字号 18'), findsOneWidget); // summary line

    await tester.tap(find.text('排版'));
    await tester.pumpAndSettle();
    expect(find.text('字号'), findsOneWidget);
    expect(find.text('行距'), findsOneWidget);
    expect(find.text('字体'), findsOneWidget);

    // Collapsing slides the options away, then removes them.
    await tester.tap(find.text('排版'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('字号'), findsOneWidget); // still animating out
    await tester.pumpAndSettle();
    expect(find.text('字号'), findsNothing);
    await tester.tap(find.text('排版'));
    await tester.pumpAndSettle();
    expect(find.text('字号'), findsOneWidget);

    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    expect(find.text('主题颜色'), findsOneWidget);
    expect(find.text('阅读背景'), findsOneWidget);

    await tester.tap(find.byTooltip('青碧'));
    await tester.pumpAndSettle();
    expect(settings.reading.accent, ThemeAccent.teal);
    final ctx = tester.element(find.text('设置'));
    expect(ShadTheme.of(ctx).colorScheme.primary, ThemeAccent.teal.color);

    await tester.tap(find.text('星河'));
    await tester.pumpAndSettle();
    expect(settings.reading.background, ReadingBackground.stars);
  });
}
