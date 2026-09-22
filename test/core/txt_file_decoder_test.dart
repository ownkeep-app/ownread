import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/services/txt_file_decoder.dart';

void main() {
  group('TxtFileDecoder.decodeBytes', () {
    test('utf-8 plain', () {
      final bytes = utf8.encode('第一章 开端\n正文');
      expect(TxtFileDecoder.decodeBytes(bytes), '第一章 开端\n正文');
    });

    test('utf-8 with BOM', () {
      final text = utf8.encode('你好');
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...text];
      expect(TxtFileDecoder.decodeBytes(bytes), '你好');
    });

    test('gbk chinese novel bytes', () {
      final bytes = gbk.encode('第一章 开端\n这是GBK编码的小说');
      expect(
        TxtFileDecoder.decodeBytes(bytes),
        '第一章 开端\n这是GBK编码的小说',
      );
    });

    test('utf-8 BOM then gbk splice (mixed file)', () {
      final head = utf8.encode('清新脱俗。\n\n');
      final mid = gbk.encode('外围同城高档会所');
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...head, ...mid];
      final text = TxtFileDecoder.decodeBytes(bytes);
      expect(text, contains('清新脱俗'));
      expect(text, contains('外围同城'));
    });

    test('empty', () {
      expect(TxtFileDecoder.decodeBytes(const []), '');
    });
  });

  group('TxtFileDecoder.readFile', () {
    test('reads gbk file from disk', () async {
      final dir = await Directory.systemTemp.createTemp('ownread_txt_');
      final file = File('${dir.path}/novel.txt');
      await file.writeAsBytes(gbk.encode('第2章 测试'));
      try {
        expect(await TxtFileDecoder.readFile(file.path), '第2章 测试');
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('reads mixed real-world style file', () async {
      final dir = await Directory.systemTemp.createTemp('ownread_txt_');
      final file = File('${dir.path}/mixed.txt');
      final head = utf8.encode('发布自禁忌书屋\n第一章 开头\n');
      final junk = gbk.encode('广告 k806.cc\n');
      final tail = utf8.encode('第二章 继续\n');
      await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...head, ...junk, ...tail]);
      try {
        final text = await TxtFileDecoder.readFile(file.path);
        expect(text, contains('禁忌书屋'));
        expect(text, contains('第二章'));
        expect(text, contains('广告'));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
