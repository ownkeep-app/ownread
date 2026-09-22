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

    await s.setSortBy(NovelSortBy.title);
    expect(s.sortBy, NovelSortBy.title);
  });
}
