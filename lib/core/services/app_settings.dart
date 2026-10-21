import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/novel_meta.dart';
import '../models/reading_settings.dart';

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _kReading = 'ownread.reading_settings';
  static const _kSort = 'ownread.library_sort';
  static const _kAutoLock = 'ownread.auto_lock';

  ReadingSettings get reading {
    final raw = _prefs.getString(_kReading);
    if (raw == null) return const ReadingSettings();
    try {
      return ReadingSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const ReadingSettings();
    }
  }

  Future<void> setReading(ReadingSettings s) async {
    await _prefs.setString(_kReading, jsonEncode(s.toJson()));
    notifyListeners();
  }

  /// Privacy cover after idle / leaving the app. On by default.
  bool get autoLock => _prefs.getBool(_kAutoLock) ?? true;

  Future<void> setAutoLock(bool enabled) async {
    await _prefs.setBool(_kAutoLock, enabled);
    notifyListeners();
  }

  NovelSortBy get sortBy {
    final raw = _prefs.getString(_kSort);
    return NovelSortBy.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => NovelSortBy.updatedAt,
    );
  }

  Future<void> setSortBy(NovelSortBy sort) async {
    await _prefs.setString(_kSort, sort.name);
    notifyListeners();
  }
}
