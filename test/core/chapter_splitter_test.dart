import 'package:flutter_test/flutter_test.dart';
import 'package:ownread/core/models/edit_history_entry.dart';
import 'package:ownread/core/services/chapter_splitter.dart';

void main() {
  group('ChapterSplitter', () {
    test('single chapter when no headings', () {
      final parts = ChapterSplitter.splitParts('hello\nworld');
      expect(parts.length, 1);
      expect(parts.first.title, '全文');
      expect(parts.first.content, 'hello\nworld');
    });

    test('splits Chinese chapter headings', () {
      const text = '序言内容\n\n第一章 开始\n正文一\n\n第二章 继续\n正文二\n';
      final parts = ChapterSplitter.splitParts(text);
      expect(parts.length, greaterThanOrEqualTo(2));
      expect(parts.any((c) => c.title.contains('第一章')), isTrue);
      expect(parts.any((c) => c.title.contains('第二章')), isTrue);
    });

    test('parts concatenate back to original', () {
      const text = '前言\n第一章 甲\n内容甲\n第二章 乙\n内容乙';
      final parts = ChapterSplitter.splitParts(text);
      expect(parts.map((p) => p.content).join(), text);
      final index = ChapterSplitter.indexFromParts(parts);
      expect(index.chapters.first.file, '0000.txt');
      expect(index.totalChars, text.length);
    });

    test('English Chapter headings', () {
      const text = 'Chapter 1 Hello\nbody\nChapter 2 World\nmore';
      final parts = ChapterSplitter.splitParts(text);
      expect(parts.length, 2);
    });

    test('anthology 1-space story titles', () {
      const text = '序\n'
          ' 吃了伟哥后\n'
          '    这是第一篇的正文内容，足够长才会被当成正文行。\n'
          '    /\n'
          '   ，\n'
          ' 体检艳遇\n'
          '    这是第二篇的正文内容，同样需要足够长一点才行。\n'
          '    第一章正规标题\n'
          '    正规章节正文继续往下写好多字才能过检测。\n';
      final parts = ChapterSplitter.splitParts(text);
      expect(parts.map((p) => p.title), containsAll(['吃了伟哥后', '体检艳遇']));
      expect(parts.any((p) => p.title.contains('第一章')), isTrue);
      expect(parts.length, greaterThanOrEqualTo(3));
    });

    test('prefixed 第N节 heading', () {
      const text = '前文\n    黄蓉后传第四节跟踪\n    正文内容从这里开始继续书写足够长度。\n';
      final parts = ChapterSplitter.splitParts(text);
      expect(parts.any((p) => p.title.contains('第四节')), isTrue);
    });

    test('numbered titles without 第N章', () {
      const text = '红尘都市\n'
          '一  运动型美女\n'
          '　　当第一缕阳光照射在周梦龙的身上时，周梦龙条件反射一样的睁开了眼睛。\n'
          '二  美女的期待\n'
          '　　张梦儿睁大了一双水汪汪的大眼睛，看着周梦龙，眼中波光流动。\n'
          '一百零四  美妇可儿  一\n'
          '　　这是第一百零四章的正文，继续往下写保证长度足够通过检测。\n';
      final parts = ChapterSplitter.splitParts(text);
      expect(parts.length, greaterThanOrEqualTo(3));
      expect(parts.map((p) => p.title), contains('一  运动型美女'));
      expect(parts.map((p) => p.title), contains('二  美女的期待'));
      expect(parts.any((p) => p.title.contains('一百零四')), isTrue);
    });
  });

  group('EditHistoryEntry summaries', () {
    test('replace_all summary format', () {
      final s = EditHistoryEntry.summaryReplaceAll(
        find: '18岁',
        replace: '14岁',
        changedChars: 400,
      );
      expect(s, "全文替换：'18岁' -> '14岁'；共计修改文本400字");
    });

    test('chapter_edit summary format', () {
      final s = EditHistoryEntry.summaryChapterEdit(
        chapterNumber1Based: 20,
        sampleFrom: '草',
        sampleTo: '曹',
        changedChars: 2,
      );
      expect(s, "第20章修改文本：'草' -> '曹'；共计修改文本2字");
    });
  });
}
