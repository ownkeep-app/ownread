import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../../core/storage/gallery_repository.dart';
import '../../../core/widgets/privacy_guard.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.repository});
  final GalleryRepository repository;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<GalleryItem> _items = [];
  GalleryKind? _filter;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _reload() async {
    try {
      final items = await widget.repository.load();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '读取图库失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(GalleryKind kind) async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: kind == GalleryKind.image
            ? GalleryRepository.imageExtensions
            : GalleryRepository.videoExtensions,
        allowMultiple: true,
        withData: false,
      );
      if (result == null) return;
      var added = 0;
      var failed = 0;
      for (final file in result.files) {
        try {
          if (file.path == null ||
              GalleryRepository.kindFor(file.name) != kind) {
            throw const FormatException('无法读取文件');
          }
          await widget.repository.add(File(file.path!), name: file.name);
          added++;
        } catch (_) {
          failed++;
        }
      }
      _message('已保存 $added 个文件${failed == 0 ? '' : '，$failed 个文件失败'}');
    } catch (e) {
      _message('添加失败：$e');
    } finally {
      await _reload();
    }
  }

  Future<void> _export(GalleryItem item) async {
    setState(() => _busy = true);
    try {
      final bytes = Uint8List.fromList(
        await widget.repository.exportImage(item),
      );
      final ext = p.extension(item.name).substring(1).toLowerCase();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出图片',
        fileName: item.name,
        type: FileType.custom,
        allowedExtensions: [ext],
        bytes: Platform.isAndroid ? bytes : null,
      );
      if (path == null) return;
      if (!Platform.isAndroid) {
        await File(
          p.extension(path).isEmpty ? '$path.$ext' : path,
        ).writeAsBytes(bytes, flush: true);
      }
      _message('已导出图片');
    } catch (e) {
      _message('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportZip() async {
    setState(() => _busy = true);
    Directory? temp;
    try {
      temp = await Directory.systemTemp.createTemp('ownread-images-');
      final zip = File(p.join(temp.path, 'images.zip'));
      final count = await widget.repository.exportImagesZip(zip);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出全部图片 ZIP',
        fileName:
            'ownread-images-${DateTime.now().toIso8601String().split('T').first}.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: Platform.isAndroid ? await zip.readAsBytes() : null,
      );
      if (path == null) return;
      if (!Platform.isAndroid) {
        await zip.copy(
          path.toLowerCase().endsWith('.zip') ? path : '$path.zip',
        );
      }
      _message('已导出 $count 张图片');
    } catch (e) {
      _message('导出失败：$e');
    } finally {
      if (temp != null) await temp.delete(recursive: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importZip() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty || !mounted) return;
      final path = picked.files.single.path;
      if (path == null) throw const FormatException('无法读取 ZIP 文件');
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入图片 ZIP'),
          content: const Text(
            '追加会保留现有图片；替换会删除全部现有图片，再导入 ZIP 中的图片。视频不参与导入，也不会被删除。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('追加图片'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('替换全部图片'),
            ),
          ],
        ),
      );
      if (replace == null) return;
      final count = await widget.repository.importImagesZip(
        File(path),
        replace: replace,
      );
      _message('已${replace ? '替换并导入' : '追加'} $count 张图片');
    } catch (e) {
      _message('导入失败：$e');
    } finally {
      await _reload();
    }
  }

  Future<void> _delete(GalleryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定从图库删除「${item.name}」？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.delete(item);
    } catch (e) {
      _message('删除失败：$e');
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items
        .where((item) => _filter == null || item.kind == _filter)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('图库'),
        actions: [
          IconButton(
            tooltip: '导入图片',
            onPressed: _busy ? null : () => _add(GalleryKind.image),
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            tooltip: '存入视频',
            onPressed: _busy ? null : () => _add(GalleryKind.video),
            icon: const Icon(Icons.video_library_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            enabled: !_busy,
            icon: const Icon(Icons.more_horiz),
            onSelected: (action) =>
                action == 'import' ? _importZip() : _exportZip(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'import', child: Text('导入图片 ZIP')),
              PopupMenuItem(
                value: 'export',
                enabled: _items.any((item) => item.kind == GalleryKind.image),
                child: const Text('导出全部图片 ZIP'),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text('本地保存 · ${_items.length} 个文件 · 仅图片可导出'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('全部'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      for (final kind in GalleryKind.values)
                        ChoiceChip(
                          label: Text(kind == GalleryKind.image ? '图片' : '视频'),
                          selected: _filter == kind,
                          onSelected: (_) => setState(() => _filter = kind),
                        ),
                    ],
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                Expanded(
                  child: _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!),
                              TextButton(
                                onPressed: _reload,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.photo_library_outlined,
                                size: 56,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _busy
                                    ? '正在读取图库…'
                                    : '暂无${_filter == GalleryKind.image
                                          ? '图片'
                                          : _filter == GalleryKind.video
                                          ? '视频'
                                          : '文件'}',
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                children: [
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _add(GalleryKind.image),
                                    child: const Text('导入图片'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _add(GalleryKind.video),
                                    child: const Text('存入视频'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 240,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.85,
                              ),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: _busy
                                          ? null
                                          : () => Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => _MediaViewer(
                                                  items: List.unmodifiable(
                                                    items,
                                                  ),
                                                  initialIndex: index,
                                                ),
                                              ),
                                            ),
                                      child: SizedBox.expand(
                                        child: item.kind == GalleryKind.image
                                            ? Image.file(
                                                item.file,
                                                fit: BoxFit.cover,
                                                cacheWidth: 480,
                                                errorBuilder: (_, _, _) =>
                                                    const Center(
                                                      child: Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        size: 40,
                                                      ),
                                                    ),
                                              )
                                            : ColoredBox(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondaryContainer,
                                                child: const Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.play_circle_outline,
                                                      size: 48,
                                                    ),
                                                    SizedBox(height: 8),
                                                    Text('视频'),
                                                  ],
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        enabled: !_busy,
                                        tooltip: '文件操作',
                                        onSelected: (action) =>
                                            action == 'export'
                                            ? _export(item)
                                            : _delete(item),
                                        itemBuilder: (_) => [
                                          if (item.kind == GalleryKind.image)
                                            const PopupMenuItem(
                                              value: 'export',
                                              child: Text('导出图片'),
                                            ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('删除'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaViewer extends StatefulWidget {
  const _MediaViewer({required this.items, required this.initialIndex});
  final List<GalleryItem> items;
  final int initialIndex;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  final _transforms = <String, TransformationController>{};
  TransformationController _transformFor(GalleryItem item) =>
      _transforms.putIfAbsent(item.file.path, TransformationController.new);

  @override
  void dispose() {
    _pages.dispose();
    for (final controller in _transforms.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          Flexible(
            child: Text(
              widget.items[_index].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.items[_index].kind == GalleryKind.image) ...[
            const SizedBox(width: 8),
            ValueListenableBuilder<Matrix4>(
              valueListenable: _transformFor(widget.items[_index]),
              builder: (context, matrix, _) => TextButton(
                onPressed: () => _transformFor(widget.items[_index]).value =
                    Matrix4.identity(),
                child: Tooltip(
                  message: '恢复 100%，继续左右切换',
                  child: Text('${(matrix.getMaxScaleOnAxis() * 100).round()}%'),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        Center(child: Text('${_index + 1} / ${widget.items.length}')),
        const SizedBox(width: 16),
      ],
    ),
    body: PageView.builder(
      scrollBehavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      ),
      controller: _pages,
      physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
      onPageChanged: (index) => setState(() {
        _index = index;
        _zoomed =
            _transformFor(widget.items[index]).value.getMaxScaleOnAxis() > 1.01;
      }),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        // Only the visible page owns a player. Leaving a video disposes it,
        // including when initialization is still in flight.
        if (index == _index || item.kind == GalleryKind.image) {
          return _MediaPage(
            key: ValueKey(item.file.path),
            item: item,
            pages: _pages,
            transform: _transformFor(item),
            onZoomChanged: (zoomed) {
              if (mounted && index == _index) setState(() => _zoomed = zoomed);
            },
          );
        }
        return Center(
          child: item.kind == GalleryKind.image
              ? Image.file(
                  item.file,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                )
              : const Icon(Icons.play_circle_outline, size: 64),
        );
      },
    ),
  );
}

class _MediaPage extends StatefulWidget {
  const _MediaPage({
    super.key,
    required this.item,
    required this.onZoomChanged,
    required this.pages,
    required this.transform,
  });
  final TransformationController transform;
  final PageController pages;
  final ValueChanged<bool> onZoomChanged;
  final GalleryItem item;
  @override
  State<_MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<_MediaPage> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  String? _error;
  TransformationController get _transform => widget.transform;
  bool _zoomed = false;
  Drag? _mouseDrag;

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    WidgetsBinding.instance.addObserver(this);
    if (widget.item.kind == GalleryKind.video) _initialize();
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.file(widget.item.file);
    _video = controller;
    try {
      await controller.initialize();
    } catch (error, stack) {
      debugPrint('Video initialization failed: $error\n$stack');
      if (mounted) {
        _error =
            error is MissingPluginException ||
                (error is PlatformException && error.code == 'channel-error')
            ? '视频播放组件未加载。请完全退出应用，再打开重新构建的版本（热重载无法加载新组件）。'
            : '无法打开视频：$error';
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PrivacyLockScope.isLocked(context)) _video?.pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _video?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mouseDrag?.cancel();
    _transform.removeListener(_onTransform);
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return SafeArea(
      child: Center(
        child: widget.item.kind == GalleryKind.image
            ? InteractiveViewer(
                transformationController: _transform,
                panEnabled: _zoomed,
                minScale: 1,
                maxScale: 5,
                child: GestureDetector(
                  // The image's scale recognizer otherwise wins mouse drags
                  // before PageView. Forward unzoomed drags to its scroll activity.
                  supportedDevices: const {PointerDeviceKind.mouse},
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: _zoomed
                      ? null
                      : (details) {
                          _mouseDrag = widget.pages.position.drag(
                            details,
                            () => _mouseDrag = null,
                          );
                        },
                  onHorizontalDragUpdate: _zoomed
                      ? null
                      : (details) => _mouseDrag?.update(details),
                  onHorizontalDragEnd: _zoomed
                      ? null
                      : (details) => _mouseDrag?.end(details),
                  onHorizontalDragCancel: _zoomed
                      ? null
                      : () => _mouseDrag?.cancel(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox.expand(
                      child: Image.file(
                        widget.item.file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Text('无法打开此图片，文件可能已损坏。')),
                      ),
                    ),
                  ),
                ),
              )
            : _error != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
            : video == null
            ? const CircularProgressIndicator()
            : ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: video,
                builder: (context, value, _) {
                  if (value.hasError) {
                    return const Text('播放失败：设备不支持此视频或文件已损坏。');
                  }
                  if (!value.isInitialized) {
                    return const CircularProgressIndicator();
                  }
                  return Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: value.aspectRatio > 0
                                ? value.aspectRatio
                                : 16 / 9,
                            child: VideoPlayer(video),
                          ),
                        ),
                      ),
                      VideoProgressIndicator(
                        video,
                        allowScrubbing: true,
                        padding: const EdgeInsets.all(16),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: value.isPlaying ? '暂停' : '播放',
                            icon: Icon(
                              value.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            onPressed: () async {
                              if (value.isPlaying) {
                                await video.pause();
                              } else {
                                if (value.position >= value.duration) {
                                  await video.seekTo(Duration.zero);
                                }
                                await video.play();
                              }
                            },
                          ),
                          Text(
                            '${_time(value.position)} / ${_time(value.duration)}',
                          ),
                          IconButton(
                            tooltip: value.volume == 0 ? '取消静音' : '静音',
                            icon: Icon(
                              value.volume == 0
                                  ? Icons.volume_off
                                  : Icons.volume_up,
                            ),
                            onPressed: () =>
                                video.setVolume(value.volume == 0 ? 1 : 0),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
      ),
    );
  }

  String _time(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}
