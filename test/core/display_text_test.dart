import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/services/display_text.dart';

void main() {
  test('drops empty and whitespace-only lines, trims the end', () {
    const raw = '\n　　第一段。\n\n  \n　　第二段。\r\n\t\n\n　　第三段。\n\n\n';
    final d = DisplayText.of(raw);
    expect(d.text, '　　第一段。\n　　第二段。\r\n　　第三段。');
  });

  test('text without blank lines is unchanged apart from trailing space', () {
    const raw = '甲\n乙\n丙  \n';
    expect(DisplayText.of(raw).text, '甲\n乙\n丙');
  });

  test('empty and all-blank input', () {
    expect(DisplayText.of('').text, '');
    expect(DisplayText.of('').toRaw(5), 0);
    expect(DisplayText.of('').toDisplay(5), 0);
    final blank = DisplayText.of('\n \n\n');
    expect(blank.text, '');
    expect(blank.toDisplay(2), 0);
  });

  test('offsets map both ways and land on the same characters', () {
    const raw = '\n\nAB\n\n\nCD\n\nEF';
    final d = DisplayText.of(raw);
    expect(d.text, 'AB\nCD\nEF');
    for (var i = 0; i < d.text.length; i++) {
      final r = d.toRaw(i);
      expect(raw[r], d.text[i], reason: 'display $i -> raw $r');
      expect(d.toDisplay(r), i);
    }
    // End of text.
    expect(d.toRaw(d.text.length), raw.length);
    expect(d.toDisplay(raw.length), d.text.length);
  });

  test('raw offsets inside removed lines snap to the next shown line', () {
    const raw = 'AB\n\n\nCD';
    final d = DisplayText.of(raw);
    // raw 3 and 4 are the removed blank lines; next shown line starts at 'C'.
    expect(d.toDisplay(3), d.text.indexOf('C'));
    expect(d.toDisplay(4), d.text.indexOf('C'));
    // Before the first shown line.
    expect(DisplayText.of('\n\nX').toDisplay(0), 0);
    // Out of range values clamp.
    expect(d.toRaw(-3), 0);
    expect(d.toDisplay(-3), 0);
    expect(d.toRaw(999), raw.length);
  });

  test('trailing blank lines after the last paragraph map to the end', () {
    const raw = 'AB\nCD\n\n\n';
    final d = DisplayText.of(raw);
    expect(d.text, 'AB\nCD');
    expect(d.toDisplay(raw.length), d.text.length);
    expect(d.toRaw(d.text.length), 5);
  });
}
