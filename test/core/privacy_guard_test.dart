import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/services/app_settings.dart';
import 'package:ownread/core/widgets/privacy_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({required bool enabled}) => MaterialApp(
      home: PrivacyGuard(
        enabled: enabled,
        idleTimeout: const Duration(seconds: 5),
        unlockHold: const Duration(seconds: 1),
        child: const Text('book'),
      ),
    );

void main() {
  test('AppSettings autoLock defaults on and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings(await SharedPreferences.getInstance());
    expect(s.autoLock, isTrue);
    await s.setAutoLock(false);
    expect(s.autoLock, isFalse);
  });

  testWidgets('locks after idle when enabled', (tester) async {
    await tester.pumpWidget(_app(enabled: true));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('目前无内容'), findsOneWidget);
  });

  testWidgets('never locks when disabled', (tester) async {
    await tester.pumpWidget(_app(enabled: false));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('目前无内容'), findsNothing);
  });

  testWidgets('switching off removes an active cover', (tester) async {
    await tester.pumpWidget(_app(enabled: true));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('目前无内容'), findsOneWidget);
    await tester.pumpWidget(_app(enabled: false));
    await tester.pump();
    expect(find.text('目前无内容'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('目前无内容'), findsNothing);
  });

  testWidgets('only a hold on the drawing unlocks', (tester) async {
    await tester.pumpWidget(_app(enabled: true));
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('目前无内容'), findsOneWidget);

    // Long hold in a corner: stays locked.
    final corner = await tester.startGesture(const Offset(10, 10));
    await tester.pump(const Duration(seconds: 2));
    await corner.up();
    await tester.pump();
    expect(find.text('目前无内容'), findsOneWidget);

    // Long hold on the title text (not the drawing): stays locked.
    final onText = await tester.startGesture(
      tester.getCenter(find.text('目前无内容')),
    );
    await tester.pump(const Duration(seconds: 2));
    await onText.up();
    await tester.pump();
    expect(find.text('目前无内容'), findsOneWidget);

    // Short press on the drawing: stays locked.
    final drawing = find.byType(CustomPaint).last;
    final quick = await tester.startGesture(tester.getCenter(drawing));
    await tester.pump(const Duration(milliseconds: 400));
    await quick.up();
    await tester.pump();
    expect(find.text('目前无内容'), findsOneWidget);

    // Full hold on the drawing: unlocks.
    final hold = await tester.startGesture(tester.getCenter(drawing));
    await tester.pump(const Duration(milliseconds: 1100));
    await hold.up();
    await tester.pump();
    expect(find.text('目前无内容'), findsNothing);
    expect(find.text('book'), findsOneWidget);
  });
}
