import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/models/chapter_index.dart';
import '../../../core/services/chinese_numerals.dart';
import '../../../core/theme/app_theme.dart';

/// Left sidebar: back / chapter search / find-replace / chapter list.
class ReaderChrome extends StatefulWidget {
  const ReaderChrome({
    super.key,
    required this.title,
    required this.chapters,
    required this.currentIndex,
    required this.onBack,
    required this.onFindReplace,
    required this.onSettings,
    required this.onJumpChapter,
    required this.onDismiss,
  });

  final String title;
  final ChapterIndex chapters;
  final int currentIndex;
  final VoidCallback onBack;
  final VoidCallback onFindReplace;

  /// Opens the global settings dialog (theme, background, font…).
  final VoidCallback onSettings;
  final ValueChanged<int> onJumpChapter;
  final VoidCallback onDismiss;

  @override
  State<ReaderChrome> createState() => _ReaderChromeState();
}

class _ReaderChromeState extends State<ReaderChrome>
    with SingleTickerProviderStateMixin {
  final _chapterSearch = TextEditingController();
  String _query = '';
  late final AnimationController _anim;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    final curve = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(curve);
    _fade = curve;
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _chapterSearch.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _anim.reverse();
    if (mounted) widget.onDismiss();
  }

  List<_ChapterHit> get _filtered {
    final q = _query.trim();
    final all = widget.chapters.chapters;
    if (q.isEmpty) {
      return [
        for (final c in all) _ChapterHit(index: c.index, entry: c),
      ];
    }
    final asNumber = int.tryParse(q);
    return [
      for (final c in all)
        if (_matchesChapter(c, q, asNumber))
          _ChapterHit(index: c.index, entry: c),
    ];
  }

  /// Match by title substring, Arabic chapter no., or Chinese numerals
  /// (e.g. `195` → `第一百九十五章`).
  static bool _matchesChapter(
    ChapterIndexEntry c,
    String q,
    int? asNumber,
  ) {
    if (c.title.contains(q)) return true;
    if (asNumber == null || asNumber < 1) return false;

    if (RegExp('第\\s*0*$asNumber\\s*[章节回卷部集话]')
        .hasMatch(c.title)) {
      return true;
    }
    if (RegExp(
      '[Cc]hapter\\s*0*$asNumber\\b',
      caseSensitive: false,
    ).hasMatch(c.title)) {
      return true;
    }

    final cn = ChineseNumerals.format(asNumber);
    if (RegExp('第\\s*$cn\\s*[章节回卷部集话]').hasMatch(c.title)) {
      return true;
    }
    // Loose fallback: title contains the Chinese numeral sequence.
    if (c.title.contains(cn)) return true;

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shad = ShadTheme.of(context);
    final cs = shad.colorScheme;
    final dark = shad.brightness == Brightness.dark;
    // Keep a stable, moderate panel width on phone and desktop (never nearly full-bleed).
    final sidebarWidth = (size.width * 0.78).clamp(260.0, 320.0);
    final filtered = _filtered;
    final accent = OwnReadAccent.text(context);

    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.border),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _fade,
            child: GestureDetector(
              onTap: _close,
              behavior: HitTestBehavior.opaque,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: dark ? 0.45 : 0.22),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: sidebarWidth,
          child: SlideTransition(
            position: _slide,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.card,
                border: Border(right: BorderSide(color: cs.border)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12),
                    blurRadius: 30,
                    offset: const Offset(6, 0),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: SafeArea(
                  right: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 12, 14, 4),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '返回',
                              onPressed: widget.onBack,
                              style: IconButton.styleFrom(
                                backgroundColor: cs.muted,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: Icon(
                                LucideIcons.arrowLeft,
                                size: 18,
                                color: cs.foreground,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: OwnReadType.heading(
                                      size: 16,
                                      color: cs.foreground,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '共 ${widget.chapters.length} 章',
                                    style: TextStyle(
                                      color: cs.mutedForeground,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '设置',
                              onPressed: widget.onSettings,
                              style: IconButton.styleFrom(
                                backgroundColor: cs.muted,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: Icon(
                                LucideIcons.settings,
                                size: 17,
                                color: cs.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 38,
                                child: TextField(
                                  controller: _chapterSearch,
                                  style: TextStyle(
                                    color: cs.foreground,
                                    fontSize: 13,
                                  ),
                                  cursorColor: OwnReadAccent.of(context),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    filled: true,
                                    fillColor: cs.background,
                                    hintText: '章节名 / 序号',
                                    hintStyle: TextStyle(
                                      color: cs.mutedForeground,
                                      fontSize: 13,
                                    ),
                                    prefixIcon: Icon(
                                      LucideIcons.search,
                                      size: 15,
                                      color: cs.mutedForeground,
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 34,
                                      minHeight: 38,
                                    ),
                                    suffixIcon: _query.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: '清除',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            onPressed: () {
                                              _chapterSearch.clear();
                                              setState(() => _query = '');
                                            },
                                            icon: Icon(
                                              LucideIcons.x,
                                              size: 14,
                                              color: cs.mutedForeground,
                                            ),
                                          ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 10,
                                    ),
                                    border: searchBorder,
                                    enabledBorder: searchBorder,
                                    focusedBorder: searchBorder.copyWith(
                                      borderSide: BorderSide(
                                        color: OwnReadAccent.of(context),
                                      ),
                                    ),
                                  ),
                                  onChanged: (v) => setState(() => _query = v),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 38,
                              child: OutlinedButton.icon(
                                onPressed: widget.onFindReplace,
                                icon: const Icon(LucideIcons.replace, size: 14),
                                label: const Text(
                                  '查找替换',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accent,
                                  side: BorderSide(
                                    color: OwnReadAccent.of(context)
                                        .withValues(alpha: 0.4),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: const Size(0, 38),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: cs.border),
                      Expanded(
                        child: _ChapterListScroller(
                          hits: filtered,
                          currentIndex: widget.currentIndex,
                          onJumpChapter: widget.onJumpChapter,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterHit {
  const _ChapterHit({required this.index, required this.entry});
  final int index;
  final ChapterIndexEntry entry;
}

/// Chapter list that jumps the scrollbar to [currentIndex] when opened.
class _ChapterListScroller extends StatefulWidget {
  const _ChapterListScroller({
    required this.hits,
    required this.currentIndex,
    required this.onJumpChapter,
  });

  final List<_ChapterHit> hits;
  final int currentIndex;
  final ValueChanged<int> onJumpChapter;

  @override
  State<_ChapterListScroller> createState() => _ChapterListScrollerState();
}

class _ChapterListScrollerState extends State<_ChapterListScroller> {
  static const double _itemExtent = 52;

  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
  }

  @override
  void didUpdateWidget(covariant _ChapterListScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.hits.length != widget.hits.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToCurrent());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToCurrent() {
    if (!_scroll.hasClients || widget.hits.isEmpty) return;
    final listIndex =
        widget.hits.indexWhere((h) => h.index == widget.currentIndex);
    if (listIndex < 0) return;
    final viewport = _scroll.position.viewportDimension;
    final max = _scroll.position.maxScrollExtent;
    final target = (listIndex * _itemExtent) - viewport / 3;
    _scroll.jumpTo(target.clamp(0.0, max));
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    if (widget.hits.isEmpty) {
      return Center(
        child: Text(
          '无匹配章节',
          style: TextStyle(color: cs.mutedForeground, fontSize: 13),
        ),
      );
    }
    final dark = ShadTheme.of(context).brightness == Brightness.dark;
    final accent = OwnReadAccent.text(context);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
      itemExtent: _itemExtent,
      itemCount: widget.hits.length,
      itemBuilder: (_, i) {
        final hit = widget.hits[i];
        final c = hit.entry;
        final selected = hit.index == widget.currentIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: selected
                ? OwnReadAccent.of(context).withValues(alpha: dark ? 0.16 : 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => widget.onJumpChapter(hit.index),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 3,
                    height: selected ? 20 : 0,
                    margin: const EdgeInsets.only(left: 4, right: 9),
                    decoration: BoxDecoration(
                      color: OwnReadAccent.of(context),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? accent : cs.foreground,
                        fontSize: 14,
                        height: 1.35,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      '${c.charCount}',
                      style: TextStyle(
                        color: cs.mutedForeground.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
