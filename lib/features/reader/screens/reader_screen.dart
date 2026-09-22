import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/chapter_index.dart';
import '../../../core/models/novel_meta.dart';
import '../../../core/models/reading_settings.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/storage/novel_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/find_replace_dialog.dart';
import '../widgets/reader_chrome.dart';

/// Infinite-scroll chapter reader with lazy load + prev/next prefetch.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.novelId,
    required this.repository,
    required this.settings,
  });

  final String novelId;
  final NovelRepository repository;
  final AppSettings settings;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _scroll = ScrollController();
  final _chapterCache = <int, String>{};
  final _loading = <int>{};

  NovelMeta? _meta;
  ChapterIndex _index = const ChapterIndex([]);
  ReadingSettings _reading = const ReadingSettings();

  bool _chromeVisible = false;
  bool _editing = false;
  int? _editingChapter;
  final _editController = TextEditingController();
  final _editFocus = FocusNode();
  final _editScroll = ScrollController();
  final _editorFieldKey = GlobalKey();
  final _readerFocus = FocusNode(debugLabel: 'reader');
  Offset? _doubleTapGlobal;

  /// Window of chapter indices currently mounted in the list.
  int _windowStart = 0;
  int _windowEnd = 0;
  /// True while adjusting the window (prepend/trim); blocks re-entrant scroll logic.
  bool _windowBusy = false;
  /// Layout keys for precise jump / visible-chapter detection.
  final Map<int, GlobalKey> _chapterKeys = {};
  /// Keys on chapter body [Text] for caret hit-testing.
  final Map<int, GlobalKey> _chapterBodyKeys = {};

  /// True while a chapter jump is in progress (blocks prepend/trim races).
  bool _jumping = false;
  /// Reader list offset captured when entering edit (Android restore fallback).
  double? _readerOffsetBeforeEdit;
  /// True while restoring scroll after leaving the editor.
  bool _restoringAfterEdit = false;
  /// Target offset for in-flight arrow-key smooth scrolling.
  double? _arrowScrollTarget;

  Timer? _progressSaveTimer;
  bool _booting = true;
  String? _error;
  int _replaceGen = 0;

  NovelRepository get repo => widget.repository;
  AppSettings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    settings.addListener(_onSettings);
    _reading = settings.reading;
    _bootstrap();
  }

  @override
  void dispose() {
    _replaceGen++;
    settings.removeListener(_onSettings);
    _progressSaveTimer?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _editController.dispose();
    _editFocus.dispose();
    _editScroll.dispose();
    _readerFocus.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (!mounted) return;
    setState(() => _reading = settings.reading);
  }

  Future<void> _bootstrap() async {
    try {
      _reading = settings.reading;

      final meta = await repo.getMeta(widget.novelId);
      if (meta == null) {
        setState(() {
          _error = '小说不存在';
          _booting = false;
        });
        return;
      }
      final index = await repo.loadIndex(widget.novelId);
      final start =
          meta.progressChapterIndex.clamp(0, mathMax0(index.length - 1));
      _meta = meta;
      _index = index;
      await _prepareWindowAt(start);
      if (!mounted) return;
      setState(() => _booting = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _readerFocus.requestFocus();
        unawaited(
          _scrollToChapterInWindow(
            start,
            fractionInChapter: meta.progressFractionInChapter,
          ),
        );
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _booting = false;
      });
    }
  }

  Future<void> _ensureChapter(int i) async {
    if (i < 0 || i >= _index.length) return;
    if (_chapterCache.containsKey(i) || _loading.contains(i)) return;
    _loading.add(i);
    try {
      final text = await repo.loadChapterByIndex(widget.novelId, i);
      if (text != null && mounted) {
        setState(() => _chapterCache[i] = text);
      }
    } finally {
      _loading.remove(i);
    }
  }

  /// Load chapters around [chapterIndex].
  ///
  /// Jump/open uses [includePrevious] = false so the list starts at the target
  /// chapter and `jumpTo(0)` is always correct (avoids landing on prev chapter).
  Future<void> _prepareWindowAt(
    int chapterIndex, {
    bool clearCache = false,
    bool includePrevious = false,
  }) async {
    final target = chapterIndex.clamp(0, mathMax0(_index.length - 1));
    final start =
        includePrevious && target > 0 ? target - 1 : target;
    final end = (target + 1).clamp(0, mathMax0(_index.length - 1));
    setState(() {
      if (clearCache) {
        _chapterCache.clear();
        _chapterKeys.clear();
        _chapterBodyKeys.clear();
      }
      _windowStart = start;
      _windowEnd = end;
      _pruneChapterKeys();
    });
    await _ensureChapter(target);
    if (start < target) await _ensureChapter(start);
    if (end > target) await _ensureChapter(end);
    // Prefetch previous for upward scroll (not mounted until prepend).
    if (!includePrevious && target > 0) {
      unawaited(_ensureChapter(target - 1));
    }
  }

  /// Scroll so [chapterIndex] is at the top. Requires it to be in the window;
  /// when the window starts at that chapter, this is simply [jumpTo](0).
  Future<void> _scrollToChapterInWindow(
    int chapterIndex, {
    double fractionInChapter = 0,
  }) async {
    final target = chapterIndex.clamp(_windowStart, _windowEnd);

    for (var attempt = 0; attempt < 16; attempt++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;

      // Fast path: target is the first mounted chapter.
      if (_windowStart == target) {
        var dest = 0.0;
        if (fractionInChapter > 0) {
          final ctx = _chapterKeys[target]?.currentContext;
          if (ctx != null && ctx.mounted) {
            final box = ctx.findRenderObject() as RenderBox?;
            if (box != null && box.attached && box.hasSize) {
              dest = box.size.height * fractionInChapter.clamp(0.0, 0.95);
            }
          } else if (attempt < 15) {
            continue;
          }
        }
        _scroll.jumpTo(
          dest.clamp(0.0, _scroll.position.maxScrollExtent),
        );
        return;
      }

      // Slow path: target is below the window start — reveal by layout offset.
      final ctx = _chapterKeys[target]?.currentContext;
      if (ctx == null || !ctx.mounted) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) continue;
      var dest = viewport.getOffsetToReveal(box, 0.0).offset;
      if (fractionInChapter > 0) {
        dest += box.size.height * fractionInChapter.clamp(0.0, 0.95);
      }
      _scroll.jumpTo(
        dest.clamp(0.0, _scroll.position.maxScrollExtent),
      );
      return;
    }
  }

  /// Jump/open helper. Does not mount the previous chapter in the list.
  Future<void> _openWindowAt(
    int chapterIndex, {
    double fractionInChapter = 0,
    bool clearCache = false,
  }) async {
    await _prepareWindowAt(
      chapterIndex,
      clearCache: clearCache,
      includePrevious: false,
    );
    await _scrollToChapterInWindow(
      chapterIndex,
      fractionInChapter: fractionInChapter,
    );
  }

  GlobalKey _keyFor(int chapterIndex) =>
      _chapterKeys.putIfAbsent(chapterIndex, GlobalKey.new);

  GlobalKey _bodyKeyFor(int chapterIndex) =>
      _chapterBodyKeys.putIfAbsent(chapterIndex, GlobalKey.new);

  void _pruneChapterKeys() {
    _chapterKeys.removeWhere(
      (i, _) => i < _windowStart || i > _windowEnd,
    );
    _chapterBodyKeys.removeWhere(
      (i, _) => i < _windowStart || i > _windowEnd,
    );
  }

  /// One blank line between chapters (matches body line box).
  double get _chapterGap => _reading.fontSize * _reading.lineHeight;

  /// Body text as shown in the reader (no trailing blank lines).
  String _displayBody(String text) => text.trimRight();

  void _onScroll() {
    if (!_scroll.hasClients ||
        _index.length == 0 ||
        _windowBusy ||
        _jumping ||
        _editing ||
        _restoringAfterEdit) {
      return;
    }
    final pos = _scroll.position;

    // Near bottom → append next chapters.
    if (pos.extentAfter < 1200) {
      final next = _windowEnd + 1;
      if (next < _index.length) {
        setState(() => _windowEnd = next);
        unawaited(_ensureChapter(next));
        if (next + 1 < _index.length) unawaited(_ensureChapter(next + 1));
      }
    }

    // Near top → prepend previous chapter.
    if (pos.extentBefore < 1200 && _windowStart > 0) {
      unawaited(_prependPreviousChapter());
    }

    final span = _windowEnd - _windowStart;
    // Only trim the far side relative to where the user is reading.
    if (span > 6) {
      // Reading near the bottom of the window → drop chapters above.
      if (pos.extentAfter < 1000 && pos.extentBefore > 3500) {
        unawaited(_trimLeadingChapter());
      }
      // Reading near the top of the window → drop chapters below.
      if (pos.extentBefore < 1000 && pos.extentAfter > 3500) {
        _trimTrailingChapter();
      }
    }

    _scheduleProgressSave();
  }

  Future<void> _prependPreviousChapter() async {
    if (_windowBusy || !_scroll.hasClients) return;
    final prev = _windowStart - 1;
    if (prev < 0) return;
    _windowBusy = true;
    try {
      await _ensureChapter(prev);
      if (!mounted || !_scroll.hasClients) return;
      if (_windowStart != prev + 1) return;

      final beforeMax = _scroll.position.maxScrollExtent;
      final oldPixels = _scroll.position.pixels;

      setState(() => _windowStart = prev);
      _pruneChapterKeys();
      if (prev > 0) unawaited(_ensureChapter(prev - 1));

      await SchedulerBinding.instance.endOfFrame;
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;

      final afterMax = _scroll.position.maxScrollExtent;
      final inserted = (afterMax - beforeMax).clamp(0.0, double.infinity);
      _scroll.jumpTo((oldPixels + inserted).clamp(0.0, afterMax));
    } finally {
      _windowBusy = false;
    }
    // Keep prepending while still near the top (e.g. short chapters).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _windowBusy) return;
      if (_scroll.position.extentBefore < 1200 && _windowStart > 0) {
        unawaited(_prependPreviousChapter());
      }
    });
  }

  Future<void> _trimLeadingChapter() async {
    if (_windowBusy || !_scroll.hasClients) return;
    if (_windowEnd - _windowStart <= 6) return;
    final drop = _windowStart;
    if (drop >= _windowEnd - 3) return;

    _windowBusy = true;
    try {
      final beforeMax = _scroll.position.maxScrollExtent;
      final oldPixels = _scroll.position.pixels;
      setState(() {
        _windowStart = drop + 1;
        _chapterCache.remove(drop);
        _chapterKeys.remove(drop);
        _chapterBodyKeys.remove(drop);
        _pruneChapterKeys();
      });
      await SchedulerBinding.instance.endOfFrame;
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      final afterMax = _scroll.position.maxScrollExtent;
      final removed = (beforeMax - afterMax).clamp(0.0, double.infinity);
      _scroll.jumpTo((oldPixels - removed).clamp(0.0, afterMax));
    } finally {
      _windowBusy = false;
    }
  }

  void _trimTrailingChapter() {
    if (_windowBusy || !_scroll.hasClients) return;
    if (_windowEnd - _windowStart <= 6) return;
    final drop = _windowEnd;
    if (drop <= _windowStart + 3) return;
    setState(() {
      _windowEnd = drop - 1;
      _chapterCache.remove(drop);
      _chapterKeys.remove(drop);
      _chapterBodyKeys.remove(drop);
      _pruneChapterKeys();
    });
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted || !_scroll.hasClients || _meta == null) return;
      final chapter = _estimateVisibleChapter();
      final frac = _fractionInVisibleChapter(chapter);
      await repo.updateProgress(
        id: widget.novelId,
        chapterIndex: chapter,
        fractionInChapter: frac,
      );
    });
  }

  /// Chapter whose body currently covers a probe near the top of the viewport.
  int _estimateVisibleChapter() {
    if (_windowEnd < _windowStart) return 0;
    if (_chapterKeys.isEmpty) return _windowStart;

    final probeY = MediaQuery.paddingOf(context).top + 96;
    int? containing;
    int? nearest;
    var nearestDist = double.infinity;

    for (var i = _windowStart; i <= _windowEnd; i++) {
      final ctx = _chapterKeys[i]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (probeY >= top && probeY < bottom) {
        containing = i;
        break;
      }
      final mid = (top + bottom) / 2;
      final dist = (probeY - mid).abs();
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = i;
      }
    }
    return containing ?? nearest ?? _windowStart;
  }

  double _fractionInVisibleChapter(int chapterIndex) {
    final ctx = _chapterKeys[chapterIndex]?.currentContext;
    if (ctx == null) return 0;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize || box.size.height <= 0) {
      return 0;
    }
    final top = box.localToGlobal(Offset.zero).dy;
    final probeY = MediaQuery.paddingOf(context).top + 96;
    return ((probeY - top) / box.size.height).clamp(0.0, 1.0);
  }

  void _toggleChrome() {
    if (_editing) return;
    setState(() => _chromeVisible = !_chromeVisible);
    if (!_chromeVisible) {
      _readerFocus.requestFocus();
    }
  }

  /// Arrow-key nudge with eased animation; held keys accumulate the target.
  void _nudgeReaderScroll(int direction) {
    if (_editing || _chromeVisible || !_scroll.hasClients) return;
    final line = _reading.fontSize * _reading.lineHeight;
    final step = (line * 2.5).clamp(48.0, 120.0);
    final from = _arrowScrollTarget ?? _scroll.offset;
    final next = (from + direction * step).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((next - _scroll.offset).abs() < 0.5 &&
        (_arrowScrollTarget == null ||
            (_arrowScrollTarget! - next).abs() < 0.5)) {
      return;
    }
    _arrowScrollTarget = next;
    // animateTo cancels any previous arrow animation and eases to the new target.
    unawaited(
      _scroll
          .animateTo(
            next,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
        if (_arrowScrollTarget == next) {
          _arrowScrollTarget = null;
        }
      }),
    );
  }

  void _enterEdit(int chapterIndex) {
    final text = _chapterCache[chapterIndex];
    if (text == null) return;
    final caret = _caretOffsetForTap(text, chapterIndex);
    _readerOffsetBeforeEdit =
        _scroll.hasClients ? _scroll.offset : _readerOffsetBeforeEdit;
    setState(() {
      _editing = true;
      _editingChapter = chapterIndex;
      _chromeVisible = false;
      _editController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editFocus.requestFocus();
      unawaited(_scrollEditToMatchTapY(caret));
    });
  }

  /// Map double-tap into a character offset using the laid-out body paragraph.
  int _caretOffsetForTap(String text, int chapterIndex) {
    final display = _displayBody(text);
    if (display.isEmpty) return 0;

    final global = _doubleTapGlobal;
    final ctx = _chapterBodyKeys[chapterIndex]?.currentContext;
    if (global != null && ctx != null && ctx.mounted) {
      final ro = ctx.findRenderObject();
      if (ro is RenderParagraph) {
        final local = ro.globalToLocal(global);
        return ro
            .getPositionForOffset(local)
            .offset
            .clamp(0, display.length)
            .clamp(0, text.length);
      }
      if (ro is RenderBox && ro.hasSize) {
        final local = ro.globalToLocal(global);
        final tp = _bodyPainter(display, maxWidth: ro.size.width);
        return tp
            .getPositionForOffset(local)
            .offset
            .clamp(0, display.length)
            .clamp(0, text.length);
      }
    }
    return 0;
  }

  TextPainter _bodyPainter(String text, {required double maxWidth}) {
    return TextPainter(
      text: TextSpan(text: text, style: _bodyStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
  }

  RenderEditable? _findRenderEditable() {
    final ro = _editorFieldKey.currentContext?.findRenderObject();
    if (ro == null) return null;
    RenderEditable? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderEditable) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    visit(ro);
    return found;
  }

  /// Align the editor caret to the same screen Y as the double-tap.
  ///
  /// Uses [RenderEditable] metrics (not TextPainter estimates). Near the end
  /// of a chapter, scroll is clamped to [maxScrollExtent] so the caret sits as
  /// high as the viewport allows — without fake trailing blank space.
  Future<void> _scrollEditToMatchTapY(int caret) async {
    final preferY = _doubleTapGlobal?.dy;
    if (preferY == null) return;

    for (var pass = 0; pass < 4; pass++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || !_editScroll.hasClients) return;
      final editable = _findRenderEditable();
      if (editable == null || !editable.attached) continue;

      final caretLocal = editable.getLocalRectForCaret(
        TextPosition(offset: caret),
      ).topCenter;
      final caretGlobal = editable.localToGlobal(caretLocal);
      final delta = caretGlobal.dy - preferY;
      if (delta.abs() < 1.5) return;

      final next = (_editScroll.offset + delta).clamp(
        0.0,
        _editScroll.position.maxScrollExtent,
      );
      if ((next - _editScroll.offset).abs() < 0.5) return;
      _editScroll.jumpTo(next);
    }
  }

  /// After leaving the editor, put the caret line back under the same screen Y.
  Future<void> _scrollReaderToCaret(
    int chapterIndex,
    String text,
    int caret,
  ) async {
    _restoringAfterEdit = true;
    try {
      // Let the soft keyboard finish collapsing (Android viewInsets).
      for (var i = 0; i < 8; i++) {
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted) return;
        if (MediaQuery.viewInsetsOf(context).bottom < 1) break;
      }
      if (!mounted || !_scroll.hasClients) return;

      // Prefer the pre-edit offset — IndexedStack keeps the list mounted, but
      // keyboard / height changes can still nudge pixels on Android.
      final baseline = _readerOffsetBeforeEdit;
      if (baseline != null) {
        final max = _scroll.position.maxScrollExtent;
        final target = baseline.clamp(0.0, max);
        if ((_scroll.offset - target).abs() > 0.5) {
          _scroll.jumpTo(target);
          await SchedulerBinding.instance.endOfFrame;
          await SchedulerBinding.instance.endOfFrame;
        }
      }

      final preferY = _doubleTapGlobal?.dy;
      final display = _displayBody(text);
      final c = caret.clamp(0, display.length);
      final viewport = _scroll.position.viewportDimension;

      for (var pass = 0; pass < 6; pass++) {
        await SchedulerBinding.instance.endOfFrame;
        if (!mounted || !_scroll.hasClients) return;

        final ctx = _chapterBodyKeys[chapterIndex]?.currentContext;
        if (ctx == null || !ctx.mounted) continue;
        final ro = ctx.findRenderObject();
        if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;

        final proto = Rect.fromLTWH(0, 0, 2, _reading.fontSize);
        final caretLocal = ro.getOffsetForCaret(TextPosition(offset: c), proto);
        final caretGlobal = ro.localToGlobal(caretLocal);
        final targetY = preferY ??
            (MediaQuery.paddingOf(context).top + viewport / 3);
        final delta = caretGlobal.dy - targetY;
        if (delta.abs() < 1.5) return;

        // Huge deltas usually mean layout is still settling — don't leap.
        if (delta.abs() > viewport * 1.5) {
          if (baseline != null) {
            _scroll.jumpTo(
              baseline.clamp(0.0, _scroll.position.maxScrollExtent),
            );
          }
          continue;
        }

        final next = (_scroll.offset + delta).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        );
        if ((next - _scroll.offset).abs() < 0.5) return;
        _scroll.jumpTo(next);
      }
    } finally {
      _restoringAfterEdit = false;
      _readerOffsetBeforeEdit = null;
    }
  }

  Future<void> _leaveEditMode() async {
    _editFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    await SchedulerBinding.instance.endOfFrame;
  }

  void _exitEditAndRestoreScroll({required bool keepEditedText}) {
    final idx = _editingChapter;
    final edited = _editController.text;
    final caret =
        _editController.selection.baseOffset.clamp(0, edited.length);
    final textForScroll = keepEditedText
        ? edited
        : (idx != null ? (_chapterCache[idx] ?? edited) : edited);
    final caretForScroll = caret.clamp(0, textForScroll.length);

    unawaited(() async {
      await _leaveEditMode();
      if (!mounted) return;
      setState(() {
        _editing = false;
        _editingChapter = null;
      });
      _readerFocus.requestFocus();
      if (idx == null) return;
      await _scrollReaderToCaret(idx, textForScroll, caretForScroll);
    }());
  }

  Future<void> _saveEdit() async {
    final idx = _editingChapter;
    if (idx == null) return;
    final newText = _editController.text;
    final caret =
        _editController.selection.baseOffset.clamp(0, newText.length);
    await repo.saveChapterEdit(
      id: widget.novelId,
      chapterIndex: idx,
      newChapterText: newText,
    );
    final meta = await repo.getMeta(widget.novelId);
    final index = await repo.loadIndex(widget.novelId);
    await _leaveEditMode();
    if (!mounted) return;
    setState(() {
      _meta = meta;
      _index = index;
      _chapterCache[idx] = newText;
      _editing = false;
      _editingChapter = null;
    });
    _readerFocus.requestFocus();
    await _scrollReaderToCaret(idx, newText, caret);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    }
  }

  Future<void> _jumpToChapter(int i) async {
    setState(() => _chromeVisible = false);
    _jumping = true;
    try {
      await _openWindowAt(i, clearCache: true);
      // Settle layout before allowing prepend (avoids racing jumpTo(0)).
      await SchedulerBinding.instance.endOfFrame;
      await SchedulerBinding.instance.endOfFrame;
    } finally {
      _jumping = false;
    }
    await repo.updateProgress(
      id: widget.novelId,
      chapterIndex: i,
      fractionInChapter: 0,
    );
  }

  Future<void> _openFindReplace() async {
    setState(() => _chromeVisible = false);
    final result = await showDialog<FindReplaceResult>(
      context: context,
      builder: (_) => const FindReplaceDialog(),
    );
    if (result == null || result.find.isEmpty) return;

    final gen = ++_replaceGen;
    final priorityChapter = _windowStart;
    final priorityDone = Completer<ReplacePriorityResult>();

    final job = repo.replaceAllInNovel(
      id: widget.novelId,
      find: result.find,
      replace: result.replace,
      priorityChapterIndex: priorityChapter,
      onChapterUpdated: (update) {
        if (!mounted || gen != _replaceGen) return;
        setState(() {
          _index = update.index;
          _chapterCache[update.chapterIndex] = update.text;
          final m = _meta;
          if (m != null) {
            _meta = m.copyWith(totalChars: update.index.totalChars);
          }
        });
      },
      onPriorityComplete: (priority) {
        if (!priorityDone.isCompleted) priorityDone.complete(priority);
      },
    );

    // Only block UI until the chapter being read is done.
    final priority = await priorityDone.future;
    if (!mounted || gen != _replaceGen) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          priority.hadMatch
              ? '当前章已替换，其余章节后台处理中…'
              : '当前章无匹配，正在搜索其余章节…',
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    final entry = await job;
    if (!mounted || gen != _replaceGen) return;
    final meta = await repo.getMeta(widget.novelId);
    if (!mounted || gen != _replaceGen) return;
    setState(() => _meta = meta);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          entry == null ? '未找到匹配' : '已全部替换，修改 ${entry.changedChars} 字',
        ),
      ),
    );
  }

  TextStyle _bodyStyle(BuildContext context) {
    final fg = ShadTheme.of(context).colorScheme.foreground;
    return TextStyle(
      fontFamily: ReadingSettings.fontFamily,
      fontFamilyFallback: ReadingSettings.fontFamilyFallbacks,
      fontSize: _reading.fontSize,
      height: _reading.lineHeight,
      color: fg,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;

    if (_booting) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(title: const Text('阅读')),
        body: Center(child: Text(_error!)),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      // Never resize the body for the IME — otherwise Android rewrites the
      // (still-mounted) reader ListView's ScrollPosition when the keyboard
      // opens/closes around edit → save.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Keep the chapter list mounted while editing so Android does not
          // detach ScrollPosition / reset offset when swapping to the editor.
          IndexedStack(
            index: _editing ? 1 : 0,
            sizing: StackFit.expand,
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _nudgeReaderScroll(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _nudgeReaderScroll(-1),
                },
                child: Focus(
                  focusNode: _readerFocus,
                  autofocus: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _readerFocus.requestFocus();
                      _toggleChrome();
                    },
                    onDoubleTapDown: (d) => _doubleTapGlobal = d.globalPosition,
                    onDoubleTap: () {
                      if (_editing) return;
                      final ch = _estimateVisibleChapter();
                      _enterEdit(ch);
                    },
                    child: _buildReaderList(),
                  ),
                ),
              ),
              _buildEditor(),
            ],
          ),
          if (_chromeVisible && !_editing)
            ReaderChrome(
              title: _meta?.title ?? '',
              chapters: _index,
              currentIndex: _estimateVisibleChapter(),
              onBack: () => Navigator.of(context).maybePop(),
              onFindReplace: _openFindReplace,
              onJumpChapter: _jumpToChapter,
              onDismiss: () {
                setState(() => _chromeVisible = false);
                _readerFocus.requestFocus();
              },
            ),
          if (_editing)
            Positioned(
              right: 20,
              bottom: 28 + MediaQuery.viewInsetsOf(context).bottom,
              child: FloatingActionButton.extended(
                onPressed: _saveEdit,
                icon: const Icon(LucideIcons.save, size: 18),
                label: const Text('保存'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReaderList() {
    final style = _bodyStyle(context);
    final items = <int>[
      for (var i = _windowStart; i <= _windowEnd && i < _index.length; i++) i,
    ];
    // Eagerly build all chapters in the sliding window (usually ≤8).
    // ListView.builder would skip off-screen keys and break jump-to-chapter.
    return NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        // Pulling past the top → load earlier chapters even when scroll offset
        // cannot decrease further (common after jump-to-chapter).
        if (n.overscroll < 0 &&
            n.metrics.pixels <= n.metrics.minScrollExtent + 0.5 &&
            _windowStart > 0 &&
            !_windowBusy &&
            !_jumping) {
          unawaited(_prependPreviousChapter());
        }
        return false;
      },
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          18,
          MediaQuery.paddingOf(context).top + 12,
          18,
          48,
        ),
        children: [
          for (var i = 0; i < items.length; i++)
            _buildChapterBlock(
              chapterIndex: items[i],
              isFirst: i == 0,
              style: style,
            ),
        ],
      ),
    );
  }

  Widget _buildChapterBlock({
    required int chapterIndex,
    required bool isFirst,
    required TextStyle style,
  }) {
    final entry = _index[chapterIndex];
    final text = _chapterCache[chapterIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isFirst) SizedBox(height: _chapterGap),
        KeyedSubtree(
          key: _keyFor(chapterIndex),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry?.title ?? '第${chapterIndex + 1}章',
                style: style.copyWith(
                  fontSize: _reading.fontSize + 4,
                  fontWeight: FontWeight.w700,
                  color: OwnReadColors.orange,
                ),
              ),
              SizedBox(height: _chapterGap * 0.5),
              if (text == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Text(
                  _displayBody(text),
                  key: _bodyKeyFor(chapterIndex),
                  style: style,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    final cs = ShadTheme.of(context).colorScheme;
    final style = _bodyStyle(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: OwnReadColors.orange.withValues(alpha: 0.15),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () =>
                        _exitEditAndRestoreScroll(keepEditedText: false),
                    child: Text('取消', style: TextStyle(color: cs.foreground)),
                  ),
                  Expanded(
                    child: Text(
                      '编辑 · ${_index[_editingChapter ?? 0]?.title ?? ''}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.foreground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 64),
                ],
              ),
            ),
            Expanded(
              child: TextField(
                key: _editorFieldKey,
                controller: _editController,
                focusNode: _editFocus,
                scrollController: _editScroll,
                maxLines: null,
                expands: true,
                style: style,
                cursorColor: OwnReadColors.orange,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int mathMax0(int v) => v < 0 ? 0 : v;
