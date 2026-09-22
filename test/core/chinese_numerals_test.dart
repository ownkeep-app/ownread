import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/services/chinese_numerals.dart';

void main() {
  group('ChineseNumerals.format', () {
    test('single digits and teens', () {
      expect(ChineseNumerals.format(1), '一');
      expect(ChineseNumerals.format(10), '十');
      expect(ChineseNumerals.format(15), '十五');
    });

    test('tens and hundreds', () {
      expect(ChineseNumerals.format(20), '二十');
      expect(ChineseNumerals.format(101), '一百零一');
      expect(ChineseNumerals.format(110), '一百一十');
      expect(ChineseNumerals.format(195), '一百九十五');
    });

    test('thousands', () {
      expect(ChineseNumerals.format(1000), '一千');
      expect(ChineseNumerals.format(1005), '一千零五');
      expect(ChineseNumerals.format(1228), '一千二百二十八');
    });
  });
}
