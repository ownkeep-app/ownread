import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/novel_meta.dart';
import 'package:ownread/core/models/reading_settings.dart';
import 'package:ownread/core/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppSettings persists reading and sort', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = AppSettings(prefs);

    expect(s.reading.darkMode, isFalse);
    await s.setReading(const ReadingSettings(darkMode: true, fontSize: 20));
    expect(s.reading.darkMode, isTrue);
    expect(s.reading.fontSize, 20);

    expect(s.reading.font, ReadingFont.chillRound);
    await s.setReading(s.reading.copyWith(font: ReadingFont.harmonySans));
    expect(s.reading.font, ReadingFont.harmonySans);
    expect(s.reading.fontSize, 20);

    await s.setSortBy(NovelSortBy.title);
    expect(s.sortBy, NovelSortBy.title);
  });

  test('ReadingFont falls back to the default for unknown names', () {
    expect(ReadingFont.fromName(null), ReadingSettings.defaultFont);
    expect(ReadingFont.fromName('nope'), ReadingFont.chillRound);
    expect(ReadingFont.fromName('yuan975'), ReadingFont.yuan975);
    expect(
      ReadingSettings.fromJson(
        const ReadingSettings(font: ReadingFont.fangYuan).toJson(),
      ).font,
      ReadingFont.fangYuan,
    );
  });

  test('ThemeAccent persists and defaults to orange', () {
    expect(const ReadingSettings().accent, ThemeAccent.orange);
    expect(ThemeAccent.fromName('nope'), ThemeAccent.orange);
    const teal = ReadingSettings(accent: ThemeAccent.teal);
    expect(ReadingSettings.fromJson(teal.toJson()).accent, ThemeAccent.teal);
    expect(teal, isNot(const ReadingSettings()));
  });

  test('ReadingBackground persists, defaults to 宣纸, maps assets', () {
    expect(const ReadingSettings().background, ReadingBackground.xuan);
    expect(ReadingBackground.fromName('nope'), ReadingBackground.xuan);
    expect(ReadingBackground.plain.asset(false), isNull);
    expect(
      ReadingBackground.stars.asset(true),
      'assets/backgrounds/stars_dark.jpg',
    );
    const s = ReadingSettings(background: ReadingBackground.sakura);
    expect(ReadingSettings.fromJson(s.toJson()).background,
        ReadingBackground.sakura);
  });

  test('every background tile asset exists', () {
    for (final b in ReadingBackground.values) {
      for (final dark in [false, true]) {
        final asset = b.asset(dark);
        if (asset != null) expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    }
  });
}
