import '../models/chapter_index.dart';

/// Splits novel plain text into chapter bodies using Chinese/English headings
/// and common anthology story-title layouts.
class ChapterSplitter {
  ChapterSplitter._();

  /// Matches common Chinese and English chapter headings at line starts.
  /// Only horizontal whitespace before the heading (not newlines).
  static final RegExp headingPattern = RegExp(
    r'^[ \t　]*('
    r'第[零〇一二三四五六七八九十百千万两0-9０-９]+[章节回卷部集话节]'
    r'|[Cc]hapter\s+[0-9]+'
    r'|CHAPTER\s+[0-9]+'
    r')'
    r'[^\n]{0,80}$',
    multiLine: true,
  );

  /// Prefixed headings such as 「黄蓉后传第四节跟踪」.
  static final RegExp prefixedHeadingPattern = RegExp(
    r'^[ \t　]*[^\n第。！？]{0,16}'
    r'第[零〇一二三四五六七八九十百千万两0-9０-９]+[章节回卷部集话节]'
    r'[^\n]{0,40}$',
    multiLine: true,
  );

  /// Numbered titles without 「第…章」: 「一  运动型美女」「一百零四  美妇可儿  一」.
  static final RegExp numberedTitlePattern = RegExp(
    r'^[ \t　]*'
    r'(?:[零〇一二三四五六七八九十百千万两]{1,8}|[0-9]{1,4})'
    r'[ \t　]{1,8}'
    r'\S[^\n]{0,40}'
    r'$',
    multiLine: true,
  );

  static final RegExp _hasCjk = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _adLine = RegExp(
    r'书盟|下载|电子书|TXT|txt|http|www\.|\.com|\.cc',
  );

  /// Split [text] into chapter parts. If no headings are found, returns one
  /// part titled 「全文」.
  static List<SplitChapter> splitParts(String text) {
    final starts = _headingStarts(text);
    if (starts.isEmpty) {
      return [SplitChapter(title: '全文', content: text)];
    }

    final parts = <SplitChapter>[];
    if (starts.first > 0) {
      final prologue = text.substring(0, starts.first);
      if (prologue.trim().isNotEmpty) {
        parts.add(SplitChapter(title: '序章', content: prologue));
      }
    }

    for (var i = 0; i < starts.length; i++) {
      final start = starts[i];
      final end = i + 1 < starts.length ? starts[i + 1] : text.length;
      final body = text.substring(start, end);
      final titleLine = body.split('\n').first.trim();
      final title = titleLine.isEmpty
          ? '第${parts.length + 1}章'
          : _truncate(titleLine, 40);
      parts.add(SplitChapter(title: title, content: body));
    }
    return parts;
  }

  /// Build a chapter index for [parts] using zero-padded filenames.
  static ChapterIndex indexFromParts(List<SplitChapter> parts) {
    return ChapterIndex([
      for (var i = 0; i < parts.length; i++)
        ChapterIndexEntry(
          index: i,
          title: parts[i].title,
          file: fileNameForIndex(i),
          charCount: parts[i].content.length,
        ),
    ]);
  }

  static String fileNameForIndex(int index) =>
      '${index.toString().padLeft(4, '0')}.txt';

  /// Convenience: split and build index (without writing files).
  static ChapterIndex split(String text) => indexFromParts(splitParts(text));

  static ChapterIndex rebuildIndex(String text) => split(text);

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// Derive a display title from chapter body (first line).
  static String titleFromContent(String content, {String fallback = '未命名'}) {
    final line = content.split('\n').first.trim();
    if (line.isEmpty) return fallback;
    return _truncate(line, 40);
  }

  static List<int> _headingStarts(String text) {
    final starts = <int>{};

    for (final m in headingPattern.allMatches(text)) {
      if (_isFalseHeading(m.group(0)!)) continue;
      starts.add(m.start);
    }
    for (final m in prefixedHeadingPattern.allMatches(text)) {
      final line = m.group(0)!;
      if (_isFalseHeading(line)) continue;
      if (line.trim().length > 40) continue;
      starts.add(m.start);
    }
    starts.addAll(_numberedTitleStarts(text));
    starts.addAll(_anthologyTitleStarts(text));

    final list = starts.toList()..sort();
    return list;
  }

  /// 「一  运动型美女」style — common in long web novels without 第N章.
  static List<int> _numberedTitleStarts(String text) {
    final out = <int>[];
    var offset = 0;
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final lineStart = offset;

      if (_isNumberedTitleLine(line)) {
        final next = _nextNonEmpty(lines, i + 1);
        if (next != null && _looksLikeIndentedBody(next.$2)) {
          out.add(lineStart);
        }
      }

      offset += raw.length + (i < lines.length - 1 ? 1 : 0);
    }
    return out;
  }

  static bool _isNumberedTitleLine(String line) {
    if (!numberedTitlePattern.hasMatch(line)) return false;
    final s = line.trim();
    if (s.length < 3 || s.length > 48) return false;
    if (!_hasCjk.hasMatch(s)) return false;
    if (_adLine.hasMatch(s)) return false;
    if (s.contains('。') || RegExp(r'[。！？!?]$').hasMatch(s)) return false;
    // Already covered by 第N章 patterns.
    if (headingPattern.hasMatch(line) || prefixedHeadingPattern.hasMatch(line)) {
      return false;
    }
    // Require a real title after the number (not just "一").
    final rest = s.replaceFirst(
      RegExp(r'^(?:[零〇一二三四五六七八九十百千万两]{1,8}|[0-9]{1,4})[ \t　]+'),
      '',
    );
    if (rest.isEmpty || !_hasCjk.hasMatch(rest)) return false;
    return true;
  }

  /// Body with fullwidth/space indent (e.g. 「　　当第一缕阳光…」).
  static bool _looksLikeIndentedBody(String line) {
    final lead = _leadWidth(line);
    final s = line.trim();
    if (s.length < 15) return false;
    return lead >= 2;
  }

  static bool _isFalseHeading(String line) {
    final s = line.trim();
    if (_adLine.hasMatch(s)) return true;
    // 「第二节课」in dialogue, not a chapter.
    if (s.contains('节课')) return true;
    // Long prose that happens to contain 第N集.
    if (s.contains('，') && s.length > 24) return true;
    return false;
  }

  /// Anthology TXT: story titles often use 1-space indent before 4-space body,
  /// sometimes after a `/` + `，` separator.
  static List<int> _anthologyTitleStarts(String text) {
    final out = <int>[];
    var offset = 0;
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final lineStart = offset;

      final afterSep = _afterAnthologySeparator(lines, i);
      if (_isAnthologyTitle(line, afterSeparator: afterSep)) {
        final next = _nextNonEmpty(lines, i + 1);
        if (next != null && _looksLikeBody(next.$2)) {
          out.add(lineStart);
        }
      }

      offset += raw.length + (i < lines.length - 1 ? 1 : 0);
    }
    return out;
  }

  /// `/` … optional ads/blanks … `，` … optional blanks … title
  static bool _afterAnthologySeparator(List<String> lines, int titleIndex) {
    var k = titleIndex - 1;
    while (k >= 0 && lines[k].replaceAll('\r', '').trim().isEmpty) {
      k--;
    }
    if (k < 0 || !_isSepComma(lines[k])) return false;
    k--;
    while (k >= 0) {
      final t = lines[k].replaceAll('\r', '').trim();
      if (t.isEmpty || _adLine.hasMatch(t)) {
        k--;
        continue;
      }
      return _isSepSlash(lines[k]);
    }
    return false;
  }

  static bool _isSepSlash(String raw) {
    final s = raw.replaceAll('\r', '').trim();
    return s == '/' || s == '／';
  }

  static bool _isSepComma(String raw) {
    final s = raw.replaceAll('\r', '').trim();
    return s == '，' || s == ',';
  }

  static (int, String)? _nextNonEmpty(List<String> lines, int from) {
    for (var j = from; j < lines.length; j++) {
      final raw = lines[j];
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.trim().isEmpty) continue;
      return (j, line);
    }
    return null;
  }

  static bool _isAnthologyTitle(String line, {required bool afterSeparator}) {
    // Anthology titles use 1–2 ASCII spaces, not fullwidth 「　」body indent.
    if (line.isNotEmpty && line.runes.first == 0x3000) return false;
    final lead = _asciiLeadWidth(line);
    final s = line.trim();
    if (s.length < 2 || s.length > 30) return false;
    if (!_hasCjk.hasMatch(s)) return false;
    if (_adLine.hasMatch(s)) return false;
    if (_looksLikeDialogue(s)) return false;
    // Body fragments / sentences are not titles.
    if (RegExp(r'[。！？!?]$').hasMatch(s) || s.contains('。')) return false;
    if (headingPattern.hasMatch(line) ||
        prefixedHeadingPattern.hasMatch(line) ||
        numberedTitlePattern.hasMatch(line)) {
      return false;
    }
    // Primary signal for this anthology format: shallow ASCII-space indent.
    if (lead == 1 || lead == 2) return true;
    // Titles right after `/` `，` separators use the same shallow indent.
    if (afterSeparator && (lead == 1 || lead == 2)) return true;
    return false;
  }

  static bool _looksLikeBody(String line) {
    final lead = _leadWidth(line);
    final s = line.trim();
    if (s.length < 18) return false;
    // Body lines in these files are typically indented ~4 spaces.
    if (lead >= 3) return true;
    // Allow unindented prose after a title.
    return s.length >= 40;
  }

  static bool _looksLikeDialogue(String s) {
    if (RegExp(r'[「」""“”]').hasMatch(s) &&
        (s.contains('…') || s.contains('...') || s.contains('啊'))) {
      return true;
    }
    if (RegExp(r'^[「」""“”]').hasMatch(s)) return true;
    return false;
  }

  static int _asciiLeadWidth(String line) {
    var n = 0;
    for (final c in line.runes) {
      if (c == 0x20 || c == 0x09) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  static int _leadWidth(String line) {
    var n = 0;
    for (final c in line.runes) {
      if (c == 0x20 || c == 0x09 || c == 0x3000) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }
}
