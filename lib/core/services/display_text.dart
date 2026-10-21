/// Chapter text as shown in the reader: blank (empty or whitespace-only) lines
/// and trailing whitespace are dropped, so TXT files padded with empty lines
/// between paragraphs read compactly. The stored text is never changed.
///
/// Keeps a map between display and raw offsets so a tap on the page can be
/// turned into an editor caret (raw) and back.
class DisplayText {
  DisplayText._(this.text, this._displayStarts, this._rawStarts, this._lengths);

  factory DisplayText.of(String raw) {
    final buf = StringBuffer();
    final displayStarts = <int>[];
    final rawStarts = <int>[];
    final lengths = <int>[];
    var lineStart = 0;
    while (lineStart < raw.length) {
      final nl = raw.indexOf('\n', lineStart);
      final end = nl < 0 ? raw.length : nl + 1; // include the newline
      final line = raw.substring(lineStart, nl < 0 ? raw.length : nl);
      if (line.trim().isNotEmpty) {
        displayStarts.add(buf.length);
        rawStarts.add(lineStart);
        lengths.add(end - lineStart);
        buf.write(raw.substring(lineStart, end));
      }
      lineStart = end;
    }
    var text = buf.toString();
    final trimmed = text.trimRight();
    if (trimmed.length != text.length) {
      text = trimmed;
      // Clip the last kept segment to the trimmed end.
      if (lengths.isNotEmpty) {
        lengths[lengths.length - 1] = text.length - displayStarts.last;
      }
    }
    return DisplayText._(text, displayStarts, rawStarts, lengths);
  }

  /// What the reader renders.
  final String text;

  final List<int> _displayStarts;
  final List<int> _rawStarts;
  final List<int> _lengths;

  /// Raw text offset for a position in [text].
  int toRaw(int displayOffset) {
    if (_displayStarts.isEmpty) return 0;
    final d = displayOffset.clamp(0, text.length);
    final i = _lastAtOrBefore(_displayStarts, d);
    return _rawStarts[i] + (d - _displayStarts[i]).clamp(0, _lengths[i]);
  }

  /// Position in [text] for a raw offset. Offsets inside a removed blank line
  /// map to the start of the next shown line.
  int toDisplay(int rawOffset) {
    if (_rawStarts.isEmpty) return 0;
    final r = rawOffset < 0 ? 0 : rawOffset;
    if (r < _rawStarts.first) return 0;
    final i = _lastAtOrBefore(_rawStarts, r);
    final within = r - _rawStarts[i];
    final d = within <= _lengths[i]
        ? _displayStarts[i] + within
        : (i + 1 < _displayStarts.length
            ? _displayStarts[i + 1]
            : text.length);
    return d.clamp(0, text.length);
  }

  /// Index of the last entry <= [value] (entries are ascending; value >= first).
  static int _lastAtOrBefore(List<int> starts, int value) {
    var lo = 0, hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= value) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
