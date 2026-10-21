import 'dart:io';
import 'package:archive/archive_io.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/storage/gallery_repository.dart';

void main() {
  late Directory temp;
  late GalleryRepository repo;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ownread_gallery_test');
    repo = GalleryRepository(root: Directory('${temp.path}/gallery'));
  });
  tearDown(() async => temp.delete(recursive: true));

  test(
    'copies media, persists across reloads, and exports only images',
    () async {
      final image = await File(
        '${temp.path}/photo.PNG',
      ).writeAsBytes([1, 2, 3]);
      final video = await File('${temp.path}/clip.mp4').writeAsBytes([4, 5, 6]);
      await repo.add(image);
      await repo.add(video);
      await image.delete();
      await video.delete();
      final reloaded = GalleryRepository(root: repo.root);
      final items = await reloaded.load();
      expect(items, hasLength(2));
      final photo = items.singleWhere((i) => i.kind == GalleryKind.image);
      final clip = items.singleWhere((i) => i.kind == GalleryKind.video);
      expect(await reloaded.exportImage(photo), [1, 2, 3]);
      expect(await clip.file.readAsBytes(), [4, 5, 6]);
      await expectLater(reloaded.exportImage(clip), throwsStateError);
      await reloaded.delete(photo);
      expect(await reloaded.load(), hasLength(1));
      expect(await clip.file.exists(), isTrue);
    },
  );

  test('duplicate names do not overwrite existing files', () async {
    final file = await File('${temp.path}/photo.jpg').writeAsBytes([1]);
    await repo.add(file);
    await file.writeAsBytes([2]);
    await repo.add(file);
    final items = await repo.load();
    expect(items, hasLength(2));
    expect(items.map((i) => i.file.path).toSet(), hasLength(2));
    expect(
      await Future.wait(items.map((i) => i.file.readAsBytes())),
      containsAll([
        [1],
        [2],
      ]),
    );
  });

  test(
    'rejects unsupported and empty files without publishing entries',
    () async {
      final unsupported = await File(
        '${temp.path}/file.txt',
      ).writeAsString('text');
      await expectLater(repo.add(unsupported), throwsFormatException);
      final empty = await File('${temp.path}/empty.png').create();
      await expectLater(repo.add(empty), throwsFormatException);
      expect(await repo.load(), isEmpty);
    },
  );

  test(
    'ignores interrupted copies and does not delete outside gallery',
    () async {
      final staging = await Directory(
        '${repo.root.path}/.staging',
      ).create(recursive: true);
      await File('${staging.path}/photo.jpg').writeAsBytes([1]);
      expect(await repo.load(), isEmpty);
      final outside = await File('${temp.path}/outside.jpg').writeAsBytes([2]);
      final item = GalleryItem(
        file: outside,
        name: 'outside.jpg',
        kind: GalleryKind.image,
        addedAt: DateTime.now(),
      );
      await expectLater(repo.delete(item), throwsArgumentError);
      await expectLater(repo.exportImage(item), throwsArgumentError);
      expect(await outside.exists(), isTrue);
    },
  );
  test(
    'ZIP round trip preserves duplicate names, append and replace exclude videos',
    () async {
      final photo = await File(
        '${temp.path}/photo.png',
      ).writeAsBytes([1, 2, 3]);
      final video = await File('${temp.path}/video.mp4').writeAsBytes([4, 5]);
      await repo.add(photo);
      await repo.add(photo);
      await repo.add(video);
      final zip = File('${temp.path}/images.zip');
      expect(await repo.exportImagesZip(zip), 2);
      final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
      expect(archive.files, hasLength(2));
      expect(archive.files.every((e) => e.name.endsWith('/photo.png')), isTrue);
      expect(await repo.importImagesZip(zip, replace: false), 2);
      expect(await repo.load(), hasLength(5));
      expect(await repo.importImagesZip(zip, replace: true), 2);
      final items = await repo.load();
      expect(items.where((e) => e.kind == GalleryKind.image), hasLength(2));
      expect(
        await items
            .singleWhere((e) => e.kind == GalleryKind.video)
            .file
            .readAsBytes(),
        [4, 5],
      );
    },
  );

  test(
    'ZIP imports images in folders and skips videos and unrelated files',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('folder/photo.PNG', [1, 2]))
        ..addFile(ArchiveFile.bytes('movie.mp4', [3]))
        ..addFile(ArchiveFile.string('notes.txt', 'hello'));
      final zip = await File(
        '${temp.path}/mixed.zip',
      ).writeAsBytes(ZipEncoder().encodeBytes(archive));
      expect(await repo.importImagesZip(zip, replace: false), 1);
      final items = await repo.load();
      expect(items.single.name, 'photo.PNG');
      expect(await items.single.file.readAsBytes(), [1, 2]);
    },
  );

  test('invalid and image-free ZIPs never clear existing images', () async {
    final photo = await File('${temp.path}/photo.png').writeAsBytes([1]);
    await repo.add(photo);
    for (final entry in [
      ArchiveFile.bytes('movie.mp4', [3]),
      ArchiveFile.bytes('../escape.png', [3]),
      ArchiveFile.bytes('empty.png', []),
    ]) {
      final zip = await File(
        '${temp.path}/invalid.zip',
      ).writeAsBytes(ZipEncoder().encodeBytes(Archive()..addFile(entry)));
      await expectLater(
        repo.importImagesZip(zip, replace: true),
        throwsA(isA<FormatException>()),
      );
      expect(await repo.load(), hasLength(1));
    }
    final broken = await File(
      '${temp.path}/broken.zip',
    ).writeAsBytes([1, 2, 3]);
    await expectLater(
      repo.importImagesZip(broken, replace: true),
      throwsA(anything),
    );
    expect(await repo.load(), hasLength(1));
  });
}
