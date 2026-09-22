import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/services/text_replace.dart';

void main() {
  group('TextReplace.replaceAll', () {
    test('replaces all occurrences', () {
      final r = TextReplace.replaceAll('18岁的他和18岁的她', '18岁', '14岁');
      expect(r.text, '14岁的他和14岁的她');
      expect(r.occurrenceCount, 2);
      expect(r.changedChars, greaterThan(0));
    });

    test('empty find is no-op', () {
      final r = TextReplace.replaceAll('abc', '', 'x');
      expect(r.occurrenceCount, 0);
      expect(r.text, 'abc');
    });

    test('identical find/replace is no-op', () {
      final r = TextReplace.replaceAll('aa', 'a', 'a');
      expect(r.occurrenceCount, 0);
    });

    test('no match', () {
      final r = TextReplace.replaceAll('hello', 'zzz', 'y');
      expect(r.occurrenceCount, 0);
      expect(r.text, 'hello');
    });
  });

  group('TextReplace.firstDiffSample', () {
    test('detects middle change', () {
      final s = TextReplace.firstDiffSample('abc草def', 'abc曹def');
      expect(s, isNotNull);
      expect(s!.from, '草');
      expect(s.to, '曹');
      expect(s.changedChars, 1);
    });

    test('null when equal', () {
      expect(TextReplace.firstDiffSample('same', 'same'), isNull);
    });
  });
}
