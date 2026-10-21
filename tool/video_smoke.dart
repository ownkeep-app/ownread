// Native playback diagnostic: flutter run -d macos -t tool/video_smoke.dart
// --dart-define=VIDEO_PATH=/absolute/path/to/video.mp4
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('Video playback check'))));
  final controller = VideoPlayerController.file(
    File(const String.fromEnvironment('VIDEO_PATH')),
  );
  try {
    await controller.initialize().timeout(const Duration(seconds: 20));
    await controller.setVolume(0);
    await controller.play();
    await Future<void>.delayed(const Duration(seconds: 2));
    final position = await controller.position;
    if (position == null || position <= Duration.zero) {
      throw StateError('Playback did not advance');
    }
    debugPrint(
      'VIDEO_SMOKE_OK: ${controller.value.size}, ${controller.value.duration}, position=$position',
    );
    await controller.dispose();
    exit(0);
  } catch (error, stack) {
    debugPrint('VIDEO_SMOKE_FAILED: $error\n$stack');
    await controller.dispose();
    exit(1);
  }
}
