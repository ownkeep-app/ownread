import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

enum GalleryKind { image, video }

class GalleryItem {
  const GalleryItem({
    required this.file,
    required this.name,
    required this.kind,
    required this.addedAt,
  });
  final File file;
  final String name;
  final GalleryKind kind;
  final DateTime addedAt;
}

/// Each committed directory contains exactly one local media file. Copy into a
/// staging directory first so interrupted additions never appear in the gallery.
class GalleryRepository {
  GalleryRepository({required this.root});
  final Directory root;
  static const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
  static const videoExtensions = ['mp4', 'mov', 'm4v', 'webm'];

  static GalleryKind kindFor(String name) {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (imageExtensions.contains(ext)) return GalleryKind.image;
    if (videoExtensions.contains(ext)) return GalleryKind.video;
    throw const FormatException('不支持此文件格式');
  }

  Future<List<GalleryItem>> load() async {
    await root.create(recursive: true);
    final items = <GalleryItem>[];
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory || p.basename(entry.path).startsWith('.')) {
        continue;
      }
      await for (final file in entry.list(followLinks: false)) {
        if (file is! File) continue;
        try {
          final stat = await file.stat();
          items.add(
            GalleryItem(
              file: file,
              name: p.basename(file.path),
              kind: kindFor(file.path),
              addedAt: stat.modified,
            ),
          );
        } on FormatException {
          /* Ignore unrelated files. */
        }
      }
    }
    items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return items;
  }

  Future<void> add(File source, {String? name}) async {
    final safeName = p.basename(name ?? source.path);
    kindFor(safeName);
    if (await source.length() == 0) throw const FormatException('文件为空');
    await root.create(recursive: true);
    final id = const Uuid().v4();
    final stage = Directory(p.join(root.path, '.$id'));
    await stage.create();
    try {
      final copy = await source.copy(p.join(stage.path, safeName));
      await copy.setLastModified(DateTime.now());
      await stage.rename(p.join(root.path, id));
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  void _checkOwned(GalleryItem item) {
    if (!p.isWithin(
      p.normalize(p.absolute(root.path)),
      p.normalize(p.absolute(item.file.path)),
    )) {
      throw ArgumentError('文件不在图库中');
    }
  }

  Future<List<int>> exportImage(GalleryItem item) async {
    _checkOwned(item);
    if (kindFor(item.file.path) != GalleryKind.image) {
      throw StateError('仅支持导出图片');
    }
    return item.file.readAsBytes();
  }

  /// Streams every image into a ZIP; unique folders preserve duplicate names.
  Future<int> exportImagesZip(File destination) async {
    final images = (await load())
        .where((item) => item.kind == GalleryKind.image)
        .toList();
    if (images.isEmpty) throw StateError('图库中没有可导出的图片');
    final encoder = ZipFileEncoder();
    encoder.create(destination.path);
    try {
      for (var i = 0; i < images.length; i++) {
        await encoder.addFile(images[i].file, 'images/$i/${images[i].name}');
      }
    } finally {
      await encoder.close();
    }
    return images.length;
  }

  /// Extract and verify all images before touching existing data. Videos and
  /// other entries are ignored. Failed commits restore the previous images.
  Future<int> importImagesZip(File source, {required bool replace}) async {
    await root.create(recursive: true);
    final stage = await Directory(
      p.join(root.path, '.import-${const Uuid().v4()}'),
    ).create();
    final staged = <Directory>[];
    final published = <Directory>[];
    final originals = <String, File>{};
    var preserveRecovery = false;
    try {
      final input = InputFileStream(source.path);
      try {
        final archive = ZipDecoder().decodeStream(input);
        var totalSize = 0;
        for (final entry in archive) {
          final name = entry.name.replaceAll('\\', '/');
          if (entry.isSymbolicLink ||
              name.startsWith('/') ||
              RegExp(r'^[a-zA-Z]:').hasMatch(name) ||
              name.split('/').contains('..')) {
            throw const FormatException('ZIP 包含不安全的文件路径');
          }
          if (!entry.isFile ||
              name.startsWith('__MACOSX/') ||
              p.posix.basename(name).startsWith('.')) {
            continue;
          }
          final ext = p.posix
              .extension(name)
              .toLowerCase()
              .replaceFirst('.', '');
          if (!imageExtensions.contains(ext)) continue;
          totalSize += entry.size;
          if (entry.size <= 0 ||
              entry.size > 256 * 1024 * 1024 ||
              totalSize > 4 * 1024 * 1024 * 1024 ||
              staged.length >= 10000) {
            throw const FormatException('图片为空或 ZIP 超出大小限制');
          }
          final dir = await Directory(
            p.join(stage.path, const Uuid().v4()),
          ).create();
          final file = File(p.join(dir.path, p.posix.basename(name)));
          final output = OutputFileStream(file.path);
          try {
            entry.writeContent(output);
          } finally {
            await output.close();
          }
          var crc = 0;
          await for (final chunk in file.openRead()) {
            crc = getCrc32(chunk, crc);
          }
          if (await file.length() != entry.size || crc != entry.crc32) {
            throw const FormatException('ZIP 中的图片数据已损坏');
          }
          entry.clear();
          staged.add(dir);
          await Future<void>.delayed(Duration.zero);
        }
      } finally {
        await input.close();
      }
      if (staged.isEmpty) throw const FormatException('ZIP 中没有支持的图片，现有图库未更改');

      try {
        if (replace) {
          final old = (await load()).where(
            (item) => item.kind == GalleryKind.image,
          );
          final backup = await Directory(
            p.join(stage.path, 'previous'),
          ).create();
          for (final item in old) {
            final saved = await item.file.rename(
              p.join(backup.path, const Uuid().v4()),
            );
            originals[item.file.path] = saved;
          }
        }
        for (final dir in staged) {
          published.add(
            await dir.rename(p.join(root.path, p.basename(dir.path))),
          );
        }
      } catch (_) {
        // Retain recovery files if rollback itself fails (e.g. disk failure).
        preserveRecovery = true;
        for (final dir in published) {
          await dir.delete(recursive: true);
        }
        for (final entry in originals.entries) {
          await entry.value.rename(entry.key);
        }
        preserveRecovery = false;
        rethrow;
      }
      return staged.length;
    } finally {
      if (!preserveRecovery && await stage.exists()) {
        await stage.delete(recursive: true);
      }
    }
  }

  Future<void> delete(GalleryItem item) async {
    _checkOwned(item);
    await item.file.delete();
    if (await item.file.parent.list().isEmpty) await item.file.parent.delete();
  }
}
