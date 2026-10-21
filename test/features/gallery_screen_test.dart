import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/storage/gallery_repository.dart';
import 'package:ownread/features/gallery/screens/gallery_screen.dart';

void main() {
  testWidgets(
    'gallery filters media, uses video tiles and offers image-only export',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('gallery_widget'),
      ))!;
      addTearDown(() => temp.delete(recursive: true));
      final repo = GalleryRepository(root: Directory('${temp.path}/gallery'));
      await tester.runAsync(() async {
        await repo.add(await File('${temp.path}/photo.png').writeAsBytes([1]));
        await repo.add(await File('${temp.path}/clip.mp4').writeAsBytes([2]));
      });
      final items = (await tester.runAsync(repo.load))!;
      await tester.pumpWidget(
        MaterialApp(
          home: GalleryScreen(repository: _LoadedRepository(repo.root, items)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('photo.png'), findsOneWidget);
      expect(find.text('clip.mp4'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('导入图片 ZIP'), findsOneWidget);
      expect(find.text('导出全部图片 ZIP'), findsOneWidget);
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, '视频'));
      await tester.pumpAndSettle();
      expect(find.text('photo.png'), findsNothing);
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pumpAndSettle();
      expect(find.text('导出图片'), findsNothing);
      expect(find.text('删除'), findsOneWidget);
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pumpAndSettle();
      expect(find.text('导出图片'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'viewer swipes in filtered order from selected image and stops at ends',
    (tester) async {
      final temp = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('gallery_swipe'),
      ))!;
      addTearDown(() => temp.delete(recursive: true));
      final items = <GalleryItem>[];
      await tester.runAsync(() async {
        final bytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=',
        );
        for (var i = 0; i < 3; i++) {
          final file = await File(
            '${temp.path}/image$i.png',
          ).writeAsBytes(bytes);
          items.add(
            GalleryItem(
              file: file,
              name: 'image$i.png',
              kind: GalleryKind.image,
              addedAt: DateTime.now(),
            ),
          );
        }
        items.insert(
          1,
          GalleryItem(
            file: File('${temp.path}/video.mp4'),
            name: 'video.mp4',
            kind: GalleryKind.video,
            addedAt: DateTime.now(),
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: GalleryScreen(repository: _LoadedRepository(temp, items)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image).at(1));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      final transform = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      transform.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();
      await tester.drag(find.byType(InteractiveViewer), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('200%'), findsOneWidget);
      transform.value = Matrix4.diagonal3Values(1.2, 1.2, 1);
      await tester.pump();
      expect(find.text('120%'), findsOneWidget);
      await tester.tap(find.text('120%'));
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);
      expect(transform.value, Matrix4.identity());

      await tester.drag(find.byType(InteractiveViewer), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.drag(find.byType(InteractiveViewer), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.drag(find.byType(InteractiveViewer), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.drag(
        find.byType(InteractiveViewer),
        const Offset(-600, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.drag(
        find.byType(InteractiveViewer),
        const Offset(600, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      final slowDrag = await tester.startGesture(
        tester.getCenter(find.byType(InteractiveViewer)),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 12; i++) {
        await slowDrag.moveBy(const Offset(-50, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await slowDrag.up();
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      final click = await tester.startGesture(
        tester.getCenter(find.byType(InteractiveViewer)),
        kind: PointerDeviceKind.mouse,
      );
      await click.up();
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
      expect(find.text('图库'), findsOneWidget);
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
      expect(find.text('图库'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );
}

class _LoadedRepository extends GalleryRepository {
  _LoadedRepository(Directory root, this.items) : super(root: root);
  final List<GalleryItem> items;
  @override
  Future<List<GalleryItem>> load() async => items;
}
