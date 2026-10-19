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

/// Where the reader is inside a chapter, independent of scroll offsets.
typedef ReadingAnchor = ({int chapter, double fraction});

/// Infinite-scroll chapter reader.
///
/// Layout invariant (keeps the reading position stable):
/// the list is a [CustomScrollView] whose `center` sliver starts at the
/// *anchor* chapter (scroll offset 0). Later chapters are appended to the
/// forward sliver, earlier chapters to the backward sliver above the center.
/// Only chapters whose text is already loaded are ever inserted, and they are
/// only inserted at the far ends, so loading never moves what is on screen and
/// no scroll offset ever has to be compensated.
///
/// Anything that changes the height of already-inserted chapters (font
/// settings, width, replace, edit) restores position via [ReadingAnchor].
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

  /// Bumped whenever a chapter's text is replaced, so in-flight loads that
  /// read the old file are discarded.
  final _chapterRevision = <int, int>{};

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

  /// First chapter of the center (forward) sliver; sits at scroll offset 0.
  int _anchorChapter = 0;

  /// Loaded chapters mounted in the list: `[_firstLoaded, _endLoaded)`.
  int _firstLoaded = 0;
  int _endLoaded = 0;

  /// Identity of the current list layout. Changing it recreates the slivers.
  int _listGen = 0;

  /// Invalidates async work started for an older anchor.
  int _anchorToken = 0;
  bool _extendingForward = false;
  bool _extendingBackward = false;

  /// Layout keys for measuring chapters (visible-chapter detection, restore).
  final Map<int, GlobalKey> _chapterKeys = {};

  /// Keys on chapter body [Text] for caret hit-testing.
  final Map<int, GlobalKey> _chapterBodyKeys = {};

  /// Last known reading position; used to restore after a width change.
  ReadingAnchor? _lastAnchor;
  double? _lastListWidth;

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
    _anchorToken++;
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
    final next = settings.reading;
    if (next == _reading) return;
    final anchor = _captureAnchor();
    setState(() => _reading = next);
    if (anchor != null) unawaited(_restoreAnchor(anchor));
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
      await _anchorAt(start, fractionInChapter: meta.progressFractionInChapter);
      if (!mounted) return;
      if (_booting) setState(() => _booting = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _readerFocus.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _booting = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Chapter loading / list layout
  // ---------------------------------------------------------------------------

  Future<String?> _loadChapter(int i) async {
    if (i < 0 || i >= _index.length) return null;
    for (var attempt = 0; attempt < 3; attempt++) {
      final cached = _chapterCache[i];
      if (cached != null) return cached;
      final rev = _chapterRevision[i] ?? 0;
      final text = await repo.loadChapterByIndex(widget.novelId, i);
      if (text == null) return null;
      if ((_chapterRevision[i] ?? 0) != rev) continue;
      return _chapterCache.putIfAbsent(i, () => text);
    }
    return _chapterCache[i];
  }

  /// Rebuild the list with [chapterIndex] as the anchor (scroll offset 0).
  ///
  /// Used for opening the book and every jump. The anchor chapter's text is
  /// loaded before it is shown, so its layout is final on the first frame.
  Future<void> _anchorAt(
    int chapterIndex, {
    double fractionInChapter = 0,
  }) async {
    if (_index.length == 0) return;
    final target = chapterIndex.clamp(0, _index.length - 1);
    final token = ++_anchorToken;
    _extendingForward = false;
    _extendingBackward = false;

    final text = await _loadChapter(target);
    if (!mounted || token != _anchorToken) return;
    // Next chapter too, so a restored fraction near the end is not clamped.
    if (text != null && target + 1 < _index.length) {
      await _loadChapter(target + 1);
      if (!mounted || token != _anchorToken) return;
    }

    _arrowScrollTarget = null;
    setState(() {
      _booting = false;
      _listGen++;
      _anchorChapter = target;
      _firstLoaded = target;
      _endLoaded = text == null
          ? target
          : (_chapterCache.containsKey(target + 1) ? target + 2 : target + 1);
      _chapterKeys.clear();
      _chapterBodyKeys.clear();
      _chapterCache.removeWhere(
        (i, _) => i < _firstLoaded - 1 || i > _endLoaded,
      );
    });
    // Offset 0 is the anchor's top in the new layout; set it before layout.
    if (_scroll.hasClients) _scroll.jumpTo(0);

    await _revealChapter(target, fractionInChapter, token);
    if (!mounted || token != _anchorToken) return;
    _lastAnchor = (chapter: target, fraction: fractionInChapter);
    unawaited(_extendBackward());
    _scheduleExtendCheck();
  }

  /// Append the next unloaded chapter below the forward sliver.
  Future<void> _extendForward() async {
    if (_extendingForward || _endLoaded >= _index.length) return;
    final token = _anchorToken;
    final i = _endLoaded;
    _extendingForward = true;
    String? text;
    try {
      text = await _loadChapter(i);
    } finally {
      if (token == _anchorToken) _extendingForward = false;
    }
    if (!mounted || token != _anchorToken || text == null) return;
    if (_endLoaded != i) return;
    setState(() => _endLoaded = i + 1);
    _scheduleExtendCheck();
  }

  /// Prepend the previous unloaded chapter above the backward sliver.
  Future<void> _extendBackward() async {
    if (_extendingBackward || _firstLoaded <= 0) return;
    final token = _anchorToken;
    final i = _firstLoaded - 1;
    _extendingBackward = true;
    String? text;
    try {
      text = await _loadChapter(i);
    } finally {
      if (token == _anchorToken) _extendingBackward = false;
    }
    if (!mounted || token != _anchorToken || text == null) return;
    if (_firstLoaded != i + 1) return;
    setState(() => _firstLoaded = i);
    _scheduleExtendCheck();
  }

  void _scheduleExtendCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeExtend();
    });
  }

  /// Keep a couple of viewports of loaded text on both sides of the view.
  void _maybeExtend() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (!pos.hasContentDimensions || !pos.hasViewportDimension) return;
    final margin =
        (pos.viewportDimension * 2).clamp(1200.0, double.infinity);
    if (pos.extentAfter < margin) unawaited(_extendForward());
    if (pos.extentBefore < margin) unawaited(_extendBackward());
  }

  /// Called while building chapter [i]; lazy slivers only build what is near
  /// the viewport, so this is an extent-estimate-independent prefetch trigger.
  void _onChapterBuilt(int i) {
    if ((i >= _endLoaded - 2 && _endLoaded < _index.length) ||
        (i <= _firstLoaded + 1 && _firstLoaded > 0)) {
      _scheduleExtendCheckFromBuild(i);
    }
  }

  void _scheduleExtendCheckFromBuild(int i) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (i >= _endLoaded - 2) unawaited(_extendForward());
      if (i <= _firstLoaded + 1) unawaited(_extendBackward());
    });
  }

  GlobalKey _keyFor(int chapterIndex) =>
      _chapterKeys.putIfAbsent(chapterIndex, GlobalKey.new);

  GlobalKey _bodyKeyFor(int chapterIndex) =>
      _chapterBodyKeys.putIfAbsent(chapterIndex, GlobalKey.new);

  /// One blank line between chapters (matches body line box).
  double get _chapterGap => _reading.fontSize * _reading.lineHeight;

  /// Body text as shown in the reader (no trailing blank lines).
  String _displayBody(String text) => text.trimRight();

  /// Space between the screen top and the reading viewport.
  double get _viewportTopInset => MediaQuery.paddingOf(context).top + 12;

  /// Reading line used for progress / anchors, in viewport coordinates.
  static const double _probeY = 84;

  double _clampOffset(double v) {
    final pos = _scroll.position;
    return v.clamp(pos.minScrollExtent, pos.maxScrollExtent);
  }

  void _jumpReaderTo(double offset) {
    if (!_scroll.hasClients) return;
    _arrowScrollTarget = null;
    _scroll.jumpTo(_clampOffset(offset));
  }

  // ---------------------------------------------------------------------------
  // Measuring / anchoring
  // ---------------------------------------------------------------------------

  /// Chapter block top (in viewport coordinates) and height, if laid out.
  ({double top, double height})? _measureChapter(int chapterIndex) {
    final ctx = _chapterKeys[chapterIndex]?.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    return (top: top, height: box.size.height);
  }

  /// Put [fraction] of [chapterIndex] under the reading line (fraction 0 puts
  /// the chapter title at the top of the viewport).
  Future<void> _revealChapter(
    int chapterIndex,
    double fraction,
    int token,
  ) async {
    final f = fraction.clamp(0.0, 0.98);
    for (var attempt = 0; attempt < 12; attempt++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || token != _anchorToken) return;
      if (!_scroll.hasClients) continue;
      final m = _measureChapter(chapterIndex);
      if (m == null) continue;
      final desiredTop = f <= 0 ? 0.0 : _probeY - m.height * f;
      final delta = m.top - desiredTop;
      if (delta.abs() < 0.5) return;
      final before = _scroll.offset;
      _jumpReaderTo(before + delta);
      if ((_scroll.offset - before).abs() < 0.5) return;
    }
  }

  ReadingAnchor? _captureAnchor() {
    if (!_scroll.hasClients || _booting) return null;
    final chapter = _estimateVisibleChapter();
    final m = _measureChapter(chapter);
    if (m == null || m.height <= 0) return null;
    return (
      chapter: chapter,
      fraction: ((_probeY - m.top) / m.height).clamp(0.0, 1.0),
    );
  }

  /// After chapter heights changed, put [anchor] back under the reading line.
  Future<void> _restoreAnchor(ReadingAnchor anchor) async {
    final token = _anchorToken;
    for (var attempt = 0; attempt < 6; attempt++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || token != _anchorToken || !_scroll.hasClients) return;
      final m = _measureChapter(anchor.chapter);
      if (m == null) return;
      final delta = m.top + m.height * anchor.fraction - _probeY;
      if (delta.abs() < 0.5) break;
      final before = _scroll.offset;
      _jumpReaderTo(before + delta);
      if ((_scroll.offset - before).abs() < 0.5) break;
    }
    if (mounted && token == _anchorToken) _lastAnchor = anchor;
  }

  void _onScroll() {
    if (!_scroll.hasClients || _index.length == 0 || _editing) return;
    _maybeExtend();
    if (_restoringAfterEdit) return;
    _lastAnchor = _captureAnchor() ?? _lastAnchor;
    _scheduleProgressSave();
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted || !_scroll.hasClients || _meta == null) return;
      final anchor = _captureAnchor();
      if (anchor == null) return;
      await repo.updateProgress(
        id: widget.novelId,
        chapterIndex: anchor.chapter,
        fractionInChapter: anchor.fraction,
      );
    });
  }

  /// Chapter whose block currently covers the reading line.
  int _estimateVisibleChapter() {
    if (_endLoaded <= _firstLoaded) return _anchorChapter;
    int? nearest;
    var nearestDist = double.infinity;
    for (var i = _firstLoaded; i < _endLoaded; i++) {
      final m = _measureChapter(i);
      if (m == null) continue;
      final bottom = m.top + m.height;
      if (_probeY >= m.top && _probeY < bottom) return i;
      final dist = (_probeY - (m.top + bottom) / 2).abs();
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = i;
      }
    }
    return nearest ?? _anchorChapter;
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
    final next = _clampOffset(from + direction * step);
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

  // ---------------------------------------------------------------------------
  // Editing
  // ---------------------------------------------------------------------------

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
        final target = _clampOffset(baseline);
        if ((_scroll.offset - target).abs() > 0.5) {
          _jumpReaderTo(target);
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
          if (baseline != null) _jumpReaderTo(baseline);
          continue;
        }

        final next = _clampOffset(_scroll.offset + delta);
        if ((next - _scroll.offset).abs() < 0.5) return;
        _jumpReaderTo(next);
      }
    } finally {
      _restoringAfterEdit = false;
      _readerOffsetBeforeEdit = null;
      if (mounted) _lastAnchor = _captureAnchor() ?? _lastAnchor;
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
    final chapterCountChanged = index.length != _index.length;
    setState(() {
      _meta = meta;
      _index = index;
      _chapterRevision[idx] = (_chapterRevision[idx] ?? 0) + 1;
      _chapterCache[idx] = newText;
      _editing = false;
      _editingChapter = null;
      if (chapterCountChanged) {
        // Chapter numbering shifted; cached bodies no longer line up.
        _chapterCache.removeWhere((i, _) => i != idx);
      }
    });
    _readerFocus.requestFocus();
    if (chapterCountChanged) {
      _readerOffsetBeforeEdit = null;
      await _anchorAt(idx);
    } else {
      await _scrollReaderToCaret(idx, newText, caret);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    }
  }

  Future<void> _jumpToChapter(int i) async {
    setState(() => _chromeVisible = false);
    _readerFocus.requestFocus();
    await _anchorAt(i);
    if (!mounted) return;
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
    final priorityChapter = _estimateVisibleChapter();
    final priorityDone = Completer<ReplacePriorityResult>();

    final job = repo.replaceAllInNovel(
      id: widget.novelId,
      find: result.find,
      replace: result.replace,
      priorityChapterIndex: priorityChapter,
      onChapterUpdated: (update) {
        if (!mounted || gen != _replaceGen) return;
        final i = update.chapterIndex;
        final mountedInList = i >= _firstLoaded && i < _endLoaded;
        final anchor = mountedInList ? _captureAnchor() : null;
        setState(() {
          _index = update.index;
          _chapterRevision[i] = (_chapterRevision[i] ?? 0) + 1;
          if (mountedInList || _chapterCache.containsKey(i)) {
            _chapterCache[i] = update.text;
          }
          final m = _meta;
          if (m != null) {
            _meta = m.copyWith(totalChars: update.index.totalChars);
          }
        });
        if (anchor != null) unawaited(_restoreAnchor(anchor));
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
      // (still-mounted) reader list's ScrollPosition when the keyboard
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
    final centerKey = ValueKey<String>('reader-forward-$_listGen');
    const horizontal = EdgeInsets.symmetric(horizontal: 18);
    return Padding(
      padding: EdgeInsets.only(top: _viewportTopInset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final previous = _lastListWidth;
          _lastListWidth = width;
          final anchor = _lastAnchor;
          if (previous != null &&
              (previous - width).abs() > 0.5 &&
              anchor != null) {
            // Text reflowed; keep the same passage under the reading line.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_restoreAnchor(anchor));
            });
          }
          return CustomScrollView(
            controller: _scroll,
            center: centerKey,
            slivers: [
              SliverPadding(
                key: ValueKey<String>('reader-backward-$_listGen'),
                padding: horizontal,
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, k) => _buildChapterBlock(
                      chapterIndex: _anchorChapter - 1 - k,
                      style: style,
                    ),
                    childCount: _anchorChapter - _firstLoaded,
                  ),
                ),
              ),
              SliverPadding(
                key: centerKey,
                padding: horizontal,
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, k) => _buildChapterBlock(
                      chapterIndex: _anchorChapter + k,
                      style: style,
                    ),
                    childCount: _endLoaded - _anchorChapter,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _endLoaded < _index.length
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const SizedBox(height: 48),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Title + body + trailing gap. Only called for chapters with loaded text.
  Widget _buildChapterBlock({
    required int chapterIndex,
    required TextStyle style,
  }) {
    _onChapterBuilt(chapterIndex);
    final entry = _index[chapterIndex];
    final text = _chapterCache[chapterIndex] ?? '';
    return KeyedSubtree(
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
          Text(
            _displayBody(text),
            key: _bodyKeyFor(chapterIndex),
            style: style,
          ),
          SizedBox(height: _chapterGap),
        ],
      ),
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
