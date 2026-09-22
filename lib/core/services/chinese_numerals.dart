/// Convert integers to Chinese numerals as used in novel chapter titles
/// (e.g. `195` → `一百九十五`).
class ChineseNumerals {
  ChineseNumerals._();

  static const _digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

  /// Format a positive integer in common Chinese chapter-number style.
  static String format(int n) {
    if (n <= 0) return '$n';
    if (n < 100) return _below100(n);
    if (n < 1000) return _below1000(n);
    if (n < 10000) return _below10000(n);
    return '$n';
  }

  static String _below100(int n) {
    if (n < 10) return _digits[n];
    if (n == 10) return '十';
    if (n < 20) return '十${_digits[n % 10]}';
    final tens = n ~/ 10;
    final ones = n % 10;
    return '${_digits[tens]}十${ones == 0 ? '' : _digits[ones]}';
  }

  static String _below1000(int n) {
    final hundreds = n ~/ 100;
    final rest = n % 100;
    final head = '${_digits[hundreds]}百';
    if (rest == 0) return head;
    if (rest < 10) return '$head零${_digits[rest]}';
    // 110–119 → 一百一十 / 一百一十一… (need explicit 一 before 十)
    if (rest < 20) {
      return rest == 10 ? '$head一十' : '$head一十${_digits[rest % 10]}';
    }
    return '$head${_below100(rest)}';
  }

  static String _below10000(int n) {
    final thousands = n ~/ 1000;
    final rest = n % 1000;
    final head = '${_digits[thousands]}千';
    if (rest == 0) return head;
    if (rest < 100) return '$head零${_below100(rest)}';
    return '$head${_below1000(rest)}';
  }
}
