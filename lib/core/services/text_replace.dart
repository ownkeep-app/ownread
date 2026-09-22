import 'dart:convert';
import 'dart:math' as math;

/// Streaming-friendly find/replace helpers for large novels.
class TextReplace {
  TextReplace._();

  /// Replace all non-overlapping occurrences of [find] with [replace] in [text].
  /// Returns the new text and the number of characters changed
  /// (`|find|*count + |replace|*count` absolute magnitude used for history:
  /// we report `find.length * count` as "修改字数" when replace is shorter/longer
  /// the product asks for 共计修改文本N字 — we use max(removed, inserted) * count
  /// simplified as: sum of |len(find)-len(replace)| * count + min lengths...
  /// Spec examples count total affected chars; we use `find.length * count`
  /// when replace differs, else 0 if identical).
  static ReplaceResult replaceAll(String text, String find, String replace) {
    if (find.isEmpty) {
      return ReplaceResult(text: text, occurrenceCount: 0, changedChars: 0);
    }
    if (find == replace) {
      return ReplaceResult(text: text, occurrenceCount: 0, changedChars: 0);
    }

    final parts = text.split(find);
    final count = parts.length - 1;
    if (count <= 0) {
      return ReplaceResult(text: text, occurrenceCount: 0, changedChars: 0);
    }
    final newText = parts.join(replace);
    final per = math.max(find.length, replace.length);
    return ReplaceResult(
      text: newText,
      occurrenceCount: count,
      changedChars: per * count,
    );
  }

  /// Estimate a short before/after sample for chapter-edit history.
  static DiffSample? firstDiffSample(String before, String after, {int max = 8}) {
    if (before == after) return null;
    final minLen = math.min(before.length, after.length);
    var start = 0;
    while (start < minLen && before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }
    var endBefore = before.length;
    var endAfter = after.length;
    while (endBefore > start &&
        endAfter > start &&
        before.codeUnitAt(endBefore - 1) == after.codeUnitAt(endAfter - 1)) {
      endBefore--;
      endAfter--;
    }
    String clip(String s, int a, int b) {
      final slice = s.substring(a, b);
      if (slice.length <= max) return slice;
      return '${slice.substring(0, max)}…';
    }

    return DiffSample(
      from: clip(before, start, endBefore),
      to: clip(after, start, endAfter),
      changedChars: math.max(
        (endBefore - start).abs(),
        (endAfter - start).abs(),
      ),
    );
  }

  /// Decode UTF-8 bytes safely.
  static String decodeUtf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
}

class ReplaceResult {
  const ReplaceResult({
    required this.text,
    required this.occurrenceCount,
    required this.changedChars,
  });

  final String text;
  final int occurrenceCount;
  final int changedChars;
}

class DiffSample {
  const DiffSample({
    required this.from,
    required this.to,
    required this.changedChars,
  });

  final String from;
  final String to;
  final int changedChars;
}
