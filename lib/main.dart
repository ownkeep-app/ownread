import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/services/app_env.dart';
import 'core/services/app_settings.dart';
import 'core/services/library_controller.dart';
import 'core/storage/novel_repository.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/privacy_guard.dart';
import 'features/library/screens/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppEnv.load();
  final prefs = await SharedPreferences.getInstance();
  final support = await getApplicationSupportDirectory();
  final root = Directory('${support.path}/ownread');
  final repo = NovelRepository(root: root);
  await repo.ensureReady();
  final settings = AppSettings(prefs);
  final library = LibraryController(repo);
  await library.load(sortBy: settings.sortBy);
  runApp(OwnReadApp(
    repository: repo,
    settings: settings,
    library: library,
  ));
}

class OwnReadApp extends StatelessWidget {
  const OwnReadApp({
    super.key,
    required this.repository,
    required this.settings,
    required this.library,
  });

  final NovelRepository repository;
  final AppSettings settings;
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final dark = settings.reading.darkMode;
        return ShadApp(
          title: '私人阅读',
          debugShowCheckedModeBanner: false,
          theme: buildOwnReadLightTheme(),
          darkTheme: buildOwnReadDarkTheme(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          materialThemeBuilder: buildOwnReadMaterialTheme,
          // ShadApp is WidgetsApp-based; Material SnackBars need this ancestor.
          builder: (context, child) => ScaffoldMessenger(
            child: PrivacyGuard(
              idleTimeout: AppEnv.privacyIdleTimeout,
              unlockHold: AppEnv.privacyUnlockHold,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          home: LibraryScreen(
            library: library,
            repository: repository,
            settings: settings,
          ),
        );
      },
    );
  }
}
