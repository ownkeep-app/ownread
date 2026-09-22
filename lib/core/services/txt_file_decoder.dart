import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';

/// Decodes TXT novel bytes with UTF-8 first, then common Chinese encodings.
///
/// Many Windows / phone TXT novels are GBK / GB18030. Some files also mix
/// encodings (UTF-8 body + GBK ad splices). Those are decoded **line by line**.
class TxtFileDecoder {
  const TxtFileDecoder._();

  static Future<String> readFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return decodeBytes(bytes);
  }

  static String decodeBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';

    var data = bytes;

    // UTF-8 BOM — do not assume the rest is valid UTF-8 (mixed files exist).
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      data = data.sublist(3);
      try {
        return utf8.decode(data);
      } on FormatException {
        return _decodeMixedByLines(data);
      }
    }

    if (hasUtf16Bom(bytes)) {
      try {
        return utf16.decode(bytes);
      } on FormatException {
        // Fall through.
      }
    }

    try {
      return utf8.decode(data);
    } on FormatException {
      // Common for Chinese novels saved as GBK / GB2312 / GB18030.
    }

    try {
      return gbk.decode(data);
    } on FormatException {
      // Fall through.
    }

    return _decodeMixedByLines(data);
  }

  /// Decode each line as UTF-8 or GBK. Handles UTF-8 novels with GBK ad blocks.
  static String _decodeMixedByLines(List<int> bytes) {
    final out = StringBuffer();
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 0x0A) continue;
      out.write(_decodeLine(bytes.sublist(start, i + 1)));
      start = i + 1;
    }
    if (start < bytes.length) {
      out.write(_decodeLine(bytes.sublist(start)));
    }
    return out.toString();
  }

  static String _decodeLine(List<int> line) {
    if (line.isEmpty) return '';
    try {
      return utf8.decode(line);
    } on FormatException {
      // try GBK
    }
    try {
      return gbk.decode(line);
    } on FormatException {
      // try lossy
    }

    final utf8Lossy = utf8.decode(line, allowMalformed: true);
    final gbkLossy = gbk.decode(line, allowMalformed: true);
    return _replacementCount(utf8Lossy) <= _replacementCount(gbkLossy)
        ? utf8Lossy
        : gbkLossy;
  }

  static int _replacementCount(String s) {
    var n = 0;
    for (final c in s.codeUnits) {
      if (c == 0xFFFD) n++;
    }
    return n;
  }
}
